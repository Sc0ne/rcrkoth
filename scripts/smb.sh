#!/usr/bin/env bash
set -euo pipefail

# ----- Config -----
HOST="${1:-10.3.2.12}"    # target host (first arg optional)
SHARE="shared"             # share name (//HOST/shared)
SMB_USER="localuser"
SMB_PASS="$SMB_PASSWORD"
FILE="flag.txt"
# ------------------

# Try streaming the file to stdout (many smbclient builds accept '-' as stdout target)
# Pipe through sed to ensure a trailing newline is present.
if smbclient "//$HOST/$SHARE" -U "${SMB_USER}%${SMB_PASS}" -c "get ${FILE} -" 2>/dev/null | sed -e '$a\' ; then
  exit 0
fi

# If streaming failed, fallback to saving to a temp file and printing it
TMP="$(mktemp /tmp/smbflag.XXXXXX)"
chmod 600 "$TMP"

# Use smbclient to download the file to tmp (smbclient prints progress to stderr — suppress it)
if smbclient "//$HOST/$SHARE" -U "${SMB_USER}%${SMB_PASS}" -c "get ${FILE} ${TMP}" 2>/dev/null; then
  # print the file and ensure trailing newline
  cat "$TMP"
  printf '\n'
  rm -f "$TMP"
  exit 0
fi

# If we reach here, both methods failed
rm -f "$TMP"
echo "ERROR: failed to fetch ${FILE} from //${HOST}/${SHARE}" >&2
exit 2

