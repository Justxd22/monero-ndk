#!/bin/bash
# Phase 3d: Build libc.a from bionic source
#
# Strategy: Generate libc.a as a static archive containing stub implementations
# for all symbols exported by bionic's libc at API level 21.
#
# Why stubs work: Android always dynamically links libc.so at runtime. The libc.a
# in the NDK sysroot exists for:
#   1. Configure-time probes (AC_CHECK_FUNC, cmake check_function_exists)
#   2. Linker symbol resolution during cross-compilation
#   3. CRT startup code (handled separately by 03b-build-crt.sh)
#
# The real libc implementation lives on the Android device in /system/lib{64}/libc.so.
# A full from-source libc.a (650+ files with scudo, gwp_asan, etc.) is only needed
# for fully static Android executables, which monero_c does not produce.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.sh"

BIONIC_SRC="${SOURCES_DIR}/bionic"
SYSROOT_DIR="${OUTPUT_DIR}/sysroot"
LLVM_BIN="${BUILD_DIR}/llvm-install/bin"
LIBC_BUILD_DIR="${BUILD_DIR}/libc"

CC="${LLVM_BIN}/clang"
AR="${LLVM_BIN}/llvm-ar"

declare -A SYSROOT_TRIPLE
SYSROOT_TRIPLE[aarch64]="aarch64-linux-android"
SYSROOT_TRIPLE[armv7a]="arm-linux-androideabi"
SYSROOT_TRIPLE[x86_64]="x86_64-linux-android"

declare -A CLANG_TARGET
CLANG_TARGET[aarch64]="aarch64-linux-android${API_LEVEL}"
CLANG_TARGET[armv7a]="armv7a-linux-androideabi${API_LEVEL}"
CLANG_TARGET[x86_64]="x86_64-linux-android${API_LEVEL}"

echo "============================================"
echo "  Building libc.a from bionic map file"
echo "============================================"
echo ""

# ---------- Reuse the map-file parser from 03a ----------
# We parse libc.map.txt the same way as for .so stubs, but compile
# into .o files and archive them into libc.a

generate_libc_stubs() {
    local map_file="$1"
    local arch="$2"
    local output_c="$3"

    local arch_tag="" arch_tag_64=""
    case "$arch" in
        aarch64) arch_tag="arm64"  ; arch_tag_64="aarch64" ;;
        armv7a)  arch_tag="arm"    ; arch_tag_64="" ;;
        x86_64)  arch_tag="x86_64" ; arch_tag_64="" ;;
    esac

    local section_api=0 in_global=0

    cat > "$output_c" <<'HEADER'
// Auto-generated libc.a stubs from bionic libc.map.txt
// Provides symbol resolution for cross-compilation linking.
// Real implementations are in /system/lib{64}/libc.so on the Android device.
#include <stddef.h>
HEADER

    while IFS= read -r line; do
        local trimmed
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$trimmed" ]] && continue
        [[ "$trimmed" == \#* ]] && continue

        if [[ "$trimmed" =~ ^[A-Z_0-9]+[[:space:]]*\{ ]]; then
            in_global=0; section_api=0
            if [[ "$trimmed" =~ ^LIBC_PLATFORM ]] || [[ "$trimmed" =~ ^LIBC_PRIVATE ]]; then
                section_api=99999; continue
            fi
            if [[ "$trimmed" =~ introduced-${arch_tag}=([0-9]+) ]]; then
                section_api="${BASH_REMATCH[1]}"
            elif [[ -n "$arch_tag_64" ]] && [[ "$trimmed" =~ introduced-${arch_tag_64}=([0-9]+) ]]; then
                section_api="${BASH_REMATCH[1]}"
            elif [[ "$trimmed" =~ introduced=([0-9]+) ]]; then
                section_api="${BASH_REMATCH[1]}"
            fi
            [[ "$trimmed" =~ platform-only ]] && section_api=99999
            continue
        fi

        [[ "$trimmed" == "global:" ]] && { in_global=1; continue; }
        [[ "$trimmed" == "local:" ]] && { in_global=0; continue; }
        [[ "$trimmed" =~ ^\} ]] && { in_global=0; section_api=0; continue; }
        [[ $in_global -eq 0 ]] && continue

        local symbol="" annotations=""
        if [[ "$trimmed" =~ ^([a-zA-Z0-9_]+)[[:space:]]*\;[[:space:]]*(#.*)?$ ]]; then
            symbol="${BASH_REMATCH[1]}"; annotations="${BASH_REMATCH[2]}"
        else
            continue
        fi
        [[ -z "$symbol" ]] && continue

        local is_var=0 is_weak=0 sym_api="$section_api" arch_match=1
        if [[ -n "$annotations" ]]; then
            annotations="${annotations#\#}"
            annotations=$(echo "$annotations" | sed 's/^[[:space:]]*//')
            [[ "$annotations" =~ (^|[[:space:]])var($|[[:space:]]) ]] && is_var=1
            [[ "$annotations" =~ (^|[[:space:]])weak($|[[:space:]]) ]] && is_weak=1
            if [[ "$annotations" =~ introduced-${arch_tag}=([0-9]+) ]]; then
                sym_api="${BASH_REMATCH[1]}"
            elif [[ -n "$arch_tag_64" ]] && [[ "$annotations" =~ introduced-${arch_tag_64}=([0-9]+) ]]; then
                sym_api="${BASH_REMATCH[1]}"
            elif [[ "$annotations" =~ introduced=([0-9]+) ]]; then
                sym_api="${BASH_REMATCH[1]}"
            fi
            local has_arch_tags=0
            for tag in arm arm64 x86 x86_64 riscv64; do
                [[ "$annotations" =~ (^|[[:space:]])${tag}($|[[:space:]]) ]] && { has_arch_tags=1; break; }
            done
            if [[ $has_arch_tags -eq 1 ]]; then
                arch_match=0
                [[ "$annotations" =~ (^|[[:space:]])${arch_tag}($|[[:space:]]) ]] && arch_match=1
                [[ -n "$arch_tag_64" ]] && [[ "$annotations" =~ (^|[[:space:]])${arch_tag_64}($|[[:space:]]) ]] && arch_match=1
            fi
        fi

        [[ $sym_api -gt $API_LEVEL ]] && continue
        [[ $arch_match -eq 0 ]] && continue

        if [[ $is_var -eq 1 ]]; then
            if [[ $is_weak -eq 1 ]]; then
                echo "__attribute__((weak)) void* ${symbol} = 0;" >> "$output_c"
            else
                echo "void* ${symbol} = 0;" >> "$output_c"
            fi
        else
            if [[ $is_weak -eq 1 ]]; then
                echo "__attribute__((weak)) void ${symbol}(void) {}" >> "$output_c"
            else
                echo "void ${symbol}(void) {}" >> "$output_c"
            fi
        fi
    done < "$map_file"
}

for arch in ${ARCHES}; do
    triple="${SYSROOT_TRIPLE[$arch]}"
    target="${CLANG_TARGET[$arch]}"
    lib_dir="${SYSROOT_DIR}/usr/lib/${triple}"
    arch_build="${LIBC_BUILD_DIR}/${arch}"

    mkdir -p "$lib_dir" "$arch_build"

    echo "[LIBC] Building for ${triple}..."

    # Generate stubs from map file
    stub_c="${arch_build}/libc_stubs.c"
    generate_libc_stubs "${BIONIC_SRC}/libc/libc.map.txt" "$arch" "$stub_c"

    sym_count=$(grep -c "void" "$stub_c" || echo 0)
    echo "        Generated ${sym_count} stub symbols"

    # Compile stubs (use -fno-builtin -w to suppress builtin signature mismatch warnings)
    "$CC" --target="$target" \
        --sysroot="${SYSROOT_DIR}" \
        -c -fPIC -O2 -fno-builtin -w \
        "$stub_c" -o "${arch_build}/libc_stubs.o"

    # Also compile a few real bionic source files that are commonly
    # needed at link time (errno, __errno, etc.)
    extra_objs=()

    # errno.cpp — needed by virtually everything
    if [ -f "${BIONIC_SRC}/libc/bionic/errno.cpp" ]; then
        if "$CC" --target="$target" \
            --sysroot="${SYSROOT_DIR}" \
            -I "${BIONIC_SRC}/libc/private" \
            -I "${BIONIC_SRC}/libc/bionic" \
            -D_LIBC=1 -DANDROID -D__ANDROID__ \
            -c -fPIC -O2 -std=c++17 -fno-exceptions -fno-rtti \
            "${BIONIC_SRC}/libc/bionic/errno.cpp" \
            -o "${arch_build}/errno.o" 2>/dev/null; then
            extra_objs+=("${arch_build}/errno.o")
            echo "        [OK] errno.cpp"
        fi
    fi

    # Create archive
    "$AR" rcs "${lib_dir}/libc.a" "${arch_build}/libc_stubs.o" "${extra_objs[@]}"
    echo "        [OK] ${triple}/libc.a ($(wc -c < "${lib_dir}/libc.a") bytes, ${sym_count} symbols)"
    echo ""
done

echo "[LIBC] All libc.a libraries built successfully"
