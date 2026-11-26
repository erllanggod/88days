NOMOUNT_REPO="https://github.com/maxsteeel/nomount"
NOMOUNT_REF="dev"
REQUIRED=(NOMOUNT)
PROBES=("NOMOUNT -")

addon_apply() {
  local ksrc="$1" work="$2"
  git clone -q --depth 1 -b "$NOMOUNT_REF" "$NOMOUNT_REPO" "$work/src"
  [[ -f "$work/src/kernel/src/Kconfig" && -f "$work/src/kernel/src/Makefile" ]] || { echo "nomount: upstream layout changed (kernel/src missing)" >&2; return 1; }
  rm -rf "$ksrc/fs/nomount"; mkdir -p "$ksrc/fs/nomount"
  cp -a "$work/src/kernel/src/." "$ksrc/fs/nomount/"
  grep -q nomount "$ksrc/fs/Makefile" || printf '\nobj-$(CONFIG_NOMOUNT) += nomount/\n' >> "$ksrc/fs/Makefile"
  if ! grep -q 'source "fs/nomount/Kconfig"' "$ksrc/fs/Kconfig"; then
    awk '/^endmenu/ { last = NR } { l[NR] = $0 }
         END { for (i = 1; i <= NR; i++) { if (i == last) print "source \"fs/nomount/Kconfig\""; print l[i] } }' \
      "$ksrc/fs/Kconfig" > "$ksrc/fs/Kconfig.tmp" && mv "$ksrc/fs/Kconfig.tmp" "$ksrc/fs/Kconfig"
  fi
  grep -q 'source "fs/nomount/Kconfig"' "$ksrc/fs/Kconfig" || { echo "failed to hook fs/Kconfig" >&2; return 1; }
  jq -r '"\(.version) (\(.versionCode))"' "$work/src/update.json" > "$work/version"
  echo "   integrated NoMount $(cat "$work/version") @ $(git -C "$work/src" rev-parse --short HEAD)"
}
