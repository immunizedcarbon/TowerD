#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path


def replace_all_checked(path: Path, old: str, new: str, minimum: int, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count < minimum:
        raise SystemExit(f"{label}: expected at least {minimum} matches in {path}, found {count}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match in {path}, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: functional-startup-fixes.py WEB_ROOT ANDROID_ROOT")

    web = Path(sys.argv[1])
    android = Path(sys.argv[2])

    # Embedded resources such as the ZXing WASM module are same-origin fetches.
    # External traffic remains impossible because the native WebView blocks it
    # and the Android manifest intentionally has no INTERNET permission.
    html_files = [web / "index.html", web / "send/index.html", web / "receive/index.html"]
    for html in html_files:
        replace_all_checked(html, "connect-src 'none'", "connect-src 'self'", 1, f"same-origin CSP {html.name}")

    send_html = web / "send/index.html"
    replace_once(
        send_html,
        '''            <option value="sample-small" selected>Testbild · ca. 512 KB</option>
            <option value="sample-large">Testbild · ca. 2 MB</option>
            <option value="file">Eigene Datei …</option>''',
        '''            <option value="file" selected>Eigene Datei …</option>
            <option value="sample-small">Testbild · ca. 512 KB</option>
            <option value="sample-large">Testbild · ca. 2 MB</option>''',
        "default local file source",
    )

    send_main = web / "send/main.ts"
    replace_once(
        send_main,
        "const device = detectDevice();\nprofileEl.textContent = device.label;",
        '''const device = detectDevice();
profileEl.textContent = device.label;
(window as Window & { __decimenSenderReady?: boolean }).__decimenSenderReady = false;''',
        "sender readiness initialization",
    )
    replace_once(
        send_main,
        "document.addEventListener(\"visibilitychange\", () => {",
        '''(window as Window & { __decimenSenderReady?: boolean }).__decimenSenderReady = true;

document.addEventListener("visibilitychange", () => {''',
        "sender readiness publication",
    )

    receive_main = web / "receive/main.ts"
    replace_once(
        receive_main,
        "startBtn.addEventListener(\"click\", () => void start());",
        '''(window as Window & { __decimenReceiverReady?: boolean }).__decimenReceiverReady = true;
startBtn.addEventListener("click", () => void start());''',
        "receiver readiness publication",
    )

    test = android / "app/src/androidTest/java/dev/decimen/optical/DeviceCompatibilityTest.java"
    replace_once(
        test,
        '''            waitForJs(scenario, "location.pathname", value -> value.contains("/assets/send/index.html"), 30_000);
            String selectFile = eval(scenario, "(() => { const i=document.querySelector('input[type=file]'); if(!i) return 'missing'; const d=new DataTransfer(); d.items.add(new File([new Uint8Array(32768)],'runtime-test.bin',{type:'application/octet-stream'})); i.files=d.files; i.dispatchEvent(new Event('change',{bubbles:true})); return 'selected'; })()");
            assertTrue(selectFile, selectFile.contains("selected"));''',
        '''            waitForJs(scenario, "location.pathname", value -> value.contains("/assets/send/index.html"), 30_000);
            waitForJs(scenario, "window.__decimenSenderReady === true", value -> value.contains("true"), 30_000);
            String selectFile = eval(scenario, "(() => { const i=document.querySelector('input[type=file]'); if(!i) return 'missing'; const d=new DataTransfer(); d.items.add(new File([new Uint8Array(32768)],'runtime-test.bin',{type:'application/octet-stream'})); i.files=d.files; const source=document.getElementById('cfg-source'); if(source) source.value='file'; i.dispatchEvent(new Event('change',{bubbles:true})); return i.files?.length===1 ? 'selected' : 'not-selected'; })()");
            assertTrue(selectFile, selectFile.contains("selected") && !selectFile.contains("not-selected"));''',
        "sender test readiness",
    )
    replace_once(
        test,
        '''            load(scenario, ROOT + "receive/index.html");
            eval(scenario, "(document.getElementById('start')?.click(),'clicked')");''',
        '''            load(scenario, ROOT + "receive/index.html");
            waitForJs(scenario, "window.__decimenReceiverReady === true", value -> value.contains("true"), 30_000);
            String cameraClick = eval(scenario, "(() => { const b=document.getElementById('start'); if(!(b instanceof HTMLButtonElement)) return 'missing'; b.click(); return 'clicked'; })()");
            assertTrue(cameraClick, cameraClick.contains("clicked"));''',
        "receiver test readiness",
    )


if __name__ == "__main__":
    main()
