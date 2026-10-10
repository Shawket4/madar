# inventory/inv_settings (AT PARITY, minors) + team/requests (1 major via kit; minors)
## inv_settings (packages/dashboard_features/inventory/lib/src/inv_settings/)
1 (SET-010): make the word "Packaging" tappable (calls _setPackaging(orgId, cat, !cat.isPackaging) when canAdjust), keep ExcludeSemantics, delete that divergence row (reply), and add a test (inventory_settings_page.dart:523-538).
2 (SET-009): the name tie-break is case-sensitive (:43). Compare toLowerCase(), and add a mixed-case test.
3 (SET-009/014): add the Arabic plural forms (_one/_two/_few/_many/_other) to assets/i18n/inv_settings.ar.json for the ingredient counts. Also fix inv_settings.en.json: two _one plural keys are reportedly missing and fail an inventory shared test. Run test/shared too.
4 (SET-006 test): assert the exact "0 % or more" and "… is not a number" texts (inv_settings_page_test.dart:155-179).
5 (SET-015 test): pick the reassign target by tapping the field and the option, not onChanged (inv_settings_categories_test.dart:304-311).
6 (SET-012/014): DeleteCategoryDialog looks up the live category by id (fallback widget.category), so a refreshed ingredient_count shows the picker.
## requests (packages/dashboard_features/team/lib/src/requests/ and the shared lib/src/approvals/approvals_dialogs.dart)
(The major, the date popover overflowing, is a kit fix in progress; when it lands, remove the 1440×1400 window from test/requests/requests_dialogs_test.dart:395-398. Not yours now.)
2 (REQ-018): log (reply) that a reject re-reads /staff (the web leaves the request listed as pending), and assert gets(h) == lists + 1 in the 018 test.
3 (REQ-020): give showApproveWithPayDialog a source provider; Requests passes its own list read, and _approveIntent returns null for pay kinds (no GET status=pending on other filters).
4 (REQ-024 race): in confirmMissionOverPunches return false when unmounted, before the empty check; add `if (!mounted) return;` after that await in _approve.
5 (REQ-024 tests): seed fixed attendance and assert the warning (requests_page_test.dart:670-686); add a test where GET /staff/attendance 500s and expects a direct PATCH.
6: tests: hold the PATCH, close the dialog, release → one more list GET; paid_default changes and refresh → the switch follows until touched.
7: intent tests for "Show what's pending" and a pay kind's Approve on a non-default filter; assert exactly 1 for New request.
8 (REQ-020): the pay dialog width is 448 (RequestsMetrics.dialog), not 512.
9: the reject and cancel tests assert the PATCH path /staff/requests/<id>/decision.
Run test/requests, test/approvals and test/inv_settings, plus inventory test/shared.
