include common.mk

TARGET_TRIPLE := hexagon-unknown-linux-musl
CARGO_FLAGS   := +nightly -Zbuild-std -Zbuild-std-features=llvm-libunwind
BINARY        := target/$(TARGET_TRIPLE)/debug/rust-hvx

export PATH := $(BIN_DIR):$(PATH)
export QEMU_LD_PREFIX := $(SYSROOT_LINUX)

.PHONY: all clean run run-scalar run-v60

all:
	cargo $(CARGO_FLAGS) build --target=$(TARGET_TRIPLE)

run: all
	$(QEMU_HEXAGON) -cpu v66 $(BINARY)

run-scalar: all
	$(QEMU_HEXAGON) -cpu v66 $(BINARY) --force-tier 0

run-v60: all
	$(QEMU_HEXAGON) -cpu v66 $(BINARY) --force-tier 1

clean:
	cargo clean
