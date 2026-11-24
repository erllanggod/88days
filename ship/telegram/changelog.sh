#!/usr/bin/env bash
set -euo pipefail

BASE="${CHANGELOG_BASE:-}"
if [[ -n "$BASE" ]] && git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  RANGE=("$BASE..HEAD")
else
  RANGE=(-n 5)
fi

declare -A G=([Added]="" [Fixed]="" [Changed]="")
while IFS= read -r subj; do
  [[ -z "$subj" ]] && continue
  type="${subj%%:*}"; msg="${subj#*: }"
  [[ "$subj" == *:* ]] || { type="change"; msg="$subj"; }
  type="${type%%(*}"
  case "$type" in
    ci|docs|chore|style|test) continue ;;
    feat|add)            grp=Added ;;
    fix)                 grp=Fixed ;;
    *)                   grp=Changed ;;
  esac
  msg="$(tr '[:lower:]' '[:upper:]' <<< "${msg:0:1}")${msg:1}"
  G[$grp]+="$msg"$'\n'
done < <(git log --no-merges --reverse --format=%s "${RANGE[@]}")

for grp in Added Fixed Changed; do
  while IFS= read -r l; do
    [[ -n "$l" ]] && echo "$grp: $l"
  done <<< "${G[$grp]}"
done
