#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match in {path}, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: final-functional-fixes.py WEB_ROOT ANDROID_ROOT")
    web = Path(sys.argv[1])
    android = Path(sys.argv[2])

    index = web / "index.html"
    replace_once(index, 'href="./send/"', 'href="./send/index.html"', "send route")
    replace_once(index, 'href="./receive/"', 'href="./receive/index.html"', "receive route")
    replace_once(index, 'Offline · SHA-256 · v0.2', 'SHA-256 · v0.4', "home badge")
    diagnostics = '''    <section class="panel diagnostics" aria-live="polite">
      <div class="panel-title">Lokaler Systemcheck</div>
      <div id="selftest-status" class="status pending">Wird ausgeführt …</div>
      <div id="selftest-details" class="hint left"></div>
      <button id="selftest-run" class="secondary" type="button">Erneut prüfen</button>
    </section>

    <p class="hint">
      Die Anwendung besitzt keine Internet-Berechtigung. Dateien verlassen das Gerät nur als Licht über den Bildschirm.
    </p>
    <script type="module" src="./main.ts"></script>
'''
    replace_once(index, diagnostics, "", "remove visible diagnostics")

    for rel in ("send/index.html", "receive/index.html"):
        replace_once(web / rel, 'href="../"', 'href="../index.html"', f"explicit back route {rel}")

    style = web / "shared/style.css"
    replace_once(style, '  --safe-top: env(safe-area-inset-top, 0px);', '  --safe-top: 0px;', "native top inset")
    replace_once(style, '  --safe-bottom: env(safe-area-inset-bottom, 0px);', '  --safe-bottom: 0px;', "native bottom inset")

    tsconfig = web / "tsconfig.json"
    text = tsconfig.read_text(encoding="utf-8")
    text = text.replace('    "main.ts",\n', '')
    tsconfig.write_text(text, encoding="utf-8")
    (web / "main.ts").unlink(missing_ok=True)

    for rel in ("package.json", "package-lock.json"):
        path = web / rel
        path.write_text(path.read_text(encoding="utf-8").replace('"version": "0.2.0"', '"version": "0.4.0"'), encoding="utf-8")

    worker = web / "receive/worker.ts"
    warmup = '''void readBarcodes(new ImageData(8, 8), { formats: ["QRCode"] })
  .catch(() => undefined)
  .then(() => ctx.postMessage({ id: -1, bytes: null, ms: 0 }));
'''
    warmup_fixed = '''void readBarcodes(new ImageData(8, 8), { formats: ["QRCode"] })
  .then(() => ctx.postMessage({ id: -1, bytes: null, ms: 0 }))
  .catch((error: unknown) => ctx.postMessage({
    id: -1,
    bytes: null,
    ms: 0,
    error: error instanceof Error ? error.message.slice(0, 160) : "wasm-init-failed",
  }));
'''
    replace_once(worker, warmup, warmup_fixed, "report decoder warmup")

    receiver = web / "receive/main.ts"
    replace_once(
        receiver,
        '''function spawnWorkers(count: number): void {
  terminateWorkers();
''',
        '''function spawnWorkers(count: number): void {
  terminateWorkers();
  (window as Window & { __decimenDecoderReady?: string }).__decimenDecoderReady = "pending";
''',
        "decoder pending state",
    )
    replace_once(
        receiver,
        '''      if (message.id === -1) return;
      busy[slot] = false;
''',
        '''      if (message.id === -1) {
        const state = window as Window & { __decimenDecoderReady?: string };
        state.__decimenDecoderReady = message.error ? `failed:${message.error}` : "ready";
        if (message.error) setStatus("error", "QR-Decoder konnte nicht geladen werden.");
        return;
      }
      busy[slot] = false;
''',
        "decoder warmup state",
    )
    replace_once(
        receiver,
        '''    worker.onerror = () => {
      busy[slot] = false;
      setStatus("error", "Ein QR-Decoder ist ausgefallen. Kamera bitte neu starten.");
    };
''',
        '''    worker.onerror = () => {
      busy[slot] = false;
      (window as Window & { __decimenDecoderReady?: string }).__decimenDecoderReady = "failed:worker-error";
      setStatus("error", "Ein QR-Decoder ist ausgefallen. Kamera bitte neu starten.");
    };
''',
        "decoder worker error state",
    )

    activity = android / "app/src/main/java/dev/decimen/optical/MainActivity.java"
    text = activity.read_text(encoding="utf-8")
    text = text.replace("import android.Manifest;\n", "import android.Manifest;\nimport android.annotation.SuppressLint;\n")
    text = text.replace("import android.content.pm.PackageManager;\n", "import android.content.pm.ApplicationInfo;\nimport android.content.pm.PackageManager;\n")
    text = text.replace('private static final String ASSET_ROOT = "/assets/www/";', 'private static final String ASSET_ROOT = "/assets/";')
    text = text.replace(
        '''        registerActivityResults();
        configureWebView();
        setContentView(webView);
        applySystemInsets();
        configureBackNavigation();
''',
        '''        registerActivityResults();
        configureWebView();
        applySystemInsets();
        setContentView(webView);
        ViewCompat.requestApplyInsets(webView);
        configureBackNavigation();
''',
    )
    text = text.replace("    private void configureWebView() {", '    @SuppressLint({"SetJavaScriptEnabled", "WebViewApiAvailability"})\n    private void configureWebView() {')
    text = text.replace("WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG);", "WebView.setWebContentsDebuggingEnabled(isDebuggable());")
    text = text.replace("        if (BuildConfig.DEBUG) {", "        if (isDebuggable()) {")
    text = text.replace(
        "    private String resolveDeviceModel() {\n",
        '''    private boolean isDebuggable() {
        return (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    }

    private String resolveDeviceModel() {
''',
    )
    activity.write_text(text, encoding="utf-8")

    build = android / "app/build.gradle"
    text = build.read_text(encoding="utf-8")
    text = text.replace("versionCode 3", "versionCode 4").replace("versionName '0.3.0'", "versionName '0.4.0'")
    build.write_text(text, encoding="utf-8")

    test = android / "app/src/androidTest/java/dev/decimen/optical/DeviceCompatibilityTest.java"
    test.write_text(TEST_SOURCE, encoding="utf-8")


TEST_SOURCE = r'''package dev.decimen.optical;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.webkit.WebView;

import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.UiDevice;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Predicate;

@RunWith(AndroidJUnit4.class)
public final class DeviceCompatibilityTest {
    private static final String ROOT = "https://appassets.androidplatform.net/assets/";

    @Test
    public void functionalApplicationRunsOnPixelProfile() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        int expectedSdk = Integer.parseInt(InstrumentationRegistry.getArguments()
                .getString("expected_sdk", String.valueOf(Build.VERSION.SDK_INT)));
        assertEquals(expectedSdk, Build.VERSION.SDK_INT);
        assertEquals(PackageManager.PERMISSION_DENIED,
                context.getPackageManager().checkPermission(Manifest.permission.INTERNET, context.getPackageName()));
        assertNotNull(WebView.getCurrentWebViewPackage());
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
                .executeShellCommand("pm grant " + context.getPackageName() + " android.permission.CAMERA");

        Intent intent = new Intent(context, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK)
                .putExtra(MainActivity.EXTRA_TEST_PROFILE, "pixel9a");
        try (ActivityScenario<MainActivity> scenario = ActivityScenario.launch(intent)) {
            waitForJs(scenario, "document.readyState", value -> value.contains("complete"), 30_000);
            String home = eval(scenario, "JSON.stringify({text:document.body.innerText,self:!!document.getElementById('selftest-status')})");
            assertTrue(home, !home.contains("SYSTEMCHECK") && !home.contains("Dateien verlassen") && home.contains("\\\"self\\\":false"));
            AtomicInteger topPadding = new AtomicInteger();
            scenario.onActivity(activity -> topPadding.set(activity.getWebViewForTests().getPaddingTop()));
            assertTrue("Status-bar/cutout inset must be applied natively", topPadding.get() > 0);

            eval(scenario, "(document.querySelector('a.action-card[href*=send]')?.click(),'clicked')");
            waitForJs(scenario, "location.pathname", value -> value.contains("/assets/send/index.html"), 30_000);
            String selectFile = eval(scenario, "(() => { const i=document.querySelector('input[type=file]'); if(!i) return 'missing'; const d=new DataTransfer(); d.items.add(new File([new Uint8Array(32768)],'runtime-test.bin',{type:'application/octet-stream'})); i.files=d.files; i.dispatchEvent(new Event('change',{bubbles:true})); return 'selected'; })()");
            assertTrue(selectFile, selectFile.contains("selected"));
            String sender = waitForJs(scenario,
                    "JSON.stringify({canvas:document.getElementById('qr')?.width||0,status:document.getElementById('specs')?.textContent||'',cls:document.getElementById('specs')?.className||''})",
                    value -> value.matches(".*\\\\\"canvas\\\\\":[1-9][0-9]{2,}.*") && !value.contains("Fehler"), 90_000);
            assertTrue(sender, sender.contains("status ok"));

            load(scenario, ROOT + "receive/index.html");
            eval(scenario, "(document.getElementById('start')?.click(),'clicked')");
            String receiver = waitForJs(scenario,
                    "JSON.stringify({decoder:window.__decimenDecoderReady||'',stream:!!document.getElementById('video')?.srcObject,status:document.getElementById('stats')?.textContent||''})",
                    value -> value.contains("\\\"decoder\\\":\\\"ready\\\"") && value.contains("\\\"stream\\\":true"), 90_000);
            assertTrue(receiver, !receiver.contains("failed:") && !receiver.contains("konnte nicht geladen"));

            File directory = context.getExternalFilesDir(null);
            if (directory != null) {
                UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
                        .takeScreenshot(new File(directory, "functional-pixel9a.png"), 1.0f, 90);
            }
        }
    }

    private static void load(ActivityScenario<MainActivity> scenario, String url) throws Exception {
        scenario.onActivity(activity -> activity.getWebViewForTests().loadUrl(url));
        waitForJs(scenario, "document.readyState", value -> value.contains("complete"), 30_000);
    }

    private static String waitForJs(ActivityScenario<MainActivity> scenario, String expression,
                                    Predicate<String> predicate, long timeoutMs) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs);
        String last = "";
        while (System.nanoTime() < deadline) {
            last = eval(scenario, expression);
            if (predicate.test(last)) return last;
            Thread.sleep(250);
        }
        throw new AssertionError("Timed out: " + expression + " last=" + last);
    }

    private static String eval(ActivityScenario<MainActivity> scenario, String expression) throws Exception {
        CountDownLatch latch = new CountDownLatch(1);
        AtomicReference<String> result = new AtomicReference<>("null");
        scenario.onActivity(activity -> activity.getWebViewForTests().evaluateJavascript(
                "(() => { try { return (" + expression + "); } catch (e) { return 'JS_ERROR:' + e; } })()",
                value -> { result.set(value == null ? "null" : value); latch.countDown(); }));
        if (!latch.await(10, TimeUnit.SECONDS)) throw new AssertionError("evaluateJavascript timed out");
        return result.get();
    }
}
'''


if __name__ == "__main__":
    main()
