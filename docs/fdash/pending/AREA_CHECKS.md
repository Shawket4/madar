# Area checks (one agent per area). Do ALL of "Every area", then your area's list.

## Every area
1. Run the WHOLE package's tests and `--analyze` on lib + test. Fix every failure/issue in your area. A failure caused by another area or a shared package: report it, don't edit their files.
2. Move local copies onto the kit APIs added in kit batch 1 (see `git log -p --follow packages/dashboard_kit` or the kit tests):
   - DashButtonVariant.outlineDanger;
   - DashBadge(outline: true);
   - DashStatusPill(wrap: true);
   - DashDataTable.retrying (pass retrying: q.isLoading wherever the table shows an error with Retry);
   - DashNumberField/DashNumberInput.onSubmitted (Enter submits where the web's form does);
   - DashStatCard.action in DashLedgerStrip (remove any SizedBox(height: 44) spacer hack);
   - DashLoadMore.onIntent, DashDateField.onIntent, DashDateRangeField.onQuickIntent, DashSelectField.onOptionIntent, DashPageHeader.onBackIntent and DashEditableCardGrid.onAddIntent (wire the reads they warm);
   - dashTextDirectionOf for custom free-text cells.
   Delete the local copies, update tests, and delete or reword the divergence rows that cited these kit gaps (give the row edits in your final reply; .md writes may be refused).
3. Export logo: the web uses brand.logoUrl?.trim(), blank → no logo (use-brand.ts:111). Check every export in your area.
4. `dart format` every Dart file in your package (CI runs `dart format --set-exit-if-changed` on the whole tree). Formatting only; re-run the tests after.
5. The divergence files for your area: every row has Web | Flutter | Why filled, no stale rows (kit fixes, web fixes since baseline), and no duplicates.

## sell
- Fold the four copies of the error-wording helper (orders/error_text.dart and the others) into sell/lib/src/shared/, and update imports (floor, bookings, customers, orders, tills).
- Orders table at 1440: the name columns' minWidth made Total start off screen. Tune the widths so 1440 fits like the web's content-sized columns, and check 1024 keeps the row actions on screen.
- The duplicated delivery-channels block (orders vs overview) and the excluded-items provider (orders vs reports operations, key madar.excluded-line-items.<orgId>): move both to dashboard_core (you're authorised to add core files for these two only), and switch sell, overview and reports to import them. Coordinate: re-read the reports and overview files right before editing, and only change their imports and usages.
## catalog_menu
- Fix MENU-ITEMS-083 (upload error text: "Bad request: …" not shown, probably the kit's describeError path; make the items upload error type extend ApiException as onboarding and orgs did).
- The catalog_menu merged en.json has 11 keys vs ar.json 23: find missing English or Arabic words and fill them.
- Items Arabic dark screenshot: the Active switches read as off; check the cause (DashSwitch dark fix landed) and fix if wrong.
- shared/unsaved_bar.dart analyze warning (if still present).
## catalog_offers
- OFFR-ALL-018: the shared gate is blank while permissions load; match the brief (skeleton, no blank).
- offersCategoriesProvider vs comboCategoriesProvider: one provider for /categories.
## reports
- One export logo helper in reports/shared (legalExportLogo = finExportLogo = exportLogoUrl).
- The REP-ALL-018 rule: on the web a failed refresh replaces shown rows with the error. Make the reports units consistent (one shared getter in reports/shared, used everywhere), and log it once.
- Flaky in parallel runs: REP-LEG-018 ×2, REP-OPS-047/048, REP-OPS-049/050 (a failed read requested once more). Find the race (likely warm vs failure) and make them deterministic.
- Low-stock + waste-report mocks are registered by both reports and inventory: reports registers only if absent (inventory owns them), so figures agree in the app. Zamalek waiters' department matches the team seed (Front of house).
## inventory
- Any helpers still imported from another unit (e.g. purchasing PoNumberInput used by waste/transfers) → lib/src/shared/.
- Transfers isStaleTransferRefusal: keep it local unless sell/team have the same; note it as a core candidate.
- The INV-TOD-032 divergence (KPIs 2×2 at 1024) is obsolete (the kit now counts by window width): remove it and assert 4 across.
## team
- Merge the ladder pricing (team_setup setup_rules.dart vs rules tierPiastres) into one team/shared helper with vector or unit tests.
- shared/setup_data.dart wrappers: ensure webCache semantics (no skeleton flash on remount).
- Approvals' own review-advance/reject dialogs duplicate payroll's money_dialogs: share one.
- staff_query.dart failedEmpty → the core failedFirst everywhere; delete the copy.
- Requests: remove the 1440×1400 window workaround in test/requests/requests_dialogs_test.dart:395-398 (the kit popover now flips/caps).
- NightRangeField (rules) and ShiftTimeRange (shifts): one shared time-range field in team/shared.
## setup
- QrImage duplicates shared/qr_preview_dialog.dart's image code: one copy.
- The sticky side column is duplicated (settings shell + links): one shared copy in setup/shared.
- Two booking_settings seeds (setup vs sell): make setup's seed match sell's rows when sell isn't loaded (same ids and values), so the app and the unit tests agree.
## admin
- orgs/org_errors.dart is imported by devices, review, branches and branch_setup: move it to admin/lib/src/shared/.
- Two POST /devices/activation-codes mock handlers (devices + branch_setup): keep one (devices owns it; branch_setup registers only if absent), with identical behaviour.
- Delete the unused admin/lib/src/users/make_employee.dart.
- Linkable accounts: admin users and team employees each have a provider for /staff/employees/linkable. Admin should reuse team's through the AddEmployeeOpener warm, or log it.
## overview
- The OVW-HOME-044 divergence (KPIs at 1024) is obsolete: remove it.
- The delivery-channels block is moving to dashboard_core (the sell agent does it); just switch the import when it lands, if it's not done by the time you finish.
