#!/bin/bash
set -euo pipefail

RECOVERY_IMG="$1"
echo "🔍 validate.sh: checking $RECOVERY_IMG"

if [ ! -f "$RECOVERY_IMG" ]; then
    echo "❌ File $RECOVERY_IMG does not exist"
    exit 1
fi

FILE_TYPE=$(file "$RECOVERY_IMG")
echo "File type: $FILE_TYPE"

if [[ "$FILE_TYPE" == *"LZ4"* ]]; then
    echo "🔧 Detected LZ4 compressed file, decompressing..."
    lz4 -d "$RECOVERY_IMG" "${RECOVERY_IMG}.decompressed"
    mv "${RECOVERY_IMG}.decompressed" "$RECOVERY_IMG"
fi

if [[ "$FILE_TYPE" == *"XZ"* ]] || [[ "$FILE_TYPE" == *"LZMA"* ]]; then
    echo "🔧 Detected XZ/LZMA compressed file, decompressing..."
    xz -d "$RECOVERY_IMG"
fi

if [[ "$FILE_TYPE" == *"gzip"* ]]; then
    echo "🔧 Detected gzip compressed file, decompressing..."
    gunzip "$RECOVERY_IMG"
fi

MAGIC=$(xxd -l 8 -p "$RECOVERY_IMG" 2>/dev/null || true)
if [[ "$MAGIC" == "414e44524f494421" ]]; then
    echo "✅ Found Android boot image magic (ANDROID!)"
    exit 0
fi

echo "❌ Not detecting Android boot image magic in $RECOVERY_IMG"
echo "Magic bytes found: $MAGIC (expected: 414e44524f494421)"
echo "First 32 bytes of file:"
xxd -l 32 "$RECOVERY_IMG" || true
exit 1
