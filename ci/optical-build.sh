#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="$ROOT/optical-transfer-build"
WORK="$ROOT/optical-transfer-v020-work"
ARTIFACT="$ROOT/final-artifact"
ARCHIVE="$RUNNER_TEMP/OpticalTransfer-ci-v020.zip"
B64="$RUNNER_TEMP/OpticalTransfer-ci-v020.zip.b64"

rm -rf "$WORK" "$ARTIFACT"
mkdir -p "$WORK" "$ARTIFACT/reports"
cat "$INPUT"/optical-ci-v020.b64.part* | tr -d '[:space:]' > "$B64"
echo '3b5ea88cdace31c63d13c9afbbd36d7499d48f7c4c4e1a90d2ffd9cd03c6180d  '"$B64" | sha256sum --check --strict
base64 --decode "$B64" > "$ARCHIVE"
echo 'aa855d7345682ac97afab09f081d004dde311cfa0a0a42963850b881b0b74295  '"$ARCHIVE" | sha256sum --check --strict
unzip -q "$ARCHIVE" -d "$WORK"

PROJECT="$WORK/OpticalTransfer"
MAIN="$PROJECT/app/src/main/java/de/oai/opticaltransfer/MainActivity.kt"
ASSEMBLER="$PROJECT/app/src/main/java/de/oai/opticaltransfer/ReceiverAssembler.kt"
PROFILE="$PROJECT/app/src/main/java/de/oai/opticaltransfer/DeviceProfile.kt"
python3 - "$MAIN" "$ASSEMBLER" "$PROFILE" <<'PY'
from pathlib import Path
import sys

main = Path(sys.argv[1])
text = main.read_text(encoding='utf-8')
inner = '''    ) : AutoCloseable {\n        private data class Presentation(val bitmap: Bitmap, val status: String?)\n\n'''
if text.count(inner) != 1:
    raise SystemExit('Unexpected nested Presentation declaration')
text = text.replace(inner, '''    ) : AutoCloseable {\n''', 1)
prepared = '''    private data class PreparedSend(\n        val file: File,\n        val metadata: OpticalProtocol.Metadata,\n        val profile: DeviceProfile,\n    )\n'''
if text.count(prepared) != 1:
    raise SystemExit('PreparedSend insertion point missing')
text = text.replace(prepared, prepared + '\n    private data class Presentation(val bitmap: Bitmap, val status: String?)\n', 1)
main.write_text(text, encoding='utf-8')

assembler = Path(sys.argv[2])
text = assembler.read_text(encoding='utf-8')
old = 'private fun acceptMeta(incoming: OpticalProtocol.Metadata): Update {'
new = 'private fun acceptMeta(incoming: OpticalProtocol.Metadata): Update? {'
if text.count(old) != 1:
    raise SystemExit('Unexpected acceptMeta declaration')
text = text.replace(old, new, 1)
marker = '    private var announcedWaitingForMetadata = false\n'
if text.count(marker) != 1:
    raise SystemExit('Receiver state insertion point missing')
text = text.replace(marker, marker + '    private var closed = false\n', 1)
accept = '    fun accept(decoded: QrCodec.Decoded): Update? {\n        return when'
if text.count(accept) != 1:
    raise SystemExit('Receiver accept insertion point missing')
text = text.replace(accept, '    fun accept(decoded: QrCodec.Decoded): Update? {\n        if (closed) return null\n        return when', 1)
close = '    override fun close() {\n        reset(deleteFile = true)'
if text.count(close) != 1:
    raise SystemExit('Receiver close insertion point missing')
text = text.replace(close, '    override fun close() {\n        closed = true\n        reset(deleteFile = true)', 1)
assembler.write_text(text, encoding='utf-8')

profile = Path(sys.argv[3])
text = profile.read_text(encoding='utf-8')
replacements = {
    'isTabS5e -> DeviceProfile(framesPerSecond = 10, minimumPixelsPerModule = 7)':
        'isTabS5e -> DeviceProfile(framesPerSecond = 10, minimumPixelsPerModule = 8)',
    'isTablet -> DeviceProfile(framesPerSecond = fps.coerceAtMost(10), minimumPixelsPerModule = 7)':
        'isTablet -> DeviceProfile(framesPerSecond = fps.coerceAtMost(10), minimumPixelsPerModule = 8)',
    'else -> DeviceProfile(framesPerSecond = fps, minimumPixelsPerModule = 6)':
        'else -> DeviceProfile(framesPerSecond = fps, minimumPixelsPerModule = 7)',
}
for old, new in replacements.items():
    if text.count(old) != 1:
        raise SystemExit(f'Device profile pattern missing: {old}')
    text = text.replace(old, new, 1)
profile.write_text(text, encoding='utf-8')
PY

grep -q 'versionName = "0.2.0"' "$PROJECT/app/build.gradle.kts"
grep -q 'minSdk = 35' "$PROJECT/app/build.gradle.kts"
grep -q 'targetSdk = 37' "$PROJECT/app/build.gradle.kts"
grep -q 'com.google.zxing:core:3.5.4' "$PROJECT/app/build.gradle.kts"

SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
yes | "$SDKMANAGER" --licenses >/dev/null || true
"$SDKMANAGER" 'platforms;android-37' 'build-tools;36.0.0'

gradle -p "$PROJECT" --no-daemon --stacktrace :app:assembleDebug

APK="$PROJECT/app/build/outputs/apk/debug/app-debug.apk"
test -s "$APK"
BUILD_TOOLS="$ANDROID_HOME/build-tools/36.0.0"
ANALYZER="$ANDROID_HOME/cmdline-tools/latest/bin/apkanalyzer"
"$BUILD_TOOLS/apksigner" verify --verbose --print-certs "$APK" | tee "$ARTIFACT/reports/apksigner.txt"
"$ANALYZER" apk summary "$APK" | tee "$ARTIFACT/reports/apk-summary.txt"
"$ANALYZER" manifest permissions "$APK" | tee "$ARTIFACT/reports/manifest-permissions.txt"
"$ANALYZER" manifest debuggable "$APK" | tee "$ARTIFACT/reports/manifest-debuggable.txt"
"$ANALYZER" manifest min-sdk "$APK" | tee "$ARTIFACT/reports/manifest-min-sdk.txt"
"$ANALYZER" manifest target-sdk "$APK" | tee "$ARTIFACT/reports/manifest-target-sdk.txt"

grep -q android.permission.CAMERA "$ARTIFACT/reports/manifest-permissions.txt"
! grep -q android.permission.INTERNET "$ARTIFACT/reports/manifest-permissions.txt"
grep -qx true "$ARTIFACT/reports/manifest-debuggable.txt"
grep -qx 35 "$ARTIFACT/reports/manifest-min-sdk.txt"
grep -qx 37 "$ARTIFACT/reports/manifest-target-sdk.txt"
if unzip -Z1 "$APK" | grep -q '^lib/'; then
    echo 'Unexpected native ABI library in APK' >&2
    exit 1
fi
unzip -t "$APK" > "$ARTIFACT/reports/unzip-test.txt"

cp "$APK" "$ARTIFACT/OpticalTransfer-0.2.0-debug.apk"
cat > "$ARTIFACT/BUILD_INFO.txt" <<'EOF'
Optical Transfer 0.2.0
Android Gradle Plugin 9.3.0
Gradle 9.5.0
Java 17
compileSdk/targetSdk 37
minSdk 35
ZXing Core 3.5.4
Debug-signed engineering build
EOF
(
    cd "$ARTIFACT"
    sha256sum OpticalTransfer-0.2.0-debug.apk > OpticalTransfer-0.2.0-SHA256.txt
)
cat "$ARTIFACT/OpticalTransfer-0.2.0-SHA256.txt"
