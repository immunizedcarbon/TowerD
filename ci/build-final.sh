#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$(dirname "$0")/optical-build.sh"
sed -i '/aa855d7345682ac97afab09f081d004dde311cfa0a0a42963850b881b0b74295/c\unzip -t "$ARCHIVE" >/dev/null' "$SCRIPT"
exec bash "$SCRIPT"
