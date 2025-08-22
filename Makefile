.PHONY: build clean test install

# Platform detection
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Determine the correct binary name based on platform
ifeq ($(UNAME_S),Linux)
    ifeq ($(UNAME_M),x86_64)
        BINARY_NAME = ndmgr-linux-x86_64
    else
        BINARY_NAME = ndmgr-linux-$(UNAME_M)
    endif
endif

ifeq ($(UNAME_S),Darwin)
    ifeq ($(UNAME_M),x86_64)
        BINARY_NAME = ndmgr-macos-x86_64
    else ifeq ($(UNAME_M),arm64)
        BINARY_NAME = ndmgr-macos-aarch64
    else
        BINARY_NAME = ndmgr-macos-$(UNAME_M)
    endif
endif

# Fallback if platform detection fails
ifndef BINARY_NAME
    BINARY_NAME = ndmgr
endif

build:
	zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe
	mv zig-out/bin/ndmgr zig-out/bin/ndmgr-macos-x86_64
	zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe
	mv zig-out/bin/ndmgr zig-out/bin/ndmgr-macos-aarch64
	zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe
	strip zig-out/bin/ndmgr
	cp zig-out/bin/ndmgr zig-out/bin/ndmgr-linux-x86_64

clean:
	rm -rf zig-out zig-cache .zig-cache

test:
	zig build test --summary all

install:
	@echo "Installing ndmgr for $(UNAME_S) $(UNAME_M)..."
	@echo "Looking for binary: zig-out/bin/$(BINARY_NAME)"
	@if [ ! -f "zig-out/bin/$(BINARY_NAME)" ]; then \
		echo "Error: Binary zig-out/bin/$(BINARY_NAME) not found!"; \
		echo "Please run 'make build' first."; \
		exit 1; \
	fi
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "Error: Installation requires root privileges."; \
		echo "Please run: sudo make install"; \
		exit 1; \
	fi
	cp zig-out/bin/$(BINARY_NAME) /usr/bin/ndmgr
	chmod +x /usr/bin/ndmgr
	@if [ ! -f "man/ndmgr.1" ]; then \
		echo "Warning: Man page ndmgr.1 not found, skipping man page installation."; \
	else \
		mkdir -p /usr/local/share/man/man1; \
		cp man/ndmgr.1 /usr/local/share/man/man1/; \
		chmod 644 /usr/local/share/man/man1/ndmgr.1; \
		echo "Man page installed to /usr/local/share/man/man1/ndmgr.1"; \
	fi
	@echo "ndmgr installed successfully to /usr/bin/ndmgr"
	@echo "You can now run 'ndmgr' from anywhere."
	@echo "View the manual with: man ndmgr"
