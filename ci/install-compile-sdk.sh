#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/ci/functional-lint-fixes.py" "$ROOT/project-functional/android"
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" 'platforms;android-37.0'
