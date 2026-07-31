#!/usr/bin/env bash
set -euo pipefail

: "${PROFILE:?PROFILE required}"
: "${API:?API required}"
: "${IMAGE:?IMAGE required}"
: "${WIDTH:?WIDTH required}"
: "${HEIGHT:?HEIGHT required}"
: "${DENSITY:?DENSITY required}"
: "${RAM:?RAM required}"
: "${ROTATION:?ROTATION required}"

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
ARTIFACT="$ROOT/final-artifact"
EVIDENCE="$ROOT/evidence-$PROFILE"
mkdir -p "$EVIDENCE"

SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
IMAGE_ID="system-images;android-${API};${IMAGE};x86_64"

yes | "$SDKMANAGER" --licenses >/dev/null || true
"$SDKMANAGER" "platform-tools" "emulator" "$IMAGE_ID"
sudo chmod 666 /dev/kvm || true

echo no | "$AVDMANAGER" create avd --force --name decimen-test --package "$IMAGE_ID" --device pixel_8
cat >> "$HOME/.android/avd/decimen-test.avd/config.ini" <<EOF
hw.cpu.ncore=4
hw.keyboard=yes
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader_indirect
hw.camera.back=virtualscene
hw.camera.front=none
disk.dataPartition.size=8G
skin.dynamic=yes
showDeviceFrame=no
hw.ramSize=$RAM
EOF

export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"
nohup emulator @decimen-test -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data \
  -gpu swiftshader_indirect -camera-back virtualscene -camera-front none \
  -memory "$RAM" -cores 4 -no-metrics > "$EVIDENCE/emulator.log" 2>&1 &
EMULATOR_PID=$!
cleanup() {
  adb emu kill >/dev/null 2>&1 || true
  kill "$EMULATOR_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

adb wait-for-device
for attempt in $(seq 1 240); do
  if [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
    break
  fi
  if [ "$attempt" = 240 ]; then
    cat "$EVIDENCE/emulator.log"
    exit 1
  fi
  sleep 2
done

adb shell input keyevent 82 || true
adb shell wm size "${WIDTH}x${HEIGHT}"
adb shell wm density "$DENSITY"
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation "$ROTATION"
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb shell settings put global stay_on_while_plugged_in 3
adb shell getprop > "$EVIDENCE/device-properties.txt"
adb shell wm size > "$EVIDENCE/display-size.txt"
adb shell wm density > "$EVIDENCE/display-density.txt"

adb logcat -c
adb install -r -t "$ARTIFACT/app-debug.apk"
adb install -r -t "$ARTIFACT/app-debug-androidTest.apk"
adb shell pm grant dev.decimen.optical.debug android.permission.CAMERA

timeout 600 adb shell am instrument -w -r \
  -e class dev.decimen.optical.DeviceCompatibilityTest \
  -e profile "$PROFILE" \
  -e expected_sdk "$API" \
  -e expected_width "$WIDTH" \
  -e expected_height "$HEIGHT" \
  dev.decimen.optical.debug.test/androidx.test.runner.AndroidJUnitRunner \
  | tee "$EVIDENCE/instrumentation.txt"
grep -q '^OK (' "$EVIDENCE/instrumentation.txt"

adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
adb pull /sdcard/window.xml "$EVIDENCE/window.xml" >/dev/null 2>&1 || true
adb pull /sdcard/Android/data/dev.decimen.optical.debug/files "$EVIDENCE/debug-files" >/dev/null 2>&1 || true

adb uninstall dev.decimen.optical.debug.test || true
adb uninstall dev.decimen.optical.debug || true
adb install "$ARTIFACT/Decimen-Optical-Transfer-0.3.0-hardened.apk"
adb shell am start -W -n dev.decimen.optical/.MainActivity | tee "$EVIDENCE/release-launch.txt"
sleep 15
test -n "$(adb shell pidof dev.decimen.optical | tr -d '\r')"
adb shell dumpsys package dev.decimen.optical > "$EVIDENCE/release-package.txt"
grep -q android.permission.CAMERA "$EVIDENCE/release-package.txt"
! grep -q android.permission.INTERNET "$EVIDENCE/release-package.txt"
adb exec-out screencap -p > "$EVIDENCE/release.png"
adb logcat -d -v threadtime > "$EVIDENCE/logcat.txt"
if grep -E 'FATAL EXCEPTION.*dev\.decimen|Process: dev\.decimen.*FATAL' "$EVIDENCE/logcat.txt"; then
  echo 'Fatal application exception detected' >&2
  exit 1
fi

cat > "$EVIDENCE/RESULT.txt" <<EOF
profile=$PROFILE
api=$API
resolution=${WIDTH}x${HEIGHT}
density=$DENSITY
ram_mb=$RAM
instrumentation=passed
signed_release_launch=passed
camera_permission=present
internet_permission=absent
fatal_app_exception=absent
EOF
cat "$EVIDENCE/RESULT.txt"
