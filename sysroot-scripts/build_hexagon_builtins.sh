#!/usr/bin/env bash
# build_builtins.sh
#
# Builds compiler-rt builtins for Hexagon baremetal, one build per core.
# Produces three install trees from a single build:
#   target/picolibc/hexagon-unknown-none-elf/  (built directly, for --cstdlib=picolibc)
#   target/picolibc/hexagon-unknown-h2-elf/    (symlinked from none-elf, for --cstdlib=picolibc)
#   target/picolibc/hexagon-unknown-qurt-elf/  (copied from none-elf, for --cstdlib=picolibc)
#
# Required environment variables:
#   TOOLCHAIN    - Path to the installed Hexagon LLVM toolchain
#                  e.g. /path/to/inst/Tools
#   SOURCECODE   - Path to the llvm-top source directory
#                  e.g. /path/to/build/llvm-top
#   BUILDPATH    - Root directory for all build artifacts
#                  e.g. /path/to/build
#   INSTALLPATH  - Root directory where libs are installed
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
#   compiler-rt/
#     build-hexagon-<core>-builtins/      (cmake build dir, non-G0)
#     build-hexagon-<core>-builtins-G0/   (cmake build dir, G0)
#     build-hexagon-<core>-builtins-G0-pic/ (cmake build dir, G0 + PIC)
#     install/<core>/                     (intermediate install, non-G0)
#     install/<core>-G0/                  (intermediate install, G0)
#     install/<core>-G0-pic/              (intermediate install, G0 + PIC)
#
# Install layout under INSTALLPATH (flat variant directories):
#   target/
#     picolibc/
#       hexagon-unknown-none-elf/
#         lib/<core>/
#           libclang_rt.builtins.a          (non-G0, built)
#         lib/<core>-G0/
#           libclang_rt.builtins.a          (G0, built)
#         lib/<core>-G0-pic/
#           libclang_rt.builtins.a          (G0 + PIC, built)
#         lib/<other-core>[-G0[-pic]]/<file> -> ../<core>[-G0[-pic]]/<file>  (per-file symlinks for non-built cores)
#       hexagon-unknown-h2-elf/
#         lib/<core>[-G0[-pic]]/<file> -> ../../hexagon-unknown-none-elf/lib/<core>[-G0[-pic]]/<file>  (per-file symlinks)
#       hexagon-unknown-qurt-elf/
#         lib/  (full copy of hexagon-unknown-none-elf/lib/)

set -euo pipefail

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
: "${TOOLCHAIN:?'TOOLCHAIN env var is required (path to installed Hexagon LLVM toolchain)'}"
: "${SOURCECODE:?'SOURCECODE env var is required (path to llvm-top source directory)'}"
: "${BUILDPATH:?'BUILDPATH env var is required (root directory for all build artifacts)'}"
: "${INSTALLPATH:?'INSTALLPATH env var is required (root directory where libs are installed)'}"

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

COMPILER_RT_SRC="${SOURCECODE}/compiler-rt"

COMPILER_RT_BUILD_ROOT="${BUILDPATH}/compiler-rt"
COMPILER_RT_INSTALL_ROOT="${BUILDPATH}/compiler-rt/install"

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
# Pre-flight checks
# ---------------------------------------------------------------------------
log "=== Pre-flight checks ==="
require_tool cmake
require_tool "${NINJA}"

[[ -x "${CLANG}" ]]   || die "hexagon-clang/clang not found (tried ${TOOLCHAIN}/bin/hexagon-clang and ${TOOLCHAIN}/bin/clang)"
[[ -x "${CLANGXX}" ]] || die "hexagon-clang++/clang++ not found (tried ${TOOLCHAIN}/bin/hexagon-clang++ and ${TOOLCHAIN}/bin/clang++)"
[[ -d "${COMPILER_RT_SRC}" ]] || die "compiler-rt source not found at ${COMPILER_RT_SRC}"

mkdir -p "${COMPILER_RT_BUILD_ROOT}" "${COMPILER_RT_INSTALL_ROOT}"

# ---------------------------------------------------------------------------
# Build compiler-rt builtins (G0 and non-G0, one build per core per variant)
# ---------------------------------------------------------------------------
log "=== Building compiler-rt builtins ==="
log "Building for cores: ${BUILD_CORES}"
log "Will copy to all cores: ${ALL_CORES}"

for CORE in ${BUILD_CORES}; do
    for VARIANT in "non-G0" "G0" "G0-pic"; do
        if [[ "${VARIANT}" == "G0" ]]; then
            VARIANT_SUFFIX="-G0"
            G0_FLAG="-G0"
            DEST_SUFFIX="-G0"
            PIC_ENABLED="OFF"
            PIC_FLAG=""
            EXTRA_FLAGS="-O3 -ffunction-sections -fdata-sections"
        elif [[ "${VARIANT}" == "G0-pic" ]]; then
            VARIANT_SUFFIX="-G0-pic"
            G0_FLAG="-G0"
            DEST_SUFFIX="-G0-pic"
            PIC_ENABLED="ON"
            PIC_FLAG="-fPIC"
            EXTRA_FLAGS="-O3 -ffunction-sections -fdata-sections -fvisibility=hidden"
        else
            VARIANT_SUFFIX=""
            G0_FLAG=""
            DEST_SUFFIX=""
            PIC_ENABLED="OFF"
            PIC_FLAG=""
            EXTRA_FLAGS="-O3 -ffunction-sections -fdata-sections"
        fi

        log "--- compiler-rt builtins: ${CORE}${VARIANT_SUFFIX} ---"

        BUILD_DIR="${COMPILER_RT_BUILD_ROOT}/build-hexagon-${CORE}-builtins${VARIANT_SUFFIX}"
        BUILTINS_INSTALL_DIR="${COMPILER_RT_INSTALL_ROOT}/${CORE}${VARIANT_SUFFIX}"
        mkdir -p "${BUILD_DIR}" "${BUILTINS_INSTALL_DIR}"

        cmake -G Ninja \
            -DCMAKE_C_COMPILER="${CLANG}" \
            -DCMAKE_CXX_COMPILER="${CLANGXX}" \
            -DCMAKE_ASM_FLAGS="${G0_FLAG} -mlong-calls -m${CORE} ${PIC_FLAG} ${EXTRA_FLAGS} --cstdlib=picolibc" \
            -DCMAKE_C_FLAGS="${G0_FLAG} -ffreestanding -m${CORE} ${PIC_FLAG} ${EXTRA_FLAGS} --cstdlib=picolibc" \
            -DCMAKE_CXX_FLAGS="${G0_FLAG} -ffreestanding -m${CORE} ${PIC_FLAG} ${EXTRA_FLAGS} --cstdlib=picolibc" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="${BUILTINS_INSTALL_DIR}" \
            -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR:BOOL=ON \
            -DLLVM_TARGET_TRIPLE=hexagon-unknown-none-elf \
            -DCOMPILER_RT_DEFAULT_TARGET_TRIPLE=hexagon-unknown-none-elf \
            -DCOMPILER_RT_BUILD_BUILTINS:BOOL=ON \
            -DCOMPILER_RT_BUILD_SANITIZERS:BOOL=OFF \
            -DCOMPILER_RT_BUILD_XRAY:BOOL=OFF \
            -DCOMPILER_RT_BUILD_LIBFUZZER:BOOL=OFF \
            -DCOMPILER_RT_BUILD_PROFILE:BOOL=OFF \
            -DCOMPILER_RT_BUILD_MEMPROF:BOOL=OFF \
            -DCOMPILER_RT_BUILD_ORC:BOOL=OFF \
            -DCOMPILER_RT_BUILD_GWP_ASAN:BOOL=OFF \
            -DCOMPILER_RT_BUILTINS_ENABLE_PIC:BOOL=${PIC_ENABLED} \
            -DCOMPILER_RT_SUPPORTED_ARCH=hexagon \
            -DCOMPILER_RT_BAREMETAL_BUILD:BOOL=ON \
            -DCMAKE_CROSSCOMPILING:BOOL=ON \
            -DCAN_TARGET_hexagon=1 \
            -DCMAKE_C_COMPILER_FORCED:BOOL=ON \
            -DCMAKE_CXX_COMPILER_FORCED:BOOL=ON \
            -DCMAKE_C_COMPILER_TARGET=hexagon-unknown-none-elf \
            -DCMAKE_CXX_COMPILER_TARGET=hexagon-unknown-none-elf \
            -B "${BUILD_DIR}" \
            -S "${COMPILER_RT_SRC}"

        cmake --build "${BUILD_DIR}" -j"${JOBS}" -- install-builtins

        # Copy the built library into the final install tree.
        # With LLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON the library lands at:
        #   <prefix>/lib/hexagon-unknown-none-elf/libclang_rt.builtins.a
        BUILTIN_LIB_DIR="${BUILTINS_INSTALL_DIR}/lib/hexagon-unknown-none-elf"
        DEST_DIR="${FINAL_INSTALL}/target/picolibc/hexagon-unknown-none-elf/lib/${CORE}${DEST_SUFFIX}"
        mkdir -p "${DEST_DIR}"

        if [[ -f "${BUILTIN_LIB_DIR}/libclang_rt.builtins.a" ]]; then
            cp -v "${BUILTIN_LIB_DIR}/libclang_rt.builtins.a" "${DEST_DIR}/"
            log "Installed libclang_rt.builtins.a -> ${DEST_DIR}"
        else
            log "WARNING: libclang_rt.builtins.a not found in ${BUILTIN_LIB_DIR}"
        fi
    done
done

# ---------------------------------------------------------------------------
# Copy built libraries to all other architecture versions
# ---------------------------------------------------------------------------
log "=== Symlinking builtins to all architecture versions ==="

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

    # Symlink individual files (not directories) so a downstream "cp -drfv"
    # never tries to overwrite an existing real directory with a symlink.
    LIB_BASE="${FINAL_INSTALL}/target/picolibc/hexagon-unknown-none-elf/lib"
    SOURCE_DIR="${LIB_BASE}/${SOURCE_CORE}"
    if [[ -d "${SOURCE_DIR}" ]]; then
        for VARIANT_SUFFIX in "" "-G0" "-G0-pic"; do
            SOURCE_VARIANT_DIR="${LIB_BASE}/${SOURCE_CORE}${VARIANT_SUFFIX}"
            DEST_VARIANT_DIR="${LIB_BASE}/${CORE}${VARIANT_SUFFIX}"

            if [[ ! -d "${SOURCE_VARIANT_DIR}" ]]; then
                continue
            fi

            mkdir -p "${DEST_VARIANT_DIR}"

            # Flat layout: variant dirs are siblings under lib/, so the source
            # is always one level up (../<source-core><suffix>).
            REL_PREFIX="../${SOURCE_CORE}${VARIANT_SUFFIX}"

            for SRC_FILE in "${SOURCE_VARIANT_DIR}"/*; do
                [[ -f "${SRC_FILE}" ]] || continue
                FNAME="$(basename "${SRC_FILE}")"
                DEST_FILE="${DEST_VARIANT_DIR}/${FNAME}"
                rm -f "${DEST_FILE}"
                ln -s "${REL_PREFIX}/${FNAME}" "${DEST_FILE}"
            done
        done
        log "Symlinked builtins (per-file): ${CORE} -> ${SOURCE_CORE}"
    else
        log "WARNING: Source directory ${SOURCE_DIR} not found"
    fi
done

# ---------------------------------------------------------------------------
# Symlink builtins to target/picolibc/hexagon-unknown-h2-elf/
#
# hexagon-unknown-h2-elf uses the same builtins as hexagon-unknown-none-elf.
# Create per-file symlinks pointing back into the none-elf tree.
# ---------------------------------------------------------------------------
log "=== Symlinking builtins: picolibc/hexagon-unknown-h2-elf -> picolibc/hexagon-unknown-none-elf ==="

SOURCE_LIB_DIR="${FINAL_INSTALL}/target/picolibc/hexagon-unknown-none-elf/lib"
DEST_LIB_DIR="${FINAL_INSTALL}/target/picolibc/hexagon-unknown-h2-elf/lib"

if [[ -d "${SOURCE_LIB_DIR}" ]]; then
    for CORE_DIR in "${SOURCE_LIB_DIR}"/*/; do
        CORE_NAME="$(basename "${CORE_DIR}")"
        SOURCE_VARIANT_DIR="${SOURCE_LIB_DIR}/${CORE_NAME}"
        DEST_VARIANT_DIR="${DEST_LIB_DIR}/${CORE_NAME}"

        if [[ ! -d "${SOURCE_VARIANT_DIR}" ]]; then
            continue
        fi

        mkdir -p "${DEST_VARIANT_DIR}"

        # Flat layout: <core-name> already carries any -G0/-G0-pic suffix, so
        # from h2-elf/lib/<core-name>/ the none-elf sibling tree is three
        # levels up (../../../hexagon-unknown-none-elf/lib/<core-name>).
        REL_PREFIX="../../../hexagon-unknown-none-elf/lib/${CORE_NAME}"

        for SRC_FILE in "${SOURCE_VARIANT_DIR}"/*; do
            [[ -f "${SRC_FILE}" || -L "${SRC_FILE}" ]] || continue
            FNAME="$(basename "${SRC_FILE}")"
            DEST_FILE="${DEST_VARIANT_DIR}/${FNAME}"
            rm -f "${DEST_FILE}"
            ln -s "${REL_PREFIX}/${FNAME}" "${DEST_FILE}"
        done
    done
    log "Symlinked builtins (per-file): picolibc/hexagon-unknown-h2-elf/lib -> picolibc/hexagon-unknown-none-elf/lib"
else
    log "WARNING: Source directory ${SOURCE_LIB_DIR} not found, skipping symlink"
fi

# ---------------------------------------------------------------------------
# Copy builtins to target/picolibc/hexagon-unknown-qurt-elf/
#
# hexagon-unknown-qurt-elf uses the same builtins as hexagon-unknown-none-elf.
# Copy the full lib tree so qurt consumers get real files, not symlinks.
# ---------------------------------------------------------------------------
log "=== Copying builtins: picolibc/hexagon-unknown-none-elf -> picolibc/hexagon-unknown-qurt-elf ==="

QURT_LIB_DIR="${FINAL_INSTALL}/target/picolibc/hexagon-unknown-qurt-elf/lib"

if [[ -d "${SOURCE_LIB_DIR}" ]]; then
    mkdir -p "${FINAL_INSTALL}/target/picolibc/hexagon-unknown-qurt-elf"
    cp -rL "${SOURCE_LIB_DIR}" "${QURT_LIB_DIR}"
    log "Copied builtins: picolibc/hexagon-unknown-qurt-elf/lib"
else
    log "WARNING: Source directory ${SOURCE_LIB_DIR} not found, skipping copy"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log "=== Build complete ==="
log "Install tree: ${FINAL_INSTALL}/target/picolibc/hexagon-unknown-none-elf/"
log "Install tree: ${FINAL_INSTALL}/target/picolibc/hexagon-unknown-h2-elf/"
log "Install tree: ${FINAL_INSTALL}/target/picolibc/hexagon-unknown-qurt-elf/"
