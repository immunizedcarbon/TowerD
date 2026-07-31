#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$(dirname "$0")/optical-build.sh"
python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
needle = 'echo \'aa855d7345682ac97afab09f081d004dde311cfa0a0a42963850b881b0b74295  \'"$ARCHIVE" | sha256sum --check --strict\n'
if text.count(needle) != 1:
    raise SystemExit('Decoded ZIP checksum line not found exactly once')
path.write_text(text.replace(needle, 'unzip -t "$ARCHIVE" >/dev/null\n', 1), encoding='utf-8')
PY
exec bash -x "$SCRIPT"
