# Debian 13 Web Terminal (Browser Shell): Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **Debian 13 Web Terminal (Browser Shell)** (round-4 listing, unchanged; "13" is the pinned Debian major) |
| Description | Persistent Debian shell in your browser, password-protected. No SSH needed. (75 chars, at the limit, unchanged) |
| Category | Other |
| Tags | debian, terminal, web-terminal, ttyd, tmux, shell, linux, devbox |
| Icon | `https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/debian-linux.svg` (200, image/svg+xml) |

The template delivers the description as written. "Persistent": `/home` is a volume, and tmux keeps sessions alive across browser reconnects. "Password-protected": nginx basic auth with a `secret(32)` password, and the service refuses to start without one. "No SSH needed": the shell is served over Railway's HTTPS domain.

## Base market template

- **Base: `debian-linux` "Debian-Linux"** (XenaaLangliss/debian-railway, 2,479 active / 868 deploys in 30 days, market leader). Kept the concept people pick it for: a Debian shell behind ttyd with a login prompt, and the `USERNAME` / `PASSWORD` variable names its users know. Problems fixed: Debian 12 (oldstable since Aug 2025); ttyd 1.7.3 downloaded without a checksum; a root shell; **no volume** (all files lost on redeploy); no healthcheck; user-typed credentials passed to `ttyd -c` on the command line, which ttyd prints (base64) into the deploy log at startup; no tmux, so closing the tab kills running jobs; `neofetch`, which no longer exists in Debian 13.
- `debian` "Debian Linux, Open Source Web Terminal" (kayrakryo, 1,295 active): adds tini, multi-arch ttyd 1.7.7 and a `/data` volume. Home (`/root`), dotfiles and history are still lost on redeploy, and it has the same root shell, `-c` log leak and missing healthcheck. Its "persistent storage" only covers files placed in `/data` by hand.
- `debian-desktop-web-gui` (XFCE desktop, 300 active) is a different product, a GUI desktop at about 800 MB RAM idle. Idea reused: an unauthenticated health location in front of basic auth.
- Both repos have **no license**. They were read for ideas only; no file or text was copied. ttyd itself is MIT.

## Pinned versions

| Component | Source | Version | Released | Checked |
|---|---|---|---|---|
| Base image | `debian:13.7` (Docker Official Image, same digest as `13`: `sha256:913f6706df59a68922d1dd08f78c2476560a8d367897200a6005b00e5f67c2d5`; amd64 `sha256:bcf83fd8…`) | 13.7 | 2026-10-06 | 2026-10-20 |
| ttyd | GitHub release binary, SHA-256 verified at build | 1.7.7 (latest release) | 2024-03-30 | 2026-10-20 |
| Node.js | nodejs.org tarball, SHA-256 verified at build | 24.22.0 LTS "Krypton" | 2026-10-14 | 2026-10-20 |
| nginx | Debian trixie package | 1.26.3-3+deb13u7/u9 | trixie + security | 2026-10-20 |
| tmux | Debian trixie package | 3.5a-3 | trixie | 2026-10-20 |
| Python | Debian trixie package | 3.13.5 | trixie | 2026-10-20 |

ARGs at the top of `services/terminal/Dockerfile` hold the versions and checksums. Debian packages follow the trixie point releases, and every fresh build runs `apt-get upgrade`. Railway can reuse cached layers, so bumping `debian:13.x` is the reliable way to force a rebuild that picks up new security fixes. ttyd is not packaged in trixie (only forky/sid), so the static release binary is used. It has no runtime dependencies.

## Architecture

```
 Browser ── HTTPS (Railway edge) ──► :8080 nginx  (PORT, 0.0.0.0 + [::])
                                       │  /healthz  no auth ─► ttyd /token (200 {"token": ""})
                                       │  /         basic auth (SHA-512 crypt), rate limit,
                                       │            Origin check, WebSocket upgrade
                                       ▼
                               127.0.0.1:7681 ttyd 1.7.7 (auth-header mode, user "debian")
                                       │  one process per tab
                                       ▼
                               terminal-session ─► tmux new-session -A -s main|?arg=NAME
                                                   └─ bash --login (sudo NOPASSWD)
 ┌──────────────────────────────────────────────────────────────────────────┐
 │ Terminal service (Dockerfile in services/terminal)                       │
 │ podman-init (PID 1, Railway) → tini -s → entrypoint (root)                │
 │   ├─ nginx master (root) + 1 worker (www-data)                           │
 │   ├─ ttyd (debian)                                                       │
 │   └─ apt restore job (optional, background)                              │
 │ volume /home  (/home/debian = $HOME)                                     │
 └──────────────────────────────────────────────────────────────────────────┘
```

## Services

### Terminal

| Setting | Value |
|---|---|
| Source | repo `baranberkay96/debian-terminal-railway`, root `/services/terminal` (Dockerfile) |
| Healthcheck | `/healthz` on `PORT=8080`, timeout 120 s |
| Public domain | yes, target port 8080 |
| TCP proxy | none (SSH is out of scope; the Ubuntu dev box template covers it) |
| Volume | `/home` (the home of `debian` is `/home/debian`) |
| Restart policy | ON_FAILURE, 10 retries |
| Replicas | 1 (volume-backed, single user) |

Files in `services/terminal/`:
- `Dockerfile`: `debian:13.7`, the apt toolset, ttyd and Node.js with checksums, user `debian` (uid 1000) with passwordless sudo, and a skel `.bashrc` hook.
- `entrypoint.sh`: validates the variables and fails closed without a password. It seeds `/home/debian` on first boot, writes the htpasswd file (SHA-512 crypt via `openssl passwd -6 -stdin`, root:www-data 0640), renders the nginx config (adds the IPv6 listener only if the container has IPv6) and checks it with `nginx -t`. Then it unsets `PASSWORD`, starts the optional apt restore in the background, starts ttyd as `debian` through `setpriv`, waits for it, and starts nginx. It supervises both: if either exits, the container exits. On SIGTERM it runs `tmux kill-server` (shells save history) and stops both processes.
- `terminal-session.sh`: run by ttyd for each tab. Attaches to tmux session `main`, or to the session named by `?arg=NAME` (validated `[A-Za-z0-9_-]{1,32}`). Falls back to `bash --login` when `TERMINAL_TMUX=false`.
- `nginx.conf.template`: auth proxy (see below).
- `bashrc.sh` → `/etc/debian-terminal/bashrc`: PATH (`~/.npm-global/bin`, `~/.local/bin`, `~/bin`), `NPM_CONFIG_PREFIX=~/.npm-global`, 50k history appended after every command, git-aware prompt, aliases (`ll`, `fd`), and a banner (motd + fastfetch) once per tmux session. Sourced from the last line of `~/.bashrc`, so image updates refresh the defaults without touching user files.
- `tmux.conf` → `/etc/tmux.conf`: true colour, mouse, 50k scrollback, windows from 1, browser tab title, status bar with key hints. `~/.tmux.conf` overrides it.
- `motd.txt` → `/etc/debian-terminal/motd`: what persists, tmux keys, apt, the fair-use reminder.

### Variables

| Variable | Default | Notes |
|---|---|---|
| `PASSWORD` | `${{secret(32)}}` | Browser login. At least 12 characters, otherwise the service exits with a clear log message. Only its hash is stored; it is unset before ttyd, nginx and the shells start. |
| `USERNAME` | `debian` | Browser login name, `[A-Za-z0-9._-]{1,64}`. The Linux account is always `debian`. |
| `PORT` | `8080` | nginx listen port. Rule 8.1: Railway's healthcheck probes this port. 7681 is reserved for ttyd. |
| `TERMINAL_TMUX` | `true` | `false` gives one plain login shell per tab (no persistence across reconnects). |
| `TERMINAL_FONT_SIZE` | `15` | Passed to ttyd as `-t fontSize=…` (8-40). |
| `APT_PACKAGES` | empty | Optional extra packages to reinstall at start, merged with `~/.config/debian-terminal/apt-packages`. |
| `TZ` | `UTC` | Shell time zone (tzdata installed). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `15` | Grace period for the clean tmux shutdown. |

No required inputs. The template boots with the generated password.

## Healthcheck and auth design

Why a proxy, and why `/healthz` in it: ttyd's HTTP handler (`src/http.c`, tag 1.7.7) runs the basic-auth check **before** it looks at the path. With `ttyd -c user:pass`, every path, including `/`, `/token`, `/ws` and unknown paths, answers 401, so no ttyd path can serve an unauthenticated 2xx for Railway. A proxy in front was needed anyway for two other reasons:

1. **Log leak**: in `-c` mode ttyd 1.7.7 logs `credential: <base64 user:pass>` at startup (`print_config` in `src/server.c`). Both market templates therefore write their password to Railway's deploy logs, and also expose it on the ttyd command line (`ps`).
2. **Cross-site WebSocket hijacking**: browsers attach cached basic-auth credentials to WebSocket requests from other sites. The proxy rejects any request whose `Origin` host differs from `Host`. Ports are ignored, which avoids false rejections that ttyd's own `--check-origin` would cause if the edge adds `:443`. A missing `Origin`, as sent by CLI clients, is allowed after the password check.

Design: nginx (Debian package, already in the image's security update stream) listens on `PORT`, checks `USERNAME`/`PASSWORD` against a SHA-512 crypt hash, rate-limits to 10 req/s with a burst of 40 per client (keyed on `X-Real-IP` from Railway's edge), sets `X-WebAuth-User`, and strips the `Authorization` header. ttyd runs in **auth-header mode** (`-H X-WebAuth-User`) on `127.0.0.1:7681` (`-i lo`), so it is unreachable from outside the container, and nginx always overwrites the header. Headers: `X-Frame-Options: SAMEORIGIN`, `frame-ancestors 'self'`, `nosniff`, `no-referrer`, `server_tokens off`.

`/healthz` is the only unauthenticated path. nginx proxies it to ttyd's `/token` with an injected auth header. In auth-header mode ttyd answers `200 {"token": ""}`, which contains no secret, so the healthcheck only passes when nginx **and** ttyd are both up. Only GET/HEAD are allowed, and it cannot reach `/ws`: there is no Upgrade forwarding, and the proxied path is fixed.

PID 1 (Rule 8.3): nothing depends on being PID 1. tini runs with `-s` (child subreaper) under Railway's podman-init and reaps the double-forked tmux server. The entrypoint supervises nginx and ttyd itself with `wait -n`.

## First login

1. Open the public URL. The browser shows a login prompt.
2. User `debian` (or your `USERNAME`), password = `PASSWORD` from the Variables tab.
3. You are in tmux session `main` as `debian`. Close the tab and reopen the URL to resume. `?arg=work` opens a second session.
4. `sudo apt update && sudo apt install {package}`. To have a package reinstalled after redeploys, add its name to `~/.config/debian-terminal/apt-packages` (one or more per line, `#` comments) or to `APT_PACKAGES`.

## Improvements over market templates

1. **Never an open shell**: generated `secret(32)` password, and the service fails closed if `PASSWORD` is empty or shorter than 12 characters. Market: user-typed credentials with no strength check. ttyd even accepts an empty `:` pair.
2. **No secret in logs, `ps` or the shell environment**: nginx holds a SHA-512 crypt hash, and ttyd runs in auth-header mode. Market: `ttyd -c` logs the base64 credential at startup and shows it in the process list.
3. **Persistent home**: the whole `/home` is on a volume, including dotfiles, history, venvs, pipx and `npm -g` (`~/.npm-global`). Market: no volume (leader), or only a manual `/data` directory with `/root` lost.
4. **Sessions survive reconnects**: every tab attaches to tmux (`main`, or a named session via `?arg=`). Market: a new bash per connection, and closing the tab kills running jobs.
5. **Non-root user with sudo** instead of a root shell. uid 1000 keeps volume ownership stable.
6. **Current, verified versions**: Debian 13.7 instead of Debian 12, ttyd 1.7.7 checked against `SHA256SUMS` (the leader runs 1.7.3 with no check), Node.js 24 LTS checked against `SHASUMS256.txt`, and `apt-get upgrade` at build.
7. **Healthcheck** `/healthz` with `PORT` set, testing nginx and ttyd end to end. Market: none.
8. **Browser hardening**: cross-site WebSocket check, anti-framing headers, rate-limited login, ttyd bound to loopback.
9. **A useful toolset**: build-essential, python3 (+ venv, pip, pipx, dev headers), Node.js/npm, git + git-lfs, tmux, htop, vim, nano, ripgrep, fd, jq, sqlite3, rsync, dnsutils, man pages, bash-completion, fastfetch (replaces neofetch, which trixie dropped). Market: wget, curl, git, python3, pip, neofetch.
10. **apt persistence helper**: `APT_PACKAGES` / `~/.config/debian-terminal/apt-packages` reinstall in the background after every redeploy, without blocking boot or the healthcheck.
11. **Clean shutdown**: SIGTERM → `tmux kill-server` (bash writes history) → ttyd and nginx stopped. `RAILWAY_DEPLOYMENT_DRAINING_SECONDS=15`.
12. IPv4 + IPv6 listeners (IPv6 only when available), restart policy, and descriptions on every variable.

## Resource estimate

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Estimates, not measured.

| Service | Idle RAM / CPU | Typical RAM / CPU | Notes |
|---|---|---|---|
| Terminal | 0.04-0.06 GB / ~0.002 vCPU (nginx ~6 MB, ttyd ~5 MB, tmux + bash ~10 MB) | 0.3 GB avg, 1 GB+ peaks / 0.05 vCPU avg | Peaks come from what users run: `npm install`, `make -j`, Python jobs |
| Volume `/home` | 0.1 GB | 2-5 GB | Projects, venvs, node_modules |

Estimated monthly cost: **idle ≈ $0.60** (0.05 GB × $10 + 0.002 vCPU × $20 + 0.1 GB × $0.15), **typical ≈ $4.50** (0.3 GB × $10 + 0.05 vCPU × $20 + 3 GB × $0.15). A heavy dev user lands around $15 (1 GB, 0.25 vCPU, 5 GB).

Minimum plan: **Trial** runs it (well under 1 GB idle), but large builds can hit the 1 GB limit. **Hobby** is the realistic plan for a 24/7 shell. Its 5 GB volume cap per service bounds `/home`; Pro allows larger volumes. Do not enable Railway's serverless sleep if you rely on tmux: a sleeping service stops its processes.

## Verification checklist

- [ ] Build completes for linux/amd64. The log shows `ttyd version 1.7.7…`, `v24.22.0`, an npm version, and `sha256sum: OK` lines for ttyd and Node.
- [ ] Deploy log: `Ready on port 8080 …`. The log must not contain the password or any `credential:` line.
- [ ] `curl -i https://{domain}/healthz` → `200` with `{"token": ""}`. `curl -i https://{domain}/` → `401` with `WWW-Authenticate: Basic`. A wrong password → `401`. More than ~50 quick requests → `429`.
- [ ] The browser login with `debian` / `PASSWORD` opens tmux session `main`, the banner shows, and `whoami` = `debian`. `sudo -n true` works. `echo "${PASSWORD:-unset}"` prints `unset`.
- [ ] Start `top` in the tab, close the tab, reopen the URL: `top` is still running. `?arg=work` opens a separate session.
- [ ] Cross-site check: `curl -i -u debian:PASS -H 'Origin: https://evil.example' https://{domain}/` → `403`. The same request with `Origin: https://{domain}` → `200`.
- [ ] Tools: `git --version`, `python3 -V` (3.13), `node -v` (v24.22.0), `npm i -g cowsay && which cowsay` (in `~/.npm-global/bin`), `gcc --version`, `tmux -V` (3.5a), `fastfetch`.
- [ ] Persistence: create `~/test.txt`, add `jq` to `~/.config/debian-terminal/apt-packages` after `sudo apt remove jq`, then redeploy. `~/test.txt` and history survive, and `/var/log/debian-terminal/apt-restore.log` shows jq reinstalled.
- [ ] Set `PASSWORD` to empty and redeploy: the deploy fails with the "PASSWORD is empty or shorter than 12 characters" log line, and no shell is served.

## Open questions

- Not built or run locally (Docker was off-limits this round). Checks were static only (see the round-4 report). The first Railway build is the first build of this Dockerfile.
- `sudo` needs setuid to work in Railway's container runtime. Expected, but untested for this template.
- Railway's edge passes `Host` unchanged and sets `X-Real-IP` (assumed from other templates: code-server's origin check worked behind Railway in template 22). If `Host` differed from the browser's `Origin`, WebSocket connections would get 403.
- ttyd `-i lo` was checked in the libwebsockets 4.3.3 source that the 1.7.7 release binary is built with: it binds lo's IPv4 address, 127.0.0.1. The `fastfetch --logo-type small --structure …` flags were checked in fastfetch 2.40.4's `help.json`. Neither was executed. A wrong fastfetch flag would only hide the system-info block (stderr is silenced).
- The predicted marketplace code `debian-13-web-terminal-browser-shell` (Deploy button in README) follows the pattern of earlier publishes. Confirm it after publishing.
- Railway Trial/Hobby volume size limits are taken from STANDARD.md and may change.
