#!/bin/bash

#  Copyright (c) 2022, Qualcomm Innovation Center, Inc. All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

apply_patches() {
	local repo_name=$1
	local tag_name=$2
	local patch_dir=${SRC_DIR}/patches/${repo_name}/${tag_name}
	if compgen -G "${patch_dir}/*.patch" > /dev/null 2>&1; then
		echo "Applying patches from ${patch_dir}"
		for p in "${patch_dir}"/*.patch; do
			echo "  Applying $(basename "$p")"
			patch -p1 < "$p"
		done
	fi
}

get_src_tarballs() {
	cd ${SRC_DIR}
	mkdir -p ${MANIFEST_DIR}

	wget --quiet ${LLVM_SRC_URL} -O llvm-project.tar.xz
	mkdir llvm-project
	cd llvm-project
	tar xf ../llvm-project.tar.xz --strip-components=1
	rm ../llvm-project.tar.xz
	echo ${LLVM_SRC_URL} > ${MANIFEST_DIR}/llvm-project.txt
	apply_patches llvm-project llvmorg-${VER}
	cd -

	wget --quiet ${ELD_SRC_URL} -O eld.tar.xz
	mkdir llvm-project/eld
	cd llvm-project/eld
	tar xf ../../eld.tar.xz --strip-components=1
	rm ../../eld.tar.xz
	echo ${ELD_SRC_URL} > ${MANIFEST_DIR}/eld.txt
	cd -

	wget --quiet ${LLVM_TESTS_SRC_URL} -O llvm-test-suite.tar.xz
	mkdir llvm-test-suite
	cd llvm-test-suite
	tar xf ../llvm-test-suite.tar.xz --strip-components=1
	rm ../llvm-test-suite.tar.xz
	echo ${LLVM_TESTS_SRC_URL} > ${MANIFEST_DIR}/llvm-test-suite.txt
	cd -

	git clone --branch ${QEMU_REF} ${QEMU_REPO}
	cd qemu
	git remote -v > ${MANIFEST_DIR}/qemu.txt
	git log -3 HEAD >> ${MANIFEST_DIR}/qemu.txt
	cd -

	wget --quiet ${MUSL_SRC_URL} -O musl.tar.xz
	mkdir musl
	cd musl
	tar xf ../musl.tar.xz --strip-components=1
	rm ../musl.tar.xz
	echo ${MUSL_SRC_URL} > ${MANIFEST_DIR}/musl.txt
	cd -

	wget --quiet ${BUILDROOT_SRC_URL} -O buildroot.tar.xz
	mkdir buildroot
	cd buildroot
	tar xf ../buildroot.tar.xz --strip-components=1
	echo ${BUILDROOT_SRC_URL} > ${MANIFEST_DIR}/buildroot.txt
	cd -

	wget --quiet ${LINUX_SRC_URL} -O linux.tar.xz
	mkdir linux
	cd linux
	tar xf ../linux.tar.xz --strip-components=1
	echo ${LINUX_SRC_URL} > ${MANIFEST_DIR}/linux.txt
	cd -

	wget --quiet ${PICOLIBC_SRC_URL} -O picolibc.tar.xz
	mkdir picolibc
	cd picolibc
	tar xf ../picolibc.tar.xz --strip-components=1
	rm ../picolibc.tar.xz
	echo ${PICOLIBC_SRC_URL} > ${MANIFEST_DIR}/picolibc.txt
	cd -
}

SRC_DIR=${1}
MANIFEST_DIR=${2}
set -x
get_src_tarballs
