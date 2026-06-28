# Toolchain for Hexagon

This repository contains scripts and recipes for building a cross toolchain for use with the [Hexagon DSP](https://developer.qualcomm.com/software/hexagon-dsp-sdk/dsp-processor).

Check the releases page for links to binary cross toolchain releases.  These can be used to build and test Hexagon linux userspace binaries, the hexagon linux kernel, and more.

## License
Toolchain for Hexagon is licensed under the BSD 3-clause "New" or "Revised" License. Check out the [LICENSE](LICENSE) for more details.


## Usage

Refer to [examples](examples/README.md) for sample use cases for this toolchain.

## Building the toolchain

Checkout the required source repos like `llvm-project`, `musl`, etc.  Either
invoke `get-src-tarballs.sh` with the corresponding `*_SRC_URL` links to the specific
releases to use (see `Dockerfile` for reference / last-known-good versions).

Or instead you can check out the trunk of those projects' repos using
`git` - try invoking `get-src-repos.sh $PWD $PWD/manifest`.  Once you have
cloned the repos locally, see `Dockerfile` for reference / last-known-good
versions to use as a basis.

Once the source repos are setup, build the toolchain using `build-toolchain.sh`.

> [!IMPORTANT]
> Note that build-toolchain.sh often makes assumptions about the source repos such
> that you should only expect it to work if you check out the known-good git refs
> used for previous releases.

`build-toolchain.sh` / `build-buildroot.sh` expect the inputs below as environment
variables:

* `ARTIFACT_TAG` - the tag from the llvm-project repo with which this release
should be labeled.
* `TOOLCHAIN_INSTALL` - the path to install the toolchain to.
* `ROOT_INSTALL` - the path to install the rootfs to.  Initially this will
only contain the target includes + libraries.
* `ARTIFACT_BASE` - the path to put the tarballs + manifests.
* optional `MAKE_TARBALLS` - if `MAKE_TARBALLS` is set to `1`, it will create
tarballs of the release and purge the intermediate build artifacts.
* optional `CROSS_TRIPLES` - if desired, canadian cross toolchains can be
 built for other targets.  Enabling this requires a
[zig toolchain](https://ziglang.org/download) on the host system.
* optional `CROSS_TRIPLES_PIC` - additional cross toolchain builds, built
with position-independent code.  This is required for eld and implies that
eld should be included with this toolchain.
* optional `CROSS_TRIPLES_DYLIB` - additional cross toolchain builds that
link LLVM and clang as shared libraries (`libLLVM.so` / `libclang-cpp.so`).

Sample usage:

    export ARTIFACT_TAG=17.0.0
    export TOOLCHAIN_INSTALL=$PWD/clang+llvm-${ARTIFACT_TAG}-cross-hexagon-unknown-linux-musl
    export ROOT_INSTALL=$PWD/install_rootfs
    export ARTIFACT_BASE=$PWD/artifacts
    export TEST_TOOLCHAIN=0
    export CROSS_TRIPLES=""
    export CROSS_TRIPLES_PIC="aarch64-windows-gnu x86_64-windows-gnu"
    export CROSS_TRIPLES_DYLIB="x86_64-linux-gnu aarch64-linux-gnu aarch64-macos"

    mkdir -p ${ARTIFACT_BASE}

    ./build-toolchain.sh 2>&1 | tee build_${ARTIFACT_TAG}.log
    if [[ ${TEST_TOOLCHAIN} -eq 1 ]]; then
        ./test-toolchain.sh 2>&1 | tee test_${ARTIFACT_TAG}.log
    fi
    BUSYBOX_SRC_URL=https://busybox.net/downloads/busybox-1.33.1.tar.bz2 \
       ./build-buildroot.sh 2>&1 | tee build_buildroot.log

Alternatively, you can run `build-in-container.sh` to build everything in a Docker
container and extract the results to `./hexagon-artifacts`.
