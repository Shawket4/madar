#!/usr/bin/env python3
"""Copy the web dashboard's pinned madar-shared vectors into the Flutter dashboard.

  tool/sync_web_vectors.py [path to MadarDashboard]   (default: ../MadarDashboard)

Copies MadarDashboard/src/lib/*_vectors.json and their *_vectors.source.json (the
madar-shared tag and hash each copy is pinned to) into
packages/dashboard_core/test/vectors/, byte for byte, drops copies the web no longer
has, and checks each copy's sha256 against its .source.json (exit 1 on a mismatch).
Dart tests read them with `sharedVectors(name)` from package:dashboard_core/testing.dart.
Standard library only; prints what changed.
"""
import filecmp
import glob
import hashlib
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(ROOT, "packages", "dashboard_core", "test", "vectors")


def main(argv):
    web = os.path.abspath(argv[0] if argv else os.path.join(ROOT, "..", "MadarDashboard"))
    src_dir = os.path.join(web, "src", "lib")
    sources = sorted(glob.glob(os.path.join(src_dir, "*_vectors.json"))
                     + glob.glob(os.path.join(src_dir, "*_vectors.source.json")))
    if not sources:
        print(f"[sync_web_vectors] no *_vectors.json in {src_dir}", file=sys.stderr)
        return 2
    os.makedirs(DEST, exist_ok=True)
    names = set()
    for src in sources:
        name = os.path.basename(src)
        names.add(name)
        dst = os.path.join(DEST, name)
        if os.path.exists(dst) and filecmp.cmp(src, dst, shallow=False):
            continue
        shutil.copyfile(src, dst)
        print(f"updated {name}")
    for dst in glob.glob(os.path.join(DEST, "*_vectors*.json")):
        if os.path.basename(dst) not in names:
            os.remove(dst)
            print(f"removed {os.path.basename(dst)}")
    # Each copy must be the bytes its .source.json records for the madar-shared tag.
    bad = 0
    for meta in sorted(glob.glob(os.path.join(DEST, "*_vectors.source.json"))):
        copy = meta.replace(".source.json", ".json")
        want = json.load(open(meta))["sha256"]
        got = hashlib.sha256(open(copy, "rb").read()).hexdigest()
        if got != want:
            bad += 1
            print(f"HASH MISMATCH {os.path.basename(copy)}: {got} != {want}", file=sys.stderr)
    print(f"[sync_web_vectors] {len(names)} files in sync with {src_dir}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
