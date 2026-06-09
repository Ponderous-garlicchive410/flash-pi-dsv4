#!/bin/bash
# Codex middle-ground launcher: top-2 alpha0 + zero-slot compaction + raw-KV compressor skip.
# Keeps the fast/broken hash pruning and confidence top1 knobs OFF.
# Uses the repo-built Codex fast binary unless DS4_CODEX_FAST_DIR points
# elsewhere.
# Default generation is bounded for interactive use; set DS4_AGENT_UNTIL_EOS=1
# to omit -n and let the model run until EOS/context.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DS4_CODEX_FAST_DIR="${DS4_CODEX_FAST_DIR:-$REPO_ROOT/build/codex-fast}"

if [ ! -x "$DS4_CODEX_FAST_DIR/ds4" ]; then
  echo "missing $DS4_CODEX_FAST_DIR/ds4; run scripts/pi/build_ds4_codex_fast.sh on the Pi first" >&2
  exit 1
fi

cd "$DS4_CODEX_FAST_DIR"
ulimit -l unlimited || true
echo 64 > /sys/block/nvme0n1/queue/read_ahead_kb 2>/dev/null || true

export DS4_Q4_STATIC=1
export DS4_Q4_STATIC_8=1
export DS4_Q4_LMHEAD=1
export DS4_Q4_CACHE="${DS4_Q4_CACHE:-/mnt/nvme/q4_8type.cache}"
export DS4_Q4_PREFILL_SDOT=1
export DS4_PIN_STATIC=1
export DS4_PIN_STATIC_BYTES=2000M
export DS4_NO_EXPERT_READAHEAD=1
export DS4_SPEC_ROUTE=1
export DS4_EXPERT_PACK="${DS4_EXPERT_PACK:-/mnt/nvme/expert_pack_full.bin}"

export DS4_TOPK=2
export DS4_TOPK_RENORM_ALPHA=0
export DS4_SPEC_PREFETCH_K=2
export DS4_COMPACT_ACTIVE_EXPERTS=1
export DS4_SKIP_COMPRESS_UNTIL_RAW_FULL=1

unset DS4_HASH_TOPK
unset DS4_HASH_TOPK_RENORM_ALPHA
unset DS4_TOPK1_CONF

runner=(./ds4)
if [ "${DS4_AGENT_STOP_ON_THINK_END:-1}" = "1" ]; then
  runner=(python3 "$DS4_CODEX_FAST_DIR/ds4_stop_on_think.py" ./ds4)
fi

args=(
  "${runner[@]}" -m /mnt/nvme/ds4flash.gguf --nothink
  --temp "${DS4_AGENT_TEMP:-0}"
  --top-p "${DS4_AGENT_TOP_P:-1}"
  --min-p "${DS4_AGENT_MIN_P:-0.05}"
)

if [ -n "${DS4_AGENT_TOKENS:-}" ]; then
  args+=(-n "$DS4_AGENT_TOKENS")
elif [ "${DS4_AGENT_UNTIL_EOS:-0}" != "1" ]; then
  args+=(-n "${DS4_AGENT_DEFAULT_TOKENS:-768}")
fi

exec "${args[@]}" "$@"
