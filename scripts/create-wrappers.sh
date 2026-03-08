#!/bin/bash
# Generate target-specific clang wrapper scripts
# These wrappers call clang with the correct --target and --sysroot flags

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.sh"

OUTPUT_DIR="${ROOT_DIR}/output"
BIN_DIR="${OUTPUT_DIR}/bin"

# Wrapper triple mapping
declare -A WRAPPER_TRIPLE
WRAPPER_TRIPLE[aarch64]="aarch64-linux-android"
WRAPPER_TRIPLE[armv7a]="armv7a-linux-androideabi"
WRAPPER_TRIPLE[x86_64]="x86_64-linux-android"

create_wrapper() {
    local wrapper_name="$1"
    local compiler="$2"  # clang or clang++
    local target="$3"    # e.g., aarch64-linux-android21

    cat > "${BIN_DIR}/${wrapper_name}" <<WRAPPER
#!/bin/bash
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
exec "\${SCRIPT_DIR}/${compiler}" \\
    --target=${target} \\
    --sysroot="\${SCRIPT_DIR}/../sysroot" \\
    "\$@"
WRAPPER
    chmod +x "${BIN_DIR}/${wrapper_name}"
}

mkdir -p "$BIN_DIR"

for arch in ${ARCHES}; do
    triple="${WRAPPER_TRIPLE[$arch]}"
    target="${triple}${API_LEVEL}"

    # Create clang wrapper (with API level suffix — this is the real script)
    create_wrapper "${target}-clang" "clang" "$target"

    # Create clang++ wrapper (with API level suffix — this is the real script)
    create_wrapper "${target}-clang++" "clang++" "$target"

    # Create wrappers without API level suffix as symlinks to the API-level ones
    # (symlinks avoid symlink_same.py dedup creating circular links)
    ln -sf "${target}-clang" "${BIN_DIR}/${triple}-clang"
    ln -sf "${target}-clang++" "${BIN_DIR}/${triple}-clang++"

    # Create gcc-compatible aliases (some build systems look for these)
    ln -sf "${target}-clang" "${BIN_DIR}/${triple}-gcc" 2>/dev/null || true
    ln -sf "${target}-clang++" "${BIN_DIR}/${triple}-g++" 2>/dev/null || true

    # Create arch-specific tool aliases
    ln -sf llvm-ar "${BIN_DIR}/${triple}-ar" 2>/dev/null || true
    ln -sf llvm-ranlib "${BIN_DIR}/${triple}-ranlib" 2>/dev/null || true
    ln -sf llvm-strip "${BIN_DIR}/${triple}-strip" 2>/dev/null || true
    ln -sf llvm-nm "${BIN_DIR}/${triple}-nm" 2>/dev/null || true
    ln -sf llvm-objcopy "${BIN_DIR}/${triple}-objcopy" 2>/dev/null || true
    ln -sf llvm-objdump "${BIN_DIR}/${triple}-objdump" 2>/dev/null || true
    ln -sf llvm-readelf "${BIN_DIR}/${triple}-readelf" 2>/dev/null || true
    ln -sf lld "${BIN_DIR}/${triple}-ld" 2>/dev/null || true

    echo "        Created wrappers for ${triple} (API ${API_LEVEL})"
done
