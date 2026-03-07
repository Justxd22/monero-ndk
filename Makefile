include config.mk

.PHONY: all fetch llvm sysroot runtimes assemble verify clean

all: fetch llvm sysroot runtimes assemble verify

fetch:
	@echo "=== Phase 1: Fetching sources ==="
	bash scripts/01-fetch-sources.sh

llvm: fetch
	@echo "=== Phase 2: Building LLVM/Clang ==="
	bash scripts/02-build-llvm.sh

sysroot: fetch llvm
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
