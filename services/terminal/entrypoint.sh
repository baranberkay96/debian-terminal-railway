#!/usr/bin/env bash
# Debian Web Terminal entrypoint. It runs as root under tini.
#
# 1. Checks PORT, USERNAME and PASSWORD. Without a password of at least 12
#    characters it refuses to start: this template never serves an open shell.
# 2. Creates /home/debian on the Railway volume on first boot.
# 3. Writes the nginx config: basic auth on $PORT, an unauthenticated /healthz,
#    and a WebSocket proxy to ttyd. ttyd listens on loopback only.
# 4. Starts ttyd as user "debian" and nginx, then supervises both. If either
#    one exits, the container exits so Railway restarts it.
set -Eeuo pipefail

readonly LINUX_USER="debian"
readonly HOME_DIR="/home/${LINUX_USER}"
readonly TTYD_PORT="7681"
readonly AUTH_HEADER="X-WebAuth-User"
readonly CONFIG_DIR="/etc/debian-terminal"
readonly HTPASSWD_FILE="/etc/nginx/terminal.htpasswd"
readonly STATE_DIR="/var/log/debian-terminal"
readonly APT_LIST_FILE="${HOME_DIR}/.config/debian-terminal/apt-packages"
readonly MIN_PASSWORD_LENGTH=12

TTYD_PID=""
NGINX_PID=""

log() { printf '[debian-terminal] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

is_true() {
  case "${1,,}" in
    1 | true | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

as_user() {
  setpriv --reuid="$LINUX_USER" --regid="$LINUX_USER" --init-groups -- "$@"
}

validate_settings() {
  PORT="${PORT:-8080}"
  if [[ ! "$PORT" =~ ^[1-9][0-9]{0,4}$ ]] || (( PORT > 65535 )); then
    die "PORT must be a number between 1 and 65535 (got '${PORT}')."
  fi
  if (( PORT == TTYD_PORT )); then
    die "PORT ${TTYD_PORT} is reserved for the internal ttyd listener. Use another port."
  fi

  USERNAME="${USERNAME:-debian}"
  if [[ ! "$USERNAME" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
    die "USERNAME may only contain letters, digits, '.', '_' and '-' (1-64 characters)."
  fi

  PASSWORD="${PASSWORD:-}"
  if (( ${#PASSWORD} < MIN_PASSWORD_LENGTH )); then
    die "PASSWORD is empty or shorter than ${MIN_PASSWORD_LENGTH} characters. Set it in the service Variables. The terminal does not start without a password."
  fi
  if [[ "$PASSWORD" == *$'\n'* ]]; then
    die "PASSWORD must be a single line."
  fi

  TERMINAL_FONT_SIZE="${TERMINAL_FONT_SIZE:-15}"
  if [[ ! "$TERMINAL_FONT_SIZE" =~ ^[1-9][0-9]?$ ]] || (( TERMINAL_FONT_SIZE < 8 || TERMINAL_FONT_SIZE > 40 )); then
    die "TERMINAL_FONT_SIZE must be a number between 8 and 40 (got '${TERMINAL_FONT_SIZE}')."
  fi

  if is_true "${TERMINAL_TMUX:-true}"; then
    export TERMINAL_TMUX="true"
  else
    export TERMINAL_TMUX="false"
  fi
}

prepare_home() {
  if ! mountpoint -q /home; then
    log "WARNING: /home is not a mounted volume. Files will be lost on every redeploy."
  fi

  if [[ ! -d "$HOME_DIR" ]]; then
    log "First boot: creating ${HOME_DIR}."
    install -d -m 0750 -o "$LINUX_USER" -g "$LINUX_USER" "$HOME_DIR"
    cp -a /etc/skel/. "${HOME_DIR}/"
    chown -R "${LINUX_USER}:${LINUX_USER}" "$HOME_DIR"
  fi

  # Fix ownership of the top level only. A recursive chown of a large home
  # would slow every boot.
  if [[ "$(stat -c %u "$HOME_DIR")" != "$(id -u "$LINUX_USER")" ]]; then
    log "Repairing ownership of ${HOME_DIR}."
    chown "${LINUX_USER}:${LINUX_USER}" "$HOME_DIR"
  fi
}

write_proxy_config() {
  local hash listen_v6=""

  hash="$(printf '%s\n' "$PASSWORD" | openssl passwd -6 -stdin)" || die "Could not hash PASSWORD."
  [[ "$hash" == '$6$'* ]] || die "openssl returned an unexpected password hash format."
  (
    umask 0027
    printf '%s:%s\n' "$USERNAME" "$hash" > "$HTPASSWD_FILE"
  )
  chown root:www-data "$HTPASSWD_FILE"
  chmod 0640 "$HTPASSWD_FILE"

  # Same check as the official nginx image: listen on [::] only when the
  # container has IPv6.
  if [[ -s /proc/net/if_inet6 ]]; then
    listen_v6="listen [::]:${PORT} default_server;"
  else
    log "IPv6 is not available in this container. nginx listens on IPv4 only."
  fi

  sed -e "s|@PORT@|${PORT}|g" \
      -e "s|@TTYD_PORT@|${TTYD_PORT}|g" \
      -e "s|@AUTH_HEADER@|${AUTH_HEADER}|g" \
      -e "s|@HTPASSWD_FILE@|${HTPASSWD_FILE}|g" \
      -e "s|@LISTEN_V6@|${listen_v6}|g" \
      "${CONFIG_DIR}/nginx.conf.template" > /etc/nginx/nginx.conf
  nginx -t -q || die "nginx rejected the generated configuration."
}

# Prints the requested apt packages, one per line, from APT_PACKAGES and from
# ~/.config/debian-terminal/apt-packages ('#' starts a comment). Invalid names
# are skipped. The user already has sudo, so this file grants no extra rights.
collect_apt_packages() {
  local -a words=() parts=()
  local -A seen=()
  local line word

  if [[ -n "${APT_PACKAGES:-}" ]]; then
    read -r -a words <<< "${APT_PACKAGES//,/ }"
  fi
  # Symlinks are ignored so the list cannot point at another file.
  if [[ -f "$APT_LIST_FILE" && ! -L "$APT_LIST_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      read -r -a parts <<< "$line"
      words+=("${parts[@]}")
    done < "$APT_LIST_FILE"
  fi

  for word in "${words[@]}"; do
    if [[ ! "$word" =~ ^[a-z0-9][a-z0-9+.-]+(=[A-Za-z0-9.+:~-]+)?$ ]]; then
      log "Skipping invalid apt package name: '${word:0:64}'"
      continue
    fi
    if [[ -z "${seen[$word]:-}" ]]; then
      seen[$word]=1
      printf '%s\n' "$word"
    fi
  done
}

# apt installs live outside the volume and vanish on redeploy. This puts the
# requested packages back in the background, so a slow mirror never delays the
# terminal or its healthcheck.
restore_apt_packages() {
  local -a pkgs=()
  local logfile="${STATE_DIR}/apt-restore.log"

  mapfile -t pkgs < <(collect_apt_packages)
  (( ${#pkgs[@]} > 0 )) || return 0

  log "Reinstalling ${#pkgs[@]} apt package(s) in the background: ${pkgs[*]} (log: ${logfile})"
  (
    if {
      DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 update &&
        DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 \
          install -y --no-install-recommends "${pkgs[@]}"
    } > "$logfile" 2>&1; then
      log "apt packages restored."
    else
      log "WARNING: restoring apt packages failed. See ${logfile}."
    fi
  ) &
}

start_ttyd() {
  # ttyd runs in auth-header mode: nginx does the password check and passes
  # the user name in AUTH_HEADER. With -c, ttyd 1.7.7 would print the
  # credential (base64) to the deploy logs. nginx also does the WebSocket
  # Origin check. ttyd's --check-origin compares Host and Origin including the
  # port, which breaks if the edge adds ":443" to Host.
  # -W: writable terminal. -a: ?arg=NAME selects the tmux session.
  local -a ttyd_args=(
    -i lo -p "$TTYD_PORT"
    -H "$AUTH_HEADER"
    -W -a
    -w "$HOME_DIR"
    -d 3
    -t "fontSize=${TERMINAL_FONT_SIZE}"
    /usr/local/bin/terminal-session
  )

  env -u PASSWORD -u USERNAME \
    HOME="$HOME_DIR" USER="$LINUX_USER" LOGNAME="$LINUX_USER" SHELL=/bin/bash \
    setpriv --reuid="$LINUX_USER" --regid="$LINUX_USER" --init-groups -- \
    /usr/local/bin/ttyd "${ttyd_args[@]}" &
  TTYD_PID=$!
}

wait_for_ttyd() {
  local attempt
  for attempt in $(seq 1 50); do
    if curl -fsS -o /dev/null -H "${AUTH_HEADER}: entrypoint" \
      "http://127.0.0.1:${TTYD_PORT}/token" 2>/dev/null; then
      return 0
    fi
    kill -0 "$TTYD_PID" 2>/dev/null || die "ttyd exited during startup."
    sleep 0.2
  done
  log "WARNING: ttyd did not answer within 10 seconds. Starting nginx anyway."
}

start_nginx() {
  nginx &
  NGINX_PID=$!
}

stop_all() {
  # Hang up the tmux server first so shells exit cleanly and save their history.
  as_user env HOME="$HOME_DIR" tmux kill-server > /dev/null 2>&1 || true
  [[ -n "$TTYD_PID" ]] && kill -TERM "$TTYD_PID" 2> /dev/null || true
  [[ -n "$NGINX_PID" ]] && kill -TERM "$NGINX_PID" 2> /dev/null || true
  wait "$TTYD_PID" "$NGINX_PID" 2> /dev/null || true
}

on_signal() {
  trap - TERM INT
  log "Received $1. Stopping tmux sessions, ttyd and nginx."
  stop_all
  exit 0
}

supervise() {
  local status=0
  trap 'on_signal TERM' TERM
  trap 'on_signal INT' INT
  wait -n "$TTYD_PID" "$NGINX_PID" || status=$?
  log "ttyd or nginx exited (status ${status}). Stopping the container so Railway restarts it."
  trap - TERM INT
  stop_all
  exit 1
}

main() {
  validate_settings
  install -d -m 0755 "$STATE_DIR"
  prepare_home
  write_proxy_config
  # Only the hash is kept. Neither ttyd, nginx nor the shells see the password.
  unset PASSWORD
  restore_apt_packages
  start_ttyd
  wait_for_ttyd
  start_nginx
  log "Ready on port ${PORT}: browser login '${USERNAME}', Linux user '${LINUX_USER}', tmux sessions ${TERMINAL_TMUX}."
  supervise
}

main "$@"
