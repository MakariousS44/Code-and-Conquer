#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/sandbox_worker/src/main_posix.cpp"

case "$(uname -s)" in
  Linux)
    TAG="linux-x86_64"
    OUT_DIR="$ROOT/sandbox_worker/bin/$TAG"
    mkdir -p "$OUT_DIR"
    if g++ -std=c++17 -O2 -Wall -Wextra -static -o "$OUT_DIR/sandbox_runner" "$SRC" -pthread 2>/dev/null; then
      :
    else
      g++ -std=c++17 -O2 -Wall -Wextra -static-libgcc -static-libstdc++ -o "$OUT_DIR/sandbox_runner" "$SRC" -pthread
    fi
    ;;
  Darwin)
    TAG="macos-arm64"
    OUT_DIR="$ROOT/sandbox_worker/bin/$TAG"
    mkdir -p "$OUT_DIR"
    clang++ -std=c++17 -O2 -Wall -Wextra -arch arm64 -mmacosx-version-min=11.0 -o "$OUT_DIR/sandbox_runner" "$SRC"
    ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

chmod +x "$OUT_DIR/sandbox_runner"
echo "Built $OUT_DIR/sandbox_runner"
