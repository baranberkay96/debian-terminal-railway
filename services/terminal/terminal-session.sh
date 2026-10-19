#!/usr/bin/env bash
# ttyd starts this for every browser connection, as user "debian".
#
# With TERMINAL_TMUX=true (the default), each tab attaches to a tmux session.
# The shell and its running jobs survive closed tabs, page reloads and dropped
# connections, and reopening the URL reattaches. Choose a session with
# ?arg=NAME in the URL (letters, digits, '-' and '_'). The default is "main".
# Tabs on the same session mirror each other.
set -uo pipefail

session="main"
if [[ $# -gt 0 && "$1" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; then
  session="$1"
fi

cd "${HOME:-/}" 2> /dev/null || cd /

case "${TERMINAL_TMUX:-true}" in
  true)
    if command -v tmux > /dev/null 2>&1; then
      exec tmux new-session -A -s "$session"
    fi
    echo "tmux is not installed. Starting a plain shell." >&2
    ;;
esac

exec /bin/bash --login
