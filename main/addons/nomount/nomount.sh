NOMOUNT_REPO="https://github.com/maxsteeel/nomount"
NOMOUNT_REF="dev"
REQUIRED=(NOMOUNT)
PROBES=("NOMOUNT -")

addon_apply() {
  local ksrc="$1" work="$2"
  git clone -q --filter=blob:none -b "$NOMOUNT_REF" "$NOMOUNT_REPO" "$work/src"
  [[ -f "$work/src/kernel/src/Kconfig" && -f "$work/src/kernel/src/Makefile" ]] || { echo "nomount: upstream layout changed (kernel/src missing)" >&2; return 1; }
  rm -rf "$ksrc/fs/nomount"; mkdir -p "$ksrc/fs/nomount"
  cp -a "$work/src/kernel/src/." "$ksrc/fs/nomount/"
  local count; count="$(git -C "$work/src" rev-list --count HEAD)"
  [[ "$count" =~ ^[0-9]+$ ]] || { echo "nomount: cannot count upstream commits" >&2; return 1; }
  sed -i "/^ifneq (\$(NOMOUNT_COMMITS),)/i NOMOUNT_COMMITS := $count" "$ksrc/fs/nomount/Makefile"
  grep -q "^NOMOUNT_COMMITS := $count\$" "$ksrc/fs/nomount/Makefile" || { echo "nomount: failed to stamp commit count" >&2; return 1; }
  grep -q nomount "$ksrc/fs/Makefile" || printf '\nobj-$(CONFIG_NOMOUNT) += nomount/\n' >> "$ksrc/fs/Makefile"
  if ! grep -q 'source "fs/nomount/Kconfig"' "$ksrc/fs/Kconfig"; then
    awk '/^endmenu/ { last = NR } { l[NR] = $0 }
         END { for (i = 1; i <= NR; i++) { if (i == last) print "source \"fs/nomount/Kconfig\""; print l[i] } }' \
      "$ksrc/fs/Kconfig" > "$ksrc/fs/Kconfig.tmp" && mv "$ksrc/fs/Kconfig.tmp" "$ksrc/fs/Kconfig"
  fi
  grep -q 'source "fs/nomount/Kconfig"' "$ksrc/fs/Kconfig" || { echo "failed to hook fs/Kconfig" >&2; return 1; }
  echo "$(jq -r '.version' "$work/src/update.json") ($count)" > "$work/version"
  echo "   integrated NoMount $(cat "$work/version") @ $(git -C "$work/src" rev-parse --short HEAD)"
}
