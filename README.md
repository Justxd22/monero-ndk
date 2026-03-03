# monero-ndk

Build a minimal, reproducible Android NDK toolchain entirely from source.

## Purpose

Drop-in replacement for Google's prebuilt NDK, built from pinned AOSP sources.
Used by [monero_c](https://github.com/MrCyjaneK/monero_c) for reproducible Android builds.

## Quick Start

```bash
# Fetch all sources (shallow, pinned commits)
make fetch

# Build everything
make all

# Verify output
make verify

# Or step by step:
make llvm       # Build LLVM/Clang (~1-2 hours)
make sysroot    # Assemble bionic sysroot (~1 min)
make libcxx     # Cross-compile libc++ (~10 min)
make assemble   # Assemble final NDK layout (~1 min)
make verify     # Run verification tests
```

## Requirements

- Linux x86_64 host
- 16 GB RAM minimum
- ~15 GB free disk space
- CMake >= 3.20
- Ninja
- Python 3
- Go (for simplybs integration, optional)

## Output

Produces a standalone toolchain at `output/` compatible with:
- monero_c / simplybs build system
- OpenSSL's Android detection (`15-android.conf`)
- Standard Android cross-compilation

## Supported Targets

| Architecture | Triplet | API Level |
|---|---|---|
| ARM64 | aarch64-linux-android | 21 |
| ARM32 | armv7a-linux-androideabi | 21 |
| x86_64 | x86_64-linux-android | 21 |

## License

Same as AOSP components: Apache 2.0 / LLVM License
