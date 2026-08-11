# Host tools: LLVM + Clang for Hexagon cross-compilation
#
# Usage:
#   cmake -G Ninja -C hexagon-stage0.cmake -C hexagon-stage0-cross.cmake ...
#   cmake --build . --target install-distribution
#
# For zig cross-builds, add -C hexagon-stage0-dylib.cmake

set(LLVM_TARGETS_TO_BUILD "Hexagon" CACHE STRING "")
set(LLVM_ENABLE_PROJECTS "clang;lld" CACHE STRING "")
set(CMAKE_BUILD_TYPE Release CACHE STRING "")
set(LLVM_ENABLE_PIC ON CACHE BOOL "")

# LLVM dylib is not needed for the cross-toolchain distribution.
# Kept OFF for consistency with ELD's static LLVM linkage (libLW.so).
set(LLVM_BUILD_LLVM_DYLIB OFF CACHE BOOL "")
set(LLVM_LINK_LLVM_DYLIB OFF CACHE BOOL "")
set(LLVM_VERSION_SUFFIX "" CACHE STRING "")

set(CMAKE_INSTALL_RPATH "$ORIGIN/../lib" CACHE STRING "")

# Clang defaults for Hexagon
set(LLVM_DEFAULT_TARGET_TRIPLE "hexagon-unknown-linux-musl" CACHE STRING "")
set(CLANG_DEFAULT_CXX_STDLIB "libc++" CACHE STRING "")
set(CLANG_DEFAULT_RTLIB "compiler-rt" CACHE STRING "")
set(CLANG_DEFAULT_UNWINDLIB "libunwind" CACHE STRING "")
set(CLANG_DEFAULT_LINKER "lld" CACHE STRING "")
set(CLANG_DEFAULT_OBJCOPY "llvm-objcopy" CACHE STRING "")

# Trim
set(LLVM_INSTALL_TOOLCHAIN_ONLY ON CACHE BOOL "")
set(LLVM_INCLUDE_TESTS OFF CACHE BOOL "")
set(LLVM_INCLUDE_DOCS OFF CACHE BOOL "")
set(LLVM_ENABLE_ZLIB ON CACHE BOOL "")
set(LLVM_ENABLE_ZSTD ON CACHE BOOL "")

# Distribution components -- installed via `--target install-distribution`
set(LLVM_TOOLCHAIN_TOOLS
  llvm-addr2line
  llvm-ar
  llvm-config
  llvm-cov
  llvm-cxxfilt
  llvm-dwarfdump
  llvm-mc
  llvm-nm
  llvm-objcopy
  llvm-objdump
  llvm-profdata
  llvm-ranlib
  llvm-readelf
  llvm-readobj
  llvm-size
  llvm-strings
  llvm-strip
  llvm-symbolizer
  CACHE STRING "")

set(LLVM_DISTRIBUTION_COMPONENTS
  clang
  clang-resource-headers
  lld
  LTO
  ${LLVM_TOOLCHAIN_TOOLS}
  CACHE STRING "")
# Note: builtins are NOT in LLVM_DISTRIBUTION_COMPONENTS because the
# hexagon-unknown-linux-musl builtins need musl headers (stdlib.h) which
# are installed later.  Build builtins explicitly via:
#   cmake --build obj_llvm --target install-builtins

# -- Per-target builtins -----------------------------------------------
set(LLVM_BUILTIN_TARGETS "hexagon-unknown-linux-musl;hexagon-unknown-none-elf" CACHE STRING "")

# Linux builtins (from compiler-rt/cmake/caches/hexagon-linux-builtins.cmake)
# CMAKE_SYSROOT is needed because the build-tree clang doesn't resolve the
# relative DEFAULT_SYSROOT correctly; musl headers must be installed first.
set(BUILTINS_hexagon-unknown-linux-musl_CMAKE_SYSTEM_NAME Linux CACHE STRING "")
set(BUILTINS_hexagon-unknown-linux-musl_CMAKE_BUILD_TYPE Release CACHE STRING "")
set(BUILTINS_hexagon-unknown-linux-musl_CMAKE_SYSROOT
    "${CMAKE_INSTALL_PREFIX}/target/hexagon-unknown-linux-musl" CACHE STRING "")
set(BUILTINS_hexagon-unknown-linux-musl_CMAKE_ASM_FLAGS "-G0 -mlong-calls -fno-pic" CACHE STRING "")
set(BUILTINS_hexagon-unknown-linux-musl_COMPILER_RT_BUILTINS_ENABLE_PIC OFF CACHE BOOL "")

# Baremetal builtins (from compiler-rt/cmake/caches/hexagon-builtins-baremetal.cmake)
set(BUILTINS_hexagon-unknown-none-elf_CMAKE_SYSTEM_NAME Generic CACHE STRING "")
set(BUILTINS_hexagon-unknown-none-elf_CMAKE_BUILD_TYPE Release CACHE STRING "")
set(BUILTINS_hexagon-unknown-none-elf_CMAKE_ASM_FLAGS "-G0 -mlong-calls -fno-pic" CACHE STRING "")
set(BUILTINS_hexagon-unknown-none-elf_CMAKE_C_FLAGS "-ffreestanding" CACHE STRING "")
set(BUILTINS_hexagon-unknown-none-elf_CMAKE_CXX_FLAGS "-ffreestanding" CACHE STRING "")
set(BUILTINS_hexagon-unknown-none-elf_COMPILER_RT_BAREMETAL_BUILD ON CACHE BOOL "")
set(BUILTINS_hexagon-unknown-none-elf_COMPILER_RT_BUILTINS_ENABLE_PIC OFF CACHE BOOL "")
# CMake 4.x + Generic platform rejects SHARED IMPORTED targets from
# find_package(LLVM).  Override after project() so the declarations succeed.
set(BUILTINS_hexagon-unknown-none-elf_CMAKE_PROJECT_INCLUDE
    "${CMAKE_CURRENT_LIST_DIR}/generic-allow-shared-imports.cmake" CACHE STRING "")

# -- Per-target runtimes (built AFTER musl, via separate build target) -
set(LLVM_RUNTIME_TARGETS "hexagon-unknown-linux-musl" CACHE STRING "")

# Sysroot path for musl headers -- populated by musl build before runtimes.
set(RUNTIMES_hexagon-unknown-linux-musl_CMAKE_SYSTEM_NAME Linux CACHE STRING "")
set(RUNTIMES_hexagon-unknown-linux-musl_CMAKE_BUILD_TYPE Release CACHE STRING "")
set(RUNTIMES_hexagon-unknown-linux-musl_CMAKE_SYSROOT
    "${CMAKE_INSTALL_PREFIX}/target/hexagon-unknown-linux-musl" CACHE STRING "")
# Note: CMAKE_TRY_COMPILE_TARGET_TYPE is intentionally NOT set to STATIC_LIBRARY
# here.  Runtimes configure lazily (at cmake --build time), after musl+builtins
# are fully installed, so cmake can do real link tests.  This avoids false
# positives from check_library_exists() (e.g. __cxa_thread_atexit_impl).

# Runtimes to build (from libcxx/cmake/caches/hexagon-linux-runtimes.cmake
# + compiler-rt/cmake/caches/hexagon-linux-clangrt.cmake)
set(RUNTIMES_hexagon-unknown-linux-musl_LLVM_ENABLE_RUNTIMES
    "libcxx;libcxxabi;libunwind;compiler-rt" CACHE STRING "")

# Per-target runtime dirs OFF -- the Hexagon driver overrides getCompilerRTPath()
# to return ${SysRoot}/usr/lib/ and searches there with arch-suffix naming
# (libclang_rt.<name>-hexagon.{a,so}).  Per-target ON would install to a
# <triple>/ subdirectory that the driver doesn't search.  All install dirs
# below are set explicitly, so the per-target default paths don't matter.
set(RUNTIMES_hexagon-unknown-linux-musl_LLVM_ENABLE_PER_TARGET_RUNTIME_DIR OFF CACHE BOOL "")

# compiler-rt sanitizer/xray/memprof libraries -> sysroot lib dir.
# The Hexagon driver's getCompilerRTPath() returns ${SysRoot}/usr/lib/,
# so compiler-rt libraries must be installed there with arch-suffix names.
# Headers stay in the resource dir (COMPILER_RT_INSTALL_INCLUDE_DIR default).
# Must be an ABSOLUTE path.  A relative value does not survive to the sysroot
# here: compiler-rt's own CMakeLists re-declares COMPILER_RT_INSTALL_LIBRARY_DIR
# as `CACHE PATH` in the runtimes sub-build, which re-types the forwarded value
# to PATH and resolves the relative path against the sub-build dir -- sending
# the sanitizer libs to obj_llvm/.../runtimes-bins instead of the sysroot.
# (LIBCXX_* below stay STRING and so a relative value works for them; the
# asymmetry is why compiler-rt needs the absolute form.)  An absolute value is
# left untouched by PATH-typing and installs to the sysroot as intended.
set(RUNTIMES_hexagon-unknown-linux-musl_COMPILER_RT_INSTALL_LIBRARY_DIR
    "${CMAKE_INSTALL_PREFIX}/target/hexagon-unknown-linux-musl/usr/lib" CACHE STRING "")

# libc++/libcxxabi/libunwind headers and libraries -> sysroot.
# Paths are relative to CMAKE_INSTALL_PREFIX (the host toolchain root).
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXX_INSTALL_LIBRARY_DIR
    "target/hexagon-unknown-linux-musl/usr/lib" CACHE STRING "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXX_INSTALL_INCLUDE_DIR
    "target/hexagon-unknown-linux-musl/usr/include/c++/v1" CACHE STRING "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXX_INSTALL_INCLUDE_TARGET_DIR
    "target/hexagon-unknown-linux-musl/usr/include/c++/v1" CACHE STRING "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXXABI_INSTALL_LIBRARY_DIR
    "target/hexagon-unknown-linux-musl/usr/lib" CACHE STRING "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXXABI_INSTALL_INCLUDE_DIR
    "target/hexagon-unknown-linux-musl/usr/include/c++/v1" CACHE STRING "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBUNWIND_INSTALL_LIBRARY_DIR
    "target/hexagon-unknown-linux-musl/usr/lib" CACHE STRING "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBUNWIND_INSTALL_INCLUDE_DIR
    "target/hexagon-unknown-linux-musl/usr/include" CACHE STRING "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXX_HAS_MUSL_LIBC ON CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXX_INCLUDE_BENCHMARKS OFF CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXX_INCLUDE_TESTS OFF CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXXABI_INCLUDE_TESTS OFF CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBUNWIND_INCLUDE_TESTS OFF CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXX_CXX_ABI libcxxabi CACHE STRING "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXXABI_USE_LLVM_UNWINDER ON CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXXABI_ENABLE_SHARED ON CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXX_USE_COMPILER_RT ON CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBCXXABI_USE_COMPILER_RT ON CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_LIBUNWIND_USE_COMPILER_RT ON CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_COMPILER_RT_USE_LLVM_UNWINDER ON CACHE BOOL "")
# compiler-rt sanitizer/xray shared libs need in-tree libc++ and builtins.
# Following Fuchsia's runtimes configuration pattern:
#   - COMPILER_RT_CXX_LIBRARY=libcxx: in-tree libc++ headers for C++ sources (XRay)
#   - SANITIZER_CXX_ABI=libc++ + INTREE: link sanitizer .so against in-tree libc++abi
#   - COMPILER_RT_USE_BUILTINS_LIBRARY=ON: statically links builtins into each
#     compiler-rt runtime (via AddCompilerRT.cmake's add_compiler_rt_runtime),
#     needed because Hexagon uses library calls for division (__hexagon_udivsi3
#     etc.) and also removes -Wl,-z,defs for any remaining deferred symbols
set(RUNTIMES_hexagon-unknown-linux-musl_COMPILER_RT_CXX_LIBRARY "libcxx" CACHE STRING "")
set(RUNTIMES_hexagon-unknown-linux-musl_COMPILER_RT_USE_BUILTINS_LIBRARY ON CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_SANITIZER_CXX_ABI "libc++" CACHE STRING "")
set(RUNTIMES_hexagon-unknown-linux-musl_SANITIZER_CXX_ABI_INTREE ON CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_COMPILER_RT_BUILD_BUILTINS OFF CACHE BOOL "")
# sanitizer_common's struct-stat64-on-musl issue is fixed as of
# llvmorg-23.1.0-rc1, so every feature that pulls in sanitizer_common can be
# built. hexagon is already present in each feature's ALL_<X>_SUPPORTED_ARCH
# list in compiler-rt/cmake/Modules/AllSupportedArchDefs.cmake, so no arch-list
# patch is needed.
#
# COMPILER_RT_SANITIZERS_TO_BUILD is scoped rather than left at "all" because
# the remaining entries have no Hexagon support: msan/tsan/hwasan/dfsan/nsan
# omit hexagon from their ALL_<X>_SUPPORTED_ARCH lists, and asan_abi is
# Darwin-only.  Everything listed here is exercised by examples/ and is
# expected to link and run:
#   asan               -fsanitize=address (shadow scale 3 / offset 0x20000000,
#                      matching llvm's kDefaultShadowOffset32 for 32-bit)
#   safestack          -fsanitize=safe-stack -- needs the musl fix that also
#                      runs __safestack_init from a constructor, since musl
#                      does not honour .preinit_array (upstream in compiler-rt)
#   cfi                cross-DSO CFI; plain -fsanitize=cfi-icall needs no
#                      runtime, only the cfi_ignorelist.txt installed by the
#                      sanitizer-ignorelists target
#   rtsan tysan scudo_standalone gwp_asan
# ubsan and lsan are not list members -- compiler-rt builds them unconditionally
# alongside sanitizer_common (see compiler-rt/lib/CMakeLists.txt).
# Shadow-call-stack is a pure codegen+linker feature (a reserved register, no
# compiler-rt runtime component) and kcfi is codegen-only; neither needs a
# COMPILER_RT_BUILD_* flag here.
set(RUNTIMES_hexagon-unknown-linux-musl_COMPILER_RT_BUILD_SANITIZERS ON CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_COMPILER_RT_SANITIZERS_TO_BUILD
    "asan;safestack;cfi;rtsan;tysan;scudo_standalone;gwp_asan" CACHE STRING "")
# XRay: the Hexagon PIC/trampoline/sled fixes are upstream, so the runtime
# builds and works (see examples/xray).
set(RUNTIMES_hexagon-unknown-linux-musl_COMPILER_RT_BUILD_XRAY ON CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_COMPILER_RT_BUILD_MEMPROF OFF CACHE BOOL "")
set(RUNTIMES_hexagon-unknown-linux-musl_COMPILER_RT_BUILD_CTX_PROFILE OFF CACHE BOOL "")
# LibFuzzer builds its own private copy of libc++ with -fno-exceptions, which is
# the only configuration that instantiates libc++'s __is_function_overridden().
# That emits a GAS symbol assignment (`sym = expr`), and `=` is Hexagon's operand
# assignment operator, so the assembler rejects it:
#   overridable_function.h: error: unrecognized instruction
#     1 |  _ZNSt3__110__impl_refIXadL_ZnwjEEE7__impl_...Ej = _Znwj
# Still unfixed as of llvm-project main (libcxx/src/include/overridable_function.h
# emits `%cc0 = %cc1`); re-enable once Hexagon spells it `.set sym, expr`.
set(RUNTIMES_hexagon-unknown-linux-musl_COMPILER_RT_BUILD_LIBFUZZER OFF CACHE BOOL "")
