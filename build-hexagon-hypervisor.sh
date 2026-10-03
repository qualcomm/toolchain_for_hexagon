#!/usr/bin/env bash

#  Copyright (c) 2026, Qualcomm Innovation Center, Inc. All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause

# Build the H2 hypervisor and QEMU's loadlinux firmware with the
# Hexagon SDK.  H2 deliberately does not use the LLVM toolchain built by this
# repository: its build expects hexagon-clang and hexagon-strip from the SDK.

set -euo pipefail

: "${ARTIFACT_BASE:?ARTIFACT_BASE must name the artifact root}"
: "${ARTIFACT_TAG:?ARTIFACT_TAG must name the artifact directory}"

SDK_ROOT=${HEXAGON_SDK_ROOT:-/opt/Hexagon_SDK}
H2_DIR="${H2_DIR:-$(pwd)/hexagon-hypervisor}"
OUTPUT_DIR="${ARTIFACT_BASE}/${ARTIFACT_TAG}/hexagon-hypervisor"

sdk_clang=$(find "${SDK_ROOT}" \( -type f -o -type l \) -name hexagon-clang -print -quit)
sdk_strip=$(find "${SDK_ROOT}" \( -type f -o -type l \) -name hexagon-strip -print -quit)
if [[ -z ${sdk_clang} || -z ${sdk_strip} ]]; then
    echo "error: Hexagon SDK tools were not found below ${SDK_ROOT}" >&2
    exit 1
fi
export PATH="$(dirname "${sdk_clang}"):$(dirname "${sdk_strip}"):${PATH}"

if [[ ! -d ${H2_DIR} ]]; then
    echo "error: H2 source directory is missing: ${H2_DIR}" >&2
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"

for archv in 68 73 81; do
    # Keep each architecture independent: the H2 artifact paths are shared
    # across variants and their generated configuration is architecture-specific.
    make -C "${H2_DIR}" USE_PKW=0 ARCHV="${archv}" TARGET=opt clean
    make -C "${H2_DIR}" -j"$(nproc)" USE_PKW=0 ARCHV="${archv}" TARGET=opt \
        NULL_ANGEL_TRAP=1 SHUTDOWN_AFTER_GUEST_EXIT=1
    make -C "${H2_DIR}/linux" -j"$(nproc)" USE_PKW=0 ARCHV="${archv}" NO_LOAD=1 \
        NULL_ANGEL_TRAP=1 SHUTDOWN_AFTER_GUEST_EXIT=1 \
        LINUX_LINK_ADDR=0xa0000000 \
        INSTALLPATH="${H2_DIR}/artifacts/v${archv}/opt/install" \
        KERNELPATH="${H2_DIR}/artifacts/v${archv}/opt/build/kernel" \
        loadlinux

    install -D -m 0755 \
        "${H2_DIR}/artifacts/v${archv}/opt/install/bin/booter" \
        "${OUTPUT_DIR}/booter_v${archv}"
    install -D -m 0755 "${H2_DIR}/linux/loadlinux" \
        "${OUTPUT_DIR}/hexagon_loadlinux_v${archv}"
done

archv=68
make -C "${H2_DIR}" USE_PKW=0 ARCHV="${archv}" TARGET=opt clean
make -C "${H2_DIR}" -j"$(nproc)" USE_PKW=0 ARCHV="${archv}" TARGET=opt \
    NULL_ANGEL_TRAP=1 SHUTDOWN_AFTER_GUEST_EXIT=1 H2K_LOAD_ADDR=0x88f00000
make -C "${H2_DIR}/linux" -j"$(nproc)" USE_PKW=0 ARCHV="${archv}" NO_LOAD=1 \
    NULL_ANGEL_TRAP=1 SHUTDOWN_AFTER_GUEST_EXIT=1 \
    LINUX_LINK_ADDR=0xa1000000 \
    INSTALLPATH="${H2_DIR}/artifacts/v${archv}/opt/install" \
    KERNELPATH="${H2_DIR}/artifacts/v${archv}/opt/build/kernel" \
    loadlinux

install -D -m 0755 "${H2_DIR}/linux/loadlinux" \
    "${OUTPUT_DIR}/hexagon_loadlinux_qcs6490_cdsp"
