#!/usr/bin/env bash
set -euo pipefail

: "${MAGISK_URL:?MAGISK_URL is empty}"
: "${RUNNER_TEMP:?RUNNER_TEMP is empty}"

curl -fsSL --retry 3 -o "$RUNNER_TEMP/magisk.apk" "$MAGISK_URL"
for t in magiskboot busybox magiskpolicy; do
  unzip -p "$RUNNER_TEMP/magisk.apk" "lib/arm64-v8a/lib$t.so" > "$RUNNER_TEMP/$t"
  chmod +x "$RUNNER_TEMP/$t"
  file "$RUNNER_TEMP/$t" | grep -q 'ARM aarch64'
done
echo "AK_TOOLS_ARM64=$RUNNER_TEMP" >> "$GITHUB_ENV"
