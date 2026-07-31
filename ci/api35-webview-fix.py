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
    if len(sys.argv) != 2:
        raise SystemExit("usage: api35-webview-fix.py ANDROID_ROOT")

    android = Path(sys.argv[1])
    activity = android / "app/src/main/java/dev/decimen/optical/MainActivity.java"

    replace_once(
        activity,
        '''                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
                .build();''',
        '''                .addPathHandler("/assets/", path -> {
                    try {
                        return new WebResourceResponse(
                                assetMimeType(path), assetEncoding(path), getAssets().open(path));
                    } catch (IOException error) {
                        Log.w(TAG, "Local asset not found: " + path);
                        return null;
                    }
                })
                .build();''',
        "custom local asset handler",
    )

    replace_once(
        activity,
        "        settings.setBlockNetworkLoads(true);",
        '''        // appassets uses an HTTPS-shaped local origin. Android 15 WebView needs
        // network-shaped requests enabled for synchronous WASM XHR. Every non-appassets
        // request is still rejected by LockedWebViewClient, and the manifest has no INTERNET permission.
        settings.setBlockNetworkLoads(false);''',
        "allow intercepted appassets requests",
    )

    marker = '''    private static WebResourceResponse blockedResponse() {
'''
    helpers = '''    private static String assetMimeType(String path) {
        String lower = path.toLowerCase(Locale.ROOT);
        if (lower.endsWith(".wasm")) return "application/wasm";
        if (lower.endsWith(".html")) return "text/html";
        if (lower.endsWith(".js") || lower.endsWith(".mjs")) return "text/javascript";
        if (lower.endsWith(".css")) return "text/css";
        if (lower.endsWith(".json")) return "application/json";
        if (lower.endsWith(".svg")) return "image/svg+xml";
        if (lower.endsWith(".png")) return "image/png";
        if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
        if (lower.endsWith(".webp")) return "image/webp";
        if (lower.endsWith(".ico")) return "image/x-icon";
        if (lower.endsWith(".txt")) return "text/plain";
        return "application/octet-stream";
    }

    @Nullable
    private static String assetEncoding(String path) {
        String lower = path.toLowerCase(Locale.ROOT);
        return lower.endsWith(".html") || lower.endsWith(".js") || lower.endsWith(".mjs")
                || lower.endsWith(".css") || lower.endsWith(".json")
                || lower.endsWith(".svg") || lower.endsWith(".txt") ? "utf-8" : null;
    }

'''
    replace_once(activity, marker, helpers + marker, "asset MIME helpers")


if __name__ == "__main__":
    main()
