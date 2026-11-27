#!/usr/bin/env bash
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJ"

c()    { printf '\033[%sm' "$1"; }
hdr()  { echo; echo "$(c '1;36')════ $* ════$(c 0)"; }
step() { echo "$(c '1;34')▶$(c 0) $*"; }
ok()   { echo "$(c '1;32')✓$(c 0) $*"; }
warn() { echo "$(c '1;33')⚠$(c 0) $*" >&2; }
die()  { echo "$(c '1;31')✗ ERROR: $*$(c 0)" >&2; exit 1; }

VARIANT=""; GATE_ONLY=0; DROIDSPACES="${DROIDSPACES:-0}"; NOMOUNT="${NOMOUNT:-0}"; ROOT="${ROOT:-}"; LTO="${LTO:-none}"; HZ_MODE="${HZ_MODE:-balance}"; JOBS="${JOBS:-$(nproc)}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    vanilla)     VARIANT="$1" ;;
    --gate-only) GATE_ONLY=1 ;;
    --droidspaces) DROIDSPACES=1 ;;
    --nomount)   NOMOUNT=1 ;;
    --root)      shift; ROOT="${1:-}" ;;
    --hz)        shift; HZ_MODE="${1:-}" ;;
    --lto)       shift; LTO="${1:-}" ;;
    --jobs)      shift; JOBS="${1:-}" ;;
    *)           die "unknown argument: $1" ;;
  esac
  shift
done
[[ -n "$VARIANT" ]] || die "usage: ./build.sh vanilla [--droidspaces] [--nomount] [--root finasu] [--hz balance|performance|ultra] [--lto none|thin] [--gate-only] [--jobs N]"

[[ -f "$PROJ/main/branding/device.conf" ]] || die "missing $PROJ/main/branding/device.conf"
source "$PROJ/main/branding/device.conf"
[[ -f "$PROJ/main/config/pins.lock" ]] && source "$PROJ/main/config/pins.lock"

[[ "${MODULE_LAYOUT:-}" =~ ^0x[0-9a-fA-F]{8}$ ]] || die \
  "main/branding/device.conf MODULE_LAYOUT is empty or not an 8-digit hex CRC ('${MODULE_LAYOUT:-}')"

for v in PROJ KERNEL_SRC KMI_REF_TREE KMI_REF_SYSTEM_TREE CLANG_DIR; do
  case "${!v:-}" in
    *[[:space:]]*|*:*) die "$v contains a space or colon: '${!v}'" ;;
  esac
done

TAG="$VARIANT"
ADDONS=(rekernel tcpbrutal)
[[ "$DROIDSPACES" == 1 ]] && { ADDONS+=(droidspace); TAG="$TAG-droidspaces"; }
[[ "$NOMOUNT" == 1 ]] && { ADDONS+=(nomount); TAG="$TAG-nomount"; }
[[ -f "$PROJ/main/etc/hz/$HZ_MODE/$HZ_MODE.sh" ]] || die "unknown hz '$HZ_MODE'"
[[ "$HZ_MODE" == balance ]] || TAG="$TAG-$HZ_MODE"
[[ "$LTO" == none || -f "$PROJ/main/etc/lto/$LTO/$LTO.sh" ]] || die "unknown lto '$LTO'"
[[ "$LTO" == none ]] || TAG="$TAG-$LTO"
[[ -z "$ROOT" || -f "$PROJ/main/etc/root/ksu/$ROOT/$ROOT.sh" ]] || die "unknown root '$ROOT'"
[[ -n "$ROOT" ]] && TAG="$TAG-$ROOT"

hdr "$DEVICE_FULL_LABEL — variant: $TAG"

[[ -f "$KERNEL_SRC/Makefile" ]] || die "no kernel source at $KERNEL_SRC/Makefile"
for _t in bin/clang bin/clang++ bin/llvm-ar bin/llvm-strip bin/llvm-objcopy bin/ld.lld; do
  [[ -x "$CLANG_DIR/$_t" ]] || die "CLANG_DIR=$CLANG_DIR missing executable $_t"
done

if [[ -n "${KERNEL_COMMON_REF:-}" ]]; then
  _cur="$(git -C "$KERNEL_SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
  if [[ "$_cur" != "$KERNEL_COMMON_REF" && "$_cur" != "${KERNEL_COMMON_UPSTREAM_REF:-}" ]]; then
    die "KERNEL_SRC is at ${_cur:0:12} but main/config/pins.lock pins ${KERNEL_COMMON_REF:0:12} (upstream ${KERNEL_COMMON_UPSTREAM_REF:0:12}).
  Restore with: git -C $KERNEL_SRC checkout $KERNEL_COMMON_REF"
  fi
fi

KSRC_VER="$(awk -F' = ' '/^VERSION/{v=$2} /^PATCHLEVEL/{p=$2} /^SUBLEVEL/{s=$2}
                         END{print v"."p"."s}' "$KERNEL_SRC/Makefile")"
KSRC_REF="$(git -C "$KERNEL_SRC" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
KMI_GEN="$(awk -F= '/^KMI_GENERATION/{print $2}' "$KERNEL_SRC/build.config.common" "$KERNEL_SRC/build.config.constants" 2>/dev/null | head -1)"
LOCALVERSION_STR="-${BRAND}"
EXPECT_REL="${KSRC_VER}${LOCALVERSION_STR}"

for v in BRAND KBUILD_BUILD_USER KBUILD_BUILD_HOST; do
  [[ "${!v:-}" =~ ^[A-Za-z0-9._-]+$ ]] || die "main/branding/device.conf $v='${!v:-}' — use only [A-Za-z0-9._-]"
done
(( ${#EXPECT_REL} <= 64 )) || die "release '$EXPECT_REL' exceeds 64 chars (__NEW_UTS_LEN)"

SYSPY=""
for p in /usr/bin/python3 /usr/local/bin/python3 python3; do
  "$p" -c 'import sys' >/dev/null 2>&1 && { SYSPY="$p"; break; }
done
[[ -n "$SYSPY" ]] || die "no python3 found"

NKO_VENDOR="$(find "$KMI_REF_TREE" -name '*.ko' 2>/dev/null | wc -l)"
NKO_SYSTEM="$(find "$KMI_REF_SYSTEM_TREE" -name '*.ko' 2>/dev/null | wc -l)"
[[ "$NKO_VENDOR" -gt 0 ]] || die "no .ko files under $KMI_REF_TREE"
[[ "$NKO_SYSTEM" -gt 0 ]] || die "no .ko files under $KMI_REF_SYSTEM_TREE"
[[ -f "$STOCK_SYMVERS" ]] || die "missing $STOCK_SYMVERS"
NSTOCK_SYMS="$(wc -l < "$STOCK_SYMVERS")"

echo "   source        : Linux $KSRC_VER @ $KSRC_REF (android15-6.6-lts, KMI_GENERATION=$KMI_GEN)"
echo "   clang         : $("$CLANG_DIR/bin/clang" --version | head -1)"
echo "   pahole        : $(pahole --version 2>/dev/null || echo unknown)"
echo "   release       : $EXPECT_REL (${KBUILD_BUILD_USER}@${KBUILD_BUILD_HOST})"
echo "   KMI target    : $MODULE_LAYOUT ($NKO_VENDOR vendor + $NKO_SYSTEM system_dlkm modules, $NSTOCK_SYMS stock exports)"
echo "   gate python   : $SYSPY"

KOUT="${KOUT:-$PROJ/.build/out-$TAG}"
OUT="$PROJ/out/$TAG"
mkdir -p "$KOUT" "$OUT" "$PROJ/.build/logs"

export PATH="$CLANG_DIR/bin:$PATH"

export KBUILD_BUILD_USER KBUILD_BUILD_HOST
SRC_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$KERNEL_SRC" log -1 --format=%ct 2>/dev/null || echo 0)}"
export SOURCE_DATE_EPOCH="$SRC_EPOCH"
export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-$(date -u -d "@$SRC_EPOCH" 2>/dev/null || date -u)}"

CCACHE_ON=0
if [[ "${CCACHE:-1}" != 0 ]] && command -v ccache >/dev/null 2>&1; then
  CCACHE_ON=1
  export CCACHE_DIR="${CCACHE_DIR:-$PROJ/.build/ccache}" CCACHE_BASEDIR="$PROJ"
  export CCACHE_COMPRESS=1 CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-1500M}" CCACHE_COMPILERCHECK=content
  export CCACHE_SLOPPINESS=include_file_mtime,include_file_ctime
  mkdir -p "$CCACHE_DIR"
  ccache -z >/dev/null
  echo "   ccache        : $(ccache --version | head -1) ($CCACHE_DIR, max $CCACHE_MAXSIZE)"
fi

REPRO_FLAGS="-ffile-prefix-map=$KOUT=/build/obj -ffile-prefix-map=$KERNEL_SRC=/build/src"
MK=( make -C "$KERNEL_SRC" O="$KOUT" ARCH=arm64 LLVM=1 LLVM_IAS=1
     CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu-
     KCFLAGS="$REPRO_FLAGS" )
if [[ "$CCACHE_ON" == 1 ]]; then MK+=(CC="ccache clang"); fi

if [[ -n "$ROOT" ]]; then
  while IFS= read -r _v; do [[ -n "$_v" ]] && MK+=("$_v"); done < <("$PROJ/main/etc/root/load.sh" makevars "$ROOT")
fi

SOURCE_DIRTY=0
cleanup_source() {
  local rc=$?
  if [[ "$SOURCE_DIRTY" == 1 ]]; then
    step "Restoring $KERNEL_SRC to pristine state"
    git -C "$KERNEL_SRC" reset -q --hard HEAD 2>/dev/null || true
    git -C "$KERNEL_SRC" clean -ffdq 2>/dev/null || true
  fi
  exit $rc
}

prepare_source() {
  if [[ -n "$(git -C "$KERNEL_SRC" status --porcelain)" ]]; then
    if [[ "${KEEP_DIRTY:-0}" == "1" ]]; then
      die "$KERNEL_SRC is dirty and KEEP_DIRTY=1"
    fi
    warn "$KERNEL_SRC had leftover changes — resetting to pristine"
    git -C "$KERNEL_SRC" reset -q --hard HEAD 2>/dev/null || true
    git -C "$KERNEL_SRC" clean -ffdq 2>/dev/null || true
  fi
  SOURCE_DIRTY=1
}

if [[ "$GATE_ONLY" == 0 ]]; then
  prepare_source
  trap cleanup_source EXIT

  git -C "$KERNEL_SRC" apply "$PROJ/main/etc/banner/single-url.patch" || die "banner patch failed to apply"
  HZ_PATCH="$("$PROJ/main/etc/hz/load.sh" patch "$HZ_MODE")"
  if [[ -n "$HZ_PATCH" ]]; then
    git -C "$KERNEL_SRC" apply "$HZ_PATCH" || die "hz patch $(basename "$HZ_PATCH") failed to apply"
  fi

  step "Generating GKI ABI symbol whitelist ($KOUT/abi_symbollist.raw)"
  {
    awk '
      /^[[:space:]]*#/ || /^[[:space:]]*$/ || /^\[/ { next }
      { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*$/) print $0 }
    ' "$KERNEL_SRC"/android/abi_gki_aarch64 "$KERNEL_SRC"/android/abi_gki_aarch64_*
    awk '{print $2}' "$STOCK_SYMVERS"
  } | LC_ALL=C sort -u > "$KOUT/abi_symbollist.raw"
  NSYMLIST="$(wc -l < "$KOUT/abi_symbollist.raw")"
  ok "abi_symbollist.raw: $NSYMLIST symbols (union of abi_gki_aarch64* + stock.symvers)"

  step "Configuring base gki_defconfig"
  "${MK[@]}" gki_defconfig > "$KOUT/defconfig.log" 2>&1 || {
    tail -30 "$KOUT/defconfig.log" >&2
    die "gki_defconfig failed"
  }

  for a in "${ADDONS[@]}"; do
    step "Applying addon: $a"
    "$PROJ/main/addons/load.sh" apply "$a" "$KERNEL_SRC" || die "addon $a failed to apply"
  done

  if [[ -n "$ROOT" ]]; then
    step "Integrating root: $ROOT + SUSFS"
    "$PROJ/main/etc/root/load.sh" apply "$ROOT" "$KERNEL_SRC" || die "root $ROOT failed to integrate"
  fi

  FRAGS=("$PROJ/main/config/vanilla_defconfig")
  SOFT_FRAGS=()
  if [[ -n "$ROOT" ]]; then
    "$PROJ/main/etc/root/load.sh" required "$ROOT" > "$KOUT/root-$ROOT.required"
    FRAGS+=("$KOUT/root-$ROOT.required")
  fi
  "$PROJ/main/etc/hz/load.sh" required "$HZ_MODE" > "$KOUT/hz-$HZ_MODE.required"
  FRAGS+=("$KOUT/hz-$HZ_MODE.required")
  if [[ "$LTO" != none ]]; then
    "$PROJ/main/etc/lto/load.sh" required "$LTO" > "$KOUT/lto-$LTO.required"
    FRAGS+=("$KOUT/lto-$LTO.required")
  fi
  for a in "${ADDONS[@]}"; do
    "$PROJ/main/addons/load.sh" required "$a" > "$KOUT/addon-$a.required"
    "$PROJ/main/addons/load.sh" optional "$a" > "$KOUT/addon-$a.optional"
    FRAGS+=("$KOUT/addon-$a.required")
    SOFT_FRAGS+=("$KOUT/addon-$a.optional")
  done
  for f in "${FRAGS[@]}"; do [[ -f "$f" ]] || die "missing fragment $f"; done
  if grep -n '^CONFIG_LOCALVERSION' "${FRAGS[@]}"; then
    die "a config fragment sets CONFIG_LOCALVERSION — remove it; build.sh owns the brand"
  fi

  COMPOSED="$OUT/composed_defconfig"
  {
    for f in "${FRAGS[@]}"; do
      echo "# ── ${f#$PROJ/} ──"
      cat "$f"
      echo
    done
    echo "# ── generated by build.sh from device.conf ──"
    echo "CONFIG_LOCALVERSION=\"$LOCALVERSION_STR\""
    echo "CONFIG_LOCALVERSION_AUTO=y"
    echo "CONFIG_MODULE_SCMVERSION=y"
    echo "CONFIG_TRIM_UNUSED_KSYMS=y"
    echo "CONFIG_UNUSED_KSYMS_WHITELIST=\"$KOUT/abi_symbollist.raw\""
  } > "$COMPOSED"

  step "Merging ${FRAGS[*]#$PROJ/} + brand ($LOCALVERSION_STR)"
  "$KERNEL_SRC/scripts/kconfig/merge_config.sh" -m -r -O "$KOUT" "$KOUT/.config" "$COMPOSED" ${SOFT_FRAGS[@]+"${SOFT_FRAGS[@]}"} > "$KOUT/merge_config.log" 2>&1
  "${MK[@]}" olddefconfig > "$KOUT/olddefconfig.log" 2>&1 || {
    tail -30 "$KOUT/olddefconfig.log" >&2
    die "olddefconfig failed"
  }
  LTO_INVARIANTS="CONFIG_LTO_NONE=y"
  [[ "$LTO" == none ]] || LTO_INVARIANTS="$("$PROJ/main/etc/lto/load.sh" invariant "$LTO")"
  HZ_INVARIANTS="$("$PROJ/main/etc/hz/load.sh" invariant "$HZ_MODE")"
  for inv in CONFIG_LOCALVERSION_AUTO=y CONFIG_MODULE_SCMVERSION=y CONFIG_PAHOLE_HAS_BTF_TAG=y CONFIG_CFI_CLANG=y $LTO_INVARIANTS $HZ_INVARIANTS; do
    grep -qx "$inv" "$KOUT/.config" || die "KMI config invariant missing after olddefconfig: $inv"
  done

  if [[ -n "$ROOT" ]]; then
    step "Pre-generating SELinux headers for the root driver"
    "${MK[@]}" -j"$JOBS" security/selinux/ > "$KOUT/selinux-pre.log" 2>&1 || {
      tail -30 "$KOUT/selinux-pre.log" >&2
      die "security/selinux/ pre-build failed"
    }
  fi

  step "Building vmlinux, Image, Image.gz, Image.lz4, modules (-j$JOBS)"
  "${MK[@]}" KERNELRELEASE="$EXPECT_REL" -j"$JOBS" vmlinux Image Image.gz Image.lz4 modules 2>&1 | tee "$OUT/build.log"
  if [[ "$CCACHE_ON" == 1 ]]; then ccache -s 2>&1 | sed -n '1,12p'; fi
  ok "Kernel compilation complete"

fi

SOFT_MISS=()
for f in ${SOFT_FRAGS[@]+"${SOFT_FRAGS[@]}"}; do
  while IFS= read -r l; do
    [[ "$l" == CONFIG_*=* ]] && { grep -qxF "$l" "$KOUT/.config" || SOFT_MISS+=("${l%%=*}"); }
  done < "$f"
done
[[ ${#SOFT_MISS[@]} -eq 0 ]] || warn "optional addon options not enabled after olddefconfig: ${SOFT_MISS[*]}"

SYMVERS="$KOUT/vmlinux.symvers"
MODSYMVERS="$KOUT/Module.symvers"
VMLINUX="$KOUT/vmlinux"
DOTCFG="$KOUT/.config"
SMAP="$KOUT/System.map"
SYMBOLLIST="$KOUT/abi_symbollist.raw"
KREL_FILE="$KOUT/include/config/kernel.release"

[[ -f "$SYMVERS" && -f "$VMLINUX" && -f "$DOTCFG" && -f "$SMAP" ]] || \
  die "missing build outputs under $KOUT — run ./build.sh $VARIANT without --gate-only first"

GOT_REL="$(cat "$KREL_FILE" 2>/dev/null || echo '<none>')"
echo "   kernel.release: $GOT_REL"

[[ "$GOT_REL" == "$EXPECT_REL" ]] || \
  die "kernel.release is '$GOT_REL', expected '$EXPECT_REL'"
BANNER="$(LC_ALL=C grep -aom1 'Linux version [^ ]* ([^)]*)' "$KOUT/arch/arm64/boot/Image" 2>/dev/null || true)"
[[ "$BANNER" == "Linux version $EXPECT_REL (${KBUILD_BUILD_USER}@${KBUILD_BUILD_HOST})" ]] || \
  die "Image banner is '$BANNER', expected 'Linux version $EXPECT_REL (${KBUILD_BUILD_USER}@${KBUILD_BUILD_HOST})'"
ok "Banner verified: $BANNER"

MISS=""
while IFS= read -r l; do
  case "$l" in
    CONFIG_UNUSED_KSYMS_WHITELIST=*) ;;
    CONFIG_*=*)
      grep -qxF "$l" "$DOTCFG" || MISS+="  missing in .config: $l"$'\n' ;;
    "# CONFIG_"*" is not set")
      o="${l#\# }"; o="${o%% *}"
      grep -q "^$o=" "$DOTCFG" && MISS+="  expected unset in .config: $l"$'\n' ;;
  esac
done < "$OUT/composed_defconfig"

while read -r p cfg sym; do
  [[ "$cfg" == "-" ]] || grep -qx "$cfg=y" "$DOTCFG" || MISS+="  $p: $cfg is not =y"$'\n'
  [[ "$sym" == "-" ]] || awk -v s="$sym" '$3==s{f=1} END{exit !f}' "$SMAP" \
    || MISS+="  $p: probe symbol '$sym' missing from System.map"$'\n'
done < <({ awk '!/^[[:space:]]*(#|$)/' "$PROJ/main/etc/cpatch/series"
           for a in ${ADDONS[@]+"${ADDONS[@]}"}; do "$PROJ/main/addons/load.sh" probes "$a"; done
           [[ -z "$ROOT" ]] || "$PROJ/main/etc/root/load.sh" probes "$ROOT"; })

[[ -z "$MISS" ]] || die "built kernel is missing configured features or patch symbols:
$MISS"
ok "Feature gate: all composed_defconfig switches active and all $(awk '!/^[[:space:]]*(#|$)/ && $3!="-"' "$PROJ/main/etc/cpatch/series" | wc -l) patch probe symbols present in System.map"

hdr "Running 6-Layer KMI / ABI Gate Suite ($VARIANT)"
set +e

step "Layer 1 (Vendor) — symbol CRCs vs $NKO_VENDOR vendor_boot + vendor_dlkm modules"
"$SYSPY" "$PROJ/main/core/kmi_check.py" "$SYMVERS" "$KMI_REF_TREE" \
  --extra-exports "$KMI_REF_SYSTEM_TREE/exports.tsv" \
  --expect-vermagic "$KMI_EXPECT_VERMAGIC" \
  --expect-module-layout "$MODULE_LAYOUT" 2>&1 | tee "$OUT/kmi-check.log"
L1=${PIPESTATUS[0]}

step "Layer 2 (Vendor) — protected exports (MODULE_SIG_PROTECT)"
if grep -q '^CONFIG_MODULE_SIG_PROTECT=y' "$DOTCFG" 2>/dev/null; then
  "$SYSPY" "$PROJ/main/core/protect_check.py" "$VMLINUX" "$KMI_REF_TREE" \
    --extra-exports "$KMI_REF_SYSTEM_TREE/exports.tsv" 2>&1 | tee "$OUT/protect-check.log"
  L2=${PIPESTATUS[0]}
else
  echo "PASS [protect_check]: MODULE_SIG_PROTECT is off; no export is protected" | tee "$OUT/protect-check.log"
  L2=0
fi

step "Layer 3 (Vendor) — full module import accounting + whitelist check"
"$SYSPY" "$PROJ/main/core/import_check.py" "$SYMVERS" "$KMI_REF_TREE" \
  --extra-exports "$KMI_REF_SYSTEM_TREE/exports.tsv" \
  --raw-symbollist "$SYMBOLLIST" 2>&1 | tee "$OUT/import-check.log"
L3=${PIPESTATUS[0]}

step "Layer 1 (system_dlkm) — symbol CRCs vs $NKO_SYSTEM GKI modules"
"$SYSPY" "$PROJ/main/core/kmi_check.py" "$SYMVERS" "$KMI_REF_SYSTEM_TREE" \
  --expect-vermagic "$KMI_SYSTEM_EXPECT_VERMAGIC" \
  --expect-module-layout "$MODULE_LAYOUT" 2>&1 | tee "$OUT/kmi-check-system.log"
S1=${PIPESTATUS[0]}

step "Layer 2 (system_dlkm) — protected exports (MODULE_SIG_PROTECT)"
if grep -q '^CONFIG_MODULE_SIG_PROTECT=y' "$DOTCFG" 2>/dev/null; then
  "$SYSPY" "$PROJ/main/core/protect_check.py" "$VMLINUX" "$KMI_REF_SYSTEM_TREE" 2>&1 \
    | tee "$OUT/protect-check-system.log"
  S2=${PIPESTATUS[0]}
else
  echo "PASS [protect_check]: MODULE_SIG_PROTECT is off; no export is protected" | tee "$OUT/protect-check-system.log"
  S2=0
fi

step "Layer 3 (system_dlkm) — full module import accounting + whitelist check"
"$SYSPY" "$PROJ/main/core/import_check.py" "$SYMVERS" "$KMI_REF_SYSTEM_TREE" \
  --raw-symbollist "$SYMBOLLIST" 2>&1 | tee "$OUT/import-check-system.log"
S3=${PIPESTATUS[0]}

step "Layer 4 (Stock vmlinux symvers) — strict 100% check vs all $NSTOCK_SYMS stock vmlinux exports"
"$SYSPY" "$PROJ/main/core/stock_symvers_check.py" "$SYMVERS" "$STOCK_SYMVERS" \
  --required-tsv "$KMI_REF_TREE/required.tsv" \
  --required-tsv "$KMI_REF_SYSTEM_TREE/required.tsv" \
  --strict-all-stock 2>&1 | tee "$OUT/stock-symvers-check.log"
L4=${PIPESTATUS[0]}

step "Layer 5 (Duplicate export guard) — 0 overlap between vmlinux exports and $((NKO_VENDOR + NKO_SYSTEM)) stock modules"
"$SYSPY" "$PROJ/main/core/dup_export_check.py" "$SYMVERS" "$KMI_REF_TREE" "$KMI_REF_SYSTEM_TREE" 2>&1 \
  | tee "$OUT/dup-export-check.log"
L5=${PIPESTATUS[0]}

step "Layer 6 (kCFI) — vmlinux __kcfi_typeid_* vs stock .ko"
"$SYSPY" "$PROJ/main/core/kcfi_check.py" "$VMLINUX" "$SYMVERS" "$KMI_REF_TREE" "$KMI_REF_SYSTEM_TREE" 2>&1 \
  | tee "$OUT/kcfi-check.log"
L6=${PIPESTATUS[0]}

set -e
echo
if [[ "$L1" == 0 && "$L2" == 0 && "$L3" == 0 && "$S1" == 0 && "$S2" == 0 && "$S3" == 0 && "$L4" == 0 && "$L5" == 0 && "$L6" == 0 ]]; then
  STAGED="$PROJ/.build/staged-$TAG"
  rm -rf "$STAGED"; mkdir -p "$STAGED"
  for f in Image Image.gz Image.lz4; do
    [[ -f "$KOUT/arch/arm64/boot/$f" ]] || die "missing $KOUT/arch/arm64/boot/$f"
    cp -f "$KOUT/arch/arm64/boot/$f" "$STAGED/$f"
    cp -f "$KOUT/arch/arm64/boot/$f" "$OUT/$f"
  done
  cp -f "$KREL_FILE" "$STAGED/kernel.release"
  cp -f "$KREL_FILE" "$OUT/kernel.release"
  cp -f "$DOTCFG" "$OUT/kernel.config"
  cp -f "$SYMVERS" "$OUT/vmlinux.symvers"
  ( cd "$OUT" && sha256sum Image Image.gz Image.lz4 > SHA256SUMS )
  ok "GATE: PASS — All 6 Gate Layers (Vendor+System L1/L2/L3, L4 all $NSTOCK_SYMS stock exports, L5 dup-export, L6 kCFI) 100% CLEAN."
else
  die "GATE: FAIL — vendor L1/L2/L3=$L1/$L2/$L3  system_dlkm S1/S2/S3=$S1/$S2/$S3  stock_symvers L4=$L4  dup_export L5=$L5  kcfi L6=$L6"
fi
