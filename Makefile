ROOT := $(CURDIR)

DS4_BASE ?= $(ROOT)/third_party/ds4
DS4_SRC ?= $(ROOT)/src/ds4-codex-fast/ds4.c
BUILD_DIR ?= $(if $(DS4_CODEX_FAST_DIR),$(DS4_CODEX_FAST_DIR),$(ROOT)/build/codex-fast)
OBJ_DIR ?= $(BUILD_DIR)/obj

CC ?= cc
MODEL ?= /mnt/nvme/ds4flash.gguf
EXPERT_PACK ?= /mnt/nvme/expert_pack_full.bin

UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

COMMON_CFLAGS := \
	-O3 \
	-g0 \
	-fomit-frame-pointer \
	-mcpu=cortex-a76 \
	-mtune=cortex-a76 \
	-std=c99 \
	-D_GNU_SOURCE \
	-Wall \
	-Wextra \
	-I$(DS4_BASE)

ENGINE_CFLAGS := $(COMMON_CFLAGS) -DDS4_NO_GPU
LINK_FLAGS := -O3 -g0 -fomit-frame-pointer -mcpu=cortex-a76 -mtune=cortex-a76
LDLIBS := -lm -pthread

BIN := $(BUILD_DIR)/ds4
WRAPPER := $(BUILD_DIR)/ds4_stop_on_think.py
BUILD_STAMP := $(OBJ_DIR)/.sources-ok
REQUIRED_SOURCES := \
	$(DS4_SRC) \
	$(DS4_BASE)/ds4.h \
	$(DS4_BASE)/ds4_cli.c \
	$(DS4_BASE)/linenoise.c \
	$(DS4_BASE)/linenoise.h \
	$(DS4_BASE)/gguf-tools/quants.c \
	$(DS4_BASE)/gguf-tools/quants.h
EXISTING_REQUIRED_SOURCES := $(wildcard $(REQUIRED_SOURCES))
OBJS := \
	$(OBJ_DIR)/ds4_codex_fast.o \
	$(OBJ_DIR)/ds4_cli.o \
	$(OBJ_DIR)/linenoise.o \
	$(OBJ_DIR)/quants.o

.PHONY: all build clean check-platform check-sources hash run expert-pack help

all: build

build: $(BIN) $(WRAPPER)
	@echo "built $(BIN)"

$(BIN): $(OBJS) | $(BUILD_DIR)
	$(CC) $(LINK_FLAGS) $(OBJS) $(LDLIBS) -o $@
	@{ sha256sum "$@" 2>/dev/null || shasum -a 256 "$@"; }

$(WRAPPER): $(ROOT)/scripts/pi/ds4_stop_on_think.py | $(BUILD_DIR)
	cp $< $@
	chmod +x $@

$(BUILD_STAMP): $(EXISTING_REQUIRED_SOURCES) | check-platform check-sources $(OBJ_DIR)
	touch $@

$(OBJ_DIR)/ds4_codex_fast.o: $(BUILD_STAMP)
	$(CC) $(ENGINE_CFLAGS) -c $(DS4_SRC) -o $@

$(OBJ_DIR)/ds4_cli.o: $(BUILD_STAMP)
	$(CC) $(ENGINE_CFLAGS) -c $(DS4_BASE)/ds4_cli.c -o $@

$(OBJ_DIR)/linenoise.o: $(BUILD_STAMP)
	$(CC) $(ENGINE_CFLAGS) -c $(DS4_BASE)/linenoise.c -o $@

$(OBJ_DIR)/quants.o: $(BUILD_STAMP)
	$(CC) $(COMMON_CFLAGS) -c $(DS4_BASE)/gguf-tools/quants.c -o $@

$(BUILD_DIR) $(OBJ_DIR):
	mkdir -p $@

check-platform:
	@if [ "$(UNAME_S)" != "Linux" ]; then \
		echo "This build targets Raspberry Pi Linux; run make on the Pi." >&2; \
		exit 2; \
	fi
	@case "$(UNAME_M)" in \
		aarch64|arm64) ;; \
		*) echo "warning: expected aarch64/arm64 Raspberry Pi, got $(UNAME_M)" >&2 ;; \
	esac

check-sources:
	@test -f "$(DS4_SRC)" || { echo "missing Codex fast source: $(DS4_SRC)" >&2; exit 1; }
	@missing=0; \
	for path in \
		"$(DS4_BASE)/ds4.h" \
		"$(DS4_BASE)/ds4_cli.c" \
		"$(DS4_BASE)/linenoise.c" \
		"$(DS4_BASE)/linenoise.h" \
		"$(DS4_BASE)/gguf-tools/quants.c" \
		"$(DS4_BASE)/gguf-tools/quants.h"; do \
		if [ ! -f "$$path" ]; then \
			echo "missing DS4 helper source: $$path" >&2; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" -ne 0 ]; then \
		echo "set DS4_BASE=/path/to/ds4 or clone antirez/ds4 into third_party/ds4" >&2; \
		exit 1; \
	fi

hash: $(BIN)
	@{ sha256sum "$(BIN)" 2>/dev/null || shasum -a 256 "$(BIN)"; }

run: build
	DS4_CODEX_FAST_DIR="$(BUILD_DIR)" $(ROOT)/scripts/pi/run_ds4_agent_codex_mid_temp.sh

expert-pack: build
	DS4_GEN_EXPERT_PACK="$(EXPERT_PACK)" "$(BIN)" -m "$(MODEL)" --nothink -p "build expert pack" -n 1

clean:
	rm -rf "$(BUILD_DIR)"

help:
	@echo "Targets:"
	@echo "  make build        Build the Pi CPU/NVMe mid-temp ds4 binary"
	@echo "  make run          Build, then run scripts/pi/run_ds4_agent_codex_mid_temp.sh"
	@echo "  make expert-pack  Generate EXPERT_PACK from MODEL"
	@echo "  make clean        Remove BUILD_DIR"
	@echo
	@echo "Useful overrides:"
	@echo "  DS4_BASE=/path/to/ds4"
	@echo "  BUILD_DIR=/path/to/build/codex-fast"
	@echo "  MODEL=/mnt/nvme/ds4flash.gguf"
	@echo "  EXPERT_PACK=/mnt/nvme/expert_pack_full.bin"
