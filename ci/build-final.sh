#!/usr/bin/env bash
set -euo pipefail

ROOT="${DECIMEN_ROOT:-${GITHUB_WORKSPACE:-$(pwd)}}"
export DECIMEN_ROOT="$ROOT"
WORK="$ROOT/final-work"
ARTIFACT="$ROOT/final-artifact"
rm -rf "$WORK" "$ARTIFACT"
mkdir -p "$WORK" "$ARTIFACT/reports"

git clone --filter=blob:none https://github.com/bashalarmistalt/decimen-optical-transfer.git "$WORK/web"
git -C "$WORK/web" checkout 13e86c26a187882637015b9267bb0361d67f1033
cat "$ROOT"/web-hardening.patch.gz.b64.part* | base64 --decode | gzip -dc > "$RUNNER_TEMP/web-hardening.patch"
echo '6a0e0809e627d544882eb4d72bffad76b6a12b4ca6cf4205f283c1646923098d  '"$RUNNER_TEMP/web-hardening.patch" | sha256sum -c -
git -C "$WORK/web" apply --check "$RUNNER_TEMP/web-hardening.patch"
git -C "$WORK/web" apply "$RUNNER_TEMP/web-hardening.patch"
git -C "$WORK/web" apply --check "$ROOT/web-lifecycle-fix.patch"
git -C "$WORK/web" apply "$ROOT/web-lifecycle-fix.patch"

cp -a "$ROOT/android-src" "$WORK/android"
mkdir -p "$WORK/android/app/src/main/java/dev/decimen/optical"
mkdir -p "$WORK/android/app/src/androidTest/java/dev/decimen/optical"
cat "$ROOT"/android-src-parts/MainActivity.java.part* > "$WORK/android/app/src/main/java/dev/decimen/optical/MainActivity.java"
cat "$ROOT"/android-src-parts/DeviceCompatibilityTest.java.part* > "$WORK/android/app/src/androidTest/java/dev/decimen/optical/DeviceCompatibilityTest.java"
MAIN_ACTIVITY="$WORK/android/app/src/main/java/dev/decimen/optical/MainActivity.java"
echo '0cb55a214feec2c2c064b8b27e0f8e99ac2e3f452d2656972d7a4da513ca0352  '"$MAIN_ACTIVITY" | sha256sum -c -
python3 - "$MAIN_ACTIVITY" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
if text.count('BuildConfig.DEBUG') != 2:
    raise SystemExit('Unexpected BuildConfig.DEBUG occurrence count')
text = text.replace('BuildConfig.DEBUG', 'isDebuggable()')
needle = '    private String resolveDeviceModel() {\n'
helper = (
    '    private boolean isDebuggable() {\n'
    '        return (getApplicationInfo().flags\n'
    '                & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;\n'
    '    }\n\n'
)
if text.count(needle) != 1:
    raise SystemExit('resolveDeviceModel insertion point missing')
path.write_text(text.replace(needle, helper + needle), encoding='utf-8')
PY
! grep -q 'BuildConfig.DEBUG' "$MAIN_ACTIVITY"
grep -q 'ApplicationInfo.FLAG_DEBUGGABLE' "$MAIN_ACTIVITY"
cp "$ROOT/VERIFICATION.md" "$WORK/VERIFICATION.md"

pushd "$WORK/web"
npm ci --ignore-scripts
npm run check
npm run build
npm audit --json > "$WORK/npm-audit.json" || true
node - <<'NODE'
const report = require(process.env.DECIMEN_ROOT + '/final-work/npm-audit.json');
const v = report.metadata?.vulnerabilities ?? {};
const total = (v.low || 0) + (v.moderate || 0) + (v.high || 0) + (v.critical || 0);
console.log('npm audit:', v);
if (total !== 0) process.exit(1);
NODE
popd

pipx run semgrep scan --config p/default --json \
  --exclude "$WORK/web/node_modules" --exclude "$WORK/web/dist" \
  "$WORK/web" "$WORK/android/app/src" > "$WORK/semgrep.json"
python3 - "$WORK/semgrep.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1], encoding='utf-8'))
results = report.get('results', [])
errors = report.get('errors', [])
print('Semgrep findings:', len(results))
print('Semgrep errors:', len(errors))
for finding in results:
    extra = finding.get('extra', {})
    start = finding.get('start', {})
    print('SEMGREP_FINDING', finding.get('check_id'), finding.get('path'),
          start.get('line'), extra.get('severity'), extra.get('message'))
if results or errors:
    raise SystemExit(1)
PY

rm -rf "$WORK/android/app/src/main/assets/www"
mkdir -p "$WORK/android/app/src/main/assets/www"
cp -a "$WORK/web/dist/." "$WORK/android/app/src/main/assets/www/"
test -s "$WORK/android/app/src/main/assets/www/index.html"
test -s "$WORK/android/app/src/main/assets/www/send/index.html"
test -s "$WORK/android/app/src/main/assets/www/receive/index.html"

PASSWORD="$(openssl rand -hex 24)"
echo "::add-mask::$PASSWORD"
KEYSTORE="$RUNNER_TEMP/decimen-final-release.jks"
keytool -genkeypair -noprompt -keystore "$KEYSTORE" -storepass "$PASSWORD" -keypass "$PASSWORD" \
  -alias decimen -keyalg RSA -keysize 3072 -sigalg SHA256withRSA -validity 10000 \
  -dname 'CN=Decimen Verified Release, OU=Exact Device Matrix, O=Open Source, C=DE'
export DECIMEN_KEYSTORE="$KEYSTORE"
export DECIMEN_STORE_PASSWORD="$PASSWORD"
export DECIMEN_KEY_ALIAS=decimen
export DECIMEN_KEY_PASSWORD="$PASSWORD"

gradle -p "$WORK/android" --no-daemon --stacktrace \
  :app:lintRelease :app:assembleDebug :app:assembleDebugAndroidTest :app:assembleRelease

APK="$WORK/android/app/build/outputs/apk/release/app-release.apk"
DEBUG_APK="$WORK/android/app/build/outputs/apk/debug/app-debug.apk"
TEST_APK="$WORK/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
test -s "$APK" && test -s "$DEBUG_APK" && test -s "$TEST_APK"

BUILD_TOOLS="$ANDROID_HOME/build-tools/36.0.0"
ANALYZER="$ANDROID_HOME/cmdline-tools/latest/bin/apkanalyzer"
"$BUILD_TOOLS/apksigner" verify --verbose --print-certs "$APK" | tee "$WORK/apksigner-report.txt"
"$ANALYZER" apk summary "$APK" | tee "$WORK/apk-summary.txt"
"$ANALYZER" manifest permissions "$APK" | tee "$WORK/manifest-permissions.txt"
"$ANALYZER" manifest debuggable "$APK" | tee "$WORK/manifest-debuggable.txt"
"$ANALYZER" manifest min-sdk "$APK" | tee "$WORK/manifest-min-sdk.txt"
"$ANALYZER" manifest target-sdk "$APK" | tee "$WORK/manifest-target-sdk.txt"

grep -q android.permission.CAMERA "$WORK/manifest-permissions.txt"
! grep -q android.permission.INTERNET "$WORK/manifest-permissions.txt"
grep -qx false "$WORK/manifest-debuggable.txt"
grep -qx 35 "$WORK/manifest-min-sdk.txt"
grep -qx 37 "$WORK/manifest-target-sdk.txt"
if unzip -Z1 "$APK" | grep -q '^lib/'; then
  echo 'Unexpected native ABI library in release APK' >&2
  exit 1
fi
unzip -Z1 "$APK" | grep -q 'assets/www/index.html'
unzip -Z1 "$APK" | grep -q 'assets/www/send/index.html'
unzip -Z1 "$APK" | grep -q 'assets/www/receive/index.html'
unzip -Z1 "$APK" | grep -Eq 'zxing_reader.*\.wasm'

cp "$APK" "$ARTIFACT/Decimen-Optical-Transfer-0.3.0-hardened.apk"
cp "$DEBUG_APK" "$ARTIFACT/app-debug.apk"
cp "$TEST_APK" "$ARTIFACT/app-debug-androidTest.apk"
cp "$WORK/VERIFICATION.md" "$ARTIFACT/"
cp "$WORK/npm-audit.json" "$WORK/semgrep.json" "$WORK/apksigner-report.txt" \
  "$WORK/apk-summary.txt" "$WORK/manifest-permissions.txt" "$WORK/manifest-debuggable.txt" \
  "$WORK/manifest-min-sdk.txt" "$WORK/manifest-target-sdk.txt" "$ARTIFACT/reports/"
cp -a "$WORK/android/app/build/reports/lint-results-release."* "$ARTIFACT/reports/" 2>/dev/null || true
(
  cd "$ARTIFACT"
  sha256sum Decimen-Optical-Transfer-0.3.0-hardened.apk > SHA256SUMS.txt
)
cat "$ARTIFACT/SHA256SUMS.txt"
