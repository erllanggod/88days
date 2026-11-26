#!/usr/bin/env bash
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TAG="${1:?usage: release/telegram/post.sh <tag>}"

source "$PROJ/main/branding/device.conf"
: "${TELEGRAM_TOKEN:?TELEGRAM_TOKEN is empty}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is empty}"
API="${TELEGRAM_API_BASE:-https://api.telegram.org}/bot${TELEGRAM_TOKEN}"

ZIP="$(ls -1 "$PROJ"/dist/*.zip | head -1)"
OUT="$PROJ/out/$TAG"
[[ -f "$ZIP" && -f "$OUT/kernel.release" ]] || { echo "missing zip or kernel.release for $TAG" >&2; exit 1; }

esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

DUR=$(( $(date +%s) - ${BUILD_START:-$(date +%s)} ))
KERNEL_REL="$(cat "$OUT/kernel.release")"
KERNEL_VER="${KERNEL_REL%%-*}"
CLANG_L="$("${CLANG_DIR:-$PROJ/.build/clang}/bin/clang" --version | head -1)"
CLANG_V="$(sed -nE 's/.*clang version ([0-9.]+).*/\1/p' <<<"$CLANG_L")"
SHA256="$(sha256sum "$ZIP" | cut -d' ' -f1)"
DURATION="$((DUR / 60))m $((DUR % 60))s"
BUILD_DATE="$(TZ=Asia/Jakarta date '+%Y-%m-%d %H:%M WIB')"

if [[ "${CLANG_FAMILY:-aosp}" == neutron ]]; then CLANG_NAME="Neutron Clang"; else CLANG_NAME="AOSP Clang"; fi

ROOT_NAME=""
for _r in "$PROJ"/main/etc/root/ksu/*/; do
  _n="$(basename "$_r")"
  [[ "$TAG" == *-"$_n" ]] && ROOT_NAME="$_n"
done

ROOT_LABEL=""; SUSFS_VERSION=""
if [[ -n "$ROOT_NAME" ]]; then
  ROOT_LABEL="$("$PROJ/main/etc/root/load.sh" label "$ROOT_NAME")"
  SUSFS_VERSION="$(source "$PROJ/main/etc/root/susfs/susfs.sh"; echo "$SUSFS_VERSION")"
fi

KCOMMIT="$(git -C "$PROJ/.build/kernel-src" rev-parse --short=7 HEAD 2>/dev/null || echo "-")"
BCOMMIT="$(git -C "$PROJ" rev-parse --short=7 HEAD)"
SRV="${GITHUB_SERVER_URL:-https://github.com}"
BURL="$SRV/${GITHUB_REPOSITORY:-}/commit/$(git -C "$PROJ" rev-parse HEAD)"
RURL="$SRV/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-0}"

ROOT_LINE=""
if [[ -n "$ROOT_NAME" ]]; then
  _kv="$(sed -nE 's/.*KernelSU version: ([0-9]+).*/\1/p' "$OUT/build.log" | head -1)"
  _kn="$(sed -nE 's/.*KernelSU version full: (v[0-9][^-@ ]*).*/\1/p' "$OUT/build.log" | head -1)"
  _ku="$(sed -nE 's/.*KERNEL_SU_UAPI_VERSION *= *([0-9]+).*/\1/p' "$PROJ/.build/root/$ROOT_NAME/uapi/supercall.h" 2>/dev/null | head -1)"
  ROOT_LINE="${ROOT_LABEL} ${_kn}${_kv:+ ($_kv${_ku:+/$_ku})}"
fi

BULLETS=("ADIOS I/O Scheduler" "BORE Scheduler")
[[ "$TAG" == *droidspaces* ]] && BULLETS+=("Droidspaces")
BULLETS+=("kcompressd + le9uo")
[[ "$TAG" == *-nomount* ]] && BULLETS+=("NoMount $("$PROJ/main/etc/nomount/load.sh" version 2>/dev/null || true)")
BULLETS+=("NTSync" "Reflex CPU Governor")
[[ -n "$ROOT_NAME" ]] && BULLETS+=("SuSFS $SUSFS_VERSION")
LTO_LABEL="No LTO"
for _l in "$PROJ"/main/etc/lto/*/; do
  _n="$(basename "$_l")"
  [[ "$TAG" == *-"$_n" || "$TAG" == *-"$_n"-* ]] && LTO_LABEL="$("$PROJ/main/etc/lto/load.sh" label "$_n")"
done
BULLETS+=("TCP: BBRv3" "$LTO_LABEL")
mapfile -t BULLETS < <(printf '%s\n' "${BULLETS[@]}" | LC_ALL=C sort -f)

CAPTION="${BRAND} ${KERNEL_VER}"
[[ -n "$ROOT_LINE" ]] && CAPTION+=$'\n'"$ROOT_LINE"
CAPTION+=$'\n'
for b in "${BULLETS[@]}"; do CAPTION+=$'\n'"• $b"; done

DETAIL="<b>Build Info:</b>
⚙️ Clang: ${CLANG_NAME} ${CLANG_V}
🔐 SHA256: <code>${SHA256}</code>
⏱️ Duration: ${DURATION}
📅 Date: ${BUILD_DATE}
🧬 Kernel Commit: ${KCOMMIT}
🛠️ Builder Commit: <a href=\"${BURL}\">${BCOMMIT}</a>
🏃 Run: <a href=\"${RURL}\">#${GITHUB_RUN_NUMBER:-0}</a>"

# POST with retry on 429 (honours retry_after); the response body lands in $RESP.
RESP=""
send() {
  local method="$1"; shift
  local n=0 wait
  while :; do
    RESP="$(curl -sS --max-time 900 -X POST "$API/$method" "$@" || true)"
    if echo "$RESP" | jq -e '.ok' >/dev/null 2>&1; then return 0; fi
    wait="$(echo "$RESP" | jq -r '.parameters.retry_after // empty' 2>/dev/null || true)"
    n=$((n + 1))
    if [[ -n "$wait" && $n -lt 5 ]]; then
      echo "$method rate limited, retrying in $((wait + 2))s ($n/4)" >&2
      sleep $((wait + 2))
      continue
    fi
    echo "$method failed: $(echo "$RESP" | jq -r '.description // .' 2>/dev/null || echo "$RESP")" >&2
    return 1
  done
}

send sendDocument -F chat_id="$TELEGRAM_CHAT_ID" --form-string caption="$CAPTION" \
  -F document=@"$ZIP" || exit 1
MSG_ID="$(echo "$RESP" | jq -r '.result.message_id')"

send sendMessage -d chat_id="$TELEGRAM_CHAT_ID" -d parse_mode=HTML \
  -d reply_to_message_id="$MSG_ID" -d disable_web_page_preview=true \
  --data-urlencode text="$DETAIL" || exit 1
echo "Telegram post sent."
