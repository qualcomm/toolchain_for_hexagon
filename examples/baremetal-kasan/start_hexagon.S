// Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
// SPDX-License-Identifier: BSD-3-Clause-Clear

// Hexagon bare-metal startup for baremetal_kasan.
// Sets up the stack pointer and calls main.

.section .reset, "ax"
.global reset_handler
reset_handler:
    r29 = ##__stack_top
    call main
.Lwait:
    jump .Lwait
