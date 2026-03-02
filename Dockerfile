
FROM ubuntu:22.04

ENV HOST_CLANG_VER 14
ENV PATH="/opt/zig-linux-x86_64-0.11.0:$PATH"

# Install common build utilities
RUN apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -yy \
	apt-transport-https ca-certificates \
        eatmydata software-properties-common wget gpgv2 unzip && \
    DEBIAN_FRONTEND=noninteractive eatmydata \
	wget --quiet https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz && \
	tar xf ./zig-linux-x86_64-0.11.0.tar.xz --directory /opt && \
    DEBIAN_FRONTEND=noninteractive eatmydata apt update && \
    DEBIAN_FRONTEND=noninteractive eatmydata \
    apt install -y --no-install-recommends \
        bison \
        cmake \
        flex \
        rsync \
        wget \
	build-essential \
	python3 \
	python3-venv \
	python3-distutils \
	clang-${HOST_CLANG_VER} \
	lld-${HOST_CLANG_VER} \
	libc++-${HOST_CLANG_VER}-dev \
	libc++abi-${HOST_CLANG_VER}-dev \
	python3-pip \
	curl \
	xz-utils \
	zstd \
	ca-certificates \
	ccache \
	git \
	software-properties-common \
        bc \
        ninja-build \
	cpio \
	python3-psutil \
	unzip && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${HOST_CLANG_VER} 100 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${HOST_CLANG_VER} 100 && \
    DEBIAN_FRONTEND=noninteractive eatmydata apt install -y --no-install-recommends llvm-${HOST_CLANG_VER} && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3 100

# Install Python packages that are not available in Ubuntu repos
RUN python3 -m pip install tomli tomli-w meson

RUN cat /etc/apt/sources.list | sed "s/^deb\ /deb-src /" >> /etc/apt/sources.list

RUN apt update && \
    DEBIAN_FRONTEND=noninteractive eatmydata \
    apt build-dep -yy --arch-only qemu clang python3

# From env.sh
ARG QEMU_REPO
ARG QEMU_REF=hexagon-sysemu-19-jan-2026

ARG ARTIFACT_BASE
ARG ARTIFACT_TAG

ENV VER 22.1.0
ENV TOOLCHAIN_INSTALL /usr/local/clang+llvm-${VER}-cross-hexagon-unknown-linux-musl/
ENV ROOT_INSTALL /usr/local/hexagon-unknown-linux-musl-rootfs
ENV MAKE_TARBALLS 1

ENV LLVM_SRC_URL https://github.com/llvm/llvm-project/archive/llvmorg-${VER}.tar.gz
ENV ELD_SRC_URL https://github.com/qualcomm/eld/archive/22.1.0.tar.gz
ENV LLVM_TESTS_SRC_URL https://github.com/llvm/llvm-test-suite/archive/llvmorg-${VER}.tar.gz
ENV MUSL_SRC_URL https://github.com/quic/musl/archive/hexagon-v1.2.4-dec-2025.tar.gz
ENV LINUX_SRC_URL https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.13.5.tar.xz
ENV BUSYBOX_SRC_URL https://busybox.net/downloads/busybox-1.36.1.tar.bz2
ENV PICOLIBC_SRC_URL https://github.com/picolibc/picolibc/releases/download/1.8.11/picolibc-1.8.11.tar.xz
ENV BUILDROOT_SRC_URL https://github.com/quic/buildroot/archive/hexagon-2025.04.30.tar.gz

ADD patches /root/hexagon-toolchain/patches
ADD test-suite-patches /root/hexagon-toolchain/test-suite-patches
ADD get-src-tarballs.sh /root/hexagon-toolchain/get-src-tarballs.sh
ADD *.cmake /root/hexagon-toolchain/
RUN cd /root/hexagon-toolchain && ./get-src-tarballs.sh ${PWD} ${TOOLCHAIN_INSTALL}/manifest

ADD test_init/test_init.c test_init/Makefile /root/hexagon-toolchain/test_init/

ENV IN_CONTAINER 1

ENV CROSS_TRIPLES ""
ENV CROSS_TRIPLES_PIC ""
ENV CROSS_TRIPLES_DYLIB "x86_64-linux-musl aarch64-linux-musl aarch64-windows-gnu x86_64-windows-gnu aarch64-macos"
ADD build-toolchain.sh /root/hexagon-toolchain/build-toolchain.sh
RUN cd /root/hexagon-toolchain && ./build-toolchain.sh ${ARTIFACT_TAG}

ADD build-buildroot.sh /root/hexagon-toolchain/build-buildroot.sh
RUN echo 'remoteencoding = UTF-8' >> ~/.wgetrc
RUN cd /root/hexagon-toolchain && ./build-buildroot.sh

ARG TEST_TOOLCHAIN=1

ADD test-toolchain.sh /root/hexagon-toolchain/test-toolchain.sh
RUN cd /root/hexagon-toolchain && ./test-toolchain.sh
