# admin/branches: verifier findings (1 major, minors)
1 MAJOR (BRA-006/007/008/011): at tablet, phone numbers, printer IPs and the warehouse name are cut (branches_page.dart:339-421). Status: fixed width 104; Phone minWidth 150; Printer minWidth 170; Name minWidth 180 (≈604 of ~606 px at 1024). Re-shoot at tablet EN and AR and check there's no sideways scroll (the kit doesn't pin row actions). The Phone cell → MadarClippedText.
2 minor (BRA-004): /branches is fetched twice (page adminBranchesProvider + core branchesProvider, same request). Have the page read the core branchesProvider (Retry invalidates it), keep the route prefetch warming that same provider, and update the tests (ADM-BRA-012's fail times: 2 → 1). Run admin test/users too (it uses adminBranchesProvider): keep adminBranchesProvider as a forwarding alias if other files import it.
3 minor (BRA-029/037): log a divergence (reply) for the lat ±90 / lng ±180 / radius ≥ 0 checks.
4 minor (BRA-037): clearing Radius sends null, which the backend ignores (COALESCE). Make Radius required (drop allowEmpty, default 200) and note it in the row.
5 minor (BRA-009/012): a test emitting branch.settings_changed → one more list request and the new value shown.
6 minor (BRA-019/020): BranchDialog pops when editing and the refreshed list no longer holds the id.
7 nit (:363): the phone "—" → DashType.body.copyWith(color: c.textSecondary).
