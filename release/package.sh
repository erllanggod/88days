#!/usr/bin/env bash
set -euo pipefail
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$PROJ"
die() { echo "ERROR: $*" >&2; exit 1; }

VARIANT="${1:-vanilla}"
source "$PROJ/main/branding/device.conf"
source "$PROJ/main/config/pins.lock"

STAGED="$PROJ/.build/staged-$VARIANT"
OUT="$PROJ/out/$VARIANT"
[[ -f "$STAGED/Image" && -f "$STAGED/kernel.release" ]] || die "no staged Image, run build.sh $VARIANT first"

for f in kmi-check protect-check import-check kmi-check-system protect-check-system import-check-system \
         stock-symvers-check dup-export-check kcfi-check; do
  grep -qE "^PASS \[" "$OUT/$f.log" || die "gate $f did not pass"
done

KREL="$(cat "$STAGED/kernel.release")"
EXPECT="$(awk -F' = ' '/^VERSION/{v=$2} /^PATCHLEVEL/{p=$2} /^SUBLEVEL/{s=$2} END{print v"."p"."s}' "$KERNEL_SRC/Makefile")-${BRAND}"
[[ "$KREL" == "$EXPECT" ]] || die "kernel.release '$KREL' != '$EXPECT'"
BANNER="$(LC_ALL=C grep -aom1 'Linux version [^ ]*' "$STAGED/Image" | awk '{print $3}')"
[[ "$BANNER" == "$KREL" ]] || die "Image banner '$BANNER' != '$KREL'"

: "${AK_TOOLS_ARM64:?set AK_TOOLS_ARM64 to a dir holding arm64 magiskboot, busybox, magiskpolicy}"

DATE="$(TZ=Asia/Jakarta date +%Y%m%d)"
STAMP="$(TZ=Asia/Jakarta date +%Y%m%d-%H%M)"
AK="$PROJ/.build/ak3-$VARIANT"
rm -rf "$AK"; cp -r "$PROJ/release/anykernel" "$AK"
rm -f "$AK"/Image* "$AK"/zImage*
cp "$STAGED/Image" "$AK/Image"
for t in magiskboot busybox magiskpolicy; do
  cp "$AK_TOOLS_ARM64/$t" "$AK/tools/$t"; chmod 755 "$AK/tools/$t"
  file "$AK/tools/$t" | grep -q 'ARM aarch64' || die "tools/$t is not arm64"
done

NAMELINES=""; i=1
for n in $DEVICE_NAMES; do NAMELINES+="device.name${i}=${n}"$'\n'; i=$((i+1)); done

cat > "$AK/anykernel.sh" <<AKEOF
properties() { '
kernel.string=${BRAND} Kernel ${KREL} (${DATE})
do.devicecheck=${DEVICE_CHECK}
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
${NAMELINES}supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

kver=\$(cat /proc/version | awk '{print \$3}' | cut -d- -f1)
case "\$kver" in
  6.6.*) ;;
  *) abort " -> Not a 6.6 GKI ROM (\$kver), aborting to protect the boot partition." ;;
esac

ui_print " ";
ui_print " ${BRAND} Kernel ${KREL}";
ui_print " Running : \$kver";
ui_print " ";
ui_print " Flashing boomkernel, please wait...";
ui_print " ";

split_boot;
rm -f "\$SPLITIMG/kernel_dtb";
if [ -f "\$SPLITIMG/ramdisk.cpio" ] || [ -d "\$SPLITIMG/vendor_ramdisk" ]; then
  unpack_ramdisk;
  write_boot;
else
  flash_boot;
fi

ui_print " ";
ui_print " BOOM. New kernel loaded, reboot to see the damage.";
ui_print " ";
AKEOF

mkdir -p "$PROJ/dist"
ZIP="$PROJ/dist/${BRAND}-Vanilla-${STAMP}.zip"
rm -f "$ZIP"
( cd "$AK" && zip -r9 "$ZIP" . -x '.git*' >/dev/null )
( cd "$PROJ/dist" && sha256sum "$(basename "$ZIP")" > SHA256SUMS )
echo "zip: $ZIP"; cat "$PROJ/dist/SHA256SUMS"
