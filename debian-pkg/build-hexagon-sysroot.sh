#!/bin/bash -x

#  Copyright (c) 2021, Qualcomm Innovation Center, Inc. All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause

# Build Hexagon cross-toolchain sysroot .deb packages using the system
# clang/lld from Ubuntu.  This script does NOT build LLVM/Clang itself --
# it reuses /usr/lib/llvm-${LLVM_VERSION} and only builds the target
# sysroot components (linux headers, musl, compiler-rt, libc++, picolibc).

set -euo pipefail
set -x

# -- LLVM version (override via environment, e.g. LLVM_VERSION=22) ----
LLVM_VERSION="${LLVM_VERSION:-22}"

# -- Paths --------------------------------------------------------------
# LLVM_ROOT can be overridden via environment (e.g. to point at a
# freshly-built toolchain instead of the system /usr/lib/llvm-N).
LLVM_ROOT="${LLVM_ROOT:-/usr/lib/llvm-${LLVM_VERSION}}"
CC="${CC:-${LLVM_ROOT}/bin/clang}"
CXX="${CXX:-${LLVM_ROOT}/bin/clang++}"
AR="${AR:-${LLVM_ROOT}/bin/llvm-ar}"
NM="${NM:-${LLVM_ROOT}/bin/llvm-nm}"
RANLIB="${RANLIB:-${LLVM_ROOT}/bin/llvm-ranlib}"
STRIP="${STRIP:-${LLVM_ROOT}/bin/llvm-strip}"
OBJCOPY="${OBJCOPY:-${LLVM_ROOT}/bin/llvm-objcopy}"
OBJDUMP="${OBJDUMP:-${LLVM_ROOT}/bin/llvm-objdump}"
READELF="${READELF:-${LLVM_ROOT}/bin/llvm-readelf}"
SIZE="${SIZE:-${LLVM_ROOT}/bin/llvm-size}"
LLD="${LLD:-${LLVM_ROOT}/bin/ld.lld}"
LLVM_CMAKE_DIR="${LLVM_CMAKE_DIR:-${LLVM_ROOT}/lib/cmake/llvm}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LINUX_SRC="${REPO_ROOT}/linux"
MUSL_SRC="${REPO_ROOT}/musl"
PICOLIBC_SRC="${REPO_ROOT}/picolibc"
LLVM_PROJECT="${REPO_ROOT}/llvm-project"

BUILD="${SCRIPT_DIR}/build"
DEBS="${SCRIPT_DIR}/debs"
mkdir -p "${BUILD}" "${DEBS}"

# Use a private TMPDIR to avoid /tmp contention during parallel builds
export TMPDIR="${BUILD}/tmp"
mkdir -p "${TMPDIR}"

# Architecture versions for picolibc -- probe the compiler for support
HEX_ARCH_ALL="v68 v69 v71 v73 v75 v79 v81"
HEX_ARCH_VERSIONS=""
for _v in ${HEX_ARCH_ALL}; do
    if "${CC}" --target=hexagon-unknown-none-elf "-m${_v}" -c -x c /dev/null \
         -o /dev/null 2>/dev/null; then
        HEX_ARCH_VERSIONS="${HEX_ARCH_VERSIONS:+${HEX_ARCH_VERSIONS} }${_v}"
    fi
done
echo "Supported arch versions: ${HEX_ARCH_VERSIONS}"

# Target install prefixes (FHS cross paths)
LINUX_SYSROOT=/usr/hexagon-unknown-linux-musl
BAREMETAL_SYSROOT=/usr/hexagon-unknown-none-elf

# musl build flags (from build-toolchain.sh)
MUSL_CFLAGS="-G0 -O0 -mv68 -fno-builtin -mlong-calls --target=hexagon-unknown-linux-musl"
MUSL_CFLAGS="${MUSL_CFLAGS} -Wno-switch-bool"
MUSL_CFLAGS="${MUSL_CFLAGS} -Wno-unsupported-floating-point-opt"

# Package version -- override via environment or default to date-based
PKG_VERSION="${PKG_VERSION:-0.1.0~$(date +%Y%m%d)}"

# Versioned package names (embed LLVM_VERSION so everything stays in sync)
PKG_LINUX_HEADERS=linux-libc-dev-hexagon-cross
PKG_MUSL=musl-dev-hexagon-cross
PKG_RT_LINUX="libclang-rt-${LLVM_VERSION}-builtins-hexagon-cross"
PKG_LIBCXX="libc++-${LLVM_VERSION}-dev-hexagon-cross"
PKG_LIBCXXABI="libc++abi-${LLVM_VERSION}-dev-hexagon-cross"
PKG_LIBUNWIND="libunwind-${LLVM_VERSION}-dev-hexagon-cross"
PKG_RT_BAREMETAL="libclang-rt-${LLVM_VERSION}-builtins-hexagon-baremetal"
PKG_PICOLIBC=picolibc-hexagon-unknown-none-elf
PKG_CLANG_CROSS=clang-hexagon-cross

# -- Helpers ------------------------------------------------------------

stage_dir() {
    # Return staging directory for a given package name
    echo "${BUILD}/stage-${1}"
}

make_deb() {
    local pkg="$1"
    local stage
    stage="$(stage_dir "${pkg}")"

    # Write DEBIAN/control from the template
    mkdir -p "${stage}/DEBIAN"
    extract_control "${pkg}" > "${stage}/DEBIAN/control"

    fakeroot dpkg-deb --build "${stage}" "${DEBS}/"
}

extract_control() {
    # Extract a single binary package stanza from debian/control and
    # reformat it as a DEBIAN/control for dpkg-deb.
    # Strip debhelper substvars (${misc:Depends} etc.) since we use
    # dpkg-deb directly rather than debhelper.
    local pkg="$1"
    local control="${SCRIPT_DIR}/debian/control"

    # Grab Maintainer from the Source stanza
    local maintainer
    maintainer="$(awk '/^Maintainer:/{print; exit}' "${control}")"

    awk -v pkg="${pkg}" '
        /^Package:/ { found = ($2 == pkg) }
        found { print }
        found && /^$/ { exit }
    ' "${control}" \
        | sed '/^$/d' \
        | sed 's/, *\${[^}]*}//g; s/\${[^}]*}, *//g; s/\${[^}]*}//g'
    echo "Version: ${PKG_VERSION}"
    echo "${maintainer}"
}

# -- Step 1: Linux kernel headers --------------------------------------

build_linux_headers() {
    echo "=== Step 1: Linux kernel headers ==="
    local stage
    stage="$(stage_dir "${PKG_LINUX_HEADERS}")"
    rm -rf "${stage}"
    mkdir -p "${stage}${LINUX_SYSROOT}/usr"

    cd "${LINUX_SRC}"
    make mrproper
    make ARCH=hexagon headers_install \
        INSTALL_HDR_PATH="${stage}${LINUX_SYSROOT}/usr"

    # Remove the ..install.cmd files that kernel leaves behind
    find "${stage}" -name '.install' -o -name '..install.cmd' | xargs rm -f
}

# -- Step 2: musl headers (temporary, needed for compiler-rt) ----------

build_musl_headers() {
    echo "=== Step 2: musl headers (temporary) ==="
    local hdr_tmp="${BUILD}/musl-headers-tmp"
    rm -rf "${hdr_tmp}"
    mkdir -p "${hdr_tmp}"

    cd "${MUSL_SRC}"
    make clean || true

    CC="${CC}" \
    CROSS_COMPILE=hexagon-unknown-linux-musl- \
    LIBCC="-lclang_rt.builtins-hexagon" \
    CFLAGS="${MUSL_CFLAGS}" \
        ./configure --target=hexagon --prefix="${hdr_tmp}"
    make install-headers
}

# -- Step 3: compiler-rt builtins (Linux) ------------------------------

build_clang_rt_builtins_linux() {
    echo "=== Step 3: compiler-rt builtins (Linux target) ==="
    local stage
    stage="$(stage_dir "${PKG_RT_LINUX}")"
    rm -rf "${stage}"
    mkdir -p "${stage}${LINUX_SYSROOT}/usr/lib"

    local objdir="${BUILD}/obj_clang_rt_linux"
    rm -rf "${objdir}"

    # Assemble a temporary sysroot with linux headers + musl headers
    local tmp_sysroot="${BUILD}/tmp-sysroot-builtins"
    rm -rf "${tmp_sysroot}"
    mkdir -p "${tmp_sysroot}/usr/include"

    local linux_stage
    linux_stage="$(stage_dir "${PKG_LINUX_HEADERS}")"
    cp -a "${linux_stage}${LINUX_SYSROOT}/usr/include/." "${tmp_sysroot}/usr/include/"
    cp -a "${BUILD}/musl-headers-tmp/include/." "${tmp_sysroot}/usr/include/"

    cmake -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_CMAKE_DIR:PATH="${LLVM_CMAKE_DIR}" \
        -DCMAKE_INSTALL_PREFIX:PATH="${stage}${LINUX_SYSROOT}/usr" \
        -DCMAKE_CROSSCOMPILING:BOOL=ON \
        -DCOMPILER_RT_OS_DIR= \
        -DCAN_TARGET_hexagon=1 \
        -DCAN_TARGET_x86_64=0 \
        -DCMAKE_C_COMPILER:STRING="${CC}" \
        -DCMAKE_CXX_COMPILER:STRING="${CXX}" \
        -DCMAKE_ASM_COMPILER:STRING="${CC}" \
        -DCMAKE_AR:STRING="${AR}" \
        -DCMAKE_NM:STRING="${NM}" \
        -DCMAKE_RANLIB:STRING="${RANLIB}" \
        -DCMAKE_C_COMPILER_TARGET:STRING=hexagon-unknown-linux-musl \
        -DCMAKE_CXX_COMPILER_TARGET:STRING=hexagon-unknown-linux-musl \
        -DCMAKE_ASM_COMPILER_TARGET:STRING=hexagon-unknown-linux-musl \
        -DCMAKE_SYSROOT:PATH="${tmp_sysroot}" \
        -DCMAKE_C_COMPILER_FORCED:BOOL=ON \
        -DCMAKE_CXX_COMPILER_FORCED:BOOL=ON \
        -C "${LLVM_PROJECT}/compiler-rt/cmake/caches/hexagon-linux-builtins.cmake" \
        -B "${objdir}" \
        -S "${LLVM_PROJECT}/compiler-rt"

    cmake --build "${objdir}" -- -v install-builtins
}

# -- Step 4: musl full build -------------------------------------------

build_musl_full() {
    echo "=== Step 4: musl full build ==="
    local stage
    stage="$(stage_dir "${PKG_MUSL}")"
    rm -rf "${stage}"
    mkdir -p "${stage}${LINUX_SYSROOT}/usr" "${stage}${LINUX_SYSROOT}/lib"

    # Point at the freshly-built builtins
    local builtins_stage
    builtins_stage="$(stage_dir "${PKG_RT_LINUX}")"
    local LIBCC="${builtins_stage}${LINUX_SYSROOT}/usr/lib/libclang_rt.builtins-hexagon.a"

    cd "${MUSL_SRC}"
    make clean || true

    CC="${CC}" \
    AR="${AR}" \
    RANLIB="${RANLIB}" \
    STRIP="${STRIP}" \
    CROSS_COMPILE=hexagon-unknown-linux-musl- \
    LIBCC="${LIBCC}" \
    CFLAGS="${MUSL_CFLAGS}" \
        ./configure --target=hexagon --prefix="${stage}${LINUX_SYSROOT}/usr"

    make -j"$(nproc)" install

    # Create dynamic linker symlinks
    cd "${stage}${LINUX_SYSROOT}/usr/lib"
    ln -sf libc.so ld-musl-hexagon.so
    ln -sf ld-musl-hexagon.so ld-musl-hexagon.so.1

    # /usr/hexagon-unknown-linux-musl/lib/ld-musl-hexagon.so.1 -> ../usr/lib/...
    cd "${stage}${LINUX_SYSROOT}/lib"
    ln -sf ../usr/lib/ld-musl-hexagon.so.1

    # multilib arch symlinks (v68 -> ../usr/lib, etc.)
    for arch in ${HEX_ARCH_VERSIONS}; do
        ln -sf ../usr/lib "${stage}${LINUX_SYSROOT}/lib/${arch}"
    done
}

# -- Step 5: libc++/libc++abi/libunwind --------------------------------

build_runtimes() {
    echo "=== Step 5: libc++/libc++abi/libunwind ==="

    # Install everything into a temporary prefix, then split into per-package staging dirs
    local install_tmp="${BUILD}/runtimes-install-tmp"
    rm -rf "${install_tmp}"
    mkdir -p "${install_tmp}"

    local objdir="${BUILD}/obj_runtimes"
    rm -rf "${objdir}"

    # Assemble a combined sysroot from steps 1 + 3 + 4
    local combined="${BUILD}/combined-sysroot"
    rm -rf "${combined}"
    mkdir -p "${combined}/usr/include" "${combined}/usr/lib"

    local linux_stage
    linux_stage="$(stage_dir "${PKG_LINUX_HEADERS}")"
    local builtins_stage
    builtins_stage="$(stage_dir "${PKG_RT_LINUX}")"
    local musl_stage
    musl_stage="$(stage_dir "${PKG_MUSL}")"

    # Linux headers
    cp -a "${linux_stage}${LINUX_SYSROOT}/usr/include/." "${combined}/usr/include/"
    # musl headers + libs
    cp -a "${musl_stage}${LINUX_SYSROOT}/usr/include/." "${combined}/usr/include/"
    cp -a "${musl_stage}${LINUX_SYSROOT}/usr/lib/." "${combined}/usr/lib/"
    # compiler-rt builtins
    cp -a "${builtins_stage}${LINUX_SYSROOT}/usr/lib/." "${combined}/usr/lib/"

    cmake -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_CMAKE_DIR:PATH="${LLVM_CMAKE_DIR}" \
        -DCMAKE_INSTALL_PREFIX:PATH="${install_tmp}" \
        -DCMAKE_CROSSCOMPILING:BOOL=ON \
        -DCMAKE_C_COMPILER:STRING="${CC}" \
        -DCMAKE_CXX_COMPILER:STRING="${CXX}" \
        -DCMAKE_ASM_COMPILER:STRING="${CC}" \
        -DCMAKE_AR:STRING="${AR}" \
        -DCMAKE_NM:STRING="${NM}" \
        -DCMAKE_RANLIB:STRING="${RANLIB}" \
        -DCMAKE_STRIP:STRING="${STRIP}" \
        -DCMAKE_OBJCOPY:STRING="${OBJCOPY}" \
        -DCMAKE_C_COMPILER_TARGET:STRING=hexagon-unknown-linux-musl \
        -DCMAKE_CXX_COMPILER_TARGET:STRING=hexagon-unknown-linux-musl \
        -DCMAKE_ASM_COMPILER_TARGET:STRING=hexagon-unknown-linux-musl \
        -DCMAKE_SYSROOT:PATH="${combined}" \
        -DCMAKE_CXX_COMPILER_FORCED:BOOL=ON \
        -DCMAKE_C_COMPILER_FORCED:BOOL=ON \
        -DCMAKE_SIZEOF_VOID_P=4 \
        -DCMAKE_CXX_COMPILE_FEATURES="cxx_std_17;cxx_std_14;cxx_std_11;cxx_std_03;cxx_std_98" \
        -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
        -C "${LLVM_PROJECT}/libcxx/cmake/caches/hexagon-linux-runtimes.cmake" \
        -B "${objdir}" \
        -S "${LLVM_PROJECT}/runtimes"

    cmake --build "${objdir}" -- -v install

    # -- Split installed files into three per-package staging dirs --
    local stage_unwind stage_cxxabi stage_cxx
    stage_unwind="$(stage_dir "${PKG_LIBUNWIND}")"
    stage_cxxabi="$(stage_dir "${PKG_LIBCXXABI}")"
    stage_cxx="$(stage_dir "${PKG_LIBCXX}")"
    rm -rf "${stage_unwind}" "${stage_cxxabi}" "${stage_cxx}"

    local dst_unwind="${stage_unwind}${LINUX_SYSROOT}/usr"
    local dst_cxxabi="${stage_cxxabi}${LINUX_SYSROOT}/usr"
    local dst_cxx="${stage_cxx}${LINUX_SYSROOT}/usr"
    mkdir -p "${dst_unwind}/"{include,lib} "${dst_cxxabi}/"{include,lib} "${dst_cxx}/"{include,lib}

    # libunwind: libraries + top-level headers
    mv "${install_tmp}"/lib/libunwind* "${dst_unwind}/lib/"
    mkdir -p "${dst_unwind}/include/mach-o"
    for f in __libunwind_config.h libunwind.h libunwind.modulemap \
             unwind.h unwind_arm_ehabi.h unwind_itanium.h; do
        [ -f "${install_tmp}/include/${f}" ] && \
            mv "${install_tmp}/include/${f}" "${dst_unwind}/include/"
    done
    [ -f "${install_tmp}/include/mach-o/compact_unwind_encoding.h" ] && \
        mv "${install_tmp}/include/mach-o/compact_unwind_encoding.h" \
            "${dst_unwind}/include/mach-o/"

    # libc++abi: libraries + headers (cxxabi headers are under c++/v1/)
    mv "${install_tmp}"/lib/libc++abi* "${dst_cxxabi}/lib/"
    mkdir -p "${dst_cxxabi}/include/c++/v1"
    mv "${install_tmp}/include/c++/v1/cxxabi.h"           "${dst_cxxabi}/include/c++/v1/"
    mv "${install_tmp}/include/c++/v1/__cxxabi_config.h"  "${dst_cxxabi}/include/c++/v1/"

    # libc++: everything remaining (libraries + c++/v1 headers + share/ modules)
    mv "${install_tmp}"/lib/libc++* "${dst_cxx}/lib/"
    mv "${install_tmp}/include/c++" "${dst_cxx}/include/"
    if [ -d "${install_tmp}/share" ]; then
        mkdir -p "${dst_cxx}/share"
        mv "${install_tmp}/share/libc++" "${dst_cxx}/share/"
    fi
}

# -- Step 6: compiler-rt builtins (baremetal) --------------------------

build_clang_rt_builtins_baremetal() {
    echo "=== Step 6: compiler-rt builtins (baremetal) ==="
    local stage
    stage="$(stage_dir "${PKG_RT_BAREMETAL}")"
    rm -rf "${stage}"
    mkdir -p "${stage}${BAREMETAL_SYSROOT}/lib/hexagon-unknown-none-elf"

    local objdir="${BUILD}/obj_clang_rt_baremetal"
    rm -rf "${objdir}"

    cmake -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_CMAKE_DIR:PATH="${LLVM_CMAKE_DIR}" \
        -DCMAKE_INSTALL_PREFIX:PATH="${stage}${BAREMETAL_SYSROOT}" \
        -DCMAKE_C_COMPILER:STRING="${CC}" \
        -DCMAKE_CXX_COMPILER:STRING="${CXX}" \
        -DCMAKE_ASM_COMPILER:STRING="${CC}" \
        -DCMAKE_AR:STRING="${AR}" \
        -DCMAKE_NM:STRING="${NM}" \
        -DCMAKE_RANLIB:STRING="${RANLIB}" \
        -DCMAKE_C_COMPILER_TARGET:STRING=hexagon-unknown-none-elf \
        -DCMAKE_CXX_COMPILER_TARGET:STRING=hexagon-unknown-none-elf \
        -DCMAKE_ASM_COMPILER_TARGET:STRING=hexagon-unknown-none-elf \
        -C "${LLVM_PROJECT}/compiler-rt/cmake/caches/hexagon-builtins-baremetal.cmake" \
        -B "${objdir}" \
        -S "${LLVM_PROJECT}/compiler-rt"

    cmake --build "${objdir}" -- -v install-builtins
}

# -- Step 7: picolibc (per-arch v68-v81) ------------------------------

build_picolibc() {
    echo "=== Step 7: picolibc ==="
    local stage
    stage="$(stage_dir "${PKG_PICOLIBC}")"
    rm -rf "${stage}"

    # Get path to baremetal builtins for linking
    local bm_stage
    bm_stage="$(stage_dir "${PKG_RT_BAREMETAL}")"

    for archver in ${HEX_ARCH_VERSIONS}; do
        echo "--- Building picolibc for ${archver} ---"
        local builddir="${BUILD}/obj_picolibc_${archver}"
        rm -rf "${builddir}"

        local archlib="${stage}${BAREMETAL_SYSROOT}/lib/${archver}/G0"
        mkdir -p "${archlib}"

        # Symlink builtins into per-arch dir (resolves at install time via
        # the libclang-rt-*-builtins-hexagon-baremetal package)
        ln -sf ../../hexagon-unknown-none-elf/libclang_rt.builtins.a \
            "${archlib}/libclang_rt.builtins.a"

        # Generate meson cross-file
        local crossfile="${BUILD}/picolibc-hexagon-${archver}.txt"
        cat > "${crossfile}" <<CROSSEOF
[binaries]
c = ['${CC}', '--no-default-config', '--target=hexagon-unknown-none-elf', '-m${archver}', '-fno-pic', '-fno-PIE', '-static', '-nostdlib', '-fuse-init-array', '-G0']
c_ld = '${LLD}'
ar = '${AR}'
as = '${CC}'
nm = '${NM}'
strip = '${STRIP}'
objcopy = '${OBJCOPY}'

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

        meson setup \
            --cross-file "${crossfile}" \
            -Dprefix="${stage}${BAREMETAL_SYSROOT}" \
            -Dlibdir="lib/${archver}/G0" \
            -Dincludedir=include \
            -Dspecsdir=none \
            -Dtests=false \
            -Dmultilib=false \
            -Dposix-console=true \
            -Dsysroot-install=false \
            -Dc_link_args="-L${bm_stage}${BAREMETAL_SYSROOT}/lib/hexagon-unknown-none-elf" \
            "${builddir}" \
            "${PICOLIBC_SRC}"

        ninja -C "${builddir}"
        DESTDIR= ninja -C "${builddir}" install
    done
}

# -- Step 8: .cfg files + symlinks meta-package ------------------------

build_clang_hexagon_cross() {
    echo "=== Step 8: clang-hexagon-cross meta-package ==="
    local stage
    stage="$(stage_dir "${PKG_CLANG_CROSS}")"
    rm -rf "${stage}"

    # -- .cfg files ------------------------------------------------------
    local cfgdir="${stage}/usr/lib/llvm-${LLVM_VERSION}/bin"
    mkdir -p "${cfgdir}"
    cp "${SCRIPT_DIR}/hexagon-unknown-linux-musl.cfg" "${cfgdir}/"
    cp "${SCRIPT_DIR}/hexagon-unknown-none-elf.cfg"   "${cfgdir}/"

    # Short-form .cfg aliases so clang finds config via short triples
    ln -sf "hexagon-unknown-linux-musl.cfg" "${cfgdir}/hexagon-linux-musl.cfg"
    ln -sf "hexagon-unknown-none-elf.cfg"   "${cfgdir}/hexagon-none-elf.cfg"
    ln -sf "hexagon-unknown-none-elf.cfg"   "${cfgdir}/hexagon.cfg"

    # -- /usr/bin symlinks -----------------------------------------------
    local bindir="${stage}/usr/bin"
    mkdir -p "${bindir}"

    local clang_target="../lib/llvm-${LLVM_VERSION}/bin/clang-${LLVM_VERSION}"

    for triple in hexagon-unknown-linux-musl hexagon-unknown-none-elf \
                  hexagon-unknown-qurt hexagon-linux-musl hexagon-none-elf \
                  hexagon-qurt hexagon; do
        # clang / clang++ / cc -- versioned and unversioned
        for tool in clang clang++; do
            ln -sf "${clang_target}" "${bindir}/${triple}-${tool}"
            ln -sf "${clang_target}" "${bindir}/${triple}-${tool}-${LLVM_VERSION}"
        done
        ln -sf "${clang_target}" "${bindir}/${triple}-cc"

        # binutils-like tools
        for tool in ar ranlib nm objcopy objdump readelf strip size; do
            ln -sf "../lib/llvm-${LLVM_VERSION}/bin/llvm-${tool}" \
                "${bindir}/${triple}-${tool}"
        done

        # linker
        ln -sf "../lib/llvm-${LLVM_VERSION}/bin/ld.lld" \
            "${bindir}/${triple}-ld.lld"
    done
}

# -- Step 9: Build all .deb packages ----------------------------------

build_all_debs() {
    echo "=== Step 9: Building .deb packages ==="

    for pkg in \
        "${PKG_LINUX_HEADERS}" \
        "${PKG_MUSL}" \
        "${PKG_RT_LINUX}" \
        "${PKG_LIBUNWIND}" \
        "${PKG_LIBCXXABI}" \
        "${PKG_LIBCXX}" \
        "${PKG_RT_BAREMETAL}" \
        "${PKG_PICOLIBC}" \
        "${PKG_CLANG_CROSS}" \
    ; do
        make_deb "${pkg}"
    done

    echo "=== Done! Packages in ${DEBS}/ ==="
    ls -lh "${DEBS}/"*.deb
}

# -- Prerequisite checks ----------------------------------------------

check_prereqs() {
    local missing=()
    [[ -x "${CC}" ]]    || missing+=("clang-${LLVM_VERSION}")
    [[ -x "${LLD}" ]]   || missing+=("lld-${LLVM_VERSION}")
    [[ -x "${AR}" ]]    || missing+=("llvm-${LLVM_VERSION}")
    command -v cmake     >/dev/null || missing+=("cmake")
    command -v ninja     >/dev/null || missing+=("ninja-build")
    command -v meson     >/dev/null || missing+=("meson")
    command -v fakeroot  >/dev/null || missing+=("fakeroot")
    command -v dpkg-deb  >/dev/null || missing+=("dpkg")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing prerequisites: ${missing[*]}"
        echo "Install with: sudo apt install ${missing[*]}"
        exit 1
    fi

    echo "Using compiler: $(${CC} --version | head -1)"
}

# -- Main --------------------------------------------------------------

main() {
    check_prereqs

    # Steps 1-5: Linux sysroot (sequential -- each depends on prior)
    build_linux_headers         # 1
    build_musl_headers          # 2
    build_clang_rt_builtins_linux  # 3
    build_musl_full             # 4
    build_runtimes              # 5

    # Steps 6-7: Baremetal (independent of 4-5, but sequential here
    # for simplicity; could be parallelized)
    build_clang_rt_builtins_baremetal  # 6
    build_picolibc              # 7

    # Step 8: meta-package
    build_clang_hexagon_cross   # 8

    # Step 9: package everything
    build_all_debs              # 9
}

main "$@"
