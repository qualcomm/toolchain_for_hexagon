#!/bin/bash -x

#  Copyright (c) 2021, Qualcomm Innovation Center, Inc. All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause

STAMP=${1-$(date +"%Y_%b_%d")}
readonly CC_PREFIX=hexagon-unknown-linux-musl-
readonly ARCH=`uname -p`
# Host-specific, not a generic "${ARCH}-linux-gnu": a cross triple named
# exactly that (e.g. CROSS_TRIPLES_PIC="x86_64-linux-gnu") would otherwise
# resolve to the same CMAKE_INSTALL_PREFIX as the native build below and
# silently overwrite it. See ./toolchain_collision.md.
readonly NATIVE_TRIPLE="${ARCH}-$(lsb_release -is | tr '[:upper:]' '[:lower:]')-$(lsb_release -rs)"

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
	if [[ "${IN_CONTAINER-0}" -ne 1 ]]; then
		CMAKE_CCACHE="-DLLVM_CCACHE_BUILD:BOOL=ON"
	fi
	if [[ -n "${LLVM_PARALLEL_LINK_JOBS-}" ]]; then
		CMAKE_LINK_JOBS="-DLLVM_PARALLEL_LINK_JOBS=${LLVM_PARALLEL_LINK_JOBS}"
	fi

	# Build distribution components list — ELD is skipped for cross-builds
	# (LLD is sufficient); only the native build includes ld.eld.
	DIST_COMPONENTS=(
		clang clang-resource-headers lld LTO
		llvm-addr2line llvm-ar llvm-config llvm-cov llvm-cxxfilt llvm-dwarfdump
		llvm-mc llvm-nm llvm-objcopy llvm-objdump llvm-profdata
		llvm-ranlib llvm-readelf llvm-readobj
		llvm-size llvm-strings llvm-strip llvm-symbolizer
	)
	DYLIB=""
	if [[ "${dylib}" == "ON" ]]; then
		DYLIB="-C ./cmake/caches/hexagon-stage0-dylib.cmake"
		DIST_COMPONENTS+=(LLVM clang-cpp)
	fi
	DIST_LIST=$(IFS=';'; echo "${DIST_COMPONENTS[*]}")

	CC="zig cc --target=${triple}" \
	ASM="zig cc --target=${triple}" \
	CXX="zig c++ --target=${triple}" \
		cmake -G Ninja \
		-DCMAKE_INSTALL_PREFIX:PATH=${TOOLCHAIN_INSTALL}/${triple}/ \
		${CMAKE_CCACHE-} \
		${CMAKE_LINK_JOBS-} \
		-DLLVM_ENABLE_ASSERTIONS:BOOL=ON \
		-DLLVM_HOST_TRIPLE=${triple} \
		-DLLVM_TOOL_DSYMUTIL_BUILD:BOOL=OFF \
		-DLIBCLANG_BUILD_STATIC:BOOL=ON \
		-DLLVM_NATIVE_TOOL_DIR=${PWD}/obj_llvm/bin \
		-DCMAKE_BUILD_WITH_INSTALL_RPATH:BOOL=ON \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		${EXTRA} \
		${DYLIB} \
		-C ./cmake/caches/hexagon-stage0.cmake \
		-C ./cmake/caches/hexagon-stage0-cross.cmake \
		-DLLVM_ENABLE_PIC:BOOL="${pic}" \
		-DLLVM_DISTRIBUTION_COMPONENTS="${DIST_LIST}" \
		-B ./obj_llvm_${triple} \
		-S ./llvm-project/llvm
	cmake --build ./obj_llvm_${triple} --target install-distribution
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
	if [[ -n "${LLVM_PARALLEL_LINK_JOBS-}" ]]; then
		CMAKE_LINK_JOBS="-DLLVM_PARALLEL_LINK_JOBS=${LLVM_PARALLEL_LINK_JOBS}"
	fi

	# Conditionally add ELD as an LLVM external project.
	ELD=""
	if [[ -d ./llvm-project/eld ]]; then
		ELD="-DLLVM_EXTERNAL_PROJECTS=eld \
		     -DLLVM_EXTERNAL_ELD_SOURCE_DIR=${PWD}/llvm-project/eld \
		     -DELD_ENABLE_SYMBOL_VERSIONING:BOOL=ON"
	fi

	CC=clang CXX=clang++ cmake -G Ninja \
		-DCMAKE_INSTALL_PREFIX:PATH=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/ \
		${CMAKE_CCACHE-} \
		${CMAKE_LINK_JOBS-} \
		-DLLVM_ENABLE_LLD:BOOL=ON \
		-DLLVM_ENABLE_LIBCXX:BOOL=ON \
		-DLLVM_ENABLE_ASSERTIONS:BOOL=ON \
		${ELD} \
		-C ./cmake/caches/hexagon-stage0.cmake \
		-C ./cmake/caches/hexagon-stage0-cross.cmake \
		-B ./obj_llvm \
		-S ./llvm-project/llvm
	cmake --build ./obj_llvm --target install-distribution

	# ELD external project doesn't participate in install-distribution;
	# install-ld.eld handles both the ld.eld binary and libLW shared library.
	# Note: ELD's libLW uses NO_EXPORT (via patch) to stay out of
	# LLVMExports.cmake, avoiding conflicts with baremetal builtins sub-builds.
	if [[ -n "${ELD}" ]]; then
		cmake --build ./obj_llvm --target install-ld.eld
	fi

	DEST_BIN=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin
	add_symlinks ${DEST_BIN}
}

add_symlinks() {
    linkdir=${1}

	for triple in hexagon-unknown-linux-musl hexagon-unknown-none-elf hexagon-unknown-qurt hexagon-linux-musl hexagon-none-elf hexagon-qurt hexagon
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
		if [[ -e ${linkdir}/ld.eld ]]; then
			ln -sf --relative ${linkdir}/ld.eld ${linkdir}/${triple}-ld.eld
		fi
	done

	for triple in hexagon-unknown-linux-musl hexagon-unknown-none-elf hexagon-unknown-qurt hexagon-linux-musl hexagon-none-elf hexagon-qurt hexagon
	do
		ln -sf --relative ${linkdir}/clang ${linkdir}/${triple}-clang
		ln -sf --relative ${linkdir}/clang ${linkdir}/${triple}-clang++
		ln -sf --relative ${linkdir}/clang ${linkdir}/${triple}-cc
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

build_builtins() {
	cd ${BASE}

	# Builtins are not part of install-distribution because the Linux
	# builtins (hexagon-unknown-linux-musl) need musl headers (<stdlib.h>).
	# Build after musl headers are installed.
	cmake --build ./obj_llvm --target install-builtins

	# Hexagon driver passes -lclang_rt.builtins-hexagon (old-style name).
	# Create a compatibility symlink in the sysroot lib dir so the linker
	# finds builtins during runtimes build and user builds.
	RESOURCE_DIR=$(${TOOLCHAIN_BIN}/clang --print-resource-dir)
	mkdir -p ${HEX_TOOLS_TARGET_BASE}/lib
	ln -sf --relative "${RESOURCE_DIR}/lib/hexagon-unknown-linux-musl/libclang_rt.builtins.a" \
		${HEX_TOOLS_TARGET_BASE}/lib/libclang_rt.builtins-hexagon.a
}

build_runtimes() {
	cd ${BASE}

	# Install libunwind/libc++abi/libc++ into the sysroot before the rest of
	# the runtimes build, replacing the empty stub archives created above.
	# The Hexagon driver places -L${SysRoot}/usr/lib and its unconditional
	# -lc++ -lc++abi -lunwind ahead of any -L the build passes, so the stubs
	# would win over the in-tree libraries when compiler-rt links its shared
	# runtimes (e.g. libclang_rt.scudo_standalone-hexagon.so, whose GWP-ASan
	# backtrace needs _Unwind_Backtrace/_Unwind_GetIP) -- with -Wl,-z,defs
	# that is a hard link error.  These three runtimes don't depend on
	# compiler-rt's sanitizers, so building them first is safe.
	for rt in unwind cxxabi cxx; do
		cmake --build ./obj_llvm --target install-${rt}-hexagon-unknown-linux-musl
	done

	cmake --build ./obj_llvm --target install-runtimes-hexagon-unknown-linux-musl
}

config_kernel() {
	cd ${BASE}
	mkdir obj_linux
	cd linux
	make O=../obj_linux ARCH=hexagon \
		CROSS_COMPILE=${CC_PREFIX} \
		CC=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin/clang \
		AS=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin/clang \
		LD=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin/ld.lld \
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
		CC=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin/clang \
		INSTALL_HDR_PATH=${HEX_TOOLS_TARGET_BASE} \
		V=1 \
		headers_install

}

build_musl_headers() {
	cd ${BASE}
	cd musl
	make clean

	RESOURCE_DIR=$(${TOOLCHAIN_BIN}/clang --print-resource-dir)
	CC=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin/hexagon-unknown-linux-musl-clang \
		CROSS_COMPILE=${CC_PREFIX} \
		LIBCC="${RESOURCE_DIR}/lib/hexagon-unknown-linux-musl/libclang_rt.builtins.a" \
		CROSS_CFLAGS="-G0 -O0 -mv68 -fno-builtin --target=hexagon-unknown-linux-musl" \
		./configure --target=hexagon --prefix=${HEX_TOOLS_TARGET_BASE}
	PATH=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin/:$PATH make install-headers

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

	RESOURCE_DIR=$(${TOOLCHAIN_BIN}/clang --print-resource-dir)
	CROSS_COMPILE=${CC_PREFIX} \
		AR=llvm-ar \
		RANLIB=llvm-ranlib \
		STRIP=llvm-strip \
		CC=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin/hexagon-unknown-linux-musl-clang \
		LIBCC="${RESOURCE_DIR}/lib/hexagon-unknown-linux-musl/libclang_rt.builtins.a" \
		CFLAGS="${MUSL_CFLAGS}" \
		./configure --target=hexagon --prefix=${HEX_TOOLS_TARGET_BASE}
	PATH=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin/:$PATH make -j install
	cd ${HEX_TOOLS_TARGET_BASE}/lib
	ln -sf libc.so ld-musl-hexagon.so
	ln -sf ld-musl-hexagon.so ld-musl-hexagon.so.1
	mkdir -p ${HEX_TOOLS_TARGET_BASE}/../lib
	cd ${HEX_TOOLS_TARGET_BASE}/../lib
	ln -sf ../usr/lib/ld-musl-hexagon.so.1
}


build_musl_scs() {
	# Build a shadow-call-stack-instrumented libc for the scs multilib.
	# The Hexagon driver's scs multilib (see clang Hexagon.cpp) prepends
	# ${SysRoot}/usr/lib/scs to the library search path when a program is
	# built with -fsanitize=shadow-call-stack, so an instrumented libc.a/
	# libc.so must live there.  Anything not present in scs/ falls back to
	# the uninstrumented libraries in usr/lib.
	cd ${BASE}
	cd musl
	make clean

	SCS_STAGING=${BASE}/obj_musl_scs_staging
	rm -rf ${SCS_STAGING}

	RESOURCE_DIR=$(${TOOLCHAIN_BIN}/clang --print-resource-dir)
	CROSS_COMPILE=${CC_PREFIX} \
		AR=llvm-ar \
		RANLIB=llvm-ranlib \
		STRIP=llvm-strip \
		CC=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin/hexagon-unknown-linux-musl-clang \
		LIBCC="${RESOURCE_DIR}/lib/hexagon-unknown-linux-musl/libclang_rt.builtins.a" \
		CFLAGS="${MUSL_CFLAGS} ${SCS_CFLAGS} -D__HEXAGON_SCS_THREADS__ -D__HEXAGON_SCS_REG=${SCS_REG}" \
		./configure --target=hexagon --prefix=${SCS_STAGING}
	PATH=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin/:$PATH make -j install

	mkdir -p ${HEX_TOOLS_TARGET_BASE}/lib/scs
	# musl folds libm/libpthread/etc. into libc; only libc.a/libc.so exist.
	cp -a ${SCS_STAGING}/lib/libc.a  ${HEX_TOOLS_TARGET_BASE}/lib/scs/
	cp -a ${SCS_STAGING}/lib/libc.so ${HEX_TOOLS_TARGET_BASE}/lib/scs/ 2>/dev/null || true

	# The driver resolves startup objects from the selected multilib dir, so
	# every object it can ask for has to exist in scs/ or the link fails
	# outright: crt1.o for a default link, rcrt1.o for -static -pie, and
	# crti.o/crtn.o for -shared.
	#
	# These are correct as built: musl's arch/hexagon/crt_arch.h points the SCS
	# register at a per-entry-point shadow stack before the first instrumented
	# function runs, so crt1.o, Scrt1.o and rcrt1.o each set it up, as does
	# ldso/dlstart.c inside libc.so.  crti.o/crtn.o are plain _init/_fini
	# prologue asm with no shadow-call-stack component.
	for o in crt1.o rcrt1.o Scrt1.o crti.o crtn.o; do
		cp -a ${SCS_STAGING}/lib/${o} ${HEX_TOOLS_TARGET_BASE}/lib/scs/ 2>/dev/null || true
	done
}

build_runtimes_scs() {
	# Build shadow-call-stack-instrumented libc++/libc++abi/libunwind into
	# the scs multilib dir (usr/lib/scs).  This is a standalone runtimes
	# build against the freshly-built Hexagon clang (the embedded obj_llvm
	# RUNTIMES_ machinery only builds the default, uninstrumented variant).
	# compiler-rt is intentionally excluded -- the scs multilib is about
	# instrumenting the C/C++ runtime, not rebuilding the sanitizer runtimes.
	cd ${BASE}
	rm -rf ./obj_runtimes_scs

	PATH=${TOOLCHAIN_BIN}:${PATH} \
		cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX:PATH=${HEX_TOOLS_TARGET_BASE} \
		-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR:BOOL=OFF \
		-DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
		-DCMAKE_C_FLAGS="${SCS_CFLAGS}" \
		-DCMAKE_CXX_FLAGS="${SCS_CFLAGS}" \
		-DCMAKE_ASM_FLAGS="${SCS_CFLAGS}" \
		-DLIBCXX_HAS_MUSL_LIBC:BOOL=ON \
		-DLIBCXX_INCLUDE_BENCHMARKS:BOOL=OFF \
		-DLIBCXX_INCLUDE_TESTS:BOOL=OFF \
		-DLIBCXXABI_INCLUDE_TESTS:BOOL=OFF \
		-DLIBUNWIND_INCLUDE_TESTS:BOOL=OFF \
		-DLIBCXX_CXX_ABI=libcxxabi \
		-DLIBCXXABI_USE_LLVM_UNWINDER:BOOL=ON \
		-DLIBCXXABI_ENABLE_SHARED:BOOL=ON \
		-DLIBCXX_USE_COMPILER_RT:BOOL=ON \
		-DLIBCXXABI_USE_COMPILER_RT:BOOL=ON \
		-DLIBUNWIND_USE_COMPILER_RT:BOOL=ON \
		-DLIBCXX_INSTALL_LIBRARY_DIR=lib/scs \
		-DLIBCXXABI_INSTALL_LIBRARY_DIR=lib/scs \
		-DLIBUNWIND_INSTALL_LIBRARY_DIR=lib/scs \
		-DLIBCXX_INSTALL_INCLUDE_DIR=include/c++/v1 \
		-DLIBCXX_INSTALL_INCLUDE_TARGET_DIR=include/c++/v1 \
		-DLIBCXXABI_INSTALL_INCLUDE_DIR=include/c++/v1 \
		-DLIBUNWIND_INSTALL_INCLUDE_DIR=include \
		-C ./hexagon-linux-cross.cmake \
		-B ./obj_runtimes_scs \
		-S ./llvm-project/runtimes
	cmake --build ./obj_runtimes_scs --target install-cxx install-cxxabi install-unwind
	if [[ "${IN_CONTAINER-0}" -eq 1 ]]; then
		rm -rf ./obj_runtimes_scs
	fi
}

populate_sanitizer_multilibs() {
	# The Hexagon driver declares three musl multilibs -- msan, asan and scs
	# (see HexagonToolChain's constructor) -- and selecting any of them changes
	# where BOTH the startup objects and the compiler-rt runtimes are looked up:
	#
	#   * Hexagon.cpp's StartFile() builds "${SysRoot}/usr/lib${suffix}/crt1.o"
	#     with no existence check and no fallback, and
	#   * HexagonToolChain::getCompilerRTPath() appends the same suffix, so
	#     getCompilerRT() stops finding libclang_rt.<x>-hexagon.a in usr/lib.
	#
	# compiler-rt is deliberately built once, uninstrumented, into usr/lib (the
	# runtimes are interposition/bookkeeping code; there is no reason to build a
	# shadow-call-stack copy of them).  So without this step:
	#
	#   -fsanitize=address              -> cannot open usr/lib/asan/crt1.o
	#   -fsanitize=shadow-call-stack,undefined
	#                                  -> cannot open libclang_rt.ubsan_standalone.a
	#
	# i.e. ASan is unusable and the scs multilib cannot be combined with any
	# runtime-backed sanitizer.  Mirror what each multilib is missing.
	for ml in asan scs; do
		mldir=${HEX_TOOLS_TARGET_BASE}/lib/${ml}
		mkdir -p ${mldir}
		# Startup objects: the scs multilib builds its own (instrumented, with
		# the SCS register set up before any instrumented code runs), so only
		# fill in what is absent.  asan needs no instrumented libc -- it works
		# by interposing at run time -- so the base objects are correct there.
		for o in crt1.o rcrt1.o Scrt1.o crti.o crtn.o; do
			[[ -e ${HEX_TOOLS_TARGET_BASE}/lib/${o} && ! -e ${mldir}/${o} ]] && \
				ln -sf --relative ${HEX_TOOLS_TARGET_BASE}/lib/${o} ${mldir}/${o}
		done
		# compiler-rt runtimes, including the .syms link-order files the driver
		# passes via --dynamic-list.
		for f in ${HEX_TOOLS_TARGET_BASE}/lib/libclang_rt.*; do
			[[ -e ${f} ]] || continue
			ln -sf --relative ${f} ${mldir}/$(basename ${f})
		done
	done
}

build_scs_multilib() {
	# build_musl_scs must run first: it installs the startup objects into
	# usr/lib/scs, and build_runtimes_scs configures with
	# -fsanitize=shadow-call-stack, which makes the driver select the scs
	# multilib.  Without crt1.o there, CMake's compiler feature tests (which
	# link a full executable) fail with "cannot open .../usr/lib/scs/crt1.o",
	# CXX_SUPPORTS_FNO_EXCEPTIONS_FLAG comes back Failed, and libunwind's
	# CMakeLists aborts the whole configure.
	build_musl_scs
	build_runtimes_scs
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
	                  --disable-rbd \
		--target-list=hexagon-softmmu,hexagon-linux-user --prefix=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE} \
		--extra-cflags="-Wno-error=misleading-indentation" \

#	--cc=clang \
#	--cross-prefix=hexagon-unknown-linux-musl-
#	--cross-cc-hexagon="hexagon-unknown-linux-musl-clang" \
#		--cross-cc-cflags-hexagon="-mv67 --sysroot=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/target/hexagon-unknown-linux-musl"

	make -j
	make -j install

	cat <<EOF > ./qemu_wrapper.sh
#!/bin/bash

set -euo pipefail

export QEMU_LD_PREFIX=${HEX_TOOLS_TARGET_BASE}

exec ${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin/qemu-hexagon \$*
EOF
	cp ./qemu_wrapper.sh ${TOOLCHAIN_BIN}/
	chmod +x ./qemu_wrapper.sh ${TOOLCHAIN_BIN}/qemu_wrapper.sh
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
c_ld = '${TOOLCHAIN_BIN}/ld.lld'
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
		RESOURCE_DIR=$(${TOOLCHAIN_BIN}/clang --print-resource-dir)
		ln -sf --relative "${RESOURCE_DIR}/lib/hexagon-unknown-none-elf/libclang_rt.builtins.a" \
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
	cd ${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/target/picolibc
	ln -sf hexagon-unknown-none-elf hexagon-none-elf 2>/dev/null || true
}

install_baremetal_cfg() {
	cd ${BASE}
	cp hexagon-unknown-none-elf.cfg ${TOOLCHAIN_BIN}/hexagon-unknown-none-elf.cfg
	# The cfg asks for ld.eld, which is only installed when ELD is part of the
	# build (see build_llvm_clang).  Without this fallback, every baremetal
	# link with the shipped toolchain dies at
	#   clang: error: invalid linker name in argument '--ld-path=.../ld.eld'
	# since clang auto-loads this cfg for --target=hexagon-unknown-none-elf.
	if [[ ! -e ${TOOLCHAIN_BIN}/ld.eld ]]; then
		sed -i 's|^--ld-path=<CFGDIR>/ld.eld$|--ld-path=<CFGDIR>/ld.lld|' \
			${TOOLCHAIN_BIN}/hexagon-unknown-none-elf.cfg
	fi
	ln -sf hexagon-unknown-none-elf.cfg ${TOOLCHAIN_BIN}/hexagon.cfg
}

purge_builds() {
	rm -rf ${BASE}/obj_*/
}

TOOLCHAIN_INSTALL_REL=${TOOLCHAIN_INSTALL}
TOOLCHAIN_INSTALL=$(readlink -f ${TOOLCHAIN_INSTALL})
TOOLCHAIN_BIN=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/bin
TOOLCHAIN_LIB=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/lib
HEX_SYSROOT=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/target/hexagon-unknown-linux-musl
HEX_TOOLS_TARGET_BASE=${HEX_SYSROOT}/usr
HEX_PICOLIBC_BASE=${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/target/picolibc/hexagon-unknown-none-elf
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

# Flags for the shadow-call-stack multilib (usr/lib/scs).  On Hexagon,
# -fsanitize=shadow-call-stack uses r18 as the shadow-stack pointer by default
# (selectable with -mscs-reg=<reg>) and the backend errors unless the register
# is also reserved with -ffixed-<reg>.
SCS_REG=${SCS_REG:-r18}
SCS_CFLAGS="-fsanitize=shadow-call-stack -mscs-reg=${SCS_REG} -ffixed-${SCS_REG}"

which clang
clang --version
ninja --version
cmake --version
python3 --version

build_llvm_clang

# Create sysroot symlink in build tree so the build-tree clang can
# resolve DEFAULT_SYSROOT for partial-link steps during builtins/runtimes.
mkdir -p ${BASE}/obj_llvm/target
ln -sfn "${HEX_SYSROOT}" ${BASE}/obj_llvm/target/hexagon-unknown-linux-musl

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
build_builtins
build_musl

# Create stub archives for libraries being built by runtimes.
# The Hexagon driver unconditionally links -lc++ -lc++abi -lunwind;
# stubs prevent link failures during compiler-rt partial-link steps.
for lib in c++ c++abi unwind; do
    ${TOOLCHAIN_BIN}/llvm-ar rc ${HEX_TOOLS_TARGET_BASE}/lib/lib${lib}.a
done

build_runtimes
#build_sanitizers

# Shadow-call-stack multilib (usr/lib/scs).  Non-fatal: a failure here should
# not discard the whole toolchain -- everything that does not use
# -fsanitize=shadow-call-stack still works.  It is NOT a soft degradation for
# SCS itself, though: Hexagon.cpp's StartFile() resolves crt1.o from
# usr/lib/scs unconditionally, with no fallback to usr/lib, so an incomplete
# scs/ leaves every SCS link failing.  Say so loudly rather than shipping a
# toolchain whose advertised feature silently does not link.
if ! build_scs_multilib; then
	SCS_MULTILIB_FAILED=1
	echo "WARNING: build_scs_multilib failed; usr/lib/scs is incomplete and" >&2
	echo "WARNING: -fsanitize=shadow-call-stack will NOT link with this toolchain." >&2
fi

# Fill in the startup objects and compiler-rt runtimes that the driver expects
# to find under each selected multilib.  Must run after build_runtimes (which
# installs compiler-rt) and after build_scs_multilib (which creates usr/lib/scs
# and its own instrumented startup objects).
populate_sanitizer_multilibs

build_picolibc
install_baremetal_cfg

RESOURCE_DIR=$(${TOOLCHAIN_BIN}/clang --print-resource-dir)
for t in ${CROSS_ALL}
do
	cp -ra ${TOOLCHAIN_INSTALL}/${NATIVE_TRIPLE}/target ${TOOLCHAIN_INSTALL}/${t}
	cp ${TOOLCHAIN_BIN}/hexagon-unknown-none-elf.cfg ${TOOLCHAIN_INSTALL}/${t}/bin/ 2>/dev/null || true
	ln -sf hexagon-unknown-none-elf.cfg ${TOOLCHAIN_INSTALL}/${t}/bin/hexagon.cfg 2>/dev/null || true

	# install-builtins/install-runtimes-hexagon-unknown-linux-musl only ever
	# run against the native obj_llvm build, so each cross triple's own
	# resource dir is missing the actual Hexagon-target runtime objects
	# (libclang_rt.builtins.a, clang_rt.crtbegin.o, clang_rt.crtend.o) that
	# the compat symlink under target/.../usr/lib (copied above) points at
	# -- linking any Linux-target program with this cross triple's clang
	# fails with "unable to find library -lclang_rt.builtins-hexagon"
	# without this. Derive the path by substituting the triple rather than
	# executing the cross clang binary, which may not be runnable on the
	# build host (e.g. aarch64-linux-gnu without binfmt/qemu-user set up).
	CROSS_RESOURCE_DIR=${RESOURCE_DIR/\/${NATIVE_TRIPLE}\//\/${t}\/}
	mkdir -p ${CROSS_RESOURCE_DIR}/lib/hexagon-unknown-linux-musl
	cp -a ${RESOURCE_DIR}/lib/hexagon-unknown-linux-musl/. ${CROSS_RESOURCE_DIR}/lib/hexagon-unknown-linux-musl/
done
build_qemu

cd ${BASE}

if [[ ${MAKE_TARBALLS-0} -eq 1 ]]; then
    tar c -C $(dirname ${TOOLCHAIN_INSTALL_REL}) ${REL_NAME}/${NATIVE_TRIPLE} \
        | python3 ${BASE}/tar-strip-symlink-modes.py \
        | zstd --fast -T0 > ${RESULTS_DIR}/${REL_NAME}.tar.zst
	for t in ${CROSS_ALL}
	do
		if [[ -d ${TOOLCHAIN_INSTALL_REL}/${t} ]]; then
			tar c -C $(dirname ${TOOLCHAIN_INSTALL_REL}) ${REL_NAME}/${t} \
			    | python3 ${BASE}/tar-strip-symlink-modes.py \
			    | zstd --fast -T0 > ${RESULTS_DIR}/${REL_NAME}_${t}.tar.zst
		fi
	done
    cd ${RESULTS_DIR}
    sha256sum *.tar.zst | tee SHA256SUMS
fi
