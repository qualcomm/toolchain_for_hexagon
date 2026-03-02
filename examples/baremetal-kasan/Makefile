include common.mk

# ---------------------------------------------------------------------------
# Baremetal KASan example
#
# Clones and builds the baremetal_kasan test suite using the open-source
# Hexagon toolchain, with PL011 UART output at 0x10000000.
#
# Usage:
#   make                        # build (clones baremetal_kasan on first run)
#   make run                    # build + run under qemu-system-hexagon
#   make TOOLCHAIN_ROOT=...     # override toolchain location
#   make HEX_CPU=v73            # override CPU version
# ---------------------------------------------------------------------------

KASAN_REPO := https://github.com/androidoffsec/baremetal_kasan.git
KASAN_SRC  := baremetal_kasan

# Clone sources at Makefile-parse time so VPATH resolves correctly.
ifeq ($(wildcard $(KASAN_SRC)/.),)
$(info Cloning $(KASAN_REPO)...)
$(if $(shell git clone $(KASAN_REPO) $(KASAN_SRC) >&2 || echo FAIL),\
  $(error Failed to clone $(KASAN_REPO)))
endif

# VPATH lets make find source files in the baremetal_kasan tree.
VPATH := $(KASAN_SRC):$(KASAN_SRC)/third_party/printf

# Toolchain programs
CC := $(BIN_DIR)/clang
LD := $(BIN_DIR)/ld.eld

# CPU version — change to match your QEMU machine model.
HEX_CPU ?= v68

# QEMU machine model — must match the memory layout below.
HEX_MACHINE ?= virt

# PL011 UART data register — l2vic IRQ 15
UART_BASE_ADDRESS := 0x10000000

# Target triple
#   All C code uses hexagon-unknown-linux-musl for consistent varargs ABI.
#   Only sanitized_lib.o gets -fsanitize=kernel-address flags.
#   Assembly uses hexagon-unknown-none-elf (no ABI dependency).
#   --no-default-config prevents the driver from adding unwanted sysroot flags.
ARCH_TARGET := hexagon-unknown-linux-musl

# Memory layout — must match the QEMU machine's physical memory map.
TARGET_DRAM_START := 0x80000000
TARGET_DRAM_END   := 0x8fffffff

# Shadow memory parameters
# shadow(addr) = (addr >> 3) + KASAN_SHADOW_MAPPING_OFFSET
# For DRAM at 0x80000000, shadow at 0x8A700000:
#   offset = 0x8A700000 - (0x80000000 >> 3) = 0x7A700000
KASAN_SHADOW_MAPPING_OFFSET := 0x7A700000
KASAN_SHADOW_MEMORY_START   := 0x8A700000
KASAN_SHADOW_MEMORY_SIZE    := 0x2000000

# ---------------------------------------------------------------------------
# Compiler flags
# ---------------------------------------------------------------------------
CFLAGS := -Wall -Wno-unused-function -O2
CFLAGS += --no-default-config --target=$(ARCH_TARGET) -mcpu=hexagon$(HEX_CPU)
CFLAGS += -ffreestanding -fno-pic
CFLAGS += -DTARGET_ARCH_hexagon
CFLAGS += -DUART_BASE_ADDRESS=$(UART_BASE_ADDRESS)
CFLAGS += -DKASAN_SHADOW_MAPPING_OFFSET=$(KASAN_SHADOW_MAPPING_OFFSET)
CFLAGS += -DKASAN_SHADOW_MEMORY_START=$(KASAN_SHADOW_MEMORY_START)
CFLAGS += -DKASAN_SHADOW_MEMORY_SIZE=$(KASAN_SHADOW_MEMORY_SIZE)
CFLAGS += -DTARGET_DRAM_START=$(TARGET_DRAM_START)
CFLAGS += -DTARGET_DRAM_END=$(TARGET_DRAM_END)

# Compact printf configuration (disable features we don't need)
CFLAGS += -DPRINTF_DISABLE_SUPPORT_FLOAT
CFLAGS += -DPRINTF_DISABLE_SUPPORT_EXPONENTIAL
CFLAGS += -DPRINTF_DISABLE_SUPPORT_PTRDIFF_T
CFLAGS += -DPRINTF_DISABLE_SUPPORT_LONG_LONG
CFLAGS += -Wno-incompatible-library-redeclaration

# Include paths
CFLAGS += -I$(KASAN_SRC)/third_party -I$(KASAN_SRC)/third_party/printf -I$(KASAN_SRC)

# Builtins library for compiler-generated calls (__hexagon_udivsi3, etc.)
PICOLIBC_SYSROOT := $(TOOLCHAIN_ROOT)/x86_64-linux-gnu/target/picolibc/hexagon-unknown-none-elf
BUILTINS_LIB := $(PICOLIBC_SYSROOT)/lib/$(HEX_CPU)/G0/libclang_rt.builtins.a

LDFLAGS := -nostdlib

# ---------------------------------------------------------------------------
# KASan-specific flags (applied only to sanitized_lib.o)
# ---------------------------------------------------------------------------
KASAN_CC_FLAGS := -fsanitize=kernel-address
KASAN_CC_FLAGS += -fno-builtin
KASAN_CC_FLAGS += -mllvm -asan-mapping-offset=$(KASAN_SHADOW_MAPPING_OFFSET)
KASAN_CC_FLAGS += -mllvm -asan-instrumentation-with-call-threshold=0
KASAN_CC_FLAGS += -mllvm -asan-stack=1
KASAN_CC_FLAGS += -mllvm -asan-globals=1
KASAN_CC_FLAGS += -mllvm -asan-max-inline-poisoning-size=0
KASAN_CC_FLAGS += -DKASAN_ENABLED

# ---------------------------------------------------------------------------
# Source files
# ---------------------------------------------------------------------------
# Sources from the cloned baremetal_kasan repo (found via VPATH)
SRCS := kasan.c heap.c kasan_test.c sanitized_lib.c rt_utils.c printf.c
# Local Hexagon-specific sources
SRCS += start_hexagon.S kasan_hexagon.c

OBJS := $(SRCS:.c=.o)
OBJS := $(OBJS:.S=.o)

LD_SCRIPT     := $(KASAN_SRC)/kasan_test.ld
LD_SCRIPT_GEN := kasan_test.lds

TARGET := kasan_test

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------

.PHONY: all clean run

all: $(TARGET)

clean:
	rm -f $(TARGET) $(OBJS) $(LD_SCRIPT_GEN)

# Run with qemu-system-hexagon.
# The test loops after completion; timeout ensures make returns.
run: $(TARGET)
	timeout --foreground 10 $(QEMU_SYSTEM) -M $(HEX_MACHINE) -display none -serial stdio -monitor none -kernel ./$(TARGET) || true

# ---------------------------------------------------------------------------
# Build rules
# ---------------------------------------------------------------------------

# sanitized_lib.o adds KASan instrumentation flags
sanitized_lib.o: CFLAGS += $(KASAN_CC_FLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.S
	$(CC) --no-default-config --target=hexagon-unknown-none-elf -mcpu=hexagon$(HEX_CPU) -c $< -o $@

# Pre-process the linker script (it uses C preprocessor #ifdefs)
$(LD_SCRIPT_GEN): $(LD_SCRIPT)
	$(CC) -E -P -x c $(CFLAGS) $< > $@

$(TARGET): $(LD_SCRIPT_GEN) $(OBJS)
	$(LD) -T $(LD_SCRIPT_GEN) $(LDFLAGS) $(OBJS) $(BUILTINS_LIB) -o $@
