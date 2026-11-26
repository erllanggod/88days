# Full LTO links the whole kernel in one lld process; DWARF + BTF make that blow past the runner's RAM.
LTO_LABEL="Full LTO"
REQUIRED=(LTO_CLANG_FULL DEBUG_INFO_NONE)
UNSET=(LTO_NONE DEBUG_INFO_BTF DEBUG_INFO_DWARF5 DEBUG_INFO_COMPRESSED_ZSTD)
