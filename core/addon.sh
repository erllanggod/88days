#!/usr/bin/env bash
set -euo pipefail

ADDON="${1:?usage: core/addon.sh <addon> <kernel_dir>}"
KSRC="${2:?kernel dir}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$PROJ/addons/$ADDON"

[[ -d "$DIR/kabi" ]] || { echo "addon '$ADDON' has no kabi/ directory" >&2; exit 1; }

shopt -s nullglob
PATCHES=("$DIR"/kabi/*.patch)
[[ ${#PATCHES[@]} -gt 0 ]] || { echo "addon '$ADDON': no patches" >&2; exit 1; }

for p in "${PATCHES[@]}"; do
  git -C "$KSRC" apply --check "$p" 2>/dev/null || { echo "addon '$ADDON': ${p##*/} does not apply cleanly" >&2; exit 1; }
  git -C "$KSRC" apply "$p"
  echo "   applied ${p##*/}"
done
