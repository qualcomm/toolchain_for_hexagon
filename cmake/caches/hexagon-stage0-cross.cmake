# Cross-compilation additions: sysroot and clang symlinks
#
# Loaded after hexagon-stage0.cmake to add cross-toolchain specifics.

set(DEFAULT_SYSROOT "../target/hexagon-unknown-linux-musl/" CACHE STRING "")

set(CLANG_LINKS_TO_CREATE
  hexagon-linux-musl-clang++
  hexagon-linux-musl-clang
  hexagon-unknown-linux-musl-clang++
  hexagon-unknown-linux-musl-clang
  hexagon-none-elf-clang++
  hexagon-none-elf-clang
  hexagon-unknown-none-elf-clang++
  hexagon-unknown-none-elf-clang
  clang++
  clang-cl
  clang-cpp
  CACHE STRING "")
