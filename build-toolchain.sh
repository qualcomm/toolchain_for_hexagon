#!/bin/bash -x

#  Copyright (c) 2021, Qualcomm Innovation Center, Inc. All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause

STAMP=${1-$(date +"%Y_%b_%d")}
readonly CC_PREFIX=hexagon-unknown-linux-musl-
readonly ARCH=`uname -p`

set -euo pipefail
set -x

build_llvm_clang_cross() {
	triple=${1}
	pic="${2-OFF}"
	dylib="${3-OFF}"
	cd ${BASE}

	EXTRA=""
	if [[ "${triple}" =~ "windows" ]]; then
		EXTRA="-C windows-gnu-target.cmake"
	fi
	if [[ "${triple}" =~ "macos" ]]; then
		EXTRA="${EXTRA} -DCMAKE_TOOLCHAIN_FILE=${PWD}/macos-toolchain.cmake -C macos-target.cmake"
	fi
	if [[ "${HOST_CLANG_VER-}" -ne "" ]]; then
		EXTRA="${EXTRA-} -DHOST_CLANG_VER=${HOST_CLANG_VER}"
	fi
	if [[ "${IN_CONTAINER-0}" -ne 1 ]]; then
		CMAKE_CCACHE="-DLLVM_CCACHE_BUILD:BOOL=ON"
	fi
	if [[ "${pic}" =~ "ON" ]]; then
		ELD="-DLLVM_EXTERNAL_PROJECTS=eld \
		     -DLLVM_EXTERNAL_ELD_SOURCE_DIR=${PWD}/llvm-project/eld \
		     -DELD_ENABLE_SYMBOL_VERSIONING:BOOL=ON \
		     "
	fi
	if [[ "${dylib}" =~ "ON" ]]; then
		ELD=""
		DYLIB="-C ./llvm-project/clang/cmake/caches/hexagon-unknown-linux-musl-clang-dylib.cmake"
	fi


	CC="zig cc --target=${triple}" \
	ASM="zig cc --target=${triple}" \
	CXX="zig c++ --target=${triple}" \
		cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX:PATH=${TOOLCHAIN_INSTALL}/${triple}/ \
		${CMAKE_CCACHE-} \
		-DLLVM_ENABLE_ASSERTIONS:BOOL=ON \
		-DLLVM_HOST_TRIPLE=${triple} \
		-DLLVM_TOOL_DSYMUTIL_BUILD:BOOL=OFF \
		-DLLVM_INCLUDE_TESTS:BOOL=OFF \
		-DLLVM_INCLUDE_EXAMPLES:BOOL=OFF \
		-DLLVM_ENABLE_PIC:BOOL="${pic}" \
		-DLIBCLANG_BUILD_STATIC:BOOL=ON \
		${ELD-} \
		-DLLVM_NATIVE_TOOL_DIR=${PWD}/obj_llvm/bin \
		-DCMAKE_BUILD_WITH_INSTALL_RPATH:BOOL=ON \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		${EXTRA} \
		-C ./llvm-tools.cmake \
		${DYLIB-} \
		-C ./llvm-project/clang/cmake/caches/hexagon-unknown-linux-musl-clang.cmake \
		-C ./llvm-project/clang/cmake/caches/hexagon-unknown-linux-musl-clang-cross.cmake \
		-B ./obj_llvm_${triple} \
		-S ./llvm-project/llvm
	cmake --build ./obj_llvm_${triple} -- -v all install
	if [[ "${IN_CONTAINER-0}" -eq 1 ]]; then
		rm -rf ./obj_llvm_${triple}
	fi
	DEST_BIN=${TOOLCHAIN_INSTALL}/${triple}/bin
	add_symlinks ${DEST_BIN}
}

build_llvm_clang() {
	cd ${BASE}
	if [[ "${IN_CONTAINER-0}" -ne 1 ]]; then
		CMAKE_CCACHE="-DLLVM_CCACHE_BUILD:BOOL=ON"
	fi


	CC=clang CXX=clang++ cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX:PATH=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/ \
		${CMAKE_CCACHE-} \
		-DLLVM_ENABLE_LLD:BOOL=ON \
		-DLLVM_ENABLE_LIBCXX:BOOL=ON \
		-DLLVM_ENABLE_ASSERTIONS:BOOL=ON \
		-DLLVM_ENABLE_PIC:BOOL=ON \
		-DLLVM_EXTERNAL_PROJECTS=eld \
		-DLLVM_EXTERNAL_ELD_SOURCE_DIR=${PWD}/llvm-project/eld \
		-DELD_ENABLE_SYMBOL_VERSIONING:BOOL=ON \
		-C ./llvm-project/clang/cmake/caches/hexagon-unknown-linux-musl-clang.cmake \
		-C ./llvm-project/clang/cmake/caches/hexagon-unknown-linux-musl-clang-cross.cmake \
		-B ./obj_llvm \
		-S ./llvm-project/llvm
	cmake --build ./obj_llvm -- -v all install
	DEST_BIN=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/bin
	add_symlinks ${DEST_BIN}
}

add_symlinks() {
    linkdir=${1}

	for triple in hexagon-unknown-linux-musl hexagon-unknown-none-elf hexagon-linux-musl hexagon-none-elf
	do
		ln -sf --relative ${linkdir}/llvm-size ${linkdir}/${triple}-size
		ln -sf --relative ${linkdir}/llvm-strip ${linkdir}/${triple}-strip
		ln -sf --relative ${linkdir}/llvm-nm ${linkdir}/${triple}-nm
		ln -sf --relative ${linkdir}/llvm-ar ${linkdir}/${triple}-ar
		ln -sf --relative ${linkdir}/llvm-objdump ${linkdir}/${triple}-objdump
		ln -sf --relative ${linkdir}/llvm-objcopy ${linkdir}/${triple}-objcopy
		ln -sf --relative ${linkdir}/llvm-readelf ${linkdir}/${triple}-readelf
		ln -sf --relative ${linkdir}/llvm-ranlib ${linkdir}/${triple}-ranlib
		ln -sf --relative ${linkdir}/llvm-config ${linkdir}/${triple}-llvm-config
		ln -sf --relative ${linkdir}/ld.lld ${linkdir}/${triple}-ld.lld
		ln -sf --relative ${linkdir}/ld.eld ${linkdir}/${triple}-ld.eld
	done

	for triple in hexagon-unknown-linux-musl hexagon-unknown-none-elf hexagon-linux-musl hexagon-none-elf hexagon
	do
		ln -sf --relative ${linkdir}/clang ${linkdir}/${triple}-clang
		ln -sf --relative ${linkdir}/clang ${linkdir}/${triple}-clang++
	done
}

add_multilib_symlinks() {
	linkdir=${1}

	cd ${linkdir}
	for arch in v68 v69 v71 v73 v75 v79
	do
		ln -sf --relative  ../usr/lib ./${arch}
	done
	cd -
}

build_clang_rt_builtins() {
	cd ${BASE}

	PATH=${TOOLCHAIN_BIN}:${PATH} \
		cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DLLVM_CMAKE_DIR:PATH=${TOOLCHAIN_LIB} \
		-DCOMPILER_RT_EMULATOR:STRING="${TOOLCHAIN_BIN}/qemu_wrapper.sh" \
		-DCMAKE_INSTALL_PREFIX:PATH=${HEX_TOOLS_TARGET_BASE} \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		-DCOMPILER_RT_OS_DIR= \
		-DCAN_TARGET_hexagon=1 \
		-DCAN_TARGET_${ARCH}=0 \
		-DCMAKE_C_COMPILER_FORCED:BOOL=ON \
		-DCMAKE_CXX_COMPILER_FORCED:BOOL=ON \
		-C ./llvm-project/compiler-rt/cmake/caches/hexagon-linux-builtins.cmake \
		-C ./hexagon-linux-cross.cmake \
		-B ./obj_clang_rt \
		-S ./llvm-project/compiler-rt

	cmake --build ./obj_clang_rt -- -v install-builtins
}



config_kernel() {
	cd ${BASE}
	mkdir obj_linux
	cd linux
	make O=../obj_linux ARCH=hexagon \
		CROSS_COMPILE=${CC_PREFIX} \
		CC=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/bin/clang \
		AS=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/bin/clang \
		LD=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/bin/ld.lld \
		LLVM=1 \
		LLVM_IAS=1 \
		KBUILD_VERBOSE=1 comet_defconfig
}

build_kernel_headers() {
	cd ${BASE}
	cd linux
	make mrproper
	cd ${BASE}
	cd obj_linux
	make \
	        ARCH=hexagon \
		CC=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/bin/clang \
		INSTALL_HDR_PATH=${HEX_TOOLS_TARGET_BASE} \
		V=1 \
		headers_install

}

build_musl_headers() {
	cd ${BASE}
	cd musl
	make clean

	CC=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/bin/hexagon-unknown-linux-musl-clang \
		CROSS_COMPILE=${CC_PREFIX} \
		LIBCC=${HEX_TOOLS_TARGET_BASE}/lib/libclang_rt.builtins-hexagon.a \
		CROSS_CFLAGS="-G0 -O0 -mv68 -fno-builtin --target=hexagon-unknown-linux-musl" \
		./configure --target=hexagon --prefix=${HEX_TOOLS_TARGET_BASE}
	PATH=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/bin/:$PATH make install-headers

	cd ${HEX_SYSROOT}/..
	ln -sf hexagon-unknown-linux-musl hexagon
	ln -sf hexagon-unknown-linux-musl hexagon-linux-musl
	DEST_TGT_LIB=${HEX_SYSROOT}/lib
	mkdir -p ${DEST_TGT_LIB}
	add_multilib_symlinks ${DEST_TGT_LIB}
}

build_musl() {
	cd ${BASE}
	cd musl
	make clean

	CROSS_COMPILE=${CC_PREFIX} \
		AR=llvm-ar \
		RANLIB=llvm-ranlib \
		STRIP=llvm-strip \
		CC=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/bin/hexagon-unknown-linux-musl-clang \
		LIBCC=${HEX_TOOLS_TARGET_BASE}/lib/libclang_rt.builtins-hexagon.a \
		CFLAGS="${MUSL_CFLAGS}" \
		./configure --target=hexagon --prefix=${HEX_TOOLS_TARGET_BASE}
	PATH=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/bin/:$PATH make -j install
	cd ${HEX_TOOLS_TARGET_BASE}/lib
	ln -sf libc.so ld-musl-hexagon.so
	ln -sf ld-musl-hexagon.so ld-musl-hexagon.so.1
	mkdir -p ${HEX_TOOLS_TARGET_BASE}/../lib
	cd ${HEX_TOOLS_TARGET_BASE}/../lib
	ln -sf ../usr/lib/ld-musl-hexagon.so.1
}


build_libs() {
	cd ${BASE}

	PATH=${TOOLCHAIN_BIN}:${PATH} \
		cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DLLVM_CMAKE_DIR:PATH=${TOOLCHAIN_LIB} \
		-DCMAKE_INSTALL_PREFIX:PATH=${HEX_TOOLS_TARGET_BASE} \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		-DCMAKE_CXX_COMPILER_FORCED:BOOL=ON \
		-C ./hexagon-linux-cross.cmake \
		-C ./llvm-project/libcxx/cmake/caches/hexagon-linux-runtimes.cmake \
		-C ./llvm-project/compiler-rt/cmake/caches/hexagon-linux-clangrt.cmake \
		-DCOMPILER_RT_OS_DIR= \
		-B ./obj_libs \
		-S ./llvm-project/runtimes

	PATH=${TOOLCHAIN_BIN}:${PATH} \
	cmake --build ./obj_libs -- -v \
		install
}

build_sanitizers() {
	cd ${BASE}
	set -x
	PATH=${TOOLCHAIN_BIN}:${PATH} \
		cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DLLVM_CMAKE_DIR:PATH=${TOOLCHAIN_LIB} \
		-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR:BOOL=OFF \
		-DCMAKE_INSTALL_PREFIX:PATH=${HEX_TOOLS_TARGET_BASE} \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		-DCOMPILER_RT_BUILD_BUILTINS:BOOL=OFF \
		-DCOMPILER_RT_BUILD_SANITIZERS:BOOL=ON \
		-DCAN_TARGET_hexagon=1 \
		-DCMAKE_C_COMPILER_FORCED:BOOL=ON \
		-DCMAKE_CXX_COMPILER_FORCED:BOOL=ON \
		-DCOMPILER_RT_SUPPORTED_ARCH=hexagon \
		-DLLVM_TARGET_TRIPLE=hexagon-unknown-linux-musl \
		-C ./hexagon-linux-cross.cmake \
		-B ./obj_san \
		-S ./llvm-project/compiler-rt
	cmake --build ./obj_san -- -v install-compiler-rt
}


build_qemu() {
	cd ${BASE}
	mkdir -p obj_qemu
	cd obj_qemu
	CC=$(which gcc) \
	PATH=${TOOLCHAIN_BIN}:${PATH} \
	../qemu/configure --enable-fdt --disable-capstone --disable-guest-agent \
	                  --enable-slirp \
	                  --enable-plugins \
	                  --disable-containers \
	                  --python=$(which python3) \
	                  --disable-brlapi \
	                  --disable-spice \
	                  --disable-vnc \
	                  --disable-vnc-jpeg \
	                  --disable-vnc-sasl \
	                  --disable-gnutls \
	                  --disable-nettle \
	                  --disable-gcrypt \
	                  --disable-seccomp \
	                  --disable-numa \
	                  --disable-rdma \
	                  --disable-libpmem \
	                  --disable-gtk \
	                  --disable-sdl \
	                  --disable-opengl \
	                  --disable-virglrenderer \
	                  --disable-png \
	                  --disable-curses \
	                  --disable-libssh \
	                  --disable-libnfs \
	                  --disable-glusterfs \
	                  --disable-rbd \
		--target-list=hexagon-softmmu,hexagon-linux-user --prefix=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu \

#	--cc=clang \
#	--cross-prefix=hexagon-unknown-linux-musl-
#	--cross-cc-hexagon="hexagon-unknown-linux-musl-clang" \
#		--cross-cc-cflags-hexagon="-mv67 --sysroot=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/target/hexagon-unknown-linux-musl"

	make -j
	make -j install

	cat <<EOF > ./qemu_wrapper.sh
#!/bin/bash

set -euo pipefail

export QEMU_LD_PREFIX=${HEX_TOOLS_TARGET_BASE}

exec ${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/bin/qemu-hexagon \$*
EOF
	cp ./qemu_wrapper.sh ${TOOLCHAIN_BIN}/
	chmod +x ./qemu_wrapper.sh ${TOOLCHAIN_BIN}/qemu_wrapper.sh
}

build_clang_rt_builtins_baremetal() {
	cd ${BASE}

	PATH=${TOOLCHAIN_BIN}:${PATH} \
		cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DLLVM_CMAKE_DIR:PATH=${TOOLCHAIN_LIB} \
		-DCMAKE_INSTALL_PREFIX:PATH=${HEX_PICOLIBC_BASE} \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		-DCOMPILER_RT_OS_DIR= \
		-DCMAKE_C_COMPILER:STRING=${TOOLCHAIN_BIN}/clang \
		-DCMAKE_ASM_COMPILER:STRING=${TOOLCHAIN_BIN}/clang \
		-C ./llvm-project/compiler-rt/cmake/caches/hexagon-builtins-baremetal.cmake \
		-B ./obj_clang_rt_baremetal \
		-S ./llvm-project/compiler-rt

	cmake --build ./obj_clang_rt_baremetal -- -v install-builtins
}

build_picolibc() {
	cd ${BASE}

	# Build picolibc for each architecture version since multilib is
	# disabled for hexagon.  Each build produces libc.a, libm.a,
	# libsemihost.a, crt0.o, crt0-semihost.o etc.
	for archver in ${HEX_ARCH_VERSIONS}
	do
		echo "=== Building picolibc for ${archver} ==="
		BUILDDIR=obj_picolibc_${archver}

		PICOLIBC_PREFIX=${HEX_PICOLIBC_BASE}

		# Generate a meson cross-file for this architecture version.
		# We point at the freshly-built toolchain.
		cat > picolibc-hexagon-${archver}.txt <<CROSSEOF
[binaries]
c = ['${TOOLCHAIN_BIN}/clang', '--target=hexagon-unknown-none-elf', '-m${archver}', '-fno-pic', '-fno-PIE', '-static', '-nostdlib', '-fuse-init-array', '-G0']
c_ld = '${TOOLCHAIN_BIN}/ld.eld'
ar = '${TOOLCHAIN_BIN}/llvm-ar'
as = '${TOOLCHAIN_BIN}/clang'
nm = '${TOOLCHAIN_BIN}/llvm-nm'
strip = '${TOOLCHAIN_BIN}/llvm-strip'
objcopy = '${TOOLCHAIN_BIN}/llvm-objcopy'

[host_machine]
system = 'none'
cpu_family = 'hexagon'
cpu = 'hexagon'
endian = 'little'

[properties]
librt = '-lclang_rt.builtins'
skip_sanity_check = true
needs_exe_wrapper = true
link_spec = '--build-id=none'
default_ram_addr = '0x00500000'
default_ram_size = '0x00800000'
default_flash_addr = '0x00100000'
default_flash_size = '0x00400000'
CROSSEOF

		# Place builtins into per-arch lib dir where the driver will search
		ARCHLIB=${HEX_PICOLIBC_BASE}/lib/${archver}/G0
		mkdir -p ${ARCHLIB}
		ln -sf ../../hexagon-unknown-none-elf/libclang_rt.builtins.a \
			${ARCHLIB}/libclang_rt.builtins.a

		meson setup \
			--cross-file picolibc-hexagon-${archver}.txt \
			-Dprefix=${PICOLIBC_PREFIX} \
			-Dlibdir=lib/${archver}/G0 \
			-Dincludedir=include \
			-Dspecsdir=none \
			-Dtests=false \
			-Dmultilib=false \
			-Dposix-console=true \
			-Dsysroot-install=false \
			-Dc_link_args="-L${ARCHLIB}" \
			${BUILDDIR} \
			picolibc

		ninja -C ${BUILDDIR}
		DESTDIR= ninja -C ${BUILDDIR} install

		if [[ "${IN_CONTAINER-0}" -eq 1 ]]; then
			rm -rf ${BUILDDIR}
		fi
	done

	# Create convenience symlinks for the bare triple forms
	cd ${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/target/picolibc
	ln -sf hexagon-unknown-none-elf hexagon-none-elf 2>/dev/null || true
}

install_baremetal_cfg() {
	cd ${BASE}
	cp hexagon-unknown-none-elf.cfg ${TOOLCHAIN_BIN}/hexagon-unknown-none-elf.cfg
	ln -sf hexagon-unknown-none-elf.cfg ${TOOLCHAIN_BIN}/hexagon.cfg
}

purge_builds() {
	rm -rf ${BASE}/obj_*/
}

TOOLCHAIN_INSTALL_REL=${TOOLCHAIN_INSTALL}
TOOLCHAIN_INSTALL=$(readlink -f ${TOOLCHAIN_INSTALL})
TOOLCHAIN_BIN=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/bin
TOOLCHAIN_LIB=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/lib
HEX_SYSROOT=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/target/hexagon-unknown-linux-musl
HEX_TOOLS_TARGET_BASE=${HEX_SYSROOT}/usr
HEX_PICOLIBC_BASE=${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/target/picolibc/hexagon-unknown-none-elf
ROOT_INSTALL_REL=${ROOT_INSTALL}
ROOTFS=$(readlink -f ${ROOT_INSTALL})
RESULTS_DIR_=${ARTIFACT_BASE}/${ARTIFACT_TAG}
mkdir -p ${RESULTS_DIR_}
RESULTS_DIR=$(readlink -f ${RESULTS_DIR_})

if [[ ! -d ${RESULTS_DIR} ]]; then
    echo err results dir "${RESULTS_DIR}" not found or not a dir
    exit 3
fi

REL_NAME=$(basename ${TOOLCHAIN_INSTALL_REL})
BASE=$(readlink -f ${PWD})

if [[ ${MAKE_TARBALLS-0} -eq 1 ]]; then
    echo toolchain will be placed in ${RESULTS_DIR}/${REL_NAME}.tar.zst
    echo creating empty file there as a test:
    echo '' > ${RESULTS_DIR}/${REL_NAME}.tar.zst
fi

ccache --show-stats


HEX_ARCH_VERSIONS="v68 v69 v71 v73 v75 v79 v81"

MUSL_CFLAGS="-G0 -O0 -mv68 -fno-builtin -mlong-calls --target=hexagon-unknown-linux-musl"

# Workaround, 'C()' macro results in switch over bool:
MUSL_CFLAGS="${MUSL_CFLAGS} -Wno-switch-bool"
# Workaround, this looks like a bug/incomplete feature in the
# hexagon compiler backend:
MUSL_CFLAGS="${MUSL_CFLAGS} -Wno-unsupported-floating-point-opt"

which clang
clang --version
ninja --version
cmake --version
python3 --version

build_llvm_clang

CROSS_ALL="${CROSS_TRIPLES} ${CROSS_TRIPLES_PIC} ${CROSS_TRIPLES_DYLIB}"
for t in ${CROSS_TRIPLES}
do
	build_llvm_clang_cross ${t}
done
for t in ${CROSS_TRIPLES_PIC}
do
	build_llvm_clang_cross ${t} ON OFF
done
for t in ${CROSS_TRIPLES_DYLIB}
do
	build_llvm_clang_cross ${t} ON ON
done
ccache --show-stats
config_kernel
build_kernel_headers
build_musl_headers
build_clang_rt_builtins
build_musl

build_libs
#build_sanitizers

build_clang_rt_builtins_baremetal
build_picolibc
install_baremetal_cfg

for t in ${CROSS_ALL}
do
	cp -ra ${TOOLCHAIN_INSTALL}/${ARCH}-linux-gnu/target ${TOOLCHAIN_INSTALL}/${t}
	cp ${TOOLCHAIN_BIN}/hexagon-unknown-none-elf.cfg ${TOOLCHAIN_INSTALL}/${t}/bin/ 2>/dev/null || true
	ln -sf hexagon-unknown-none-elf.cfg ${TOOLCHAIN_INSTALL}/${t}/bin/hexagon.cfg 2>/dev/null || true
done
build_qemu

cd ${BASE}
if [[ ${MAKE_TARBALLS-0} -eq 1 ]]; then
    tar c -C $(dirname ${TOOLCHAIN_INSTALL_REL}) ${REL_NAME}/${ARCH}-linux-gnu | zstd --fast -T0 > ${RESULTS_DIR}/${REL_NAME}.tar.zst
	for t in ${CROSS_ALL}
	do
		if [[ -d ${TOOLCHAIN_INSTALL_REL}/${t} ]]; then
			tar c -C $(dirname ${TOOLCHAIN_INSTALL_REL}) ${REL_NAME}/${t} | zstd --fast -T0 > ${RESULTS_DIR}/${REL_NAME}_${t}.tar.zst
		fi
	done
    cd ${RESULTS_DIR}
    sha256sum *.tar.zst | tee SHA256SUMS
fi
