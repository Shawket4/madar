#!/usr/bin/env python3
"""Run `flutter test` or `flutter analyze` for one dashboard package, safely, while many
agents do the same on one Mac.

  tool/fdash_test.py <package dir> [test files or flutter test args...]
  tool/fdash_test.py --analyze <package dir> [paths...]

- A per-package lock: two test runs in one package would share its build/ and .dart_tool
  caches and trip over each other, so they take turns.
- A global cap (FDASH_SLOTS, default 8) on concurrent runs across all packages: each run is
  a Dart compile of 1-2 GB, and more than ~8 at once pushes a 24 GB Mac into swap.
- FLUTTER_ALREADY_LOCKED=true and --no-pub, as the spec requires; FDASH_SHOTS passes through.

Standard library only. Exits with flutter's exit code.
"""
import fcntl
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCKS = os.path.join(ROOT, ".locks")
SLOTS = int(os.environ.get("FDASH_SLOTS", "8"))


def lock_file(name):
    os.makedirs(LOCKS, exist_ok=True)
    return open(os.path.join(LOCKS, name), "w")


def take_slot():
    """Block until one of the global slots is free; return its open (locked) file."""
    waited = 0.0
    while True:
        for i in range(SLOTS):
            f = lock_file(f"slot-{i}.lock")
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                if waited:
                    print(f"[fdash_test] got a slot after {waited:.0f}s", file=sys.stderr)
                return f
            except BlockingIOError:
                f.close()
        time.sleep(2)
        waited += 2


def main(argv):
    analyze = bool(argv) and argv[0] == "--analyze"
    if analyze:
        argv = argv[1:]
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    pkg = os.path.abspath(argv[0])
    rest = argv[1:]
    if not os.path.isfile(os.path.join(pkg, "pubspec.yaml")):
        print(f"[fdash_test] not a package: {pkg}", file=sys.stderr)
        return 2

    pkg_lock = None
    if not analyze:
        pkg_lock = lock_file("pkg-" + os.path.relpath(pkg, ROOT).replace("/", "_") + ".lock")
        t0 = time.time()
        fcntl.flock(pkg_lock, fcntl.LOCK_EX)
        if time.time() - t0 > 1:
            print(f"[fdash_test] waited {time.time() - t0:.0f}s for the package lock", file=sys.stderr)
    slot = take_slot()
    try:
        env = {**os.environ, "FLUTTER_ALREADY_LOCKED": "true"}
        if analyze:
            cmd = ["flutter", "analyze", *(rest or ["lib", "test"])]
        else:
            cmd = ["flutter", "test", "--no-pub", *rest]
        return subprocess.call(cmd, cwd=pkg, env=env)
    finally:
        slot.close()
        if pkg_lock:
            pkg_lock.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
