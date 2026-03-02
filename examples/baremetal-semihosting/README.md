# Baremetal Semihosting Demo

Demonstrates a baremetal "Hello, world!" on Hexagon using picolibc and
semihosting for I/O.

## How It Works

The program runs without an operating system. Standard I/O (`printf`, etc.)
is provided by **semihosting**: the emulator (or hardware simulator) intercepts
special trap instructions and performs I/O on the host.

## Build and Run

```
make
make run
```

### Alternative Runner

If you have the Qualcomm Hexagon simulator (not included in the open-source
toolchain):

```
hexagon-sim -mv68 hello_semihost.elf
```

## Supported CPU Versions

Change `-mcpu=hexagonv68` in the Makefile to target a different architecture.
Available: v68, v69, v71, v73, v75, v79, v81.

For non-v68 architectures, you also need to specify the matching library
directory and linker script. See the `hexagon-unknown-none-elf.cfg` file for
details.
