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

DUR=$(( $(date +%s) - ${BUILD_START:-$(date +%s)} ))
export KERNEL_REL="$(cat "$OUT/kernel.release")"
export CLANG_STR="$("${CLANG_DIR:-$PROJ/.build/clang}/bin/clang" --version | head -1 | sed -E 's/ \(https.*//; s/^.*clang version/clang/')"
export SIZE="$(du -h "$ZIP" | cut -f1)"
export SHA256="$(sha256sum "$ZIP" | cut -d' ' -f1)"
export DURATION="$((DUR / 60))m $((DUR % 60))s"
export BUILD_DATE="$(date -u '+%Y-%m-%d %H:%M UTC')"
export TG_TITLE="${BRAND} · Vanilla"
export DROIDSPACES=$([[ "$TAG" == *droidspaces* ]] && echo 1 || echo 0)
export CHANGELOG="$("$PROJ/release/telegram/changelog.sh" || true)"

PAYLOAD="$(mktemp)"; trap 'rm -f "$PAYLOAD"' EXIT
python3 "$PROJ/release/telegram/payload.py" "$ZIP" "$PAYLOAD"

send() {
  local method="$1"; shift
  local n=0 R wait
  while :; do
    R="$(curl -sS --max-time 900 -X POST "$API/$method" "$@" || true)"
    if echo "$R" | jq -e '.ok' >/dev/null 2>&1; then return 0; fi
    wait="$(echo "$R" | jq -r '.parameters.retry_after // empty' 2>/dev/null || true)"
    n=$((n + 1))
    if [[ -n "$wait" && $n -lt 5 ]]; then
      echo "$method rate limited, retrying in $((wait + 2))s ($n/4)" >&2
      sleep $((wait + 2))
      continue
    fi
    echo "$method failed: $(echo "$R" | jq -r '.description // .' 2>/dev/null || echo "$R")" >&2
    return 1
  done
}

if send sendRichMessage -F chat_id="$TELEGRAM_CHAT_ID" -F "rich_message=<$PAYLOAD" \
     -F "zip_1=@$ZIP;filename=$(basename "$ZIP")"; then
  echo "Telegram rich post sent."; exit 0
fi

send sendDocument -F chat_id="$TELEGRAM_CHAT_ID" --form-string caption="${TG_TITLE} · ${KERNEL_REL}" \
  -F document=@"$ZIP" || exit 1
echo "Telegram fallback post sent."
