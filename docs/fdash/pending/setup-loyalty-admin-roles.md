# setup/loyalty (NOT at parity) + admin/roles (AT PARITY, minors)
## loyalty (packages/dashboard_features/setup/lib/src/loyalty/)
1 MAJOR (LOY-069/070): the adjust-balance branch list offers warehouses. member_sheet.dart:265-269 uses `if (b.isActive) b`; the web (member-section.tsx:81) filters `b.is_active && isSelling(b)`. Use isSelling (dashboard_core scope.dart:128). Test with an active warehouse branch: it is not listed and doesn't count toward "more than one branch". The SELL copy has the same gap at sell/lib/src/customers/member_section.dart:58: fix it there too (one-line change; re-read first; run sell test/customers).
3 MAJOR (intent): the Rewards tab press makes an unwarmed GET /loyalty/earning-items. loyalty_page.dart:46-50 must also warm earningItemsProvider(branchId) when the cached settings are in 'visits' mode. Make loyalty_intent_test.dart:36-62 count that request (one before, none after the press).
4 minor (LOY-060): members_pane.dart:120's hand-written loading check → list.awaitingFirst && _previous == null.
5 minor (LOY-058): "Load more" can't warm (kit DashLoadMore has no onIntent): keep it logged as a kit gap.
(Finding 2, the member row opening the real customer sheet, is done by the integration agent through a core seam; don't change members_pane.dart _open or member_sheet's order link.)
## roles (packages/dashboard_features/admin/lib/src/roles/)
R1 minor (ROL-016): the limits popover (admin/lib/src/shared/limits_button.dart:108-116, shared with users ADM-USR-048) takes its values once. Add didUpdateWidget so that while it is open and untouched, a changed widget.value re-seeds the draft and "own". Add a test; run test/users too.
R2 minor (ROL-003 phone): below 760 px, scroll the role header into view after selecting (Scrollable.ensureVisible in roles_page.dart _select).
