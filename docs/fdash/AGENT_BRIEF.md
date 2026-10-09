# Unit builder brief (every page-builder agent follows this)

You are one of many agents porting the Madar web dashboard to Flutter, each owning one **unit**
(a page or a few pages of one area). Your prompt names your area, unit, web paths and any note.

## Read first
1. `docs/fdash/SPEC.md`, all of it. Obey section 2 (hard rules), section 4 (ownership) and
   section 6.1, including the **caching** rule (every autoDispose read calls `ref.webCache()`
   first) and the **prefetch** rule.
2. `docs/fdash/PATTERNS.md`: the page pattern to copy (the overview package is the worked example).
3. Your area's inventory `docs/fdash/inventory/<area>.md`: your unit's rows are the definition of
   done.
4. The web source behind each of your rows in `/Users/shawket/Desktop/Madar/MadarDashboard`
   (routes, features, dialogs, util, and the web's own tests). It and every other repo are READ-ONLY.

## What you own (and nothing else)
- `packages/dashboard_features/<area>/lib/src/<unit>/**`
- `packages/dashboard_features/<area>/test/<unit>/**`
- `packages/dashboard_features/<area>/lib/src/mock/<unit>_mock.dart`
- your supplement word tables, in your AREA's convention, which its `lib/dashboard_<area>.dart`
  `i18nSupplements` list shows: sell and setup use a folder per unit
  (`assets/i18n/<unit>/en.json` and `ar.json`, already declared); the other areas use
  `assets/i18n/<unit>.en.json` and `<unit>.ar.json`
- `docs/fdash/divergences/<area>-<unit>.md`
- **Only your own `DashRoute` entries** in the area's `lib/src/routes.dart`, your own line in
  `lib/src/mock/register.dart` if it is missing, and your own two lines in the area's
  `lib/dashboard_<area>.dart` `i18nSupplements` list
  (`'packages/dashboard_<area>/assets/i18n/<unit>.en.json'` and `.ar.json`), if they are missing.
  The area's pubspec must list `assets/i18n/` (check it; don't add it twice). Without the
  declaration your words never load. Other units edit the same files at the same
  time: re-read the file immediately before an edit, change only your lines, never reformat it.
- The area's `lib/src/shared/` and `lib/src/area_seed.dart` are shared by its units: fix a bug
  there only if it blocks you, keep the public API, and say so in your report.

Never touch other files, never revert or reformat anything you don't own, never commit, never
push, never run `pub get`, never edit shell configuration. The shared packages (dashboard_api,
dashboard_kit, dashboard_core, apps/dashboard) belong to the foundation: if a shared widget is
missing or broken, build a local one in your unit and list it under kit candidates.

## How to work
- Tests and analyze ONLY through `python3 tool/fdash_test.py <package dir> [test files]` and
  `--analyze`. It queues when the machine is busy; that is normal. Run your own unit's tests, not
  the whole package, until the end.
- Screenshots: `FDASH_SHOTS=/Users/shawket/Desktop/Madar/wt-fdash-pos/.shots`. Read at most ~10
  PNGs per pass (big image batches make requests time out) and fix what looks wrong.
- Work in small, saved steps: write files early and run tests often, so an interruption loses
  little. This may be a restart: read what is already in your files first, keep what is right, and
  continue from it.
- Keep the disk in mind: don't create large files; screenshots only through the harness.

## Build to FULL parity (SPEC section 6)
- Every inventory row of your unit, with the web behaviour behind it.
- Both layouts: the web layout at >= 760 wide, the phone layout below.
- Every dialog, side panel and sheet; every filter, sort, search and pagination control; exports.
- Toasts; empty, loading and error states; gating and module rules.
- Words from the web's keys. Missing keys go in your supplement, with correct Modern Standard
  Arabic.
- Numbers, money and dates formatted like `format.ts`.
- Reads use `ref.webCache()`, keyed by exactly the arguments the request uses.
- Mutations invalidate exactly what the web invalidates, ALWAYS: capture the invalidator (or
  `realtimeBusProvider`) before the `await` and invalidate unconditionally after it. The web's
  query client refetches even after the dialog or page closes mid-save, so never put the
  invalidation behind `if (mounted)`. Realtime events refresh what the web's do.
- A form seeded from cached data (an edit dialog, a settings form) re-seeds when a background
  refresh lands, until the person has edited it. A read opened on data older than 30 s refetches
  in the background (`ref.webCache()`), and a form that copied the old value once would save it
  over newer data.
- Loading vs error vs empty: show a skeleton while there is no data (`isLoading && !hasValue`),
  an error with Retry when it failed with no data (also while that retry runs), and the web's
  empty state only for a real empty answer. Never flash "no results" during a load or retry.
- If `MadarDashboard/src/lib/route-prefetch.ts` has a case for your path, set `prefetch:` on your
  route, warming the page's exact first-mount reads, and add a hover test: the page opens without
  a second request. `dashboard_admin/test/shared/prefetch_test.dart` is the pattern.
- Mock handlers for EVERY endpoint you call, behaving like the backend:
  - validation 422s, and 403 refusals per capability;
  - paging, and state that persists across calls;
  - data consistent with the core seed and the area seed.
- Tests:
  - a driven DashHarness test per inventory row, with the row id in the test name;
  - refusal tests per persona;
  - empty, loading and error tests;
  - the screenshot matrix.

  Scope finders to the widget under test (the shell builds every sidebar row, and pages share
  words). Assert a refusal's words with `h.refusalWords(response)`, never a hand-copied server
  sentence: the mock's wording will be aligned with the real app's later, and the helper
  follows.
- A web bug is not copied: port the intent and log it in your divergences file.

Iterate until all your tests pass, analyze is clean for your files, and your screenshots look right
at every size, in both languages and both themes.

## Final message
Inventory rows covered/total, the missing row ids, the test command and its result, kit
candidates, and open issues. Be honest about coverage.
