// Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
// SPDX-License-Identifier: BSD-3-Clause-Clear

// Additional __asan_set_shadow_* routines needed by the Hexagon compiler
// that are not provided by the upstream baremetal_kasan project.

#include <stddef.h>

void *memset(void *s, int c, size_t n);

#define DEFINE_KASAN_SET_SHADOW_ROUTINE(byte)              \
  void __asan_set_shadow_##byte(void *addr, size_t size) { \
    memset(addr, 0x##byte, size);                          \
  }

DEFINE_KASAN_SET_SHADOW_ROUTINE(01)  // partially addressable (1 byte)
DEFINE_KASAN_SET_SHADOW_ROUTINE(02)  // partially addressable (2 bytes)
DEFINE_KASAN_SET_SHADOW_ROUTINE(03)  // partially addressable (3 bytes)
DEFINE_KASAN_SET_SHADOW_ROUTINE(04)  // partially addressable (4 bytes)
DEFINE_KASAN_SET_SHADOW_ROUTINE(05)  // partially addressable (5 bytes)
DEFINE_KASAN_SET_SHADOW_ROUTINE(06)  // partially addressable (6 bytes)
DEFINE_KASAN_SET_SHADOW_ROUTINE(07)  // partially addressable (7 bytes)
DEFINE_KASAN_SET_SHADOW_ROUTINE(f5)  // stack after return
DEFINE_KASAN_SET_SHADOW_ROUTINE(f8)  // stack use after scope
