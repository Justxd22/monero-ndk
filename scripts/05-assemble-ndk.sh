#!/bin/bash
# Phase 5: Assemble the final NDK directory layout
# Combines LLVM binaries + sysroot + libc++ into standalone toolchain

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.sh"

LLVM_INSTALL="${ROOT_DIR}/build/llvm-install"
SYSROOT_DIR="${ROOT_DIR}/output/sysroot"
RUNTIMES_DIR="${ROOT_DIR}/build/runtimes"
OUTPUT_DIR="${ROOT_DIR}/output"

# Sysroot lib triple mapping
declare -A SYSROOT_TRIPLE
SYSROOT_TRIPLE[aarch64]="aarch64-linux-android"
SYSROOT_TRIPLE[armv7a]="arm-linux-androideabi"
SYSROOT_TRIPLE[x86_64]="x86_64-linux-android"

# Wrapper triple mapping (what the wrapper script name uses)
declare -A WRAPPER_TRIPLE
WRAPPER_TRIPLE[aarch64]="aarch64-linux-android"
WRAPPER_TRIPLE[armv7a]="armv7a-linux-androideabi"
WRAPPER_TRIPLE[x86_64]="x86_64-linux-android"

echo "============================================"
echo "  Assembling final NDK layout"
echo "============================================"
echo ""

# ---- Step 1: Copy LLVM binaries ----
echo "[BIN] Copying LLVM binaries..."

mkdir -p "${OUTPUT_DIR}/bin"

# Essential binaries
LLVM_BINS=(
    clang clang++ clang-19
    lld ld.lld ld64.lld
    llvm-ar llvm-ranlib llvm-strip llvm-nm llvm-as
    llvm-objcopy llvm-objdump llvm-readelf llvm-size
    llvm-strings llvm-symbolizer llvm-addr2line
    llvm-cxxfilt llvm-profdata llvm-lib llvm-rc
)

for bin in "${LLVM_BINS[@]}"; do
    if [ -f "${LLVM_INSTALL}/bin/${bin}" ]; then
        cp "${LLVM_INSTALL}/bin/${bin}" "${OUTPUT_DIR}/bin/"
    fi
done

# Ensure clang++ exists (sometimes it's a symlink to clang)
if [ ! -f "${OUTPUT_DIR}/bin/clang++" ]; then
    ln -sf clang "${OUTPUT_DIR}/bin/clang++"
fi

echo "        Copied $(ls "${OUTPUT_DIR}/bin/" | wc -l) binaries"

# ---- Step 2: Create convenience symlinks ----
echo "[LINKS] Creating convenience symlinks..."

cd "${OUTPUT_DIR}/bin"
ln -sf llvm-ar ar
ln -sf llvm-ranlib ranlib
ln -sf llvm-strip strip
ln -sf llvm-nm nm
ln -sf llvm-as as
ln -sf llvm-objcopy objcopy
ln -sf llvm-objdump objdump
ln -sf llvm-readelf readelf
ln -sf lld ld
cd "$ROOT_DIR"

echo "        Created symlinks: ar, ranlib, strip, nm, as, objcopy, objdump, readelf, ld"

# ---- Step 3: Generate target wrapper scripts ----
echo "[WRAPPERS] Generating target-specific compiler wrappers..."

bash "${SCRIPT_DIR}/create-wrappers.sh"

# ---- Step 4: Copy compiler-rt builtins ----
echo "[RT] Copying compiler-rt builtins..."

if [ -d "${LLVM_INSTALL}/lib/clang" ]; then
    mkdir -p "${OUTPUT_DIR}/lib"
    cp -a "${LLVM_INSTALL}/lib/clang" "${OUTPUT_DIR}/lib/"
    echo "        Copied compiler-rt from ${LLVM_INSTALL}/lib/clang"
fi

# Also copy any LLVM libraries needed
if [ -d "${LLVM_INSTALL}/lib/linux" ]; then
    mkdir -p "${OUTPUT_DIR}/lib/linux"
    cp -a "${LLVM_INSTALL}/lib/linux/"* "${OUTPUT_DIR}/lib/linux/" 2>/dev/null || true
fi

# ---- Step 5: Install libc++ and libunwind into sysroot ----
echo "[LIBCXX] Installing libc++ and libunwind into sysroot..."

for arch in ${ARCHES}; do
    triple="${SYSROOT_TRIPLE[$arch]}"
    install_dir="${RUNTIMES_DIR}/${arch}-install"
    target_lib_dir="${SYSROOT_DIR}/usr/lib/${triple}"

    if [ ! -d "$install_dir" ]; then
        echo "        [WARN] Runtimes not found for ${arch}"
        continue
    fi

    # Copy static libraries
    mkdir -p "$target_lib_dir"
    cp -f "${install_dir}/lib/libc++_static.a" "$target_lib_dir/" 2>/dev/null || true
    cp -f "${install_dir}/lib/libc++abi.a" "$target_lib_dir/" 2>/dev/null || true
    cp -f "${install_dir}/lib/libc++.a" "$target_lib_dir/" 2>/dev/null || true
    cp -f "${install_dir}/lib/libunwind.a" "$target_lib_dir/" 2>/dev/null || true

    echo "        [OK] ${arch}: installed to ${target_lib_dir}"
done

# Copy C++ headers (from first arch — they're the same for all)
first_arch=$(echo "${ARCHES}" | awk '{print $1}')
cxx_headers="${RUNTIMES_DIR}/${first_arch}-install/include"
if [ -d "$cxx_headers" ]; then
    mkdir -p "${SYSROOT_DIR}/usr/include"
    cp -a "$cxx_headers"/* "${SYSROOT_DIR}/usr/include/" 2>/dev/null || true
    echo "        [OK] C++ headers installed"
fi

# ---- Step 6: Write AndroidVersion.txt ----
echo "[META] Writing AndroidVersion.txt..."

# Get clang version
CLANG_VERSION=$("${OUTPUT_DIR}/bin/clang" --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "19.0.1")
echo "${CLANG_VERSION}" > "${OUTPUT_DIR}/AndroidVersion.txt"
echo "        Version: ${CLANG_VERSION}"

# ---- Step 7: Deduplicate identical files ----
echo "[DEDUP] Deduplicating identical files..."

if [ -f "${ROOT_DIR}/patches/symlink_same.py" ]; then
    python3 "${ROOT_DIR}/patches/symlink_same.py" "${OUTPUT_DIR}" 2>/dev/null | tail -5 || true
    echo "        Deduplication complete"
else
    echo "        [SKIP] symlink_same.py not found"
fi

# ---- Done ----
echo ""
echo "============================================"
echo "  NDK assembly complete"
echo "============================================"
echo ""
echo "Output: ${OUTPUT_DIR}/"
echo ""
echo "Key files:"
echo "  bin/clang:         $(file "${OUTPUT_DIR}/bin/clang" 2>/dev/null | cut -d: -f2 | head -c60)"
echo "  AndroidVersion.txt: $(cat "${OUTPUT_DIR}/AndroidVersion.txt")"
echo ""
echo "Wrappers:"
for arch in ${ARCHES}; do
    wrapper_triple="${WRAPPER_TRIPLE[$arch]}"
    echo "  bin/${wrapper_triple}${API_LEVEL}-clang"
done
echo ""
du -sh "${OUTPUT_DIR}"
echo ""
echo "Directory structure:"
find "${OUTPUT_DIR}" -maxdepth 3 -type d | sort
