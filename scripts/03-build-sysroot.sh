#!/bin/bash
# Phase 3: Assemble the bionic sysroot
# Combines headers from bionic source + platform libs from prebuilts/ndk

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source <(grep -E '^[A-Z_]+\s*:?=' "$ROOT_DIR/config.mk" | sed 's/ *:= */=/;s/ *=  */=/')

SOURCES_DIR="${ROOT_DIR}/sources"
SYSROOT_DIR="${ROOT_DIR}/output/sysroot"
BIONIC_SRC="${SOURCES_DIR}/bionic"
PREBUILTS_NDK_SRC="${SOURCES_DIR}/prebuilts-ndk"

# Architecture mapping for sysroot lib directories
declare -A SYSROOT_TRIPLE
SYSROOT_TRIPLE[aarch64]="aarch64-linux-android"
SYSROOT_TRIPLE[armv7a]="arm-linux-androideabi"
SYSROOT_TRIPLE[x86_64]="x86_64-linux-android"

# Skip if already built
if [ -f "${SYSROOT_DIR}/.sysroot_complete" ]; then
    echo "[SKIP] Sysroot already assembled at ${SYSROOT_DIR}"
    exit 0
fi

echo "============================================"
echo "  Assembling bionic sysroot"
echo "============================================"
echo ""

# Clean and create output
rm -rf "${SYSROOT_DIR}"
mkdir -p "${SYSROOT_DIR}/usr/include"
mkdir -p "${SYSROOT_DIR}/usr/lib"

# ---- Step 1: Locate the sysroot in prebuilts/ndk ----
echo "[SYSROOT] Locating prebuilt sysroot in prebuilts/ndk..."

# The prebuilts/ndk repo contains the platform sysroot under
# a versioned directory. Find the latest one available.
PLATFORM_SYSROOT=""

# Try common paths in prebuilts/ndk
for candidate in \
    "${PREBUILTS_NDK_SRC}/current/sources/sysroot" \
    "${PREBUILTS_NDK_SRC}/platform/sysroot" \
    "${PREBUILTS_NDK_SRC}/r28/sources/sysroot" \
    "${PREBUILTS_NDK_SRC}/r27/sources/sysroot" \
    "${PREBUILTS_NDK_SRC}/r26/sources/sysroot"; do
    if [ -d "$candidate" ]; then
        PLATFORM_SYSROOT="$candidate"
        echo "        Found at: $candidate"
        break
    fi
done

# If not found in expected paths, search for it
if [ -z "$PLATFORM_SYSROOT" ]; then
    echo "        Searching for sysroot directory..."
    PLATFORM_SYSROOT=$(find "${PREBUILTS_NDK_SRC}" -type d -name "sysroot" -path "*/sources/*" 2>/dev/null | head -1 || true)
    if [ -z "$PLATFORM_SYSROOT" ]; then
        # Also check for usr/include pattern directly
        PLATFORM_SYSROOT=$(find "${PREBUILTS_NDK_SRC}" -type d -name "sysroot" 2>/dev/null | head -1 || true)
    fi
fi

if [ -z "$PLATFORM_SYSROOT" ]; then
    echo "[ERROR] Could not find sysroot in prebuilts/ndk"
    echo "        Available directories:"
    find "${PREBUILTS_NDK_SRC}" -maxdepth 3 -type d | head -30
    exit 1
fi

echo "[OK]    Sysroot source: ${PLATFORM_SYSROOT}"

# ---- Step 2: Copy headers ----
echo ""
echo "[HEADERS] Copying C headers..."

# Copy from prebuilts sysroot (most complete set of headers)
if [ -d "${PLATFORM_SYSROOT}/usr/include" ]; then
    cp -a "${PLATFORM_SYSROOT}/usr/include/"* "${SYSROOT_DIR}/usr/include/"
    echo "        Copied from prebuilts sysroot"
fi

# If bionic has additional headers not in prebuilts, overlay them
if [ -d "${BIONIC_SRC}/libc/include" ]; then
    echo "        Overlaying bionic libc headers..."
    cp -a "${BIONIC_SRC}/libc/include/"* "${SYSROOT_DIR}/usr/include/" 2>/dev/null || true
fi

# Kernel UAPI headers
if [ -d "${BIONIC_SRC}/libc/kernel/uapi" ]; then
    echo "        Copying kernel UAPI headers..."
    cp -a "${BIONIC_SRC}/libc/kernel/uapi/"* "${SYSROOT_DIR}/usr/include/" 2>/dev/null || true
fi

# Verify arch-specific header dirs exist
for arch in ${ARCHES}; do
    triple="${SYSROOT_TRIPLE[$arch]}"
    if [ -d "${SYSROOT_DIR}/usr/include/${triple}" ]; then
        echo "        [OK] Arch headers: ${triple}"
    else
        echo "        [WARN] Missing arch headers: ${triple}"
        # Try to create from bionic
        if [ -d "${BIONIC_SRC}/libc/arch-${arch}/include" ]; then
            mkdir -p "${SYSROOT_DIR}/usr/include/${triple}"
            cp -a "${BIONIC_SRC}/libc/arch-${arch}/include/"* \
                "${SYSROOT_DIR}/usr/include/${triple}/" 2>/dev/null || true
            echo "        [OK] Created from bionic arch-${arch}"
        fi
    fi
done

echo "        Total headers: $(find "${SYSROOT_DIR}/usr/include" -type f | wc -l) files"

# ---- Step 3: Copy platform libraries ----
echo ""
echo "[LIBS] Copying platform libraries..."

# Find the platform libs in prebuilts/ndk
# They're typically under platforms/android-<API>/arch-<arch>/usr/lib/
# Or under a more modern layout
for arch in ${ARCHES}; do
    triple="${SYSROOT_TRIPLE[$arch]}"
    lib_dir="${SYSROOT_DIR}/usr/lib/${triple}"
    api_lib_dir="${lib_dir}/${API_LEVEL}"

    mkdir -p "$lib_dir"
    mkdir -p "$api_lib_dir"

    echo "        Processing ${triple}..."

    # Try modern sysroot layout first (lib/<triple>/)
    src_lib="${PLATFORM_SYSROOT}/usr/lib/${triple}"
    if [ -d "$src_lib" ]; then
        # Copy static libs
        find "$src_lib" -maxdepth 1 -name "*.a" -exec cp {} "$lib_dir/" \; 2>/dev/null
        find "$src_lib" -maxdepth 1 -name "*.o" -exec cp {} "$lib_dir/" \; 2>/dev/null

        # Copy API-specific shared libs
        if [ -d "${src_lib}/${API_LEVEL}" ]; then
            cp -a "${src_lib}/${API_LEVEL}/"* "$api_lib_dir/" 2>/dev/null || true
        fi

        static_count=$(find "$lib_dir" -maxdepth 1 -name "*.a" | wc -l)
        shared_count=$(find "$api_lib_dir" -name "*.so" | wc -l)
        crt_count=$(find "$lib_dir" -maxdepth 1 -name "*.o" | wc -l)
        echo "        [OK] ${triple}: ${static_count} .a, ${shared_count} .so, ${crt_count} .o"
    else
        echo "        [WARN] No libs found at ${src_lib}"
        # Try legacy layout
        legacy_arch="$arch"
        case "$arch" in
            aarch64) legacy_arch="arm64" ;;
            armv7a)  legacy_arch="arm" ;;
        esac
        legacy_path=$(find "${PREBUILTS_NDK_SRC}" -type d -name "arch-${legacy_arch}" -path "*/android-${API_LEVEL}/*" 2>/dev/null | head -1 || true)
        if [ -n "$legacy_path" ] && [ -d "${legacy_path}/usr/lib" ]; then
            cp -a "${legacy_path}/usr/lib/"* "$lib_dir/" 2>/dev/null || true
            echo "        [OK] Used legacy layout: ${legacy_path}"
        else
            echo "        [ERROR] Could not find platform libs for ${triple}"
        fi
    fi
done

# ---- Step 4: Mark complete ----
touch "${SYSROOT_DIR}/.sysroot_complete"

echo ""
echo "============================================"
echo "  Sysroot assembly complete"
echo "============================================"
echo ""
echo "Layout:"
echo "  ${SYSROOT_DIR}/"
find "${SYSROOT_DIR}" -maxdepth 4 -type d | sort | head -30
echo ""
du -sh "${SYSROOT_DIR}"
