include config.mk

.PHONY: all full fetch llvm sysroot runtimes assemble verify clean

# Build everything from already-present sources (no network).
# Sources must already exist under $(SOURCES_DIR)
all: llvm sysroot runtimes assemble verify

# Convenience target for standalone builds: fetch sources then build.
full: fetch all

fetch:
	@echo "=== Phase 1: Fetching sources ==="
	bash scripts/01-fetch-sources.sh

llvm:
	@echo "=== Phase 2: Building LLVM/Clang ==="
	bash scripts/02-build-llvm.sh

sysroot: llvm
	@echo "=== Phase 3: Building sysroot from source ==="
	bash scripts/03-build-sysroot.sh

runtimes: llvm sysroot
	@echo "=== Phase 4: Building runtimes ==="
	bash scripts/04-build-runtimes.sh

assemble: llvm sysroot runtimes
	@echo "=== Phase 5: Assembling NDK ==="
	bash scripts/05-assemble-ndk.sh

verify: assemble
	@echo "=== Phase 6: Verifying output ==="
	bash scripts/06-verify.sh

clean:
	rm -rf $(BUILD_DIR) $(OUTPUT_DIR)

distclean: clean
	rm -rf $(SOURCES_DIR)

# Print configuration
info:
	@bash -c 'source config.sh && echo "LLVM commit:      $$LLVM_COMMIT" && echo "Bionic commit:    $$BIONIC_COMMIT" && echo "API level:        $$API_LEVEL" && echo "Architectures:    $$ARCHES" && echo "Cores:            $$NUM_CORES" && echo "RAM:              $${TOTAL_RAM_GB} GB" && echo "Build jobs:       $$BUILD_JOBS" && echo "Link jobs:        $$LLVM_LINK_JOBS" && echo "Sources dir:      $$SOURCES_DIR" && echo "Build dir:        $$BUILD_DIR" && echo "Output dir:       $$OUTPUT_DIR"'
