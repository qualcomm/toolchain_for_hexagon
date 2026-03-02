# ASan (Address Sanitizer) Demo

Demonstrates the Address Sanitizer on Hexagon Linux.

## Bugs Demonstrated

| # | Bug | Description |
|---|-----|-------------|
| 1 | Heap buffer overflow | Write 1 byte past a 16-byte `malloc` buffer |
| 2 | Use-after-free | Read memory after `free()` |
| 3 | Stack buffer overflow | Write past a stack-allocated array |

## Build and Run

```
make
make run
```

Or run a specific test case:

```
qemu-hexagon -L $SYSROOT ./asan_demo 1
```

## Flags

```
-fsanitize=address
```

ASan instruments heap, stack, and global memory accesses at compile time and
inserts redzones around allocations to detect overflows and use-after-free.
