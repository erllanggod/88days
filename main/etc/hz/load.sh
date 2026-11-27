#!/usr/bin/env bash
set -euo pipefail

CMD="${1:?usage: main/etc/hz/load.sh required|label|invariant|patch <hz>}"
HZ="${2:?hz value}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DIR="$PROJ/main/etc/hz/$HZ"
MANIFEST="$DIR/$HZ.sh"

[[ -f "$MANIFEST" ]] || { echo "unknown hz '$HZ' (no $MANIFEST)" >&2; exit 1; }
REQUIRED=(); UNSET=(); PATCH=""; HZ_VALUE=""
source "$MANIFEST"

case "$CMD" in
  required)  for c in ${REQUIRED[@]+"${REQUIRED[@]}"}; do echo "CONFIG_$c=y"; done
             for c in ${UNSET[@]+"${UNSET[@]}"}; do echo "# CONFIG_$c is not set"; done ;;
  invariant) for c in ${REQUIRED[@]+"${REQUIRED[@]}"}; do echo "CONFIG_$c=y"; done
             echo "CONFIG_HZ=$HZ_VALUE" ;;
  label)     echo "$HZ_LABEL" ;;
  patch)     [[ -z "$PATCH" ]] || echo "$DIR/$PATCH" ;;
  *) echo "unknown command '$CMD'" >&2; exit 2 ;;
esac
