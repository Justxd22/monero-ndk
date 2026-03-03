#!/bin/bash
# Shared configuration for all build scripts
# This is the single source of truth for pinned versions

# AOSP repositories
LLVM_URL="https://android.googlesource.com/toolchain/llvm-project"
LLVM_COMMIT="3b5e7c83a6e226d5bd7ed2e9b67449b64812074c"

LLVM_ANDROID_URL="https://android.googlesource.com/toolchain/llvm_android"
LLVM_ANDROID_COMMIT="e727bfb014bd436f581a66a450c939a6983a1fc3"

TOOLCHAIN_UTILS_URL="https://android.googlesource.com/platform/external/toolchain-utils"
TOOLCHAIN_UTILS_COMMIT="d71e320ab860721f764fe7403588641c8a7bc65d"

BIONIC_URL="https://android.googlesource.com/platform/bionic"
BIONIC_COMMIT="a63b21091ada240d92f8ceadb1cabbdedaaab81b"

PREBUILTS_NDK_URL="https://android.googlesource.com/platform/prebuilts/ndk"
PREBUILTS_NDK_COMMIT="c0815fea3a8081be6215440de330c63246e6551f"

# Build configuration
API_LEVEL="21"
SVN_REVISION="530567"

# Target architectures
ARCHES="aarch64 armv7a x86_64"

# LLVM backends
LLVM_TARGETS="AArch64;ARM;X86"

# Directories (relative to repo root)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="${ROOT_DIR}/sources"
BUILD_DIR="${ROOT_DIR}/build"
OUTPUT_DIR="${ROOT_DIR}/output"
SYSROOT_DIR="${OUTPUT_DIR}/sysroot"

# Host detection
NUM_CORES="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
