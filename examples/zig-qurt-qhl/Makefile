# Makefile for Zig QuRT QHL example
#
# Prerequisites:
#   1. Source the Hexagon SDK environment:
#      source /opt/Hexagon_SDK/6.4.0.2/setup_sdk_env.source
#   2. Have Zig installed (0.11.0 or newer)

.PHONY: all build run clean help

# Default target
all: build

# Build the example
build:
	@echo "Building Zig QuRT QHL example..."
	@if [ -z "$$HEXAGON_SDK_ROOT" ]; then \
		echo "Error: HEXAGON_SDK_ROOT is not set."; \
		echo "Please run: source /opt/Hexagon_SDK/6.4.0.2/setup_sdk_env.source"; \
		exit 1; \
	fi
	zig build

# Build with specific architecture
build-v73:
	zig build -Darch=v73

build-v75:
	zig build -Darch=v75

build-v68:
	zig build -Darch=v68

# Build optimized
build-release:
	zig build -Doptimize=ReleaseFast

# Run the example on QEMU
run:
	@echo "Running on QEMU..."
	@if [ -z "$$HEXAGON_SDK_ROOT" ]; then \
		echo "Error: HEXAGON_SDK_ROOT is not set."; \
		echo "Please run: source /opt/Hexagon_SDK/6.4.0.2/setup_sdk_env.source"; \
		exit 1; \
	fi
	zig build run

# Clean build artifacts
clean:
	rm -rf zig-out zig-cache .zig-cache

# Show help
help:
	@echo "Zig QuRT QHL Example - Build targets:"
	@echo ""
	@echo "  make              - Build the example (default)"
	@echo "  make build        - Build the example"
	@echo "  make build-v73    - Build for Hexagon v73"
	@echo "  make build-v75    - Build for Hexagon v75"
	@echo "  make build-v68    - Build for Hexagon v68"
	@echo "  make build-release - Build with optimizations"
	@echo "  make run          - Build and run on QEMU"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make help         - Show this help"
	@echo ""
	@echo "Prerequisites:"
	@echo "  source /opt/Hexagon_SDK/6.4.0.2/setup_sdk_env.source"
