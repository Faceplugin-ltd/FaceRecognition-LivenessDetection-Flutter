#!/usr/bin/env python3
"""Fetch iOS frameworks if missing, then run the Flutter iOS example (macOS only).

Mirrors the README manual steps: fetch missing native binaries, then the
standard flutter commands for this repo.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IS_WIN = os.name == "nt"


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def which(name: str) -> str | None:
    hits = [shutil.which(name)]
    if IS_WIN:
        hits.extend([shutil.which(name + ".cmd"), shutil.which(name + ".exe")])
    return next((h for h in hits if h), None)


def need(name: str, hint: str) -> str:
    path = which(name)
    if not path:
        die(f"{name} is not on PATH. {hint}")
    return path


def run(args: list[str], cwd: Path | None = None) -> None:
    print("+", " ".join(str(a) for a in args))
    r = subprocess.run(args, cwd=str(cwd or ROOT))
    if r.returncode:
        raise SystemExit(r.returncode)


FW = ROOT / "ios" / "Frameworks"


def main() -> None:
    import fp_releases

    if sys.platform != "darwin":
        die("iOS builds need macOS and Xcode. Use python run_android.py on this machine.")
    flutter = need("flutter", "Install Flutter and add it to PATH.")
    print(f"{ROOT.name}: ios (flutter)")
    fp_releases.ensure_ios_engine(ROOT, FW, with_bridge=False)
    run([flutter, "pub", "get"])
    run([flutter, "pub", "get"], cwd=ROOT / "example")
    podfile = ROOT / "example" / "ios" / "Podfile"
    if podfile.is_file() and which("pod"):
        run(["pod", "install"], cwd=podfile.parent)
    run([flutter, "run"], cwd=ROOT / "example")


if __name__ == "__main__":
    main()
