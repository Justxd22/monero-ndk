#!/bin/bash
# Phase 3a: Generate .so stub libraries from bionic .map.txt files
# These are linker stubs — they contain the right symbol names/types
# so the linker resolves them, but the real implementations live on the
# Android device in /system/lib{64}/.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.sh"

BIONIC_SRC="${SOURCES_DIR}/bionic"
LOGGING_SRC="${SOURCES_DIR}/system-logging"
SYSROOT_DIR="${OUTPUT_DIR}/sysroot"
LLVM_BIN="${BUILD_DIR}/llvm-install/bin"
STUB_BUILD_DIR="${BUILD_DIR}/stubs"

# Architecture mapping
declare -A SYSROOT_TRIPLE
SYSROOT_TRIPLE[aarch64]="aarch64-linux-android"
SYSROOT_TRIPLE[armv7a]="arm-linux-androideabi"
SYSROOT_TRIPLE[x86_64]="x86_64-linux-android"

declare -A CLANG_TARGET
CLANG_TARGET[aarch64]="aarch64-linux-android${API_LEVEL}"
CLANG_TARGET[armv7a]="armv7a-linux-androideabi${API_LEVEL}"
CLANG_TARGET[x86_64]="x86_64-linux-android${API_LEVEL}"

# Map arch names used in .map.txt annotations to our arch names
# In map files: arm = armv7a (32-bit ARM), arm64 = aarch64, x86_64 = x86_64

echo "============================================"
echo "  Generating .so stub libraries"
echo "============================================"
echo ""

# parse_map_and_generate_stubs <map_file> <lib_name> <arch>
# Reads a bionic .map.txt file and generates a C file with stub symbols
# that are appropriate for the given arch at API level ${API_LEVEL}.
parse_map_and_generate_stubs() {
    local map_file="$1"
    local lib_name="$2"
    local arch="$3"
    local output_c="$4"

    # Determine what arch tags match this arch in map file annotations
    local arch_tag=""
    local arch_tag_64=""
    case "$arch" in
        aarch64) arch_tag="arm64"  ; arch_tag_64="aarch64" ;;
        armv7a)  arch_tag="arm"    ; arch_tag_64="" ;;
        x86_64)  arch_tag="x86_64" ; arch_tag_64="" ;;
    esac

    # Track current section's introduced level
    local section_api=0

    cat > "$output_c" <<'HEADER'
// Auto-generated stub library — do not edit
// These stubs provide symbol resolution for linking against Android platform libs
HEADER

    local in_global=0

    while IFS= read -r line; do
        # Strip leading/trailing whitespace
        local trimmed
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Skip empty lines and pure comments
        [[ -z "$trimmed" ]] && continue
        [[ "$trimmed" == \#* ]] && continue

        # Detect section headers like: LIBC_OMR1 { # introduced=27
        if [[ "$trimmed" =~ ^[A-Z_0-9]+[[:space:]]*\{ ]]; then
            in_global=0
            section_api=0

            # Exclude LIBC_PLATFORM and LIBC_PRIVATE sections (not for NDK)
            if [[ "$trimmed" =~ ^LIBC_PLATFORM ]] || [[ "$trimmed" =~ ^LIBC_PRIVATE ]]; then
                section_api=99999
                continue
            fi

            # Check for per-arch introduced on section header first
            if [[ "$trimmed" =~ introduced-${arch_tag}=([0-9]+) ]]; then
                section_api="${BASH_REMATCH[1]}"
            elif [[ -n "$arch_tag_64" ]] && [[ "$trimmed" =~ introduced-${arch_tag_64}=([0-9]+) ]]; then
                section_api="${BASH_REMATCH[1]}"
            elif [[ "$trimmed" =~ introduced=([0-9]+) ]]; then
                # Generic introduced= (no arch suffix)
                section_api="${BASH_REMATCH[1]}"
            fi

            # Check for arch restriction on section header (e.g., "# arm platform-only")
            if [[ "$trimmed" =~ platform-only ]]; then
                section_api=99999
            fi
            continue
        fi

        # Detect "global:" marker
        if [[ "$trimmed" == "global:" ]]; then
            in_global=1
            continue
        fi

        # Detect "local:" marker — stop processing symbols in this section
        if [[ "$trimmed" == "local:" ]]; then
            in_global=0
            continue
        fi

        # Detect section close: } LIBC_xxx;
        if [[ "$trimmed" =~ ^\} ]]; then
            in_global=0
            section_api=0
            continue
        fi

        # Skip LIBC_PRIVATE and LIBC_PLATFORM sections (not for NDK)
        # These are filtered by section_api=99999 above, but also skip
        # any symbol not in a global: block
        [[ $in_global -eq 0 ]] && continue

        # Parse symbol line: "symbol_name; # annotations"
        local symbol=""
        local annotations=""
        if [[ "$trimmed" =~ ^([a-zA-Z0-9_]+)[[:space:]]*\;[[:space:]]*(#.*)?$ ]]; then
            symbol="${BASH_REMATCH[1]}"
            annotations="${BASH_REMATCH[2]}"
        elif [[ "$trimmed" =~ ^\*\; ]]; then
            # wildcard in local section, skip
            continue
        else
            continue
        fi

        [[ -z "$symbol" ]] && continue

        # Check annotations
        local is_var=0
        local is_weak=0
        local sym_api="$section_api"
        local arch_restricted=0
        local arch_match=1

        if [[ -n "$annotations" ]]; then
            # Remove the leading #
            annotations="${annotations#\#}"
            annotations=$(echo "$annotations" | sed 's/^[[:space:]]*//')

            # Check for "var"
            [[ "$annotations" =~ (^|[[:space:]])var($|[[:space:]]) ]] && is_var=1

            # Check for "weak"
            [[ "$annotations" =~ (^|[[:space:]])weak($|[[:space:]]) ]] && is_weak=1

            # Check for per-arch introduced first, then fall back to generic introduced=
            # Per-arch takes priority: introduced-arm=N, introduced-arm64=N, etc.
            if [[ "$annotations" =~ introduced-${arch_tag}=([0-9]+) ]]; then
                sym_api="${BASH_REMATCH[1]}"
            elif [[ -n "$arch_tag_64" ]] && [[ "$annotations" =~ introduced-${arch_tag_64}=([0-9]+) ]]; then
                sym_api="${BASH_REMATCH[1]}"
            elif [[ "$annotations" =~ introduced=([0-9]+) ]]; then
                # Generic introduced= (only use if no per-arch variant exists)
                sym_api="${BASH_REMATCH[1]}"
            fi

            # Check for arch restrictions (e.g., "# arm" means only arm, "# arm x86" means arm and x86)
            # If annotations contain bare arch names without "introduced-", it's a restriction
            local has_arch_tags=0
            for tag in arm arm64 x86 x86_64 riscv64; do
                if [[ "$annotations" =~ (^|[[:space:]])${tag}($|[[:space:]]) ]]; then
                    has_arch_tags=1
                    break
                fi
            done

            if [[ $has_arch_tags -eq 1 ]]; then
                # This symbol is arch-restricted — check if our arch matches
                arch_match=0
                if [[ "$annotations" =~ (^|[[:space:]])${arch_tag}($|[[:space:]]) ]]; then
                    arch_match=1
                fi
                if [[ -n "$arch_tag_64" ]] && [[ "$annotations" =~ (^|[[:space:]])${arch_tag_64}($|[[:space:]]) ]]; then
                    arch_match=1
                fi
            fi
        fi

        # Skip if introduced after our API level
        if [[ $sym_api -gt $API_LEVEL ]]; then
            continue
        fi

        # Skip if arch doesn't match
        if [[ $arch_match -eq 0 ]]; then
            continue
        fi

        # Emit the symbol
        if [[ $is_var -eq 1 ]]; then
            if [[ $is_weak -eq 1 ]]; then
                echo "__attribute__((weak)) void* ${symbol} = 0;" >> "$output_c"
            else
                echo "void* ${symbol} = 0;" >> "$output_c"
            fi
        else
            if [[ $is_weak -eq 1 ]]; then
                echo "__attribute__((weak)) void ${symbol}() {}" >> "$output_c"
            else
                echo "void ${symbol}() {}" >> "$output_c"
            fi
        fi
    done < "$map_file"
}

# compile_stub <arch> <lib_name> <c_file> <output_so>
compile_stub() {
    local arch="$1"
    local lib_name="$2"
    local c_file="$3"
    local output_so="$4"
    local target="${CLANG_TARGET[$arch]}"

    "${LLVM_BIN}/clang" \
        --target="$target" \
        -shared \
        -nostdlib \
        -Wl,-soname,"${lib_name}.so" \
        -o "$output_so" \
        "$c_file" \
        2>/dev/null || {
            echo "        [WARN] Failed to compile ${lib_name}.so for ${arch}, trying with -Wno-everything..."
            "${LLVM_BIN}/clang" \
                --target="$target" \
                -shared \
                -nostdlib \
                -Wno-everything \
                -Wl,-soname,"${lib_name}.so" \
                -o "$output_so" \
                "$c_file"
        }
}

# Libraries to generate stubs for
declare -A STUB_LIBS
STUB_LIBS[libc]="${BIONIC_SRC}/libc/libc.map.txt"
STUB_LIBS[libm]="${BIONIC_SRC}/libm/libm.map.txt"
STUB_LIBS[libdl]="${BIONIC_SRC}/libdl/libdl.map.txt"
STUB_LIBS[libstdc++]="${BIONIC_SRC}/libc/libstdc++.map.txt"

for arch in ${ARCHES}; do
    triple="${SYSROOT_TRIPLE[$arch]}"
    target="${CLANG_TARGET[$arch]}"
    api_lib_dir="${SYSROOT_DIR}/usr/lib/${triple}/${API_LEVEL}"
    arch_stub_dir="${STUB_BUILD_DIR}/${arch}"

    mkdir -p "$api_lib_dir"
    mkdir -p "$arch_stub_dir"

    echo "[STUBS] Generating for ${triple}..."

    for lib_name in libc libm libdl libstdc++; do
        map_file="${STUB_LIBS[$lib_name]}"
        if [ ! -f "$map_file" ]; then
            echo "        [WARN] Map file not found: ${map_file}"
            continue
        fi

        stub_c="${arch_stub_dir}/${lib_name}_stubs.c"
        stub_so="${api_lib_dir}/${lib_name}.so"

        parse_map_and_generate_stubs "$map_file" "$lib_name" "$arch" "$stub_c"
        compile_stub "$arch" "$lib_name" "$stub_c" "$stub_so"
        echo "        [OK] ${lib_name}.so"
    done

    # Generate liblog.so — use system/logging map file if available, else hardcode known symbols
    liblog_stub_c="${arch_stub_dir}/liblog_stubs.c"
    liblog_so="${api_lib_dir}/liblog.so"

    if [ -f "${LOGGING_SRC}/liblog/liblog.map.txt" ]; then
        parse_map_and_generate_stubs "${LOGGING_SRC}/liblog/liblog.map.txt" "liblog" "$arch" "$liblog_stub_c"
    else
        # Hardcode the 8 well-known liblog symbols available at API 21
        cat > "$liblog_stub_c" <<'EOF'
// liblog stub — hardcoded symbols for API 21
void __android_log_assert() {}
void __android_log_buf_print() {}
void __android_log_buf_write() {}
void __android_log_print() {}
void __android_log_vprint() {}
void __android_log_write() {}
void __android_log_btwrite() {}
void __android_log_is_loggable() {}
EOF
    fi

    compile_stub "$arch" "liblog" "$liblog_stub_c" "$liblog_so"
    echo "        [OK] liblog.so"
done

echo ""
echo "[STUBS] All stub libraries generated successfully"
