#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update -q
sudo apt-get install -y -q build-essential ccache bc bison flex libssl-dev libelf-dev dwarves \
  lz4 zstd cpio python3 zip unzip xxd rsync gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
pahole --version
