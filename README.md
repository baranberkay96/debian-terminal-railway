# Deploy and Host Debian 13 Web Terminal with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/debian-13-web-terminal-browser-shell?referralCode=20H68q)

A Debian 13 (trixie) shell you open in any browser. The shell runs in tmux, so your session and running commands survive closed tabs and dropped connections. A generated password protects it, and your home directory sits on a persistent volume. git, Python, Node.js, build tools and editors come preinstalled.

## About Hosting Debian 13 Web Terminal

A web terminal needs a long-running Linux container with a terminal server, real authentication in front of it, TLS, and storage that outlives rebuilds. This community template builds on the official `debian:13.7` image and serves the shell with ttyd 1.7.7. nginx stands in front of ttyd and checks a password that Railway generates at deploy. You work as a normal user, `debian`, with sudo, and `/home` is a Railway volume. Railway's edge provides HTTPS. Each browser tab attaches to a tmux session, so long jobs keep running after you close the tab.

## Common Use Cases

- A Linux shell from a Chromebook, tablet, work laptop or any machine where you cannot install SSH or a VM
- Running long scripts, downloads, builds or bots in tmux and checking back on them later
- Learning Linux commands, apt and shell scripting without a local setup
- Testing scripts, CLIs and packages on Debian 13 before shipping them
- A small always-on scratch box for git, Python and Node.js work

## Dependencies for Debian 13 Web Terminal Hosting

- A Railway volume mounted at `/home` (included in the template)
- Nothing else: no database, no API keys, no external accounts

### Deployment Dependencies

- Debian 13 "trixie" release notes: https://www.debian.org/releases/trixie/
- Debian image on Docker Hub: https://hub.docker.com/_/debian
- ttyd (web terminal, MIT): https://github.com/tsl0922/ttyd
- tmux: https://github.com/tmux/tmux/wiki
- nginx basic authentication: https://nginx.org/en/docs/http/ngx_http_auth_basic_module.html
- Railway volumes: https://docs.railway.com/volumes
- Railway Acceptable Use Policy: https://railway.com/legal/fair-use

### Implementation Details

| Service | Source | Purpose |
|---|---|---|
| Terminal | Dockerfile based on `debian:13.7` | nginx basic-auth proxy on port 8080 (public HTTPS domain, `/healthz`), ttyd on loopback, tmux sessions, user `debian` with sudo, volume at `/home` |

**First login**

1. Open the service's public URL.
2. Your browser asks for a user name and password. The user name is `debian` (the `USERNAME` variable). The password is the generated `PASSWORD` value on the service's Variables tab.
3. You land in a tmux session named `main`. Close the tab at any time and reopen the URL to resume. For a second, independent session, open `https://{your-domain}/?arg=work`.
4. Install software with `sudo apt update && sudo apt install {package}`. Packages you list in `~/.config/debian-terminal/apt-packages` (or in the `APT_PACKAGES` variable) are installed again in the background after every redeploy.

**What persists**: everything under `/home/debian`: files, dotfiles, shell history, Python virtualenvs, pipx apps in `~/.local`, and global npm packages in `~/.npm-global`. Running processes and system packages installed with apt reset on every redeploy or restart. tmux keeps sessions alive across browser reconnects, not across container restarts.

**Security**: the shell is never served without a password. With an empty or short `PASSWORD` the service refuses to start. nginx checks the password, which the container keeps only as a SHA-512 crypt hash, and rate-limits attempts. It also rejects WebSocket connections from other sites. ttyd listens on 127.0.0.1 only. The password does not appear in logs, process arguments or the shell environment. To change it, edit `PASSWORD` and redeploy. Browsers cache basic-auth logins until you close them, so use a private window on shared computers.

**Scaling**: this is a single-user machine on one volume, so keep one replica. Railway scales RAM and CPU vertically up to your plan limit. For a team, deploy one terminal per person.

**Pinning and upgrades**: the Debian base tag and the ttyd and Node.js versions (with checksums) are pinned at the top of `services/terminal/Dockerfile`. Change them and redeploy. Every fresh image build runs `apt-get upgrade` for Debian security fixes. Railway may reuse cached build layers, so bump the base tag (for example to the next `13.x` point release) to force a fresh one.

**Fair use**: Railway's Acceptable Use Policy applies to everything you run in this shell. Do not use it for cryptocurrency mining, proxies, anonymizers, torrenting or reselling compute. Railway may disable resources that break the policy.

### Why Deploy Debian 13 Web Terminal on Railway?

Railway gives the terminal an HTTPS URL, a persistent volume and automatic restarts, with no server to administer. You get a protected Debian shell from one click and pay only for the little CPU and memory an idle shell uses.
