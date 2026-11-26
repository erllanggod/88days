#!/usr/bin/env bash
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

patch_glibc() {
  local g="$HOME/.neutron-tc/glibc" pe base idx pkg name
  rm -rf "$g"; mkdir -p "$g"
  pe="$(mktemp -d)"
  curl -fsSL --retry 3 "https://github.com/NixOS/patchelf/releases/download/0.18.0/patchelf-0.18.0-x86_64.tar.gz" | tar -xz -C "$pe"

  for base in https://geo.mirror.pkgbuild.com/core/os/x86_64 https://mirrors.kernel.org/archlinux/core/os/x86_64; do
    idx="$(curl -fsSL --retry 3 "$base/" || true)"
    [ -n "$idx" ] || { echo "mirror $base unreachable" >&2; continue; }
    for name in glibc gcc-libs; do
      pkg="$(grep -oE "${name}-[0-9][^\"<> ]*-x86_64\.pkg\.tar\.zst" <<<"$idx" | sort -uV | tail -1)"
      [ -n "$pkg" ] || { echo "no $name package on $base" >&2; continue 2; }
      echo "fetching $pkg"
      curl -fsSL --retry 3 -o "$pe/$pkg" "$base/$pkg" || continue 2
      tar --zstd -C "$g" -xf "$pe/$pkg"
    done
    [ -e "$g/usr/lib/ld-linux-x86-64.so.2" ] && break
  done
  [ -e "$g/usr/lib/ld-linux-x86-64.so.2" ] || { echo "could not fetch glibc from any mirror" >&2; return 1; }
  ln -sfn "$g/usr/lib" "$g/usr/lib64"

  local dir bin
  for dir in "$g" "$PWD"; do
    find "$dir" -type f -exec file {} + | grep 'ELF .* interpreter' | cut -d: -f1 | while read -r bin; do
      "$pe/bin/patchelf" --set-rpath "$g/usr/lib" --force-rpath --set-interpreter "$g/usr/lib/ld-linux-x86-64.so.2" "$bin"
    done
  done
  rm -rf "$pe"
}

retry ./antman --patch=glibc || patch_glibc

./bin/clang --version | head -1
