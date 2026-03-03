#!/bin/bash
# Phase 4: Cross-compile LLVM runtimes for each Android target architecture
# Builds: compiler-rt builtins, libunwind, libc++abi, libc++
# Uses our from-source clang + the assembled sysroot

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.sh"

SOURCES_DIR="${ROOT_DIR}/sources"
LLVM_SRC="${SOURCES_DIR}/llvm-project"
LLVM_INSTALL="${ROOT_DIR}/build/llvm-install"
CLANG="${LLVM_INSTALL}/bin/clang"
CLANGXX="${LLVM_INSTALL}/bin/clang++"
SYSROOT_DIR="${ROOT_DIR}/output/sysroot"
RUNTIMES_OUTPUT_DIR="${ROOT_DIR}/build/runtimes"

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

# compiler-rt arch name (used in output filenames)
declare -A RT_ARCH
RT_ARCH[aarch64]="aarch64"
RT_ARCH[armv7a]="arm"
RT_ARCH[x86_64]="x86_64"

if [ ! -x "$CLANG" ]; then
    echo "[ERROR] Clang not found at ${CLANG}"
    echo "        Run 'make llvm' first"
    exit 1
fi

# Get clang resource dir (where compiler-rt builtins go)
CLANG_VERSION=$("$CLANG" --version | head -1 | grep -oP '\d+' | head -1)
CLANG_RESOURCE_DIR="${LLVM_INSTALL}/lib/clang/${CLANG_VERSION}"

echo "============================================"
echo "  Building LLVM runtimes for Android targets"
echo "  (compiler-rt, libunwind, libc++abi, libc++)"
echo "============================================"
echo ""
echo "Clang version:    ${CLANG_VERSION}"
echo "Resource dir:     ${CLANG_RESOURCE_DIR}"
echo ""

for arch in ${ARCHES}; do
    target="${CMAKE_TARGET[$arch]}"
    triple="${SYSROOT_TRIPLE[$arch]}"
    rt_arch="${RT_ARCH[$arch]}"
    build_dir="${RUNTIMES_OUTPUT_DIR}/${arch}"
    install_dir="${RUNTIMES_OUTPUT_DIR}/${arch}-install"

    # Skip if already built
    if [ -f "${install_dir}/lib/libc++_static.a" ] || [ -f "${install_dir}/lib/libc++.a" ]; then
        # Also check for compiler-rt builtins
        if [ -f "${CLANG_RESOURCE_DIR}/lib/linux/libclang_rt.builtins-${rt_arch}-android.a" ]; then
            echo "[SKIP] Runtimes for ${arch} already built"
            continue
        fi
    fi

    echo "==========================================="
    echo "[BUILD] Runtimes for ${arch} (target: ${target})"
    echo "==========================================="
    echo ""

    rm -rf "$build_dir" "$install_dir"
    mkdir -p "$build_dir" "$install_dir"

    # ---- Step 1: Build compiler-rt builtins ----
    # These must be built FIRST because libunwind/libc++ link against them
    echo "[1/2] Building compiler-rt builtins for ${arch}..."

    builtins_build="${build_dir}/builtins"
    builtins_install="${build_dir}/builtins-install"
    mkdir -p "$builtins_build"

    cmake -S "${LLVM_SRC}/compiler-rt/lib/builtins" -B "$builtins_build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$builtins_install" \
        -DCMAKE_C_COMPILER="$CLANG" \
        -DCMAKE_CXX_COMPILER="$CLANGXX" \
        -DCMAKE_C_COMPILER_TARGET="$target" \
        -DCMAKE_CXX_COMPILER_TARGET="$target" \
        -DCMAKE_ASM_COMPILER_TARGET="$target" \
        -DCMAKE_SYSROOT="$SYSROOT_DIR" \
        -DCMAKE_C_FLAGS="--target=${target}" \
        -DCMAKE_CXX_FLAGS="--target=${target}" \
        -DCMAKE_ASM_FLAGS="--target=${target}" \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
        -DCOMPILER_RT_BUILD_BUILTINS=ON \
        -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
        -DCOMPILER_RT_BUILD_XRAY=OFF \
        -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
        -DCOMPILER_RT_BUILD_PROFILE=OFF \
        -DCOMPILER_RT_BUILD_MEMPROF=OFF \
        -DCOMPILER_RT_BUILD_ORC=OFF \
        -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
        -DCOMPILER_RT_BAREMETAL_BUILD=OFF \
        -DANDROID=ON

    ninja -C "$builtins_build" -j"${BUILD_JOBS}"

    # Install builtins into clang resource dir so clang can find them
    mkdir -p "${CLANG_RESOURCE_DIR}/lib/linux"

    # Find the built builtins lib (name varies by arch)
    builtins_lib=$(find "$builtins_build" -name "libclang_rt.builtins*.a" | head -1)
    if [ -n "$builtins_lib" ]; then
        cp "$builtins_lib" "${CLANG_RESOURCE_DIR}/lib/linux/libclang_rt.builtins-${rt_arch}-android.a"
        echo "[OK]    compiler-rt builtins: $(basename "$builtins_lib") → libclang_rt.builtins-${rt_arch}-android.a"
    else
        echo "[WARN]  No builtins library found, checking build output..."
        find "$builtins_build" -name "*.a" | head -10
    fi

    echo ""

    # ---- Step 2: Build libunwind + libc++abi + libc++ ----
    echo "[2/2] Building libunwind + libc++abi + libc++ for ${arch}..."

    cmake -S "${LLVM_SRC}/runtimes" -B "$build_dir/runtimes" -G Ninja \
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
        -DCMAKE_ASM_FLAGS="--target=${target}" \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
        -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
        -DLIBUNWIND_ENABLE_SHARED=OFF \
        -DLIBUNWIND_ENABLE_STATIC=ON \
        -DLIBUNWIND_INCLUDE_TESTS=OFF \
        -DLIBUNWIND_USE_COMPILER_RT=ON \
        -DLIBCXX_ENABLE_SHARED=OFF \
        -DLIBCXX_ENABLE_STATIC=ON \
        -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=OFF \
        -DLIBCXX_INCLUDE_TESTS=OFF \
        -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
        -DLIBCXX_USE_COMPILER_RT=ON \
        -DLIBCXXABI_ENABLE_SHARED=OFF \
        -DLIBCXXABI_ENABLE_STATIC=ON \
        -DLIBCXXABI_INCLUDE_TESTS=OFF \
        -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
        -DLIBCXXABI_USE_COMPILER_RT=ON \
        -DANDROID=ON \
        -DANDROID_NATIVE_API_LEVEL="${API_LEVEL}"

    ninja -C "$build_dir/runtimes" -j"${BUILD_JOBS}"
    ninja -C "$build_dir/runtimes" install

    # Also install libunwind into clang resource dir
    # (clang looks for it as -l:libunwind.a in the resource dir)
    unwind_lib=$(find "$install_dir" -name "libunwind.a" | head -1)
    if [ -n "$unwind_lib" ]; then
        cp "$unwind_lib" "${CLANG_RESOURCE_DIR}/lib/linux/libunwind-${rt_arch}-android.a"
        # Also put as libunwind.a in the sysroot lib dir so the linker can find it
        cp "$unwind_lib" "${SYSROOT_DIR}/usr/lib/${triple}/libunwind.a"
        echo "[OK]    libunwind installed for ${arch}"
    fi

    # Verify output — create libc++_static.a alias if needed
    if [ -f "${install_dir}/lib/libc++.a" ]; then
        if [ ! -f "${install_dir}/lib/libc++_static.a" ]; then
            cp "${install_dir}/lib/libc++.a" "${install_dir}/lib/libc++_static.a"
        fi
    fi

    echo ""
    echo "[VERIFY] Runtimes for ${arch}:"
    if [ -f "${install_dir}/lib/libc++_static.a" ] || [ -f "${install_dir}/lib/libc++.a" ]; then
        echo "        libc++:     $(du -h "${install_dir}/lib/libc++_static.a" 2>/dev/null || du -h "${install_dir}/lib/libc++.a" | cut -f1)"
    fi
    if [ -f "${install_dir}/lib/libc++abi.a" ]; then
        echo "        libc++abi:  $(du -h "${install_dir}/lib/libc++abi.a" | cut -f1)"
    fi
    if [ -f "${install_dir}/lib/libunwind.a" ]; then
        echo "        libunwind:  $(du -h "${install_dir}/lib/libunwind.a" | cut -f1)"
    fi
    builtins_installed="${CLANG_RESOURCE_DIR}/lib/linux/libclang_rt.builtins-${rt_arch}-android.a"
    if [ -f "$builtins_installed" ]; then
        echo "        builtins:   $(du -h "$builtins_installed" | cut -f1)"
    fi
    echo ""
done

echo "============================================"
echo "  All runtimes built successfully"
echo "============================================"
