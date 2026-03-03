#!/bin/bash
# Phase 4: Cross-compile libc++ for each Android target architecture
# Uses our from-source clang + the assembled sysroot

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.sh"

SOURCES_DIR="${ROOT_DIR}/sources"
LLVM_SRC="${SOURCES_DIR}/llvm-project"
CLANG="${ROOT_DIR}/build/llvm-install/bin/clang"
CLANGXX="${ROOT_DIR}/build/llvm-install/bin/clang++"
SYSROOT_DIR="${ROOT_DIR}/output/sysroot"
LIBCXX_OUTPUT_DIR="${ROOT_DIR}/build/libcxx"

# Architecture to CMake target mapping
declare -A CMAKE_TARGET
CMAKE_TARGET[aarch64]="aarch64-linux-android${API_LEVEL}"
CMAKE_TARGET[armv7a]="armv7a-linux-androideabi${API_LEVEL}"
CMAKE_TARGET[x86_64]="x86_64-linux-android${API_LEVEL}"

# Architecture to LLVM arch name
declare -A LLVM_ARCH
LLVM_ARCH[aarch64]="AArch64"
LLVM_ARCH[armv7a]="ARM"
LLVM_ARCH[x86_64]="X86"

# Sysroot lib triple (arm uses different name)
declare -A SYSROOT_TRIPLE
SYSROOT_TRIPLE[aarch64]="aarch64-linux-android"
SYSROOT_TRIPLE[armv7a]="arm-linux-androideabi"
SYSROOT_TRIPLE[x86_64]="x86_64-linux-android"

if [ ! -x "$CLANG" ]; then
    echo "[ERROR] Clang not found at ${CLANG}"
    echo "        Run 'make llvm' first"
    exit 1
fi

echo "============================================"
echo "  Building libc++ for Android targets"
echo "============================================"
echo ""

for arch in ${ARCHES}; do
    target="${CMAKE_TARGET[$arch]}"
    triple="${SYSROOT_TRIPLE[$arch]}"
    build_dir="${LIBCXX_OUTPUT_DIR}/${arch}"
    install_dir="${LIBCXX_OUTPUT_DIR}/${arch}-install"

    # Skip if already built
    if [ -f "${install_dir}/lib/libc++_static.a" ]; then
        echo "[SKIP] libc++ for ${arch} already built"
        continue
    fi

    echo "[BUILD] libc++ for ${arch} (target: ${target})"
    echo ""

    rm -rf "$build_dir" "$install_dir"
    mkdir -p "$build_dir" "$install_dir"

    cmake -S "${LLVM_SRC}/runtimes" -B "$build_dir" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$install_dir" \
        -DCMAKE_C_COMPILER="$CLANG" \
        -DCMAKE_CXX_COMPILER="$CLANGXX" \
        -DCMAKE_C_COMPILER_TARGET="$target" \
        -DCMAKE_CXX_COMPILER_TARGET="$target" \
        -DCMAKE_ASM_COMPILER_TARGET="$target" \
        -DCMAKE_SYSROOT="$SYSROOT_DIR" \
        -DCMAKE_C_FLAGS="--target=${target}" \
        -DCMAKE_CXX_FLAGS="--target=${target}" \
        -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
        -DLIBCXX_ENABLE_SHARED=OFF \
        -DLIBCXX_ENABLE_STATIC=ON \
        -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=OFF \
        -DLIBCXX_INCLUDE_TESTS=OFF \
        -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
        -DLIBCXXABI_ENABLE_SHARED=OFF \
        -DLIBCXXABI_ENABLE_STATIC=ON \
        -DLIBCXXABI_INCLUDE_TESTS=OFF \
        -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
        -DANDROID=ON \
        -DANDROID_NATIVE_API_LEVEL="${API_LEVEL}"

    ninja -C "$build_dir" -j"${NUM_CORES}"
    ninja -C "$build_dir" install

    # Verify output
    if [ -f "${install_dir}/lib/libc++.a" ]; then
        # libc++ may install as libc++.a or libc++_static.a depending on config
        # Create the _static name if needed (that's what monero_c LDFLAGS expects)
        if [ ! -f "${install_dir}/lib/libc++_static.a" ]; then
            cp "${install_dir}/lib/libc++.a" "${install_dir}/lib/libc++_static.a"
        fi
    fi

    if [ -f "${install_dir}/lib/libc++_static.a" ] && [ -f "${install_dir}/lib/libc++abi.a" ]; then
        echo "[OK]    libc++ for ${arch}:"
        echo "        libc++_static.a: $(du -h "${install_dir}/lib/libc++_static.a" | cut -f1)"
        echo "        libc++abi.a:     $(du -h "${install_dir}/lib/libc++abi.a" | cut -f1)"
    else
        echo "[ERROR] libc++ build for ${arch} missing expected output"
        echo "        Contents of ${install_dir}/lib/:"
        ls -la "${install_dir}/lib/" 2>/dev/null || echo "        (empty)"
        exit 1
    fi

    echo ""
done

echo "============================================"
echo "  libc++ build complete for all architectures"
echo "============================================"
