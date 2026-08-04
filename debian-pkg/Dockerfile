# debian-pkg/Dockerfile — self-contained build + validation of Hexagon
# cross-toolchain .deb packages.
#
# Usage:
#   docker build -t hexagon-debs:latest -f debian-pkg/Dockerfile .
#
# The build downloads all source tarballs, applies patches, invokes
# build-hexagon-sysroot.sh (which produces 9 .deb packages), then
# validates them by installing and running compile + QEMU tests.
#
# .deb output: /root/hexagon-toolchain/debian-pkg/debs/

FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive

# ── Build arguments (override at build time) ────────────────────────
ARG VER=23.1.0-rc1
ARG LLVM_SRC_URL=https://github.com/llvm/llvm-project/archive/llvmorg-${VER}.tar.gz
ARG MUSL_SRC_URL=https://github.com/quic/musl/archive/hexagon-v1.2.4-jul-2026.tar.gz
ARG LINUX_SRC_URL=https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.13.5.tar.xz
ARG PICOLIBC_SRC_URL=https://github.com/picolibc/picolibc/releases/download/1.8.11/picolibc-1.8.11.tar.xz

# ── System dependencies ─────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates gnupg wget software-properties-common \
        build-essential bc patch rsync perl xz-utils \
        cmake ninja-build meson fakeroot \
        python3 qemu-user && \
    # Add LLVM 23 apt repository
    wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | \
        tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc && \
    add-apt-repository -y \
        "deb http://apt.llvm.org/noble/ llvm-toolchain-noble-23 main" && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        clang-23 lld-23 llvm-23-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /root/hexagon-toolchain

# ── Copy build scripts, configs, and patches ────────────────────────
COPY debian-pkg/ debian-pkg/
COPY patches/    patches/
COPY strip1-extract.py strip1-extract.py

# ── Download & extract sources ──────────────────────────────────────
# GNU tar 1.35 (this image's Ubuntu 24.04) fails extracting these large
# archives under rootless podman with "Cannot change mode: Operation not
# permitted" -- use strip1-extract.py (Python's tarfile) instead. See
# strip1-extract.py for details.
RUN wget -q "${LLVM_SRC_URL}" -O llvm-project.tar.gz && \
    mkdir llvm-project && \
    python3 strip1-extract.py llvm-project.tar.gz llvm-project && \
    rm llvm-project.tar.gz && \
    cd llvm-project && \
    for p in /root/hexagon-toolchain/patches/llvm-project/llvmorg-${VER}/*.patch; do \
        [ -f "$p" ] || continue; \
        echo "Applying $(basename "$p")"; \
        patch -p1 < "$p"; \
    done

RUN wget -q "${MUSL_SRC_URL}" -O musl.tar.gz && \
    mkdir musl && \
    python3 strip1-extract.py musl.tar.gz musl && \
    rm musl.tar.gz

RUN wget -q "${LINUX_SRC_URL}" -O linux.tar.xz && \
    mkdir linux && \
    python3 strip1-extract.py linux.tar.xz linux && \
    rm linux.tar.xz

RUN wget -q "${PICOLIBC_SRC_URL}" -O picolibc.tar.xz && \
    mkdir picolibc && \
    python3 strip1-extract.py picolibc.tar.xz picolibc && \
    rm picolibc.tar.xz

# ── Build .deb packages ─────────────────────────────────────────────
RUN PKG_VERSION=${VER} debian-pkg/build-hexagon-sysroot.sh

# ── Validate: install .debs, compile & run hello world ──────────────
RUN dpkg -i debian-pkg/debs/*.deb

RUN hexagon-linux-musl-clang++ -o /tmp/hello debian-pkg/test/hello.cpp && \
    QEMU_LD_PREFIX=/usr/hexagon-unknown-linux-musl qemu-hexagon /tmp/hello

RUN hexagon-linux-musl-clang++ -static -o /tmp/hello_s debian-pkg/test/hello.cpp && \
    qemu-hexagon /tmp/hello_s

RUN hexagon-none-elf-clang -o /tmp/hello_bare debian-pkg/test/hello_bare.c
