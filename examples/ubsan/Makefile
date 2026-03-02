include common.mk

CFLAGS := $(LINUX_STATIC_FLAGS) -fsanitize=undefined -fno-sanitize-recover=all

TARGET := ubsan_demo

.PHONY: all clean run

all: $(TARGET)

$(TARGET): ubsan_demo.c
	$(CC_LINUX) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

run: $(TARGET)
	@echo "--- UBSan: signed integer overflow ---"
	-$(QEMU_HEXAGON) -L $(SYSROOT_LINUX) ./$(TARGET) 1
	@echo ""
	@echo "--- UBSan: shift exponent too large ---"
	-$(QEMU_HEXAGON) -L $(SYSROOT_LINUX) ./$(TARGET) 2
	@echo ""
	@echo "--- UBSan: null pointer dereference ---"
	-$(QEMU_HEXAGON) -L $(SYSROOT_LINUX) ./$(TARGET) 3
