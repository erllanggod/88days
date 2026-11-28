#!/usr/bin/env bash
set -euo pipefail

# ClangBuiltLinux: kernel.org slim LLVM toolchains.
# CBL_VERSION is "latest" (highest x.y.z published on kernel.org) or an exact version such as 22.1.8.
DEST="${1:-.build/clang}"
CBL_VERSION="${CBL_VERSION:-latest}"
BASE="https://cdn.kernel.org/pub/tools/llvm"

if [[ "$CBL_VERSION" == latest ]]; then
  idx=""
  for u in "$BASE/" https://mirrors.kernel.org/pub/tools/llvm/ https://www.kernel.org/pub/tools/llvm/; do
    idx="$(curl -fsSL --max-time 60 --retry 3 "$u" || true)"
    [[ -n "$idx" ]] && break
  done
  CBL_VERSION="$(grep -oE 'llvm-[0-9]+\.[0-9]+\.[0-9]+-x86_64\.tar\.xz' <<<"$idx" | sed -E 's/^llvm-(.*)-x86_64\.tar\.xz$/\1/' | sort -uV | tail -1)"
  [[ -n "$CBL_VERSION" ]] || { echo "cbl: cannot resolve the latest version from kernel.org" >&2; exit 1; }
fi
[[ "$CBL_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "cbl: bad version '$CBL_VERSION'" >&2; exit 1; }
echo "cbl: using LLVM $CBL_VERSION"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fL --retry 5 --retry-delay 15 --retry-all-errors --max-time 900 -o "$TMP/llvm.tar.xz" \
  "$BASE/files/llvm-$CBL_VERSION-x86_64.tar.xz" || { echo "cbl: download of $CBL_VERSION failed (does that version exist?)" >&2; exit 1; }

bin="$(tar -tJf "$TMP/llvm.tar.xz" | grep -m1 -E '(^|/)bin/clang$' || true)"
[[ -n "$bin" ]] || { echo "cbl: bin/clang not found in the tarball" >&2; exit 1; }
strip=$(( $(tr '/' '\n' <<<"$bin" | wc -l) - 2 ))
mkdir -p "$DEST"
tar -xJf "$TMP/llvm.tar.xz" -C "$DEST" --strip-components="$strip"
for t in clang ld.lld llvm-ar llvm-strip llvm-objcopy; do
  [[ -x "$DEST/bin/$t" ]] || { echo "cbl: $t missing from the toolchain" >&2; exit 1; }
done
"$DEST/bin/clang" --version | head -1
