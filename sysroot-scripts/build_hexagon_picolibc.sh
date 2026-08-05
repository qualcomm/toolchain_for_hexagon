#!/usr/bin/env bash
# build_hexagon_picolibc.sh
#
# Builds picolibc for all Hexagon cores (G0, non-G0, and G0+PIC) and installs
# into Tools/target/picolibc/hexagon-unknown-{none,h2,qurt}-elf structure.
# The G0+PIC variant is built with the local-dynamic TLS model
# (-Dtls-model=local-dynamic) for use in shared-library contexts.
#
# Required environment variables:
#   TOOLCHAIN    - Path to the installed Hexagon LLVM toolchain
#                  e.g. /path/to/inst/Tools
#   PICOLIBC_SRC - Path to the picolibc source directory (contains meson.build)
#                  e.g. /path/to/picolibc
#   BUILDPATH    - Root directory for all build artifacts
#                  e.g. /path/to/build
#   INSTALLPATH  - Root directory where libs/headers are installed
#                  e.g. /path/to/install
#
# Optional environment variables:
#   BUILD_CORES    - Space-separated list of Hexagon arch versions to actually build
#                    (default: "v68")
#   ALL_CORES      - Space-separated list of all Hexagon arch versions to install for
#                    (default: "v68 v69 v71 v71t v73 v75 v77 v79 v81 v83 v85 v87 v89 v91")
#   BUILD_VARIANTS - Space-separated list of variants to build: non-G0, G0, G0-pic
#                    (default: "non-G0 G0 G0-pic")
#   TEST           - Set to 1 to enable tests (default: 0)
#   MESON          - Path to the meson executable (default: meson)
#   NINJA          - Path to the ninja executable (default: ninja)
#   JOBS           - Parallel jobs for ninja (default: number of CPU cores)
#
# Build layout under BUILDPATH:
#   picolibc-build/
#     build-picolibc-<core>/           (meson build dir, non-G0)
#     build-picolibc-<core>-G0/        (meson build dir, G0)
#     build-picolibc-<core>-G0-pic/    (meson build dir, G0 + PIC)
#   picolibc-install/
#     <core>/                          (intermediate install, non-G0)
#     <core>-G0/                       (intermediate install, G0)
#     <core>-G0-pic/                   (intermediate install, G0 + PIC)
#
# Install layout under INSTALLPATH (flat variant directories):
#   Tools/
#     target/
#       picolibc/
#         hexagon-unknown-none-elf/
#           include/
#           lib/<core>/
#             libc.a  libm.a  ...      (non-G0, built)
#           lib/<core>-G0/
#             libc.a  libm.a  ...      (G0, built)
#           lib/<core>-G0-pic/
#             libc.a  libm.a  ...      (G0 + PIC, local-dynamic TLS, built)
#           lib/<other-core>[-G0[-pic]]/  (per-file symlinks into lib/<core>[-G0[-pic]]/)
#         hexagon-unknown-h2-elf/      (per-file symlinks into hexagon-unknown-none-elf)
#         hexagon-unknown-qurt-elf/    (copy of hexagon-unknown-none-elf)

set -euo pipefail

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
: "${TOOLCHAIN:?'TOOLCHAIN env var is required (path to installed Hexagon LLVM toolchain)'}"
: "${PICOLIBC_SRC:?'PICOLIBC_SRC env var is required (path to picolibc source directory)'}"
: "${BUILDPATH:?'BUILDPATH env var is required (root directory for all build artifacts)'}"
: "${INSTALLPATH:?'INSTALLPATH env var is required (root directory where libs/headers are installed)'}"

# ---------------------------------------------------------------------------
# Defaults for optional variables
# ---------------------------------------------------------------------------
BUILD_CORES="${BUILD_CORES:-v68}"
ALL_CORES="${ALL_CORES:-v68 v69 v71 v71t v73 v75 v77 v79 v81 v83 v85 v87 v89 v91}"
BUILD_VARIANTS="${BUILD_VARIANTS:-non-G0 G0 G0-pic}"
ENABLE_TESTS="${TEST:-0}"
MESON="${MESON:-meson}"
NINJA="${NINJA:-ninja}"
JOBS="${JOBS:-$(nproc)}"

# ---------------------------------------------------------------------------
# Cross-file generation settings
# ---------------------------------------------------------------------------
CROSS_TARGET="hexagon-unknown-none-elf"
CROSS_SYSTEM="linux"
CROSS_CPU_FAMILY="hexagon"
CROSS_CPU="hexagon"
CROSS_ENDIAN="little"

# Flags common to all variants
CROSS_COMMON_CFLAGS=(
    "--target=${CROSS_TARGET}"
    "--cstdlib=picolibc"
    "-nostdlib"
    "-ffunction-sections"
    "-fdata-sections"
    "-fvisibility=hidden"
)
CROSS_COMMON_LINK_ARGS=(
    "--target=${CROSS_TARGET}"
    "--cstdlib=picolibc"
    "-nostdlib"
)

# Per-variant extra c_args (prepended before common flags)
# non-G0: no small-data, no PIC
CROSS_NON_G0_EXTRA_CFLAGS=( "-fno-pic" "-fno-PIE" "-static" )

# G0: small-data model, no PIC
CROSS_G0_EXTRA_CFLAGS=( "-fno-pic" "-fno-PIE" "-static" "-G0" )

# G0-pic: small-data model, PIC, local-dynamic TLS
CROSS_G0_PIC_EXTRA_CFLAGS=( "-fPIC" "-static" "-G0" )

# [properties] values (identical across all variants)
CROSS_LIBRT="-lclang_rt.builtins"
CROSS_LINK_SPEC="--build-id=none"
CROSS_SDATA_ALIGNMENT="64"
CROSS_DEFAULT_RAM_ADDR="0x00500000"
CROSS_DEFAULT_RAM_SIZE="0x00800000"
CROSS_DEFAULT_FLASH_ADDR="0x00100000"
CROSS_DEFAULT_FLASH_SIZE="0x00400000"

# ---------------------------------------------------------------------------
# generate_cross_file CORE VARIANT
#   Emits a Meson cross file to stdout.
#   VARIANT - one of: non-G0  G0  G0-pic
# ---------------------------------------------------------------------------
generate_cross_file() {
    local CORE="$1"
    local VARIANT="$2"
    local -a CFLAGS=()

    case "${VARIANT}" in
        non-G0)
            CFLAGS+=( "${CROSS_NON_G0_EXTRA_CFLAGS[@]}" )
            ;;
        G0)
            CFLAGS+=( "${CROSS_G0_EXTRA_CFLAGS[@]}" )
            ;;
        G0-pic)
            CFLAGS+=( "${CROSS_G0_PIC_EXTRA_CFLAGS[@]}" )
            ;;
        *)
            die "generate_cross_file: unknown variant '${VARIANT}'"
            ;;
    esac

    CFLAGS+=( "-m${CORE}" "${CROSS_COMMON_CFLAGS[@]}" )

    local C_ARGS_STR=""
    local FLAG
    for FLAG in "${CFLAGS[@]}"; do
        C_ARGS_STR+="'${FLAG}', "
    done
    C_ARGS_STR="[ ${C_ARGS_STR%, } ]"

    local C_LINK_ARGS_STR=""
    for FLAG in "${CROSS_COMMON_LINK_ARGS[@]}"; do
        C_LINK_ARGS_STR+="'${FLAG}', "
    done
    C_LINK_ARGS_STR="[ ${C_LINK_ARGS_STR%, } ]"

    cat <<EOF
[binaries]
c = '${MESON_C}'
cpp = '${MESON_CXX}'
c_ld = 'eld'
ar = 'hexagon-ar'
as = 'as'
nm = 'hexagon-nm'
strip = 'hexagon-strip'
objcopy = 'hexagon-llvm-objcopy'
# only needed to run tests
exe_wrapper = ['env', 'run-hexagon']

[host_machine]
system = '${CROSS_SYSTEM}'
cpu_family = '${CROSS_CPU_FAMILY}'
cpu = '${CROSS_CPU}'
endian = '${CROSS_ENDIAN}'

[built-in options]
c_args = ${C_ARGS_STR}
c_link_args = ${C_LINK_ARGS_STR}
cpp_args = ${C_ARGS_STR}
cpp_link_args = ${C_LINK_ARGS_STR}

[properties]
librt = '${CROSS_LIBRT}'
skip_sanity_check = true
needs_exe_wrapper = true
link_spec = '${CROSS_LINK_SPEC}'
sdata_alignment = '${CROSS_SDATA_ALIGNMENT}'
default_ram_addr   = '${CROSS_DEFAULT_RAM_ADDR}'
default_ram_size   = '${CROSS_DEFAULT_RAM_SIZE}'
default_flash_addr = '${CROSS_DEFAULT_FLASH_ADDR}'
default_flash_size = '${CROSS_DEFAULT_FLASH_SIZE}'
EOF
}

# ---------------------------------------------------------------------------
# Derived paths
# ---------------------------------------------------------------------------
CLANG="${TOOLCHAIN}/bin/hexagon-clang"
CLANGXX="${TOOLCHAIN}/bin/hexagon-clang++"

# Fall back to plain clang/clang++ if hexagon-prefixed variants are absent.
# MESON_C / MESON_CXX carry the (bare) tool names emitted into the Meson
# cross-file; PATH is prepended with ${TOOLCHAIN}/bin below so bare names
# resolve to the correct toolchain binary.
MESON_C="hexagon-clang"
MESON_CXX="hexagon-clang++"
if [[ ! -x "${CLANG}" ]]; then
    CLANG="${TOOLCHAIN}/bin/clang"
    MESON_C="clang"
fi
if [[ ! -x "${CLANGXX}" ]]; then
    CLANGXX="${TOOLCHAIN}/bin/clang++"
    MESON_CXX="clang++"
fi

export PATH="${TOOLCHAIN}/bin:${PATH}"

PICOLIBC_BUILD_ROOT="${BUILDPATH}/picolibc-build"
PICOLIBC_INSTALL_ROOT="${BUILDPATH}/picolibc-install"

FINAL_INSTALL="${INSTALLPATH}/Tools"
OUTDIR="${FINAL_INSTALL}/target/picolibc/hexagon-unknown-none-elf"
H2_OUTDIR="${FINAL_INSTALL}/target/picolibc/hexagon-unknown-h2-elf"

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
require_tool "${MESON}"
require_tool "${NINJA}"
require_tool git

[[ -x "${CLANG}" ]]        || die "hexagon-clang/clang not found (tried ${TOOLCHAIN}/bin/hexagon-clang and ${TOOLCHAIN}/bin/clang)"
[[ -x "${CLANGXX}" ]]      || die "hexagon-clang++/clang++ not found (tried ${TOOLCHAIN}/bin/hexagon-clang++ and ${TOOLCHAIN}/bin/clang++)"
[[ -d "${PICOLIBC_SRC}" ]] || die "picolibc source not found at ${PICOLIBC_SRC}"

if [[ "${ENABLE_TESTS}" == "1" ]]; then
    TEST_FLAGS="-Dtests=true -Dtests-enable-posix-io=true -Dtest-stdin=true"
    log "Tests: ENABLED"
else
    TEST_FLAGS="-Dtests=false"
    log "Tests: DISABLED"
fi

log "Picolibc src: ${PICOLIBC_SRC}"
log "Building for cores: ${BUILD_CORES}"
log "Building variants:  ${BUILD_VARIANTS}"
log "Will symlink to all cores: ${ALL_CORES}"
log "Output:  ${OUTDIR}"

mkdir -p "${PICOLIBC_BUILD_ROOT}" "${PICOLIBC_INSTALL_ROOT}" "${OUTDIR}/include" "${OUTDIR}/lib"

# ---------------------------------------------------------------------------
# Build picolibc (non-G0, G0, and G0+PIC — one build per core per variant)
# ---------------------------------------------------------------------------
log "=== Building picolibc ==="

TEST_FAILED=0

for CORE in ${BUILD_CORES}; do
    for VARIANT in ${BUILD_VARIANTS}; do
        case "${VARIANT}" in
            non-G0)
                VARIANT_SUFFIX=""
                DEST_SUFFIX=""
                MESON_EXTRA_OPTS=""
                ;;
            G0)
                VARIANT_SUFFIX="-G0"
                DEST_SUFFIX="-G0"
                MESON_EXTRA_OPTS=""
                ;;
            G0-pic)
                VARIANT_SUFFIX="-G0-pic"
                DEST_SUFFIX="-G0-pic"
                MESON_EXTRA_OPTS="-Dtls-model=local-dynamic"
                ;;
        esac

        log "--- picolibc: ${CORE}${VARIANT_SUFFIX} ---"

        CROSS_FILE="${PICOLIBC_BUILD_ROOT}/cross-clang-hexagon-${CORE}${VARIANT_SUFFIX}.txt"
        generate_cross_file "${CORE}" "${VARIANT}" > "${CROSS_FILE}"
        log "Generated cross file: ${CROSS_FILE}"
        log "--- cross file contents ---"
        cat "${CROSS_FILE}"
        log "--- end cross file ---"

        BUILD_DIR="${PICOLIBC_BUILD_ROOT}/build-picolibc-${CORE}${VARIANT_SUFFIX}"
        INSTALL_DIR="${PICOLIBC_INSTALL_ROOT}/${CORE}${VARIANT_SUFFIX}"
        mkdir -p "${BUILD_DIR}" "${INSTALL_DIR}"

        "${MESON}" setup "${BUILD_DIR}" "${PICOLIBC_SRC}" \
            --buildtype=release \
            --cross-file="${CROSS_FILE}" \
            --prefix="${INSTALL_DIR}" \
            ${TEST_FLAGS} \
            ${MESON_EXTRA_OPTS} \
            -Dstdio-locking=true \
            -Dstdio-exit-flush=true \
            -Dmultilib=false \
            -Dposix-console=true

        "${NINJA}" -C "${BUILD_DIR}" -j"${JOBS}"
        "${NINJA}" -C "${BUILD_DIR}" install

        if [[ "${ENABLE_TESTS}" == "1" ]]; then
            log "--- running tests: ${CORE}${VARIANT_SUFFIX} ---"
            "${MESON}" test -C "${BUILD_DIR}" -t 20 \
                || { log "ERROR: tests failed for ${CORE}${VARIANT_SUFFIX}"; TEST_FAILED=1; }
        fi

        DEST_LIB="${OUTDIR}/lib/${CORE}${DEST_SUFFIX}"
        mkdir -p "${DEST_LIB}"

        if [[ -d "${INSTALL_DIR}/lib" ]]; then
            cp -a "${INSTALL_DIR}/lib/." "${DEST_LIB}/"
        else
            log "WARNING: no lib dir found at ${INSTALL_DIR}/lib"
        fi
        log "Installed picolibc for ${CORE}${VARIANT_SUFFIX} -> ${DEST_LIB}"
    done
done

# ---------------------------------------------------------------------------
# Copy headers (use G0 of first core; identical across all cores and variants)
# ---------------------------------------------------------------------------
FIRST_CORE="${BUILD_CORES%% *}"
SRC_INC="${PICOLIBC_INSTALL_ROOT}/${FIRST_CORE}-G0/include"
if [[ ! -d "${SRC_INC}" ]]; then
    SRC_INC="$(find "${PICOLIBC_INSTALL_ROOT}" -maxdepth 3 -type d -name include | head -n1 || true)"
fi
[[ -d "${SRC_INC}" ]] || die "could not find installed headers under ${PICOLIBC_INSTALL_ROOT}"
cp -a "${SRC_INC}/." "${OUTDIR}/include/"
log "Installed headers -> ${OUTDIR}/include"

# ---------------------------------------------------------------------------
# Symlink built libraries to all other architecture versions
#
# Per-file symlinks (not directory symlinks) so downstream "cp -drfv" can
# descend into real directories without "cannot overwrite directory" errors.
#
# Flat layout: variant dirs are siblings under lib/, so relative path from
# lib/<core><suffix>/ back to lib/<source><suffix>/ is always one level up:
#   lib/<core>/          -> ../<source>/
#   lib/<core>-G0/       -> ../<source>-G0/
#   lib/<core>-G0-pic/   -> ../<source>-G0-pic/
# ---------------------------------------------------------------------------
log "=== Symlinking picolibc to all architecture versions ==="

SOURCE_CORE=$(echo ${BUILD_CORES} | awk '{print $1}')
log "Using ${SOURCE_CORE} as source for symlinking to other architectures"

for CORE in ${ALL_CORES}; do
    if echo "${BUILD_CORES}" | grep -qw "${CORE}"; then
        log "Skipping ${CORE} (already built)"
        continue
    fi

    log "Symlinking libraries for ${CORE} from ${SOURCE_CORE}"

    for VARIANT_SUFFIX in "" "-G0" "-G0-pic"; do
        REL_PREFIX="../"

        SRC_DIR="${OUTDIR}/lib/${SOURCE_CORE}${VARIANT_SUFFIX}"
        DST_DIR="${OUTDIR}/lib/${CORE}${VARIANT_SUFFIX}"

        if [[ ! -d "${SRC_DIR}" ]]; then
            log "WARNING: source directory ${SRC_DIR} not found, skipping"
            continue
        fi

        mkdir -p "${DST_DIR}"

        for SRC_FILE in "${SRC_DIR}"/*; do
            [[ -e "${SRC_FILE}" || -L "${SRC_FILE}" ]] || continue
            FNAME="$(basename "${SRC_FILE}")"
            # Skip real subdirectories; nothing nested is expected in flat layout
            [[ -d "${SRC_FILE}" && ! -L "${SRC_FILE}" ]] && continue
            ln -sf "${REL_PREFIX}${SOURCE_CORE}${VARIANT_SUFFIX}/${FNAME}" \
                "${DST_DIR}/${FNAME}"
        done

        log "Symlinked ${VARIANT_SUFFIX:-non-G0} picolibc: ${SOURCE_CORE} -> ${CORE}"
    done
done

# ---------------------------------------------------------------------------
# Symlink hexagon-unknown-none-elf -> hexagon-unknown-h2-elf
#
# H2_OUTDIR is a sibling of OUTDIR under target/picolibc/. With the flat
# layout each <core><suffix> is a direct child of lib/, so relative paths
# from H2_OUTDIR/lib/<core><suffix>/ back to OUTDIR/lib/<core><suffix>/ are
# always three levels up:
#   lib/<core>/          -> ../../../hexagon-unknown-none-elf/lib/<core>/
#   lib/<core>-G0/       -> ../../../hexagon-unknown-none-elf/lib/<core>-G0/
#   lib/<core>-G0-pic/   -> ../../../hexagon-unknown-none-elf/lib/<core>-G0-pic/
# ---------------------------------------------------------------------------
NONE_TRIPLE="hexagon-unknown-none-elf"

log "Symlinking ${OUTDIR} -> ${H2_OUTDIR}"
rm -rf "${H2_OUTDIR}"
mkdir -p "${H2_OUTDIR}/include" "${H2_OUTDIR}/lib"

for SRC_FILE in "${OUTDIR}/include"/*; do
    [[ -e "${SRC_FILE}" || -L "${SRC_FILE}" ]] || continue
    FNAME="$(basename "${SRC_FILE}")"
    ln -sf "../../${NONE_TRIPLE}/include/${FNAME}" "${H2_OUTDIR}/include/${FNAME}"
done
log "Symlinked headers -> ${H2_OUTDIR}/include"

for CORE_DIR in "${OUTDIR}/lib"/*/; do
    [[ -d "${CORE_DIR}" ]] || continue
    CORE="$(basename "${CORE_DIR}")"

    SRC_DIR="${OUTDIR}/lib/${CORE}"
    DST_DIR="${H2_OUTDIR}/lib/${CORE}"

    [[ -d "${SRC_DIR}" ]] || continue
    mkdir -p "${DST_DIR}"

    # Flat layout: <core> already carries any -G0/-G0-pic suffix.
    REL_PREFIX="../../../"

    for SRC_FILE in "${SRC_DIR}"/*; do
        [[ -e "${SRC_FILE}" || -L "${SRC_FILE}" ]] || continue
        FNAME="$(basename "${SRC_FILE}")"
        [[ -d "${SRC_FILE}" && ! -L "${SRC_FILE}" ]] && continue
        ln -sf "${REL_PREFIX}${NONE_TRIPLE}/lib/${CORE}/${FNAME}" \
            "${DST_DIR}/${FNAME}"
    done
done
log "Symlinked H2 artifacts -> ${H2_OUTDIR}"

# ---------------------------------------------------------------------------
# Copy hexagon-unknown-none-elf -> hexagon-unknown-qurt-elf
#
# Artifacts are identical to none-elf; only the --target= triple differs and
# has no effect on object code, so we copy rather than rebuild.
# ---------------------------------------------------------------------------
QURT_OUTDIR="${FINAL_INSTALL}/target/picolibc/hexagon-unknown-qurt-elf"

log "Copying ${OUTDIR} -> ${QURT_OUTDIR}"
rm -rf "${QURT_OUTDIR}"
cp -a "${OUTDIR}" "${QURT_OUTDIR}"
log "Copied artifacts -> ${QURT_OUTDIR}"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log "=== Build complete ==="
log "Install tree: ${FINAL_INSTALL}/target/picolibc/hexagon-unknown-none-elf/"
log "Install tree: ${FINAL_INSTALL}/target/picolibc/hexagon-unknown-h2-elf/"
log "Install tree: ${FINAL_INSTALL}/target/picolibc/hexagon-unknown-qurt-elf/"

if [[ "${ENABLE_TESTS}" == "1" && "${TEST_FAILED}" -ne 0 ]]; then
    die "one or more test variants failed — see above for details"
fi
