#!/usr/bin/env bash
set -euo pipefail

: "${RECOVERY_IMG:?missing RECOVERY_IMG}"

echo "🔍 validate.sh: checking $RECOVERY_IMG"
file "$RECOVERY_IMG" || true

if ! strings "$RECOVERY_IMG" | grep -qi -e ANDROID -e SEANDROID -e "ANDROID!"; then
  echo "❌ Not detecting Android boot image magic in $RECOVERY_IMG"
  exit 1
fi

# Optional: print header with AIK if available
if command -v unpackbootimg >/dev/null 2>&1; then
  echo "ℹ️ unpackbootimg present; dumping header"
  unpackbootimg -i "$RECOVERY_IMG" || true
fi

echo "✅ validate.sh: basic checks passed"
