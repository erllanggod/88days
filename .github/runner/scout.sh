#!/usr/bin/env bash
# Scout: for the selected root, try the newest upstream commit of the root source and of SUSFS.
#   - a new commit is used as a "candidate" (at most one candidate per run, so a failure has one suspect)
#   - a known-bad or unreachable upstream falls back to the last pin that built fine
# The result is exported through GITHUB_ENV; checkpoint.sh promotes or blacklists the candidate afterwards.
set -euo pipefail

ROOT="${1:?usage: scout.sh <root>}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CK="$PROJ/main/config/checkpoint.json"
OUT="${GITHUB_ENV:-/dev/stdout}"

log()  { echo "scout: $*"; }
warn() { echo "scout: $*" >&2; }

if [[ "${SCOUT:-on}" == off ]]; then
  log "disabled (SCOUT=off), using the pinned commits"
  exit 0
fi

CLAIMED=""
resolve() {
  local role="$1" key="$2" repo="$3" branch="$4" good latest bad ref="" cand=0
  good="$(jq -r --arg k "$key" '.[$k].good // empty' "$CK")"
  [[ -n "$good" ]] || { warn "$key: no good pin in checkpoint.json"; exit 1; }
  latest="$(git ls-remote "$repo" "refs/heads/$branch" 2>/dev/null | awk '{print $1}' | head -1 || true)"
  if [[ -z "$latest" ]]; then
    warn "$key: cannot reach $repo ($branch), using good ${good:0:8}"; ref="$good"
  elif [[ "$latest" == "$good" ]]; then
    log "$key: up to date at ${good:0:8}"; ref="$good"
  elif jq -e --arg k "$key" --arg s "$latest" '.[$k].bad | index($s)' "$CK" >/dev/null; then
    warn "$key: latest ${latest:0:8} is known bad, falling back to good ${good:0:8}"; ref="$good"
  elif [[ -n "$CLAIMED" ]]; then
    log "$key: new commit ${latest:0:8} postponed ($CLAIMED is the candidate this run), using good ${good:0:8}"; ref="$good"
  else
    log "$key: candidate ${latest:0:8} (good: ${good:0:8})"; ref="$latest"; cand=1; CLAIMED="$key"
  fi
  case "$role" in
    root)  echo "ROOT_REF_OVERRIDE=$ref" >> "$OUT" ;;
    susfs) echo "SUSFS_REF_OVERRIDE=$ref" >> "$OUT" ;;
  esac
  if [[ "$cand" == 1 ]]; then
    { echo "SCOUT_KEY=$key"; echo "SCOUT_REF=$ref"; } >> "$OUT"
  fi
}

while read -r key repo branch; do
  role=root; [[ "$key" == "$ROOT" ]] || role=susfs
  resolve "$role" "$key" "$repo" "$branch"
done < <("$PROJ/main/etc/root/load.sh" components "$ROOT")
