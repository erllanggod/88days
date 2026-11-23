#!/usr/bin/env python3
"""
kcfi_check.py — Gate Layer 6: Cross-Compiler Modern kCFI Type-ID Verifier.

Why this exists:
  Linux 6.1+ uses modern Clang kCFI (CONFIG_CFI_CLANG=y, -fsanitize=kcfi).
  Every indirect call loads the 32-bit XXH64 type hash embedded 4 bytes before
  the target function entry point (`ldur w16, [xTarget, #-4]`) and compares it
  against the caller's expected 32-bit `__kcfi_typeid_<fn>` constant.

  When stock vendor / system_dlkm .ko modules (compiled with Google Clang 18)
  take the address of an exported vmlinux function (or pass callbacks across
  the vmlinux <-> module boundary), the .ko ELF records an SHN_ABS symbol
  `__kcfi_typeid_<fn>` whose `st_value` is the 32-bit kCFI type ID expected by
  that module. If a kernel compiled with Neutron Clang 24 emits a different
  32-bit kCFI type ID before `<fn>` in vmlinux, the indirect call panics at
  runtime (`CFI failure at ...`) even when all genksyms CRCs match 100%.

  This gate extracts:
    1. Every `__kcfi_typeid_<fn>` symbol across all stock .ko modules in the
       provided KMI reference trees (923 modules -> 239 vmlinux exported
       functions).
    2. The kernel's 32-bit kCFI type IDs from either:
       - a built `vmlinux` ELF (`__kcfi_typeid_<fn>` symbols in .symtab AND
         the 32-bit word at `st_value(fn) - 4` in .text for every STT_FUNC), OR
       - a raw uncompressed ARM64 `Image` (by scanning `__ksymtab` +
         `__ksymtab_gpl` PREL32 entries and reading the 32-bit word at
         `target_off - 4`).
    3. Fails if any vmlinux function's kCFI type ID is missing or mismatches
       what the stock .ko modules expect.
"""
import argparse
import glob
import os
import struct
import sys

SHT_SYMTAB = 2
STT_FUNC = 2


def valid_ident(b: bytes) -> bool:
    return (
        bool(b)
        and len(b) <= 128
        and all(
            (48 <= c <= 57) or (65 <= c <= 90) or (97 <= c <= 122) or c in (95, 46)
            for c in b
        )
    )


def extract_kcfi_from_elf(path: str):
    """Return ({fn: kcfi_u32}, is_elf) from an ELF vmlinux or .ko."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        return {}, False
    e_shoff = struct.unpack_from("<Q", data, 40)[0]
    e_shentsize, e_shnum, _ = struct.unpack_from("<HHH", data, 58)
    shdrs = [
        struct.unpack_from("<IIQQQQIIQQ", data, e_shoff + i * e_shentsize)
        for i in range(e_shnum)
    ]
    symtab = next((sh for sh in shdrs if sh[1] == SHT_SYMTAB), None)
    if not symtab:
        return {}, True
    str_sh = shdrs[symtab[6]]
    strtab = data[str_sh[4] : str_sh[4] + str_sh[5]]
    symdata = data[symtab[4] : symtab[4] + symtab[5]]
    entsize = symtab[9] or 24
    out = {}
    funcs = []
    for off in range(0, len(symdata), entsize):
        st_name, st_info, _, st_shndx, st_value, _ = struct.unpack_from(
            "<IBBHQQ", symdata, off
        )
        if not st_name:
            continue
        end = strtab.find(b"\x00", st_name)
        if end < 0:
            continue
        nm = strtab[st_name:end]
        if nm.startswith(b"__kcfi_typeid_"):
            fn = nm[14:].decode("ascii", "replace")
            out[fn] = st_value & 0xFFFFFFFF
        elif (st_info & 0xF) == STT_FUNC and 0 < st_shndx < len(shdrs):
            bind = st_info >> 4
            funcs.append((nm.decode("ascii", "replace"), st_shndx, st_value, bind))

    # For vmlinux ELF, read the 32-bit word 4 bytes before each STT_FUNC entry.
    # Global/weak symbols (bind != 0) are the exported definitions and must take
    # precedence over file-local static functions (bind == 0) of the same name.
    funcs.sort(key=lambda item: (item[3] == 0))
    for fn, shndx, addr, _ in funcs:
        if fn in out:
            continue
        sec = shdrs[shndx]
        sec_addr, sec_off, sec_sz = sec[3], sec[4], sec[5]
        rel = addr - sec_addr
        if 4 <= rel <= sec_sz:
            file_off = sec_off + rel - 4
            if 0 <= file_off <= len(data) - 4:
                out[fn] = struct.unpack_from("<I", data, file_off)[0]
    return out, True


def extract_kcfi_from_raw_image(path: str):
    """Extract {fn: kcfi_u32} from an uncompressed ARM64 Image via __ksymtab PREL32."""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 0x100000 or data[0x38:0x3C] != b"ARM\x64":
        return None

    def get_sym(off: int):
        if off < 0 or off + 12 > len(data):
            return None
        v_off, n_off, ns_off = struct.unpack_from("<iii", data, off)
        if (
            abs(v_off) > 0x3000000
            or abs(n_off) > 0x200000
            or abs(ns_off) > 0x200000
        ):
            return None
        n_pos = off + 4 + n_off
        ns_pos = off + 8 + ns_off
        if not (0 <= n_pos < len(data) and 0 <= ns_pos < len(data)):
            return None
        n_end = data.find(b"\x00", n_pos, n_pos + 129)
        ns_end = data.find(b"\x00", ns_pos, ns_pos + 129)
        if n_end < 0 or ns_end < 0:
            return None
        name = data[n_pos:n_end]
        ns = data[ns_pos:ns_end]
        if not valid_ident(name) or (ns and not valid_ident(ns)):
            return None
        return (off + v_off, name.decode("ascii"))

    seed = None
    pos = 0
    while True:
        idx = data.find(b"module_layout\x00", pos)
        if idx < 0:
            break
        if idx == 0 or data[idx - 1] == 0:
            lo = max(0, idx - 0x200000) & ~3
            hi = min(len(data) - 12, idx + 0x200000)
            for off in range(lo, hi, 4):
                val = struct.unpack_from("<i", data, off)[0]
                if off + val == idx:
                    cand = off - 4
                    if get_sym(cand) and get_sym(cand - 12) and get_sym(cand + 12):
                        seed = cand
                        break
        if seed is not None:
            break
        pos = idx + 1

    if seed is None:
        return None

    start = seed
    while get_sym(start - 12):
        start -= 12
    end = seed
    while get_sym(end):
        end += 12

    count = (end - start) // 12
    if count < 1000:
        return None

    out = {}
    for i in range(count):
        target_off, fn = get_sym(start + i * 12)
        if 4 <= target_off <= len(data) - 4:
            out[fn] = struct.unpack_from("<I", data, target_off - 4)[0]
    return out


def load_symvers_names(path: str):
    names = set()
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            p = line.strip().split()
            if len(p) >= 2:
                names.add(p[1])
    return names


def main():
    ap = argparse.ArgumentParser(
        description="Gate Layer 6: Cross-compiler modern kCFI type-ID verifier"
    )
    ap.add_argument(
        "kernel",
        help="Path to built vmlinux ELF or uncompressed arm64 Image",
    )
    ap.add_argument(
        "symvers",
        help="Path to vmlinux.symvers or stock.symvers",
    )
    ap.add_argument(
        "kmi_ref",
        nargs="+",
        help="One or more KMI reference directories containing .ko modules",
    )
    ap.add_argument(
        "--min-checked",
        type=int,
        default=100,
        help="Minimum vmlinux kCFI functions that must be checked",
    )
    args = ap.parse_args()

    if not os.path.isfile(args.kernel) or not os.path.isfile(args.symvers):
        sys.stderr.write("FAIL [kcfi_check]: missing kernel or symvers file\n")
        return 2

    vmlinux_exports = load_symvers_names(args.symvers)
    if len(vmlinux_exports) < 1000:
        sys.stderr.write(
            f"FAIL [kcfi_check]: vacuous symvers ({len(vmlinux_exports)} symbols)\n"
        )
        return 2

    kernel_kcfi, is_elf = extract_kcfi_from_elf(args.kernel)
    if not is_elf:
        kernel_kcfi = extract_kcfi_from_raw_image(args.kernel)
    if not kernel_kcfi:
        sys.stderr.write(
            f"FAIL [kcfi_check]: could not extract kCFI type IDs from {args.kernel}\n"
        )
        return 2

    kos = []
    for ref in args.kmi_ref:
        kos.extend(sorted(glob.glob(os.path.join(ref, "**", "*.ko"), recursive=True)))
    if not kos:
        sys.stderr.write("FAIL [kcfi_check]: 0 .ko modules in reference dirs\n")
        return 2

    ko_kcfi = {}
    for ko in kos:
        d, _ = extract_kcfi_from_elf(ko)
        for fn, tid in d.items():
            ko_kcfi.setdefault(fn, (tid, os.path.basename(ko)))

    checked = 0
    missing = []
    mismatched = []
    for fn, (want_tid, ex_ko) in sorted(ko_kcfi.items()):
        if fn not in vmlinux_exports:
            continue
        if fn not in kernel_kcfi:
            missing.append((fn, want_tid, ex_ko))
        elif kernel_kcfi[fn] != want_tid:
            mismatched.append((fn, want_tid, kernel_kcfi[fn], ex_ko))
        else:
            checked += 1

    if checked < args.min_checked:
        sys.stderr.write(
            f"FAIL [kcfi_check]: vacuous check (checked={checked}, min_checked={args.min_checked})\n"
        )
        return 2

    if missing or mismatched:
        sys.stderr.write(
            f"FAIL [kcfi_check]: kos={len(kos)} checked={checked} "
            f"missing={len(missing)} mismatched={len(mismatched)}\n"
        )
        for fn, want, ko in missing[:20]:
            sys.stderr.write(
                f"  MISSING  __kcfi_typeid_{fn} (want 0x{want:08x}, used by {ko})\n"
            )
        for fn, want, got, ko in mismatched[:20]:
            sys.stderr.write(
                f"  MISMATCH __kcfi_typeid_{fn}: ko({ko}) wants 0x{want:08x}, "
                f"kernel has 0x{got:08x}\n"
            )
        return 1

    print(
        f"PASS [kcfi_check]: kos={len(kos)} module_kcfi_syms={len(ko_kcfi)} "
        f"vmlinux_kcfi_matched={checked} missing=0 mismatched=0"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
