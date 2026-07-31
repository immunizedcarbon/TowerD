#!/usr/bin/env bash
set -euo pipefail

: "${PROFILE:?PROFILE required}"
: "${API:?API required}"
: "${IMAGE:?IMAGE required}"
: "${RAM:?RAM required}"

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
ARTIFACT="$ROOT/final-artifact"
EVIDENCE="$ROOT/evidence-$PROFILE"
mkdir -p "$EVIDENCE"

SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
IMAGE_ID="system-images;android-${API};${IMAGE};x86_64"
AVD_NAME="decimen-diagnostic"
AVD_HOME="${ANDROID_AVD_HOME:-$HOME/.android/avd}"
AVD_DIR="$AVD_HOME/$AVD_NAME.avd"

yes | "$SDKMANAGER" --licenses >/dev/null || true
timeout 1800 "$SDKMANAGER" --channel=3 platform-tools emulator "$IMAGE_ID"
sudo chmod 666 /dev/kvm || true
mkdir -p "$AVD_HOME"
rm -rf "$AVD_DIR" "$AVD_HOME/$AVD_NAME.ini"
printf 'no\n' | "$AVDMANAGER" create avd --force --name "$AVD_NAME" \
  --package "$IMAGE_ID" --path "$AVD_DIR"
test -f "$AVD_DIR/config.ini"
cat >> "$AVD_DIR/config.ini" <<EOF
hw.cpu.ncore=4
hw.keyboard=yes
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader_indirect
hw.camera.back=virtualscene
hw.camera.front=none
disk.dataPartition.size=8G
hw.ramSize=$RAM
EOF
cat > "$AVD_HOME/$AVD_NAME.ini" <<EOF
avd.ini.encoding=UTF-8
path=$AVD_DIR
target=android-$API
EOF

export ANDROID_AVD_HOME="$AVD_HOME"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"
emulator -list-avds | grep -qx "$AVD_NAME"
nohup emulator "@$AVD_NAME" -no-window -no-audio -no-boot-anim -no-snapshot \
  -no-snapshot-save -wipe-data -gpu swiftshader_indirect -memory "$RAM" -cores 4 \
  -no-metrics > "$EVIDENCE/emulator.log" 2>&1 &
EMULATOR_PID=$!
cleanup() {
  adb forward --remove tcp:9222 >/dev/null 2>&1 || true
  adb emu kill >/dev/null 2>&1 || true
  kill "$EMULATOR_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for attempt in $(seq 1 180); do
  kill -0 "$EMULATOR_PID" >/dev/null 2>&1 || { cat "$EVIDENCE/emulator.log"; exit 1; }
  [ "$(adb get-state 2>/dev/null || true)" = device ] && break
  [ "$attempt" = 180 ] && { cat "$EVIDENCE/emulator.log"; exit 1; }
  sleep 2
done
for attempt in $(seq 1 180); do
  [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
  [ "$attempt" = 180 ] && { cat "$EVIDENCE/emulator.log"; exit 1; }
  sleep 2
done

adb install -r -t "$ARTIFACT/app-debug.apk"
adb shell am force-stop dev.decimen.optical.debug
adb shell am start -W \
  -n dev.decimen.optical.debug/dev.decimen.optical.MainActivity \
  --es dev.decimen.optical.TEST_PROFILE "$PROFILE" \
  | tee "$EVIDENCE/debug-launch.txt"

PID=""
for attempt in $(seq 1 60); do
  PID="$(adb shell pidof dev.decimen.optical.debug 2>/dev/null | tr -d '\r')"
  [ -n "$PID" ] && break
  sleep 1
done
[ -n "$PID" ] || { echo 'Debug process missing' >&2; exit 1; }

SOCKET="webview_devtools_remote_$PID"
for attempt in $(seq 1 60); do
  if adb shell cat /proc/net/unix 2>/dev/null | grep -q "$SOCKET"; then
    break
  fi
  [ "$attempt" = 60 ] && {
    echo "WebView debugging socket $SOCKET missing" >&2
    adb shell cat /proc/net/unix | grep -i webview >&2 || true
    exit 1
  }
  sleep 1
done
adb forward tcp:9222 "localabstract:$SOCKET"

python3 - "$EVIDENCE/webview-selftest.json" <<'PY'
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import time
import urllib.request
from urllib.parse import urlparse

output = sys.argv[1]
endpoint = 'http://127.0.0.1:9222/json'
targets = None
for _ in range(120):
    try:
        targets = json.load(urllib.request.urlopen(endpoint, timeout=2))
        pages = [t for t in targets if t.get('type') == 'page']
        if pages:
            break
    except Exception:
        pass
    time.sleep(0.5)
else:
    raise SystemExit('No WebView DevTools page target')

target = next((t for t in pages if 'appassets.androidplatform.net' in t.get('url', '')), pages[0])
url = urlparse(target['webSocketDebuggerUrl'])
host, port = '127.0.0.1', 9222
path = url.path + (('?' + url.query) if url.query else '')
sock = socket.create_connection((host, port), timeout=10)
key = base64.b64encode(os.urandom(16)).decode('ascii')
request = (
    f'GET {path} HTTP/1.1\r\n'
    f'Host: {host}:{port}\r\n'
    'Upgrade: websocket\r\n'
    'Connection: Upgrade\r\n'
    f'Sec-WebSocket-Key: {key}\r\n'
    'Sec-WebSocket-Version: 13\r\n\r\n'
)
sock.sendall(request.encode('ascii'))
response = b''
while b'\r\n\r\n' not in response:
    response += sock.recv(4096)
if b' 101 ' not in response.split(b'\r\n', 1)[0]:
    raise SystemExit('WebSocket handshake failed: ' + response[:300].decode('latin1', 'replace'))

def send_text(text):
    payload = text.encode('utf-8')
    mask = os.urandom(4)
    length = len(payload)
    header = bytearray([0x81])
    if length < 126:
        header.append(0x80 | length)
    elif length <= 0xffff:
        header.append(0x80 | 126)
        header.extend(struct.pack('!H', length))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack('!Q', length))
    header.extend(mask)
    header.extend(bytes(value ^ mask[index % 4] for index, value in enumerate(payload)))
    sock.sendall(header)

def read_exact(size):
    data = b''
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise EOFError('WebSocket closed')
        data += chunk
    return data

def receive():
    first, second = read_exact(2)
    opcode = first & 0x0f
    length = second & 0x7f
    if length == 126:
        length = struct.unpack('!H', read_exact(2))[0]
    elif length == 127:
        length = struct.unpack('!Q', read_exact(8))[0]
    masked = bool(second & 0x80)
    mask = read_exact(4) if masked else b''
    payload = read_exact(length)
    if masked:
        payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    if opcode == 0x9:
        return receive()
    if opcode == 0x8:
        raise EOFError('WebSocket close frame')
    return json.loads(payload.decode('utf-8'))

command_id = 0
def command(method, params=None):
    global command_id
    command_id += 1
    current = command_id
    send_text(json.dumps({'id': current, 'method': method, 'params': params or {}}))
    while True:
        message = receive()
        if message.get('id') == current:
            return message

command('Runtime.enable')
expression = """JSON.stringify({
  url: location.href,
  ready: document.readyState,
  status: document.getElementById('selftest-status')?.textContent || '',
  details: document.getElementById('selftest-details')?.textContent || '',
  secure: isSecureContext,
  webAssembly: !!globalThis.WebAssembly,
  worker: !!globalThis.Worker,
  webCrypto: !!globalThis.crypto?.subtle,
  userAgent: navigator.userAgent
})"""
result = None
for _ in range(180):
    reply = command('Runtime.evaluate', {
        'expression': expression,
        'returnByValue': True,
        'awaitPromise': True,
    })
    raw = reply.get('result', {}).get('result', {}).get('value')
    if raw:
        result = json.loads(raw)
        if result.get('status') in ('SYSTEMCHECK BESTANDEN', 'SYSTEMCHECK FEHLGESCHLAGEN'):
            break
    time.sleep(0.5)
if result is None:
    raise SystemExit('No self-test result from WebView')
with open(output, 'w', encoding='utf-8') as handle:
    json.dump(result, handle, ensure_ascii=False, indent=2)
print(json.dumps(result, ensure_ascii=False, indent=2))
if result.get('status') != 'SYSTEMCHECK BESTANDEN':
    raise SystemExit('Web self-test failed: ' + result.get('details', 'unknown'))
PY

adb exec-out screencap -p > "$EVIDENCE/webview-screen.png" || true
adb logcat -d -v threadtime > "$EVIDENCE/webview-logcat.txt" || true
