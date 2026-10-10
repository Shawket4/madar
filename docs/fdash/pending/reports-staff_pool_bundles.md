# reports/staff_pool_bundles: verifier findings to fix (NOT at parity)
1 BLOCKER (BUN-001, SPL-001, ALL-005/030): routes.dart:91 and :110 still set `caps:`, so the shell's gate shows the wrong words and a blank page while permissions load; the page's own gate never runs. Delete those two `caps:` lines (only those); in test/staff_pool_bundles/support.dart drop the caps from unitArea and delete pageGatedArea (point those tests at the default area); real-route refusal tests assert h.t('reports.noAccess'); add a test that pumps before permissions are ready → the page renders and requests nothing.
2 minor (BUN-016): bundles_mix_dialog.dart:188 should test `size != null && size.isNotEmpty`.
3 minor (SPL-015): at 1440 the Item column wraps "Americano · Regular": raise its minWidth (~176) or rebalance flex vs Note (staff_drinks_table.dart:89).
4 Intent warming (owner rule): the Combos/Deals toggle warms bundlesReportProvider for the other kind; a combo row (desktop and phone) warms comboMixProvider; "View order" warms staffDrinkOrderProvider(orderId). Test per kind.
5 Replace the hand-written firstLoad in unit_support.dart:17 with awaitingFirst/failedFirst.
