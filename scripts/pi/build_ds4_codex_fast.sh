#!/usr/bin/env bash
# Build the Codex fast DS4 engine used by run_ds4_agent_codex_mid_temp.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DS4_BASE="${DS4_BASE:-$ROOT/third_party/ds4}"
DS4_SRC="${DS4_SRC:-$ROOT/src/ds4-codex-fast/ds4.c}"
OUT_DIR="${DS4_CODEX_FAST_DIR:-$ROOT/build/codex-fast}"
CC="${CC:-cc}"

exec make -C "$ROOT" build \
  DS4_BASE="$DS4_BASE" \
  DS4_SRC="$DS4_SRC" \
  BUILD_DIR="$OUT_DIR" \
  CC="$CC"
