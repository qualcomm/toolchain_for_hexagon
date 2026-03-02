# Hexagon Toolchain Examples

Example programs for the [open-source Hexagon toolchain](https://github.com/quic/toolchain_for_hexagon).

## Prerequisites

[Download](https://github.com/quic/toolchain_for_hexagon/releases) and unpack the toolchain:

```
VER=22.1.0_
wget https://artifacts.codelinaro.org/artifactory/codelinaro-toolchain-for-hexagon/${VER}/clang+llvm-${VER}-cross-hexagon-unknown-linux-musl.tar.zst
tar --zstd -xf clang+llvm-${VER}-cross-hexagon-unknown-linux-musl.tar.zst -C /opt
```

The default install location is `/opt/clang+llvm-22.1.0-cross-hexagon-unknown-linux-musl`.
Override with `TOOLCHAIN_ROOT` if installed elsewhere.

## Quick Start

Build and run all examples:

```
make
make run
```

Or with a custom toolchain location:

```
make TOOLCHAIN_ROOT=/path/to/clang+llvm-22.1.0-cross-hexagon-unknown-linux-musl
make run
```

## Examples

### Baremetal (hexagon-clang)

These programs target `hexagon-unknown-none-elf` and run under
`qemu-system-hexagon` or `hexagon-sim` (requires [Hexagon SDK](https://github.com/snapdragon-toolchain/hexagon-sdk/releases)).

| Example | Description |
|---------|-------------|
| [baremetal-semihosting/](baremetal-semihosting/) | Hello world with picolibc `printf` via semihosting |
| [baremetal-kasan/](baremetal-kasan/) | Kernel Address Sanitizer on bare metal via split-target build |

### Sanitizers (Linux, hexagon-unknown-linux-musl-clang)

These programs target `hexagon-unknown-linux-musl` (Linux userspace) and run
under `qemu-hexagon`.

| Example | Sanitizer | Bugs Demonstrated |
|---------|-----------|-------------------|
| [ubsan/](ubsan/) | Undefined Behavior Sanitizer | Signed overflow, bad shift, null deref |
| [asan/](asan/) | Address Sanitizer | Heap overflow, use-after-free, stack overflow |

### Other

| Example | Description |
|---------|-------------|
| [contrived/](contrived/) | Rust + Zig + C++ multi-language demo |
