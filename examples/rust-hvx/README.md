# Rust HVX Intrinsics — Histogram Equalization

Runtime CPU detection (`getauxval(AT_HWCAP)`) with multi-version HVX dispatch
for histogram equalization, using `core::arch::hexagon::v128` intrinsics.

The `stdarch_hexagon` feature is **nightly-only** and
[not yet stabilized](https://github.com/rust-lang/rust/issues/151523).

This toolchain provides only a linker and target libraries necessary for
building the program, the majority of the support comes from the Rust
project.

## Algorithm

[Histogram equalization](https://en.wikipedia.org/wiki/Histogram_equalization)
redistributes pixel intensities to produce a more uniform distribution:

1. **Histogram** — count occurrences of each byte value (256 bins)
2. **CDF** — cumulative sum, normalized to [0, 255]
3. **Remap** — replace each pixel via the CDF lookup table

## Dispatch Tiers

| Tier | Histogram | Remap | Selected when |
|------|-----------|-------|---------------|
| 0 — Scalar | `hist[pixel]++` loop | `out = lut[pixel]` loop | No HVX |
| 1 — HVX v60 | Scalar histogram | `vlut32` (128 pixels/iter) | HVX 128b, ISA < v65 |
| 2 — HVX v65 | `vscatteracc` (64 bins/instr) | `vlut32` (128 pixels/iter) | HVX 128b, ISA ≥ v65 |

### hwcap Detection

The program reads `getauxval(AT_HWCAP)` to detect the CPU at runtime:

```
bits [6:0]:  ISA version (V60=6, V62=7, V65=8, V66=9, ...)
bit  7:      HVX supported
bit  9:      HVX 128-byte vectors
```

Use `--force-tier {0,1,2}` to override automatic detection.

## Prerequisites

- Hexagon toolchain (for the linker and QEMU)
- Rust **nightly** with `rust-src`:
  ```
  rustup toolchain install nightly
  rustup component add rust-src --toolchain nightly
  ```

## Build and Run

```
make            # compile
make run        # run with auto-detected tier (v66 → tier 2)
make run-scalar # force scalar path (tier 0)
make run-v60    # force v60 HVX path (tier 1)
```

## Sample Output

```
CPU: Hexagon V66
HVX: 128-byte vectors
Selected: tier 2 — vscatteracc histogram + vlut32 remap (v65)

Input  histogram: min_count=16, max_count=48 (ideally uniform: 16)
Output histogram: min_count=16, max_count=48 (more uniform after equalization)

Comparison: 4096 pixels, max_error=0, mismatches=0
PASS
```
