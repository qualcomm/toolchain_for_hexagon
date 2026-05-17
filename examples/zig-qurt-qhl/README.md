# Zig QuRT with QHL Libraries Example

This example demonstrates how to use **pure Zig to build programs targeting Qualcomm's QuRT RTOS**.

## Prerequisites

1. **Hexagon SDK**: Install the Hexagon SDK (version 6.4.0.2 or compatible)
   - Download from [Qualcomm Hexagon SDK](https://developer.qualcomm.com/software/hexagon-dsp-sdk)
   - Default installation path: `/opt/Hexagon_SDK/6.4.0.2`

2. **Zig**: Install Zig (0.11.0 or newer recommended)
   - Download from [ziglang.org](https://ziglang.org/download/)

3. **Set up the SDK environment**:
   ```bash
   source /opt/Hexagon_SDK/6.4.0.2/setup_sdk_env.source
   ```

## Building

Build the example:

```bash
zig build
```

Build with specific options:

```bash
# Build for different Hexagon architecture versions
zig build -Darch=v75  # Default
zig build -Darch=v73
zig build -Darch=v68

# Build with optimization
zig build -Doptimize=ReleaseFast
```

## Running

Execute with QEMU:

```bash
zig build run
```

Or manually with the Hexagon SDK's QEMU:

```bash
/opt/Hexagon_SDK/6.4.0.2/tools/Tools/QEMUHexagon/bin/qemu-system-hexagon \
    -kernel /opt/Hexagon_SDK/6.4.0.2/rtos/qurt/computev75/sdksim_bin/runelf.pbn \
    -append '/opt/Hexagon_SDK/6.4.0.2/libs/run_main_on_hexagon/ship/hexagon_toolv19_v75/run_main_on_hexagon_sim -- zig-out/build/libqurt-qhl-demo.so'
```
## Linker Considerations

This example uses the Hexagon SDK's linker (`ld.qcld`) via hexagon-clang for QuRT shared libraries.

To use **ld.lld** instead, uncomment the lld flags in `build.zig`. The following flags are needed:

```
-fuse-ld=lld
-Wl,-z,max-page-size=4096
-Wl,-z,common-page-size=4096
-Wl,-z,separate-loadable-segments
```

- **Page size flags**: QuRT uses 4K pages. Without these, lld may produce segments with larger alignment that QuRT's loader cannot handle.
- **Separate loadable segments**: Prevents lld from merging adjacent PT_LOAD segments. QuRT's dynamic loader expects each segment to be distinct.

## Environment Variables

The build.zig reads these environment variables (set by `setup_sdk_env.source`):

- `HEXAGON_SDK_ROOT`: Path to the Hexagon SDK installation
- `HEXAGON_TOOLS_ROOT`: Path to the Hexagon tools
- `V_ARCH`: Target Hexagon architecture version (e.g., v75, v73)


## QuRT Runtime Libraries

The example links against the QuRT runtime:
- `${HEXAGON_SDK_ROOT}/rtos/qurt/compute${V_ARCH}/lib/`
- System includes: `${HEXAGON_SDK_ROOT}/rtos/qurt/compute${V_ARCH}/include/`

## References

- [Hexagon SDK Documentation](https://developer.qualcomm.com/software/hexagon-dsp-sdk)
- [QHL API Documentation](https://developer.qualcomm.com/qfile/69578/qhl_api_reference.pdf)
- [Zig Build System](https://ziglang.org/documentation/master/#Build-System)
