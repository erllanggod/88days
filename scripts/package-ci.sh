#!/usr/bin/env bash
# Package a gated build into an AnyKernel3 zip (CI variant: no stock boot.img self-test).
# Usage: scripts/package-ci.sh vanilla
set -euo pipefail
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$PROJ"
die() { echo "ERROR: $*" >&2; exit 1; }
VARIANT="${1:-vanilla}"
# shellcheck disable=SC1091
source "$PROJ/device.conf"; source "$PROJ/sources.lock"

STAGED="$PROJ/.build/staged-$VARIANT"
[[ -f "$STAGED/Image" && -f "$STAGED/kernel.release" ]] || die "no staged Image — run build.sh $VARIANT first"
OUT="$PROJ/out/$VARIANT"
for f in kmi-check protect-check import-check kmi-check-system protect-check-system import-check-system \
         stock-symvers-check dup-export-check kcfi-check; do
  grep -qE "^PASS \[" "$OUT/$f.log" || die "gate $f did not pass"
done

KREL="$(cat "$STAGED/kernel.release")"
EXPECT="$(awk -F' = ' '/^VERSION/{v=$2} /^PATCHLEVEL/{p=$2} /^SUBLEVEL/{s=$2} END{print v"."p"."s}' "$KERNEL_SRC/Makefile")-${BRAND}"
[[ "$KREL" == "$EXPECT" ]] || die "kernel.release '$KREL' != '$EXPECT'"
BANNER="$(LC_ALL=C grep -aom1 'Linux version [^ ]*' "$STAGED/Image" | awk '{print $3}')"
[[ "$BANNER" == "$KREL" ]] || die "Image banner '$BANNER' != '$KREL'"

COMPILER="$(LC_ALL=C grep -aom1 'clang version [0-9][^ )]*' "$STAGED/Image" | head -1 || true)"
[[ -n "$COMPILER" ]] || COMPILER="clang"
DATE="$(date -u +%Y%m%d)"
AK="$PROJ/.build/ak3-$VARIANT"
rm -rf "$AK"; cp -r "$PROJ/anykernel" "$AK"
rm -f "$AK"/Image* "$AK"/zImage*
cp "$STAGED/Image" "$AK/Image"
# The bundled AnyKernel3 tools are 32-bit ARM; Snapdragon 8s Gen 4 has no 32-bit
# support, so the installer dies at "Busybox setup failed". Use arm64 builds.
: "${AK_TOOLS_ARM64:?set AK_TOOLS_ARM64 to a dir with arm64 magiskboot, busybox, magiskpolicy}"
for t in magiskboot busybox magiskpolicy; do
  cp "$AK_TOOLS_ARM64/$t" "$AK/tools/$t"; chmod 755 "$AK/tools/$t"
  file "$AK/tools/$t" | grep -q 'ARM aarch64' || die "tools/$t is not arm64"
done

NAMELINES=""; i=1
for n in $DEVICE_NAMES; do NAMELINES+="device.name${i}=${n}"$'\n'; i=$((i+1)); done

cat > "$AK/anykernel.sh" <<AKEOF
### AnyKernel3 Ramdisk Mod Script — ${DEVICE_FULL_LABEL}

properties() { '
kernel.string=${DEVICE_LABEL} ${BRAND_FULL} • ${KREL} • ${DATE}
do.devicecheck=${DEVICE_CHECK}
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
${NAMELINES}supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

ui_print " ";
ui_print "   ${DEVICE_LABEL} — ${BRAND_FULL}";
ui_print "   Linux ${KREL}";
ui_print "   compiler : ${COMPILER}";
ui_print "   KMI      : module_layout ${MODULE_LAYOUT}";
ui_print " ";

kver=\$(cat /proc/version | awk '{print \$3}' | cut -d- -f1)
case "\$kver" in
  6.6.*) ui_print " -> ROM is on \$kver (6.6 GKI base OK) — installing ${KREL}" ;;
  *)     abort " -> Not a 6.6 GKI ROM (\$kver) — aborting to protect boot partition!" ;;
esac

split_boot;
rm -f "\$SPLITIMG/kernel_dtb";
if [ -f "\$SPLITIMG/ramdisk.cpio" ] || [ -d "\$SPLITIMG/vendor_ramdisk" ]; then
  unpack_ramdisk;
  write_boot;
else
  flash_boot;
fi
AKEOF

mkdir -p "$OUT" "$PROJ/dist"
ZIP="$PROJ/dist/DumpC2J-Vanilla-${DATE}.zip"
rm -f "$ZIP"
( cd "$AK" && zip -r9 "$ZIP" . -x '.git*' 'README.md' >/dev/null )
( cd "$PROJ/dist" && sha256sum "$(basename "$ZIP")" > SHA256SUMS )
echo "zip: $ZIP"; cat "$PROJ/dist/SHA256SUMS"
