# Intent + newer-rules sweep over units built before the rules existed
For EACH unit listed for your area, apply the AGENT_BRIEF rules added after it was built:
1. Intent warming (the "Intent warming, on EVERY page" bullet): list every control whose press makes a READ (rows opening a sheet/dialog/page, pager buttons, tabs/segments, filter options, menu items, buttons opening a dialog that reads, in-page links to routes with a prefetch), and wire each with the kit hooks (onRowIntent, onPageIntent, onIntent, onOptionIntent, DashIntent) using ref.warm(provider(key)) with the EXACT provider and key the press uses, or ref.prefetchRoute('/path') for links. Never warm a write. One rest-then-press test per kind (pattern: packages/dashboard_features/sell/test/orders/orders_intent_test.dart): rest 90 ms, one request; press, no second request.
2. Loading/error: replace every hand-written `isLoading && !hasValue && !hasError` / local firstLoad with the core `awaitingFirst` / `failedFirst` (DashAsyncState). Where the web replaces shown rows with the error on a failed refresh, use `hasError && !retrying`. Never show an error or empty state during Riverpod's automatic retries.
3. Re-seed: every form seeded from cached data re-seeds from a fresh read until the person edits (if not already).
4. Saves refresh even when the dialog/page closed mid-request (capture the invalidator/bus before the await).
5. Where the web query has its own staleTime, pass webCache(staleTime:).
Report per unit: what you wired (control → provider), what you changed for 2–5, tests added, test results.
Known in-page links from the prefetch audit: overview home_kpis.dart:149 (/tills); inventory ingredients links if any; catalog_menu studio (done); catalog_offers combo_editor_page.dart:556 (/menu/pricing).
