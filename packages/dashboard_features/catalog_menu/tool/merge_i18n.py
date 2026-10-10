#!/usr/bin/env python3
"""Merge the catalog_menu units' i18n supplements into the area-level tables.

Each unit owns assets/i18n/<unit>.en.json and <unit>.ar.json (flat dotted keys, the
web's English and a correct Arabic). Today dashboard_core reads a supplement's language
from its file name (`items.en.json` reads as language "items.en"), so the unit files are
not used yet; the area-level assets/i18n/en.json and ar.json are. Run this after editing
a unit file:

    python3 packages/dashboard_features/catalog_menu/tool/merge_i18n.py

It rewrites en.json and ar.json as the union of every unit file (stdlib only, safe to
run concurrently: every run reads every unit file). A key defined by two units with
different text is an error. Once the core reads `<unit>.<lang>.json` the unit files load
directly and the merged copies are harmless duplicates.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
I18N = os.path.join(HERE, "assets", "i18n")


def main():
    problems = []
    for lang in ("en", "ar"):
        merged = {}
        owner = {}
        for name in sorted(os.listdir(I18N)):
            parts = name.split(".")
            if len(parts) != 3 or parts[1] != lang or parts[2] != "json":
                continue
            unit = parts[0]
            with open(os.path.join(I18N, name), encoding="utf-8") as f:
                table = json.load(f)
            for key, text in table.items():
                if key in merged and merged[key] != text:
                    problems.append(f"{lang}: {key} differs in {owner[key]} and {unit}")
                    continue
                merged[key] = text
                owner[key] = unit
        out = os.path.join(I18N, f"{lang}.json")
        tmp = out + f".{os.getpid()}.tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(json.dumps(dict(sorted(merged.items())), ensure_ascii=False, indent=2) + "\n")
        os.replace(tmp, out)
        print(f"{out}: {len(merged)} keys")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
