#!/usr/bin/env bash
# Fetch the pinned toolchain into vendor/ (nothing is installed system-wide).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MRUBY_TAG="${MRUBY_TAG:-$(git ls-remote --tags --refs https://github.com/mruby/mruby.git | awk -F/ '{print $3}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)}"
EMSDK_VERSION="${EMSDK_VERSION:-latest}"
cd "$ROOT/vendor"
[ -d mruby ] || git clone --depth 1 --branch "$MRUBY_TAG" https://github.com/mruby/mruby.git
[ -d emsdk ] || git clone --depth 1 https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install "$EMSDK_VERSION"
./emsdk activate "$EMSDK_VERSION"
echo "mruby: $MRUBY_TAG"
