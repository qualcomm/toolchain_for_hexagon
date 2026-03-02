include common.mk

# The hexagon-unknown-none-elf target auto-discovers its .cfg file, which
# provides all the necessary flags for picolibc + semihosting + ld.eld.
# We only need to specify the CPU version.
CFLAGS := -mcpu=hexagonv68 -g

TARGET := hello_semihost.elf

.PHONY: all clean run

all: $(TARGET)

$(TARGET): hello_semihost.c
	$(CC_BAREMETAL) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

run: $(TARGET)
	$(QEMU_SYSTEM) -M sim -cpu v68 -semihosting -nographic -kernel ./$(TARGET)
