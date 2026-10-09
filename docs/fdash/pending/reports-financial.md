# reports/financial: verifier findings to fix (NOT at parity)
1 BLOCKER (REP-FIN-037/040): _FinTargetFormState in fin_profitability.dart (~821-900) seeds once (`!_seeded`); a background refetch leaves stale values, an untouched field counts as changed, and Save PUTs stale data. The web re-seeds on every targets change (target-editor.tsx:51-56). Keep `_seededFrom` + `_edited`; re-seed while `!_edited && !identical(d, _seededFrom)`; set _edited in both fields' onChanged. Test: open the editor, change the org target in finTargetsTable, invalidateInsights(bus), settle → the field shows the new value and Save stays disabled.
2 MAJOR (073): Orders/Discounts stack on the 1024 tablet; the web's lg:grid-cols-2 is a 1024 VIEWPORT query. In fin_sales.dart:283-298 use MediaQuery.sizeOf(context).width >= DashBreakpoints.lg (like fin_inventory.dart:99); add a DashSize.tablet test that both cards share a dy.
3 minor (073): the lower pair's staggered fade-in (web staggerContainer(0.06) + fadeInUp): 60 ms step, nothing under reduced motion.
4 minor (017): grey only the Dog class chip's text (web pp:47-52).
5 minor (063/064): chart errors show no server message (web ChartError passes none; fin_charts.dart:331): drop `message:`.
6 minor (050): financial_mock.dart:1418 re-registers GET /users differently from admin's users_mock.dart:178: register only when `!server.handles('GET','/users')`, and match admin's filter.
7 minor (031/032/040): assert the full Dismiss/Snooze bodies and the PUT margin-target `org_id` query (as fin_flags_test.dart:111-120).
8 Intent warming (owner rule, AGENT_BRIEF): wire every control whose press makes a read (the six tabs, granularity segments, the Snapshot/Today's costs switch, the scope toggle, ledger rows and flag popovers that read, pagers, filter options), with a test per kind (hover → click → no second request).
9 Replace the hand-written firstLoad (fin_profitability.dart:27) with the core awaitingFirst/failedFirst.
