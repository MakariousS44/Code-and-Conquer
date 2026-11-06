#!/usr/bin/env python3
"""Fetch pinned python-build-standalone runtimes for supported platforms."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

RELEASE_TAG = "20260610"
REPO = "astral-sh/python-build-standalone"
ROOT = Path(__file__).resolve().parents[1]

TARGETS = {
    "linux-x86_64": "x86_64-unknown-linux-gnu",
    "macos-arm64": "aarch64-apple-darwin",
    "windows-x86_64": "x86_64-pc-windows-msvc",
}


def api_json(url: str):
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)


def find_asset(platform: str) -> str:
    target = TARGETS[platform]
    release = api_json(f"https://api.github.com/repos/{REPO}/releases/tags/{RELEASE_TAG}")
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if name.startswith("cpython-3.14") and target in name and name.endswith("install_only_stripped.tar.gz"):
            return name
    raise SystemExit(f"No CPython 3.14 install_only_stripped asset found for {platform} in release {RELEASE_TAG}")


def download(url: str, destination: Path) -> None:
    with urllib.request.urlopen(url, timeout=300) as response, destination.open("wb") as output:
        shutil.copyfileobj(response, output, length=1024 * 1024)


def verify_checksum(asset_name: str, archive: Path) -> None:
    checksum_name = asset_name + ".sha256"
    url = f"https://github.com/{REPO}/releases/download/{RELEASE_TAG}/{checksum_name}"
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            expected = response.read().decode().split()[0].strip()
    except Exception:
        print(f"warning: no checksum asset for {asset_name}; skipping verification", file=sys.stderr)
        return
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != expected:
        raise SystemExit(f"Checksum mismatch for {asset_name}: expected {expected}, got {digest}")


def fetch(platform: str) -> None:
    asset_name = find_asset(platform)
    url = f"https://github.com/{REPO}/releases/download/{RELEASE_TAG}/{asset_name}"
    destination_root = ROOT / "sandbox_worker" / "runtime" / platform / "python"
    destination_root.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as temp_dir:
        archive = Path(temp_dir) / asset_name
        print(f"Downloading {asset_name} ...")
        download(url, archive)
        verify_checksum(asset_name, archive)
        extract_dir = Path(temp_dir) / "extract"
        extract_dir.mkdir()
        with tarfile.open(archive, "r:gz") as tar:
            tar.extractall(extract_dir, filter="data")
        source = extract_dir / "python"
        if not source.is_dir():
            raise SystemExit(f"Archive {asset_name} did not contain a top-level python/ directory")
        if destination_root.exists():
            shutil.rmtree(destination_root)
        shutil.copytree(source, destination_root, symlinks=False)

    print(f"Installed Python runtime to {destination_root}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=sorted(TARGETS), action="append", help="Platform tag to fetch; repeatable")
    parser.add_argument("--all", action="store_true", help="Fetch every supported platform")
    args = parser.parse_args()
    platforms = sorted(TARGETS) if args.all else (args.platform or [next(iter(TARGETS))])
    for platform in platforms:
        fetch(platform)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
