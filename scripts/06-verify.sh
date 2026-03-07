#!/bin/bash
# Phase 6: Verify the assembled NDK
# Checks that all required files exist and test-compiles simple programs

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.sh"

OUTPUT_DIR="${ROOT_DIR}/output"
TEST_DIR="${ROOT_DIR}/test"
PASS=0
FAIL=0

check() {
    local desc="$1"
    local path="$2"

    if [ -e "$path" ]; then
        echo "  [PASS] ${desc}"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] ${desc} — missing: ${path}"
        FAIL=$((FAIL + 1))
    fi
}

check_exec() {
    local desc="$1"
    local path="$2"

    if [ -x "$path" ]; then
        echo "  [PASS] ${desc}"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] ${desc} — not executable: ${path}"
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================"
echo "  Verifying NDK output"
echo "============================================"
echo ""

# ---- Check 1: Core binaries ----
echo "--- Core binaries ---"
check_exec "clang" "${OUTPUT_DIR}/bin/clang"
check_exec "clang++" "${OUTPUT_DIR}/bin/clang++"
check_exec "lld" "${OUTPUT_DIR}/bin/lld"
check_exec "ld.lld" "${OUTPUT_DIR}/bin/ld.lld"
check_exec "llvm-ar" "${OUTPUT_DIR}/bin/llvm-ar"
check_exec "llvm-ranlib" "${OUTPUT_DIR}/bin/llvm-ranlib"
check_exec "llvm-strip" "${OUTPUT_DIR}/bin/llvm-strip"
check_exec "llvm-nm" "${OUTPUT_DIR}/bin/llvm-nm"
check_exec "llvm-as" "${OUTPUT_DIR}/bin/llvm-as"

# ---- Check 2: Symlinks ----
echo ""
echo "--- Convenience symlinks ---"
check "ar -> llvm-ar" "${OUTPUT_DIR}/bin/ar"
check "ranlib -> llvm-ranlib" "${OUTPUT_DIR}/bin/ranlib"

# ---- Check 3: Target wrappers ----
echo ""
echo "--- Target wrappers ---"

declare -A WRAPPER_TRIPLE
WRAPPER_TRIPLE[aarch64]="aarch64-linux-android"
WRAPPER_TRIPLE[armv7a]="armv7a-linux-androideabi"
WRAPPER_TRIPLE[x86_64]="x86_64-linux-android"

for arch in ${ARCHES}; do
    triple="${WRAPPER_TRIPLE[$arch]}"
    check_exec "${triple}${API_LEVEL}-clang" "${OUTPUT_DIR}/bin/${triple}${API_LEVEL}-clang"
    check_exec "${triple}${API_LEVEL}-clang++" "${OUTPUT_DIR}/bin/${triple}${API_LEVEL}-clang++"
    check_exec "${triple}-ar" "${OUTPUT_DIR}/bin/${triple}-ar"
    check_exec "${triple}-ranlib" "${OUTPUT_DIR}/bin/${triple}-ranlib"
done

# ---- Check 4: Metadata ----
echo ""
echo "--- Metadata ---"
check "AndroidVersion.txt" "${OUTPUT_DIR}/AndroidVersion.txt"

# ---- Check 5: Sysroot headers ----
echo ""
echo "--- Sysroot headers ---"
check "sysroot/usr/include/stdio.h" "${OUTPUT_DIR}/sysroot/usr/include/stdio.h"
check "sysroot/usr/include/stdlib.h" "${OUTPUT_DIR}/sysroot/usr/include/stdlib.h"
check "sysroot/usr/include/android/log.h" "${OUTPUT_DIR}/sysroot/usr/include/android/log.h"
check "sysroot/usr/include/pthread.h" "${OUTPUT_DIR}/sysroot/usr/include/pthread.h"

for arch in ${ARCHES}; do
    declare -A SYSROOT_TRIPLE
    SYSROOT_TRIPLE[aarch64]="aarch64-linux-android"
    SYSROOT_TRIPLE[armv7a]="arm-linux-androideabi"
    SYSROOT_TRIPLE[x86_64]="x86_64-linux-android"
    triple="${SYSROOT_TRIPLE[$arch]}"
    check "arch headers ${triple}" "${OUTPUT_DIR}/sysroot/usr/include/${triple}"
done

# ---- Check 6: Sysroot libraries ----
echo ""
echo "--- Sysroot libraries ---"

for arch in ${ARCHES}; do
    SYSROOT_TRIPLE[aarch64]="aarch64-linux-android"
    SYSROOT_TRIPLE[armv7a]="arm-linux-androideabi"
    SYSROOT_TRIPLE[x86_64]="x86_64-linux-android"
    triple="${SYSROOT_TRIPLE[$arch]}"
    lib_dir="${OUTPUT_DIR}/sysroot/usr/lib/${triple}"

    check "${triple}/libc.a" "${lib_dir}/libc.a"
    check "${triple}/libm.a" "${lib_dir}/libm.a"
    check "${triple}/libdl.a" "${lib_dir}/libdl.a"
    check "${triple}/liblog.so (API ${API_LEVEL})" "${lib_dir}/${API_LEVEL}/liblog.so"
    check "${triple}/libc.so (API ${API_LEVEL})" "${lib_dir}/${API_LEVEL}/libc.so"
    check "${triple}/libm.so (API ${API_LEVEL})" "${lib_dir}/${API_LEVEL}/libm.so"
    check "${triple}/libdl.so (API ${API_LEVEL})" "${lib_dir}/${API_LEVEL}/libdl.so"
    check "${triple}/crtbegin_so.o" "${lib_dir}/${API_LEVEL}/crtbegin_so.o"
    check "${triple}/crtend_so.o" "${lib_dir}/${API_LEVEL}/crtend_so.o"
    check "${triple}/crtbegin_dynamic.o" "${lib_dir}/${API_LEVEL}/crtbegin_dynamic.o"
    check "${triple}/crtend_android.o" "${lib_dir}/${API_LEVEL}/crtend_android.o"
    check "${triple}/libc++_static.a" "${lib_dir}/libc++_static.a"
    check "${triple}/libc++abi.a" "${lib_dir}/libc++abi.a"
    check "${triple}/libunwind.a" "${lib_dir}/libunwind.a"
done

# ---- Check 7: Compiler-rt builtins ----
echo ""
echo "--- Compiler-rt builtins ---"

declare -A RT_ARCH
RT_ARCH[aarch64]="aarch64"
RT_ARCH[armv7a]="arm"
RT_ARCH[x86_64]="x86_64"

# Find clang version for resource dir path
CLANG_VER=$("${OUTPUT_DIR}/bin/clang" --version 2>/dev/null | head -1 | grep -oP '\d+' | head -1 || echo "19")
for arch in ${ARCHES}; do
    rt_arch="${RT_ARCH[$arch]}"
    check "builtins-${rt_arch}-android" "${OUTPUT_DIR}/lib/clang/${CLANG_VER}/lib/linux/libclang_rt.builtins-${rt_arch}-android.a"
done

# ---- Check 8: Test compilation ----
echo ""
echo "--- Test compilation ---"

if [ -f "${TEST_DIR}/hello.c" ] && [ -x "${OUTPUT_DIR}/bin/clang" ]; then
    for arch in ${ARCHES}; do
        triple="${WRAPPER_TRIPLE[$arch]}"
        wrapper="${OUTPUT_DIR}/bin/${triple}${API_LEVEL}-clang"
        test_out="/tmp/test_${arch}"

        if [ -x "$wrapper" ]; then
            if "$wrapper" -c "${TEST_DIR}/hello.c" -o "${test_out}.o" 2>/dev/null; then
                # Check ELF
                file_info=$(file "${test_out}.o" 2>/dev/null || echo "unknown")
                echo "  [PASS] C compile ${triple}: ${file_info}"
                PASS=$((PASS + 1))
                rm -f "${test_out}.o"
            else
                echo "  [FAIL] C compile ${triple}"
                FAIL=$((FAIL + 1))
            fi
        else
            echo "  [SKIP] ${triple} — wrapper not found"
        fi
    done
fi

if [ -f "${TEST_DIR}/hello.cpp" ] && [ -x "${OUTPUT_DIR}/bin/clang++" ]; then
    for arch in ${ARCHES}; do
        triple="${WRAPPER_TRIPLE[$arch]}"
        wrapper="${OUTPUT_DIR}/bin/${triple}${API_LEVEL}-clang++"
        test_out="/tmp/test_${arch}_cpp"

        if [ -x "$wrapper" ]; then
            if "$wrapper" -c "${TEST_DIR}/hello.cpp" -o "${test_out}.o" -stdlib=libc++ 2>/dev/null; then
                file_info=$(file "${test_out}.o" 2>/dev/null || echo "unknown")
                echo "  [PASS] C++ compile ${triple}: ${file_info}"
                PASS=$((PASS + 1))
                rm -f "${test_out}.o"
            else
                echo "  [FAIL] C++ compile ${triple}"
                FAIL=$((FAIL + 1))
            fi
        else
            echo "  [SKIP] ${triple} — wrapper not found"
        fi
    done
fi

# ---- Summary ----
echo ""
echo "============================================"
echo "  Verification Summary"
echo "============================================"
echo ""
echo "  PASS: ${PASS}"
echo "  FAIL: ${FAIL}"
echo ""

if [ $FAIL -gt 0 ]; then
    echo "  STATUS: FAILED"
    exit 1
else
    echo "  STATUS: ALL CHECKS PASSED"
    exit 0
fi
