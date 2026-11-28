#!/usr/bin/env bash
# Records the outcome of a scout candidate in main/config/checkpoint.json (pushed to main):
#   success -> the candidate becomes the new good pin
#   failure -> the candidate is added to the bad list and never tried again
set -euo pipefail

OUTCOME="${1:?usage: checkpoint.sh success|failure}"
KEY="${SCOUT_KEY:-}"; REF="${SCOUT_REF:-}"
[[ -n "$KEY" && -n "$REF" ]] || { echo "checkpoint: no candidate in this run, nothing to record"; exit 0; }
: "${GH_TOKEN:?GH_TOKEN is not set}"
: "${GITHUB_REPOSITORY:?}"

REL="main/config/checkpoint.json"
case "$OUTCOME" in
  success) FILTER='.[$k].good = $s | .[$k].bad -= [$s]'; MSG="checkpoint: ${KEY} -> ${REF:0:8} verified (run ${GITHUB_RUN_ID:-local})" ;;
  failure) FILTER='.[$k].bad |= ((. + [$s]) | unique)';  MSG="checkpoint: ${KEY} ${REF:0:8} marked bad (run ${GITHUB_RUN_ID:-local})" ;;
  *) echo "checkpoint: unknown outcome '$OUTCOME'" >&2; exit 2 ;;
esac

REMOTE="https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

for attempt in 1 2 3 4 5; do
  rm -rf "$TMP/r"
  if git clone -q --depth 1 --branch main "$REMOTE" "$TMP/r"; then
    jq --arg k "$KEY" --arg s "$REF" "$FILTER" "$TMP/r/$REL" > "$TMP/new.json"
    cp "$TMP/new.json" "$TMP/r/$REL"
    if git -C "$TMP/r" diff --quiet; then echo "checkpoint: already recorded"; exit 0; fi
    git -C "$TMP/r" -c user.name="88days bot" -c user.email="noreply@github.com" commit -q -am "$MSG"
    if git -C "$TMP/r" push -q origin HEAD:main; then echo "checkpoint: $MSG"; exit 0; fi
  fi
  echo "checkpoint: attempt $attempt failed, retrying" >&2
  sleep $(( RANDOM % 5 + 3 ))
done
echo "checkpoint: could not record the result after 5 attempts" >&2
exit 1
