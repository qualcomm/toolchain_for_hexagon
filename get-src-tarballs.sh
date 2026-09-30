#!/bin/bash

#  Copyright (c) 2022, Qualcomm Innovation Center, Inc. All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

CURL_RETRY_OPTS=(--fail --location --silent --show-error --retry 5 --retry-delay 30)

H2_REPO=${H2_REPO:-https://github.com/androm3da/hexagon-hypervisor}
H2_REF=${H2_REF:-5e1428a425230eed9fcb8c76284269721cb348bf}

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

	curl "${CURL_RETRY_OPTS[@]}" ${LLVM_SRC_URL} -o llvm-project.tar.xz
	mkdir llvm-project
	cd llvm-project
	tar xf ../llvm-project.tar.xz --strip-components=1 --no-same-permissions
	rm ../llvm-project.tar.xz
	echo ${LLVM_SRC_URL} > ${MANIFEST_DIR}/llvm-project.txt
	apply_patches llvm-project "${LLVM_PATCH_TAG:-llvmorg-${VER}}"
	cd -

	curl "${CURL_RETRY_OPTS[@]}" ${ELD_SRC_URL} -o eld.tar.xz
	mkdir llvm-project/eld
	cd llvm-project/eld
	tar xf ../../eld.tar.xz --strip-components=1 --no-same-permissions
	rm ../../eld.tar.xz
	echo ${ELD_SRC_URL} > ${MANIFEST_DIR}/eld.txt
	apply_patches eld "${ELD_PATCH_TAG:-${VER}}"
	cd -

	curl "${CURL_RETRY_OPTS[@]}" ${LLVM_TESTS_SRC_URL} -o llvm-test-suite.tar.xz
	mkdir llvm-test-suite
	cd llvm-test-suite
	tar xf ../llvm-test-suite.tar.xz --strip-components=1 --no-same-permissions
	rm ../llvm-test-suite.tar.xz
	echo ${LLVM_TESTS_SRC_URL} > ${MANIFEST_DIR}/llvm-test-suite.txt
	cd -

	local qemu_src_url=${QEMU_REPO}/archive/${QEMU_REF}.tar.gz
	curl "${CURL_RETRY_OPTS[@]}" ${qemu_src_url} -o qemu.tar.gz
	mkdir qemu
	cd qemu
	tar xf ../qemu.tar.gz --strip-components=1 --no-same-permissions
	rm ../qemu.tar.gz
	echo ${qemu_src_url} > ${MANIFEST_DIR}/qemu.txt
	cd -

	# H2's Makefile embeds its Git revision in the firmware.  Unlike the other
	# source archives, this must retain .git so the generated C macro is valid.
	git init -q hexagon-hypervisor
	git -C hexagon-hypervisor remote add origin "${H2_REPO}.git"
	git -C hexagon-hypervisor fetch -q --depth 1 origin "${H2_REF}"
	git -C hexagon-hypervisor checkout -q --detach FETCH_HEAD
	{
		git -C hexagon-hypervisor remote get-url origin
		git -C hexagon-hypervisor rev-parse HEAD
	} > ${MANIFEST_DIR}/hexagon-hypervisor.txt

	curl "${CURL_RETRY_OPTS[@]}" ${MUSL_SRC_URL} -o musl.tar.xz
	mkdir musl
	cd musl
	tar xf ../musl.tar.xz --strip-components=1 --no-same-permissions
	rm ../musl.tar.xz
	echo ${MUSL_SRC_URL} > ${MANIFEST_DIR}/musl.txt
	cd -

	curl "${CURL_RETRY_OPTS[@]}" ${BUILDROOT_SRC_URL} -o buildroot.tar.xz
	mkdir buildroot
	cd buildroot
	tar xf ../buildroot.tar.xz --strip-components=1 --no-same-permissions
	echo ${BUILDROOT_SRC_URL} > ${MANIFEST_DIR}/buildroot.txt
	cd -

	curl "${CURL_RETRY_OPTS[@]}" ${LINUX_SRC_URL} -o linux.tar.xz
	mkdir linux
	cd linux
	tar xf ../linux.tar.xz --strip-components=1 --no-same-permissions
	echo ${LINUX_SRC_URL} > ${MANIFEST_DIR}/linux.txt
	cd -

	curl "${CURL_RETRY_OPTS[@]}" ${PICOLIBC_SRC_URL} -o picolibc.tar.xz
	mkdir picolibc
	cd picolibc
	tar xf ../picolibc.tar.xz --strip-components=1 --no-same-permissions
	rm ../picolibc.tar.xz
	echo ${PICOLIBC_SRC_URL} > ${MANIFEST_DIR}/picolibc.txt
	cd -
}

SRC_DIR=${1}
MANIFEST_DIR=${2}
set -x
get_src_tarballs
