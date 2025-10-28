#!/usr/bin/env bash
set -euo pipefail

# Target
HOST="10.3.2.11"
USER="root"
PASS="$SSH_PASSWORD"
REMOTE_PATH="/flag/flag.txt"

# SSH options: short connect timeout, no interactive prompts, avoid hostkey prompts
SSH_OPTS=( -o ConnectTimeout=5 -o BatchMode=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password )

# create a secure temporary password file to avoid showing the password in ps output
PWFILE="$(mktemp /tmp/sshpw.XXXXXX)"
chmod 600 "$PWFILE"
printf '%s\n' "$PASS" > "$PWFILE"

cleanup() {
  shred -u "$PWFILE" 2>/dev/null || rm -f "$PWFILE"
}
trap cleanup EXIT

# remote command: print the file only if it exists
REMOTE_CMD="if [ -f '${REMOTE_PATH}' ]; then cat '${REMOTE_PATH}'; fi"

# Use timeout if available to bound total runtime
if command -v timeout >/dev/null 2>&1; then
  SSH_RUN=(timeout 8 sshpass -f "$PWFILE" ssh "${SSH_OPTS[@]}" "${USER}@${HOST}" "$REMOTE_CMD")
else
  SSH_RUN=(sshpass -f "$PWFILE" ssh "${SSH_OPTS[@]}" "${USER}@${HOST}" "$REMOTE_CMD")
fi

# Run the command silently (suppress stderr). Capture stdout; don't fail the script on non-zero exit.
output="$("${SSH_RUN[@]}" 2>/dev/null || true)"

# Print only if non-empty, guarantee newline
if [[ -n "${output}" ]]; then
  printf '%s\n' "$output"
fi

exit 0
