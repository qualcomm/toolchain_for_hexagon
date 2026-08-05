#!/usr/bin/env bash
# build_runtimes.sh
#
# Builds runtimes (libunwind, libcxxabi, libcxx) for Hexagon targets.
# Supports multiple triples with different configurations.
#
# Required environment variables:
#   TOOLCHAIN    - Path to the installed Hexagon LLVM toolchain
#                  e.g. /path/to/inst/Tools
#   SOURCECODE   - Path to the llvm-top source directory
#                  e.g. /path/to/build/llvm-top
#   BUILDPATH    - Root directory for all build artifacts
#                  e.g. /path/to/build
#   INSTALLPATH  - Root directory where libs/headers are installed
#                  e.g. /path/to/install
#
# Optional environment variables:
#   BUILD_CORES  - Space-separated list of Hexagon arch versions to actually build
#                  (default: "v68")
#   ALL_CORES    - Space-separated list of all Hexagon arch versions to install for
#                  (default: "v68 v69 v71 v71t v73 v75 v77 v79 v81 v83 v85 v87 v89 v91")
#   NINJA        - Path to the ninja executable (default: ninja)
#   JOBS         - Parallel jobs for ninja (default: number of CPU cores)
#
# Build layout under BUILDPATH:
#   runtimes/
#     build-<build-prefix>-<core>/            (cmake build dir, non-G0)
#     build-<build-prefix>-<core>-G0/         (cmake build dir, G0)
#     build-<build-prefix>-<core>-G0-pic/     (cmake build dir, G0 + PIC)
#     install/<build-prefix>-<core>/          (intermediate install, non-G0)
#     install/<build-prefix>-<core>-G0/       (intermediate install, G0)
#     install/<build-prefix>-<core>-G0-pic/   (intermediate install, G0 + PIC)
#
# Install layout under INSTALLPATH (flat variant directories):
#   target/
#     <triple>/
#       include/
#       lib/<core>/
#         libunwind.a                  (non-G0, built)
#         libc++abi.a
#         libc++.a
#       lib/<core>-G0/
#         libunwind.a                  (G0, built)
#         libc++abi.a
#         libc++.a
#       lib/<core>-G0-pic/
#         libunwind.a                  (G0 + PIC, built)
#         libc++abi.a
#         libc++.a
#       lib/<other-core>/              (real dir; each file symlinks into lib/<core>/)
#         libunwind.a -> ../<core>/libunwind.a
#         libc++abi.a -> ../<core>/libc++abi.a
#         libc++.a    -> ../<core>/libc++.a
#       lib/<other-core>-G0/
#         libunwind.a -> ../<core>-G0/libunwind.a  (etc.)
#       lib/<other-core>-G0-pic/
#         libunwind.a -> ../<core>-G0-pic/libunwind.a  (etc.)

set -euo pipefail

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
: "${TOOLCHAIN:?'TOOLCHAIN env var is required (path to installed Hexagon LLVM toolchain)'}"
: "${SOURCECODE:?'SOURCECODE env var is required (path to llvm-top source directory)'}"
: "${BUILDPATH:?'BUILDPATH env var is required (root directory for all build artifacts)'}"
: "${INSTALLPATH:?'INSTALLPATH env var is required (root directory where libs/headers are installed)'}"

# ---------------------------------------------------------------------------
# Defaults for optional variables
# ---------------------------------------------------------------------------
BUILD_CORES="${BUILD_CORES:-v68}"
ALL_CORES="${ALL_CORES:-v68 v69 v71 v71t v73 v75 v77 v79 v81 v83 v85 v87 v89 v91}"
NINJA="${NINJA:-ninja}"
JOBS="${JOBS:-$(nproc)}"

# ---------------------------------------------------------------------------
# Derived paths
# ---------------------------------------------------------------------------
CLANG="${TOOLCHAIN}/bin/hexagon-clang"
CLANGXX="${TOOLCHAIN}/bin/hexagon-clang++"

# Fall back to plain clang/clang++ if hexagon-prefixed variants are absent.
[[ -x "${CLANG}"   ]] || CLANG="${TOOLCHAIN}/bin/clang"
[[ -x "${CLANGXX}" ]] || CLANGXX="${TOOLCHAIN}/bin/clang++"

RUNTIMES_SRC="${SOURCECODE}/runtimes"

RUNTIMES_BUILD_ROOT="${BUILDPATH}/runtimes"
RUNTIMES_INSTALL_ROOT="${BUILDPATH}/runtimes/install"

FINAL_INSTALL="${INSTALLPATH}/Tools"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' not found in PATH"
}

# ---------------------------------------------------------------------------
# build_runtimes_for_triple
#
# Builds runtimes for a specific triple with custom configuration.
#
# Arguments:
#   $1  TRIPLE                  - Target triple (e.g., hexagon-unknown-none-elf)
#   $2  BUILD_PREFIX            - Prefix for build directories (e.g., hexagon)
#   $3  EXTRA_C_FLAGS           - Additional C compiler flags
#   $4  EXTRA_CXX_FLAGS         - Additional C++ compiler flags
#   $5  ENABLE_THREADS          - ON or OFF
#   $6  USE_LIBC                - Libc to use (e.g., picolibc)
#   $7  MONOTONIC_CLOCK         - ON or OFF
#   $8  WIDE_CHARACTERS         - ON or OFF
#   $9  LOCALIZATION            - ON or OFF
#   $10 EXTRA_SITE_DEFINES      - Semicolon-separated list of NAME or NAME=VALUE defines
#                                 baked into the installed __config_site header
#   $11 INSTALL_PREFIX_OVERRIDE - Optional override for the install destination base
#                                 (default: ${FINAL_INSTALL}/target/${TRIPLE})
#                                 Use to install into e.g. target/picolibc/<triple>
# ---------------------------------------------------------------------------
build_runtimes_for_triple() {
    local TRIPLE="$1"
    local BUILD_PREFIX="$2"
    local EXTRA_C_FLAGS="$3"
    local EXTRA_CXX_FLAGS="$4"
    local ENABLE_THREADS="$5"
    local USE_LIBC="$6"
    local MONOTONIC_CLOCK="$7"
    local WIDE_CHARACTERS="$8"
    local LOCALIZATION="$9"
    local EXTRA_SITE_DEFINES="${10:-}"
    local INSTALL_PREFIX_OVERRIDE="${11:-}"
    local DEST_BASE="${INSTALL_PREFIX_OVERRIDE:-${FINAL_INSTALL}/target/${TRIPLE}}"

    log "=== Building runtimes for ${TRIPLE} ==="
    log "Building for cores: ${BUILD_CORES}"
    log "Will copy to all cores: ${ALL_CORES}"

    for CORE in ${BUILD_CORES}; do
        for VARIANT in "non-G0" "G0" "G0-pic"; do
            if [[ "${VARIANT}" == "G0" ]]; then
                VARIANT_SUFFIX="-G0"
                G0_FLAG="-G0"
                DEST_SUFFIX="-G0"
                PIC_FLAG=""
                EXTRA_FLAGS="-O3 -ffunction-sections -fdata-sections"
            elif [[ "${VARIANT}" == "G0-pic" ]]; then
                VARIANT_SUFFIX="-G0-pic"
                G0_FLAG="-G0"
                DEST_SUFFIX="-G0-pic"
                PIC_FLAG="-fPIC"
                EXTRA_FLAGS="-O3 -ffunction-sections -fdata-sections -fvisibility=hidden"
            else
                VARIANT_SUFFIX=""
                G0_FLAG=""
                DEST_SUFFIX=""
                PIC_FLAG=""
                EXTRA_FLAGS="-O3 -ffunction-sections -fdata-sections"
            fi

            log "--- runtimes: ${TRIPLE} ${CORE}${VARIANT_SUFFIX} ---"

            BUILD_DIR="${RUNTIMES_BUILD_ROOT}/build-${BUILD_PREFIX}-${CORE}${VARIANT_SUFFIX}"
            INSTALL_DIR="${RUNTIMES_INSTALL_ROOT}/${BUILD_PREFIX}-${CORE}${VARIANT_SUFFIX}"
            mkdir -p "${BUILD_DIR}" "${INSTALL_DIR}"

            # Combine base flags with extra flags
            COMBINED_C_FLAGS="${G0_FLAG} -m${CORE} ${PIC_FLAG} ${EXTRA_FLAGS} ${EXTRA_C_FLAGS}"
            COMBINED_CXX_FLAGS="${G0_FLAG} -m${CORE} ${PIC_FLAG} ${EXTRA_FLAGS} ${EXTRA_CXX_FLAGS}"

            cmake -G Ninja \
                -DCMAKE_C_COMPILER="${CLANG}" \
                -DCMAKE_CXX_COMPILER="${CLANGXX}" \
                -DCMAKE_C_COMPILER_TARGET="${TRIPLE}" \
                -DCMAKE_CXX_COMPILER_TARGET="${TRIPLE}" \
                -DCMAKE_C_FLAGS="${COMBINED_C_FLAGS}" \
                -DCMAKE_CXX_FLAGS="${COMBINED_CXX_FLAGS}" \
                -DLIBCXX_EXTRA_SITE_DEFINES="${EXTRA_SITE_DEFINES}" \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
                -DCMAKE_CROSSCOMPILING=ON \
                -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
                -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
                -DLIBUNWIND_ENABLE_SHARED=OFF \
                -DLIBUNWIND_ENABLE_THREADS="${ENABLE_THREADS}" \
                -DLIBUNWIND_USE_COMPILER_RT=ON \
                -DLIBUNWIND_IS_BAREMETAL=ON \
                -DLIBCXXABI_ENABLE_SHARED=OFF \
                -DLIBCXXABI_ENABLE_THREADS="${ENABLE_THREADS}" \
                -DLIBCXXABI_BAREMETAL=ON \
                -DLIBCXXABI_USE_COMPILER_RT=ON \
                -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
                -DLIBCXX_CXX_ABI=libcxxabi \
                -DLIBCXX_ENABLE_SHARED=OFF \
                -DLIBCXX_ENABLE_THREADS="${ENABLE_THREADS}" \
                -DLIBCXX_HAS_PTHREAD_API="${ENABLE_THREADS}" \
		-DLIBCXX_ENABLE_TIME_ZONE_DATABASE=OFF \
                -DLIBCXX_ENABLE_EXCEPTIONS=ON \
		-DLIBCXX_ENABLE_FILESYSTEM=${ENABLE_THREADS} \
                -DLIBCXX_ENABLE_MONOTONIC_CLOCK="${MONOTONIC_CLOCK}" \
                -DLIBCXX_ENABLE_RANDOM_DEVICE=OFF \
                -DLIBCXX_ENABLE_RTTI=ON \
                -DLIBCXX_ENABLE_WIDE_CHARACTERS="${WIDE_CHARACTERS}" \
                -DLIBCXX_ENABLE_LOCALIZATION="${LOCALIZATION}" \
                -DLIBCXX_USE_COMPILER_RT=ON \
                -DRUNTIMES_USE_LIBC="${USE_LIBC}" \
                -S "${RUNTIMES_SRC}" \
                -B "${BUILD_DIR}"

            cmake --build "${BUILD_DIR}" -j"${JOBS}" -- install

            # Copy runtimes libs/headers into the final install tree
            DEST_LIB="${DEST_BASE}/lib/${CORE}${DEST_SUFFIX}"
            DEST_INC="${DEST_BASE}/include"
            mkdir -p "${DEST_LIB}" "${DEST_INC}"

            if [[ -d "${INSTALL_DIR}/lib" ]]; then
                cp -rvf "${INSTALL_DIR}/lib/"* "${DEST_LIB}/"
            fi
            if [[ -d "${INSTALL_DIR}/include" ]]; then
                cp -rvf "${INSTALL_DIR}/include/"* "${DEST_INC}/"
            fi
            log "Installed runtimes for ${TRIPLE} ${CORE}${VARIANT_SUFFIX} -> ${DEST_LIB}"
        done
    done

    # ---------------------------------------------------------------------------
    # Copy built libraries to all other architecture versions
    # ---------------------------------------------------------------------------
    log "=== Symlinking runtimes to all architecture versions for ${TRIPLE} ==="

    # Determine the source core (first in BUILD_CORES)
    SOURCE_CORE=$(echo ${BUILD_CORES} | awk '{print $1}')
    log "Using ${SOURCE_CORE} as symlink target for other architectures"

    for CORE in ${ALL_CORES}; do
        # Skip if this core was already built
        if echo "${BUILD_CORES}" | grep -qw "${CORE}"; then
            log "Skipping ${CORE} (already built)"
            continue
        fi

        log "Symlinking libraries for ${CORE} -> ${SOURCE_CORE}"

        LIB_BASE="${DEST_BASE}/lib"

        # Symlink individual files (not directories) so a downstream "cp -drfv"
        # never tries to overwrite an existing real directory with a symlink.
        # Flat layout: variant dirs are siblings under lib/, so the source is
        # always one level up (../<source-core><suffix>).
        for VARIANT_SUFFIX in "" "-G0" "-G0-pic"; do
            SOURCE_VARIANT_DIR="${LIB_BASE}/${SOURCE_CORE}${VARIANT_SUFFIX}"
            DEST_VARIANT_DIR="${LIB_BASE}/${CORE}${VARIANT_SUFFIX}"

            if [[ ! -d "${SOURCE_VARIANT_DIR}" ]]; then
                log "WARNING: Source directory ${SOURCE_VARIANT_DIR} not found, skipping"
                continue
            fi

            mkdir -p "${DEST_VARIANT_DIR}"

            REL_PREFIX="../${SOURCE_CORE}${VARIANT_SUFFIX}"

            for SRC_FILE in "${SOURCE_VARIANT_DIR}"/*; do
                [[ -f "${SRC_FILE}" ]] || continue
                FNAME="$(basename "${SRC_FILE}")"
                DEST_FILE="${DEST_VARIANT_DIR}/${FNAME}"
                rm -f "${DEST_FILE}"
                ln -s "${REL_PREFIX}/${FNAME}" "${DEST_FILE}"
            done
            log "Symlinked runtimes (${VARIANT_SUFFIX:-non-G0}): ${CORE} -> ${SOURCE_CORE}"
        done
    done

    log "=== Build complete for ${TRIPLE} ==="
    log "Install tree: ${DEST_BASE}/"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
log "=== Pre-flight checks ==="
require_tool cmake
require_tool "${NINJA}"

[[ -x "${CLANG}" ]]   || die "hexagon-clang/clang not found (tried ${TOOLCHAIN}/bin/hexagon-clang and ${TOOLCHAIN}/bin/clang)"
[[ -x "${CLANGXX}" ]] || die "hexagon-clang++/clang++ not found (tried ${TOOLCHAIN}/bin/hexagon-clang++ and ${TOOLCHAIN}/bin/clang++)"
[[ -d "${RUNTIMES_SRC}" ]] || die "runtimes source not found at ${RUNTIMES_SRC}"

# Show Hexagon target headers directory structure
HEXAGON_TARGET_DIR="$(realpath "$(dirname "${CLANG}")/../target")"
if [[ -d "${HEXAGON_TARGET_DIR}" ]]; then
    log "=== Hexagon target headers directory structure ==="
    find "${HEXAGON_TARGET_DIR}" -type f
else
    log "WARNING: Hexagon target directory not found at ${HEXAGON_TARGET_DIR}"
fi

mkdir -p "${RUNTIMES_BUILD_ROOT}" "${RUNTIMES_INSTALL_ROOT}"

# ---------------------------------------------------------------------------
# Triple configurations
#
# build_runtimes_for_triple \
#     <triple>          <build-prefix> \
#     <extra-c-flags>   <extra-cxx-flags> \
#     <threads>         <use-libc> \
#     <monotonic-clock> <wide-chars> <localization> \
#     [extra-site-defines]
# ---------------------------------------------------------------------------

# 1. Baremetal: no threads, no localization, no wide chars.
#    CXX flags carry -nostdlib++ -nostdinc++ to avoid pulling in host headers.
build_runtimes_for_triple \
    "hexagon-unknown-none-elf"      "hexagon" \
    "--cstdlib=picolibc"            "--cstdlib=picolibc -nostdlib++ -nostdinc++" \
    "OFF"                           "picolibc" \
    "OFF"                           "OFF" "OFF" \
    ""                              "${FINAL_INSTALL}/target/picolibc/hexagon-unknown-none-elf"

# 2. H2 Linux: threads + localization + wide chars, picolibc defines required.
#    These defines describe the picolibc platform's capabilities and are baked
#    into the installed __config_site header so all downstream consumers see them.
H2_SITE_DEFINES="_GNU_SOURCE=;_PICOLIBC_CTYPE_SMALL=0;_POSIX_TIMERS=1;_POSIX_THREADS"
build_runtimes_for_triple \
    "hexagon-unknown-h2-elf"        "hexagon-h2" \
    "--cstdlib=picolibc"            "--cstdlib=picolibc -nostdlib++ -nostdinc++" \
    "ON"                            "picolibc" \
    "ON"                            "ON" "ON" \
    "${H2_SITE_DEFINES}"            "${FINAL_INSTALL}/target/picolibc/hexagon-unknown-h2-elf"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log "=== All builds complete ==="
