# DeepSeek V4 Flash Pi Runtime

This repository is now scoped to the Codex mid-temp CPU/NVMe runtime only.

## Canonical Files

- `src/ds4-codex-fast/ds4.c` is the patched DS4 engine source.
- `scripts/pi/build_ds4_codex_fast.sh` builds that engine on Raspberry Pi OS.
- `scripts/pi/run_ds4_agent_codex_mid_temp.sh` is the runtime launcher.
- `scripts/pi/ds4_stop_on_think.py` is the interactive stop wrapper.

Do not reintroduce Hailo compile artifacts, benchmark dumps, Pi snapshots, or
temporary recovered-source bundles into this repo. Large runtime files stay out
of git: GGUF models, expert packs, Q4 caches, HEFs, HARs, ONNX exports, and
compiled binaries.

## Runtime Target

The target is Raspberry Pi 5, 64-bit Linux, CPU-only DS4, NVMe-backed model
storage. The success metric is decode/generation tokens per second. The Mac is
not in the runtime path.

## Build Discipline

Build on the Pi with `scripts/pi/build_ds4_codex_fast.sh`. The script expects
the upstream DS4 helper checkout at `third_party/ds4` unless `DS4_BASE` points
elsewhere. Keep third-party source checkouts local and ignored unless they are
intentionally vendored in a separate, explicit change.
