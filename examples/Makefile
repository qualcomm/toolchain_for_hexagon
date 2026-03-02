# Top-level Makefile — delegates to each example subdirectory
#
# Usage:
#   make                          # build all examples
#   make run                      # build and run all examples
#   make clean                    # clean all examples
#   make TOOLCHAIN_ROOT=/path/... # override toolchain location

SUBDIRS := ubsan asan baremetal-semihosting baremetal-kasan

.PHONY: all clean run $(SUBDIRS)

all: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@

clean:
	@for dir in $(SUBDIRS); do \
		$(MAKE) -C $$dir clean; \
	done

run: all
	@for dir in $(SUBDIRS); do \
		echo ""; \
		echo "===== Running $$dir ====="; \
		$(MAKE) -C $$dir run || true; \
	done
