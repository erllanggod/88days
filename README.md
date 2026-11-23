# 88days

Kernel builder for Xiaomi POCO F7 / Redmi Turbo 4 Pro (`onyx`, SM8735).

- Source: private `qwerty` (Google ACK `android15-6.6-lts` 6.6.162 plus the KMI-safe patch set).
- Toolchain: Android clang r510928 (the compiler of the stock kernel). LTO none.
- Gates: 6-layer KMI/ABI/kCFI check against the stock firmware modules (private material, not in this repo).
- Output: AnyKernel3 zip, release `6.6.162-DumpC2J`.

Run it from Actions > Build > Run workflow.

## Credits

The build/gate pipeline (`build.sh`, `lib/`) and the patch set originate from
[riza220201/poco-f7-kernel](https://github.com/riza220201/poco-f7-kernel), adapted here.
AnyKernel3 by osm0sis and contributors.
