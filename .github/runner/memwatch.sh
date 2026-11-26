#!/usr/bin/env bash
while sleep 60; do
  echo "[memwatch $(date -u +%H:%M:%S)] $(free -m | awk '/^Mem:/{printf "ram used %s/%s MB", $3, $2} /^Swap:/{printf ", swap used %s/%s MB", $3, $2}') | top: $(ps -eo rss=,comm= --sort=-rss | head -1 | awk '{printf "%s %d MB", $2, $1/1024}')"
done
