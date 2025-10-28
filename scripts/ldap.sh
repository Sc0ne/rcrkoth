#!/usr/bin/env bash
set -euo pipefail

# ----- Config (password hardcoded as requested) -----
DC_HOST="10.3.2.13"
BIND_USER="jr@recruit.local"
BIND_PASS="$LDAP_PASSWORD"
BASE_DN="DC=recruit,DC=local"
FILTER="(userPrincipalName=jr@recruit.local)"
ATTR="description"
TIMEOUT_SECS=6
# ----------------------------------------------------

# Use timeout if available to avoid hanging
if command -v timeout >/dev/null 2>&1; then
  LDAP_CMD=(timeout "$TIMEOUT_SECS" ldapsearch -x -H "ldap://$DC_HOST:389")
else
  LDAP_CMD=(ldapsearch -x -H "ldap://$DC_HOST:389")
fi

# Run ldapsearch silently (stderr -> /dev/null). Use || true so set -e doesn't abort on non-zero exit.
output="$("${LDAP_CMD[@]}" -D "$BIND_USER" -w "$BIND_PASS" -b "$BASE_DN" "$FILTER" "$ATTR" 2>/dev/null || true)"

# Extract description lines
desc="$(printf '%s' "$output" | sed -n 's/^description: //p')"

# Print only if non-empty (with a trailing newline)
if [[ -n "$desc" ]]; then
  printf '%s\n' "$desc"
fi

