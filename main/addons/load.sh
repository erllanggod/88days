#!/usr/bin/env bash
set -euo pipefail

CMD="${1:?usage: main/addons/load.sh apply|required|optional|probes|version <addon> [kernel_dir]}"
ADDON="${2:?addon name}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$PROJ/main/addons/$ADDON/$ADDON.sh"

[[ -f "$MANIFEST" ]] || { echo "unknown addon '$ADDON' (no $MANIFEST)" >&2; exit 1; }
PATCHES=(); REQUIRED=(); OPTIONAL=(); PROBES=()
WORK="$PROJ/.build/addons/$ADDON"
source "$MANIFEST"

case "$CMD" in
  apply)
    KSRC="${3:?kernel dir}"
    declare -F addon_apply >/dev/null || [[ ${#PATCHES[@]} -gt 0 ]] || { echo "addon '$ADDON' lists no patches and has no addon_apply" >&2; exit 1; }
    for p in "${PATCHES[@]}"; do
      f="$PROJ/main/etc/kabi/$p.patch"
      [[ -f "$f" ]] || { echo "addon '$ADDON': missing $f" >&2; exit 1; }
      git -C "$KSRC" apply --check "$f" 2>/dev/null || { echo "addon '$ADDON': $p.patch does not apply cleanly" >&2; exit 1; }
      git -C "$KSRC" apply "$f"
      echo "   applied $p.patch"
    done
    if declare -F addon_apply >/dev/null; then
      rm -rf "$WORK"; mkdir -p "$WORK"
      addon_apply "$KSRC" "$WORK"
    fi ;;
  required) for c in ${REQUIRED[@]+"${REQUIRED[@]}"}; do [[ "$c" == *=* ]] && echo "CONFIG_$c" || echo "CONFIG_$c=y"; done ;;
  optional) for c in ${OPTIONAL[@]+"${OPTIONAL[@]}"}; do echo "CONFIG_$c=y"; done ;;
  probes)   for p in ${PROBES[@]+"${PROBES[@]}"}; do set -- $p; echo "- CONFIG_$1 $2"; done ;;
  version)  cat "$WORK/version" ;;
  *) echo "unknown command '$CMD'" >&2; exit 2 ;;
esac
