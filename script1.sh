#!/bin/bash
set -euxo pipefail

RECOVERY_IMG="recovery.img"

echo "🔍 script1.sh: validating and preparing $RECOVERY_IMG"

if [ ! -f "$RECOVERY_IMG" ]; then
    echo "❌ File $RECOVERY_IMG does not exist"
    exit 1
fi

# Check file type and decompress if needed
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

# Validate Android boot image magic
MAGIC=$(hexdump -C "$RECOVERY_IMG" | head -1 | awk '{print $2$3$4$5$6$7$8$9}' || echo "")
if [[ "$MAGIC" == "414e44524f494421" ]]; then
    echo "✅ Found Android boot image magic (ANDROID!)"
else
    echo "❌ Not detecting Android boot image magic in $RECOVERY_IMG"
    echo "Magic bytes found: $MAGIC (expected: 414e44524f494421)"
    echo "First 32 bytes of file:"
    hexdump -C "$RECOVERY_IMG" | head -2
    exit 1
fi

# Unpack the recovery image using magiskboot
echo "📦 Unpacking recovery image..."
./magiskboot unpack "$RECOVERY_IMG"

if [ ! -f "ramdisk.cpio" ]; then
    echo "❌ ramdisk.cpio not found after unpacking"
    exit 1
fi

echo "✅ script1.sh completed successfully"
