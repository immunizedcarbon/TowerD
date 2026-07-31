# Decimen Optical Transfer 0.3.0 — Sicherheits- und Kompatibilitätsprüfung

## Zielgeräte

- Google Pixel 9a: stabile Android-17-Plattform/API 37, 1080 × 2424, gerätespezifisches Pixel-9a-Profil.
- Google Pixel 8a: stabile Android-17-Plattform/API 37, 1080 × 2400, gerätespezifisches Pixel-8a-Profil.
- Samsung Galaxy Tab S5e LTE (`gts4lv`, Modelle SM-T725/SM-T727): LineageOS 22.2 auf Android 15/API 35, 1600 × 2560, konservatives 3-GB-Emulatorprofil unterhalb der physischen 4-GB-Ausstattung.

## Sicherheitsänderungen gegenüber dem Upstream-Prototyp

- Protokollversion 2 mit vollständigem SHA-256-Digest in jedem QR-Rahmen.
- Strikte Grenzen vor jeder Decoder-Allokation: maximal 4 MiB Datei, maximal 2 KiB Metadaten, begrenzte Block- und Framezahlen.
- Manipulierte oder widersprüchliche QR-Header werden verworfen; ein fremder QR-Strom kann einen aktiven Transfer nicht fortlaufend zurücksetzen.
- Eine Datei wird erst nach vollständiger SHA-256-Prüfung angezeigt oder freigegeben.
- Android prüft den Digest vor dem Speichern ein zweites Mal.
- Speichern erfolgt in begrenzten 192-KiB-Nachrichten über eine origin-gebundene AndroidX-WebKit-Schnittstelle und den System-Dateidialog.
- Keine Internet-Berechtigung, keine allgemeine Speicherberechtigung, kein Klartextverkehr, keine Backups.
- WebView-Datei- und Content-Zugriff sind deaktiviert; nur gebündelte Assets unter `appassets.androidplatform.net` werden geladen.
- Fremde Navigation, Downloads, SSL-Ausnahmen, Audioaufnahme und nicht angeforderte WebView-Ressourcen werden abgelehnt.
- Kamera wird nur auf der lokalen Empfangsseite freigegeben und beim Hintergrundwechsel beendet.
- Bildschirm-Wakelocks werden beim Pausieren und beim Wechsel in den Hintergrund freigegeben.
- Release-Build ist nicht debuggbar, R8-optimiert und mit einer isolierten Release-Signatur versehen.

## Moderne Android-Basis

- Mindest-SDK 35 für LineageOS 22.2/Android 15.
- Ziel- und Compile-SDK 37 für Android 17.
- Android Gradle Plugin 9.3.1, Gradle 9.5 und Java 17.
- Eine architekturunabhängige APK ohne native ABI-Bibliotheken; dieselbe Datei läuft auf den ARM64-Zielgeräten.

## Automatisierte Prüfungen

- TypeScript-Strict-Check und Produktionsbuild.
- `npm audit` ohne bekannte Low/Moderate/High/Critical-Schwachstellen.
- Semgrep über TypeScript, JavaScript und Android-Java.
- Android Lint für den Release-Build.
- APK-Signaturprüfung, Manifestprüfung und SHA-256-Prüfsumme.
- Verifikation: Mindest-SDK 35, Ziel-SDK 37, `CAMERA` vorhanden, `INTERNET` nicht vorhanden, Release nicht debuggbar.
- Gerätematrix: lokaler Selbsttest (Fountain-Code, Frameverlust, SHA-256, feindlicher Header, QR-Encode/ZXing-WASM-Decode), Sender-Rendering, Kameraöffnung, blockierter Netzwerkzugriff und signierter Release-Start.

## Aussagegrenze

Die Tests decken Build, Installation, WebView, Kameraanforderung, QR-/Fountain-Kernlogik, Integrität und Sicherheitsgrenzen reproduzierbar ab. Autofokus, Displayflimmern, reale Lichtverhältnisse, physische Kameraoptik und thermische Drosselung können nur mit den drei echten Geräten abschließend geprüft werden. Eine absolute Funktionsgarantie für jedes individuelle Gerät wäre ohne diesen Hardwaretest nicht seriös.
