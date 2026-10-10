# catalog_offers/deals: verifier findings (unit at parity; minors)
(The core gap, branchesProvider ignoring realtime, is fixed already.)
1 Add a deals test: rename Zamalek in the db, emit branch.settings_changed, and expect the dialog's branch row and the "When" text to show the new name.
2 (033) The "item order" divergence row is out of date (compareNames now folds the alef forms): delete or reword it.
3 (ALL-017) The dialog re-seeds from a changed row even after typing (as the web does): add a "question" divergence row like recipes did.
4 (046/049) A partial save refreshes nothing: in the catch, call bus.invalidate(combosInvalidationPrefixes) whenever saved != null; pin it in the 049 test (list count +1); update the divergence row, and add a line that the title then reads "Edit deal", the button "Save" and the toast "Changes saved".
5 (006) sortedDeals uses compareAsciiLowerCase: use the shared compareNames, and the same in the mock's _byListOrder.
6 (ALL-005) The web treats the pick lists as fresh for 5 minutes: in shared menu_options.dart pass `ref.webCache(staleTime: const Duration(minutes: 5))` to offersMenuItemsProvider and offersCategoriesProvider (keep the API; run the whole catalog_offers package).
7 Replace the hand-written loading check (deals_page.dart:272) with awaitingFirst/failedFirst.
8 Intent warming (owner rule): rows opening the dialog if it reads, pagers, filter options, menu items. Test per kind.
