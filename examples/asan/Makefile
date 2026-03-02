include common.mk

# ASan requires dynamic linking (the runtime uses _DYNAMIC for interception).
CFLAGS := $(LINUX_DYNAMIC_FLAGS) -fsanitize=address

TARGET := asan_demo

.PHONY: all clean run

all: $(TARGET)

$(TARGET): asan_demo.c
	$(CC_LINUX) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

run: $(TARGET)
	@echo "--- ASan: heap buffer overflow ---"
	-$(QEMU_HEXAGON) -L $(SYSROOT_LINUX) ./$(TARGET) 1
	@echo ""
	@echo "--- ASan: use-after-free ---"
	-$(QEMU_HEXAGON) -L $(SYSROOT_LINUX) ./$(TARGET) 2
	@echo ""
	@echo "--- ASan: stack buffer overflow ---"
	-$(QEMU_HEXAGON) -L $(SYSROOT_LINUX) ./$(TARGET) 3
