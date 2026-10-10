# Core batch 2 (packages/dashboard_core, plus switching each area's callers)

All eight area checks are done, so you may edit any area package to switch its callers. Re-read a file right before you edit it, because the kit batch 2 agent may still be working in packages/dashboard_kit; don't edit the kit. Keep core APIs small and documented the way the surrounding core code is. Every item gets a core test. After you switch the callers in an area, run that area's whole package.

1. **Date months:** the shared date format prints "Sept" (Dart intl CLDR) where the web's Intl prints "Sep". Normalise it in core format. Check every month and both languages against the web vectors (`packages/dashboard_core/test/vectors/`).
2. **One `exportLogoUrl(brand)` in core:** the shop's own logo only with custom branding, trimmed, and blank gives no logo (web use-brand.ts:111). Delete the copies and switch the callers:
   - admin `shared/export_logo.dart`;
   - setup `shared/export_logo.dart` (`exportLogoUrl`);
   - sell `shared/export_logo.dart` (`exportLogoOf`: note it falls back to Madar's logo without branding, so check against the web which one is right);
   - team `shared/export_logo.dart` (`teamExportLogo`);
   - inventory `inventoryExportLogo`;
   - reports `shared/report_rules.dart` (`exportLogoUrl`);
   - catalog_menu `items_export.dart` (inline).
3. **One `isStaleRefusal(error)` in core,** with the web's full code list. Switch team `team_util.dart` (`isStaleRefusal`) and inventory transfers (`isStaleTransferRefusal`) to it.
4. **One provider for `GET /staff/employees/linkable`** in core, used by admin users (`users_data.dart`) and team employees, so opening Make employee from Users costs no extra read. Wire the `AddEmployeeOpener` warm onto it. Remove the matching admin-users.md divergence (ADM-USR-014 "one more read").
5. **`branchesProvider`** gets `ref.webCache()` (fetch time plus stale refetch on mount), as `orgsProvider` has. Careful: the shell redirects read it, so check that sign-in and the org switch still route correctly. Run apps/dashboard.
6. **Navigation guard hook:** a page can register "leave?" for sidebar, palette, header and back navigation (web: useBlocker or the unsaved-changes prompt). Use it for admin branch_setup's leave guard, which today can't stop sidebar, palette or header navigation (see admin-branch_setup.md).
7. **Page-registered refresh** (DashPageRefresh or similar): a page with no webCache reads, such as Basira, registers its own refresh, so the header refresh and Cmd/Ctrl+R reach it. Wire Basira (reports `basira`) and check pending/reports-basira.md item 2.
8. **Test personas in the shared seed/harness:**
   - a teller holding `orders.void` (sell void limit, closed-shift tests);
   - a persona without `orders.read` (reports operations refusal test REP-OPS-…, see LEDGER line ~201).
   Add them, then write the two tests that were waiting on them.
9. **Staff-drink sales in the shared seed:** in the assembled app, "View order" on a staff drink 404s because the seed has no such order. Add them to the shared seed (dashboard_api mock seed) so reports staff_pool and sell agree.
10. **Mock refusal wording** (LEDGER line 25): the mocks word refusals as core's answer_words does: strip the kind prefix, words for an uncoded 403/429, Arabic never gets the server's English, and coded refusals map to errors.codes.*. Do it through one transport wrapper in the harness and the mock boot. Update `h.refusalWords` and the hard-coded raw strings in tests. This is big: if the time is short, do the wrapper plus one area, and list what's left.
11. **`apiWithHeaders`** (sell customers_data): move it to core if another area needs it; otherwise leave it and say so.
12. **`InventoryAsyncX.firstLoad`** (inventory `shared/inventory_data.dart`) duplicates core `awaitingFirst`: switch it and delete the copy.
13. **One onboarding read** shared by the shell's `onboardingCompletedProvider` and the overview home card (2 requests → 1).
14. **Print gateway:** setup qr prints through the `printing` package directly. Add a small core print seam only if a second caller exists; otherwise leave it and say so.

Final reply:
- per item: done, skipped or partial, and why;
- the test counts per package you ran;
- the divergence row edits.
