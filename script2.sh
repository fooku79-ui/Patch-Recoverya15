#!/usr/bin/env bash
set -euo pipefail

PARTITION_NAME="${PARTITION_NAME:-recovery}"
PARTITION_SIZE="${PARTITION_SIZE:-}"

WORK=./d
rm -rf "$WORK"
mkdir -p "$WORK"
pushd "$WORK" >/dev/null

echo "==> Unpacking ../r.img"
../magiskboot unpack ../r.img

echo "==> Inspecting unpack results"
ls -lah || true

# Detect ramdisk payload if present
RAMDISK=""
if [[ -f ramdisk.cpio ]]; then
  RAMDISK="ramdisk.cpio"
elif comp=$(ls ramdisk.cpio.* 2>/dev/null | head -n1); then
  RAMDISK="$comp"
elif comp=$(ls vendor_ramdisk/*recovery*.cpio* 2>/dev/null | head -n1); then
  RAMDISK="$comp"
elif comp=$(ls vendor_ramdisk/*.cpio* 2>/dev/null | head -n1); then
  RAMDISK="$comp"
fi

if [[ -n "${RAMDISK}" ]]; then
  echo "==> Found ramdisk: ${RAMDISK}"
  TMPRD=./_rd
  rm -rf "$TMPRD"; mkdir "$TMPRD"
  case "$RAMDISK" in
    *.gz)  gzip -dc "$RAMDISK" | (cd "$TMPRD" && cpio -idm --no-absolute-filenames) ;;
    *.lz4) lz4 -dq "$RAMDISK" - | (cd "$TMPRD" && cpio -idm --no-absolute-filenames) ;;
    *.cpio) (cd "$TMPRD" && cpio -idm --no-absolute-filenames < "../$RAMDISK") ;;
  esac

  # ---- OPTIONAL MODS (example) ----
  # if [[ -f "$TMPRD/default.prop" ]]; then
  #   echo "persist.example.flag=1" >> "$TMPRD/default.prop" || true
  # fi
  # ---------------------------------

  echo "==> Repacking ramdisk"
  case "$RAMDISK" in
    *.gz)   (cd "$TMPRD" && find . | cpio -o -H newc | gzip -9) > ramdisk.cpio.gz ;;
    *.lz4)  (cd "$TMPRD" && find . | cpio -o -H newc) | lz4 -q -l -9 - ramdisk.cpio.lz4 ;;
    *.cpio) (cd "$TMPRD" && find . | cpio -o -H newc) > ramdisk.cpio ;;
  esac
else
  echo "WARN: No ramdisk found (recovery-as-boot/vendor_boot likely). Proceeding without ramdisk mods."
fi

echo "==> Repacking full image"
../magiskboot repack ../r.img

[[ -f new-boot.img ]] || { echo "ERROR: new-boot.img not created"; exit 1; }

mv -f new-boot.img ../recovery-patched.img
popd >/dev/null

echo "==> Patched image at ./recovery-patched.img"
test -s recovery-patched.img

# === AVB footer ===
SIZE=$(stat -c%s recovery-patched.img)
if [[ -n "$PARTITION_SIZE" ]]; then
  ROUND="$PARTITION_SIZE"
  if (( SIZE > ROUND )); then
    echo "ERROR: Image ($SIZE) larger than provided PARTITION_SIZE ($ROUND)"; exit 1
  fi
else
  # round up to nearest 4MiB
  ROUND=$(( ((SIZE + 4194303) / 4194304) * 4194304 ))
fi

echo "Image size: $SIZE bytes; using partition_size: $ROUND"
echo "Partition name: $PARTITION_NAME"

./avbtool extract_public_key --key phh.pem --output phh.pub.bin

./avbtool add_hash_footer \
  --image recovery-patched.img \
  --partition_name "$PARTITION_NAME" \
  --partition_size "$ROUND" \
  --key phh.pem \
  --algorithm SHA256_RSA4096

echo "==> AVB footer added. Done."
