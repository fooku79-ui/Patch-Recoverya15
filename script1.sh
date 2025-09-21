#!/usr/bin/env bash
set -euo pipefail

# Verify essentials
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

need curl
need openssl
need cpio
need gzip
need lz4
need ./magiskboot
need ./avbtool

test -s r.img || { echo "r.img missing (expected downloaded image)."; exit 1; }
echo "Preflight OK. r.img size: $(stat -c%s r.img) bytes"
