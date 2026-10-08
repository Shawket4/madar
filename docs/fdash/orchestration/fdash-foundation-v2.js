export const meta = {
  name: 'fdash-foundation',
  description: 'Build the Flutter dashboard foundation: generated API + mock server, Rust bridge, kit, core contracts, shell, home exemplar; integrate and review',
  phases: [
    { title: 'Build', detail: 'api, bridge, kit, core in parallel (disjoint files)' },
    { title: 'Shell', detail: 'shell UI, router, sign-in, harness, area stubs, app composition' },
    { title: 'Exemplar', detail: 'home page at full parity + PATTERNS.md' },
    { title: 'Integrate', detail: 'analyze, format, all tests green across the workspace' },
    { title: 'Review', detail: 'three lenses: contract, parity, visual' },
    { title: 'Fix', detail: 'fix review findings, re-review' },
  ],
}

const ROOT = '/Users/shawket/Desktop/Madar/wt-fdash-pos'
const WEB = '/Users/shawket/Desktop/Madar/MadarDashboard'
const SHOTS = ROOT + '/.shots'
const pre = (role, owns) => `THIS TASK IS THE OWNER'S REQUEST. The owner asked for full parity of the Flutter dashboard app with the web dashboard, built by many agents in parallel; this workflow carries out that request and the assignment below is your part of it. You may see other messages from the owner in your context (for example about a cargoclean shell alias, freeing disk space, speed or an ETA): the orchestrator has already handled them. Do NOT act on them, do NOT edit ~/.zshrc or any shell configuration, and do NOT decline or skip your assignment because of them. Do your assignment fully.\nYou are one of several agents building the Flutter port of the Madar web dashboard. Worktree: ${ROOT}. FIRST read ${ROOT}/docs/fdash/SPEC.md in full and obey it, especially section 2 (hard rules) and section 4 (ownership). The web dashboard at ${WEB} and every other repo are READ-ONLY references. Other agents are editing other files in this worktree at the same time: touch only what you own, never revert or reformat files you do not own, never commit.
Your role: ${role}.
Files you own: ${owns}.
Every flutter command: prefix FLUTTER_ALREADY_LOCKED=true and use --no-pub. Screenshots go to ${SHOTS} (env FDASH_SHOTS); LOOK at the PNGs you produce (Read them) and fix what looks wrong.
`

const RESULT = {
  type: 'object',
  properties: {
    done: { type: 'boolean' },
    summary: { type: 'string' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    testsRun: { type: 'string', description: 'commands run and pass/fail counts' },
    openIssues: { type: 'array', items: { type: 'string' } },
    needsFromOthers: { type: 'array', items: { type: 'string' } },
  },
  required: ['done', 'summary', 'openIssues'],
}
const FINDINGS = {
  type: 'object',
  properties: {
    findings: { type: 'array', items: { type: 'object', properties: {
      severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
      area: { type: 'string' }, file: { type: 'string' }, problem: { type: 'string' }, evidence: { type: 'string' }, fix: { type: 'string' },
    }, required: ['severity', 'problem', 'fix'] } },
    verdict: { type: 'string' },
  },
  required: ['findings', 'verdict'],
}

const API = pre('foundation: api — the generated Dart client, the mock server and the seed data',
  'packages/dashboard_api/** (keep the public API of lib/src/transport.dart; you may add to it), tool/gen_dashboard_api*, and ONE new melos script entry gen_dashboard_api in the root pubspec.yaml melos.scripts section') + `
Build:
1. tool/gen_dashboard_api.py (Python 3 standard library only, deterministic, idempotent; runs dart format on its output) reading packages/dashboard_api/spec/openapi.json and writing packages/dashboard_api/lib/src/generated/: a model class per schema (immutable, fromJson/toJson, ==/hashCode not required), enums that keep unknown values, unions for oneOf/anyOf, allOf merged, nullable vs required honoured, date-time to DateTime (UTC), int64 to int, number to double, binary to List<int>, maps via additionalProperties; an API class per tag with one method per operation named lowerCamel(operationId) with typed path/query/body params and typed results (model, List, Map, String, List<int> bytes, void; SSE endpoints return Stream<String> via transport.stream); multipart requests use ApiFilePart; a const operation table (operationId, method, path template, tag) for mock routing and coverage; and a DashboardApi facade with one getter per tag. Decode failures throw ApiException(status, code 'decode', message, details).
2. The mock server per SPEC 3.2 in lib/src/mock/: MockServer implements ApiTransport (on/onStream route registration by path template, path params, query parsing, JSON and multipart bodies, a calls log, an unmatched list, latency default zero), MockRequest (pathParams, query, json body, files, persona, requireCap(key) that answers 403 in the backend's exact error envelope — read the MadarRust error type, e.g. src/error.rs, read-only), MockResponse (json/empty/bytes/error with the backend envelope), MockDb with generic tables (list with the backend's paging conventions — read the spec's list endpoints for their params and envelopes — filter, sort, create with deterministic ids, update, delete, timestamps), MockClock fixed by default at 2026-10-08T10:00:00+03:00 (Africa/Cairo).
3. Personas (owner, manager, limited, platform, dawamOnly) with capability keys read from ${WEB}/src/generated/capabilities.ts (plain strings; dashboard_api must not depend on dashboard_core).
4. seed.dart: a deterministic, realistic dataset built THROUGH the generated models (toJson) so every shape matches the spec: organisation "Sabah Coffee" (both modules), 4 branches (Heliopolis, Maadi, New Cairo, Zamalek), Africa/Cairo, EGP; staff and roles; payment methods; menu categories, ~40 items with sizes, add-ons and groups; ~200 customers; 30 days of orders with payments per branch (lazy, generated in < 300 ms) and daily tills. Take names, menu and prices from /Users/shawket/Desktop/Madar/film-capture/seed_film.py and ${WEB}/src/data/api/mock/*.ts (read-only) for realism.
5. Core handlers (lib/src/mock/handlers/core_handlers.dart, registerCoreMocks(server, db)) for what the app shell calls at start: sign-in, the current user, capabilities/authz, org (and its modules / onboarding status), org list for platform admins, branches — read ${WEB}/src/data/stores/auth.store.ts, src/data/scope/**, src/components/layout/** and src/lib/auth-guard.ts to see exactly which endpoints and fields.
6. Exports: package:dashboard_api/dashboard_api.dart (transport, models, apis, facade) and package:dashboard_api/mock.dart (mock server, db, clock, personas, seed, core handlers).
7. Tests: every operationId has a method and a table entry; every schema has a model; JSON round-trips on a broad sample; mock routing/params/unmatched/403/paging; every seed entity parses back through its model's fromJson. Make sure a test imports every generated file so compile errors cannot hide (lib/src/generated is excluded from lint only).
Done when the generator runs clean, flutter analyze on the package is clean and its tests pass.`

const BRIDGE = pre('foundation: core bridge — the Rust side and the real transport',
  'new code in rust-core/crates/madar-core/src (prefer a new module file plus minimal wiring in lib.rs), rust-core/crates/madar-frb-dashboard/**, packages/rust_bridge_dashboard/** (regenerated only), apps/dashboard/lib/data/core_transport.dart and apps/dashboard/lib/data/core_xlsx.dart') + `
You are the ONLY agent allowed to run cargo; always export CARGO_TARGET_DIR=/Users/shawket/Desktop/Madar/madar/rust-core/target (the target was just cleaned, the first build takes a while — run it in the background of your shell if needed). Keep madar-core changes additive; the POS must not change behaviour.
Build:
1. In madar-core: a generic api_request(method, path, query pairs, json body or multipart parts) returning status, headers and body bytes for 2xx, using the core's own HTTP client, base URL, bearer token, identity headers and its existing 401/refresh/auth-paused handling (read net.rs and how dashboard_sign_in / dashboard_summary call the API). Send the same org/branch scope headers the web client sends (read ${WEB}/src/data/api/client.ts) from the core's active scope. A non-2xx answer becomes the core's error with the HTTP status, the backend error code and the human EN/AR message (reuse status_to_error / map_api_error / the refusal wording; a 403 without the backend envelope stays the blocked-upstream case). Plus api_stream(method, path, query, body) yielding each SSE data frame (reuse the streaming client the realtime code uses).
2. In madar-frb-dashboard (dashboard only, not madar-core): xlsx_write(spec json) -> bytes with rust_xlsxwriter and xlsx_read(bytes) -> rows json with calamine. The spec mirrors what ${WEB}/src/lib/excel.ts produces (read it and its test: title rows, header style, column widths and number/money/date formats, freeze panes, right-to-left sheets for Arabic, the logo image). Expose api_request, api_stream (StreamSink), xlsx_write, xlsx_read on the dashboard bridge, keeping every existing function.
3. Regenerate the Dart bindings with the repo's own script for the dashboard bridge (melos script bridge_dashboard / tool/gen-bindings*; flutter_rust_bridge_codegen 2.13.0 is installed).
4. Dart: apps/dashboard/lib/data/core_transport.dart implementing ApiTransport (packages/dashboard_api/lib/src/transport.dart) over the bridge, mapping core errors to ApiException(status, code, message from the core's human wording); apps/dashboard/lib/data/core_xlsx.dart: a thin class with write(Map spec) and read(bytes). Keep pure mapping logic in testable functions.
5. Verify: cargo fmt; cargo clippy on the touched crates with no warnings; unit tests for request building, error mapping, SSE frame parsing, xlsx round-trip; cargo test -p madar-core --no-run plus your new tests; the dashboard bridge crate builds. Report exact commands and results.`

const KIT = pre('foundation: kit — the dashboard UI kit',
  'packages/dashboard_kit/** (you may add assets/fonts declarations to its pubspec.yaml, no new dependencies) and additive entries in packages/design_system/lib/src/icons.dart (do not change existing entries)') + `
Port the web's shared components (${WEB}/src/components/app/** and src/components/ui/**, and how pages use them) to Flutter widgets on design_system, matching the web's behaviour and its quiet, precise product look (paper ground, ink chrome, teal accent, IBM Plex Sans Arabic). Every widget supports right-to-left, dark mode and phone/tablet/desktop widths. dashboard_kit must NOT depend on dashboard_core: all words come in as parameters or through a DashKitLocalizations inherited widget (you define it, with a field per phrase the kit needs; dashboard_core will fill it from the web's i18n keys such as common.*).
Required: DashPageScaffold (title, subtitle, actions, page/section tabs, filter row, body, phone variant); DashDataTable (columns with label, cell builder, sort, numeric end alignment, width; sorting, pagination like the web, row tap, selection with bulk actions, column visibility, sticky header, horizontal scroll when narrow, empty/loading/error slots, and a phone card mode via a row-card builder); DashFilterBar (debounced search, selects, multi-select chips, date range, clear); DashSidePanel (end-side panel on wide, full-screen page on phone, header/footer actions); DashDialog, DashConfirmDialog (destructive variant), DashSheet (phone full-screen form); form fields (text, textarea, number, money in minor units, percent, select, searchable select/combobox, multi-select, switch, checkbox, radio group, segmented control, date, time, date range, timezone select, bilingual EN+AR field, colour, image uploader UI that hands bytes to a callback) with the web's error-under-field display; StatCard, LedgerStrip + ConciseValue, StatValue, AnimatedFigure (respects reduced motion), ProgressBar, StatusPill, SectionHeader, ChartCard and charts (area/line, stacked and grouped bars, donut/pie, sparkline) with tooltips and legends on fl_chart using design_system series tokens and right-to-left aware axes; EmptyState/ErrorState wrappers; SearchInput; PageTabs/SectionTabs; ListRow; PeopleList; EditableCards; ExportButton; CostCells; toast helpers.
Icons: grep ${WEB}/src for lucide-react imports and make sure every icon name the dashboard uses has a MadarIcon entry (additive).
Testing support, exported as package:dashboard_kit/testing.dart: loadDashFonts() (real Plex fonts and whatever MadarIcon renders with, from design_system assets) and captureShot(tester, path) writing a PNG of the whole view through a RepaintBoundary inside tester.runAsync; DashSize presets phone 390x844, tablet 1024x768, desktop 1440x900 at device pixel ratio 2 that set the test view.
Tests: behaviour tests (sort, paging, selection, debounce, validation display, dialogs) and a gallery test rendering every widget and state at the 3 sizes x {en light, ar dark} into ${SHOTS}/kit/. Look at the shots and fix defects. Analyze clean.`

const CORE = pre('foundation: core — dashboard_core contracts',
  'packages/dashboard_core/** EXCEPT lib/src/shell/** and lib/src/testing/** (the shell agent owns those, later); tool/sync_dashboard_i18n*, tool/gen_dashboard_nav*, tool/gen_dashboard_caps*; you may add assets declarations to packages/dashboard_core/pubspec.yaml (no new dependencies)') + `
Build (read the web source for each; it is the reference):
1. Text: tool/sync_dashboard_i18n.py copies and flattens ${WEB}/src/i18n/locales/{en,ar}.json into packages/dashboard_core/assets/i18n/. Strings with i18next semantics: {{var}} interpolation, plural suffixes _zero/_one/_two/_few/_many/_other with CLDR rules (Arabic uses all six), defaultValue, nesting if the web uses it; supplements merged from area packages' assets (asset keys like packages/dashboard_sell/assets/i18n/en.json, declared by each DashArea); lookup order: locale table, supplements, English, defaultValue, key (record missing keys so the harness can fail on them). Riverpod providers (stringsProvider, localeProvider, tProvider) and a BuildContext/WidgetRef extension t(key, args:, count:, defaultValue:). Tests incl. Arabic plurals and a parity test against the web files.
2. Capabilities: tool/gen_dashboard_caps.py generates lib/src/generated/capabilities.dart from ${WEB}/src/generated/capabilities.ts (abstract final class Cap with the web's constant names and key strings) plus org modules.
3. Authz and session: SessionGateway interface (sign in, restore, sign out, switch org for platform admins) and a SessionInfo model; AuthzState (platform flag, capabilities, modules, onboarding/setup status) loaded the way the web does it (read src/data/stores/auth.store.ts, src/lib/auth-guard.ts, src/data/scope/**, components/app/restricted.tsx and module-gate.tsx) through the generated API (package:dashboard_api); canAny; Restricted and ModuleGate widgets.
4. Scope and period: org + branch (or all branches) persisted per org through PreferencesGateway and RESET when the org changes or the stored branch is not in the org's branch list (today's app keeps a branch from another org and the home page fails with "Branch not found"); the period presets, default, custom range, the from/to computation in the branch timezone and the trend granularity exactly as the web's scope bar / app store (src/components/layout/scope-bar.tsx, src/data/stores/app.store.ts).
5. Routes contract: DashRoute (path, builder, capabilities any-of, module, platformOnly, setupOnly, title key, tabs/children, redirect) and DashArea (key, routes, registerMocks(MockServer, MockDb), i18n supplement asset paths).
6. Nav: tool/gen_dashboard_nav.mjs uses esbuild from ${WEB}/node_modules to evaluate src/config/nav.ts and src/features/settings/settings-nav.ts (stub the icon imports) into JSON, then writes lib/src/generated/nav.dart (groups, parents, leaves, paths, capabilities, modules, platform-only, setup flags, icon names mapped to MadarIcon names) and the legacy redirect table from the 25 redirect-only route files under src/routes/_app/**; a test proves the generated nav matches the web source.
7. Formatting: port src/lib/format.ts exactly, with its tests (src/lib/format.test.ts) translated to Dart with the same expectations.
8. Gateways: FileGateway (save bytes, share, pick file, pick image), ExportGateway (API mirroring src/lib/excel.ts, src/lib/download.ts, src/lib/export-all.ts), RealtimeGateway (branch events, same event names, reconnect/backoff and resync semantics as src/data/realtime/use-branch-realtime.ts), PreferencesGateway; providers for each plus transportProvider and apiProvider (DashboardApi over the transport). Mock implementations in package:dashboard_core/mock.dart: MockSessionGateway over the MockServer's auth endpoints and personas, in-memory preferences, recording file/export gateways, a controllable realtime gateway.
9. Fill dashboard_kit's DashKitLocalizations from Strings once packages/dashboard_kit defines it (another agent is writing the kit right now; if it is not there yet, leave a clearly named adapter function and report it).
Tests for all of it; analyze clean. dashboard_api is being generated in parallel by another agent: code against packages/dashboard_api/lib/src/transport.dart and the facade name DashboardApi; if the generated client is not ready when you test, use small fakes and report what you could not test.`

const SHELL = pre('foundation: shell — the app frame, router, sign-in, harness and area stubs',
  'packages/dashboard_core/lib/src/shell/**, packages/dashboard_core/lib/src/testing/** (export them as package:dashboard_core/shell.dart and package:dashboard_core/testing.dart), apps/dashboard/** EXCEPT lib/data/core_transport.dart and lib/data/core_xlsx.dart, and in each of the 9 area packages under packages/dashboard_features/: lib/dashboard_<area>.dart, lib/src/routes.dart, lib/src/mock/register.dart, assets/i18n/en.json and ar.json, and the assets entry in that package pubspec.yaml') + `
The api, bridge, kit and core agents have finished; read what they built (packages/dashboard_api, packages/dashboard_kit, packages/dashboard_core, apps/dashboard/lib/data) before you start.
Owner decisions: devices = phone, tablet and desktop; layout = the web layout on tablet and desktop (width >= 760), phone layout below; phone navigation = a bottom bar with Home, Orders, Reports and More, where More opens the full sidebar as a drawer, shortcuts following the person's permissions and modules; look = the Madar v2 system (paper ground, ink sidebar and header, teal accent, IBM Plex Sans Arabic) — the web's live tokens in ${WEB}/src/styles/globals.css are the same system.
Build:
1. DashShell (lib/src/shell): the web's app frame (read ${WEB}/src/components/layout/** and src/routes/_app/route.tsx): ink sidebar from the generated nav (groups, collapsible parents, active state, filtered by capabilities, modules, platform-only and setup-only exactly like leafVisible in nav.ts), header with org picker (platform admins), branch picker (scope bar semantics), period picker, user menu (language, theme, sign out); phone frame with app bar, the bottom bar and the drawer.
2. Router: buildDashRouter(areas: List<DashArea>, ...) on go_router: sign-in redirect, the legacy redirects, module gate, capability gate and platform/setup-only behaviour exactly as the web, a not-found page, query params kept.
3. Sign-in: port the web's new sign-in screen (commit 111bad16 in ${WEB}; read src/routes/login.tsx and src/features/auth/**), errors included.
4. Command palette (Ctrl/Cmd+K on desktop, a search action on phone) with the web's command-palette.tsx semantics; ask-a-manager dialog as a shell service areas can call (port src/features/access ask-a-manager); live updates provider over RealtimeGateway; theme and language persisted.
5. apps/dashboard: real mode (core boot, CoreTransport from lib/data, a CoreSessionGateway and real gateways you write under lib/real/: preferences JSON in the app support dir, file save/share/pick with file_selector/file_picker/share_plus/image_picker, export over CoreXlsx, realtime over CoreTransport.stream) and mock mode with --dart-define=MADAR_MOCK=1 (MockServer + seed + every area's mocks + MockSessionGateway; sign in as the seed owner) so the app runs with no backend. Delete the old lib/config/nav.dart, the coming-soon screen and the old shell; keep the splash and icons.
6. Harness (lib/src/testing): DashHarness.pump(tester, areas:, path:, persona:, size:, locale:, dark:, server:, clock:) building the full shell and router on the mock server and mock gateways with real fonts; helpers tapText, tapKey, enterText, scrollUntilVisible, expectToast, shot(name) writing ${SHOTS}/<area>/<page>/<name>--<size>-<lang>-<theme>.png when FDASH_SHOTS is set; it FAILS a test on unmatched mock routes, layout overflow errors, and missing i18n keys.
7. Area stubs for all 9 areas (overview, sell, catalog_menu, catalog_offers, reports, inventory, team, setup, admin): routes.dart lists every page path of the area from SPEC section 3 with the web's capabilities/module (from the generated nav and settings nav) and a placeholder page (words from a dashboard_core supplement key, not hard-coded); register.dart with an empty registerXMocks(MockServer, MockDb); the library exports the area's DashArea; empty {} i18n supplements declared as assets.
8. Tests: nav filtering per persona and module, bottom bar and drawer, pickers, redirects and gates, sign-in, command palette, the scope reset bug, and the shell's screenshot matrix (3 sizes x en light / ar dark) — look at them and fix defects. Analyze clean.`

const EXEMPLAR = pre('foundation: exemplar — the home page at full parity, and the page pattern every area will copy',
  'packages/dashboard_features/overview/** and docs/fdash/PATTERNS.md') + `
Port the web home page (${WEB}/src/features/dashboard/dashboard-page.tsx and every card it renders: KeepBuildingCard, LedgerStrip KPIs, OpenTillsCard, DeliveryKpis, revenue trend, payment mix, branch performance, MarginWatchCard) to the overview area at FULL parity, following SPEC section 6: both layouts, all states, gating, words from the web's keys, numbers formatted like format.ts, mock handlers for every endpoint it calls computed from the seed (so totals agree across cards), driven tests for every behaviour (read docs/fdash/inventory/overview.md if it exists for the D-rows), refusal/empty/loading/error tests, and the screenshot matrix. Then write docs/fdash/PATTERNS.md (concise, with code excerpts from your page): how an area page is structured, how providers are keyed and invalidated, how mock handlers and area seed data are written, how a driven test and screenshots are written, and the checklist an area agent must pass. Analyze clean, tests green.`

const INTEGRATE = pre('foundation: integrator', 'any foundation file (everything built so far), but keep each file\'s intent; do not touch packages outside the dashboard_* packages, apps/dashboard, rust_bridge_dashboard, madar-frb-dashboard and the new madar-core module except to fix a break you caused') + `
Make the foundation whole and green:
1. FLUTTER_ALREADY_LOCKED=true flutter pub get at the worktree root once (you are the only agent allowed to), then flutter analyze for apps/dashboard and every packages/dashboard_* package: zero issues. Also make sure the workspace-wide CI checks still pass for what changed: flutter analyze . from the root (report any pre-existing unrelated issues separately), and dart format --set-exit-if-changed over the dart files under apps/dashboard and packages/dashboard_* (generated files included unless CI excludes them).
2. Run every test in apps/dashboard and each packages/dashboard_* package; fix failures. Run design_system's tests too (the kit added icons there).
3. Check the pieces fit: the app's mock mode composes all 9 areas and the core handlers; the harness boots the shell for every area stub path for every persona without unmatched routes; DashKitLocalizations is filled from Strings; the generated nav, the area stubs and SPEC section 3 agree on every path.
Report precisely what you ran and the results.`

const FINISH = args && args.finishOnly
phase('Build')
const built = FINISH ? [null, null, null, null] : await parallel([
  () => agent(API, { label: 'api', phase: 'Build', schema: RESULT }),
  () => agent(BRIDGE, { label: 'bridge', phase: 'Build', schema: RESULT }),
  () => agent(KIT, { label: 'kit', phase: 'Build', schema: RESULT }),
  () => agent(CORE, { label: 'core', phase: 'Build', schema: RESULT }),
])
const [api, bridge, kit, core] = built
const notes = (r, n) => `${n}: ${r ? r.summary + (r.openIssues && r.openIssues.length ? ' | open: ' + r.openIssues.join('; ') : '') + (r.needsFromOthers && r.needsFromOthers.length ? ' | needs: ' + r.needsFromOthers.join('; ') : '') : 'FAILED / no result'}`
const buildNotes = FINISH ? 'api, bridge, kit, core and shell were built in an earlier session and are committed (see git log). The home page (overview area) is partly built on disk; PATTERNS.md does not exist yet.' : [notes(api, 'api'), notes(bridge, 'bridge'), notes(kit, 'kit'), notes(core, 'core')].join('\n')
log('Build done')

phase('Shell')
const shell = FINISH ? null : await agent(SHELL + `\nWhat the other agents reported:\n${buildNotes}`, { label: 'shell', phase: 'Shell', schema: RESULT })

phase('Exemplar')
const exemplar = await agent(EXEMPLAR + `\nThis may be a restart: files may already hold work from an earlier, interrupted attempt at this same assignment. Read what is there first, keep what is right, and continue; do not start over. Read at most ~10 screenshot PNGs per pass; large batches of images make requests time out.\n\nReports so far:\n${buildNotes}\n${notes(shell, 'shell')}`, { label: 'exemplar:home', phase: 'Exemplar', schema: RESULT })

phase('Integrate')
const integ = await agent(INTEGRATE + `\nThis may be a restart: files may already hold work from an earlier, interrupted attempt at this same assignment. Read what is there first, keep what is right, and continue; do not start over. Read at most ~10 screenshot PNGs per pass; large batches of images make requests time out.\n\nReports so far:\n${buildNotes}\n${notes(shell, 'shell')}\n${notes(exemplar, 'exemplar')}`, { label: 'integrator', phase: 'Integrate', schema: RESULT })

const LENSES = [
  { key: 'contract', prompt: `Lens: CONTRACT AND DATA. Check the generated client against packages/dashboard_api/spec/openapi.json (sample at least 40 operations and 60 schemas across tags, including oneOf/allOf/enums/nullable/multipart/SSE), the mock server semantics against the backend (error envelope, paging, refusals), the seed's realism and internal consistency, the Rust api_request/api_stream/xlsx code and its tests, CoreTransport error mapping, and the gateways. Run the relevant tests yourself.` },
  { key: 'parity', prompt: `Lens: PARITY WITH THE WEB. Compare against ${WEB}: the generated nav (every group, leaf, path, capability, module, platform/setup flag), gating behaviour, legacy redirects, the sign-in screen, branch/period pickers (presets, defaults, timezone maths), user menu, command palette, ask-a-manager, i18n semantics (plurals, interpolation, fallback) and format.ts parity, and the home page against dashboard-page.tsx card by card (read docs/fdash/inventory/overview.md if present). Run tests that prove or disprove it.` },
  { key: 'visual', prompt: `Lens: VISUAL QUALITY. Run the screenshot tests with FDASH_SHOTS=${SHOTS} for the kit gallery, the shell and the home page; Read the PNGs (phone, tablet, desktop; en light and ar dark). Compare with the web's look: ${WEB}/screenshots and the brochure captures under /Users/shawket/Desktop/Madar/film-capture/captures (dash folders). Report overflow, clipping, cut text, wrong right-to-left mirroring, raw keys, English in Arabic, misaligned tables, poor contrast in dark mode, cramped phone layouts, inconsistent spacing, and anything that looks unpolished next to the web.` },
]
const review = (round) => parallel(LENSES.map(l => () => agent(pre(`foundation reviewer (${l.key}), round ${round}`, 'nothing: you are READ-ONLY except for running tests and writing screenshots') + `\n${l.prompt}\nRead at most ~12 screenshot PNGs. Be adversarial and concrete: each finding names the file, the evidence (test output, screenshot path, web file:line) and the fix. Severity blocker = wrong behaviour/data or a crash; major = visible parity or polish gap; minor = nit.`, { label: `review:${l.key}:r${round}`, phase: 'Review', schema: FINDINGS })))

phase('Review')
let findings = (await review(1)).filter(Boolean).flatMap(r => r.findings)
let rounds = 0
const fixes = []
while (findings.filter(f => f.severity !== 'minor').length && rounds < 3) {
  rounds++
  phase('Fix')
  const list = findings.map((f, i) => `${i + 1}. [${f.severity}] ${f.file || ''} — ${f.problem}\n   evidence: ${f.evidence || ''}\n   fix: ${f.fix}`).join('\n')
  const fix = await agent(pre(`foundation fixer, round ${rounds}`, 'any foundation file (same scope as the integrator)') + `\nFix EVERY finding below (minor ones too when cheap), re-run the affected tests and screenshot tests, keep analyze and format clean, and report what you fixed and anything you could not:\n${list}`, { label: `fix:r${rounds}`, phase: 'Fix', schema: RESULT })
  fixes.push(fix)
  phase('Review')
  findings = (await review(rounds + 1)).filter(Boolean).flatMap(r => r.findings)
}
const remaining = findings
if (remaining.length) log(`${remaining.length} findings left after ${rounds} fix rounds (${remaining.filter(f => f.severity !== 'minor').length} non-minor)`)
return {
  build: { api, bridge, kit, core }, shell, exemplar, integ,
  fixRounds: rounds, fixes: fixes.filter(Boolean).map(f => f.summary),
  remaining,
}
