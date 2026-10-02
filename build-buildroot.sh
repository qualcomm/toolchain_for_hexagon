#!/bin/bash

#  Copyright (c) 2024, Qualcomm Innovation Center, Inc. All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

BASE=$(readlink -f ${PWD})
# Must match build-toolchain.sh's NATIVE_TRIPLE exactly.
NATIVE_TRIPLE="$(uname -p)-$(lsb_release -is | tr '[:upper:]' '[:lower:]')-$(lsb_release -rs)"

set -x
TOOLCHAIN_INSTALL_REL=${TOOLCHAIN_INSTALL}
TOOLCHAIN_INSTALL=$(readlink -f ${TOOLCHAIN_INSTALL})
TOOLCHAIN_BIN=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin
export PATH=${TOOLCHAIN_BIN}:${PATH}

# TODO: change build to use unprivileged user
export FORCE_UNSAFE_CONFIGURE=1
export BR2_DL_DIR=$PWD/br_download/

build_buildroot() {
    local output_dir=$1
    local defconfig=$2
    local artifact_dir=$3

    make -C buildroot/ O="${PWD}/${output_dir}" "${defconfig}"
    make -C "${output_dir}" -j
    make -C "${output_dir}" legal-info
    mkdir -p "${artifact_dir}"
    install -D "${output_dir}"/images/* "${artifact_dir}/"
}

# The baseline/QEMU buildroot is disabled for now to keep the containerized build
# within its time limit; re-enable it if the generic rootfs is needed again.
#build_buildroot obj_buildroot qcom_dsp_qemu_defconfig \
#    "${ARTIFACT_BASE}/${ARTIFACT_TAG}"
build_buildroot obj_buildroot_qcs6490_cdsp qcom_qcs6490_cdsp_defconfig \
    "${ARTIFACT_BASE}/${ARTIFACT_TAG}/qcs6490-cdsp"
