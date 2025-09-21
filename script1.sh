#!/usr/bin/env bash
set -euo pipefail

# Inputs from the workflow env
: "${AIK_DIR:?missing AIK_DIR}"
: "${WORK_DIR:?missing WORK_DIR}"

echo "🔧 patch.sh: starting"
echo "AIK_DIR=$AIK_DIR"
echo "WORK_DIR=$WORK_DIR"

# Figure out ramdisk dirs created by AIK
RAMDISK_DIR=""
VENDOR_RAMDISK_DIR=""

if [ -d "$WORK_DIR/ramdisk" ]; then
  RAMDISK_DIR="$WORK_DIR/ramdisk"
fi
if [ -d "$WORK_DIR/vendor_ramdisk" ]; then
  VENDOR_RAMDISK_DIR="$WORK_DIR/vendor_ramdisk"
fi

if [ -z "$RAMDISK_DIR" ] && [ -z "$VENDOR_RAMDISK_DIR" ]; then
  echo "❌ No ramdisk directories found. Did AIK unpack correctly?"
  ls -al "$WORK_DIR" || true
  exit 1
fi

# Helper: in-place sed that works on busybox and GNU sed
sedi() {
  local expr="$1" file="$2"
  if sed --version >/dev/null 2>&1; then
    sed -i "$expr" "$file"
  else
    sed -i "$expr" "$file"
  fi
}

mark_patched() {
  local dir="$1"
  mkdir -p "$dir/etc" || true
  echo "patched_by=github_actions" > "$dir/etc/recovery_patch.meta"
  echo "patched_at=$(date -u +%FT%TZ)" >> "$dir/etc/recovery_patch.meta"
}

neutralize_recovery_restore() {
  local dir="$1"
  # Common scripts/services that trigger restoring stock recovery on boot
  # We don’t nuke blindly; we rename to .bak so a human can undo.
  echo "   - searching for install-recovery and recovery-from-boot in $dir"
  grep -RIl --exclude-dir=".git" -e "install-recovery.sh" -e "recovery-from-boot.p" "$dir" 2>/dev/null | while read -r f; do
    echo "     * neuter: $f"
    cp -a "$f" "$f.bak" || true
    sedi 's/\(install-recovery\.sh\)/\1.disabled/g' "$f" || true
    sedi 's/\(recovery-from-boot\.p\)/\1.disabled/g' "$f" || true
  done

  # If the files actually exist in ramdisk, rename them
  for cand in \
      "$dir/sbin/install-recovery.sh" \
      "$dir/bin/install-recovery.sh" \
      "$dir/etc/install-recovery.sh" \
      "$dir/sbin/recovery-from-boot.p" \
      "$dir/bin/recovery-from-boot.p" \
      "$dir/etc/recovery-from-boot.p"
  do
    if [ -f "$cand" ]; then
      echo "     * rename payload: $cand -> ${cand}.disabled"
      mv -f "$cand" "${cand}.disabled"
    fi
  done
}

tweak_default_props() {
  local dir="$1"
  # Non-destructive cosmetic tag to prove patch ran
  for f in "$dir/default.prop" "$dir/system/etc/prop.default" "$dir/etc/prop.default"; do
    if [ -f "$f" ]; then
      echo "   - tagging $f"
      echo "# patched_via_actions=$(date -u +%Y%m%dT%H%M%SZ)" >> "$f" || true
    fi
  done
}

fix_perms() {
  local dir="$1"
  echo "   - chmod basics under $dir"
  find "$dir" -type f -name "*.sh" -exec chmod 0755 {} + || true
  [ -d "$dir/sbin" ] && chmod 0755 "$dir/sbin"/* 2>/dev/null || true
}

apply_to_dir() {
  local d="$1"
  [ -z "$d" ] && return 0
  [ -d "$d" ] || return 0
  echo "➡️ applying tweaks to: $d"
  mark_patched "$d"
  neutralize_recovery_restore "$d"
  tweak_default_props("$d") || tweak_default_props "$d"
  fix_perms "$d"
}

apply_to_dir "$RAMDISK_DIR"
apply_to_dir "$VENDOR_RAMDISK_DIR"

echo "✅ patch.sh: done"
