FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive

# System deps + LLVM 22 apt repo
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates gnupg wget software-properties-common \
        qemu-user && \
    wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | \
        tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc && \
    add-apt-repository -y \
        "deb http://apt.llvm.org/noble/ llvm-toolchain-noble-22 main" && \
    apt-get update && \
    apt-get install -y --no-install-recommends clang-22 lld-22 && \
    rm -rf /var/lib/apt/lists/*

# Install cross-toolchain .deb packages
COPY debs/*.deb /tmp/debs/
RUN dpkg -i /tmp/debs/*.deb

# Copy test sources
COPY test/hello.cpp test/hello_bare.c /tmp/test/

# ── Test 1: Linux (musl) C++ ──
# Uses short triple form: hexagon-linux-musl-clang++
RUN hexagon-linux-musl-clang++ -o /tmp/test/hello /tmp/test/hello.cpp && \
    QEMU_LD_PREFIX=/usr/hexagon-unknown-linux-musl \
        qemu-hexagon /tmp/test/hello

# ── Test 2: Linux (musl) C++ static ──
RUN hexagon-linux-musl-clang++ -static -o /tmp/test/hello_static /tmp/test/hello.cpp && \
    qemu-hexagon /tmp/test/hello_static

# ── Test 3: Baremetal (picolibc) C ──
# Uses hexagon-none-elf-clang (short triple)
# No qemu run — just verify it compiles and links
RUN hexagon-none-elf-clang -o /tmp/test/hello_bare /tmp/test/hello_bare.c

CMD ["echo", "All tests passed."]
