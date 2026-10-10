# inventory/today + inventory/counts: verifier findings to fix (both NOT at parity)
## today (lib/src/today/, test/today/)
1 MAJOR (TOD-018/029): the Receive DashButton (today_parts.dart:541) needs onIntent: () => ref.warm(purchaseOrderProvider(p.id)), as purchasing/orders_tab.dart:121 does.
2 MAJOR (TOD-005/011): the in-page links need onIntent: "Count this branch's stock" (:179) → ref.prefetchRoute('/inventory/counts'); "View all" (:353) → ref.prefetchRoute('/inventory/ingredients').
3 MAJOR: add intent tests (rest, press, no second GET) per control, following sell/test/orders/orders_intent_test.dart.
4 MAJOR (TOD-015/020/026): Arriving (:515) and Waste (:595) branch on q.hasError, so they show "Couldn't load…" during automatic retries. Use q.failedFirst and pass retrying: q.isLoading to their DashErrorState. The low-stock table (:361) must use low.errorText(t) (shared/inventory_data.dart:100), not low.hasError.
5 MAJOR (TOD-012): the Supplier column cuts "Golden Bakery…" at desktop. Give it flex/minWidth (e.g. flex: 2), loosen Name, re-shoot.
6 MAJOR (TOD-030): drive the real waste dialog from Log waste: fill it, save, assert POST /inventory/branches/{id}/waste with lastBody, and check the new line in Today's list (today_page_test.dart:1245 currently fakes it).
7 minor: remove tolerateSiblings (today_page_test.dart:32-35 and its uses); keep allowUnmatched only where truly needed.
8 minor (TOD-032): at 1024 the KPIs are 2×2 (kit DashLedgerStrip uses the container width; the web's lg:grid-cols-4 uses the viewport). Log a kit divergence and assert the column count in the tablet test.
## counts (lib/src/counts/, test/counts/)
1 MAJOR (CNT-015/016): onRowIntent: (s) { if (s.status == 'finalized') ref.warm(varianceReportProvider(s.id)); } (counts_page.dart:271), and the same as onIntent on View report (:281).
2 MAJOR (CNT-004/006/018): "Start a count" (:138) and "Count this branch" (:151 via _FirstRunCard) need onIntent warming ingredientCategoriesProvider(orgId) and inventoryCatalogProvider(orgId).
3 MAJOR (CNT-034): "New ingredient" (count_editor.dart:464) needs onIntent: () => ref.prefetchRoute('/inventory/ingredients').
4 MAJOR: add intent tests per control.
5 MAJOR (CNT-017/033/053): retries show errors. Use failedFirst in variance_report_dialog.dart:38,42,76 and the editor (count_editor.dart:443); use q.errorText(t) in the history table (counts_page.dart:166).
6 minor (CNT-012): the "—" in By is plain on the web (counts-page.tsx:128), not muted.
7 minor (CNT-011): the Scope cell should use MadarClippedText (hold hint), not Text.rich with ellipsis.
