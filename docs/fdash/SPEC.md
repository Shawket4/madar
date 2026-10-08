# Flutter dashboard: full parity with the web dashboard

This is the contract every agent working on the Flutter dashboard follows. Read it whole before you
start; re-read the section for your role when in doubt.

## 1. Goal and standard

The Flutter dashboard app (`apps/dashboard`) reaches **full parity** with the web dashboard
(`/Users/shawket/Desktop/Madar/MadarDashboard`, branch `main`, v1.4.18). Every page, tab, dialog, side
panel, action, filter, sort, search, export, empty/loading/error state, permission rule, module rule
and Arabic string the web has, the Flutter app has. **Nothing is dropped, nothing is invented.** When
unsure what the web does, read the web source; it is the reference, not your judgement.

Out of scope: the public customer bundles (`src/order`, `src/reservations`, `src/loyalty` public card,
`features/public-*`, `features/order-tracking`, the public links page) and the marketing site
(`MadarDashboard/site`). Their admin editors ARE in scope.

The plan doc: https://claude.ai/code/artifact/a67f00a2-3215-4a2a-a476-2740c1fab335 (read-only for agents).

## 2. Hard rules

- Work ONLY in `/Users/shawket/Desktop/Madar/wt-fdash-pos`. The web repo, the backend repo and every
  other checkout are READ-ONLY.
- No `flutter build`, no `flutter run`, no simulators, no backend, no Postgres. Verification is
  `flutter test` against the mock server (section 6). The only agent allowed to run `cargo` is the
  core-bridge agent, always with `CARGO_TARGET_DIR=/Users/shawket/Desktop/Madar/madar/rust-core/target`.
- Prefix every flutter command with `FLUTTER_ALREADY_LOCKED=true` (many agents run at once; this
  skips the SDK startup lock). Use `--no-pub`. Run only the test files you own, never a whole repo.
- Never run `flutter pub get`/`pub add` and never edit a `pubspec.yaml` unless your role says so. If
  you need a dependency, work without it and report it in your result.
- Never `git commit`, `git stash`, `git checkout`, `git reset` or push. Commits are made by the
  orchestrator. Never delete files you did not create.
- Edit only the files your role owns (section 4). Shared packages are frozen during area work; if a
  shared widget is missing or broken, build a local one in your area package and report it.
- No raw hex colours, no ad-hoc paddings: `design_system` tokens (`context.madarColors`, `Space`,
  `Radii`, `MadarType`, `MadarIcon`). No hard-coded UI text: every string through the i18n (section 5).
- Accessibility: tap targets ≥ 44 pt, real `Semantics` labels on icon-only controls, respect
  `MediaQuery.disableAnimations`. Arabic is right-to-left everywhere except physical geometry
  (floor plans are never mirrored — see the madar CLAUDE.md).

## 3. Architecture

```
apps/dashboard                    composition: main (real or mock mode), router, shell UI
packages/dashboard_api            generated client from spec/openapi.json + transport seam + mock server + seed
packages/dashboard_kit            UI kit on design_system (tables, forms, panels, charts, page scaffold)
packages/dashboard_core           contracts: i18n, session/scope/period, capabilities, routes, gateways, test harness
packages/dashboard_features/<area>  one package per area; pages, providers, mock handlers, tests
```

Feature areas (package `dashboard_<area>`):

| Area | Pages (web paths) |
|---|---|
| overview | `/` home (8 cards) |
| sell | `/orders`, `/floor`, `/bookings`, `/tills`, `/customers` |
| catalog_menu | `/menu/items`, `/menu/items/:itemId` (+ menu studio), `/menu/groups`, `/menu/pricing`, `/menu/bases`, `/menu/packaging` |
| catalog_offers | `/menu/combos`, `/menu/combos/:comboId`, `/menu/deals`, `/discounts` |
| reports | `/reports/operations` (+ tabs), `/reports/financial`, `/reports/inventory`, `/reports/legal`, `/reports/loyalty`, `/reports/bundles`, `/reports/staff`, `/reports/staff-pool`, `/reports/tills`, `/basira` |
| inventory | `/inventory/today`, `/inventory/counts`, `/inventory/ingredients`, `/inventory/purchasing`, `/inventory/waste`, `/inventory/transfers`, `/inventory/settings` |
| team | `/staff/setup`, `/staff/employees`, `/staff/attendance`, `/staff/shifts`, `/staff/team`, `/staff/approvals`, `/staff/schedule`, `/staff/requests`, `/staff/payroll`, `/staff/reports`, `/staff/rules` |
| setup | `/settings` (appearance), `/settings/brand`, `/settings/links`, `/settings/delivery`, `/settings/delivery-zones`, `/settings/bookings`, `/settings/loyalty`, `/settings/qr`, `/settings/combos`, `/settings/payment-methods`, `/settings/staff-pool`, `/settings/kitchen-stations`, `/settings/kitchen-routing`, `/settings/integrations`, `/settings/whatsapp` |
| admin | `/orgs`, `/branches`, `/devices`, `/access/users`, `/access/roles`, `/access/review`, `/onboarding` |

App-wide pieces owned by the shell (apps/dashboard + dashboard_core): sign-in (port the web's new
sign-in screen), org picker (platform admins), branch picker, period picker, user menu (language,
theme, sign out), command palette (Ctrl/Cmd+K), ask-a-manager dialog, live branch updates, module
gate, the web's 25 legacy redirect paths.

### 3.1 Data path

Screens never touch the Rust bridge. They call the generated Dart API in `dashboard_api`:

```dart
final api = ref.watch(apiProvider);            // DashboardApi: one getter per tag
final page = await api.orders.listOrders(branchId: id, from: from, to: to, page: 1);
```

- `dashboard_api` is GENERATED from `packages/dashboard_api/spec/openapi.json` (MadarRust `main`,
  621 operations, 773 schemas) by `tool/gen_dashboard_api.*` (melos script `gen_dashboard_api`).
  Method names = the operationId in lowerCamelCase (the same names the web's Orval hooks use, minus
  `use`). Models are immutable classes with `fromJson`/`toJson`; enums keep unknown values; nullability
  follows `required` + `nullable`. Generated code lives under `lib/src/generated/` and is never edited
  by hand.
- Every call goes through one seam:

```dart
abstract interface class ApiTransport {
  Future<ApiResponse> send(ApiRequest request);
  Stream<String> stream(ApiRequest request);        // server-sent events, one data frame per item
}
class ApiRequest { final String method; final String path; final Map<String, List<String>> query;
  final Object? body; final List<ApiFilePart> files; final Map<String, String> headers; }
class ApiResponse { final int status; final Map<String, String> headers; final List<int> bodyBytes; }
class ApiException implements Exception { final int status; final String? code; final String message;
  final Object? details; }   // message is already human, in the active language
```

- Real mode: `CoreTransport` (apps/dashboard) forwards to the core over the dashboard bridge
  (`api_request` / `api_stream`); the core adds the token, org/branch headers, refresh and the EN/AR
  refusal text. Mock mode and tests: `MockServer` (dashboard_api) implements `ApiTransport`.
- Files: `xlsx` export/import is a core function in real mode (`ExportGateway` in dashboard_core,
  core impl in the app, a mock impl in tests); save/share/pick go through `FileGateway`.

### 3.2 Mock server

`MockServer` routes `(method, pathTemplate)` to handlers over an in-memory `MockDb`:

```dart
server.on('GET', '/orders', (req) => MockResponse.json(200, db.orders.page(req)));
server.on('POST', '/orders/{id}/void', (req) { req.requireCap(Cap.ordersVoid); ... });
```

- An unmatched route returns 501 and records it; the test harness FAILS a test that hit an unmatched
  route, so every endpoint a page calls must have a handler.
- Handlers behave like the backend: validation errors (422 with the backend's error envelope),
  refusals (403 envelope when the persona lacks the capability), not-found, paging/filter/sort params,
  and state (a create shows up in the next list).
- `seed.dart` is a deterministic, realistic dataset (fictional café group "Sabah Coffee", Cairo,
  EGP, 4 branches: Heliopolis, Maadi, New Cairo, Zamalek; staff; menu with sizes and modifiers;
  payment methods; customers; 30 days of orders and tills). Areas add their own domain data in their
  package, referencing seed ids. No lorem ipsum, no "Test 1".
- Personas: `owner` (org admin, every capability, both modules), `manager` (one branch, typical
  manager caps), `limited` (read-only on a few pages), `platform` (platform admin), `dawamOnly` (org
  with only the Dawam module). Each area adds capabilities checks to its handlers.
- The web's own mock data (`MadarDashboard/src/data/api/mock/*.ts`, the generated
  `api.faker.ts`/`api.msw.ts`) is a good source of realistic shapes.

## 4. Ownership

| Owner | Files |
|---|---|
| foundation: api | `packages/dashboard_api/**`, `tool/gen_dashboard_api*` |
| foundation: core bridge | `rust-core/crates/madar-core/src/**` (new code only), `rust-core/crates/madar-frb-dashboard/**`, `packages/rust_bridge_dashboard/**` (regenerated), `apps/dashboard/lib/data/**` |
| foundation: kit | `packages/dashboard_kit/**`, additive new files/entries in `packages/design_system/lib/src/icons.dart` |
| foundation: core | `packages/dashboard_core/**`, `tool/sync_dashboard_i18n*`, `tool/gen_dashboard_nav*`, `tool/gen_dashboard_caps*` |
| foundation: shell | `apps/dashboard/**` except `lib/data/**`; the area packages' `lib/dashboard_<area>.dart`, `lib/src/routes.dart`, `lib/src/mock/register.dart` STUBS |
| area `<area>` | everything under `packages/dashboard_features/<area>/` except its public library file's exported names |

## 5. Text

- Strings come from the web's own files: `tool/sync_dashboard_i18n` copies
  `MadarDashboard/src/i18n/locales/{en,ar}.json` into `packages/dashboard_core/assets/i18n/` (flattened
  dotted keys). Use the web's keys exactly: `t('orders.voidTitle')`.
- `t(key, {args, count})`: i18next semantics — `{{name}}` interpolation, plural suffixes `_zero _one
  _two _few _many _other` with CLDR rules (Arabic uses all six), `defaultValue`.
- When the web passes an inline default (`t("x.y", "Default")`) or the key is missing from the web's
  files, add it to your area's supplement `packages/dashboard_features/<area>/assets/i18n/{en,ar}.json`
  with the web's English and a correct Arabic translation (Modern Standard Arabic, the tone of the
  web's existing Arabic). Supplements merge over the synced tables.
- Numbers, money and dates are formatted exactly like the web's `src/lib/format.ts` (money in minor
  units, the org currency, the branch timezone).

## 6. Pages, layouts and verification

### 6.1 Building a page

- A page is a widget inside the shell, wrapped in the kit's page scaffold (title, actions, tabs,
  filters, body), registered in the area's `routes.dart` with its path, its capabilities (any-of,
  same as the web) and its module.
- Two layouts, same data and actions: width ≥ 760 → the web layout (tables with the web's columns,
  detail in a side panel, forms in dialogs/side panels); width < 760 → phone layout (cards/rows,
  detail full screen, forms as full-screen sheets).
- Data: Riverpod providers keyed by scope/period/filters (`AsyncNotifier`s). After a change,
  invalidate exactly what the web's React Query invalidates. Loading → skeleton; empty → the web's
  empty state words; error → the web's error words + retry; failed mutation → toast with
  `ApiException.message`. A Save that silently does nothing is the worst outcome a form can have.
- Gating: hide or disable exactly what the web hides or disables (`<Restricted>`, `canAny`, module
  gate, platform-only, setup-only).
- Live updates: where the web listens to branch realtime events, subscribe through dashboard_core's
  realtime provider and refresh the same data.

### 6.2 Verifying a page (the definition of done)

For EVERY web action on the page (each `D-###` row of the area inventory) there is a widget test
that drives it through the real app shell with the harness:

```dart
final h = await DashHarness.pump(tester, path: '/orders', persona: Persona.owner,
    size: DashSize.desktop, locale: 'en', dark: false);
await h.tapText('Void');  ...  expect(h.server.calls.last.path, '/orders/…/void');
await h.shot('orders/void-dialog');
```

Each page also has:
- refusal tests: a persona without the capability sees the action hidden/disabled exactly as on the
  web; a 403/422 from the server shows the right words;
- empty, loading and error state tests;
- the screenshot matrix for its default state: {phone 390×844, tablet 1024×768, desktop 1440×900} ×
  {en light, ar dark}, plus every dialog/panel/sheet state at desktop-en-light and phone-ar-light.

Screenshots: run with `FDASH_SHOTS=/Users/shawket/Desktop/Madar/wt-fdash-pos/.shots` set; the harness
writes `<FDASH_SHOTS>/<area>/<page>/<name>--<size>-<lang>-<theme>.png` with real fonts (IBM Plex Sans
Arabic / Mono). LOOK at your screenshots (Read the PNGs): overflow stripes, clipped or cut text,
mirrored geometry, wrong direction, raw keys, English in Arabic, empty boxes, misaligned columns,
unreadable contrast are defects.

Commands — ALWAYS through `tool/fdash_test.py` (from the worktree root). It caps concurrent
flutter runs machine-wide and locks per package, so dozens of agents can work at once; a wait
message means it is queueing, not stuck:

```bash
python3 tool/fdash_test.py packages/dashboard_features/<area> test/<your_file>_test.dart
FDASH_SHOTS=/Users/shawket/Desktop/Madar/wt-fdash-pos/.shots python3 tool/fdash_test.py packages/dashboard_features/<area> test/<your_file>_test.dart
python3 tool/fdash_test.py --analyze packages/dashboard_features/<area> lib test
```

Run only your own test files; never the whole package unless your role is the area's final check.

A page is done when: every D-row has a passing driven test; refusal, empty, loading and error tests
pass; the screenshot matrix is clean; `flutter analyze` on the package is clean; no unmatched mock
routes; no hard-coded strings.

### 6.3 Web bugs: port the intent, log the difference

The inventories record web behaviour that is plainly a bug (a double minus sign, a save lost on
in-app navigation, a "Saving…" that never clears, raw transport errors shown to people, English
names inside the Arabic UI, a check that silently blocks Save). Do NOT copy a bug. Implement what the
web evidently intends, pin the correct behaviour with a test, and add one line per difference to
`docs/fdash/divergences/<area>-<unit>.md` (your own file; row id, what the web does, what Flutter does, why). Quirks that
are a product choice rather than a defect are ported as they are. When unsure which it is, port the
web's behaviour and log it as a question in the same file.

## 7. Where to read the web

- Routes: `src/routes/_app/**` (file routes; `route.tsx` holds tabs/guards). Nav: `src/config/nav.ts`,
  settings sub-nav: `src/features/settings/settings-nav.ts`.
- Pages and their parts: `src/features/<feature>/**` (page, dialogs, sheets, util.ts, tests — the
  web's tests are a good list of behaviours).
- Shared web components: `src/components/app/**` (data-table, page, export-button, confirm-dialog,
  restricted, module-gate, ledger-strip, chart-card, stat-card, image-uploader, …), `src/components/ui/**`.
- Formatting and helpers: `src/lib/format.ts`, `src/lib/excel.ts`, `src/lib/download.ts`.
- API hooks used by a page: imports from `@/data/api/generated/api` in its files.
- Capabilities: `src/generated/capabilities.ts`; authz: `src/data/stores/auth.store.ts`, `src/lib/auth-guard.ts`.
