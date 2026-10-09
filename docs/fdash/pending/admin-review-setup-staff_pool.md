# admin/review + setup/staff_pool: both AT PARITY, minors
## review (admin)
1 (REV-001 intent): give /access/review a prefetch: (warm, s) => warm(reviewFlagsProvider(false)) in admin routes.dart (that entry only), so resting on the Access "Review" tab warms it. Add a rest-press test.
2 (REV-009): long raw capability keys cut to one line; allow 2 lines or more flex (review_page.dart:317-323).
3 nit: _ReasonPill icon size 12 → an IconSize token (review_page.dart:396).
## staff_pool (setup)
4 (SPL-011): the phone picker sheet keeps a stale onChanged closure; use onChanged: (ids) => _edit(_form!.copyWith(itemIds: ids)) (staff_pool_settings_page.dart:268, eligible_items_control.dart:71-80).
5 (SPL-011): eligible_items_control.dart:282: hand-written q?.isLoading → q?.awaitingFirst ?? false.
6 (intent): give /settings/staff-pool a prefetch warming the settings read for the scope, only for a person with the org.settings caps (setup routes.dart, that entry only), plus a hover test.
7 nit: maxHeight: 420 → a named constant (eligible_items_control.dart:120).
