/*
 * Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
 * SPDX-License-Identifier: BSD-3-Clause-Clear
 *
 * hello_semihost.c — Baremetal "Hello, world!" using picolibc + semihosting
 *
 * This program runs on Hexagon without an OS.  Standard I/O is provided
 * by semihosting: the QEMU system emulator (or Hexagon simulator) traps
 * I/O calls and forwards them to the host.
 *
 * The toolchain's hexagon-unknown-none-elf.cfg auto-configures:
 *   - picolibc headers and libraries
 *   - crt0-semihost.o (startup with semihosting support)
 *   - -lsemihost (semihosting I/O layer)
 *   - ld.eld linker with picolibc.ld linker script
 *
 * Build:
 *   make
 *
 * Run with QEMU system emulator:
 *   qemu-system-hexagon -M sim -cpu v68 -semihosting -nographic -kernel hello_semihost.elf
 *
 * Run with Hexagon simulator (Qualcomm proprietary, not included):
 *   hexagon-sim -mv68 hello_semihost.elf
 */

#include <stdio.h>

int main(void) {
    printf("Hello from baremetal Hexagon with semihosting!\n");
    printf("picolibc printf is working.\n");

    int values[] = {1, 2, 3, 4, 5};
    int sum = 0;
    for (int i = 0; i < 5; i++)
        sum += values[i];

    printf("Sum of 1..5 = %d\n", sum);
    return 0;
}
