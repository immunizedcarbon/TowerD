#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID="$ROOT/project-functional/android"
OUT="$ROOT/final-artifact"
APK="$ANDROID/app/build/outputs/apk/release/app-release.apk"
DEBUG="$ANDROID/app/build/outputs/apk/debug/app-debug.apk"
TEST="$ANDROID/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
BT="$ANDROID_HOME/build-tools/36.0.0"
AZ="$ANDROID_HOME/cmdline-tools/latest/bin/apkanalyzer"
test -s "$APK" && test -s "$DEBUG" && test -s "$TEST"
"$BT/apksigner" verify --verbose --print-certs "$APK" | tee "$OUT/reports/signature.txt"
"$AZ" manifest permissions "$APK" | tee "$OUT/reports/permissions.txt"
"$AZ" manifest debuggable "$APK" | tee "$OUT/reports/debuggable.txt"
"$AZ" manifest min-sdk "$APK" | tee "$OUT/reports/min-sdk.txt"
"$AZ" manifest target-sdk "$APK" | tee "$OUT/reports/target-sdk.txt"
grep -q android.permission.CAMERA "$OUT/reports/permissions.txt"
! grep -q android.permission.INTERNET "$OUT/reports/permissions.txt"
grep -qx false "$OUT/reports/debuggable.txt"
grep -qx 35 "$OUT/reports/min-sdk.txt"
grep -qx 36 "$OUT/reports/target-sdk.txt"
unzip -Z1 "$APK" | grep -q '^assets/index.html$'
unzip -Z1 "$APK" | grep -q '^assets/send/index.html$'
unzip -Z1 "$APK" | grep -q '^assets/receive/index.html$'
unzip -Z1 "$APK" | grep -Eq '^assets/assets/zxing_reader.*\.wasm$'
unzip -t "$APK" > "$OUT/reports/unzip-test.txt"
cp "$APK" "$OUT/Decimen-Optical-Transfer-0.4.0.apk"
cp "$APK" "$OUT/Decimen-Optical-Transfer-0.3.0-hardened.apk"
cp "$DEBUG" "$OUT/app-debug.apk"
cp "$TEST" "$OUT/app-debug-androidTest.apk"
(cd "$OUT" && sha256sum Decimen-Optical-Transfer-0.4.0.apk > SHA256SUMS.txt)
cat "$OUT/SHA256SUMS.txt"
