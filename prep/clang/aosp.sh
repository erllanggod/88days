#!/usr/bin/env bash
set -euo pipefail

: "${CLANG_URL:?CLANG_URL is empty}"
DEST="${1:-.build/clang}"

mkdir -p "$DEST"
curl -fsSL --retry 3 "$CLANG_URL" | tar -xz -C "$DEST"
cat "$DEST/AndroidVersion.txt" || true
grep -q r510928 "$DEST/AndroidVersion.txt"
"$DEST/bin/clang" --version | head -1
