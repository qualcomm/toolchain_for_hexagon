# Baremetal KASan (Kernel Address Sanitizer)

Demonstrates Kernel Address Sanitizer (KASan) for bare-metal Hexagon programs
using a split-target build technique.

Based on [baremetal_kasan](https://github.com/androidoffsec/baremetal_kasan).

## How It Works

KASan instruments memory accesses to detect out-of-bounds and use-after-free
bugs.  On bare metal there is no OS to provide KASan runtime support, so this
example supplies its own shadow memory management and reporting.

The key technique is a **split-target build**:

- Most code is compiled for `hexagon-unknown-none-elf` (bare-metal).
- The code under test (`sanitized_lib.c`) is compiled for
  `hexagon-unknown-linux-musl` with `-fsanitize=kernel-address`, because
  the sanitizer pass requires a non-freestanding target.
- Both are linked together with `ld.eld` into a single bare-metal ELF.

## Bugs Demonstrated

- Heap buffer overflow
- Stack buffer overflow
- Global buffer overflow
- memset overflow
- memcpy overflow

## Build and Run

```
make
make run
```

The first `make` automatically clones the
[baremetal_kasan](https://github.com/androidoffsec/baremetal_kasan) repository
into the current directory.

Output goes through the PL011 UART at `0x10000000`.  QEMU is launched with
`-display none -serial stdio -monitor none` to redirect the serial port to
stdout.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `HEX_CPU` | `v68` | Hexagon CPU version |
| `HEX_MACHINE` | `V66G_1024` | QEMU machine model |
| `UART_BASE_ADDRESS` | `0x10000000` | PL011 UART data register |
| `TARGET_DRAM_START` | `0x80000000` | Start of DRAM |
| `TARGET_DRAM_END` | `0x8fffffff` | End of DRAM |

## Flags

```
-fsanitize=kernel-address
-mllvm -asan-mapping-offset=<shadow-offset>
-mllvm -asan-instrumentation-with-call-threshold=0
-mllvm -asan-stack=1
-mllvm -asan-globals=1
```
