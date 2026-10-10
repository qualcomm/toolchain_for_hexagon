#!/usr/bin/env bash
# build_hexagon_h2.sh
#
# Builds H2 libraries for Hexagon base architectures (68, 73, 81), fans the
# artifacts out to all supported architecture versions, then packages them
# directly into the Tools/target/picolibc/hexagon-unknown-h2-elf install tree.
#
# Required environment variables:
#   TOOLCHAIN    - Path to the installed Hexagon LLVM toolchain
#                  e.g. /path/to/inst/Tools
#   H2_SRC       - Path to the H2 source directory (contains Makefile)
#                  e.g. /path/to/h2
#   BUILDPATH    - Root directory for all build artifacts
#                  e.g. /path/to/build
#   INSTALLPATH  - Root directory where libs/headers are installed
#                  e.g. /path/to/install
#
#
# Build layout under BUILDPATH:
#   h2-install-<base>/               (intermediate per-base make install, base = 68|73|81)
#   h2-install-<version>/            (per-version fanout, e.g. h2-install-v68)
#
# Install layout under INSTALLPATH:
#   Tools/
#     target/
#       picolibc/
#         hexagon-unknown-h2-elf/
#           bin/<version>/G0/        (binaries, copied from h2-install-<version>/bin)
#           bin/<version>/           (per-file symlinks -> G0/<file>, for non-G0 applications)
#           lib/<version>-G0/        (libraries, copied from h2-install-<version>/lib)
#           lib/<version>/           (per-file symlinks -> ../<version>-G0/<file>, for non-G0 applications)
#           include/                 (headers, from h2-install-v81/include)
#
# Base architecture to version fanout:
#   68  ->  v68 v69 v71t v71
#   73  ->  v73 v75 v77 v79
#   81  ->  v81 v83 v85 v87 v89 v91

set -euo pipefail

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
: "${TOOLCHAIN:?'TOOLCHAIN env var is required (path to installed Hexagon LLVM toolchain)'}"
: "${H2_SRC:?'H2_SRC env var is required (path to H2 source directory)'}"
: "${BUILDPATH:?'BUILDPATH env var is required (root directory for all build artifacts)'}"
: "${INSTALLPATH:?'INSTALLPATH env var is required (root directory where libs/headers are installed)'}"

# ---------------------------------------------------------------------------
# Derived paths
# ---------------------------------------------------------------------------
CLANG="${TOOLCHAIN}/bin/hexagon-clang"

# Fall back to plain clang if the hexagon-prefixed variant is absent.
[[ -x "${CLANG}" ]] || CLANG="${TOOLCHAIN}/bin/clang"

export PATH="${TOOLCHAIN}/bin:${PATH}"

H2_INSTALL_ROOT="${BUILDPATH}/h2-install"
FINAL_INSTALL="${INSTALLPATH}/Tools"

ELF_TRIPLE="hexagon-unknown-h2-elf"
OUTDIR="${FINAL_INSTALL}/target/picolibc/${ELF_TRIPLE}"

VERSIONS=(v68 v69 v71t v71 v73 v75 v77 v79 v81 v83 v85 v87 v89 v91)

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
require_tool make

[[ -x "${CLANG}" ]]  || die "hexagon-clang/clang not found (tried ${TOOLCHAIN}/bin/hexagon-clang and ${TOOLCHAIN}/bin/clang)"
[[ -d "${H2_SRC}" ]] || die "H2 source not found at ${H2_SRC}"

log "H2 src:  ${H2_SRC}"
log "Output:  ${OUTDIR}"

mkdir -p "${H2_INSTALL_ROOT}"

# ---------------------------------------------------------------------------
# Build H2 for base architectures 68, 73, 81
# ---------------------------------------------------------------------------
log "=== Build H2 for base ARCHV 68, 73, 81 ==="

# Clean previous install fanouts to avoid mixing artifacts
log "Cleaning previous fanout dirs under ${H2_INSTALL_ROOT}"
rm -rf "${H2_INSTALL_ROOT}"-v*

for base in 68 73 81; do
    log "== Removing ${BUILDPATH}/build and ${H2_INSTALL_ROOT}-${base}"
    rm -rf "${BUILDPATH}/build/"
    rm -rf "${H2_INSTALL_ROOT}-${base}/"

    log "== Building ARCHV=${base}"
    make -j1 -C "${H2_SRC}" \
        USE_PKW=0 \
        ARCHV="${base}" \
        TARGET=opt \
        INSTALLPATH="${H2_INSTALL_ROOT}-${base}" \
        PICOLIBC=1 \
        NULL_ANGEL_TRAP=1 \
        JFLAG="-j1"
done

# ---------------------------------------------------------------------------
# Fan out per-version copies
# ---------------------------------------------------------------------------
log "=== Fanning out per-version install trees ==="

# Base 68 -> v68 v69 v71t v71
for v in v68 v69 v71t v71; do
    log "Copying install-68 -> ${H2_INSTALL_ROOT}-${v}"
    rm -rf "${H2_INSTALL_ROOT}-${v}"
    cp -a "${H2_INSTALL_ROOT}-68" "${H2_INSTALL_ROOT}-${v}"
done

# Base 73 -> v73 v75 v77 v79
for v in v73 v75 v77 v79; do
    log "Copying install-73 -> ${H2_INSTALL_ROOT}-${v}"
    rm -rf "${H2_INSTALL_ROOT}-${v}"
    cp -a "${H2_INSTALL_ROOT}-73" "${H2_INSTALL_ROOT}-${v}"
done

# Base 81 -> v81 v83 v85 v87 v89 v91
for v in v81 v83 v85 v87 v89 v91; do
    log "Copying install-81 -> ${H2_INSTALL_ROOT}-${v}"
    rm -rf "${H2_INSTALL_ROOT}-${v}"
    cp -a "${H2_INSTALL_ROOT}-81" "${H2_INSTALL_ROOT}-${v}"
done

log "=== Build & fan-out complete ==="

# ---------------------------------------------------------------------------
# Package artifacts into the Tools install tree
# ---------------------------------------------------------------------------
log "=== Copying H2 artifacts into ${OUTDIR} ==="

mkdir -p "${OUTDIR}"

# 1) Copy bin into target/picolibc/<elf>/bin/<version>/G0
log "== Copying bin to ${ELF_TRIPLE}/bin/<version>/G0 =="
for v in "${VERSIONS[@]}"; do
    src="${H2_INSTALL_ROOT}-${v}/bin"
    dst="${OUTDIR}/bin/${v}/G0"
    mkdir -p "${dst}"
    if [[ -d "${src}" ]]; then
        cp -a "${src}/." "${dst}/"
    fi
done

# 1b) Symlink non-G0 -> G0 for bin (files placed directly under bin/<version>/)
log "== Symlinking bin non-G0 -> G0 for ${ELF_TRIPLE} =="
for v in "${VERSIONS[@]}"; do
    src="${OUTDIR}/bin/${v}/G0"
    dst="${OUTDIR}/bin/${v}"
    if [[ -d "${src}" ]]; then
        for f in "${src}"/*; do
            [[ -e "${f}" || -L "${f}" ]] || continue
            fname="$(basename "${f}")"
            rm -f "${dst}/${fname}"
            ln -s "G0/${fname}" "${dst}/${fname}"
        done
    fi
done

# 2) Copy libs into target/picolibc/<elf>/lib/<version>-G0
log "== Copying libs to ${ELF_TRIPLE}/lib/<version>-G0 =="
for v in "${VERSIONS[@]}"; do
    src="${H2_INSTALL_ROOT}-${v}/lib"
    dst="${OUTDIR}/lib/${v}-G0"
    mkdir -p "${dst}"
    if [[ -d "${src}" ]]; then
        cp -a "${src}/." "${dst}/"
    fi
done

# 2b) Symlink non-G0 -> G0 for lib (files placed directly under lib/<version>/)
#     Flat layout: lib/<version> and lib/<version>-G0 are siblings, so the
#     link target is ../<version>-G0/<file>.
log "== Symlinking lib non-G0 -> G0 for ${ELF_TRIPLE} =="
for v in "${VERSIONS[@]}"; do
    src="${OUTDIR}/lib/${v}-G0"
    dst="${OUTDIR}/lib/${v}"
    if [[ -d "${src}" ]]; then
        mkdir -p "${dst}"
        for f in "${src}"/*; do
            [[ -e "${f}" || -L "${f}" ]] || continue
            fname="$(basename "${f}")"
            rm -f "${dst}/${fname}"
            ln -s "../${v}-G0/${fname}" "${dst}/${fname}"
        done
    fi
done

# 3) Copy includes into target/picolibc/<elf>/include/ (use v81 as the header source)
log "== Copying includes to ${ELF_TRIPLE}/include =="
inc_src="${H2_INSTALL_ROOT}-v81/include"
inc_dst="${OUTDIR}/include"
mkdir -p "${inc_dst}"
if [[ -d "${inc_src}" ]]; then
    cp -a "${inc_src}/." "${inc_dst}/"
fi

# ---------------------------------------------------------------------------
# Install clang config file
# ---------------------------------------------------------------------------
log "=== Installing h2-picolibc.cfg ==="
mkdir -p "${FINAL_INSTALL}/bin"
cat > "${FINAL_INSTALL}/bin/h2-picolibc.cfg" <<'EOF'
--target=hexagon-unknown-h2-elf \
--cstdlib=picolibc \
$-Wl,--undefined=__retarget_lock_init \
$-Wl,-l:liblocks.a \
$-Wl,--section-start=.start=0x2000000 \
$-Wl,-T,<CFGDIR>/../templates/staticExecutable/static-executable-h2-picolibc.lcs.template
EOF
log "Installed cfg -> ${FINAL_INSTALL}/bin/h2-picolibc.cfg"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log "=== Build complete ==="
log "Install tree: ${OUTDIR}/"
