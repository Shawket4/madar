# dashboard_api

The Madar backend API for the Flutter dashboard: a client generated from
`spec/openapi.json`, the `ApiTransport` seam, and the mock backend used by tests
and mock mode.

```dart
import 'package:dashboard_api/dashboard_api.dart'; // transport, models, APIs, DashboardApi
import 'package:dashboard_api/mock.dart';          // MockServer, MockDb, MockSeed, Persona, …
```

## The client (`lib/src/generated/`, never edited by hand)

Regenerate with `melos run gen_dashboard_api` (or `python3 tool/gen_dashboard_api.py`;
`--check` fails when the output is stale). It also writes the test fixtures in
`test/generated/`.

- `DashboardApi(transport)` has one getter per tag (`api.orders`, `api.orgs`,
  `api.bookingsPublic`, …); each method is the operationId in lowerCamelCase, the
  same names as the web's Orval hooks without `use`:
  `api.orders.listOrders(branchId: id, from: from, to: to, page: 1)`.
- Path, query and header parameters are named arguments; a request body is `body:`.
  Results are models, `List`s, `Map`s, `String` (CSV), `List<int>` (bytes), `void`,
  or `Stream<String>` for server-sent events.
- One immutable class per schema with `fromJson`/`toJson`. Snake-case fields become
  lowerCamel (`created_at` → `createdAt`); a few names that clash with Dart get a
  trailing `_` (`required` → `required_`, `default` → `default_`).
- `date-time` is a UTC `DateTime`; `date` stays a `yyyy-mm-dd` `String`; `int64` is
  `int`; `number` is `double`; free-form objects are `Map<String, Object?>`.
- Enums are classes that keep unknown values (`TillStatus.fromJson('x').isKnown`
  is false). `oneOf` schemas are sealed classes (`AiChatKind` → `AiChatKindAnswer`,
  …, `AiChatKindUnknown`).
- Optional fields left `null` are omitted from `toJson()`. To send an explicit
  `null` (a PATCH that clears a value) name it:
  `UpdateBranchRequest(explicitNulls: {'printer_ip'})`.
- A response that does not match the spec throws `ApiException` with code `decode`.
- `Category` shares its name with an annotation in `package:flutter/foundation.dart`;
  if you import both, `hide Category` from foundation.
- `apiOperations` lists every operation (id, method, path template, tag, Dart name).

## The mock backend (`lib/src/mock/`)

```dart
final db = MockDb.seeded();                       // the seed, as JSON rows
final server = MockServer(persona: Persona.owner, clock: db.clock);
registerCoreMocks(server, db);                    // what the shell calls at start
registerSellMocks(server, db);                    // an area's own handlers
final api = DashboardApi(server);
```

- `server.on(method, template, handler)` / `onStream` / `onOperation(id, handler)`.
  A later registration of the same route replaces the earlier one, so an area can
  override a core handler. Unmatched routes answer 501 and land in
  `server.unmatched`; handler crashes answer 500 and land in `server.handlerErrors`.
- `MockRequest`: `param('id')`, `q('page')`, `qInt`, `qBool`, `qDateTime`, `qAll`,
  `json`, `bodyAs(Model.fromJson)`, `files`, `persona`, `orgId`, `now`.
- Refusals in the backend's exact envelope (`{"error": …, "code"?: …}`):
  `req.requireCap('orders.void', branchId: id)` (403 naming the capability),
  `requireAnyCap`, `requireBranch`, `requireSameOrg`, `requirePlatform`,
  `notFound`, `badRequest`, `conflict(code: …)`, `unprocessable(code: …, vars: …)`,
  or `MockResponse.error(status, words, code: …)`.
- Paging like the backend: `pageOf(rows, req)` for `page`/`per_page` →
  `{data, total, page, per_page, total_pages}`; `sliceOf(rows, req)` for
  `limit`/`offset` → a plain list.
- `MockDb`: `db['orders'].query(filters:, search:, from:, to:, sort: '-created_at')`,
  `insert` (deterministic ids, timestamps from the clock), `update`, `delete`, `get`
  (404 when missing). Tables are listed on `MockSeed.loadInto`.
- Tests: `server.fail(method, template, MockResponse…, times: 1)` for error states,
  `server.hold(method, template)` → `gate.release()` for loading states,
  `server.publish(realtimeChannel(branchId), frame)` for live updates,
  `server.calls` / `callsTo(template)` to assert what was sent.
- `MockClock` is fixed at 2026-10-08 10:00 Africa/Cairo (`MockClock.cairoIso`,
  `startOfCairoDay`, `fromCairo`).

## Personas and seed

| Persona | Person | Scope |
|---|---|---|
| `owner` | Nour El-Sayed (`nour@sabah.test`) | Sabah Coffee, every capability, every branch |
| `manager` | Karim Adel (`karim@sabah.test`) | Zamalek only, the registry's manager defaults |
| `limited` | Hana Mostafa (`hana@sabah.test`) | Maadi, read-only on a few pages (`limitedCapabilities`) |
| `platform` | Madar Support (`support@madar.test`) | platform admin, any org (`server.platformOrgId` or `X-Org-Id`) |
| `dawamOnly` | Yasmin Ghali (`yasmin@nakhla.test`) | Nakhla Bakery, Dawam module only |

Password for all: `Persona.password`. Ids: `SeedIds` (orgs, branches, people).

`MockSeed.instance`: Sabah Coffee (EGP, VAT 14 % inclusive, POS + Dawam) with
Heliopolis, Maadi, New Cairo and Zamalek; 16 staff with roles; 6 payment methods;
7 categories, 40 items with sizes, the Milk and Extras modifier groups and the
legacy add-ons; 200 customers; 30 days of orders (≈8,500, lines via
`orderItems(id)` / `orderFull(id)`) with payments and two tills a day per branch
(today's morning tills open); work shifts and attendance settings. Nakhla Bakery
(Dawam only) has two branches and seven people. Areas add their own domain data
in their package, referencing these ids.
