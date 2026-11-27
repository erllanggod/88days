REKERNEL_REPO="https://github.com/Sakion-Team/Re-Kernel"
REQUIRED=(REKERNEL REKERNEL_NETWORK REKERNEL_LEGACY_NETLINK)
PROBES=("REKERNEL -")

addon_apply() {
  local ksrc="$1" work="$2" tag
  git clone -q --filter=blob:none "$REKERNEL_REPO" "$work/src"
  tag="$(git -C "$work/src" describe --tags "$(git -C "$work/src" rev-list --tags -n 1)")" || { echo "rekernel: cannot resolve latest tag" >&2; return 1; }
  git -C "$work/src" checkout -q "tags/$tag"
  [[ -f "$work/src/LKM-Source/Kconfig" && -f "$work/src/LKM-Source/Makefile" ]] || { echo "rekernel: upstream layout changed (LKM-Source missing)" >&2; return 1; }
  rm -rf "$ksrc/drivers/rekernel"; mkdir -p "$ksrc/drivers/rekernel"
  cp -a "$work/src/LKM-Source/." "$ksrc/drivers/rekernel/"
  rm -f "$ksrc/drivers/rekernel/README.md"
  sed -i 's/^obj-m := rekernel\.o/obj-$(CONFIG_REKERNEL) += rekernel.o/' "$ksrc/drivers/rekernel/Makefile"
  grep -qF 'obj-$(CONFIG_REKERNEL) += rekernel.o' "$ksrc/drivers/rekernel/Makefile" || { echo "rekernel: failed to convert Makefile to built-in" >&2; return 1; }
  grep -q 'rekernel/' "$ksrc/drivers/Makefile" || printf '\nobj-$(CONFIG_REKERNEL) += rekernel/\n' >> "$ksrc/drivers/Makefile"
  if ! grep -q 'source "drivers/rekernel/Kconfig"' "$ksrc/drivers/Kconfig"; then
    awk '/^endmenu/ { last = NR } { l[NR] = $0 }
         END { for (i = 1; i <= NR; i++) { if (i == last) print "source \"drivers/rekernel/Kconfig\""; print l[i] } }' \
      "$ksrc/drivers/Kconfig" > "$ksrc/drivers/Kconfig.tmp" && mv "$ksrc/drivers/Kconfig.tmp" "$ksrc/drivers/Kconfig"
  fi
  grep -q 'source "drivers/rekernel/Kconfig"' "$ksrc/drivers/Kconfig" || { echo "rekernel: failed to hook drivers/Kconfig" >&2; return 1; }
  grep -q 'rekernel/' "$ksrc/drivers/Makefile" || { echo "rekernel: failed to hook drivers/Makefile" >&2; return 1; }
  echo "$tag" > "$work/version"
  echo "   integrated Re:Kernel $tag @ $(git -C "$work/src" rev-parse --short HEAD)"
}
