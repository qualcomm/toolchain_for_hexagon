/*
 * Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
 * SPDX-License-Identifier: BSD-3-Clause-Clear
 *
 * asan_demo.c — Address Sanitizer demo for Hexagon
 *
 * Demonstrates three classes of memory errors that ASan catches:
 *   1 — Heap buffer overflow
 *   2 — Use-after-free
 *   3 — Stack buffer overflow
 *
 * Build:
 *   make
 *
 * Run:
 *   make run
 *   # or individually:
 *   qemu-hexagon -L <sysroot> ./asan_demo 1
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* 1. Heap buffer overflow */
static void trigger_heap_overflow(void) {
    char *buf = (char *)malloc(16);
    printf("Writing 1 byte past a 16-byte heap buffer...\n");
    buf[16] = 'A';  /* 1 byte past the allocation */
    free(buf);
}

/* 2. Use-after-free */
static void trigger_use_after_free(void) {
    char *buf = (char *)malloc(32);
    memset(buf, 'B', 32);
    free(buf);
    printf("Reading freed memory...\n");
    printf("buf[0] = 0x%02x\n", (unsigned char)buf[0]);
}

/* 3. Stack buffer overflow */
static void trigger_stack_overflow(void) {
    char buf[8];
    printf("Writing past a stack buffer of size 8...\n");
    /*
     * Use volatile to prevent the compiler from optimizing away
     * the out-of-bounds access.
     */
    volatile char *p = buf;
    p[8] = 'C';
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <1|2|3>\n", argv[0]);
        fprintf(stderr, "  1 — heap buffer overflow\n");
        fprintf(stderr, "  2 — use-after-free\n");
        fprintf(stderr, "  3 — stack buffer overflow\n");
        return 1;
    }

    int choice = atoi(argv[1]);
    switch (choice) {
    case 1: trigger_heap_overflow();    break;
    case 2: trigger_use_after_free();   break;
    case 3: trigger_stack_overflow();   break;
    default:
        fprintf(stderr, "Unknown choice: %s\n", argv[1]);
        return 1;
    }

    return 0;
}
