#!/bin/bash
set -euxo pipefail

echo "🔧 script2.sh: patching recovery for fastbootd support"

# Extract ramdisk
echo "📦 Extracting ramdisk..."
mkdir -p ramdisk
cd ramdisk
cpio -idm < ../ramdisk.cpio

# Create system/bin directory for fastbootd
mkdir -p system/bin

echo "🔧 Patching init.recovery files for fastbootd support..."

# Patch init.recovery.*.rc files
for rc_file in init.recovery*.rc; do
    if [ -f "$rc_file" ]; then
        echo "🔧 Patching $rc_file"
        
        # Add fastbootd service if not already present
        if ! grep -q "service fastbootd" "$rc_file"; then
            cat >> "$rc_file" << 'EOF'

service fastbootd /system/bin/fastbootd
    class core
    user root
    group root system
    disabled
    seclabel u:r:fastbootd:s0

on property:sys.usb.config=fastboot
    start fastbootd

on property:sys.usb.ffs.ready=1 && property:sys.usb.config=fastboot
    write /sys/class/android_usb/android0/enable 0
    write /sys/class/android_usb/android0/idVendor 18d1
    write /sys/class/android_usb/android0/idProduct d00d
    write /sys/class/android_usb/android0/functions fastboot
    write /sys/class/android_usb/android0/enable 1

EOF
            echo "✅ Added fastbootd service to $rc_file"
        else
            echo "ℹ️  fastbootd service already exists in $rc_file"
        fi
    fi
done

# Also check for generic init.rc files
for rc_file in init.rc; do
    if [ -f "$rc_file" ]; then
        echo "🔧 Checking $rc_file"
        if ! grep -q "service fastbootd" "$rc_file"; then
            cat >> "$rc_file" << 'EOF'

service fastbootd /system/bin/fastbootd
    class core
    user root
    group root system
    disabled
    seclabel u:r:fastbootd:s0

on property:sys.usb.config=fastboot
    start fastbootd

EOF
            echo "✅ Added fastbootd service to $rc_file"
        fi
    fi
done

echo "🔧 Patching fstab files for dynamic partition support..."

# Patch fstab files for dynamic partitions
for fstab_file in fstab.*; do
    if [ -f "$fstab_file" ]; then
        echo "🔧 Patching $fstab_file for dynamic partitions"
        
        # Add logical partition entries if not present
        if ! grep -q "system.*logical" "$fstab_file"; then
            echo "/dev/block/mapper/system /system ext4 ro,barrier=1,discard wait,logical,first_stage_mount" >> "$fstab_file"
            echo "✅ Added system logical partition to $fstab_file"
        fi
        
        if ! grep -q "vendor.*logical" "$fstab_file"; then
            echo "/dev/block/mapper/vendor /vendor ext4 ro,barrier=1,discard wait,logical,first_stage_mount" >> "$fstab_file"
            echo "✅ Added vendor logical partition to $fstab_file"
        fi
        
        if ! grep -q "product.*logical" "$fstab_file"; then
            echo "/dev/block/mapper/product /product ext4 ro,barrier=1,discard wait,logical,first_stage_mount" >> "$fstab_file"
            echo "✅ Added product logical partition to $fstab_file"
        fi
        
        if ! grep -q "odm.*logical" "$fstab_file"; then
            echo "/dev/block/mapper/odm /odm ext4 ro,barrier=1,discard wait,logical,first_stage_mount" >> "$fstab_file"
            echo "✅ Added odm logical partition to $fstab_file"
        fi
    fi
done

echo "🔧 Enabling fastboot mode in recovery menu..."

# Patch recovery UI for fastboot mode (if ui.xml exists)
if [ -f "ui.xml" ]; then
    if ! grep -q "fastboot" "ui.xml"; then
        sed -i 's/<\/recovery>/<item name="fastboot_mode">Enter fastboot mode<\/item><\/recovery>/' ui.xml 2>/dev/null || true
        echo "✅ Added fastboot mode to recovery menu"
    fi
fi

echo "📦 Repacking ramdisk..."

# Repack ramdisk
find . | cpio -o -H newc > ../ramdisk.cpio.new
cd ..
mv ramdisk.cpio.new ramdisk.cpio

echo "📦 Repacking recovery image..."

# Repack the recovery image
./magiskboot repack recovery.img recovery-patched.img

if [ -f "recovery-patched.img" ]; then
    SIZE=$(stat -c%s "recovery-patched.img")
    echo "✅ Patched recovery created: $SIZE bytes"
    
    # Verify the patched image has valid magic
    MAGIC_PATCHED=$(hexdump -C "recovery-patched.img" | head -1 | awk '{print $2$3$4$5$6$7$8$9}' || echo "")
    if [[ "$MAGIC_PATCHED" == "414e44524f494421" ]]; then
        echo "✅ Patched image has valid Android boot magic"
    else
        echo "⚠️  Warning: Patched image may not have valid boot magic"
    fi
else
    echo "❌ Failed to create patched recovery"
    exit 1
fi

echo "🎉 script2.sh completed successfully!"
