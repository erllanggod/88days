#!/usr/bin/env bash
set -euo pipefail

CMD="${1:?usage: main/etc/root/load.sh apply|required|makevars|probes|label|nomount-version <root> [kernel_dir]}"
ROOT="${2:?root name}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HERE="$PROJ/main/etc/root"
WORK="${ROOT_WORK:-$PROJ/.build/root}"

[[ -f "$HERE/ksu/$ROOT/$ROOT.sh" ]] || { echo "unknown root '$ROOT' (no $HERE/ksu/$ROOT/$ROOT.sh)" >&2; exit 1; }
REQUIRED=(); PROBES=(); ROOT_MAKEVARS=()
source "$HERE/susfs/susfs.sh"
source "$HERE/ksu/$ROOT/$ROOT.sh"
ROOT_REQUIRED=("${REQUIRED[@]}"); ROOT_PROBES=("${PROBES[@]}")
source "$HERE/nomount/nomount.sh"
REQUIRED=("${ROOT_REQUIRED[@]}" "${REQUIRED[@]}"); PROBES=("${ROOT_PROBES[@]}" "${PROBES[@]}")

fetch_pin() {
  local url="$1" ref="$2" dir="$3" depth="$4"
  if [[ -d "$dir/.git" && "$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)" == "$ref" ]]; then return 0; fi
  rm -rf "$dir"; mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$url"
  if [[ "$depth" == shallow ]]; then
    git -C "$dir" fetch -q --depth=1 origin "$ref"
  else
    git -C "$dir" fetch -q --filter=blob:none --tags origin "$ref"
  fi
  git -C "$dir" checkout -q FETCH_HEAD
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$ref" ]] || { echo "pin mismatch for $url" >&2; exit 1; }
}

case "$CMD" in
  apply)
    KSRC="${3:?kernel dir}"
    fetch_pin "$SUSFS_REPO" "$SUSFS_REF" "$WORK/susfs" shallow
    patch="$HERE/susfs/$SUSFS_PATCH.patch"
    git -C "$KSRC" apply --check "$patch" 2>/dev/null || { echo "susfs: $SUSFS_PATCH.patch does not apply cleanly" >&2; exit 1; }
    git -C "$KSRC" apply --whitespace=nowarn "$patch"
    echo "   applied $SUSFS_PATCH.patch (SUSFS $SUSFS_VERSION)"
    for f in "${SUSFS_FILES[@]}"; do
      cp "$WORK/susfs/kernel_patches/$f" "$KSRC/$f"
    done
    echo "   copied ${#SUSFS_FILES[@]} SUSFS source files"

    fetch_pin "$ROOT_REPO" "$ROOT_REF" "$WORK/$ROOT" full
    [[ -d "$WORK/$ROOT/kernel" ]] || { echo "$ROOT: kernel/ missing in checkout" >&2; exit 1; }
    ln -sfn "$WORK/$ROOT/kernel" "$KSRC/drivers/kernelsu"
    grep -q kernelsu "$KSRC/drivers/Makefile" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KSRC/drivers/Makefile"
    grep -q 'drivers/kernelsu/Kconfig' "$KSRC/drivers/Kconfig" || sed -i '/endmenu/i source "drivers/kernelsu/Kconfig"' "$KSRC/drivers/Kconfig"
    grep -q 'drivers/kernelsu/Kconfig' "$KSRC/drivers/Kconfig" || { echo "failed to hook drivers/Kconfig" >&2; exit 1; }
    echo "   integrated $ROOT_LABEL @ ${ROOT_REF:0:8}"

    rm -rf "$WORK/nomount"
    git clone -q --depth 1 -b "$NOMOUNT_REF" "$NOMOUNT_REPO" "$WORK/nomount"
    [[ -f "$WORK/nomount/kernel/src/Kconfig" && -f "$WORK/nomount/kernel/src/Makefile" ]] || { echo "nomount: upstream layout changed (kernel/src missing)" >&2; exit 1; }
    rm -rf "$KSRC/fs/nomount"; mkdir -p "$KSRC/fs/nomount"
    cp -a "$WORK/nomount/kernel/src/." "$KSRC/fs/nomount/"
    grep -q nomount "$KSRC/fs/Makefile" || printf '\nobj-$(CONFIG_NOMOUNT) += nomount/\n' >> "$KSRC/fs/Makefile"
    if ! grep -q 'source "fs/nomount/Kconfig"' "$KSRC/fs/Kconfig"; then
      awk '/^endmenu/ { last = NR } { l[NR] = $0 }
           END { for (i = 1; i <= NR; i++) { if (i == last) print "source \"fs/nomount/Kconfig\""; print l[i] } }' \
        "$KSRC/fs/Kconfig" > "$KSRC/fs/Kconfig.tmp" && mv "$KSRC/fs/Kconfig.tmp" "$KSRC/fs/Kconfig"
    fi
    grep -q 'source "fs/nomount/Kconfig"' "$KSRC/fs/Kconfig" || { echo "failed to hook fs/Kconfig" >&2; exit 1; }
    jq -r '"\(.version) (\(.versionCode))"' "$WORK/nomount/update.json" > "$WORK/nomount.version"
    echo "   integrated NoMount $(cat "$WORK/nomount.version") @ $(git -C "$WORK/nomount" rev-parse --short HEAD)" ;;
  nomount-version) cat "$WORK/nomount.version" ;;
  required) for c in ${REQUIRED[@]+"${REQUIRED[@]}"}; do echo "CONFIG_$c=y"; done ;;
  makevars) printf '%s\n' ${ROOT_MAKEVARS[@]+"${ROOT_MAKEVARS[@]}"} ;;
  probes)   for p in ${PROBES[@]+"${PROBES[@]}"}; do set -- $p; echo "- CONFIG_$1 $2"; done ;;
  label)    echo "$ROOT_LABEL" ;;
  *) echo "unknown command '$CMD'" >&2; exit 2 ;;
esac
