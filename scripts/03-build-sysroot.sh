#!/bin/bash
# Phase 3: Build the bionic sysroot entirely from source
# Replaces the old approach of copying from prebuilts/ndk.
#
# This script:
#   1. Copies headers from bionic source
#   2. Calls 03a-generate-stubs.sh — generates .so linker stubs from .map.txt files
#   3. Calls 03b-build-crt.sh — compiles CRT objects from bionic source
#   4. Creates minimal static library stubs (libdl.a, libm.a, libc.a, libstdc++.a)
#
# The .so stubs contain the correct exported symbols so the linker can resolve
# references. The real implementations live on the Android device in /system/lib{64}/.
# The .a static libs are minimal stubs — downstream projects (monero_c) link
# dynamically against libc/libm/libdl at runtime.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.sh"

BIONIC_SRC="${SOURCES_DIR}/bionic"
SYSROOT_DIR="${OUTPUT_DIR}/sysroot"
LLVM_BIN="${BUILD_DIR}/llvm-install/bin"

# Architecture mapping for sysroot lib directories
declare -A SYSROOT_TRIPLE
SYSROOT_TRIPLE[aarch64]="aarch64-linux-android"
SYSROOT_TRIPLE[armv7a]="arm-linux-androideabi"
SYSROOT_TRIPLE[x86_64]="x86_64-linux-android"

declare -A CLANG_TARGET
CLANG_TARGET[aarch64]="aarch64-linux-android${API_LEVEL}"
CLANG_TARGET[armv7a]="armv7a-linux-androideabi${API_LEVEL}"
CLANG_TARGET[x86_64]="x86_64-linux-android${API_LEVEL}"

# Skip if already built
if [ -f "${SYSROOT_DIR}/.sysroot_complete" ]; then
    echo "[SKIP] Sysroot already assembled at ${SYSROOT_DIR}"
    exit 0
fi

echo "============================================"
echo "  Building bionic sysroot from source"
echo "============================================"
echo ""

# Verify prerequisites
if [ ! -x "${LLVM_BIN}/clang" ]; then
    echo "[ERROR] LLVM/Clang not found at ${LLVM_BIN}/clang"
    echo "        Run 'make llvm' first."
    exit 1
fi

if [ ! -d "${BIONIC_SRC}" ]; then
    echo "[ERROR] Bionic source not found at ${BIONIC_SRC}"
    echo "        Run 'make fetch' first."
    exit 1
fi

# Clean and create output
rm -rf "${SYSROOT_DIR}"
mkdir -p "${SYSROOT_DIR}/usr/include"
mkdir -p "${SYSROOT_DIR}/usr/lib"

# ==== Step 1: Copy headers from bionic source ====
echo "[HEADERS] Copying C headers from bionic source..."

# Copy main libc headers
if [ -d "${BIONIC_SRC}/libc/include" ]; then
    cp -a "${BIONIC_SRC}/libc/include/"* "${SYSROOT_DIR}/usr/include/"
    echo "        [OK] libc/include headers"
fi

# Kernel UAPI headers
if [ -d "${BIONIC_SRC}/libc/kernel/uapi" ]; then
    cp -a "${BIONIC_SRC}/libc/kernel/uapi/"* "${SYSROOT_DIR}/usr/include/"
    echo "        [OK] kernel/uapi headers"
fi

# Kernel android UAPI headers
if [ -d "${BIONIC_SRC}/libc/kernel/android/uapi" ]; then
    cp -a "${BIONIC_SRC}/libc/kernel/android/uapi/"* "${SYSROOT_DIR}/usr/include/"
    echo "        [OK] kernel/android/uapi headers"
fi

# Arch-specific headers
# Map our arch names to bionic's kernel UAPI asm directory names
declare -A BIONIC_ASM_DIR
BIONIC_ASM_DIR[aarch64]="asm-arm64"
BIONIC_ASM_DIR[armv7a]="asm-arm"
BIONIC_ASM_DIR[x86_64]="asm-x86"

for arch in ${ARCHES}; do
    triple="${SYSROOT_TRIPLE[$arch]}"
    bionic_asm="${BIONIC_ASM_DIR[$arch]}"

    # Map arch to bionic arch directory name
    bionic_arch_dir=""
    case "$arch" in
        aarch64) bionic_arch_dir="arch-arm64" ;;
        armv7a)  bionic_arch_dir="arch-arm" ;;
        x86_64)  bionic_arch_dir="arch-x86_64" ;;
    esac

    mkdir -p "${SYSROOT_DIR}/usr/include/${triple}"

    # Copy arch-specific libc headers (if they exist — modern bionic may not have these)
    if [ -d "${BIONIC_SRC}/libc/${bionic_arch_dir}/include" ]; then
        cp -a "${BIONIC_SRC}/libc/${bionic_arch_dir}/include/"* \
            "${SYSROOT_DIR}/usr/include/${triple}/"
        echo "        [OK] Arch headers: ${triple}"
    fi

    # Copy arch-specific kernel UAPI asm headers
    # These contain <asm/types.h>, <asm/ioctl.h>, etc. needed by compiler-rt and libc
    # bionic names: asm-arm64, asm-arm, asm-x86 (NOT asm-aarch64/asm-armv7a/asm-x86_64)
    if [ -d "${BIONIC_SRC}/libc/kernel/uapi/${bionic_asm}/asm" ]; then
        mkdir -p "${SYSROOT_DIR}/usr/include/${triple}/asm"
        cp -a "${BIONIC_SRC}/libc/kernel/uapi/${bionic_asm}/asm/"* \
            "${SYSROOT_DIR}/usr/include/${triple}/asm/"
        echo "        [OK] Kernel asm headers: ${triple}/asm/ (from ${bionic_asm})"
    else
        echo "        [WARN] Missing kernel asm headers: ${bionic_asm}"
    fi
done

# Copy liblog headers from system/logging if available
LOGGING_SRC="${SOURCES_DIR}/system-logging"
if [ -d "${LOGGING_SRC}/liblog/include" ]; then
    cp -a "${LOGGING_SRC}/liblog/include/"* "${SYSROOT_DIR}/usr/include/" 2>/dev/null || true
    echo "        [OK] liblog headers from system/logging"
fi

# Copy system/core headers (android_filesystem_config.h etc.)
SYSTEM_CORE_SRC="${SOURCES_DIR}/system-core"
if [ -d "${SYSTEM_CORE_SRC}/libcutils/include" ]; then
    cp -a "${SYSTEM_CORE_SRC}/libcutils/include/"* "${SYSROOT_DIR}/usr/include/" 2>/dev/null || true
    echo "        [OK] system/core headers"
fi

echo "        Total headers: $(find "${SYSROOT_DIR}/usr/include" -type f | wc -l) files"

# ==== Step 2: Generate .so stub libraries ====
echo ""
echo "[STUBS] Generating .so stub libraries from map files..."
bash "${SCRIPT_DIR}/03a-generate-stubs.sh"

# ==== Step 3: Compile CRT objects ====
echo ""
echo "[CRT] Compiling CRT objects from bionic source..."
bash "${SCRIPT_DIR}/03b-build-crt.sh"

# ==== Step 4: Build real static libraries ====
echo ""
echo "[STATIC] Building static libraries from source..."

# Build libm.a from FreeBSD/NetBSD math sources
bash "${SCRIPT_DIR}/03c-build-libm.sh"

# Build libc.a from map-file stubs (provides symbol resolution for cross-compilation)
bash "${SCRIPT_DIR}/03d-build-libc.sh"

# Build remaining minimal stubs for libdl.a and libstdc++.a
echo ""
echo "[STATIC] Building libdl.a and libstdc++.a stubs..."

for arch in ${ARCHES}; do
    triple="${SYSROOT_TRIPLE[$arch]}"
    target="${CLANG_TARGET[$arch]}"
    lib_dir="${SYSROOT_DIR}/usr/lib/${triple}"

    mkdir -p "$lib_dir"

    stub_dir="${BUILD_DIR}/static-stubs/${arch}"
    mkdir -p "$stub_dir"

    # Create minimal libdl.a
    cat > "${stub_dir}/libdl_stub.c" <<'EOF'
// Minimal libdl.a stub
void* dlopen(const char* filename, int flag) { return 0; }
void* dlsym(void* handle, const char* symbol) { return 0; }
int dlclose(void* handle) { return 0; }
char* dlerror(void) { return 0; }
int dladdr(const void* addr, void* info) { return 0; }
EOF

    "${LLVM_BIN}/clang" --target="$target" -c -fPIC -O2 \
        "${stub_dir}/libdl_stub.c" -o "${stub_dir}/libdl_stub.o"
    "${LLVM_BIN}/llvm-ar" rcs "${lib_dir}/libdl.a" "${stub_dir}/libdl_stub.o"
    echo "        [OK] ${triple}/libdl.a"

    # Create minimal libstdc++.a stub
    cat > "${stub_dir}/libstdcpp_stub.c" <<'EOF'
// Minimal libstdc++.a stub — C++ support comes from libc++ instead
EOF

    "${LLVM_BIN}/clang" --target="$target" -c -fPIC -O2 \
        "${stub_dir}/libstdcpp_stub.c" -o "${stub_dir}/libstdcpp_stub.o"
    "${LLVM_BIN}/llvm-ar" rcs "${lib_dir}/libstdc++.a" "${stub_dir}/libstdcpp_stub.o"
    echo "        [OK] ${triple}/libstdc++.a"

done

# ==== Step 5: Mark complete ====
touch "${SYSROOT_DIR}/.sysroot_complete"

echo ""
echo "============================================"
echo "  Sysroot build complete (from source)"
echo "============================================"
echo ""
echo "Layout:"
echo "  ${SYSROOT_DIR}/"
find "${SYSROOT_DIR}" -maxdepth 4 -type d | sort | head -30
echo ""
du -sh "${SYSROOT_DIR}"
