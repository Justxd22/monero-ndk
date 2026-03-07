#!/bin/bash
# Phase 1: Fetch all AOSP sources at pinned commits
# Uses shallow fetch to minimize bandwidth

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.sh"

fetch_repo() {
    local name="$1"
    local url="$2"
    local commit="$3"
    local dest="${SOURCES_DIR}/${name}"

    if [ -d "$dest" ]; then
        # Verify correct commit is checked out
        local current
        current=$(git -C "$dest" rev-parse HEAD 2>/dev/null || echo "none")
        if [ "$current" = "$commit" ]; then
            echo "[SKIP] ${name} — already at ${commit:0:12}"
            return 0
        else
            echo "[REFETCH] ${name} — wrong commit (${current:0:12}), expected ${commit:0:12}"
            rm -rf "$dest"
        fi
    fi

    echo "[FETCH] ${name} from ${url}"
    echo "        commit: ${commit}"
    mkdir -p "$dest"
    git -C "$dest" init -q
    git -C "$dest" remote add origin "$url"

    # Try shallow fetch of exact commit first (works on most servers)
    if git -C "$dest" fetch --depth 1 origin "$commit" 2>/dev/null; then
        git -C "$dest" checkout -q FETCH_HEAD
    else
        # Fallback: fetch all refs at depth 1, then checkout
        echo "        shallow fetch of commit failed, trying full shallow clone..."
        rm -rf "$dest"
        git clone --depth 1 "$url" "$dest"
        # Now fetch the specific commit
        git -C "$dest" fetch --depth 1 origin "$commit"
        git -C "$dest" checkout -q FETCH_HEAD
    fi

    # Verify
    local actual
    actual=$(git -C "$dest" rev-parse HEAD)
    if [ "$actual" != "$commit" ]; then
        echo "[ERROR] ${name}: expected ${commit}, got ${actual}"
        exit 1
    fi

    echo "[OK]    ${name} — ${commit:0:12}"
}

echo "============================================"
echo "  Fetching AOSP sources (shallow clones)"
echo "============================================"
echo ""

mkdir -p "$SOURCES_DIR"

fetch_repo "llvm-project" \
    "$LLVM_URL" \
    "$LLVM_COMMIT"

fetch_repo "llvm_android" \
    "$LLVM_ANDROID_URL" \
    "$LLVM_ANDROID_COMMIT"

fetch_repo "toolchain-utils" \
    "$TOOLCHAIN_UTILS_URL" \
    "$TOOLCHAIN_UTILS_COMMIT"

fetch_repo "bionic" \
    "$BIONIC_URL" \
    "$BIONIC_COMMIT"

fetch_repo "arm-optimized-routines" \
    "$ARM_ROUTINES_URL" \
    "$ARM_ROUTINES_COMMIT"

fetch_repo "scudo" \
    "$SCUDO_URL" \
    "$SCUDO_COMMIT"

fetch_repo "gwp_asan" \
    "$GWP_ASAN_URL" \
    "$GWP_ASAN_COMMIT"

fetch_repo "system-core" \
    "$SYSTEM_CORE_URL" \
    "$SYSTEM_CORE_COMMIT"

fetch_repo "system-logging" \
    "$SYSTEM_LOGGING_URL" \
    "$SYSTEM_LOGGING_COMMIT"

echo ""
echo "============================================"
echo "  All sources fetched successfully"
echo "============================================"
echo ""
du -sh "$SOURCES_DIR"/* 2>/dev/null | sort -rh
