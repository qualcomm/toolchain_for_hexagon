# UBSan (Undefined Behavior Sanitizer) Demo

Demonstrates the Undefined Behavior Sanitizer on Hexagon Linux.

## Bugs Demonstrated

| # | Bug | Description |
|---|-----|-------------|
| 1 | Signed integer overflow | `INT_MAX + 1` |
| 2 | Shift exponent too large | `1 << 33` on a 32-bit int |
| 3 | Null pointer dereference | Read through a NULL pointer |

## Build and Run

```
make
make run
```

Or run a specific test case:

```
qemu-hexagon -L $SYSROOT ./ubsan_demo 1
```

## Flags

```
-fsanitize=undefined -fno-sanitize-recover=all
```

`-fno-sanitize-recover=all` makes UBSan abort on the first error instead of
continuing execution, so the error is impossible to miss.
