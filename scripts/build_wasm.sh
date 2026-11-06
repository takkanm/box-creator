#!/usr/bin/env bash
# Builds docs/box.js and docs/box.wasm. Run scripts/setup_toolchain.sh first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MRUBY="$ROOT/vendor/mruby"
OUT="$MRUBY/build/box"
SOURCES=(earcut outline mesh layout params model api)

EMSDK_QUIET=1 source "$ROOT/vendor/emsdk/emsdk_env.sh"

(cd "$MRUBY" && MRUBY_CONFIG="$ROOT/wasm/build_config.rb" rake -j8)

mkdir -p "$OUT"
FILES=()
for name in "${SOURCES[@]}"; do FILES+=("$ROOT/ruby/lib/box_creator/$name.rb"); done
"$MRUBY/build/host/bin/mrbc" -Bbox_irep -o "$OUT/box_irep.c" "${FILES[@]}"

emcc -O2 -fwasm-exceptions -sSUPPORT_LONGJMP=wasm \
  -DMRB_NO_BOXING -DMRB_INT64 -DMRB_STR_LENGTH_MAX=0 \
  -I"$MRUBY/include" -I"$MRUBY/build/wasm/include" \
  "$ROOT/wasm/box_api.c" "$OUT/box_irep.c" "$MRUBY/build/wasm/lib/libmruby.a" \
  -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createBoxModule \
  -sENVIRONMENT=web,worker,node \
  -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=2097152 -sINITIAL_MEMORY=33554432 \
  -sEXPORTED_FUNCTIONS=_box_generate,_malloc,_free \
  -sEXPORTED_RUNTIME_METHODS=cwrap,HEAPU8,HEAP32,stringToNewUTF8 \
  -o "$ROOT/docs/box.js"

ls -la "$ROOT/docs/box.js" "$ROOT/docs/box.wasm"
