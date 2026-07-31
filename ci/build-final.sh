#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/ci/functional-prepare.sh"
bash "$ROOT/ci/functional-web-build.sh"
bash "$ROOT/ci/functional-android-build.sh"
bash "$ROOT/ci/functional-verify.sh"
