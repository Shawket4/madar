#!/usr/bin/env python3
"""Give the local "Madar Demo" org a kitchen, to run Madar Kitchen against.

LOCAL ONLY. Needs the backend on localhost (MadarRust: `cargo run --bin
madar-rust`) over a dev database seeded by `scripts/dev-staff.sh`
(`seed-staff-demo`). Refuses any API that isn't localhost and any org but the
demo one.

    python3 scripts/dev-kitchen-demo.py           # stations, menu, cook, fire 4 rounds
    python3 scripts/dev-kitchen-demo.py --fire    # just fire 2 more rounds

Then, in the app (EXPO_PUBLIC_MADAR_API=http://<this Mac's IP>:8082):
    setup   admin@demo.madar / Demo1234!   (the demo seed's admin)
    branch  the first one listed
    cook    name "Kitchen Demo", PIN 135790
"""
import json
import os
import random
import subprocess
import sys
import urllib.request
import uuid

API = os.environ.get("MADAR_API", "http://localhost:8082")
DB = os.environ.get("DATABASE_URL", "postgres://madar@localhost:5432/madar")
PSQL = os.environ.get("PSQL", "/Applications/Postgres.app/Contents/Versions/17/bin/psql")
ADMIN = ("admin@demo.madar", "Demo1234!")
COOK_NAME, COOK_PIN = "Kitchen Demo", "135790"

assert API.startswith(("http://localhost", "http://127.0.0.1")), f"refusing non-local API {API}"
assert "localhost" in DB or "127.0.0.1" in DB, f"refusing non-local database {DB}"

# section -> dishes (name, Arabic name)
MENU = {
    ("Grill", "المشويات", True): [("Mixed grill", "مشويات مشكلة"), ("Kofta", "كفتة"), ("Shish tawook", "شيش طاووق")],
    ("Cold", "البارد", False): [("Tahini salad", "سلطة طحينة"), ("Fattoush", "فتوش")],
    ("Drinks", "المشروبات", False): [("Mint lemonade", "ليمون بالنعناع"), ("Turkish coffee", "قهوة تركي")],
}


def sql(q: str) -> list[list[str]]:
    out = subprocess.run([PSQL, DB, "-At", "-F", "\t", "-v", "ON_ERROR_STOP=1", "-c", q], check=True, capture_output=True, text=True).stdout
    return [l.split("\t") for l in out.strip().splitlines() if l]


def call(method: str, path: str, body=None, token=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} → {e.code}: {e.read().decode()[:400]}")


def login():
    return call("POST", "/auth/login", {"email": ADMIN[0], "password": ADMIN[1]})["token"]


# The org the demo admin belongs to (seed-staff-demo's admin; on some dev
# databases it has drifted to a probe org — follow the user, not the slug).
org = sql(f"SELECT u.org_id FROM users u JOIN organizations o ON o.id = u.org_id WHERE u.email = '{ADMIN[0]}' AND o.slug LIKE 'madar-staff-%'")
if not org:
    sys.exit("No demo admin: run MadarRust/scripts/dev-staff.sh first.")
ORG = org[0][0]
token = login()
branch = sql(f"SELECT id FROM branches WHERE org_id = '{ORG}' ORDER BY created_at, name LIMIT 1")
# Creating a branch over the API is super-admin only; the demo seed inserts them too.
BRANCH = branch[0][0] if branch else sql(
    f"INSERT INTO branches (org_id, name, timezone) VALUES ('{ORG}', 'Downtown', 'Africa/Cairo') RETURNING id")[0][0]


def ensure_shift():
    """A round needs an open till at the branch, as in a real shop."""
    req = urllib.request.Request(f"{API}/shifts/branches/{BRANCH}/current", headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req) as r:
            if (json.loads(r.read() or b"null") or {}).get("has_open_shift"):
                return
    except urllib.error.HTTPError:
        pass
    call("POST", f"/shifts/branches/{BRANCH}/open", {"opening_cash": 0}, token)
    print("opened a till")


def fire(n: int):
    ensure_shift()
    items = sql(f"SELECT id FROM menu_items WHERE org_id = '{ORG}' AND name = ANY(ARRAY[{','.join(repr(d[0]) for ds in MENU.values() for d in ds)}])")
    if not items:
        sys.exit("No kitchen menu yet: run without --fire first.")
    for _ in range(n):
        picks = random.sample(items, k=min(len(items), random.randint(2, 4)))
        t = call("POST", "/open-tickets", {
            "branch_id": BRANCH,
            "customer_name": f"T{random.randint(1, 20)}",
            "idempotency_key": str(uuid.uuid4()),
            "items": [{"menu_item_id": i[0], "quantity": random.randint(1, 3)} for i in picks],
        }, token)
        print(f"fired ticket {t['id'][:8]} with {len(picks)} lines")


if "--fire" in sys.argv:
    fire(2)
    sys.exit(0)

# Sections, categories and their routes (KS-1..4), and the branch's mode (KS-7).
for (name, name_ar, default), dishes in MENU.items():
    st = sql(f"SELECT id FROM kitchen_stations WHERE branch_id = '{BRANCH}' AND name = '{name}'")
    station = st[0][0] if st else sql(
        f"INSERT INTO kitchen_stations (org_id, branch_id, name, is_default) VALUES ('{ORG}','{BRANCH}','{name}',{str(default).lower()}) RETURNING id")[0][0]
    cat = sql(f"SELECT id FROM categories WHERE org_id = '{ORG}' AND name = 'Kitchen · {name}'")
    category = cat[0][0] if cat else sql(f"INSERT INTO categories (org_id, name) VALUES ('{ORG}','Kitchen · {name}') RETURNING id")[0][0]
    sql(f"INSERT INTO category_station_routes (branch_id, category_id, station_id) VALUES ('{BRANCH}','{category}','{station}') "
        "ON CONFLICT DO NOTHING")
    for dish, dish_ar in dishes:
        if not sql(f"SELECT 1 FROM menu_items WHERE org_id = '{ORG}' AND name = '{dish}'"):
            sql(f"INSERT INTO menu_items (org_id, category_id, name, name_translations, base_price) VALUES "
                f"('{ORG}','{category}','{dish}','{json.dumps({'ar': dish_ar, 'en': dish}, ensure_ascii=False)}'::jsonb, 10000)")
    print(f"section {name}: {len(dishes)} dishes")
sql(f"UPDATE branches SET kitchen_routing_mode = 'kds' WHERE id = '{BRANCH}'")

# The cook: a kitchen-role user with a PIN (DV-2).
if not sql(f"SELECT 1 FROM users WHERE org_id = '{ORG}' AND name = '{COOK_NAME}'"):
    call("POST", "/users", {"org_id": ORG, "name": COOK_NAME, "role": "kitchen", "pin": COOK_PIN, "branch_ids": [BRANCH]}, token)
print(f"cook: {COOK_NAME} / {COOK_PIN}")

fire(4)
print(f"branch {BRANCH} is ready. Sign in as {ADMIN[0]} on the device to bind it.")
