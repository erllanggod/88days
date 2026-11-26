#!/usr/bin/env bash
# Neutron clang, always the latest build (antman pulls whatever is current).
set -euo pipefail

DEST="${1:-.build/clang}"
mkdir -p "$DEST"
cd "$DEST"

curl -fsSL --max-time 60 --retry 3 -o antman https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman
chmod +x antman

retry() {
  local n
  for n in 1 2 3; do
    "$@" && return 0
    echo "retry $n/3: $*" >&2; sleep 15
  done
  return 1
}
retry ./antman -S
retry ./antman --patch=glibc

./bin/clang --version | head -1
