import html
import json
import os
import sys

zip_path, out_path = sys.argv[1], sys.argv[2]
e = os.environ


def esc(s):
    return html.escape(str(s), quote=True).replace("\n", " ").strip()


def chip(text, style=""):
    st = f' style="{style}"' if style else ""
    return f'<tg-button type="disabled"{st}>{esc(text)}</tg-button>'


ds = e.get("DROIDSPACES", "0") == "1"
rows = [
    ("Kernel", esc(e["KERNEL_VER"])),
    ("Toolchain", esc(e["CLANG_STR"])),
    ("LTO", chip("No LTO")),
    ("Droidspaces", chip("Enable", "success") if ds else chip("Disable", "danger")),
]
if e.get("ROOT_LABEL"):
    rows.append(("Root", chip(e["ROOT_LABEL"], "success")))
    rows.append(("SUSFS", chip(e["SUSFS_VERSION"], "success")))
else:
    rows.append(("Root", chip("Disable", "danger")))
table = "<table bordered>" + "".join(
    f"<tr><td>{k}</td><td>{v}</td></tr>" for k, v in rows
) + "</table>"

more = [
    ("BORE", "burst-oriented CPU scheduler"),
    ("Reflex", "responsive CPU governor"),
    ("ADIOS", "adaptive I/O scheduler"),
    ("kcompressd + le9uo", "better memory handling"),
    ("NTSync", "faster Wine/Proton sync"),
    ("BBRv3", "TCP congestion control"),
    ("Onyx balance", "tuned for onyx"),
    ("DS4 clone HID", "controller clones supported"),
]
feat = (
    "<details>\n<summary>Features</summary>\n\n<table bordered>"
    + "".join(f"<tr><td>{esc(k)}</td><td>{esc(v)}</td></tr>" for k, v in more)
    + "</table>\n</details>"
)

parts = [
    f'<tg-button-row><tg-button type="disabled" style="primary">{esc(e["TG_TITLE"])}</tg-button></tg-button-row>',
    table,
    "![](tg://document?id=zip1)",
    feat,
]

md = "\n\n".join(parts) + "\n"
payload = {
    "markdown": md,
    "media": [{"id": "zip1", "media": {"type": "document", "media": "attach://zip_1"}}],
}
if len(md) > 32768:
    sys.exit("rich message too long")
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False)
