# reports/loyalty_inventory_staff: verifier findings to fix (NOT at parity: 1 blocker, 1 major, 4 minor)
1 BLOCKER (intent; LOY-002/010/013, INV-003/005/007/015):
- loyalty_report_page.dart:59-66 DashPageTabs: onIntent: (v) => ref.warm(switch (v) { 'campaigns' => loyaltyCampaignsProvider(key), 'liability' => loyaltyLiabilityProvider(key), _ => loyaltyBehaviorProvider(key) });
- inventory_reports_page.dart:208-224: tabs onIntent → _warmTab(v): invLowStockProvider(scope.lowStockKey) for Low stock, else that tab's provider with scope.invKey(_scope), skipping a null key and poLeadTime without canLead;
- InventoryScopeToggle onIntent: (v) warms the open tab's provider with scope.invKey(v).
- Tests like sell/test/orders/orders_intent_test.dart: hover 90 ms, press, callsTo(tpl) has length 1. The pattern to copy is financial_page.dart:176,190.
2 MAJOR: delete LisAsync.firstLoad (lis_support.dart:17-20) and use q.awaitingFirst for loading.
- Inventory tables and Low stock: error: q.hasError && !q.retrying ? q.error : null.
- Loyalty Overview/Campaigns/Liability: q.hasError && !q.retrying (the web shows the error even with data).
- Staff: q.failedFirst.
Uses are at loyalty_report_page.dart:90,201,303; inventory_reports_page.dart:248,289,332,393,401; inventory_low_stock.dart:95-96; staff_discipline_page.dart:137-142.
3 minor (STF-005): _loadedAt is set only by a ref.listen that doesn't fire for the current value, so reopening within 30 s then resuming after 30 s refetches nothing. Use fireImmediately: true (skip the toast when prev == null) or `_loadedAt ??= now` in build when q.hasValue. Test: open, leave, return < 30 s, advance 31 s, resume → one more request.
4 minor: tokens instead of raw sizes: staff_discipline_page.dart:139 DashSkeleton(height: 160); :228 Container(height: 1) → MadarHairline; inventory_reports_page.dart:378 maxWidth: 448 → a named constant.
5 minor: rename tests so 005, 006 and 008 carry their ids ("REP-LOY-004/005/006/007/008 …", loyalty_report_test.dart:171,222).
6 minor (kit): ".Delta Dairy Co" in Arabic phone cards; log it as a kit candidate (free-text cell direction from content).
