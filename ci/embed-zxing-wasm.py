#!/usr/bin/env python3
from __future__ import annotations

import base64
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: embed-zxing-wasm.py WEB_ROOT")

    web = Path(sys.argv[1])
    wasm = web / "node_modules/zxing-wasm/dist/reader/zxing_reader.wasm"
    if not wasm.is_file() or wasm.stat().st_size < 100_000:
        raise SystemExit(f"ZXing WASM not found or unexpectedly small: {wasm}")

    encoded = base64.b64encode(wasm.read_bytes()).decode("ascii")
    chunks = [encoded[index:index + 32768] for index in range(0, len(encoded), 32768)]
    destination = web / "receive/zxing-wasm-inline.ts"
    destination.write_text(
        "// Generated during the verified build from the installed zxing-wasm package.\n"
        "// The binary is decoded inside each worker; no fetch or XHR is performed.\n"
        "const encodedChunks = [\n"
        + "".join(f"  {chunk!r},\n" for chunk in chunks)
        + "] as const;\n"
          "const encoded = encodedChunks.join(\"\");\n"
          "const decoded = atob(encoded);\n"
          "const bytes = new Uint8Array(decoded.length);\n"
          "for (let index = 0; index < decoded.length; index += 1) {\n"
          "  bytes[index] = decoded.charCodeAt(index);\n"
          "}\n"
          "export const zxingWasmBinary: Uint8Array = bytes;\n",
        encoding="utf-8",
    )

    if destination.stat().st_size < wasm.stat().st_size:
        raise SystemExit("Generated inline WASM module is unexpectedly small")


if __name__ == "__main__":
    main()
