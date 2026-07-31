#!/usr/bin/env python3
from __future__ import annotations

import shutil
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: functional-lint-fixes.py ANDROID_ROOT")

    android = Path(sys.argv[1])
    activity = android / "app/src/main/java/dev/decimen/optical/MainActivity.java"
    text = activity.read_text(encoding="utf-8")
    old = "    private void installSaveBridge() {"
    new = '    @SuppressLint("RequiresFeature")\n' + old
    if text.count(old) != 1:
        raise SystemExit("installSaveBridge declaration not found exactly once")
    activity.write_text(text.replace(old, new, 1), encoding="utf-8")

    obsolete = android / "app/src/main/res/mipmap-anydpi-v26"
    destination = android / "app/src/main/res/mipmap-anydpi"
    if obsolete.exists():
        destination.mkdir(parents=True, exist_ok=True)
        for child in obsolete.iterdir():
            target = destination / child.name
            if target.exists():
                if target.is_dir():
                    shutil.rmtree(target)
                else:
                    target.unlink()
            shutil.move(str(child), str(target))
        obsolete.rmdir()


if __name__ == "__main__":
    main()
