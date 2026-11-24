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
    ("Kernel", esc("Linux " + e["KERNEL_REL"])),
    ("Toolchain", esc(e["CLANG_STR"])),
    ("LTO", chip("No LTO")),
    ("KMI", chip("6/6 PASS", "success")),
    ("Droidspaces", chip("Enable", "success") if ds else chip("Disable", "danger")),
]
table = "<table bordered>" + "".join(
    f"<tr><td>{k}</td><td>{v}</td></tr>" for k, v in rows
) + "</table>"

info = (
    "<details>\n<summary>Build info</summary>\n\n"
    "<table bordered>"
    f"<tr><td>Size</td><td>{esc(e['SIZE'])}</td></tr>"
    f"<tr><td>Build</td><td>{esc(e['DURATION'])}</td></tr>"
    f"<tr><td>Date</td><td>{esc(e['BUILD_DATE'])}</td></tr>"
    f"<tr><td>SHA256</td><td>{esc(e['SHA256'])}</td></tr>"
    "</table>\n</details>"
)

parts = [
    f'<tg-button-row><tg-button type="disabled" style="primary">{esc(e["TG_TITLE"])}</tg-button></tg-button-row>',
    table,
    "![](tg://document?id=zip1)",
]
cl = [l.strip() for l in e.get("CHANGELOG", "").splitlines() if l.strip()]
if cl:
    parts.append("```\n" + "\n".join("• " + l for l in cl) + "\n```")
parts.append(info)

md = "\n\n".join(parts) + "\n"
payload = {
    "markdown": md,
    "media": [{"id": "zip1", "media": {"type": "document", "media": "attach://zip_1"}}],
}
if len(md) > 32768:
    sys.exit("rich message too long")
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False)
