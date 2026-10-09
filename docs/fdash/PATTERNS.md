# Area page patterns (copy these)

The overview package (`packages/dashboard_features/overview`, the home `/`) is the worked example.
Every excerpt below is real code from it unless marked otherwise. SPEC.md wins on any conflict.

## 1. Package layout

Per `AGENT_BRIEF.md` (a unit = a page or a few pages of one area; you own only your unit's files):

```
lib/dashboard_<area>.dart        DashArea (shell's stub; you add only your two i18nSupplements lines)
lib/src/routes.dart              DashRoute list (shell's stub; you add only your own entries)
lib/src/<unit>/<page>_page.dart  route widget + page widget (layouts, states)
lib/src/<unit>/<page>_providers.dart  one autoDispose read per endpoint + its key builders
lib/src/<unit>/<page>_data.dart  what the web computes in the browser, as pure functions
lib/src/mock/register.dart       shell's stub calling each unit's registrar (add your line only)
lib/src/mock/<unit>_mock.dart    your handlers, and your data on top of the shared seed's ids
lib/src/shared/, area_seed.dart  shared by the area's units (fix only what blocks you)
assets/i18n/<unit>.{en,ar}.json  supplement: keys missing from the web's files (sell/setup:
                                 assets/i18n/<unit>/{en,ar}.json)
test/flutter_test_config.dart    hitTestWarningShouldBeFatal = true (copy it)
test/<unit>/support.dart         pump helper + a seeded server you can edit before pumping
test/<unit>/<page>_test.dart     driven tests, one per inventory row, row id in the name
test/<unit>/<page>_mock_test.dart  the handlers' figures against hand-computed ones
test/<unit>/<page>_shots_test.dart the screenshot matrix
```

The overview predates the brief and is one unit, so its files sit flat (`lib/src/home/`,
`lib/src/mock/home_figures.dart` + `home_seed.dart`, `test/home_*_test.dart`); the content is the
pattern, the paths above are where yours go. `home_frame_test.dart` holds the layout, motion,
keyboard, theme, prefetch and retry recipes.

## 2. Route

```dart
const List<DashRoute> overviewRoutes = [
  DashRoute(path: '/', builder: _home, titleKey: 'nav.dashboard', titleFallback: 'Dashboard',
      module: OrgModule.pos, prefetch: _prefetchHome),
];
/// The web's `prefetchRoute('/')`, with the exact keys the page watches.
void _prefetchHome(DashPrefetcher warm, Scope s) {
  if (s.branchId != null) warm(homeBranchSalesProvider(s.branchRange));
  if (s.orgId != null) {
    warm(homeTimeseriesProvider(s.series));
    warm(homeComparisonProvider(s.orgRange));
  }
}
```

- `caps:` = the web's nav/page gate (any-of), from `src/config/nav.ts` / `settings-nav.ts`.
- `prefetch:` only when `src/lib/route-prefetch.ts` has a case for the path, warming exactly what the
  page watches on mount. A different key there means a second request: the prefetch test catches it.

## 3. The page widget

- A route widget handles the web route's own guards, then the page (`HomeRoute`: blank until the
  modules are known, blank for a Dawam-only org whom the router sends to `/staff/team`).
- The page is a `ConsumerWidget` returning `DashPageScaffold(title:, subtitle/subtitleWidget:,
  actions:, tabs:, filters:, body:, phoneBody:)`. Read scope with `ref.watch(currentScopeProvider)`,
  words with `ref.watch(tProvider)`, numbers with `ref.watch(formatProvider)`.
- Two layouts. `DashBreakpoints.isPhone(context)` (< 760) is the phone layout (cards, full-screen
  detail, `showDashSheet`); otherwise the web layout (`DashDataTable` with the web's columns, detail in
  `showDashSidePanel`, forms in `showDashDialog`, which already go full screen on a phone). Inside
  the web layout, follow the web's own Tailwind breakpoints: `DashBreakpoints.sm` (640), `.lg`
  (1024), and 768 where the web uses `useIsMobile` (`DashConciseValue` already does).
- Every card owns its four states, in this order (`home_charts.dart`):

```dart
if (q.firstLoad) {
  body = const HomeSkeleton(height: HomeMetrics.chart);           // web: Skeleton h-64
} else if (q.hasError) {
  body = HomeStateBox(                                            // web: ErrorState className="h-64"
    height: HomeMetrics.chart,
    child: DashErrorState(framed: false, title: t('dashboard.trendFailed'),
        retryLabel: t('common.retry'),
        onRetry: () => ref.invalidate(homeTimeseriesProvider(scope.series))),  // only its own read
  );
} else if (points.isEmpty) {
  body = HomeStateBox(height: HomeMetrics.chart,
      child: DashEmptyState(framed: false, title: t('dashboard.noSalesPeriod')));
} else { /* data */ }
```

- `firstLoad` (`isLoading && !hasValue && !hasError`) is React Query's `isLoading`: a background
  refetch keeps the old data on screen. `DashErrorState(retrying: q.isLoading)` spins its button.
- A query the web keeps `enabled: false` is not watched at all; `watchIf` gives the card a
  "nothing, not loading" value so it shows its empty/zero state (and no request is recorded):

```dart
final q = watchIf(ref, scope.orgId != null, () => homeTimeseriesProvider(scope.series));
```

- Gating: hide/disable exactly what the web does. `ref.watch(authzProvider.select((a) =>
  a.can(Cap.orgSettingsEdit)))` for `<Restricted>`/`canAny`; a hidden control must also not fetch
  (the Keep-building card asks nothing for a person without the cap).
- Words: `t('web.key')`, `t(key, args: {...})`, `t(key, count: n)` (plurals), `t.exists(key)` for the
  web's `t(key, {defaultValue: code})` fallbacks. Formatting: `fmt.fmtMoney`, `fmtMoneyCompact`,
  `fmtNumber`, `fmtPercent`, `fmtShare`, `fmtPeriodNamed`, `fmtDuration` (format.ts rules); wrap a
  figure inside running text with `ltr(...)`. Cut text is `MadarClippedText`.
- Colours and spacing: `context.madarColors`, `DashTone`, `Space`, `Radii`, `DashType`, `DashMetrics`.
  Fixed web heights become named constants (`HomeMetrics.chart = Space.xxl * 8` for `h-64`).
- Entrance motion: the web's `fadeInUp` / `listItem` inside `staggerContainer(x)` is
  `HomeReveal(order: i, step: x ms)` (160 ms, 6 px rise, nothing under reduced motion).

## 4. Reads: providers and the cache key

```dart
/// E1 `GET /reports/branches/{branchId}/sales` — only with a branch picked.
final homeBranchSalesProvider = FutureProvider.autoDispose
    .family<BranchSalesReport, HomeRange>((ref, k) {
      ref.webCache();                                                   // FIRST, always
      ref.watch(realtimeEpochProvider('/reports/branches/${k.id}/sales')); // live + mutations
      return ref.watch(apiProvider).reports.branchSales(
          branchId: k.id, from: _instant(k.from), to: _instant(k.to));   // DateTime.parse
    });
```

- The family argument IS the cache key: a record of exactly the params the request sends
  (`typedef HomeRange = ({String id, String from, String to})`). Build it in ONE place in your own
  providers file: the overview declares `extension HomeKeys on Scope` in `home_providers.dart`
  (`scope.branchRange`, `scope.scopeRange`, `scope.orgRange`, `scope.series`); the page, the Retry
  button, the prefetch and the tests all use it. Not the whole `Scope` (its preset or zone would
  split one web key into several), never a fresh object per build.
- `realtimeEpochProvider(<the request path>)` makes the read refetch when a realtime event or a
  mutation invalidates a prefix of it (`till.*` → `/tills`, `/reports`; `resync` → everything). The
  web's prefix rules live in dashboard_core; you only pass the real path.
- Never call the API from `build` or `initState`; never cache in widget state.

## 5. Mutations (the overview has none; shape per `AGENT_BRIEF.md`)

```dart
Future<void> _remove(Branch b) async {
  final t = ref.read(tProvider);
  final api = ref.read(apiProvider);
  final bus = ref.read(realtimeBusProvider);        // capture BEFORE the await:
  final container = ProviderScope.containerOf(context, listen: false); // the page may close mid-save
  try {
    await api.branches.deleteBranch(id: b.id);
  } on Object catch (e) {
    if (mounted) DashToast.error(context, branchErrorText(e, t));   // never a silent failure
    return;
  }
  bus.invalidate(const ['/branches']);              // web: invalidateQueries({queryKey: ['/branches']})
  container.invalidate(branchesProvider);           // core reads not keyed by a path
  if (mounted) DashToast.success(context, t('branches.deletedToast'));
}
```

- Invalidate exactly the web's `onSuccess` keys (read them; prefixes via the bus, other reads by
  provider) and ALWAYS: unconditionally after the await, never behind `if (mounted)`. Only the
  toast and closing the dialog wait on `mounted`.
- A form's Save shows its busy state, stays open on failure with the server's words, closes on
  success.
- A form seeded from cached data (an edit dialog, a settings form) re-seeds when a background
  refresh lands, until the person has edited it (a copy taken once would save stale data over
  newer).

## 6. Mock handlers and the area seed

```dart
server.on('GET', '/reports/branches/{branchId}/sales', (req) {
  req.requireCap('orders.read');                     // 403 envelope, the backend's words
  final id = req.param('branchId');
  final ids = reportBranches(req, db, id);           // requireBranch / 404 / nil = caller's branches
  final from = req.qDateTime('from'), to = req.qDateTime('to');
  return MockResponse.ok(branchSalesReport(branchId: id, branchName: _branchLabel(db, id),
      orders: ordersIn(db, ids, from: from, to: to), from: from, to: to,
      topLimit: req.qInt('limit') ?? 10));            // the backend's own default
});
```

- Read the backend handler (MadarRust `src/**/handlers.rs`) and reproduce its gate (`requireCap`,
  `requireAnyCap`, `requireBranch`, `requireSameOrg`, `requirePlatform`), its scoping, its 404s, its
  validation (`req.unprocessable(msg, code:)` for a coded 422, `req.badRequest`, `req.conflict`), its
  sort and its paging (`pageOf(req, rows)` → `{data, total, page, per_page, total_pages}`).
- State is real: a create inserts into `db['<table>']` and the next list shows it.
- Times are bucketed in the zone the backend uses (`scopeZone`: the branch's, else the org's, else
  Cairo), not the mock clock's Cairo.
- Compute figures from the shared seed's rows, as the backend does, in pure functions
  (`home_figures.dart`), so cards agree with each other and with other areas' pages (the KPI revenue
  = the sum of branch rows = the payment mix total = the trend's periods). Pin that in
  `<page>_mock_test.dart` with hand-computed expectations.
- Unit data goes in `lib/src/mock/<unit>_mock.dart` (area-wide data in `area_seed.dart`), keyed by the shared seed's ids
  (`SeedIds.maadi`, `MockSeed.menuItemId('latte')`), realistic, no lorem ipsum.

## 7. Driven tests

```dart
testWidgets('OVW-HOME-105 a card\'s Retry asks only its own read', (tester) async {
  final s = homeServer();                          // seeded server: edit db/answers before pumping
  s.server.fail('GET', _series, MockResponse.error(500, 'boom'));
  final h = await pumpHome(tester, server: s.server, db: s.db);
  int count(String t) => h.server.callsTo(t).length;
  final others = {for (final t in [_cmp, _delivery, _watch]) t: count(t)};
  await h.tap(find.descendant(of: find.byType(HomeRevenueTrendCard), matching: find.text('Retry')));
  expect(inHome(find.byType(DashLineChart)), findsOneWidget);
  for (final e in others.entries) expect(count(e.key), e.value, reason: e.key);
});
```

- One test per inventory row, the row id(s) first in the name (`'OVW-HOME-033/034 …'`), so a grep of
  test names gives coverage. Refusal, empty, loading and error each get a test.
- SCOPE every finder. The shell builds every sidebar row and the header repeats words ("All
  branches", "Dashboard", "Orders"); and a consistent seed repeats figures (the delivery total =
  the Talabat payment line). Scope to the page (`inHome(f)` / `homeText('…')` in `support.dart`),
  the card (`find.descendant(of: find.byType(HomeRevenueTrendCard), …)`), `DashSidebar`, a dialog.
  Where a figure legitimately repeats, count before and after (`findsNWidgets(before + 1)`). Tap the
  thing a person taps (the compact text), not a semantics label another widget may also carry.
- Personas: `owner`, `manager`, `limited`, `platform`, `dawamOnly`, `null` (signed out).
- Loading: `final gate = s.server.hold('GET', template)` … assert skeleton … `gate.release();
  await h.settle()`. Export in flight: `h.exports.hold = completer.future`.
- Error: `server.fail(method, template, MockResponse.error(500, …), times: null)`; refusal:
  `MockResponse.denied('orders.read')`; validation: `MockResponse.unprocessable(…, code:)`.
- Requests: `h.server.callsTo(template)` → `.path`, `.query` (assert exact params); exact key reuse
  shows as "no second request".
- Toasts: `await h.expectToast('Saved')` (flushes the timer); after any other toast, `await
  h.flushTimers()` before the test ends, or a pending timer fails it.
- Realtime: `h.realtime.current!.emit('till.opened', data: '{}'); await h.settle();`.
- Navigation to another area's page: `h.allowUnmatched = true` first (that area is not loaded).
- The harness already fails a test on an unmatched route, a crashed handler, a missing key or
  English in Arabic, and a layout overflow. Never silence those to pass.
- Words in assertions: the English literal, or `h.t('key')` when the literal is long.
- Pure rules (`<page>_data.dart`, `signalReason`) also get plain unit tests.

Recipes from `home_frame_test.dart` (copy the helpers):
- Hover / prefetch: `final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await m.addPointer(location: Offset.zero); addTearDown(m.removePointer); await m.moveTo(…)`.
  The prefetch test starts on another path, hovers the sidebar row, asserts one request, taps,
  asserts still one.
- A width between the harness sizes: `tester.view.physicalSize = Size(700, 900) *
  DashSize.pixelRatio; await h.settle();` (`resize`). Columns: count distinct `dy` (`rowsOf`).
- Motion: `pumpHome(…, reducedMotion: false)`, then `tester.pump(Duration(milliseconds: …))` and read
  `FadeTransition.opacity.value` / the shown figure; end with `await h.settle()`.
- Keyboard: `tabTo(tester, finder)` presses Tab until `primaryFocus` is on it; then Enter/Escape
  with `tester.sendKeyEvent`.
- The app's retry policy: a bare `ProviderContainer(retry: webRetry, overrides:
  [transportProvider.overrideWithValue(s.server), orgIdProvider.overrideWithValue(org)])`, listen to
  the read, `tester.pump(const Duration(seconds: 1))` × 20, count calls (403 → 1, 500 → 2, 429 → 4).
  The harness itself runs with retries off.
- Charts: fl_chart paints tooltips (no widgets to find): assert the data the chart was given
  (`tester.widget<DashLineChart>(…).labels/series/formatValue`), hover, and look at the shot. Axis
  ticks are `SideTitleWidget`s (`meta.axisSide`).
- Kit behaviour that differs from the web (breakpoints, chart mirroring): pin what the kit does,
  log it as a "kit" divergence, report it; do not fork the widget.

## 8. Screenshot matrix (`home_shots_test.dart`)

```dart
for (final size in DashSize.values) {
  for (final (lang, dark) in [('en', false), ('ar', true)]) {
    testWidgets('default, ${size.name} $lang', (tester) async {
      final h = await pumpHome(tester, size: size, locale: lang, dark: dark);
      await shootPage(h, 'default');               // scrolls the page, one PNG per screen
    });
  }
}
```

Plus every other state (loading, failed, empty, a dialog/panel/sheet, a popover) at desktop-en-light
and phone-ar-light. Run with `FDASH_SHOTS=…/.shots`, then Read the PNGs (≤ 10 per pass) and fix
overflow, clipping, raw keys, English in Arabic, wrong direction, empty boxes, poor contrast.

## 9. Divergences

`docs/fdash/divergences/<area>-<unit>.md`, one table row per difference:
`| Row | Web | Flutter | Why |`. A web bug (raw transport error, English in Arabic, lost save):
port the intent, pin it with a test named `'<ROW> (divergence) …'`. A quirk that is a product
choice: port as is. Unsure: port the web's behaviour and write "question".

## 10. Done checklist (all must hold before reporting)

1. Every inventory row id appears in a passing test name (list any you could not cover, and why).
2. Every endpoint the page calls has a handler with the backend's gate, scope, errors and paging.
3. Loading, empty, error (+ Retry refetching only that read) and refusal tests for each card/table.
4. Mutations invalidate exactly the web's keys; failures toast the server's words; no silent Save.
5. Prefetch set when the web has a case, with the page's exact keys.
6. Both layouts (< 760 and ≥ 760) render; screenshot matrix shot and looked at.
7. No hard-coded UI text; missing keys in the supplement with correct Arabic.
8. `python3 tool/fdash_test.py <pkg> <your tests>` green and `--analyze <pkg> lib test` clean.
9. Divergences logged.
