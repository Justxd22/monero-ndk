#!/usr/bin/env python3
"""Deduplicate identical files by replacing duplicates with symlinks.
Originally from simplybs (MrCyjaneK). Reduces NDK output size significantly."""

import os
import hashlib
import sys

def sha256sum(path, blocksize=65536):
    """Return SHA-256 checksum of a file."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            data = f.read(blocksize)
            if not data:
                break
            h.update(data)
    return h.hexdigest()

def dedupe(root):
    seen = {}
    deduped = 0
    saved_bytes = 0

    for dirpath, dirnames, filenames in os.walk(root):
        for name in filenames:
            path = os.path.join(dirpath, name)

            if os.path.islink(path):
                continue

            if not os.path.isfile(path):
                continue

            try:
                checksum = sha256sum(path)
                file_size = os.path.getsize(path)
            except Exception as e:
                print(f"Cannot read {path}: {e}")
                continue

            if checksum not in seen:
                seen[checksum] = path
            else:
                original = seen[checksum]

                try:
                    os.remove(path)
                except Exception as e:
                    print(f"Cannot delete {path}: {e}")
                    continue

                try:
                    os.symlink(os.path.relpath(original, os.path.dirname(path)), path)
                    deduped += 1
                    saved_bytes += file_size
                except Exception as e:
                    print(f"Cannot create symlink at {path}: {e}")

    print(f"Deduplicated {deduped} files, saved {saved_bytes / 1024 / 1024:.1f} MB")

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <directory>")
        sys.exit(1)

    root = sys.argv[1]
    dedupe(root)

if __name__ == "__main__":
    main()
