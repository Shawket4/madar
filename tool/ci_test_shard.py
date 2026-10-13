#!/usr/bin/env python3
"""Which Flutter packages one CI test shard runs (.github/workflows/ci.yml).

    python3 tool/ci_test_shard.py <shard> <shards>   # that shard's packages, one per line
    python3 tool/ci_test_shard.py --plan <shards>    # every shard, with its weight

Every package with tests is found by its pubspec.yaml, as before, so a new
package is picked up with no change here. Packages are spread over the shards
by their number of tests (test( / testWidgets( calls), heaviest first, each to
the lightest shard so far: a test count follows a package's run time closely
enough to keep the shards within a few minutes of each other.

Not here: packages/rust_bridge (the host tests, their own step) and the staff
app's tree (staff-ci.yml).
"""
import pathlib
import re
import subprocess
import sys

SKIP_EXACT = {".", "packages/rust_bridge", "apps/staff", "packages/staff_core", "packages/rust_bridge_staff"}
SKIP_PREFIX = ("packages/features/dawam_",)
TEST_CALL = re.compile(r"\b(?:testWidgets|test)\(")


def packages() -> list[tuple[str, int]]:
    files = subprocess.run(["git", "ls-files", "*pubspec.yaml"], check=True, capture_output=True, text=True).stdout.split()
    found = []
    for f in sorted(files):
        if "/cargokit/" in f:
            continue
        pkg = str(pathlib.Path(f).parent)
        if pkg in SKIP_EXACT or pkg.startswith(SKIP_PREFIX):
            continue
        tests = list(pathlib.Path(pkg, "test").rglob("*_test.dart"))
        if not tests:  # an empty test/ makes `flutter test` exit non-zero
            continue
        weight = sum(len(TEST_CALL.findall(t.read_text(errors="ignore"))) for t in tests)
        found.append((pkg, max(weight, 1)))
    return found


def plan(shards: int) -> list[tuple[int, list[str]]]:
    bins: list[tuple[int, list[str]]] = [(0, []) for _ in range(shards)]
    for pkg, weight in sorted(packages(), key=lambda p: (-p[1], p[0])):
        i = min(range(shards), key=lambda k: bins[k][0])
        bins[i] = (bins[i][0] + weight, bins[i][1] + [pkg])
    return bins


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "--plan":
        for i, (weight, pkgs) in enumerate(plan(int(sys.argv[2]))):
            print(f"shard {i}: {weight} tests: {' '.join(pkgs)}")
        return
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    shard, shards = int(sys.argv[1]), int(sys.argv[2])
    if not 0 <= shard < shards:
        sys.exit(f"shard {shard} is not in 0..{shards - 1}")
    print("\n".join(plan(shards)[shard][1]))


if __name__ == "__main__":
    main()
