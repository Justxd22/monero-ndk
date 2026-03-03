include config.mk

.PHONY: all fetch llvm sysroot libcxx assemble verify clean

all: fetch llvm sysroot libcxx assemble verify

fetch:
	@echo "=== Phase 1: Fetching sources ==="
	bash scripts/01-fetch-sources.sh

llvm: fetch
	@echo "=== Phase 2: Building LLVM/Clang ==="
	bash scripts/02-build-llvm.sh

sysroot: fetch
	@echo "=== Phase 3: Assembling sysroot ==="
	bash scripts/03-build-sysroot.sh

libcxx: llvm sysroot
	@echo "=== Phase 4: Building libc++ ==="
	bash scripts/04-build-libcxx.sh

assemble: llvm sysroot libcxx
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
	@echo "LLVM commit:      $(LLVM_COMMIT)"
	@echo "Bionic commit:    $(BIONIC_COMMIT)"
	@echo "API level:        $(API_LEVEL)"
	@echo "Architectures:    $(ARCHES)"
	@echo "Host:             $(HOST_OS)-$(HOST_ARCH)"
	@echo "Cores:            $(NUM_CORES)"
	@echo "Sources dir:      $(SOURCES_DIR)"
	@echo "Build dir:        $(BUILD_DIR)"
	@echo "Output dir:       $(OUTPUT_DIR)"
