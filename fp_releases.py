#!/usr/bin/env python3
"""Download FacePlugin native runtimes from GitHub Releases (solo-clone helper)."""

from __future__ import annotations

import shutil
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

GH = "https://github.com/Faceplugin-ltd"
REC_ANDROID = "FaceRecognition-LivenessDetection-Android"
REC_IOS = "FaceRecognition-LivenessDetection-iOS"
LIV_ANDROID = "FaceLivenessDetection-Android"
LIV_IOS = "FaceLivenessDetection-iOS"

AAR_NAME = "facerecognitionsdk.aar"
AAR_URL = f"{GH}/{REC_ANDROID}/releases/download/latest/{AAR_NAME}"
AAR_PAGE = f"{GH}/{REC_ANDROID}/releases/tag/latest"
RUNTIME_ZIP_URL = f"{GH}/{REC_IOS}/releases/download/latest/runtime.zip"
RUNTIME_PAGE = f"{GH}/{REC_IOS}/releases/tag/latest"
BRIDGE_ZIP_URL = f"{GH}/{LIV_IOS}/releases/download/latest/bridge.zip"
BRIDGE_PAGE = f"{GH}/{LIV_IOS}/releases/tag/latest"
LIVENESS_LIBS_URL = f"{GH}/{LIV_ANDROID}/releases/download/latest/liveness-libs.zip"
LIVENESS_LIBS_PAGE = f"{GH}/{LIV_ANDROID}/releases/latest"

ENGINE_IOS = (
    "facerecognitionsdk.framework",
    "FacePluginSDK.xcframework",
    "FacePlugin.xcframework",
    "FaceDetect.xcframework",
)
BRIDGE_IOS = ("FaceLivenessBridge.xcframework", "FaceLivenessKit.xcframework")
LIVENESS_AARS = ("face-liveness-kit.aar", "face-liveness-active.aar")
# ios-arm64 slice name inside each xcframework → flat .framework Binding links
SLICES = (
    ("FaceLivenessBridge.xcframework", "FaceLivenessBridge.framework"),
    ("FaceLivenessKit.xcframework", "FaceLivenessKit.framework"),
    ("FacePluginSDK.xcframework", "FacePluginSDK.framework"),
    ("FacePlugin.xcframework", "FacePPlugin.framework"),
    ("FaceDetect.xcframework", "FaceDetect.framework"),
)


def _die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def _rm(path: Path) -> None:
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()


def _download(url: str, dest: Path, page: str) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url}")
    try:
        with urllib.request.urlopen(url, timeout=300) as resp, dest.open("wb") as out:
            shutil.copyfileobj(resp, out)
    except (urllib.error.URLError, OSError) as exc:
        dest.unlink(missing_ok=True)
        _die(f"download failed: {exc}\nGet the file from {page}")


def _ok(path: Path) -> bool:
    """True if path is a real framework/xcframework (not Info.plist-only) or non-empty file."""
    if path.name.endswith(".xcframework"):
        fws = sorted(path.glob("ios-arm64/*.framework"))
        path = fws[0] if fws else path
    if path.name.endswith(".framework"):
        binary = path / path.stem
        return binary.is_file() and binary.stat().st_size > 0
    return path.is_file() and path.stat().st_size > 0


def _repair_stubs(fw: Path) -> None:
    """zipfile turns framework symlinks into tiny text files; codesign needs real binaries."""
    if not fw.is_dir():
        return
    for child in fw.iterdir():
        if not child.is_file() or child.is_symlink() or child.stat().st_size > 64:
            continue
        try:
            name = child.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        target = fw / name
        if not name or "/" in name or not target.is_file() or target.stat().st_size <= 64:
            continue
        child.unlink(missing_ok=True)
        shutil.copy2(target, child)


def _put(src: Path, dest: Path) -> None:
    _rm(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dest, symlinks=False)
        for fw in ([dest] if dest.name.endswith(".framework") else dest.rglob("*.framework")):
            _repair_stubs(fw)
    else:
        shutil.copy2(src, dest)
    print(f"staged {dest}")


def _copy_missing(src: Path, dest: Path) -> bool:
    if _ok(dest) or not _ok(src):
        return False
    _put(src, dest)
    return True


def _slice(dest: Path) -> None:
    for xc, preferred in SLICES:
        slice_dir = dest / xc / "ios-arm64"
        src = slice_dir / preferred
        if not src.is_dir():
            found = list(slice_dir.glob("*.framework")) if slice_dir.is_dir() else []
            src = found[0] if found else None
        if src is None or not src.is_dir():
            continue
        out = dest / (preferred if src.name == preferred else src.name)
        if not _ok(out):
            _put(src, out)
        else:
            _repair_stubs(out)
    flat = dest / "facerecognitionsdk.framework"
    if flat.is_dir():
        _repair_stubs(flat)


def _extract_zip(zpath: Path, out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zpath) as zf:
        for member in zf.namelist():
            if not member.startswith("__MACOSX"):
                zf.extract(member, out)


def ensure_engine_aar(root: Path, dest: Path) -> None:
    if dest.is_file() and dest.stat().st_size > 0:
        return
    apps = root.parent
    for rel in (
        "Face-Recognition-LivenessDetection-Android/libs/facerecognitionsdk.aar",
        "Face-LivenessDetection-Android/libs/facerecognitionsdk.aar",
    ):
        if _copy_missing(apps / rel, dest):
            return
    with tempfile.TemporaryDirectory(prefix="fp-aar-") as tmp:
        tmp_aar = Path(tmp) / AAR_NAME
        _download(AAR_URL, tmp_aar, AAR_PAGE)
        _put(tmp_aar, dest)


def ensure_liveness_libs(root: Path, libs_dir: Path) -> None:
    libs_dir.mkdir(parents=True, exist_ok=True)
    if all((libs_dir / n).is_file() for n in LIVENESS_AARS):
        return
    native = root.parent / "Face-LivenessDetection-Android"
    for name in LIVENESS_AARS:
        stem = name.removesuffix(".aar")
        for cand in (
            native / "libs" / name,
            native / stem / "build" / "outputs" / "aar" / f"{stem}-release.aar",
        ):
            if _copy_missing(cand, libs_dir / name):
                break
    if all((libs_dir / n).is_file() for n in LIVENESS_AARS):
        return
    with tempfile.TemporaryDirectory(prefix="fp-liv-") as tmp:
        zpath = Path(tmp) / "liveness-libs.zip"
        _download(LIVENESS_LIBS_URL, zpath, LIVENESS_LIBS_PAGE)
        _extract_zip(zpath, Path(tmp))
        for name in LIVENESS_AARS:
            src = Path(tmp) / name
            if not src.is_file():
                _die(f"liveness-libs.zip missing {name}\nDownload from {LIVENESS_LIBS_PAGE}")
            _put(src, libs_dir / name)


def ensure_ios_engine(root: Path, dest: Path, *, with_bridge: bool = False) -> None:
    need = list(ENGINE_IOS) + (list(BRIDGE_IOS) if with_bridge else [])
    for n in need:
        p = dest / n
        if p.exists() and not _ok(p):
            print(f"removing incomplete {p}")
            _rm(p)

    apps = root.parent
    if not all(_ok(dest / n) for n in need):
        for sibling in (
            apps / "Face-Recognition-LivenessDetection-iOS",
            apps / "Face-LivenessDetection-iOS",
        ):
            if all(_ok(sibling / n) for n in ENGINE_IOS):
                dest.mkdir(parents=True, exist_ok=True)
                for n in ENGINE_IOS:
                    _copy_missing(sibling / n, dest / n)
                break
        if with_bridge:
            liv = apps / "Face-LivenessDetection-iOS"
            for n in BRIDGE_IOS:
                for cand in (liv / n, liv / "build" / "xcframeworks" / n):
                    if _copy_missing(cand, dest / n):
                        break

    if not all(_ok(dest / n) for n in need):
        with tempfile.TemporaryDirectory(prefix="fp-ios-") as tmp:
            tmp_path = Path(tmp)
            if not all(_ok(dest / n) for n in ENGINE_IOS):
                zpath = tmp_path / "runtime.zip"
                _download(RUNTIME_ZIP_URL, zpath, RUNTIME_PAGE)
                extracted = tmp_path / "runtime"
                _extract_zip(zpath, extracted)
                for n in ENGINE_IOS:
                    src = extracted / n
                    if not _ok(src):
                        _die(f"runtime.zip missing a usable {n}\nGet it from {RUNTIME_PAGE}")
                    _put(src, dest / n)
            if with_bridge and not all(_ok(dest / n) for n in BRIDGE_IOS):
                zpath = tmp_path / "bridge.zip"
                _download(BRIDGE_ZIP_URL, zpath, BRIDGE_PAGE)
                extracted = tmp_path / "bridge"
                _extract_zip(zpath, extracted)
                for n in BRIDGE_IOS:
                    src = extracted / n
                    if not _ok(src):
                        _die(
                            f"bridge.zip missing a usable {n}. "
                            f"Rebuild with Face-LivenessDetection-iOS/scripts/build_bridge.sh "
                            f"and re-upload to {BRIDGE_PAGE}"
                        )
                    _put(src, dest / n)

    missing = [n for n in need if not _ok(dest / n)]
    if missing:
        msg = f"missing iOS runtimes: {', '.join(missing)}\nEngine: {RUNTIME_PAGE}"
        if with_bridge:
            msg += f"\nBridge: {BRIDGE_PAGE}"
        _die(msg)
    _slice(dest)
