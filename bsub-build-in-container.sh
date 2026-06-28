#!/bin/bash

#  Copyright (c) 2024-2026, Qualcomm Innovation Center, Inc. All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause

# Build the Hexagon toolchain natively on an LSF node (no Docker required).
#
# Two modes:
#   Outer (default): Parse arguments, submit job to LSF via bsub.
#   Inner (--_run-payload): Execute the actual build on the LSF node.
#
# The outer mode re-invokes this script with --_run-payload on the LSF node.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Configuration ──────────────────────────────────────────────────────────

LSF_RESOURCES="select[ubuntu22_llvm] rusage[mem=204800]"
LSF_QUEUE="${LSF_QUEUE:-normal}"

# Pre-installed host clang toolchain available on LSF ubuntu22_llvm nodes
HOST_CLANG=/pkg/qct/software/llvm/build_tools/clang+llvm-16.0.0-x86_64-linux-gnu-ubuntu-18.04

# Toolchain version and source URLs — keep in sync with Dockerfile
VER=22.1.8
LLVM_SRC_URL="https://github.com/llvm/llvm-project/archive/llvmorg-${VER}.tar.gz"
ELD_SRC_URL="https://github.com/qualcomm/eld/archive/v22.1.0-rc3.tar.gz"
LLVM_TESTS_SRC_URL="https://github.com/llvm/llvm-test-suite/archive/llvmorg-${VER}.tar.gz"
MUSL_SRC_URL="https://github.com/quic/musl/archive/hexagon-v1.2.4-dec-2025.tar.gz"
LINUX_SRC_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.13.5.tar.xz"
BUSYBOX_SRC_URL="https://busybox.net/downloads/busybox-1.36.1.tar.bz2"
PICOLIBC_SRC_URL="https://github.com/picolibc/picolibc/releases/download/1.8.11/picolibc-1.8.11.tar.xz"
BUILDROOT_SRC_URL="https://github.com/quic/buildroot/archive/hexagon-2025.04.30.tar.gz"
QEMU_REPO="https://github.com/quic/qemu"
QEMU_REF="hexagon-sysemu-22-may-2026"

# ─── Usage ──────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build the Hexagon toolchain natively on an LSF node (no Docker required).

Submits a job via bsub that:
  1. Downloads LLVM, ELD, test-suite, QEMU, musl, kernel, picolibc, buildroot
  2. Builds the cross-compilation toolchain (LLVM+Clang for Hexagon)
  3. Builds a buildroot rootfs (optional)
  4. Runs llvm-test-suite, libc-test, and QEMU tests (optional)

Options:
  --results-dir DIR    Where to copy final artifacts (required for builds)
  --artifact-tag TAG   Build version tag (default: v${VER}-<timestamp>)
  --skip-tests         Skip test-toolchain.sh
  --skip-buildroot     Skip build-buildroot.sh
  --with-zig           Download zig and enable cross-compilation for
                       x86_64-linux-gnu, aarch64-linux-gnu,
                       aarch64-windows-gnu, x86_64-windows-gnu, aarch64-macos
  --queue QUEUE        LSF queue (default: ${LSF_QUEUE})
  --dry-run            Print bsub command without submitting
  --probe-only         Just probe the node environment and exit
  -h, --help           Show this help

Environment:
  DRM_PROJECT          Required. LSF job accounting project.

Examples:
  # Probe LSF node environment:
  DRM_PROJECT=myproj $0 --probe-only

  # Full toolchain build + test:
  DRM_PROJECT=myproj $0 --results-dir /path/to/results --artifact-tag v${VER}

  # Build only (no tests, no buildroot):
  DRM_PROJECT=myproj $0 --results-dir /path/to/results --skip-tests --skip-buildroot

  # Dry run:
  DRM_PROJECT=myproj $0 --results-dir /path/to/results --dry-run
EOF
    exit 0
}

# ─── Probe: check the LSF node environment ─────────────────────────────────

run_probe() {
    echo "=== LSF Node Environment Probe ==="
    echo "Hostname: $(hostname)"
    echo "Date:     $(date)"
    echo "User:     $(id)"
    echo "Kernel:   $(uname -r)"
    echo ""

    echo "--- OS ---"
    head -3 /etc/os-release 2>/dev/null || echo "(unknown)"
    echo ""

    echo "--- Host Clang Toolchain ---"
    if [ -d "$HOST_CLANG" ]; then
        echo "Found: $HOST_CLANG"
        "$HOST_CLANG/bin/clang" --version 2>&1 | head -2 || echo "  clang binary not working"
    else
        echo "NOT FOUND: $HOST_CLANG"
    fi
    echo ""

    echo "--- Required Tools ---"
    for tool in cmake ninja python3 ccache meson zstd git gcc make wget patch; do
        if command -v "$tool" >/dev/null 2>&1; then
            ver=$("$tool" --version 2>&1 | head -1)
            printf "  %-12s OK  (%s)\n" "$tool" "$ver"
        else
            printf "  %-12s MISSING\n" "$tool"
        fi
    done
    echo ""

    echo "--- Disk Space ---"
    df -h /local/mnt/workspace/ 2>/dev/null || echo "/local/mnt/workspace not available"
    echo ""

    echo "--- Memory ---"
    free -h 2>/dev/null || echo "(unknown)"
    echo ""

    echo "--- CPU ---"
    echo "$(nproc 2>/dev/null || echo '?') cores available"
    echo ""

    echo "=== Probe Complete ==="
}

# ─── Payload: the actual build, runs on the LSF node ───────────────────────

run_payload() {
    local results_dir="$1"
    local artifact_tag="$2"
    local skip_tests="$3"
    local skip_buildroot="$4"
    local with_zig="${5-0}"

    echo "=== Hexagon Toolchain Build (LSF Native) ==="
    echo "Hostname:       $(hostname)"
    echo "Date:           $(date)"
    echo "Artifact Tag:   ${artifact_tag}"
    echo "Results Dir:    ${results_dir}"
    echo "Skip Tests:     ${skip_tests}"
    echo "Skip Buildroot: ${skip_buildroot}"
    echo "With Zig:       ${with_zig}"
    echo ""

    # ── Workspace setup ──────────────────────────────────────────────────
    WORKSPACE="/local/mnt/workspace/${LOGNAME}-$(date +%s)-$$"
    WORK_DIR="${WORKSPACE}/hexagon-toolchain"

    echo "Creating workspace: ${WORKSPACE}"
    mkdir -p "${WORK_DIR}"

    cleanup() {
        local rc=$?
        echo ""
        echo "=== Cleanup (exit code: ${rc}) ==="
        if [ -d "${WORKSPACE}" ]; then
            echo "Removing workspace: ${WORKSPACE}"
            rm -rf "${WORKSPACE}"
        fi
        echo "Done."
    }
    trap cleanup EXIT

    # ── Copy repo files to workspace ─────────────────────────────────────
    echo "Copying build files to workspace..."
    cp "${SCRIPT_DIR}/get-src-tarballs.sh" "${WORK_DIR}/"
    cp "${SCRIPT_DIR}/build-toolchain.sh" "${WORK_DIR}/"
    cp "${SCRIPT_DIR}/build-buildroot.sh" "${WORK_DIR}/"
    cp "${SCRIPT_DIR}/test-toolchain.sh" "${WORK_DIR}/"
    cp "${SCRIPT_DIR}"/*.cmake "${WORK_DIR}/"
    cp -a "${SCRIPT_DIR}/cmake" "${WORK_DIR}/"
    cp "${SCRIPT_DIR}/hexagon-unknown-none-elf.cfg" "${WORK_DIR}/"
    cp -a "${SCRIPT_DIR}/patches" "${WORK_DIR}/"
    cp -a "${SCRIPT_DIR}/test-suite-patches" "${WORK_DIR}/"
    cp -a "${SCRIPT_DIR}/test_init" "${WORK_DIR}/"
    cp -a "${SCRIPT_DIR}/debian-pkg" "${WORK_DIR}/"
    chmod +x "${WORK_DIR}"/*.sh

    # ── Ensure zstd is available (missing on some LSF nodes) ────────────
    if ! command -v zstd >/dev/null 2>&1; then
        echo "zstd not found in PATH, building from source..."
        local zstd_dir="${WORKSPACE}/zstd-build"
        wget --quiet https://github.com/facebook/zstd/releases/download/v1.5.6/zstd-1.5.6.tar.gz \
            -O "${WORKSPACE}/zstd.tar.gz"
        mkdir -p "${zstd_dir}"
        tar xf "${WORKSPACE}/zstd.tar.gz" -C "${zstd_dir}" --strip-components=1
        make -C "${zstd_dir}" -j"$(nproc)" zstd 2>&1 | tail -3
        mkdir -p "${WORKSPACE}/bin"
        cp "${zstd_dir}/programs/zstd" "${WORKSPACE}/bin/zstd"
        export PATH="${WORKSPACE}/bin:${PATH}"
        rm -rf "${zstd_dir}" "${WORKSPACE}/zstd.tar.gz"
        echo "zstd built: $(zstd --version)"
    fi

    # ── Environment setup ────────────────────────────────────────────────
    export CC="${HOST_CLANG}/bin/clang"
    export CXX="${HOST_CLANG}/bin/clang++"
    export PATH="${HOST_CLANG}/bin:${PATH}"
    # Host clang uses libc++ — built binaries (llvm-tblgen, etc.) need to find libc++.so.1
    export LD_LIBRARY_PATH="${HOST_CLANG}/lib/x86_64-unknown-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

    export VER
    export TOOLCHAIN_INSTALL="${WORKSPACE}/clang+llvm-${VER}-cross-hexagon-unknown-linux-musl"
    export ROOT_INSTALL="${WORKSPACE}/hexagon-unknown-linux-musl-rootfs"
    export ARTIFACT_BASE="${WORKSPACE}/hexagon-artifacts"
    export ARTIFACT_TAG="${artifact_tag}"
    export MAKE_TARBALLS=1
    # IN_CONTAINER=0: enables ccache, does not aggressively purge build dirs
    export IN_CONTAINER=0
    # LSF nodes have limited memory per slot — cap parallel link jobs
    export LLVM_PARALLEL_LINK_JOBS=8

    if [ "${with_zig}" -eq 1 ]; then
        # Download zig for cross-compilation
        local ZIG_VER=0.11.0
        echo "Downloading zig ${ZIG_VER}..."
        wget --quiet "https://ziglang.org/download/${ZIG_VER}/zig-linux-x86_64-${ZIG_VER}.tar.xz" \
            -O "${WORKSPACE}/zig.tar.xz"
        tar xf "${WORKSPACE}/zig.tar.xz" -C "${WORKSPACE}"
        rm -f "${WORKSPACE}/zig.tar.xz"
        export PATH="${WORKSPACE}/zig-linux-x86_64-${ZIG_VER}:${PATH}"
        echo "zig installed: $(zig version)"

        export CROSS_TRIPLES=""
        # Windows targets cannot use LLVM dylib — use PIC-only instead
        export CROSS_TRIPLES_PIC="aarch64-windows-gnu x86_64-windows-gnu"
        export CROSS_TRIPLES_DYLIB="x86_64-linux-gnu aarch64-linux-gnu aarch64-macos"
    else
        # No zig — skip cross-compilation for other host triples
        export CROSS_TRIPLES=""
        export CROSS_TRIPLES_PIC=""
        export CROSS_TRIPLES_DYLIB=""
    fi

    # Source URLs
    export LLVM_SRC_URL ELD_SRC_URL LLVM_TESTS_SRC_URL
    export MUSL_SRC_URL LINUX_SRC_URL BUSYBOX_SRC_URL
    export PICOLIBC_SRC_URL BUILDROOT_SRC_URL
    export QEMU_REPO QEMU_REF

    # Enable test execution inside test-toolchain.sh
    export TEST_TOOLCHAIN=1

    # Create output directories
    mkdir -p "${TOOLCHAIN_INSTALL}"
    mkdir -p "${ROOT_INSTALL}"
    mkdir -p "${ARTIFACT_BASE}/${artifact_tag}"

    echo "--- Environment ---"
    echo "CC:                ${CC}"
    echo "CXX:               ${CXX}"
    echo "TOOLCHAIN_INSTALL: ${TOOLCHAIN_INSTALL}"
    echo "ROOT_INSTALL:      ${ROOT_INSTALL}"
    echo "ARTIFACT_BASE:     ${ARTIFACT_BASE}"
    echo "IN_CONTAINER:      ${IN_CONTAINER}"
    echo ""

    # Verify host clang is functional
    echo "--- Host Clang ---"
    clang --version
    echo ""

    # ── Step 1: Download sources ─────────────────────────────────────────
    echo "=========================================="
    echo "=== Step 1: Downloading Sources"
    echo "=========================================="
    cd "${WORK_DIR}"
    ./get-src-tarballs.sh "${WORK_DIR}" "${TOOLCHAIN_INSTALL}/manifest"

    # ── Step 2: Build toolchain ──────────────────────────────────────────
    # LSF nodes may lack sphinx plugins — disable QEMU docs build
    sed -i 's/--disable-containers \\/--disable-containers \\\n\t                  --disable-docs \\/' \
        "${WORK_DIR}/build-toolchain.sh"

    if [ "${skip_tests}" -eq 1 ]; then
        # QEMU is nice-to-have when tests are skipped — make it best-effort
        sed -i 's/^build_qemu$/build_qemu || echo "WARNING: QEMU build failed (exit $?), continuing without QEMU..."/' \
            "${WORK_DIR}/build-toolchain.sh"
    fi
    # When tests are enabled, QEMU must build successfully (fail hard)

    echo ""
    echo "=========================================="
    echo "=== Step 2: Building Toolchain"
    echo "=========================================="
    cd "${WORK_DIR}"
    ./build-toolchain.sh "${artifact_tag}"

    # ── Step 2b: Build Debian sysroot packages ─────────────────────────
    if command -v fakeroot >/dev/null 2>&1 && command -v dpkg-deb >/dev/null 2>&1; then
        echo ""
        echo "=========================================="
        echo "=== Step 2b: Building Debian Packages"
        echo "=========================================="
        cd "${WORK_DIR}"

        # Clean stale artifacts from any previous run
        rm -rf debian-pkg/debs debian-pkg/build

        # Override CC/CXX so build-hexagon-sysroot.sh uses the freshly-built
        # clang (libc++ 22 headers need clang >= 18 for __builtin_clzg etc).
        LLVM_ROOT="${TOOLCHAIN_INSTALL}/x86_64-linux-gnu" \
        CC="${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/clang" \
        CXX="${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/clang++" \
        PKG_VERSION="${VER}" \
            debian-pkg/build-hexagon-sysroot.sh

        # Copy .deb files into the artifact directory
        cp debian-pkg/debs/*.deb "${ARTIFACT_BASE}/${artifact_tag}/"
    else
        echo ""
        echo "=== Skipping Debian packages (fakeroot or dpkg-deb not available) ==="
    fi

    # ── Step 3: Build buildroot ──────────────────────────────────────────
    if [ "${skip_buildroot}" -eq 0 ]; then
        echo ""
        echo "=========================================="
        echo "=== Step 3: Building Buildroot"
        echo "=========================================="
        cd "${WORK_DIR}"

        # The defconfig downloads v19.1.5 toolchain from codelinaro, which is
        # inaccessible from LSF nodes (403).  Override to use the freshly-built
        # toolchain as a pre-installed external toolchain instead.
        local _tc_bin="${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin"
        export PATH="${_tc_bin}:${PATH}"
        export FORCE_UNSAFE_CONFIGURE=1
        export BR2_DL_DIR="${PWD}/br_download/"

        make -C buildroot/ O="${PWD}/obj_buildroot/" qcom_dsp_qemu_defconfig

        # Patch .config: switch from download to pre-installed
        sed -i \
            -e 's|^BR2_TOOLCHAIN_EXTERNAL_DOWNLOAD=y|# BR2_TOOLCHAIN_EXTERNAL_DOWNLOAD is not set|' \
            -e '/^BR2_TOOLCHAIN_EXTERNAL_URL=/d' \
            -e '/^BR2_TOOLCHAIN_EXTERNAL_URL_HAS_CHECK=/d' \
            -e 's|^BR2_TOOLCHAIN_EXTERNAL_HEADERS_6_7=y|# BR2_TOOLCHAIN_EXTERNAL_HEADERS_6_7 is not set|' \
            -e 's|^BR2_TOOLCHAIN_EXTERNAL_CLANG_19_0=y|# BR2_TOOLCHAIN_EXTERNAL_CLANG_19_0 is not set|' \
            obj_buildroot/.config
        {
            echo 'BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED=y'
            echo "BR2_TOOLCHAIN_EXTERNAL_PATH=\"${TOOLCHAIN_INSTALL}/x86_64-linux-gnu\""
            # Use highest available versions (buildroot uses "at least" semantics)
            echo 'BR2_TOOLCHAIN_EXTERNAL_HEADERS_6_12=y'
            echo 'BR2_TOOLCHAIN_EXTERNAL_CLANG_20_0=y'
        } >> obj_buildroot/.config
        # Clang 22 is stricter than 19 — some buildroot packages (dropbear)
        # have pointer-type issues that became errors.  Relax them.
        echo 'BR2_TARGET_OPTIMIZATION="-Wno-error=incompatible-pointer-types -Wno-error=int-conversion"' \
            >> obj_buildroot/.config

        make -C obj_buildroot olddefconfig

        # Prevent user's gitconfig URL rewrite (insteadOf) from converting
        # https:// kernel.org URLs to ssh:// which fails without SSH keys.
        export GIT_CONFIG_GLOBAL=/dev/null

        make -C obj_buildroot -j
        make -C obj_buildroot legal-info
        install -D ./obj_buildroot/images/* "${ARTIFACT_BASE}/${artifact_tag}/"
    else
        echo ""
        echo "=== Skipping Buildroot (--skip-buildroot) ==="
    fi

    # ── Step 4: Run tests ────────────────────────────────────────────────
    if [ "${skip_tests}" -eq 0 ]; then
        echo ""
        echo "=========================================="
        echo "=== Step 4: Running Tests"
        echo "=========================================="
        cd "${WORK_DIR}"
        # test-toolchain.sh uses set +e internally around test calls,
        # but wrap the whole thing in case setup fails
        ./test-toolchain.sh || echo "WARNING: test-toolchain.sh exited with code $?"
    else
        echo ""
        echo "=== Skipping Tests (--skip-tests) ==="
    fi

    # ── Step 4b: Baseline comparison ─────────────────────────────────────
    if [ "${skip_tests}" -eq 0 ]; then
        echo ""
        echo "=========================================="
        echo "=== Step 4b: Baseline Comparison"
        echo "=========================================="
        cd "${WORK_DIR}"
        local BASELINE_URL="https://artifacts.codelinaro.org/artifactory/codelinaro-toolchain-for-hexagon/${VER}/clang+llvm-${VER}-cross-hexagon-unknown-linux-musl.tar.zst"
        local BASELINE_DIR="${WORKSPACE}/baseline"
        local RESULTS="${ARTIFACT_BASE}/${artifact_tag}"

        echo "Downloading baseline toolchain from ${BASELINE_URL}..."
        mkdir -p "${BASELINE_DIR}"
        if wget --quiet "${BASELINE_URL}" -O "${BASELINE_DIR}/baseline.tar.zst"; then
            zstd -d "${BASELINE_DIR}/baseline.tar.zst" -o "${BASELINE_DIR}/baseline.tar"
            mkdir -p "${BASELINE_DIR}/extracted"
            tar xf "${BASELINE_DIR}/baseline.tar" -C "${BASELINE_DIR}/extracted" --strip-components=1
            rm -f "${BASELINE_DIR}/baseline.tar.zst" "${BASELINE_DIR}/baseline.tar"

            # Compare file listings
            echo "Comparing file listings..."
            (cd "${BASELINE_DIR}/extracted" && find . -type f | sort) > "${RESULTS}/baseline-files.txt"
            local _tc="${TOOLCHAIN_INSTALL}/x86_64-linux-gnu"
            (cd "${_tc}" && find . -type f | sort) > "${RESULTS}/new-files.txt"
            diff -u "${RESULTS}/baseline-files.txt" "${RESULTS}/new-files.txt" \
                > "${RESULTS}/file-diff.txt" 2>&1 || true

            # Run test suite with baseline toolchain (reuse QEMU + llvm-lit from new build)
            echo "Running test suite with baseline toolchain..."
            local BASELINE_TC="${BASELINE_DIR}/extracted"
            local BASELINE_BIN="${BASELINE_TC}/bin"
            local BASELINE_SYSROOT="${BASELINE_TC}/target/hexagon-unknown-linux-musl/usr"

            # Create qemu wrapper pointing to new build's QEMU but baseline's sysroot
            cat <<BEOF > "${BASELINE_BIN}/qemu_wrapper.sh"
#!/bin/bash
set -euo pipefail
export QEMU_LD_PREFIX=${BASELINE_SYSROOT}
exec ${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/qemu-hexagon \$*
BEOF
            chmod +x "${BASELINE_BIN}/qemu_wrapper.sh"

            # Run baseline test (target-hexagon-v79-O2 only for comparison)
            local baseline_cache
            baseline_cache=$(readlink -f llvm-test-suite/cmake/caches/target-hexagon-v79-O2.cmake)
            if [ -f "${baseline_cache}" ]; then
                PATH="${BASELINE_BIN}:${PATH}" \
                cmake -G Ninja \
                    -DCMAKE_BUILD_TYPE=Release \
                    -C "${baseline_cache}" \
                    -DTEST_SUITE_CXX_ABI:STRING=libc++abi \
                    -DTEST_SUITE_RUN_UNDER:STRING="${BASELINE_BIN}/qemu_wrapper.sh" \
                    -DTEST_SUITE_USER_MODE_EMULATION:BOOL=ON \
                    -DTEST_SUITE_RUN_BENCHMARKS:BOOL=ON \
                    -DTEST_SUITE_LIT:FILEPATH="${WORK_DIR}/obj_llvm/bin/llvm-lit" \
                    -DBENCHMARK_USE_LIBCXX:BOOL=ON \
                    -DSMALL_PROBLEM_SIZE:BOOL=ON \
                    -C ./hexagon-linux-cross.cmake \
                    -B ./obj_test-suite_baseline \
                    -S ./llvm-test-suite
                cmake --build ./obj_test-suite_baseline -- -v -k 0
                cd ./obj_test-suite_baseline
                python3 "${WORK_DIR}/obj_llvm/bin/llvm-lit" -v \
                    --time-tests \
                    --timeout=600 \
                    -o "${RESULTS}/test_res_baseline_target-hexagon-v79-O2.json" \
                    MultiSource/Benchmarks/{mediabench,VersaBench,Trimaran,BitBench,Rodinia,Fhourstones*,FreeBench} \
                    SingleSource/Benchmarks/{Linpack,Dhrystone,BenchmarkGame,Stanford} \
                    SingleSource/Regression/C \
                    SingleSource/UnitTests/Vector \
                    External/SPEC \
                    Bitcode/Regression \
                    || true
                cd "${WORK_DIR}"
                echo "Baseline test suite complete."
            else
                echo "WARNING: Cache file ${baseline_cache} not found, skipping baseline test."
            fi

            echo "Baseline comparison complete."
        else
            echo "WARNING: Failed to download baseline toolchain, skipping comparison."
        fi
    fi

    # ── Step 5: Collect results ──────────────────────────────────────────
    echo ""
    echo "=========================================="
    echo "=== Step 5: Collecting Results"
    echo "=========================================="
    local src_results="${ARTIFACT_BASE}/${artifact_tag}"
    if [ -d "${src_results}" ] && [ "$(ls -A "${src_results}" 2>/dev/null)" ]; then
        echo "Copying artifacts from ${src_results}/ to ${results_dir}/"
        mkdir -p "${results_dir}"
        cp -a "${src_results}"/* "${results_dir}/"
        echo ""
        echo "Artifacts:"
        ls -lh "${results_dir}/"
    else
        echo "WARNING: No artifacts found in ${src_results}"
    fi

    echo ""
    echo "=== Build Complete ==="
    echo "Results: ${results_dir}"
    echo "Date:    $(date)"
}

# ─── Argument Parsing ──────────────────────────────────────────────────────

RESULTS_DIR=""
ARTIFACT_TAG=""
SKIP_TESTS=0
SKIP_BUILDROOT=0
WITH_ZIG=0
DRY_RUN=0
PROBE_ONLY=0
_RUN_PAYLOAD=0

while [ $# -gt 0 ]; do
    case "$1" in
        --_run-payload)   _RUN_PAYLOAD=1; shift ;;
        --results-dir)    RESULTS_DIR="$2"; shift 2 ;;
        --artifact-tag)   ARTIFACT_TAG="$2"; shift 2 ;;
        --skip-tests)     SKIP_TESTS=1; shift ;;
        --skip-buildroot) SKIP_BUILDROOT=1; shift ;;
        --with-zig)       WITH_ZIG=1; shift ;;
        --queue)          LSF_QUEUE="$2"; shift 2 ;;
        --dry-run)        DRY_RUN=1; shift ;;
        --probe-only)     PROBE_ONLY=1; shift ;;
        -h|--help)        usage ;;
        *)                echo "Unknown option: $1"; usage ;;
    esac
done

# ─── Payload Mode (runs on the LSF node) ───────────────────────────────────

if [ "$_RUN_PAYLOAD" -eq 1 ]; then
    if [ "$PROBE_ONLY" -eq 1 ]; then
        run_probe
    else
        run_payload "$RESULTS_DIR" "$ARTIFACT_TAG" "$SKIP_TESTS" "$SKIP_BUILDROOT" "$WITH_ZIG"
    fi
    exit $?
fi

# ─── Submission Mode (runs on the user's machine) ──────────────────────────

# DRM_PROJECT is required for LSF job accounting
if test -z "$DRM_PROJECT"; then
    echo "Error: DRM_PROJECT environment variable must be set for LSF job accounting."
    exit 1
fi

if [ "$PROBE_ONLY" -eq 0 ]; then
    if [ -z "$RESULTS_DIR" ]; then
        echo "Error: --results-dir is required for builds."
        echo "  Use --probe-only to just check the node environment."
        exit 1
    fi
    # Resolve to absolute path for the LSF node
    mkdir -p "$RESULTS_DIR"
    RESULTS_DIR="$(readlink -f "$RESULTS_DIR")"

    if [ -z "$ARTIFACT_TAG" ]; then
        ARTIFACT_TAG="v${VER}-$(date +%s)"
        echo "No --artifact-tag specified, using: ${ARTIFACT_TAG}"
    fi
fi

# Job naming
if [ "$PROBE_ONLY" -eq 1 ]; then
    JOB_NAME="hex-probe"
else
    JOB_NAME="hex-build"
fi

# Build the payload command: re-invoke this script with --_run-payload
PAYLOAD_CMD=("${SCRIPT_DIR}/bsub-build-in-container.sh" --_run-payload)
if [ "$PROBE_ONLY" -eq 1 ]; then
    PAYLOAD_CMD+=(--probe-only)
else
    PAYLOAD_CMD+=(--results-dir "$RESULTS_DIR")
    PAYLOAD_CMD+=(--artifact-tag "$ARTIFACT_TAG")
    [ "$SKIP_TESTS" -eq 1 ] && PAYLOAD_CMD+=(--skip-tests)
    [ "$SKIP_BUILDROOT" -eq 1 ] && PAYLOAD_CMD+=(--skip-buildroot)
    [ "$WITH_ZIG" -eq 1 ] && PAYLOAD_CMD+=(--with-zig)
fi

# Construct the bsub command
BSUB_CMD=(
    bsub
    -P "$DRM_PROJECT"
    -q "$LSF_QUEUE"
    -J "$JOB_NAME"
    -R "$LSF_RESOURCES"
    -o "${JOB_NAME}-%J.log"
    -e "${JOB_NAME}-%J.err"
    "${PAYLOAD_CMD[@]}"
)

if [ "$DRY_RUN" -eq 1 ]; then
    echo "=== Dry Run ==="
    echo "Would submit to LSF:"
    echo "  ${BSUB_CMD[*]}"
    exit 0
fi

echo "Submitting '${JOB_NAME}' job to LSF..."
echo "  Queue:     ${LSF_QUEUE}"
echo "  Resources: ${LSF_RESOURCES}"
echo "  Project:   ${DRM_PROJECT}"
if [ "$PROBE_ONLY" -eq 0 ]; then
    echo "  Artifact:  ${ARTIFACT_TAG}"
    echo "  Results:   ${RESULTS_DIR}"
fi
echo ""

"${BSUB_CMD[@]}"
