
set(CMAKE_SYSTEM_NAME Linux CACHE STRING "")
set(CMAKE_C_COMPILER_TARGET hexagon-unknown-linux-musl CACHE STRING "")
set(CMAKE_CXX_COMPILER_TARGET hexagon-unknown-linux-musl CACHE STRING "")

set(CMAKE_C_COMPILER hexagon-unknown-linux-musl-clang CACHE STRING "")
set(CMAKE_SIZEOF_VOID_P 4 CACHE STRING "")
set(CMAKE_CXX_COMPILER hexagon-unknown-linux-musl-clang++ CACHE STRING "")
set(CMAKE_ASM_COMPILER hexagon-unknown-linux-musl-clang CACHE STRING "")
set(CMAKE_OBJCOPY hexagon-unknown-linux-musl-objcopy CACHE STRING "")
set(CMAKE_C_COMPILER_RANLIB hexagon-unknown-linux-musl-ranlib CACHE STRING "")
set(CMAKE_CROSSCOMPILING_EMULATOR qemu-hexagon CACHE STRING "")
set(CMAKE_C_COMPILER_FORCED ON CACHE BOOL "")
set(CMAKE_CXX_COMPILER_FORCED ON CACHE BOOL "")

# llvm-project/runtimes/ depends on these features because
# of `llvm-libc-common-utilities` in runtimes/cmake/Modules/FindLibcCommonUtils.cmake:
set(CMAKE_CXX_COMPILE_FEATURES cxx_std_17;cxx_std_14;cxx_std_11;cxx_std_03;cxx_std_98 CACHE STRING "")

