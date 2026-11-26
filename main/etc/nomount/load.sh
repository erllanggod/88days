#!/usr/bin/env bash
set -euo pipefail

CMD="${1:?usage: main/etc/nomount/load.sh apply|required|probes|version [kernel_dir]}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HERE="$PROJ/main/etc/nomount"
WORK="${NOMOUNT_WORK:-$PROJ/.build/nomount}"

REQUIRED=(); PROBES=()
source "$HERE/nomount.sh"

case "$CMD" in
  apply)
    KSRC="${2:?kernel dir}"
    rm -rf "$WORK"
    git clone -q --depth 1 -b "$NOMOUNT_REF" "$NOMOUNT_REPO" "$WORK/src"
    [[ -f "$WORK/src/kernel/src/Kconfig" && -f "$WORK/src/kernel/src/Makefile" ]] || { echo "nomount: upstream layout changed (kernel/src missing)" >&2; exit 1; }
    rm -rf "$KSRC/fs/nomount"; mkdir -p "$KSRC/fs/nomount"
    cp -a "$WORK/src/kernel/src/." "$KSRC/fs/nomount/"
    grep -q nomount "$KSRC/fs/Makefile" || printf '\nobj-$(CONFIG_NOMOUNT) += nomount/\n' >> "$KSRC/fs/Makefile"
    if ! grep -q 'source "fs/nomount/Kconfig"' "$KSRC/fs/Kconfig"; then
      awk '/^endmenu/ { last = NR } { l[NR] = $0 }
           END { for (i = 1; i <= NR; i++) { if (i == last) print "source \"fs/nomount/Kconfig\""; print l[i] } }' \
        "$KSRC/fs/Kconfig" > "$KSRC/fs/Kconfig.tmp" && mv "$KSRC/fs/Kconfig.tmp" "$KSRC/fs/Kconfig"
    fi
    grep -q 'source "fs/nomount/Kconfig"' "$KSRC/fs/Kconfig" || { echo "failed to hook fs/Kconfig" >&2; exit 1; }
    jq -r '"\(.version) (\(.versionCode))"' "$WORK/src/update.json" > "$WORK/version"
    echo "   integrated NoMount $(cat "$WORK/version") @ $(git -C "$WORK/src" rev-parse --short HEAD)" ;;
  required) for c in ${REQUIRED[@]+"${REQUIRED[@]}"}; do echo "CONFIG_$c=y"; done ;;
  probes)   for p in ${PROBES[@]+"${PROBES[@]}"}; do set -- $p; echo "- CONFIG_$1 $2"; done ;;
  version)  cat "$WORK/version" ;;
  *) echo "unknown command '$CMD'" >&2; exit 2 ;;
esac
