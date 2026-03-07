# Pinned versions and commit hashes
# All sources are fetched at exact commits for reproducibility

# AOSP repositories
LLVM_URL            := https://android.googlesource.com/toolchain/llvm-project
LLVM_COMMIT         := 3b5e7c83a6e226d5bd7ed2e9b67449b64812074c

LLVM_ANDROID_URL    := https://android.googlesource.com/toolchain/llvm_android
LLVM_ANDROID_COMMIT := e727bfb014bd436f581a66a450c939a6983a1fc3

TOOLCHAIN_UTILS_URL    := https://android.googlesource.com/platform/external/toolchain-utils
TOOLCHAIN_UTILS_COMMIT := d71e320ab860721f764fe7403588641c8a7bc65d

BIONIC_URL          := https://android.googlesource.com/platform/bionic
BIONIC_COMMIT       := a63b21091ada240d92f8ceadb1cabbdedaaab81b

# From-source sysroot dependencies (replaces prebuilts/ndk)
ARM_ROUTINES_URL    := https://android.googlesource.com/platform/external/arm-optimized-routines
ARM_ROUTINES_COMMIT := d7c644304e83c9bb92ede58c9c204d55f8157817

SCUDO_URL           := https://android.googlesource.com/platform/external/scudo
SCUDO_COMMIT        := 1b55aeaa18248574e61a531a89439c20ee55379d

GWP_ASAN_URL        := https://android.googlesource.com/platform/external/gwp_asan
GWP_ASAN_COMMIT     := b302aa5039729da396909ef03e815160dab4448c

SYSTEM_CORE_URL     := https://android.googlesource.com/platform/system/core
SYSTEM_CORE_COMMIT  := a3b721a32242006b59cb12bd62c9133632af3a2d

SYSTEM_LOGGING_URL     := https://android.googlesource.com/platform/system/logging
SYSTEM_LOGGING_COMMIT  := bcac7c30d88a3773a7c0bc9f5617a23a886331fd

# Build configuration
API_LEVEL           := 21
SVN_REVISION        := 530567

# Target architectures
ARCHES              := aarch64 armv7a x86_64

# Target triplets
TRIPLE_aarch64      := aarch64-linux-android
TRIPLE_armv7a       := armv7a-linux-androideabi
TRIPLE_x86_64       := x86_64-linux-android

# LLVM backends needed
LLVM_TARGETS        := AArch64;ARM;X86

# Directories
SOURCES_DIR         := $(CURDIR)/sources
BUILD_DIR           := $(CURDIR)/build
OUTPUT_DIR          := $(CURDIR)/output
SYSROOT_DIR         := $(OUTPUT_DIR)/sysroot

# Host detection
HOST_OS             := $(shell uname -s | tr A-Z a-z)
HOST_ARCH           := $(shell uname -m)
NUM_CORES           := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
