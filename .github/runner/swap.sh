#!/usr/bin/env bash
# Extra swap on the big /mnt disk, so a memory-hungry link survives instead of being OOM-killed.
set -euo pipefail

SIZE_GB="${1:-28}"
free -h
sudo swapoff -a || true
sudo rm -f /mnt/swapfile
sudo fallocate -l "${SIZE_GB}G" /mnt/swapfile
sudo chmod 600 /mnt/swapfile
sudo mkswap /mnt/swapfile >/dev/null
sudo swapon /mnt/swapfile
# keep the runner agent responsive: swap only when RAM is really short
sudo sysctl -q vm.swappiness=10
free -h
