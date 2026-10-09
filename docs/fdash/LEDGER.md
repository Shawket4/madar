# fdash parity-2 ledger — cap: 20 concurrent subagents (CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS)
running (20): overview exemplar; sell orders tills floor bookings customers; catalog_menu items studio recipes groups pricing bases; catalog_offers discounts combo_editor; reports operations; inventory ingredients; team employees; setup payment_methods; admin users onboarding
queued (40, launch one per finished agent, in this order):
 catalog_offers combos, deals
 reports financial, legal, basira, tills_report, staff_pool_bundles, loyalty_inventory_staff
 inventory purchasing, counts, today, waste, transfers, inv_settings
 team schedule, team_setup, attendance, payroll, rules, requests, shifts, team_board, approvals, team_reports
 setup loyalty, integrations, qr, links, kitchen, staff_pool, delivery, brand_appearance, booking_settings, combo_settings, whatsapp
 admin orgs, branches, devices, roles, review
after a builder finishes: verifier for that unit (counts against the cap), then fixer if needed
DONE overview (113/113, 141 tests) — committed; verifier pending (run when a slot frees)
KIT/FOUNDATION TODO (mine): tooltip dot glyph box in shots; KPI strip at 1024 (3+2 → 5); page gutter 24→32 at 1024; compact figures switch 760 vs web 768; page fade-in in DashPageScaffold; violet/Talabat tokens
OWNER QUESTIONS: charts left-to-right in Arabic?; "View all"/"Menu profitability" keep scope (web drops it)
BUILT catalog_menu/bases (34/34, 123 tests; builder agent ac7338afd49422be8) → VERIFYING (verifier acb00f6d1271bf2c1); fixes go back to the builder via SendMessage
WEB FIX TODO: ar.json labels the Arabic-name field "الاسم (إنجليزي)" (Name (English)) → "{{label}} (عربي)"
KIT TODO: DashBilingualField onSubmitted (Enter submits); DashAlert; disclosure (<details>)
BUILT catalog_offers/discounts (45/45, 115 tests; builder a6e94c1691bf0ee4b) → VERIFYING
FIXED foundation: unit supplement loader (languageOfAsset) — committed
KIT TODO (+discounts): DashBadge outline; DashDataTable resets page on rows change + Esc clears search; field showing hint+error; DashBilingualField breakpoint by screen + Enter submits; shared getErrorMessage port; toggle pill
BUILT setup/payment_methods (41/41, 108 tests; builder a1b58f98557945a5b) → VERIFYING
SEED TODO (foundation, dashboard_api mock seed): core seed payment methods use colour names/Material icons instead of backend hex + web icon ids
KIT TODO (+pay): DashStatCard skeleton fixed 80px overflows narrow card; DashDataTable control column property; check Arabic phone stat figure alignment
OWNER Q: SET-PAY-039 tellers/devices loading/failed shows "No tellers..." (ported as is)
VERIFIED catalog_menu/bases: 2 major + 5 minor sent back to builder ac7338afd49422be8 (fixing)
FOUNDATION SWEEP TODO (after builders): mock refusal wording = core's answer_words rules (strip kind prefix; uncoded 403/429 words; Arabic never server English; coded → errors.codes.*) via a transport wrapper in harness + mock boot; then update h.refusalWords + the ~81 hard-coded raw strings
BUILT inventory/ingredients (INV-ING 56/56 + INV-ALL 24/27; 124 tests; builder a0f525bc82b3ed015) → VERIFY QUEUED
  notes: imports helpers from purchasing/purchasing_data.dart (jsNumberString, export helpers) → move to inventory/shared in area check; Record waste opens Waste unit's dialog (body pending)
KIT TODO (+ing): DashSurface title-trailing slot; DashDataTable page reset on rows change + search not trimming; DashTextField textAlign
LAUNCHED catalog_offers/deals builder
VERIFY QUEUE: overview, inventory/ingredients
VERIFIED catalog_offers/discounts: AT PARITY (3 minor → builder fixing)
NOTE (all areas): export logo should be brand.logoUrl?.trim(), blank → none (web use-brand.ts:111) — check in area checks
FIXED catalog_menu/bases: all 7 findings fixed (124 tests) — re-verify in the catalog_menu area check
NOTE: dashboard_api exports a model named Column → area code must `hide Column` (studio warned)
BUILT admin/users (58/58, 135 tests; builder ada08532d1ee7fab9) → VERIFYING
INTEGRATION TODO: wire makeEmployeeLauncher (admin users) to team's showAddEmployeeDialog(context, userId:) at app start; roles should warm users on /access/roles (reuse prefetchUsers)
KIT TODO (+users): shared error-wording fn in core (orgErrorWords dupes); initials avatar; stat grid; DashCheckboxField crashes in Wrap; cross-area dialog seam
LAUNCHED reports/financial builder
DONE catalog_offers/discounts — verified + fixed (117 tests), committed (route entry rides with the area commit)
BUILT sell/tills (64/64, 113 tests; builder ae9d66f59452839fd) → VERIFYING
KIT TODO (+tills): DashDataTable onRowHover/onRowPrefetch; DashSectionHeader widget description; DashListRow trailing badges before value
LAUNCHED reports/legal builder
BUILT sell/bookings (80/80, 127 tests; builder a8b9fc72f90d1838b) → VERIFY QUEUED
INTEGRATION TODO: export showBookingSettingsDialog from dashboard_sell for setup /settings/bookings (cross-area seam); apiWithHeaders (customers_data) → dashboard_core candidate
VERIFYING inventory/ingredients (launched)
VERIFY QUEUE: overview, sell/bookings
VERIFIED setup/payment_methods: AT PARITY (3 unit minors → builder fixing)
KIT TODO (+pay verifier): DashStatCard skeleton cap to card width (then pay unit → wide?4:2); hintTextDirection in DashTextInput InputDecoration (controls.dart:293); DashSelectField menu maxHeight (256)
BRIEF: added always-invalidate-after-await + loading/error/empty rules
BUILT catalog_offers/combo_editor (89/89, 86 tests; builder a3c076eeb43419ec8) → VERIFY QUEUED
KIT TODO (+ced): danger-outline button; page title as widget; form helpers (labelled field, 2-col grid, scroll-to-invalid, number-only input — deals has a copy); time/date field labels merge (a11y)
OPEN: shared menu_options.dart sorts Arabic names by code units, not locale-aware (web localeCompare)
VERIFYING sell/bookings (launched)
VERIFY QUEUE: overview, catalog_offers/combo_editor
DONE setup/payment_methods — verified + fixed (110 tests), committed
catalog_offers/combo_editor: rules applied (86 tests) → VERIFY QUEUED
AREA CHECK catalog_offers: shared menu reads (items, categories) not autoDispose/webCache; shared gate blank while permissions load (OFFR-ALL-018)
LAUNCHED reports/basira builder
BUILT catalog_menu/groups (50/50, 126 tests; builder a1eeba9d8eeae05ff) → VERIFY QUEUED
VERIFYING overview (launched)
VERIFY QUEUE: catalog_offers/combo_editor, catalog_menu/groups
KIT TODO (+groups): switch with tappable label; radio row with inline content; inline spinner; DashBadge variants (again)
WEB+CORE FIX: bilingualField.arabicLabel "{{label}} (إنجليزي)" wrong → "(عربي)" (web ar.json + synced core table)
BUILT reports/operations (REP-OPS 69 + REP-ALL 31 = 100/100, 178 tests; builder a0c000c4954af6bd4) → VERIFY QUEUED (divergence log written by me — agent couldn't write .md)
KIT TODO (+ops): stat card action in a corner; vertical bar chart all labels + LTR plot in Arabic; horizontal bar chart; equal-height card row; read-only customer/order panels shared
CORE TODO: excludedItemsProvider (madar.excluded-line-items.<orgId>) → dashboard_core, shared with Orders; elapsed format renders out of order in Arabic
BUILT catalog_menu/pricing (33/33, 95 tests; builder a7c562965e2fa5be9) → VERIFY QUEUED
WEB FIX TODO (serious, from pricing): 028 add-on edits staged on another page dropped on Save; 029 showing a branch-hidden channel says Saved but writes nothing; 030 search keeps page number; 031 invalid-price warning blank name; 032 channel add-on prices loading/failing shown as inherited; 033 raw "one_size"; 027 partial-failure reason missing
OWNER Q: add-on override reads need deploy/menu_unification_shim.sql applied on the backend
OPEN: items mock PUT/DELETE /menu-price-overrides lacks target/channel 400 checks (items unit)
VERIFYING combo_editor; LAUNCHED reports/tills_report builder
VERIFY QUEUE: catalog_menu/groups, reports/operations, catalog_menu/pricing
BUILT sell/customers (58/58, 180 tests; builder a80e04876789fc438) → VERIFY QUEUED
CROSS-AREA: Loyalty → Members tab (setup loyalty unit) not built; Google Wallet dialog lives in sell/customers — setup/loyalty should reuse via a seam
KIT TODO (+cus): DashDataTable error `retrying` flag; dashFigure cuts last digit of short numbers in Arabic inside FittedBox (!); side-panel title pill + widget description
LAUNCHED reports/staff_pool_bundles builder
VERIFY QUEUE: catalog_menu/groups, reports/operations, catalog_menu/pricing, sell/customers
BUILT catalog_offers/combos (OFFR-CMB 37 + OFFR-ALL 19, 101 tests; whole package 367 pass; builder ab9da2fe42fb6571f) → VERIFY QUEUED
AREA CHECK catalog_offers: offersCategoriesProvider should reuse comboCategoriesProvider (webCache key /categories)
KIT TODO (+cmb): DashFilterBar search width; kit search box clear/trim behaviour vs web
VERIFYING catalog_menu/groups (launched)
VERIFY QUEUE: reports/operations, catalog_menu/pricing, sell/customers, catalog_offers/combos
VERIFIED sell/tills: NOT at parity (3 major + 6 minor) → builder ae9d66f59452839fd fixing; seed T2 orders on T1 tills → orders builder told
BUILT admin/onboarding (31/31, 103 tests; builder adb971684b0a754a8) → VERIFY QUEUED. Editors COPIED from catalog_menu (category, ingredient, recipe builder, group form, per-size grid) → integration: move to a shared package
SEED TODO: core seed onboarding stub uses wrong step keys
OWNER Q (onb): owner can't save café name (backend super-admin only); new item Active switch ignored on create; " (EGP)" + sample placeholders literal
VERIFIED inventory/ingredients: NOT at parity (1 major bidi + 6 minor) → builder fixing + helper move to inventory/shared
KIT TODO (+ing verifier): DashSurface actions layout (wrap in one row on phone)
VERIFYING reports/operations (launched)
VERIFY QUEUE: catalog_menu/pricing, sell/customers, catalog_offers/combos, admin/onboarding
VERIFIED admin/users: AT PARITY (8 minors → builder fixing)
INTEGRATION TODO (+users): share one provider for /staff/employees/linkable between admin users and team employees when wiring the make-employee seam; roles route prefetch users; roles mock may re-register GET /authz/roles (collision)
BUILT catalog_menu/recipes (23/23, 87 tests; builder a71f90c6a9c5659f9) → VERIFY QUEUED
KIT TODO (+rcp): compact inline error with Retry for fields/dialogs
OPEN: catalog_menu merged en.json 11 keys vs ar.json 23 → check in area check (missing English?)
LAUNCHED reports/loyalty_inventory_staff builder
VERIFY QUEUE: catalog_menu/pricing, sell/customers, catalog_offers/combos, admin/onboarding, catalog_menu/recipes
BUILT sell/floor (91/91, 144 tests; builder a387087879f52ad2b) → VERIFY QUEUED; changed shared area_seed.dart (areas placed side by side)
OWNER Q (floor): Seats field silently ignores non-integers 0..99 (as web) — show error words?
WEB FIX TODO (floor): edit in last 600ms before navigating dropped; undo of a no-op click leaves "Saving…" forever; undo of first edit after autosave does nothing; partial delete failure no re-read; "ready" bill reads Voided; branch switch keeps floor
KIT TODO (+floor): danger ghost button; pill filter chip
VERIFYING catalog_menu/pricing (launched)
VERIFY QUEUE: sell/customers, catalog_offers/combos, admin/onboarding, catalog_menu/recipes, sell/floor
VERIFIED sell/bookings: NOT at parity (3 major + 5 minor) → builder a8b9fc72f90d1838b fixing
AREA CHECK sell: fold 4 copies of the error-wording helper into sell/shared
BRIEFS: added "forms re-seed on background refresh until edited" (builder) + verifier check 6
DONE inventory/ingredients — verified + fixed (129 tests; inventory 307 pass), committed. Waste POST from drawer untested until waste unit builds its dialog
LAUNCHED inventory/purchasing builder
DONE admin/users — verified + fixed (137 tests), committed
VERIFIED overview: NOT at parity (2 major: View all mid-card [unit], chart x-labels clipped [KIT charts.dart:295 fitInside + width-based thinning]) → exemplar a89a11da41a066b92 fixing 1,4,5,7,8 + PATTERNS.md corrections
CORE TODO: one webCache onboarding read shared by shell onboardingCompletedProvider + home card (2 requests → 1)
KIT TODO (+ovw): DashLedgerStrip 50ms stagger; trend area flat 12% fill (vs gradient)
VERIFIED catalog_offers/combo_editor: NOT at parity (BLOCKER stale-form re-seed + 8 minor) → builder a3c076eeb43419ec8 fixing incl. shared menu_options (webCache + locale sort)
KIT TODO (+ced v): locale-aware collation helper (case/accent/alef folding) for sorts
AREA CHECKS: re-run verifier check 6 (stale-form re-seed, always-refresh, no empty flash) on units verified before the rule: discounts, payment_methods, users, ingredients, bases
VERIFIED catalog_menu/groups: NOT at parity (1 major empty-ar name + 7 minor) → builder a1eeba9d8eeae05ff fixing
DONE sell/tills (fixed, 118 tests) and sell/bookings (fixed, 136 tests) → COMMIT WITH SELL AREA (units entangled: bookings uses floor providers, orders seed feeds tills)
BUILT sell/orders (109/109, 107+34 tests; builder a893d3c60342c7650). Floor imports orders/error_text.dart. OWNER Q: export dates from UTC (Cairo day reads as previous date) as web
BUILT reports/legal (38/38, 139 tests; builder a65285a70e84810fd). Route caps removed so page gate words show. OWNER Q: platform admin w/o org → Tax skeleton forever (web); "حدث" vs "حدثًا" plural
DONE overview — committed c1e69923 (with briefs). Leftover KIT: hourly axis labels cut (charts.dart), KPI stagger, trend fill
BUILT catalog_offers/deals (50/50, 163 tests; builder ad88390951806ea2c). Fixed: branch switches never saved, retry duplicating a deal
BUILT team/employees (57/57 EMP + 16/26 ALL, 189 tests; builder a02e0cdaab820d395)
INTEGRATION TODO (+emp): team_setup step 2 + Team header → showAddEmployeeDialog/showImportPeopleDialog; admin users "Make employee" → export AddEmployeeDialog from dashboard_team.dart; attendanceErrorText → team/shared; employees mock hides salaries w/o hr.payroll.read + counts suspended in departments (other team units may notice)
KIT TODO (+emp): phone field, branch checklist, icon-only row action, date field flip-above, LTR placeholder in RTL; (+deals) table error retrying flag
LAUNCHED verifiers: combos a3cd9c15b5b79d18c, onboarding ac54a47f3bc7e8ea0, orders aeff77359853a4eb2, legal a2e57622555213e27; builders inventory/counts a67098c5f6eaa4ba3, inventory/today a65d3dfe1fd7bdf43
VERIFY QUEUE: catalog_menu/recipes, sell/floor, catalog_offers/deals, team/employees
VERIFIED catalog_menu/pricing: NOT at parity (BLOCKER × writes hide instead of DELETE; 2 major toast-after-leave + 24px ×; 6 minor incl. split caches with items/studio) → builder a7c562965e2fa5be9 fixing
VERIFIED reports/operations: NOT at parity (BLOCKER sell vs reports table sittings disagree in assembled app → builder a0c000c4954af6bd4 authorised to add shared sittings to dashboard_api seed + sell floor_mock history; MAJOR customer/order panels cut-down → logged pending seam; 7 minor) → fixing
INTEGRATION TODO (+ops): core seam customerSheetLauncher/orderSheetLauncher wired by shell to sell's showCustomerSheet(readOnly)/showOrderSheet; reports ops (and any other read-only panels) use it
NOTE: overview mock sales handler ranks top items by revenue limit 10; backend ranks by qty limit 20 (reports' handler correct, wins in app) → fix overview mock in foundation sweep
BUILT catalog_menu/items (129/129, 217 tests; builder abaa32fbe66046da7) → sent back pre-verify: form seeds once (needs re-seed until edited) + hover prefetch via MouseRegion. Changed shared category_dialog.dart, new shared/menu_bilingual_field.dart. Items dialog reads studio's studioMenuItemProvider.
KIT TODO (+items): card grid hover hooks, width-based columns (3 vs web 4 at 1440), accent-insensitive search; segmented control with counts; bilingual field Enter-to-submit; image uploader drop + job polling; confirm Esc
DONE catalog_offers/combo_editor (all 9 fixed; 113 tests; package 517 pass) → COMMIT WITH catalog_offers AREA (combos verifying, deals queued; shared menu_options now autoDispose + compareNames). routes.dart also carries discounts prefetch (uncommitted)
VERIFYING catalog_menu/recipes (launched)
VERIFY QUEUE: sell/floor, catalog_offers/deals, team/employees
VERIFIED sell/customers: NOT at parity (2 major: edit form no re-seed, Arabic ledger amounts reversed; 6 minor) → builder a80e04876789fc438 fixing (incl. shared/sheets.dart onSwitchOrder)
STATUS 2026-10-09: done 9 (604 rows), built 13 (841 rows), building 10, not started 28; told owner ~35% overall, ETA 6–7 h
DONE catalog_menu/groups (fixed, 130 tests; groupMenuItemProvider → studio's studioMenuItemProvider) → COMMIT WITH catalog_menu AREA
LAUNCHED team/attendance builder (moves attendanceErrorText → team/shared)
BUILT reports/tills_report (24/24, 94 tests; builder ae384d379032e202a) → VERIFY QUEUED; divergence file written by me. Route caps removed (page gate words). Mock leak: reportBranchIds lets Dawam-only owner see Sabah (operations fixer is fixing area_seed)
OWNER: session limit near → STOP. No new launches, no SendMessage of findings; let running agents finish, record results only.

## RESTART STATE (2026-10-09, session limit; owner said stop after running agents finish)
Committed: discounts, payment_methods, ingredients, users, overview (c1e69923).
DONE, not yet committed (commit per area): sell tills + bookings; catalog_menu bases + groups; catalog_offers combo_editor.
Still running when stopped (their results may or may not have landed; check each unit's files and tests):
- builders: catalog_menu studio; reports financial, basira, staff_pool_bundles, loyalty_inventory_staff; inventory purchasing, counts, today; team team_setup, attendance
- fixers (verifier findings above): catalog_menu pricing, items (re-seed + hover prefetch); reports operations (shared sittings seed); sell customers
- verifiers: catalog_offers combos; admin onboarding; sell orders; reports legal; catalog_menu recipes
VERIFY QUEUE: sell floor, catalog_offers deals, team employees, reports tills_report, catalog_menu items (after its fix)
BUILD QUEUE: inventory waste, transfers, inv_settings | team schedule, payroll, rules, requests, shifts, team_board, approvals, team_reports | setup loyalty, integrations, qr, links, kitchen, staff_pool, delivery, brand_appearance, booking_settings, combo_settings, whatsapp | admin orgs, branches, devices, roles, review
AREA CHECKS: re-run verifier check 6 on discounts, payment_methods, users, ingredients, bases; sell: fold the 4 error-wording helpers into sell/shared; catalog_menu en/ar key count gap
BUILT reports/staff_pool_bundles (40/40, 139 tests; builder ad8a7e67dc30ab01a) → VERIFY QUEUED; divergence file written by me. Smoke test fails to compile on loyalty_inventory_staff WIP. OWNER Q: Arabic size names in reports?
INTEGRATION TODO (+spb): "open this order" hook in dashboard_core (reports can't depend on sell); same seam as operations

## PENDING FINDINGS (verified after the stop; send to a fixer on restart)
### catalog_offers/combos — NOT at parity (1 major, 3 minor), 56 rows verified, 101 tests pass
1. MAJOR (OFFR-CMB-011/030/032, OFFR-ALL-011): combo names cut on tablet/phone (web never wraps cells, table scrolls; phone card lets the badge drop under the name). Fix in combos_page.dart: (a) name column minWidth 240 → ~300; (b) ComboNameCell on phone: Wrap(spacing: Space.xs + DashMetrics.hair, crossAxisAlignment: center) instead of Row (keep Row on desktop, 56 px rows); (c) English name's MadarClippedText textDirection: ltr so the "…" lands after the text in Arabic.
2. minor (036): one frame of false "No combos yet" when an empty page past the end steps back (combos_page.dart:157-167, post-frame step). Compute steppingBack in build and pass loading: loading || steppingBack; test that the empty words never show after the refetch.
3. minor (OFFR-ALL-015): add a test: addCombos(s.db, 30), Next, emit resync, assert last query page=['2'] and "Page 2 of 2".
4. minor, CORE (OFFR-CMB-002): dashboard_core authz/gates.dart Restricted: frame the state as a card under the page title (web restricted.tsx:18-33 rounded-2xl border bg-card px-6 py-12) and use the page padding (32 not 24) → foundation sweep.
BUILT inventory/today (38/38 TOD + 14 INV-ALL, 127 tests; builder a65d3dfe1fd7bdf43) → VERIFY QUEUED. INV-TOD-030 needs a full submit test from Today once the waste unit lands (waste dialog + mock are placeholders). Today drives purchasing's PO/Receive dialogs.
KIT TODO (+tod): DashLedgerStrip 50 ms stagger; DashSectionHeader centre a 44 pt trailing control on the title
### sell/orders — NOT at parity (1 blocker, 3 major, 5 minor), 109 rows verified, 141 tests pass (builder a893d3c60342c7650)
1. BLOCKER (SELL-ORD-003, orders_page.dart:164-175, 300-303): filter changed then changed back restores the old page (`page = sig == _pageSig ? _page : 0`; _pageSig only set in onPageChanged). Fix: in build `if (sig != _pageSig) { _pageSig = sig; _page = 0; }`, page = _page; onPageChanged sets only _page. Extend the 003 test (orders_page_test.dart:157): page 2 → Completed → All statuses → expect page=1.
2. MAJOR (020/021, orders_page.dart:490-514): customer/teller/waiter names cut at every width; give those columns flex: 2 and minWidth ≈ Space.xxl*4.
3. MAJOR (038, order_sheet.dart:191): Void button must be red outline (web order-detail-sheet.tsx:163). Build a local outline-danger button (kit candidate DashButtonVariant.outlineDanger) and delete that divergence row.
4. MAJOR, KIT (012/013): DashLedgerStrip tile with a 44 pt action is ~24 px taller than the others; Arabic phone label cut "الأصناف الـ…". Kit: equal-height tiles, or overlay the action hit area → foundation sweep.
5. minor (076/089): export sheet's row estimate frozen at open (0 if opened during the first load). Pass OrdersKey and watch ordersListProvider(key).total.
6. minor (076/077, export_sheet.dart:368-389): on phone, the estimate goes above the actions, with Cancel and Export side by side (order-export-dialog.tsx:280-289).
7. minor, tests: 081 only checks the sheet opens; 010 must assert the export's till_id; 012 must assert the Items Sold figure and the red Voided tone; 016/017 must assert avg ticket and fees.
8. minor, mock void handler: add the teller limited grant (own sale within 10 min), the closed-shift 403 and the refund 409 (MadarRust orders/handlers.rs:3859-3912, 3961-4008), plus a test for the 409.
9. minor (052, order_sheet.dart:1325): Arabic phone "given free −30.00 ج.م" breaks; use   inside the money string.
### reports/legal — AT PARITY (4 minor), 38 rows, 139 tests (builder a65285a70e84810fd)
1. minor (024): Arabic detail line "Zamalek · 08 أكتوبر، 09:22 ص" splits the date around the Latin name. Wrap each part in U+2068…U+2069 in joinDetail (audit_cards.dart:195), log it, and add an Arabic test.
2. minor (037): log the owner question "modules read failed → bare header, no error/Retry" in reports-legal.md.
3. minor (001/ALL-002): pin the sidebar rule in legal_smoke_test.dart. The verifier's scratch test was copied to docs/fdash/pending/legal_nav_verify_test.dart; take its first case.
4. nit: legalExportLogo = finExportLogo = exportLogoUrl (bundles). Move one copy to reports/shared → area check.
### admin/onboarding — NOT at parity (1 blocker, 1 major, 4 minor), 31 rows, 103 tests (builder adb971684b0a754a8)
1. BLOCKER (024, onboarding_page.dart _finish 64-89): "Open my café" can leave the owner stuck on the celebration. onboardingCompletedProvider keeps the old completed:false while it reloads, so the router (router.dart:169 sendsToOnboardingProvider) bounces "/" back to /onboarding if the read takes over 1.8 s or fails; the overlay blocks Skip. Fix: right after completeOnboarding returns (before the mounted check), call container.read(onboardingSkippedProvider.notifier).skip(); keep the invalidate. Test: hold GET status after the finale, tap, pump 1.8 s, expect "/". Correct the "ADM-ONB-024 gate cache" divergence row (the web seeds the cache synchronously, onboarding-page.tsx:73-89). Probe: docs/fdash/pending/onb_probe_test.dart.
2. MAJOR (021/022, dialogs/menu_item_dialog.dart _seedFrom/_seeded): the item editor seeds sizes and add-ons once (the stale copy is saved by a replace-set). Re-seed _sizes and _allowed/_seededAllowed on each new item value until edited (web menu-item-dialog.tsx:170-186). Test: price 65→70 via invalidate shows 70, and an edit survives a second refresh. The same seed-once logic is in catalog_menu items/item_dialog.dart:150-193 (items fixer told) → the shared package takes the fixed version.
3. minor (020): the person-editor test proves nothing (onboarding_steps_test.dart:527-539). Assert users.newTitle, fill, save, and assert the POST /users body, the count line and the checklist re-read.
4. minor (018, dialogs/category_dialog.dart:117): clear _nameError in onEnChanged once the text is non-empty (react-hook-form re-validates on change).
5. minor (010, step_panel.dart:58): minHeight = 448, not 448 - 2*Space.xl.
6. minor, tests: 009 assert the done check and current marker; 012 assert multipart field `logo`; 023 hold POST complete and expect loading.
### catalog_menu/recipes — AT PARITY (2 minor + 1 question), 23 rows, 87 tests (builder a71f90c6a9c5659f9)
1. minor (005, recipe_builder.dart:540): the factor box should align to the start (number next to "×"); keep _endAlign for quantity.
2. minor (022, create_ingredient_dialog.dart:93-96, recipe_builder.dart:301-303): Esc mid-save loses the toast and the new row. Add an onCreated callback called before the mounted check; test Esc with the POST held.
3. OWNER Q (001): the builder re-seeds over edits when the saved rows change (= the web's form.reset). Apply "until edited" here? Log it as a question in catalog_menu-recipes.md.
BUILT team/team_setup (38/39 SET + ALL 003/004/009/022/008/010, 126 tests; builder ac4803b8e98685735) → VERIFY QUEUED. Missing TEAM-SET-038: step 3 "New shift" waits on the shifts unit's dialog (one line in openSetupNewShift, setup_dialogs.dart). Step 2 wired to employees' dialogs.
OWNER Q (set): "Use my location" needs a location package in the app (now it says it can't read it and the owner pastes a Maps link)
AREA CHECK team: merge ladder pricing (setup_rules.dart vs rules' tierPiastres); shared/setup_data.dart wrappers lack webCache (possible skeleton flash on remount)
KIT TODO (+set): time-range field + weekday picker; device location reader
BUILT catalog_menu/items: pre-verify fixes done (re-seed until edited in item/category/add-on dialogs; hover warm-ups for card + own pager's Next; 221 tests) → VERIFY QUEUED (builder abaa32fbe66046da7). Analyze warning in shared/unsaved_bar.dart:29 (unnecessary_null_comparison) → area check.
DONE sell/customers (all 8 fixed; 183 tests; floor+bookings 272 pass; shared/sheets.dart gained singleOrderSheet) → COMMIT WITH SELL AREA
DONE catalog_menu/pricing (all 9 fixed; 102 tests; reads via menuStudioProvider/branchAddonOverridesProvider/menuCatalogProvider; fixed shared/unsaved_bar.dart scroll jump) → COMMIT WITH catalog_menu AREA
OWNER Q (set): add geolocator to apps/dashboard for "Use my location" (asked 2026-10-09, unanswered)
USAGE LIMIT reached 2026-10-09 while ~12 agents still ran (studio, financial, basira, loyalty_inventory_staff, purchasing, counts, attendance; operations fixer). Check their files and tests on restart.
BUILT reports/basira (33/33, 110 tests; builder abf733af42d792efe) → VERIFY QUEUED. No webCache by design (web keeps Basira out of its query cache). OWNER Q: Basira heatmap mirrors in Arabic (as web); keep it LTR like the charts? KIT (+bas): start-side slide-over, round icon button, LTR charts with gaps, outline badge, DashSkeleton without a width draws nothing.
BUILT catalog_menu/studio (113/113 + AREA-014, 233 tests; builder a90734d072d2fd96f) → VERIFY QUEUED. Keep the names menuStudioProvider/studioMenuItemProvider (items and pricing import them). OWNER Q (studio): preset step note box pre-filled with the library note is saved as the drink's own; preview raw "one_size"; Options section has no permission check (the server refuses). OPEN: step animations fetched at animation_url through the API transport; check /static/step-animations/… in real mode. KIT (+studio): DashPageScaffold title slot, DashMenu submenus, outline badge with icon, dashed add button/box, check chip.
DONE reports/operations (all fixed except 9's literal ask: no persona lacks orders.read → needs a core persona; 186 tests; reports package 952 pass / 4 fail in loyalty_inventory_staff WIP). Shared sittings model in dashboard_api seed (MockSeed.sittings/sittingOf, seedFloorTables), read by sell floorTableHistory + reports; sell test/floor/floor_sittings_test.dart new. area_seed: bindReportDb + org-scoped reportBranchIds (404s). → COMMIT WITH reports AREA. A combined sell+reports mock test belongs in apps/dashboard/test (integration).
CORE TODO (+ops): a persona without orders.read for refusal tests
BUILT reports/financial (74/74, 186 tests; builder a6a03303837ce489b) → VERIFY QUEUED. CORE/API TODO: generated DecisionOut.impact must be nullable (backend sends null for decisions < 1 day old); financial works around it via the raw transport. Route caps removed (page gate words).
BUILT inventory/purchasing (73/73, 151 tests; builder a825f31bb69ed1efc) → VERIFY QUEUED. OWNER Q: the backend update keeps the old contact name/email/phone when cleared. AREA CHECK inventory: ingredients' dialog/drawer invalidate after the await (mid-save refresh bug likely). KIT (+pur): DashMenu must close before running its action (focus/Esc); DashDateField past-date warning border/icon.
BUILT reports/loyalty_inventory_staff (LOY 18 + INV 18 + STF 11 = 47/47, 157 tests; builder a57ad2839e3ff0715) → VERIFY QUEUED. Route caps removed on its 3 routes.
INTEGRATION TODO (+lis): low-stock + waste-report mocks registered by both reports and inventory (inventory wins in the app) → pick one owner. Zamalek waiters lack a department in reports' mock (team seed: Front of house). The Dawam refresh button + failed-refresh toast are duplicated (reports StaffRefreshButton vs team) → kit.
KIT (+lis): DashBarChart LTR + below-zero; percent bidi marks; DashProgressBar 8 px; DashBadge outline
BUILT team/attendance (39/39 ATT + 17 ALL, 107 tests; team 317 pass; builder a10e5eddbe46c41d5) → VERIFY QUEUED. attendanceErrorText moved to team/shared. GET /staff/attendance list now 400s without from/to (RANGE_REQUIRED).
BUILT inventory/counts (66/66, 141 tests; inventory ingredients+today+shared 283 pass; builder a67098c5f6eaa4ba3) → VERIFY QUEUED. OWNER Q: clearing a counted figure never un-counts it on the server (no API for it); Finalize uses the old figure while the screen shows "not counted".
ALL AGENTS FINISHED (2026-10-09). VERIFY QUEUE now: sell floor, catalog_offers deals, team employees, reports tills_report + staff_pool_bundles + basira + financial + loyalty_inventory_staff, inventory today + purchasing + counts, team team_setup + attendance, catalog_menu items + studio. PENDING FINDINGS to send: combos, orders, onboarding (+ legal, recipes minors).

## RESUMED 2026-10-09 (owner: keep working; Dawam manager views → decide at the end)
OWNER DISCUSSION: owner proposes scrubbing manager views from Dawam (employee-only app); managers use the Flutter dashboard. Recommended: don't share Dawam's manager tabs with the dashboard; build the team pages once in the dashboard; later add push to the dashboard app + "Manage team" link in Dawam, then remove Dawam's manager tabs (≈4.8k lines) and update the Dawam spec. Decide at the end: are two apps OK for managers? Is approvals push required before the scrub?
CACHE/PREFETCH CHECK: every web route-prefetch case for a built page is wired; missing ones are unbuilt pages (waste, transfers, inv settings, roles) or legacy redirect paths.
FIXERS (resumed): orders a893d3c60342c7650, combos ab9da2fe42fb6571f, onboarding adb971684b0a754a8, legal a65285a70e84810fd, recipes a71f90c6a9c5659f9
VERIFIERS: floor aa9347a7b59f16077, deals ae26abcb06386306b, employees aa6abb78cc9188c7e, items a93a75f5d88fff75f, studio a8caa49261b574462, tills_report a09d328db12a24ed6, financial a3e4e8e676a5ebd23, purchasing adbceebc0f1dea545
BUILDERS: inventory/waste a8d1af95ef7515b9f, team/shifts ad78b46a999c25c38 (wires team_setup 038), team/schedule a45c7f4e3907a2ef3, admin/roles a4189ea820fe16309, setup/loyalty ad7c3ccfb911861a8, setup/kitchen a309db26dd87e1b85, setup/delivery a527e7b29d483dcc8
VERIFY QUEUE: staff_pool_bundles, basira, loyalty_inventory_staff, today, counts, team_setup, attendance
BUILD QUEUE: inventory transfers, inv_settings | team payroll, rules, requests, team_board, approvals, team_reports | setup integrations, qr, links, staff_pool, brand_appearance, booking_settings, combo_settings, whatsapp | admin orgs, branches, devices, review
DONE reports/legal (minors fixed; 141 tests) → COMMIT WITH reports AREA
OWNER REQUEST 2026-10-09 (beyond parity): (1) hover prefetch must really work in the app (owner: Orders hover doesn't prefetch); (2) pull-to-refresh on every page (+Cmd/Ctrl+R) that refetches active reads live; (3) offline: persist GET responses per user+org, show them after a cold restart while offline with a banner "offline, saved at …, may be outdated"; online never serves saved data; wipe on sign-out; offline writes fail clearly (no queue); (4) smart range inference: derive a sub-range from a cached superset only where exact (per-day breakdowns or full row lists); online only from a fresh (<30 s) superset; offline from any saved one; exactness tests vs the mock server.
LAUNCHED foundation A (prefetch audit in the assembled app + pull-to-refresh) ae99850c4d0b4fccc. Foundation B (offline persistence + range inference) launches at the next free slot.
OWNER CLARIFIED (hover): every control whose press triggers a READ warms it on intent (mouse dwell ~80–100 ms, keyboard focus, touch-down): table rows → detail by id, pagination → page n±1, card grids, tabs, menu items, buttons that open dialogs which read. Never warm writes. Foundation A ae99850c4d0b4fccc does the kit hooks FIRST (DashIntent + DashDataTable row intent, pager page intent, card grid, tabs, DashMenu, DashButton/DashPressable onIntent) + the Orders example, then messages me the API → then: tell running builders, update the briefs, and run an INTENT SWEEP per area over all built units (one agent per area).
DONE admin/onboarding (all 6 fixed incl. blocker; 108 tests). LAUNCHED foundation B (offline persistence + range inference).
DONE catalog_menu/recipes (minors fixed; 88 tests) → commit with catalog_menu area. LAUNCHED team/payroll builder.
DONE catalog_offers/combos (fixed; 105 tests; package 521 pass) → commit with catalog_offers area (deals verifying)
DONE sell/orders (fixed incl. blocker; 143 tests). FOLLOW-UP (sell area check): at 1440 the table now scrolls sideways and Total starts off screen after name columns got minWidth. Tune the column widths so 1440 fits like the web's content-sized columns. CORE TODO: a teller persona holding orders.void (for the void limit and closed-shift tests).
LAUNCHED team/approvals builder
STATUS 16:51: done 18 units (1,102 rows), built awaiting verify/fix 15 (966 rows), building 9, not started 18; built rows 2,068/3,018 = 68%, verified 37%; told owner ~45% overall, ETA 5–6 h
VERIFIED reports/tills_report: AT PARITY (4 minor + nit) → builder ae384d379032e202a fixing (incl. shared area_seed reportBranchIds check order)
VERIFIED reports/financial: NOT at parity (BLOCKER margin-target form seeds once; MAJOR 1024 tablet pair stacks; 5 minor) → builder a6a03303837ce489b fixing
VERIFIED team/employees: NOT at parity (4 major: cut headers/cells, profile no re-seed, preset WhatsApp not filled, hire date can't clear; 4 minor) → builder a02e0cdaab820d395 fixing
DONE reports/tills_report (minors fixed; 100 tests; reports package 1030 pass; I updated ops_mock_test for the backend's 403 on another org's branch)
CORE FIX (me): branchesProvider watches realtimeEpochProvider('/branches') (deals verifier finding 1). webCache({staleTime}) option added. NEW dashboard_core DashAsyncState: awaitingFirst / failedFirst (handles Riverpod's automatic `retrying`); inventory shared InventoryAsyncX fixed (purchasing BLOCKER), inventory 547 pass. ~30 other sites hand-write `isLoading && !hasValue && !hasError` (error shown during auto-retry) → each area's INTENT SWEEP agent also replaces them with awaitingFirst/failedFirst. Briefs updated.
VERIFIED catalog_offers/deals: unit at parity; core gap fixed by me; minors 2–6 → builder ad88390951806ea2c
VERIFIED inventory/purchasing: BLOCKER fixed in shared by me; minor 2 (PO dialog estimates re-fill) + retry tests per table → builder a825f31bb69ed1efc
VERIFIED catalog_menu/items: NOT at parity (2 major: Arabic add-on search; failed add-on recipe read shown as empty and saved over; 7 minor) → builder abaa32fbe66046da7
VERIFIED catalog_menu/studio: NOT at parity (1 major: (EGP) + raw units in Arabic; 7 minor); the 3 owner Qs confirmed as real web behaviour → builder a90734d072d2fd96f fixing
INTENT HOOKS LANDED (foundation A): DashIntent (90 ms dwell, focus, touch-down); onIntent on DashPressable/DashButton/DashIconButton/DashCard/DashListRow/DashStatCard/DashMenuItem; DashDataTable onRowIntent + onPageIntent; DashPagination onIntent; DashEditableCardGrid onItemIntent/onPageIntent; tab strips/segments onIntent; DashSelect/DashFilterSelect/DashOptionList onOptionIntent; core ref.warm(provider) + ref.prefetchRoute('/path'); bottom bar warms. Orders rows + pager wired (example). Briefs updated by A. → told running builders/fixers; INTENT SWEEP queued per area for built units (+ replace hand-written loading checks with awaitingFirst/failedFirst).
VERIFIED reports/staff_pool_bundles: NOT at parity (BLOCKER route caps left on → shell gate words + blank while loading; 2 minor) → builder ad8a7e67dc30ab01a fixing + intent wiring
ECONNRESET wave: 8 resumed old agents dropped (financial, employees, deals, items, purchasing, studio, staff_pool_bundles fixers + basira verifier). LESSON: resuming agents with huge transcripts is fragile → findings now go to docs/fdash/pending/<area>-<unit>.md and FRESH fixer agents read them.
FRESH FIXERS: financial aaa6b33c3b4172592, employees a427b50e730b3e595, deals a9a01d5aab2eb6667, items af1e6935db10371a6, purchasing a23bad1a6d522a21e, studio a9d53b99568a9b883, staff_pool_bundles a26edd5c6c5acb389; basira verifier relaunched a76460dc8e40e7d6f
DONE inventory/purchasing (fixed; 162 tests; purchasing+today 289 pass). For Today: "Arriving → Receive" should warm purchaseOrderProvider(po.id) on intent (Today's files; intent sweep).
DONE reports/financial (fixed; 199 tests; per-field re-seed). Touched shared reports inventory_scope.dart (optional intent param). KIT: FinReveal = HomeReveal → kit.
API OUTAGE 2026-10-09 evening: every running agent died (ECONNRESET / no response / 408). Relaunching at ~10 concurrent.
RELAUNCHED at 10 concurrent (fresh agents reading docs/fdash/pending/*.md):
 foundation offline a483085bb01499d9d, foundation refresh+audit a3a300f7e96075222,
 fixers employees ad6657073a978f2c5, deals ae30201f4e5df75f3, items afa4868193fba63f2, studio ad06cfbb5f1f6a8f4, staff_pool_bundles a2d76fbaa8eaa5d71,
 builders waste a213c797b942feb0a, kitchen add3ca1f95d8ab332, schedule a9cc73a1627b54f15
WAITING (partial work on disk, relaunch as slots free): builders shifts, payroll, approvals, roles, loyalty, delivery; verifiers floor, basira
VERIFY QUEUE: loyalty_inventory_staff, today, counts, team_setup, attendance (+ re-verify units after fixes where blockers were fixed)
BUILD QUEUE (18): inventory transfers, inv_settings | team rules, requests, team_board, team_reports | setup integrations, qr, links, staff_pool, brand_appearance, booking_settings, combo_settings, whatsapp | admin orgs, branches, devices, review
INTENT SWEEP queued per area for units built before the hooks.
DONE catalog_offers/deals (fixed; 169 tests; package 527 pass) → catalog_offers area complete (discounts, combos, combo_editor, deals)
OWNER 18:42: merging some dashboard PRs; will say when done → then diff MadarDashboard (and madar main) from the parity baseline, re-inventory changed pages, and route updates to the affected units.
OWNER: the PRs are in the React dashboard, the backend, madar-shared and the monorepo (they don't touch the Flutter dashboard). AFTER-MERGE CHECKLIST: (1) diff MadarDashboard 93246e45..main → changed pages → re-inventory + route to units; (2) backend openapi.json diff → regenerate dashboard_api (tool/gen_dashboard_api.py) + update mocks for changed endpoints; (3) madar main → merge into feat/fdash-parity-2 (merge commit), rebuild/check rust_bridge_dashboard if rust-core/madar-shared changed the FRB surface; run all package tests.
OWNER 18:48: let the current agents finish (resume them on API errors so they finish), launch NOTHING new, commit, then WAIT for the owner's merges before continuing.
BUILT inventory/waste (31/31, 86 tests; today+ingredients 256 pass) → VERIFY QUEUED. OWNER Qs in inventory-waste.md (scope kept, Restricted, search columns).
DONE reports/staff_pool_bundles (fixed incl. blocker; 147 tests). NOTE: REP-ALL-018 says a failed refresh replaces shown rows with the error (web) → reports units use a local 'failed' getter, not failedFirst; reconcile at the reports area check.
DONE foundation A (prefetch audit + pull-to-refresh): audit test apps/dashboard/test/prefetch_audit_test.dart (sidebar + palette + in-page links, 3 personas): every web-prefetched page opens with no second request; NO shared root cause (owner's Orders-hover report was about row-level intent, now handled). Shared: logo + not-found "Back home" warm home. Refresh: QueryCache.refetchActive(); DashPageScaffold pull-to-refresh (header refresh button for fillBody pages); shell Cmd/Ctrl+R; failure toast; core 158, kit 143, app refresh 6 + audit pass.
INTENT SWEEP ITEMS (from audit): setup brand_appearance/settings_shell.dart: rail onIntent → ref.prefetchRoute(i.to) (~156) + phone DashSelect onOptionIntent (~104), then remove it from awaitingUnitWiring in the audit test; inventory routes: prefetch for /inventory/transfers + /inventory/settings when built; in-page links needing onIntent → ref.prefetchRoute: overview home_kpis.dart:149 (/tills), inventory today_parts.dart:179 (/inventory/counts) + :353 (/inventory/ingredients), counts/count_editor.dart:464 (/inventory/ingredients), studio/menu_studio_page.dart:612 (/menu/pricing), combo_editor_page.dart:556 (/menu/pricing), team_setup/setup_branches_step.dart:70 (/branches).
RISK (A): pages that show their error whenever hasError (orders, users, branches, discounts…) swap the table for the error on a failed manual refresh → the sweep must move them to failedFirst; verify forms with unsaved edits survive a pull (re-seed-until-edited rule covers it).
DONE catalog_menu/items (fixed; 231 tests). KIT FIX (me): DashIntent Focus includeSemantics:false (merged labels in focused cards). KIT TODO: DashMenu closes before running onSelected (Esc lost on dialogs opened from ⋯ menus); grid add-button onAddIntent; DashSelectField.onOptionIntent; Back intent on DashPageScaffold; DashSurface footer slots; DashBadge outline. CHECK: items Arabic dark shot shows Active switches as off.
DONE catalog_menu/studio (fixed; 247 tests). Gaps: Deducts select fixed 224 (web flex-1); processing image job not polled (pre-existing).
DONE team/employees (fixed; 429 team tests, 1 failing in team_setup TEAM-SET-005 429 toast → investigate). DONE setup/kitchen built (45/45, 104 tests) → VERIFY QUEUED.
FOLLOW-UP: team_setup TEAM-SET-005 (429 refresh toast) fails since the employees fix/shifts work; re-run after the shifts+schedule builders finish; check refresh_toast.dart vs retrying + whether setup-refresh still refetches /staff/work-shifts.
BUILT team/shifts (33/33 SHF, 111 tests; set-up step 3 wired) → VERIFY QUEUED. FIXED (me): TEAM-SET-005 test expected the server's 429 words; the shared refresh toast uses errors.tooManyRequests (TEAM-ALL-014) → test updated; team_setup 126 pass.
