#!/bin/bash
# Phase 3b: Compile CRT (C Runtime) objects from bionic source
# These are the startup/shutdown objects linked into every Android binary.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.sh"

BIONIC_SRC="${SOURCES_DIR}/bionic"
SYSROOT_DIR="${OUTPUT_DIR}/sysroot"
LLVM_BIN="${BUILD_DIR}/llvm-install/bin"
CRT_BUILD_DIR="${BUILD_DIR}/crt"

CC="${LLVM_BIN}/clang"

# Architecture mapping
declare -A SYSROOT_TRIPLE
SYSROOT_TRIPLE[aarch64]="aarch64-linux-android"
SYSROOT_TRIPLE[armv7a]="arm-linux-androideabi"
SYSROOT_TRIPLE[x86_64]="x86_64-linux-android"

declare -A CLANG_TARGET
CLANG_TARGET[aarch64]="aarch64-linux-android${API_LEVEL}"
CLANG_TARGET[armv7a]="armv7a-linux-androideabi${API_LEVEL}"
CLANG_TARGET[x86_64]="x86_64-linux-android${API_LEVEL}"

# Source paths
CRT_COMMON="${BIONIC_SRC}/libc/arch-common/bionic"

echo "============================================"
echo "  Compiling CRT objects from bionic source"
echo "============================================"
echo ""

# Common include directories
COMMON_INCLUDES=(
    -I "${BIONIC_SRC}/libc/include"
    -I "${BIONIC_SRC}/libc/kernel/uapi"
    -I "${BIONIC_SRC}/libc/kernel/android/uapi"
    -I "${BIONIC_SRC}/libc/private"
    -I "${BIONIC_SRC}/libc/bionic"
    -I "${BIONIC_SRC}/libc/arch-common/bionic"
    -I "${BIONIC_SRC}/libc"
)

for arch in ${ARCHES}; do
    triple="${SYSROOT_TRIPLE[$arch]}"
    target="${CLANG_TARGET[$arch]}"
    api_lib_dir="${SYSROOT_DIR}/usr/lib/${triple}/${API_LEVEL}"
    arch_build_dir="${CRT_BUILD_DIR}/${arch}"

    mkdir -p "$api_lib_dir"
    mkdir -p "$arch_build_dir"

    echo "[CRT] Building for ${triple}..."

    # Arch-specific include directory
    ARCH_INCLUDES=("${COMMON_INCLUDES[@]}")

    # Map arch to bionic arch directory name
    local_arch_dir=""
    case "$arch" in
        aarch64) local_arch_dir="arch-arm64" ;;
        armv7a)  local_arch_dir="arch-arm" ;;
        x86_64)  local_arch_dir="arch-x86_64" ;;
    esac
    ARCH_INCLUDES+=(-I "${BIONIC_SRC}/libc/${local_arch_dir}/include")
    # Also add the sysroot's triple-specific include dir (contains asm/ headers)
    ARCH_INCLUDES+=(-I "${SYSROOT_DIR}/usr/include/${triple}")

    # Common compiler flags
    # Note: --target=<triple><api> already defines __ANDROID_API__, so we don't
    # set it again to avoid a macro redefinition warning.
    COMMON_FLAGS=(
        --target="$target"
        -D_LIBC=1
        -DPLATFORM_SDK_VERSION=${API_LEVEL}
        -DANDROID
        -D__ANDROID__
        "${ARCH_INCLUDES[@]}"
        -fno-builtin
        -fPIC
        -O2
        -Wall
        -Werror=return-type
        -Wno-unused-function
    )

    # Step 1: Compile crtbrand.S → crtbrand.o (intermediate)
    echo "        Building crtbrand.o..."
    "${CC}" "${COMMON_FLAGS[@]}" \
        -c "${CRT_COMMON}/crtbrand.S" \
        -o "${arch_build_dir}/crtbrand.o"

    # Step 2: Compile crtbegin_so.c → crtbegin_so.o
    # crtbegin_so.c includes __dso_handle_so.h, atexit.h, pthread_atfork.h
    echo "        Building crtbegin_so.o..."
    "${CC}" "${COMMON_FLAGS[@]}" \
        -c "${CRT_COMMON}/crtbegin_so.c" \
        -o "${arch_build_dir}/crtbegin_so_src.o"

    # Link crtbegin_so with crtbrand to produce final crtbegin_so.o
    "${LLVM_BIN}/ld.lld" -r \
        "${arch_build_dir}/crtbegin_so_src.o" \
        "${arch_build_dir}/crtbrand.o" \
        -o "${api_lib_dir}/crtbegin_so.o"
    echo "        [OK] crtbegin_so.o"

    # Step 3: Compile crtend_so.S → crtend_so.o
    echo "        Building crtend_so.o..."
    "${CC}" "${COMMON_FLAGS[@]}" \
        -c "${CRT_COMMON}/crtend_so.S" \
        -o "${api_lib_dir}/crtend_so.o"
    echo "        [OK] crtend_so.o"

    # Step 4: Compile crtbegin.c → crtbegin_dynamic.o
    # crtbegin.c includes libc_init_common.h, __dso_handle.h, atexit.h, pthread_atfork.h
    echo "        Building crtbegin_dynamic.o..."
    "${CC}" "${COMMON_FLAGS[@]}" \
        -c "${CRT_COMMON}/crtbegin.c" \
        -o "${arch_build_dir}/crtbegin_src.o"

    # Link with crtbrand
    "${LLVM_BIN}/ld.lld" -r \
        "${arch_build_dir}/crtbegin_src.o" \
        "${arch_build_dir}/crtbrand.o" \
        -o "${api_lib_dir}/crtbegin_dynamic.o"
    echo "        [OK] crtbegin_dynamic.o"

    # Step 5: Compile crtend.S → crtend_android.o
    echo "        Building crtend_android.o..."
    "${CC}" "${COMMON_FLAGS[@]}" \
        -c "${CRT_COMMON}/crtend.S" \
        -o "${api_lib_dir}/crtend_android.o"
    echo "        [OK] crtend_android.o"

    # Step 6: Compile crt_pad_segment.S → crt_pad_segment.o
    echo "        Building crt_pad_segment.o..."
    "${CC}" "${COMMON_FLAGS[@]}" \
        -c "${CRT_COMMON}/crt_pad_segment.S" \
        -o "${api_lib_dir}/crt_pad_segment.o"
    echo "        [OK] crt_pad_segment.o"

    echo "        All CRT objects built for ${triple}"
    echo ""
done

echo "[CRT] All CRT objects compiled successfully"
