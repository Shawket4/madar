#!/usr/bin/env python3
"""Copy the web dashboard's UI strings into dashboard_core, flattened.

    tool/sync_dashboard_i18n.py [--web <MadarDashboard dir>] [--check]

Reads MadarDashboard/src/i18n/locales/{en,ar}.json (nested, i18next) and writes
packages/dashboard_core/assets/i18n/{en,ar}.json as ONE flat object of dotted
keys -> strings, in the source's order:

- nested objects join with "." (`orders.voidTitle`);
- arrays become indexed keys (`aiChat.loading.0`, `.1`, ...), which is how
  `Strings.list()` reads them back;
- null leaves are dropped (i18next treats a null as missing: `returnNull: false`);
- plural forms keep i18next's suffixes (`_zero _one _two _few _many _other`).

`--check` writes nothing and exits 1 when the assets differ from what a sync
would write (CI / the parity test use it). Standard library only. The web repo
is read-only: this never writes there.
"""
import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_WEB = "/Users/shawket/Desktop/Madar/MadarDashboard"
OUT_DIR = os.path.join(ROOT, "packages", "dashboard_core", "assets", "i18n")
LANGS = ("en", "ar")


def flatten(node, prefix, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if "." in k:
                raise SystemExit(f"key segment with a dot would be ambiguous: {prefix}{k}")
            flatten(v, f"{prefix}{k}.", out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            flatten(v, f"{prefix}{i}.", out)
    elif node is None:
        return
    elif isinstance(node, str):
        out[prefix[:-1]] = node
    elif isinstance(node, bool):
        out[prefix[:-1]] = "true" if node else "false"
    else:
        out[prefix[:-1]] = str(node)


def render(lang, web):
    with open(os.path.join(web, "src", "i18n", "locales", f"{lang}.json"), encoding="utf-8") as f:
        src = json.load(f)
    flat = {}
    flatten(src, "", flat)
    return json.dumps(flat, ensure_ascii=False, indent=1) + "\n"


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--web", default=DEFAULT_WEB)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    stale = []
    for lang in LANGS:
        text = render(lang, a.web)
        path = os.path.join(OUT_DIR, f"{lang}.json")
        current = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if current == text:
            continue
        if a.check:
            stale.append(path)
            continue
        os.makedirs(OUT_DIR, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"wrote {os.path.relpath(path, ROOT)} ({len(json.loads(text))} keys)")
    if stale:
        print("stale (run tool/sync_dashboard_i18n.py):", *stale, sep="\n  ", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
