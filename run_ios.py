#!/usr/bin/env python3
"""Fetch iOS frameworks if missing, then run the Flutter iOS example (macOS only)."""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FW = ROOT / "ios" / "Frameworks"
EXAMPLE = ROOT / "example"
EXAMPLE_IOS_FLUTTER = EXAMPLE / "ios" / "Flutter"
# Flutter iOS device builds need several GB free; a full disk often surfaces as
# "Failed to codesign Flutter.framework … internal error in Code Signing subsystem".
MIN_FREE_BYTES = 4 * 1024 * 1024 * 1024


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


def ensure_disk_space() -> None:
    free = shutil.disk_usage(ROOT).free
    if free >= MIN_FREE_BYTES:
        return
    gb = free / (1024**3)
    die(
        f"only {gb:.1f} GiB free on disk (need ~4 GiB for an iOS build).\n"
        "codesign then fails with 'internal error in Code Signing subsystem'.\n"
        "Free space, e.g.:\n"
        "  rm -rf ~/Library/Developer/Xcode/DerivedData/*\n"
        "  rm -rf example/build\n"
        "then re-run: python3 run_ios.py"
    )


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


def clean_example_build() -> None:
    build = EXAMPLE / "build"
    if build.is_dir():
        print(f"cleaning {build.relative_to(ROOT)}")
        shutil.rmtree(build)


def main() -> None:
    import fp_releases

    if sys.platform != "darwin":
        die("iOS builds need macOS and Xcode. Use python run_android.py on this machine.")
    ensure_disk_space()
    flutter = need("flutter", "Install Flutter and add it to PATH.")
    print(f"{ROOT.name}: ios (flutter)")
    fp_releases.ensure_ios_engine(ROOT, FW, with_bridge=False)
    scrub_stale_flutter_ios_config()
    clean_example_build()
    run([flutter, "pub", "get"])
    run([flutter, "pub", "get"], cwd=EXAMPLE)
    podfile = EXAMPLE / "ios" / "Podfile"
    if podfile.is_file() and shutil.which("pod"):
        run(["pod", "install"], cwd=podfile.parent)
    run([flutter, "run"], cwd=EXAMPLE)


if __name__ == "__main__":
    main()
