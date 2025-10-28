#!/usr/bin/env bash
set -euo pipefail

WIN_HOST="${1:-10.3.2.12}"
WIN_USER="localuser"
WIN_PASS="$WIN_PASSWORD"
WIN_PORT=5985
TARGET_USER="localuser"
FLAG_PATH="C:\\Users\\${TARGET_USER}\\Documents\\flag.txt"

output="$(python3 - <<PYCODE 2>/dev/null || true
import sys
try:
    import winrm
except Exception:
    sys.exit(0)

try:
    s = winrm.Session(
        "http://${WIN_HOST}:${WIN_PORT}/wsman",
        auth=("${WIN_USER}", "${WIN_PASS}"),
        transport='basic'
    )

    ps = r'''
\$path = "${FLAG_PATH}"
if (Test-Path -Path \$path) {
    Get-Content -LiteralPath \$path -Raw
}
'''

    r = s.run_ps(ps)
    out = r.std_out.decode('utf-8', errors='replace').strip()
    if out:
        sys.stdout.write(out)
    sys.exit(0)

except Exception:
    sys.exit(0)
PYCODE
)"

if [[ -n "${output}" ]]; then
  printf '%s\n' "$output"
fi

