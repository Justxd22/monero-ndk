#!/bin/bash
# Phase 2: Build LLVM/Clang from AOSP source
# Produces a host-native LLVM that can cross-compile to Android targets

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.sh"

SOURCES_DIR="${ROOT_DIR}/sources"
BUILD_DIR="${ROOT_DIR}/build/llvm"
INSTALL_DIR="${ROOT_DIR}/build/llvm-install"

# Skip if already built
if [ -x "${INSTALL_DIR}/bin/clang" ]; then
    echo "[SKIP] LLVM already built at ${INSTALL_DIR}"
    "${INSTALL_DIR}/bin/clang" --version | head -1
    exit 0
fi

echo "============================================"
echo "  Building LLVM/Clang from source"
echo "============================================"
echo ""

# ---- Step 1: Apply AOSP patches ----
echo "[PATCH] Applying AOSP patches to LLVM..."

LLVM_SRC="${SOURCES_DIR}/llvm-project"
LLVM_ANDROID_SRC="${SOURCES_DIR}/llvm_android"
TOOLCHAIN_UTILS_SRC="${SOURCES_DIR}/toolchain-utils"

# Check if patches were already applied (marker file)
PATCH_MARKER="${LLVM_SRC}/.patches_applied"
if [ -f "$PATCH_MARKER" ]; then
    echo "[SKIP] Patches already applied"
else
    if [ -f "${LLVM_ANDROID_SRC}/patches/PATCHES.json" ] && \
       [ -f "${TOOLCHAIN_UTILS_SRC}/llvm_tools/patch_manager.py" ]; then
        cd "${LLVM_ANDROID_SRC}"
        python3 "${TOOLCHAIN_UTILS_SRC}/llvm_tools/patch_manager.py" \
            --patch_metadata_file=patches/PATCHES.json \
            --src_path="${LLVM_SRC}" \
            --svn_version="${SVN_REVISION}" || {
                echo "[WARN] Some patches may have failed — continuing anyway"
            }
        touch "$PATCH_MARKER"
        echo "[OK]   Patches applied"
    else
        echo "[WARN] Patch files not found, building without AOSP patches"
    fi
fi

# ---- Step 2: Configure CMake ----
echo ""
echo "[CMAKE] Configuring LLVM build..."

mkdir -p "$BUILD_DIR"

CMAKE_FLAGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}"

    # Only build what we need
    -DLLVM_ENABLE_PROJECTS="clang;lld"
    -DLLVM_TARGETS_TO_BUILD="${LLVM_TARGETS}"

    # Disable stuff we don't need
    -DLLVM_ENABLE_BINDINGS=OFF
    -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    -DLLVM_INCLUDE_DOCS=OFF
    -DCLANG_INCLUDE_TESTS=OFF
    -DCLANG_INCLUDE_DOCS=OFF

    # compiler-rt builtins (needed for Android)
    -DCOMPILER_RT_BUILD_BUILTINS=ON
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=OFF
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF
    -DCOMPILER_RT_BUILD_XRAY=OFF
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF
    -DCOMPILER_RT_BUILD_PROFILE=OFF
    -DCOMPILER_RT_BUILD_MEMPROF=OFF
    -DCOMPILER_RT_BUILD_ORC=OFF

    # Memory-safe build for 16GB RAM
    -DLLVM_PARALLEL_LINK_JOBS=1
)

# Use lld if available on host (faster + less memory)
if command -v lld &>/dev/null || command -v ld.lld &>/dev/null; then
    CMAKE_FLAGS+=(-DLLVM_USE_LINKER=lld)
    echo "        Using lld linker"
elif command -v mold &>/dev/null; then
    CMAKE_FLAGS+=(-DLLVM_USE_LINKER=mold)
    echo "        Using mold linker"
else
    echo "        Using default linker (consider installing lld for faster builds)"
fi

cmake -S "${LLVM_SRC}/llvm" -B "${BUILD_DIR}" -G Ninja "${CMAKE_FLAGS[@]}"

# ---- Step 3: Build ----
echo ""
echo "[BUILD] Building LLVM (this will take a while)..."
echo "        Cores: ${NUM_CORES}, Link jobs: 1"
echo ""

ninja -C "${BUILD_DIR}" -j"${NUM_CORES}"

# ---- Step 4: Install ----
echo ""
echo "[INSTALL] Installing LLVM to ${INSTALL_DIR}..."

ninja -C "${BUILD_DIR}" install

# ---- Step 5: Verify ----
echo ""
echo "[VERIFY] Checking LLVM build..."

"${INSTALL_DIR}/bin/clang" --version
echo ""
echo "Supported targets:"
"${INSTALL_DIR}/bin/clang" --print-targets 2>&1 | grep -E "aarch64|arm|x86" || true

echo ""
echo "Installed binaries:"
ls "${INSTALL_DIR}/bin/" | head -30

echo ""
echo "============================================"
echo "  LLVM build complete"
echo "============================================"
du -sh "${INSTALL_DIR}"
