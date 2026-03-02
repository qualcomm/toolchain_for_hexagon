/*
 * Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
 * SPDX-License-Identifier: BSD-3-Clause-Clear
 *
 * ubsan_demo.c — Undefined Behavior Sanitizer demo for Hexagon
 *
 * Demonstrates three classes of undefined behavior that UBSan catches:
 *   1 — Signed integer overflow
 *   2 — Shift exponent too large
 *   3 — Null pointer dereference
 *
 * Build:
 *   make
 *
 * Run:
 *   make run
 *   # or individually:
 *   qemu-hexagon -L <sysroot> ./ubsan_demo 1
 */

#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

/* 1. Signed integer overflow */
static void trigger_overflow(void) {
    int x = INT_MAX;
    printf("INT_MAX = %d\n", x);
    printf("INT_MAX + 1 = %d\n", x + 1);  /* UB: signed overflow */
}

/* 2. Shift exponent too large */
static void trigger_bad_shift(void) {
    int x = 1;
    int bits = 33;  /* exceeds width of int (32 bits) */
    printf("1 << 33 = %d\n", x << bits);  /* UB: shift exponent >= width */
}

/* 3. Null pointer dereference */
static void trigger_null_deref(void) {
    int *p = NULL;
    printf("Dereferencing NULL pointer...\n");
    printf("*p = %d\n", *p);  /* UB: null dereference */
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <1|2|3>\n", argv[0]);
        fprintf(stderr, "  1 — signed integer overflow\n");
        fprintf(stderr, "  2 — shift exponent too large\n");
        fprintf(stderr, "  3 — null pointer dereference\n");
        return 1;
    }

    int choice = atoi(argv[1]);
    switch (choice) {
    case 1: trigger_overflow();   break;
    case 2: trigger_bad_shift();  break;
    case 3: trigger_null_deref(); break;
    default:
        fprintf(stderr, "Unknown choice: %s\n", argv[1]);
        return 1;
    }

    return 0;
}
