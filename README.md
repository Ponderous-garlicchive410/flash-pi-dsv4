# DeepSeek V4 Flash on a Raspberry Pi 5

This repo is a Pi-only runtime for running DeepSeek V4 Flash locally on a
Raspberry Pi 5 from NVMe storage. The goal is intentionally narrow: maximize
decode speed, measured as generation tokens per second, with no Mac or server in
the runtime path.

This is a hacked-up experimental fork of Antirez's DS4/DwarfStar engine:
<https://github.com/antirez/ds4>. It is not upstream DS4 and is not meant to be a
general-purpose local inference engine. The repo keeps only the Raspberry Pi
CPU/NVMe path and the patches needed for that workload.

The current runtime path is the Codex mid-temp CPU/NVMe profile. It runs a
patched DS4 engine with:

- top-2 routed experts instead of the model default top-6
- alpha-0 top-k renormalization
- expert-major packed routed weights
- active expert compaction, so zeroed routed slots are skipped
- raw-KV compressor skip
- Q4 static tensor cache for resident hot static weights
- a small wrapper that interrupts generation after a stray `</think>` marker

On the Pi this is the path that produced roughly 1 tok/s-class interactive
generation while staying accurate enough to use.

## Source Layout

The code that matters for this runtime is:

- `src/ds4-codex-fast/ds4.c`: canonical patched DS4 engine source recovered from
  the Pi runtime source artifact.
- `scripts/pi/build_ds4_codex_fast.sh`: Pi build script for that engine.
- `scripts/pi/run_ds4_agent_codex_mid_temp.sh`: launcher for the mid-temp
  runtime profile.
- `scripts/pi/ds4_stop_on_think.py`: PTY wrapper used by the launcher to stop
  runaway post-thinking generation.

Large runtime artifacts are intentionally not committed: the GGUF model, the
expert pack, and the Q4 static cache.

## Hardware

Recommended setup:

- Raspberry Pi 5, 8 GB RAM
- active cooling
- 64-bit Raspberry Pi OS
- M.2/NVMe adapter
- NVMe SSD, 256 GB or larger

The model should live on NVMe, not microSD. The measured full-tilt inference
power draw for this class of setup was around 8 W.

## Model

The GGUF used during development came from Antirez's DeepSeek V4 GGUF repo:

- <https://huggingface.co/antirez/deepseek-v4-gguf>
- `DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix.gguf`

DeepSeek V4 Flash is roughly a 284B-parameter mixture-of-experts model. The Pi
does not load all weights into RAM; it memory maps the GGUF and streams the
routed expert weights it actually needs.

## Setup On The Pi

Install dependencies:

```bash
sudo apt update
sudo apt install -y build-essential git curl python3
```

Clone this repo and the upstream DS4 helper checkout:

```bash
git clone <this-repo-url> dsv4-flash-localaccel
cd dsv4-flash-localaccel

mkdir -p third_party
git clone https://github.com/antirez/ds4.git third_party/ds4
```

Download the q2 imatrix GGUF to NVMe:

```bash
mkdir -p /mnt/nvme/ds4-gguf
DS4_GGUF_DIR=/mnt/nvme/ds4-gguf third_party/ds4/download_model.sh q2-imatrix
ln -sfn /mnt/nvme/ds4-gguf/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix.gguf /mnt/nvme/ds4flash.gguf
```

Build the patched engine on the Pi:

```bash
make
```

The legacy script entrypoint also works and delegates to the same Makefile:
`scripts/pi/build_ds4_codex_fast.sh`.

Generate the expert-major pack once:

```bash
DS4_GEN_EXPERT_PACK=/mnt/nvme/expert_pack_full.bin \
  build/codex-fast/ds4 -m /mnt/nvme/ds4flash.gguf --nothink -p "build expert pack" -n 1
```

Then run the interactive launcher:

```bash
scripts/pi/run_ds4_agent_codex_mid_temp.sh
```

The first run may build the Q4 static cache. By default the launcher expects it
at `/mnt/nvme/q4_8type.cache`; override `DS4_Q4_CACHE` if you store it
elsewhere.

## Runtime Knobs

Useful launcher overrides:

```bash
DS4_AGENT_UNTIL_EOS=1 scripts/pi/run_ds4_agent_codex_mid_temp.sh
DS4_AGENT_TOKENS=256 scripts/pi/run_ds4_agent_codex_mid_temp.sh
DS4_Q4_CACHE=/mnt/nvme/q4_8type.cache scripts/pi/run_ds4_agent_codex_mid_temp.sh
DS4_AGENT_STOP_ON_THINK_END=0 scripts/pi/run_ds4_agent_codex_mid_temp.sh
```

## Why It Works

The model is huge, but MoE decode only touches a small routed subset per token.
The project wins by making those routed reads predictable and by skipping routed
work that the policy has already pruned away. The Linux page cache is the expert
cache; userspace copy caches lost because they duplicated memory and added churn.

The research path covered 163+ experiments over five days, including custom
NEON/dotprod kernels, Q4 static tensor caching, NVMe layout work, expert-major
packing, Hailo static-graph attempts, Vulkan probes, O_DIRECT experiments, and
top-k quality/speed tradeoffs. The useful final path for this cleaned repo is
the CPU/NVMe mid-temp runtime above. The optimization effort was joint work
between GPT-5.5 xhigh in Codex and Opus 4.8 in Claude Code.
