#!/bin/bash
set -euo pipefail

RECOVERY_IMG="$1"
OUTPUT_DIR="output"

echo "🔧 patch.sh: patching $RECOVERY_IMG"
mkdir -p "$OUTPUT_DIR"

./magiskboot unpack "$RECOVERY_IMG"

if [ ! -f "ramdisk.cpio" ]; then
    echo "❌ ramdisk.cpio not found after unpacking"
    exit 1
fi

mkdir -p ramdisk
cd ramdisk
cpio -idm < ../ramdisk.cpio

mkdir -p system/bin

for rc_file in *.rc; do
    if [ -f "$rc_file" ]; then
        echo "🔧 Patching $rc_file"
        if ! grep -q "service fastbootd" "$rc_file"; then
            cat >> "$rc_file" << 'RCEOF'

service fastbootd /system/bin/fastbootd
    class core
    user root
    group root system
    disabled
    seclabel u:r:fastbootd:s0

on property:sys.usb.config=fastboot
    start fastbootd

RCEOF
        fi
    fi
done

for fstab_file in fstab.*; do
    if [ -f "$fstab_file" ]; then
        echo "🔧 Patching $fstab_file for dynamic partitions"
        if ! grep -q "system.*logical" "$fstab_file"; then
            echo "/dev/block/mapper/system /system ext4 ro,barrier=1,discard wait,logical,first_stage_mount" >> "$fstab_file"
        fi
        if ! grep -q "vendor.*logical" "$fstab_file"; then
            echo "/dev/block/mapper/vendor /vendor ext4 ro,barrier=1,discard wait,logical,first_stage_mount" >> "$fstab_file"
        fi
        if ! grep -q "product.*logical" "$fstab_file"; then
            echo "/dev/block/mapper/product /product ext4 ro,barrier=1,discard wait,logical,first_stage_mount" >> "$fstab_file"
        fi
    fi
done

find . | cpio -o -H newc > ../ramdisk.cpio.new
cd ..
mv ramdisk.cpio.new ramdisk.cpio

./magiskboot repack "$RECOVERY_IMG" "$OUTPUT_DIR/recovery-patched.img"

if [ -f "$OUTPUT_DIR/recovery-patched.img" ]; then
    SIZE=$(stat -c%s "$OUTPUT_DIR/recovery-patched.img")
    echo "✅ Patched recovery created: $SIZE bytes"
else
    echo "❌ Failed to create patched recovery"
    exit 1
fi

echo "🎉 Patching completed successfully!"
