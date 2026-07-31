#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="$ROOT/project-functional/web"
ANDROID="$ROOT/project-functional/android"
pushd "$WEB" >/dev/null
npm ci --ignore-scripts
npm run check
npm run build
npm audit --audit-level=high
popd >/dev/null
! grep -R 'SYSTEMCHECK\|Dateien verlassen das Gerät' "$WEB/dist"
grep -q 'send/index.html' "$WEB/dist/index.html"
grep -q 'receive/index.html' "$WEB/dist/index.html"
test -n "$(find "$WEB/dist" -name 'zxing_reader*.wasm' -print -quit)"
rm -rf "$ANDROID/app/src/main/assets"
mkdir -p "$ANDROID/app/src/main/assets"
cp -a "$WEB/dist/." "$ANDROID/app/src/main/assets/"
test -f "$ANDROID/app/src/main/assets/index.html"
test -f "$ANDROID/app/src/main/assets/send/index.html"
test -f "$ANDROID/app/src/main/assets/receive/index.html"
