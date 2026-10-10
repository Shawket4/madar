# Foundation A (remaining): prefetch audit in the assembled app + pull to refresh
Task 0 (intent hooks: DashIntent, onRowIntent/onPageIntent/…, ref.warm, ref.prefetchRoute, Orders example) is DONE and committed. A previous agent had started Task 1 (it was looking at in-page navigation: the Settings pane list and the Access tabs) when the API dropped it. Look for its partial files (apps/dashboard/test/*prefetch* or similar, git status) and continue.

## Task 1: prefetch audit in the ASSEMBLED app
1. An app-level test in apps/dashboard/test/ boots the real app as `--dart-define=MADAR_MOCK=1` does (apps/dashboard/lib/boot/mock.dart, main.dart), with the REAL clock moving and a mouse pointer. For EVERY route with a `prefetch:`: hover its sidebar row (palette row too if cheap), wait for the warm reads, click, and record every request the page makes after the click. Pass rule = the web's: the reads MadarDashboard/src/lib/route-prefetch.ts warms for that path are NOT requested again on open. Also list, per page, the other requests the opened page still makes.
2. Find and fix any shared root cause in dashboard_core: a key differing between hover and open (scope from/to recomputed with a moving clock, a default filter), a warmed provider disposed before mount, the hover target not covering the row, the router redirect path differing from the nav `to`.
3. A wrong unit prefetch function: don't edit the unit; list it (path, problem, exact fix).
4. Wherever the web calls prefetchRoute/useRoutePrefetch outside the sidebar/palette (home cards, "View all" links, Settings pane list, Access tabs, breadcrumbs), wire the same intent prefetch: in shared code yourself (`ref.prefetchRoute`), in units → list them for me.

## Task 2: pull to refresh on EVERY page (owner request, beyond web parity)
- A manual refresh re-fetches everything the open page shows straight from the live APIs, replacing the cache. Central: add to QueryCache a way to refetch every webCache entry that currently has a listener (the web's refetchQueries({type:'active'})): invalidate them and await their new futures; wire it in the page frame every page goes through (DashPageScaffold and/or the shell's page frame; find the single place) so no unit changes.
- Touch: the drag-down gesture on every page (RefreshIndicator or equivalent, kit tokens). Desktop: also Cmd+R (macOS) / Ctrl+R (others) for the open page. Pages that own their drag or have no outer scroll (floor canvas, Basira chat, menu studio grid, …): the shortcut still works, plus a small refresh action in the page header; don't break their gestures.
- While refreshing show the indicator; on failure keep the shown data and toast with the existing error wording.
- Tests: a pull on a list page re-requests its reads even when fresh (< 30 s); Cmd/Ctrl+R does the same; a page owning its gestures is not broken; inactive cached pages are not refreshed.
- Another foundation agent is building offline persistence at the transport seam; keep your query_cache.dart changes small and additive; don't build any offline storage.

Run python3 tool/fdash_test.py for packages/dashboard_core, packages/dashboard_kit, apps/dashboard at the end (+ a few area smoke tests); analyze changed files.
Final message: the audit table (path; web-warmed reads; refetched on open y/n; other reads on open), root causes + fixes, unit-level prefetch fixes for me to route, what you built for refresh and where, test commands + results.
