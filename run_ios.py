#!/usr/bin/env python3
"""Fetch iOS frameworks if missing, then run the Flutter iOS example (macOS only)."""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FW = ROOT / "ios" / "Frameworks"
EXAMPLE_IOS_FLUTTER = ROOT / "example" / "ios" / "Flutter"


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def need(name: str, hint: str) -> str:
    path = shutil.which(name)
    if not path:
        die(f"{name} is not on PATH. {hint}")
    return path


def run(args: list[str], cwd: Path | None = None) -> None:
    print("+", " ".join(str(a) for a in args))
    code = subprocess.run(args, cwd=str(cwd or ROOT)).returncode
    if code:
        raise SystemExit(code)


def scrub_stale_flutter_ios_config() -> None:
    """Drop machine-local Flutter iOS outputs so a clone does not keep foreign paths."""
    for name in ("Generated.xcconfig", "flutter_export_environment.sh", "Flutter.podspec"):
        path = EXAMPLE_IOS_FLUTTER / name
        if path.is_file():
            path.unlink()
            print(f"removed stale {path.relative_to(ROOT)}")
    ephemeral = EXAMPLE_IOS_FLUTTER / "ephemeral"
    if ephemeral.is_dir():
        shutil.rmtree(ephemeral)
        print(f"removed stale {ephemeral.relative_to(ROOT)}/")


def main() -> None:
    import fp_releases

    if sys.platform != "darwin":
        die("iOS builds need macOS and Xcode. Use python run_android.py on this machine.")
    flutter = need("flutter", "Install Flutter and add it to PATH.")
    print(f"{ROOT.name}: ios (flutter)")
    # Downloads runtime.zip when incomplete; always slices FacePluginSDK/FacePPlugin/FaceDetect.
    fp_releases.ensure_ios_engine(ROOT, FW, with_bridge=False)
    scrub_stale_flutter_ios_config()
    run([flutter, "pub", "get"])
    run([flutter, "pub", "get"], cwd=ROOT / "example")
    podfile = ROOT / "example" / "ios" / "Podfile"
    if podfile.is_file() and shutil.which("pod"):
        run(["pod", "install"], cwd=podfile.parent)
    run([flutter, "run"], cwd=ROOT / "example")


if __name__ == "__main__":
    main()
