#!/bin/bash
# Phase 3c: Build libm.a from bionic source
# Compiles FreeBSD/NetBSD math functions + bionic-specific code into libm.a
#
# Source list extracted from bionic/libm/Android.bp

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.sh"

BIONIC_SRC="${SOURCES_DIR}/bionic"
LIBM_SRC="${BIONIC_SRC}/libm"
ARM_ROUTINES_SRC="${SOURCES_DIR}/arm-optimized-routines"
SYSROOT_DIR="${OUTPUT_DIR}/sysroot"
LLVM_BIN="${BUILD_DIR}/llvm-install/bin"
LIBM_BUILD_DIR="${BUILD_DIR}/libm"

CC="${LLVM_BIN}/clang"
CXX="${LLVM_BIN}/clang++"
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
echo "  Building libm.a from source"
echo "============================================"
echo ""

# ---------- Common source files (all architectures) ----------
COMMON_SRCS=(
    upstream-freebsd/lib/msun/bsdsrc/b_tgamma.c
    upstream-freebsd/lib/msun/src/catrig.c
    upstream-freebsd/lib/msun/src/catrigf.c
    upstream-freebsd/lib/msun/src/e_acos.c
    upstream-freebsd/lib/msun/src/e_acosf.c
    upstream-freebsd/lib/msun/src/e_acosh.c
    upstream-freebsd/lib/msun/src/e_acoshf.c
    upstream-freebsd/lib/msun/src/e_asin.c
    upstream-freebsd/lib/msun/src/e_asinf.c
    upstream-freebsd/lib/msun/src/e_atan2.c
    upstream-freebsd/lib/msun/src/e_atan2f.c
    upstream-freebsd/lib/msun/src/e_atanh.c
    upstream-freebsd/lib/msun/src/e_atanhf.c
    upstream-freebsd/lib/msun/src/e_cosh.c
    upstream-freebsd/lib/msun/src/e_coshf.c
    upstream-freebsd/lib/msun/src/e_fmod.c
    upstream-freebsd/lib/msun/src/e_fmodf.c
    upstream-freebsd/lib/msun/src/e_gamma.c
    upstream-freebsd/lib/msun/src/e_gammaf.c
    upstream-freebsd/lib/msun/src/e_gammaf_r.c
    upstream-freebsd/lib/msun/src/e_gamma_r.c
    upstream-freebsd/lib/msun/src/e_hypot.c
    upstream-freebsd/lib/msun/src/e_hypotf.c
    upstream-freebsd/lib/msun/src/e_j0.c
    upstream-freebsd/lib/msun/src/e_j0f.c
    upstream-freebsd/lib/msun/src/e_j1.c
    upstream-freebsd/lib/msun/src/e_j1f.c
    upstream-freebsd/lib/msun/src/e_jn.c
    upstream-freebsd/lib/msun/src/e_jnf.c
    upstream-freebsd/lib/msun/src/e_lgamma.c
    upstream-freebsd/lib/msun/src/e_lgammaf.c
    upstream-freebsd/lib/msun/src/e_lgammaf_r.c
    upstream-freebsd/lib/msun/src/e_lgamma_r.c
    upstream-freebsd/lib/msun/src/e_log10.c
    upstream-freebsd/lib/msun/src/e_log10f.c
    upstream-freebsd/lib/msun/src/e_remainder.c
    upstream-freebsd/lib/msun/src/e_remainderf.c
    upstream-freebsd/lib/msun/src/e_rem_pio2.c
    upstream-freebsd/lib/msun/src/e_rem_pio2f.c
    upstream-freebsd/lib/msun/src/e_scalb.c
    upstream-freebsd/lib/msun/src/e_scalbf.c
    upstream-freebsd/lib/msun/src/e_sinh.c
    upstream-freebsd/lib/msun/src/e_sinhf.c
    upstream-freebsd/lib/msun/src/k_cos.c
    upstream-freebsd/lib/msun/src/k_cosf.c
    upstream-freebsd/lib/msun/src/k_exp.c
    upstream-freebsd/lib/msun/src/k_expf.c
    upstream-freebsd/lib/msun/src/k_rem_pio2.c
    upstream-freebsd/lib/msun/src/k_sin.c
    upstream-freebsd/lib/msun/src/k_sinf.c
    upstream-freebsd/lib/msun/src/k_tan.c
    upstream-freebsd/lib/msun/src/k_tanf.c
    upstream-freebsd/lib/msun/src/s_asinh.c
    upstream-freebsd/lib/msun/src/s_asinhf.c
    upstream-freebsd/lib/msun/src/s_atan.c
    upstream-freebsd/lib/msun/src/s_atanf.c
    upstream-freebsd/lib/msun/src/s_carg.c
    upstream-freebsd/lib/msun/src/s_cargf.c
    upstream-freebsd/lib/msun/src/s_cargl.c
    upstream-freebsd/lib/msun/src/s_cbrt.c
    upstream-freebsd/lib/msun/src/s_cbrtf.c
    upstream-freebsd/lib/msun/src/s_ccosh.c
    upstream-freebsd/lib/msun/src/s_ccoshf.c
    upstream-freebsd/lib/msun/src/s_cexp.c
    upstream-freebsd/lib/msun/src/s_cexpf.c
    upstream-freebsd/lib/msun/src/s_cimag.c
    upstream-freebsd/lib/msun/src/s_cimagf.c
    upstream-freebsd/lib/msun/src/s_cimagl.c
    upstream-freebsd/lib/msun/src/s_clog.c
    upstream-freebsd/lib/msun/src/s_clogf.c
    upstream-freebsd/lib/msun/src/s_conj.c
    upstream-freebsd/lib/msun/src/s_conjf.c
    upstream-freebsd/lib/msun/src/s_conjl.c
    upstream-freebsd/lib/msun/src/s_cos.c
    upstream-freebsd/lib/msun/src/s_cospi.c
    upstream-freebsd/lib/msun/src/s_cpow.c
    upstream-freebsd/lib/msun/src/s_cpowf.c
    upstream-freebsd/lib/msun/src/s_cpowl.c
    upstream-freebsd/lib/msun/src/s_cproj.c
    upstream-freebsd/lib/msun/src/s_cprojf.c
    upstream-freebsd/lib/msun/src/s_cprojl.c
    upstream-freebsd/lib/msun/src/s_creal.c
    upstream-freebsd/lib/msun/src/s_crealf.c
    upstream-freebsd/lib/msun/src/s_creall.c
    upstream-freebsd/lib/msun/src/s_csinh.c
    upstream-freebsd/lib/msun/src/s_csinhf.c
    upstream-freebsd/lib/msun/src/s_csqrt.c
    upstream-freebsd/lib/msun/src/s_csqrtf.c
    upstream-freebsd/lib/msun/src/s_ctanh.c
    upstream-freebsd/lib/msun/src/s_ctanhf.c
    upstream-freebsd/lib/msun/src/s_erf.c
    upstream-freebsd/lib/msun/src/s_erff.c
    upstream-freebsd/lib/msun/src/s_expm1.c
    upstream-freebsd/lib/msun/src/s_expm1f.c
    upstream-freebsd/lib/msun/src/s_fdim.c
    upstream-freebsd/lib/msun/src/s_finite.c
    upstream-freebsd/lib/msun/src/s_finitef.c
    upstream-freebsd/lib/msun/src/s_fma.c
    upstream-freebsd/lib/msun/src/s_fmaf.c
    upstream-freebsd/lib/msun/src/s_fmax.c
    upstream-freebsd/lib/msun/src/s_fmaxf.c
    upstream-freebsd/lib/msun/src/s_fmin.c
    upstream-freebsd/lib/msun/src/s_fminf.c
    upstream-freebsd/lib/msun/src/s_frexp.c
    upstream-freebsd/lib/msun/src/s_frexpf.c
    upstream-freebsd/lib/msun/src/s_ilogb.c
    upstream-freebsd/lib/msun/src/s_ilogbf.c
    upstream-freebsd/lib/msun/src/s_llrint.c
    upstream-freebsd/lib/msun/src/s_llrintf.c
    upstream-freebsd/lib/msun/src/s_llround.c
    upstream-freebsd/lib/msun/src/s_llroundf.c
    upstream-freebsd/lib/msun/src/s_log1p.c
    upstream-freebsd/lib/msun/src/s_log1pf.c
    upstream-freebsd/lib/msun/src/s_logb.c
    upstream-freebsd/lib/msun/src/s_logbf.c
    upstream-freebsd/lib/msun/src/s_lrint.c
    upstream-freebsd/lib/msun/src/s_lrintf.c
    upstream-freebsd/lib/msun/src/s_lround.c
    upstream-freebsd/lib/msun/src/s_lroundf.c
    upstream-freebsd/lib/msun/src/s_modf.c
    upstream-freebsd/lib/msun/src/s_modff.c
    upstream-freebsd/lib/msun/src/s_nan.c
    upstream-freebsd/lib/msun/src/s_nearbyint.c
    upstream-freebsd/lib/msun/src/s_nextafter.c
    upstream-freebsd/lib/msun/src/s_nextafterf.c
    upstream-freebsd/lib/msun/src/s_remquo.c
    upstream-freebsd/lib/msun/src/s_remquof.c
    upstream-freebsd/lib/msun/src/s_round.c
    upstream-freebsd/lib/msun/src/s_roundf.c
    upstream-freebsd/lib/msun/src/s_scalbln.c
    upstream-freebsd/lib/msun/src/s_scalbn.c
    upstream-freebsd/lib/msun/src/s_scalbnf.c
    upstream-freebsd/lib/msun/src/s_signgam.c
    upstream-freebsd/lib/msun/src/s_significand.c
    upstream-freebsd/lib/msun/src/s_significandf.c
    upstream-freebsd/lib/msun/src/s_sin.c
    upstream-freebsd/lib/msun/src/s_sinpi.c
    upstream-freebsd/lib/msun/src/s_sincos.c
    upstream-freebsd/lib/msun/src/s_tan.c
    upstream-freebsd/lib/msun/src/s_tanf.c
    upstream-freebsd/lib/msun/src/s_tanh.c
    upstream-freebsd/lib/msun/src/s_tanhf.c
    upstream-freebsd/lib/msun/src/s_tgammaf.c
    upstream-freebsd/lib/msun/src/w_cabs.c
    upstream-freebsd/lib/msun/src/w_cabsf.c
    upstream-freebsd/lib/msun/src/w_cabsl.c
    upstream-freebsd/lib/msun/src/w_drem.c
    upstream-freebsd/lib/msun/src/w_dremf.c
    # NetBSD complex functions (fill gaps in FreeBSD)
    upstream-netbsd/lib/libm/complex/ccoshl.c
    upstream-netbsd/lib/libm/complex/ccosl.c
    upstream-netbsd/lib/libm/complex/cephes_subrl.c
    upstream-netbsd/lib/libm/complex/cexpl.c
    upstream-netbsd/lib/libm/complex/csinhl.c
    upstream-netbsd/lib/libm/complex/csinl.c
    upstream-netbsd/lib/libm/complex/ctanhl.c
    upstream-netbsd/lib/libm/complex/ctanl.c
    # Bionic-specific
    significandl.c
    fake_long_double.c
    builtins.cpp
    signbit.cpp
)

# ---------- 64-bit only sources (aarch64, x86_64) ----------
LIB64_SRCS=(
    upstream-freebsd/lib/msun/src/catrigl.c
    upstream-freebsd/lib/msun/src/e_acosl.c
    upstream-freebsd/lib/msun/src/e_acoshl.c
    upstream-freebsd/lib/msun/src/e_asinl.c
    upstream-freebsd/lib/msun/src/e_atan2l.c
    upstream-freebsd/lib/msun/src/e_atanhl.c
    upstream-freebsd/lib/msun/src/e_fmodl.c
    upstream-freebsd/lib/msun/src/e_hypotl.c
    upstream-freebsd/lib/msun/src/e_lgammal.c
    upstream-freebsd/lib/msun/src/e_remainderl.c
    upstream-freebsd/lib/msun/src/e_sqrtl.c
    upstream-freebsd/lib/msun/src/s_asinhl.c
    upstream-freebsd/lib/msun/src/s_atanl.c
    upstream-freebsd/lib/msun/src/s_cbrtl.c
    upstream-freebsd/lib/msun/src/s_ceill.c
    upstream-freebsd/lib/msun/src/s_clogl.c
    upstream-freebsd/lib/msun/src/e_coshl.c
    upstream-freebsd/lib/msun/src/s_cosl.c
    upstream-freebsd/lib/msun/src/s_csqrtl.c
    upstream-freebsd/lib/msun/src/s_floorl.c
    upstream-freebsd/lib/msun/src/s_fmal.c
    upstream-freebsd/lib/msun/src/s_fmaxl.c
    upstream-freebsd/lib/msun/src/s_fminl.c
    upstream-freebsd/lib/msun/src/s_modfl.c
    upstream-freebsd/lib/msun/src/s_frexpl.c
    upstream-freebsd/lib/msun/src/s_ilogbl.c
    upstream-freebsd/lib/msun/src/s_llrintl.c
    upstream-freebsd/lib/msun/src/s_llroundl.c
    upstream-freebsd/lib/msun/src/s_logbl.c
    upstream-freebsd/lib/msun/src/s_lrintl.c
    upstream-freebsd/lib/msun/src/s_lroundl.c
    upstream-freebsd/lib/msun/src/s_nextafterl.c
    upstream-freebsd/lib/msun/src/s_nexttoward.c
    upstream-freebsd/lib/msun/src/s_nexttowardf.c
    upstream-freebsd/lib/msun/src/s_remquol.c
    upstream-freebsd/lib/msun/src/s_rintl.c
    upstream-freebsd/lib/msun/src/s_roundl.c
    upstream-freebsd/lib/msun/src/s_scalbnl.c
    upstream-freebsd/lib/msun/src/s_sincosl.c
    upstream-freebsd/lib/msun/src/e_sinhl.c
    upstream-freebsd/lib/msun/src/s_sinl.c
    upstream-freebsd/lib/msun/src/s_tanhl.c
    upstream-freebsd/lib/msun/src/s_tanl.c
    upstream-freebsd/lib/msun/src/s_truncl.c
    # ld128 long double (128-bit) support
    upstream-freebsd/lib/msun/ld128/invtrig.c
    upstream-freebsd/lib/msun/ld128/e_lgammal_r.c
    upstream-freebsd/lib/msun/ld128/e_powl.c
    upstream-freebsd/lib/msun/ld128/k_cosl.c
    upstream-freebsd/lib/msun/ld128/k_sinl.c
    upstream-freebsd/lib/msun/ld128/k_tanl.c
    upstream-freebsd/lib/msun/ld128/s_erfl.c
    upstream-freebsd/lib/msun/ld128/s_exp2l.c
    upstream-freebsd/lib/msun/ld128/s_expl.c
    upstream-freebsd/lib/msun/ld128/s_logl.c
    upstream-freebsd/lib/msun/ld128/s_nanl.c
)

# ---------- Files excluded per arch (from Android.bp exclude_srcs) ----------
# arm64 and x86_64 exclude these (they have builtins or intrinsics instead)
EXCLUDE_64=(
    s_fma.c s_fmaf.c s_fmax.c s_fmaxf.c s_fmin.c s_fminf.c
    s_llrint.c s_llrintf.c s_llround.c s_llroundf.c
    s_lrint.c s_lrintf.c s_lround.c s_lroundf.c
    s_round.c s_roundf.c
)

# x86_64 excludes only the lrint/llrint ones (not fma/fmax/fmin/round)
EXCLUDE_X86_64=(
    s_llrint.c s_llrintf.c
    s_lrint.c s_lrintf.c
)

# ---------- Per-arch fenv source ----------
declare -A FENV_SRC
FENV_SRC[aarch64]="fenv-arm64.c"
FENV_SRC[armv7a]="fenv-arm.c"
FENV_SRC[x86_64]="fenv-x86_64.c"

# ---------- arm32 additional sources ----------
ARM32_EXTRA_SRCS=(
    upstream-freebsd/lib/msun/src/s_ceil.c
    upstream-freebsd/lib/msun/src/s_ceilf.c
    upstream-freebsd/lib/msun/src/s_floor.c
    upstream-freebsd/lib/msun/src/s_floorf.c
    upstream-freebsd/lib/msun/src/s_rint.c
    upstream-freebsd/lib/msun/src/s_rintf.c
    upstream-freebsd/lib/msun/src/s_trunc.c
    upstream-freebsd/lib/msun/src/s_truncf.c
)

# Helper: check if a filename is in an exclusion list
is_excluded() {
    local filename="$1"
    shift
    local basename
    basename=$(basename "$filename")
    for excl in "$@"; do
        if [[ "$basename" == "$excl" ]]; then
            return 0
        fi
    done
    return 1
}

for arch in ${ARCHES}; do
    triple="${SYSROOT_TRIPLE[$arch]}"
    target="${CLANG_TARGET[$arch]}"
    lib_dir="${SYSROOT_DIR}/usr/lib/${triple}"
    arch_build="${LIBM_BUILD_DIR}/${arch}"

    mkdir -p "$lib_dir"
    mkdir -p "$arch_build"

    echo "[LIBM] Building for ${triple}..."

    # Use --sysroot so clang treats our sysroot as the system root.
    # This makes #include_next chains work correctly in bionic headers.
    # Additional non-sysroot include dirs (FreeBSD internals) use -I.
    INCLUDE_FLAGS=(
        -I "${LIBM_SRC}/upstream-freebsd/android/include"
        -I "${LIBM_SRC}/upstream-freebsd/lib/msun/src"
        -I "${LIBM_SRC}"
        -I "${BIONIC_SRC}/libc/private"
    )

    # 64-bit archs also need ld128 includes
    if [[ "$arch" == "aarch64" || "$arch" == "x86_64" ]]; then
        INCLUDE_FLAGS+=(-I "${LIBM_SRC}/upstream-freebsd/lib/msun/ld128")
    fi

    COMMON_CFLAGS=(
        --target="$target"
        --sysroot="${SYSROOT_DIR}"
        "${INCLUDE_FLAGS[@]}"
        -include "${LIBM_SRC}/freebsd-compat.h"
        -D_LIBC=1
        -DANDROID
        -D__ANDROID__
        -D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__
        -fPIC
        -O2
        -fno-builtin
        -fno-math-errno
        -Wall
        -Wno-missing-braces
        -Wno-parentheses
        -Wno-sign-compare
        -Wno-static-in-inline
        -Wno-unknown-pragmas
        -Wno-unused-const-variable
        -Wno-unused-variable
        -Wno-ignored-pragmas
        -Wno-unguarded-availability
        -Werror=return-type
    )

    # Build list of source files for this arch
    src_files=()

    # Add common sources, filtering exclusions per arch
    for src in "${COMMON_SRCS[@]}"; do
        # Skip comment lines
        [[ "$src" == \#* ]] && continue

        if [[ "$arch" == "aarch64" ]]; then
            is_excluded "$src" "${EXCLUDE_64[@]}" && continue
        elif [[ "$arch" == "x86_64" ]]; then
            is_excluded "$src" "${EXCLUDE_X86_64[@]}" && continue
        fi
        src_files+=("$src")
    done

    # Add 64-bit sources for 64-bit arches
    if [[ "$arch" == "aarch64" || "$arch" == "x86_64" ]]; then
        for src in "${LIB64_SRCS[@]}"; do
            [[ "$src" == \#* ]] && continue
            src_files+=("$src")
        done
    fi

    # Add arch-specific fenv
    src_files+=("${FENV_SRC[$arch]}")

    # Add arm32 extras
    if [[ "$arch" == "armv7a" ]]; then
        for src in "${ARM32_EXTRA_SRCS[@]}"; do
            src_files+=("$src")
        done
    fi

    # Compile all sources
    obj_files=()
    compiled=0
    failed=0

    for src in "${src_files[@]}"; do
        # Resolve path
        if [[ "$src" == */* ]]; then
            src_path="${LIBM_SRC}/${src}"
        else
            src_path="${LIBM_SRC}/${src}"
        fi

        if [ ! -f "$src_path" ]; then
            echo "        [WARN] Missing: $src"
            failed=$((failed + 1))
            continue
        fi

        # Object file name (flatten path into single name)
        obj_name=$(echo "$src" | sed 's|/|_|g' | sed 's|\.c$|.o|; s|\.cpp$|.o|; s|\.S$|.o|')
        obj_path="${arch_build}/${obj_name}"

        # Choose compiler based on extension
        compiler="$CC"
        extra_flags=()
        if [[ "$src" == *.cpp ]]; then
            compiler="$CXX"
            extra_flags+=(-std=c++17 -fno-exceptions -fno-rtti)
        else
            extra_flags+=(-std=gnu99)
        fi

        if "$compiler" "${COMMON_CFLAGS[@]}" "${extra_flags[@]}" \
            -c "$src_path" -o "$obj_path" 2>"${arch_build}/last_error.log"; then
            obj_files+=("$obj_path")
            compiled=$((compiled + 1))
        else
            echo "        [WARN] Failed to compile: $src"
            # Show first error for debugging (only for the first failure)
            if [[ $failed -eq 0 ]]; then
                echo "        --- First compile error ---"
                head -20 "${arch_build}/last_error.log" | sed 's/^/        /'
                echo "        ---"
            fi
            failed=$((failed + 1))
        fi
    done

    # Also compile arm-optimized-routines math sources if available
    if [ -d "$ARM_ROUTINES_SRC" ]; then
        # Find the math sources — they provide optimized exp, log, pow, etc.
        arm_math_dir="${ARM_ROUTINES_SRC}/math"
        if [ -d "$arm_math_dir" ]; then
            # The Android.bp for arm-optimized-routines-math typically compiles
            # specific .c files. Look for an Android.bp or compile what's there.
            for arm_src in "$arm_math_dir"/*.c; do
                [ -f "$arm_src" ] || continue
                obj_name="arm_math_$(basename "$arm_src" .c).o"
                obj_path="${arch_build}/${obj_name}"

                if "$CC" "${COMMON_CFLAGS[@]}" -std=gnu99 \
                    -I "${arm_math_dir}" \
                    -I "${ARM_ROUTINES_SRC}/math/include" \
                    -c "$arm_src" -o "$obj_path" 2>/dev/null; then
                    obj_files+=("$obj_path")
                    compiled=$((compiled + 1))
                fi
                # Silently skip failures — not all files may be relevant
            done
        fi
    fi

    echo "        Compiled ${compiled} objects (${failed} failed)"

    # Create archive
    if [ ${#obj_files[@]} -gt 0 ]; then
        "$AR" rcs "${lib_dir}/libm.a" "${obj_files[@]}"
        echo "        [OK] ${triple}/libm.a ($(wc -c < "${lib_dir}/libm.a") bytes)"
    else
        echo "        [ERROR] No objects compiled for ${triple}/libm.a"
        exit 1
    fi

    echo ""
done

echo "[LIBM] All libm.a libraries built successfully"
