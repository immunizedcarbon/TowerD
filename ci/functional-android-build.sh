#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID="$ROOT/project-functional/android"
PASS="$(openssl rand -hex 24)"
echo "::add-mask::$PASS"
KEYSTORE="$RUNNER_TEMP/decimen-functional-0.4.0.jks"
keytool -genkeypair -noprompt -keystore "$KEYSTORE" -storepass "$PASS" -keypass "$PASS" -alias decimen -keyalg RSA -keysize 3072 -sigalg SHA256withRSA -validity 10000 -dname 'CN=Decimen Functional 0.4.0, O=Decimen, C=DE'
export DECIMEN_KEYSTORE="$KEYSTORE"
export DECIMEN_STORE_PASSWORD="$PASS"
export DECIMEN_KEY_ALIAS=decimen
export DECIMEN_KEY_PASSWORD="$PASS"
gradle -p "$ANDROID" --no-daemon --stacktrace :app:lintRelease :app:assembleDebug :app:assembleDebugAndroidTest :app:assembleRelease
