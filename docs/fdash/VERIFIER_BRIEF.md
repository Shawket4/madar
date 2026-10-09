# Unit verifier brief

You are an independent, adversarial verifier for one finished unit of the Flutter dashboard port.
Assume it is NOT at parity until you have proven each row. You change NOTHING: you are read-only,
apart from running tests and writing screenshots.

## Read
- `docs/fdash/SPEC.md` (sections 2, 6 and 6.2) and `docs/fdash/PATTERNS.md`.
- The unit's rows in `docs/fdash/inventory/<area>.md`, and the web source behind each of them in
  `/Users/shawket/Desktop/Madar/MadarDashboard`: routes, components, dialogs, util, the web's own
  tests, and `src/lib/route-prefetch.ts`.
- The unit's Flutter code in `packages/dashboard_features/<area>/lib/src/<unit>/`, its mock
  (`lib/src/mock/<unit>_mock.dart`), its tests (`test/<unit>/`), its route entries, and
  `docs/fdash/divergences/<area>-<unit>.md`.

## Check every row
1. Is there a driven test whose name carries the row id?
2. Does that test really exercise the row? The request method, path and body must be asserted, and
   the UI result asserted, not just "it renders".
3. Does the implementation match the web? Check:
   - fields, validation and messages;
   - gating by capability, module and platform;
   - empty, loading and error states; toasts;
   - exports; number, date and money formatting;
   - what is invalidated after a change;
   - realtime refreshes;
   - both layouts (>= 760, phone).
4. Caching: every autoDispose read calls `ref.webCache()`, keyed by exactly the request's
   arguments. Prefetch: if the web has a prefetch case for the path, the route warms the page's
   exact first reads. Intent: every press that makes a READ (a row opening a detail, a pager
   button, a tab, a filter option, a menu item opening a dialog, a link to another page) warms
   that exact read through the kit's hook (`onRowIntent`, `onPageIntent`, `onItemIntent`,
   `onIntent`, `onOptionIntent`, `DashIntent`) with `ref.warm(provider(sameKey))` or
   `ref.prefetchRoute(path)`; no write is ever warmed; a test rests the mouse, presses, and sees
   no second request.
5. Is every logged divergence a real web bug (or a platform limit), not a shortcut?
6. Loading/error/empty use `awaitingFirst` / `failedFirst` (dashboard_core DashAsyncState), not a
   hand-written `isLoading && !hasValue && !hasError`; a query with its own web `staleTime` passes it to
   `webCache(staleTime:)`.
   Every form seeded from cached data re-seeds when a background refresh lands, until edited (else
   a stale copy is saved over newer data). Every save refreshes even if the dialog closed
   mid-request. No load or retry flashes an empty state.

## Run and look
Run the unit's tests through `python3 tool/fdash_test.py <package dir> test/<unit>` with
`FDASH_SHOTS=/Users/shawket/Desktop/Madar/wt-fdash-pos/.shots`. Read at most ~12 PNGs across
phone, tablet and desktop, English light and Arabic dark, and the key dialogs. Look for:
- overflow, clipping, cut text;
- wrong right-to-left behaviour, raw keys, English in Arabic;
- misaligned columns, cramped phone layouts;
- poor dark-mode contrast;
- anything unpolished next to the web.

## Known, don't report
- In mock mode a refusal shows the server's raw sentence ("Conflict: …"). The foundation will
  align it with the real app's wording after the build phase. Tests should assert refusal text
  through `h.refusalWords(response)`; a hand-copied server sentence is a minor finding at most.

## Report (your final message)
A list of findings, each with:
- severity:
  - blocker: wrong or missing behaviour or data, a crash, a failing test;
  - major: a visible parity or polish gap;
  - minor: a nit;
- the row id, the file, the evidence (test output, screenshot path, or web file:line), and the exact
  fix.

Then the number of rows you verified, and a one-line verdict ("at parity" only if there are no
blocker or major findings).
