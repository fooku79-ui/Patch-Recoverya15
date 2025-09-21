#!/usr/bin/env bash
set -euo pipefail

log=_debug.txt
{
  echo "== PATCH START =="
  echo "date: $(date -Iseconds)"
  echo "env PARTITION_NAME=${PARTITION_NAME:-}"
  echo "env PARTITION_SIZE=${PARTITION_SIZE:-<auto>}"
} | tee -a "$log"

PARTITION_NAME="${PARTITION_NAME:-recovery}"
PARTITION_SIZE="${PARTITION_SIZE:-}"

WORK=./d
rm -rf "$WORK"
mkdir -p "$WORK"
pushd "$WORK" >/dev/null

echo "==> Unpacking ../r.img" | tee -a "../$log"
../magiskboot unpack ../r.img | tee -a "../$log" || {
  echo "ERROR: magiskboot failed to parse r.img (not a boot/vendor_boot/recovery?)" | tee -a "../$log"
  exit 10
}

echo "==> Inspecting unpack results" | tee -a "../$log"
ls -lah | tee -a "../$log" || true

# Detect ramdisk payload
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

if [[ -z "${RAMDISK}" ]]; then
  echo "WARN: No ramdisk found (recovery-as-boot/vendor_boot likely). Proceeding without ramdisk mods." | tee -a "../$log"
else
  echo "==> Found ramdisk: ${RAMDISK}" | tee -a "../$log"

  TMPRD=./_rd
  rm -rf "$TMPRD"; mkdir "$TMPRD"

  case "$RAMDISK" in
    *.gz)  gzip -dc "$RAMDISK" | (cd "$TMPRD" && cpio -idm --no-absolute-filenames) ;;
    *.lz4) lz4 -dq "$RAMDISK" - | (cd "$TMPRD" && cpio -idm --no-absolute-filenames) ;;
    *.cpio) (cd "$TMPRD" && cpio -idm --no-absolute-filenames < "../$RAMDISK") ;;
  esac

  # === Put your edits inside $TMPRD if needed ===
  # Example:
  # if [[ -f "$TMPRD/default.prop" ]]; then
  #   echo "persist.example.flag=1" >> "$TMPRD/default.prop" || true
  # fi

  echo "==> Repacking ramdisk" | tee -a "../$log"
  case "$RAMDISK" in
    *.gz)
      (cd "$TMPRD" && find . | cpio -o -H newc | gzip -9) > ramdisk.cpio.gz
      mv -f ramdisk.cpio.gz .
      ;;
    *.lz4)
      (cd "$TMPRD" && find . | cpio -o -H newc) | lz4 -q
