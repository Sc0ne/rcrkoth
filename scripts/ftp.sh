#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-10.3.2.10}"
USER="root"
PASS="$FTP_PASSWORD"
REMOTE_FILE="flag.txt"        # file name in FTP root
CONNECT_TIMEOUT=4
MAX_TIME=7
LOCKFILE="/var/lock/ftp-get-flag.lock"

# Acquire non-blocking lock (exit silently if locked)
exec 200>"$LOCKFILE"
flock -n 200 || exit 0

# Create a temporary netrc for curl to use (keeps password out of ps)
NETRC="$(mktemp /tmp/netrc.XXXXXX)"
chmod 600 "$NETRC"
cat > "$NETRC" <<EOF
machine ${HOST}
login ${USER}
password ${PASS}
EOF

cleanup() {
  shred -u "$NETRC" 2>/dev/null || rm -f "$NETRC"
  # release lock by closing FD 200 (happens on exit)
}
trap cleanup EXIT

# Try to fetch the file via plain FTP. Silent on stderr, bounded by timeouts.
output="$(curl --netrc-file "$NETRC" \
  --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
  --silent "ftp://${HOST}/${REMOTE_FILE}" 2>/dev/null || true)"

# Print only if non-empty and ensure trailing newline
if [[ -n "$output" ]]; then
  printf '%s\n' "$output"
fi

