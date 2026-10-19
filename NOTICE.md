# NOTICE: Debian 13 Web Terminal template

## Software installed in the image

| Component | Source | License | How it is used |
|---|---|---|---|
| Debian 13.7 "trixie" | `debian:13.7` (Docker Official Image), https://hub.docker.com/_/debian | Various free licenses (see `/usr/share/doc/*/copyright` in the image) | Base image (`FROM`) and apt packages |
| ttyd 1.7.7 | Release binary `ttyd.x86_64` / `ttyd.aarch64`, https://github.com/tsl0922/ttyd/releases/tag/1.7.7 (tag commit `40e79c7`) | MIT, Copyright (c) 2016-2022 Shuanglei Tao | Downloaded unmodified, checked against the release's `SHA256SUMS` |
| nginx 1.26 | Debian trixie package `nginx` | BSD-2-Clause | Basic-auth reverse proxy. The config was written for this template |
| tmux 3.5a | Debian trixie package `tmux` | ISC | Persistent sessions |
| tini 0.19.0 | Debian trixie package `tini` | MIT | Init and child subreaper |
| Node.js 24.22.0 LTS | Official tarball, https://nodejs.org/dist/v24.22.0/ | MIT (plus bundled third-party licenses, see `/usr/local/share/doc/nodejs/LICENSE`) | Unmodified, checked against `SHASUMS256.txt` |
| fastfetch, git, Python 3.13, build-essential, vim, nano, htop and the other CLI tools | Debian trixie packages | Each package's own license | Installed unmodified |

Product names belong to their owners. This is a community template, not affiliated with the Debian Project, the ttyd author or Railway. "Debian" is a registered trademark of Software in the Public Interest, Inc.

## Upstream files and data checked (2026-10-20)

- ttyd tag `1.7.7`: `src/server.c` (options `-i` interface/socket, `-H` auth header, `-O`, `-W`, `-a`, `-t`, and the startup log that prints the `-c` credential), `src/http.c` (auth runs before routing, so every path answers 401 under `-c` and no path can serve as an unauthenticated healthcheck), `src/protocol.c` (WebSocket auth in auth-header mode, URL args, Origin check), `html/src/components/terminal/xterm/index.ts` (client options), `LICENSE`, release asset list and `SHA256SUMS`.
- ttyd `main` (`_upstream/tsl0922__ttyd`, read only): same auth and option handling. No newer release than 1.7.7 exists.
- Debian: Docker Hub tags `13.7` / `13` (same digest `sha256:913f6706df59…`, updated 2026-10-06), and the trixie, trixie-updates and trixie-security `Packages` indexes (amd64), used to confirm every package name. `neofetch`, which both market templates install, is no longer in trixie. `fastfetch` replaces it.
- Node.js release index (`v24.22.0`, LTS "Krypton", 2026-10-14) and `SHASUMS256.txt`. Debian trixie's own `nodejs` package is 20.19, a line that reached end-of-life upstream in April 2026.

## Market templates and repositories reviewed

| Template / repo | License | Use |
|---|---|---|
| `debian-linux` "Debian-Linux" / `XenaaLangliss/debian-railway` | none (all rights reserved) | Read for feature expectations (ttyd, USERNAME/PASSWORD variables). Nothing copied |
| `debian` "Debian Linux, Open Source Web Terminal" / `kayrakryo/debian-linux-railway-template` | none (all rights reserved) | Read for feature expectations (tini, `/data` volume, multi-arch ttyd). Nothing copied |
| `debian-desktop-web-gui` (linuxserver/webtop XFCE) | n/a (config only) | Read for the healthcheck approach (an unauthenticated health location in front of basic auth). Nothing copied |

All files in this package were written for this template: the Dockerfile, `entrypoint.sh`, `terminal-session.sh`, `bashrc.sh`, `tmux.conf`, `nginx.conf.template`, `motd.txt` and the docs. No README text was reused.
