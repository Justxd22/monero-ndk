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

# From-source sysroot dependencies (replaces prebuilts/ndk)
ARM_ROUTINES_URL="https://android.googlesource.com/platform/external/arm-optimized-routines"
ARM_ROUTINES_COMMIT="d7c644304e83c9bb92ede58c9c204d55f8157817"

SCUDO_URL="https://android.googlesource.com/platform/external/scudo"
SCUDO_COMMIT="1b55aeaa18248574e61a531a89439c20ee55379d"

GWP_ASAN_URL="https://android.googlesource.com/platform/external/gwp_asan"
GWP_ASAN_COMMIT="b302aa5039729da396909ef03e815160dab4448c"

SYSTEM_CORE_URL="https://android.googlesource.com/platform/system/core"
SYSTEM_CORE_COMMIT="a3b721a32242006b59cb12bd62c9133632af3a2d"

SYSTEM_LOGGING_URL="https://android.googlesource.com/platform/system/logging"
SYSTEM_LOGGING_COMMIT="bcac7c30d88a3773a7c0bc9f5617a23a886331fd"

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

# Detect available RAM in GB and calculate safe parallel link jobs
# Each LLVM link can consume ~10GB, so cap accordingly
if [ -f /proc/meminfo ]; then
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$(( TOTAL_RAM_KB / 1024 / 1024 ))
elif command -v sysctl &>/dev/null; then
    TOTAL_RAM_GB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 8589934592) / 1024 / 1024 / 1024 ))
else
    TOTAL_RAM_GB=8
fi

LLVM_LINK_JOBS=$(( TOTAL_RAM_GB / 10 ))
if [ "$LLVM_LINK_JOBS" -lt 1 ]; then
    LLVM_LINK_JOBS=1
fi

# Also cap build jobs to leave headroom: use nproc but no more than RAM/2GB
MAX_JOBS_BY_RAM=$(( TOTAL_RAM_GB / 2 ))
if [ "$MAX_JOBS_BY_RAM" -lt 1 ]; then
    MAX_JOBS_BY_RAM=1
fi
if [ "$NUM_CORES" -gt "$MAX_JOBS_BY_RAM" ]; then
    BUILD_JOBS="$MAX_JOBS_BY_RAM"
else
    BUILD_JOBS="$NUM_CORES"
fi
