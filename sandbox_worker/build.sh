#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/sandbox_worker/src/main_posix.cpp"

OS_NAME="$(uname -s)"
ARCH="$(uname -m)"

case "$OS_NAME" in
  Linux)
    if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
      echo "linux-x86_64 worker must be built on x86_64 Linux (detected $ARCH)." >&2
      exit 1
    fi
    TAG="linux-x86_64"
    OUT_DIR="$ROOT/sandbox_worker/bin/$TAG"
    if ! TARGET="$(g++ -dumpmachine)"; then
      echo "g++ was not found or could not report its target triple." >&2
      exit 1
    fi
    case "$TARGET" in
      *x86_64*linux*) ;;
      *)
        echo "linux-x86_64 worker requires an x86_64 Linux g++ target (detected ${TARGET:-unknown})." >&2
        exit 1
        ;;
    esac
    mkdir -p "$OUT_DIR"
    if ! g++ -std=c++17 -O2 -Wall -Wextra -static -o "$OUT_DIR/sandbox_runner" "$SRC" -pthread; then
      echo "Linux worker requires a fully static build; install a static libstdc++/libc toolchain." >&2
      exit 1
    fi
    ;;
  Darwin)
    if [ "$ARCH" != "arm64" ]; then
      echo "macos-arm64 worker must be built on Apple Silicon (detected $ARCH)." >&2
      exit 1
    fi
    TAG="macos-arm64"
    OUT_DIR="$ROOT/sandbox_worker/bin/$TAG"
    mkdir -p "$OUT_DIR"
    clang++ -std=c++17 -O2 -Wall -Wextra -arch arm64 -mmacosx-version-min=11.0 -o "$OUT_DIR/sandbox_runner" "$SRC"
    ;;
  *)
    echo "Unsupported OS: $OS_NAME" >&2
    exit 1
    ;;
esac

chmod +x "$OUT_DIR/sandbox_runner"
echo "Built $OUT_DIR/sandbox_runner"
