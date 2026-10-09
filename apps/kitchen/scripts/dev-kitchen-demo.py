#!/usr/bin/env python3
"""Give a branch on a LOCAL Madar backend a full test kitchen for Madar Kitchen.

LOCAL ONLY: refuses any API or database that isn't localhost.

    # the demo admin from MadarRust/scripts/dev-staff.sh, its first branch
    python3 scripts/dev-kitchen-demo.py

    # your own local org and branch (credentials come from the environment,
    # never from this file)
    MADAR_ADMIN_EMAIL=you@example.com MADAR_ADMIN_PASSWORD=... \\
    MADAR_BRANCH="TestBranch" python3 scripts/dev-kitchen-demo.py

    ... --fire     just fire 2 more rounds

What it builds (idempotent — run it again any time):
  sections   Grill (default), Cold, Drinks, Bakery           KS-1, KS-4
  routes     a category per section; "Garlic bread" sits in the Grill
             category but is routed to Bakery by an item route   KS-2, KS-3
             "Chef's special" has no category → default section KS-4
  tables     T1–T8
  cooks      kitchen-role staff "Chef Ahmed" / 246810 and "Chef Mona" / 357913
  waiter     "Waiter Karim" / 112233, to fire orders from the POS app
  mode       kitchen_routing_mode = kds
  orders     a spread for every board state: fresh, amber (6 min), red
             (12 min), a second round on the same table, line notes, a
             voided line, a dish with no category, one order already fully
             bumped at Drinks (its other sections still open)
"""
import json
import os
import random
import subprocess
import sys
import urllib.error
import urllib.request
import uuid

API = os.environ.get("MADAR_API", "http://localhost:8082")
DB = os.environ.get("DATABASE_URL", "postgres://madar@localhost:5432/madar")
PSQL = os.environ.get("PSQL", "/Applications/Postgres.app/Contents/Versions/17/bin/psql")
EMAIL = os.environ.get("MADAR_ADMIN_EMAIL", "admin@demo.madar")
PASSWORD = os.environ.get("MADAR_ADMIN_PASSWORD", "Demo1234!")
BRANCH_NAME = os.environ.get("MADAR_BRANCH")
COOKS = [("Chef Ahmed", "246810"), ("Chef Mona", "357913")]
WAITER = ("Waiter Karim", "112233")  # takes orders on the POS

assert API.startswith(("http://localhost", "http://127.0.0.1")), f"refusing non-local API {API}"
assert "localhost" in DB or "127.0.0.1" in DB, f"refusing non-local database {DB}"

# (section, Arabic, default) -> [(dish, Arabic)]
MENU = {
    ("Grill", "المشويات", True): [("Mixed grill", "مشويات مشكلة"), ("Kofta", "كفتة"), ("Shish tawook", "شيش طاووق"), ("Garlic bread", "خبز بالثوم")],
    ("Cold", "البارد", False): [("Tahini salad", "سلطة طحينة"), ("Fattoush", "فتوش"), ("Baba ghanoush", "بابا غنوج")],
    ("Drinks", "المشروبات", False): [("Mint lemonade", "ليمون بالنعناع"), ("Turkish coffee", "قهوة تركي"), ("Mango juice", "عصير مانجو")],
    ("Bakery", "المخبوزات", False): [("Feteer", "فطير"), ("Cheese sambousek", "سمبوسك جبنة")],
}
ITEM_ROUTE = ("Garlic bread", "Bakery")  # KS-3: the item route beats its category
UNROUTED = ("Chef's special", "طبق الشيف")  # KS-4: no category → default section


def q(s: str) -> str:
    return s.replace("'", "''")


def sql(query: str) -> list[list[str]]:
    out = subprocess.run([PSQL, DB, "-At", "-F", "\t", "-v", "ON_ERROR_STOP=1", "-c", query], check=True, capture_output=True, text=True).stdout
    return [l.split("\t") for l in out.strip().splitlines() if l]


def call(method: str, path: str, body=None, token=None, ok404=False):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        if ok404 and e.code == 404:
            return None
        sys.exit(f"{method} {path} → {e.code}: {e.read().decode()[:400]}")


token = call("POST", "/auth/login", {"email": EMAIL, "password": PASSWORD})["token"]
ORG = sql(f"SELECT org_id FROM users WHERE lower(email) = lower('{q(EMAIL)}')")[0][0]
where = f"AND name = '{q(BRANCH_NAME)}'" if BRANCH_NAME else ""
branch = sql(f"SELECT id, name FROM branches WHERE org_id = '{ORG}' {where} ORDER BY created_at, name LIMIT 1")
if not branch:
    sys.exit(f"No branch {BRANCH_NAME!r} in this account's org.")
BRANCH, BRANCH_LABEL = branch[0]


def item_id(name: str) -> str:
    return sql(f"SELECT id FROM menu_items WHERE org_id = '{ORG}' AND name = '{q(name)}'")[0][0]


def ensure_shift():
    """A round needs an open till at the branch, as in a real shop."""
    cur = call("GET", f"/shifts/branches/{BRANCH}/current", token=token, ok404=True) or {}
    if not cur.get("has_open_shift"):
        call("POST", f"/shifts/branches/{BRANCH}/open", {"opening_cash": 0}, token)
        print("opened a till")


def line(name: str, qty: int = 1, notes: str | None = None) -> dict:
    d = {"menu_item_id": item_id(name), "quantity": qty}
    if notes:
        d["notes"] = notes
    return d


def fire(lines: list[dict], table: str | None = None, notes: str | None = None) -> dict:
    body = {"branch_id": BRANCH, "idempotency_key": str(uuid.uuid4()), "items": lines}
    if table:
        body["table_id"] = sql(f"SELECT id FROM branch_tables WHERE branch_id = '{BRANCH}' AND label = '{table}'")[0][0]
    else:
        body["customer_name"] = random.choice(["Karim", "Yara", "Hassan", "Nour"])
    if notes:
        body["notes"] = notes
    return call("POST", "/open-tickets", body, token)


def age(ticket_id: str, minutes: float):
    """Back-date a ticket's kitchen rounds so the board shows amber / red ages."""
    sql(f"UPDATE kitchen_tickets SET created_at = now() - interval '{minutes} minutes' WHERE open_ticket_id = '{ticket_id}'")


def random_round():
    dishes = [d for ds in MENU.values() for d, _ in ds]
    return [line(d, random.randint(1, 3)) for d in random.sample(dishes, k=random.randint(2, 4))]


ensure_shift()
if "--fire" in sys.argv:
    for _ in range(2):
        t = fire(random_round(), table=f"T{random.randint(1, 8)}")
        print(f"fired {t['id'][:8]}")
    sys.exit(0)

# Sections, categories, routes (KS-1..4), and the branch's mode (KS-7).
stations = {}
for (name, name_ar, default), dishes in MENU.items():
    st = sql(f"SELECT id FROM kitchen_stations WHERE branch_id = '{BRANCH}' AND name = '{name}'")
    stations[name] = st[0][0] if st else sql(
        f"INSERT INTO kitchen_stations (org_id, branch_id, name, is_default) VALUES ('{ORG}','{BRANCH}','{name}',{str(default).lower()}) RETURNING id")[0][0]
    cat = sql(f"SELECT id FROM categories WHERE org_id = '{ORG}' AND name = 'Kitchen · {name}'")
    category = cat[0][0] if cat else sql(f"INSERT INTO categories (org_id, name) VALUES ('{ORG}','Kitchen · {name}') RETURNING id")[0][0]
    sql(f"INSERT INTO category_station_routes (branch_id, category_id, station_id) VALUES ('{BRANCH}','{category}','{stations[name]}') ON CONFLICT DO NOTHING")
    for dish, dish_ar in dishes:
        if not sql(f"SELECT 1 FROM menu_items WHERE org_id = '{ORG}' AND name = '{q(dish)}'"):
            sql(f"INSERT INTO menu_items (org_id, category_id, name, name_translations, base_price) VALUES "
                f"('{ORG}','{category}','{q(dish)}','{q(json.dumps({'ar': dish_ar, 'en': dish}, ensure_ascii=False))}'::jsonb, 10000)")
    print(f"section {name}: {len(dishes)} dishes")
if not sql(f"SELECT 1 FROM menu_items WHERE org_id = '{ORG}' AND name = '{q(UNROUTED[0])}'"):
    sql(f"INSERT INTO menu_items (org_id, name, name_translations, base_price) VALUES "
        f"('{ORG}','{q(UNROUTED[0])}','{q(json.dumps({'ar': UNROUTED[1], 'en': UNROUTED[0]}, ensure_ascii=False))}'::jsonb, 15000)")
sql(f"INSERT INTO menu_item_station_routes (branch_id, menu_item_id, station_id) SELECT '{BRANCH}', '{item_id(ITEM_ROUTE[0])}', '{stations[ITEM_ROUTE[1]]}' "
    f"WHERE NOT EXISTS (SELECT 1 FROM menu_item_station_routes WHERE branch_id = '{BRANCH}' AND menu_item_id = '{item_id(ITEM_ROUTE[0])}')")
sql(f"UPDATE branches SET kitchen_routing_mode = 'kds' WHERE id = '{BRANCH}'")
print(f"routes: {ITEM_ROUTE[0]} → {ITEM_ROUTE[1]} (item route), {UNROUTED[0]} → default")

# Tables T1–T8.
for i in range(1, 9):
    if not sql(f"SELECT 1 FROM branch_tables WHERE branch_id = '{BRANCH}' AND label = 'T{i}'"):
        call("POST", "/floor/tables", {"branch_id": BRANCH, "label": f"T{i}", "seats": 4, "pos_x": 120.0 * i, "pos_y": 100.0}, token)
print("tables T1–T8")

# Kitchen-role cooks with PINs (DV-2).
for name, pin in COOKS:
    if not sql(f"SELECT 1 FROM users WHERE org_id = '{ORG}' AND name = '{q(name)}'"):
        call("POST", "/users", {"org_id": ORG, "name": name, "role": "kitchen", "pin": pin, "branch_ids": [BRANCH]}, token)
print("cooks: " + ", ".join(f"{n} / {p}" for n, p in COOKS))
if not sql(f"SELECT 1 FROM users WHERE org_id = '{ORG}' AND name = '{q(WAITER[0])}'"):
    call("POST", "/users", {"org_id": ORG, "name": WAITER[0], "role": "waiter", "pin": WAITER[1], "branch_ids": [BRANCH]}, token)
print(f"waiter (POS): {WAITER[0]} / {WAITER[1]}")

# A spread of orders for every board state.
red = fire([line("Mixed grill", 2), line("Tahini salad"), line("Mint lemonade", 3)], table="T4", notes="Birthday — drinks first")
age(red["id"], 12)
amber = fire([line("Kofta", 1, "Allergy: no nuts"), line("Fattoush", 2), line("Turkish coffee", 2, "No sugar")], table="T2")
age(amber["id"], 6)
call("POST", f"/open-tickets/{red['id']}/rounds", {"idempotency_key": str(uuid.uuid4()), "items": [line("Kofta"), line("Turkish coffee")]}, token)
voided = fire([line("Shish tawook", 2), line("Baba ghanoush"), line("Mango juice")], table="T7")
victim = next(i for i in voided["items"] if i.get("menu_item_id") == item_id("Baba ghanoush"))
call("POST", f"/open-tickets/{voided['id']}/items/{victim['id']}/void", {"reason": "customer_request"}, token)
fire([line("Garlic bread", 2), line(UNROUTED[0]), line("Feteer")], table="T1")
fire([line("Cheese sambousek", 4), line("Mango juice", 2), line("Mixed grill")])
done = fire([line("Mint lemonade", 2), line("Kofta")], table="T8")
# Drinks already bumped on T8 (as Chef Mona), so its Grill part is the only one left.
cook = call("POST", "/auth/login", {"pin": COOKS[1][1], "name": COOKS[1][0], "branch_id": BRANCH})["token"]
for (kid,) in sql(f"SELECT ki.id FROM kitchen_ticket_items ki JOIN kitchen_tickets kt ON kt.id = ki.kitchen_ticket_id "
                  f"WHERE kt.open_ticket_id = '{done['id']}' AND ki.station_id = '{stations['Drinks']}'"):
    call("POST", f"/kitchen/items/{kid}/bump", {}, cook)
print("fired 6 orders + 1 round (red, amber, fresh, notes, void, item route, unrouted, half-bumped)")
print(f"\nbranch {BRANCH_LABEL} is ready. Device setup: {EMAIL}; then a cook PIN above.")
