# Debian 13 Web Terminal for Railway.
#
# Debian 13 (trixie) with ttyd serving tmux sessions, behind an nginx basic-auth
# proxy. The shell runs as the non-root user "debian" (passwordless sudo), and
# /home is a Railway volume. Every version is pinned below: change an ARG and
# redeploy to upgrade.
FROM debian:13.7

# ttyd release binaries (MIT, https://github.com/tsl0922/ttyd/releases/tag/1.7.7).
# The checksums come from the release's SHA256SUMS file.
ARG TTYD_VERSION=1.7.7
ARG TTYD_SHA256_AMD64=8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55
ARG TTYD_SHA256_ARM64=b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165

# Node.js 24 LTS "Krypton" official tarballs. The checksums come from
# https://nodejs.org/dist/v24.22.0/SHASUMS256.txt.
ARG NODE_VERSION=24.22.0
ARG NODE_SHA256_AMD64=cc2f601cee82d9a5a233302fe307abc600727035fd7d2c3a3571755989e95008
ARG NODE_SHA256_ARM64=fef00bb4d36e1c50104a9775a10359beee98f162b4104dd12472c75065c6a143

ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8 \
    TZ=UTC

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# System packages: the auth proxy (nginx), the init (tini), tmux and the tools
# people expect in a dev shell. `apt-get upgrade` picks up trixie security fixes
# that were released after the base image was built.
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
      bash-completion bind9-dnsutils build-essential bzip2 ca-certificates curl \
      fastfetch fd-find file git git-lfs gnupg htop iproute2 iputils-ping jq less \
      lsof man-db manpages nano ncdu ncurses-term netcat-openbsd nginx \
      openssh-client openssl pipx procps python3 python3-dev python3-pip \
      python3-venv ripgrep rsync sqlite3 sudo tini tmux tree tzdata unzip vim \
      wget xz-utils zip \
 && rm -f /etc/nginx/sites-enabled/default \
 && rm -rf /var/lib/apt/lists/*

# ttyd: a static release binary, checked against the published checksum.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) asset="ttyd.x86_64";  sum="${TTYD_SHA256_AMD64}" ;; \
      arm64) asset="ttyd.aarch64"; sum="${TTYD_SHA256_ARM64}" ;; \
      *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --retry 5 --retry-delay 2 -o /usr/local/bin/ttyd \
      "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/${asset}"; \
    echo "${sum}  /usr/local/bin/ttyd" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/ttyd; \
    ttyd --version

# Node.js LTS from nodejs.org. Debian 13 ships Node.js 20, which reached
# end-of-life upstream in April 2026.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) narch="x64";   sum="${NODE_SHA256_AMD64}" ;; \
      arm64) narch="arm64"; sum="${NODE_SHA256_ARM64}" ;; \
      *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    tarball="node-v${NODE_VERSION}-linux-${narch}.tar.xz"; \
    curl -fsSL --retry 5 --retry-delay 2 -o "/tmp/${tarball}" \
      "https://nodejs.org/dist/v${NODE_VERSION}/${tarball}"; \
    echo "${sum}  /tmp/${tarball}" | sha256sum -c -; \
    tar -xJf "/tmp/${tarball}" -C /usr/local --strip-components=1 --no-same-owner; \
    rm -f "/tmp/${tarball}" /usr/local/CHANGELOG.md /usr/local/README.md; \
    install -d /usr/local/share/doc/nodejs; \
    mv /usr/local/LICENSE /usr/local/share/doc/nodejs/LICENSE; \
    node --version; \
    npm --version

# The login user. It has a fixed uid 1000 so file ownership on the volume stays
# stable across image updates. New homes get Debian's default dotfiles plus one
# line that loads this template's shell defaults.
RUN set -eux; \
    printf '\n# Debian Web Terminal defaults (prompt, history, PATH). Delete these lines to opt out.\nif [ -r /etc/debian-terminal/bashrc ]; then . /etc/debian-terminal/bashrc; fi\n' \
      >> /etc/skel/.bashrc; \
    useradd --create-home --uid 1000 --user-group --groups sudo --shell /bin/bash debian; \
    printf 'debian ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/90-debian-terminal; \
    chmod 0440 /etc/sudoers.d/90-debian-terminal; \
    visudo -cf /etc/sudoers.d/90-debian-terminal

COPY entrypoint.sh /usr/local/bin/debian-terminal-entrypoint
COPY terminal-session.sh /usr/local/bin/terminal-session
COPY bashrc.sh /etc/debian-terminal/bashrc
COPY motd.txt /etc/debian-terminal/motd
COPY nginx.conf.template /etc/debian-terminal/nginx.conf.template
COPY tmux.conf /etc/tmux.conf
RUN chmod 0755 /usr/local/bin/debian-terminal-entrypoint /usr/local/bin/terminal-session \
 && chmod 0644 /etc/debian-terminal/bashrc /etc/debian-terminal/motd \
      /etc/debian-terminal/nginx.conf.template /etc/tmux.conf

EXPOSE 8080

# On Railway, podman-init is PID 1 and this runs under it. tini -s registers as
# a child subreaper, so orphaned processes (the tmux server, background jobs)
# are reaped whether or not tini is PID 1.
ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/usr/local/bin/debian-terminal-entrypoint"]
