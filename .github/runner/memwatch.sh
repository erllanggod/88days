#!/usr/bin/env bash
# Prints memory/swap and the biggest process once a minute, so a link that dies still leaves numbers in the log.
while sleep 60; do
  echo "[memwatch $(date -u +%H:%M:%S)] $(free -m | awk '/^Mem:/{printf "ram used %s/%s MB", $3, $2} /^Swap:/{printf ", swap used %s/%s MB", $3, $2}') | top: $(ps -eo rss=,comm= --sort=-rss | head -1 | awk '{printf "%s %d MB", $2, $1/1024}')"
done
