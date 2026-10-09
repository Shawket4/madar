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
## links (setup) — the major (placeholder direction) is a kit fix in kit batch 1
8 (LNK-012/013): add overflow: TextOverflow.ellipsis to the row title and subtitle MadarClippedText calls (links_page.dart:547,554).
9 (LNK-026): edits typed during a save are wiped (links_page.dart:233). Keep an edit counter, note it before the request, and reset _edited only if no edit happened since.
10 (LNK-010/016): the length limits count characters, but the web and backend count code units; Arabic with diacritics passes 160 then gets refused. Add an input formatter limiting code units (links_page.dart:426,437,495,503).
11 (LNK-023): links_preview.dart:85 error branch → q.failedFirst.
12 tests: a saved body with a hidden branch and a filled Maps link (019/021); a new link going out with visible: true and a client id (017); refresh after close; "SET-LNK-007" in the intent test name; use h.refusalWords instead of the hand-copied "Bad request: …".
13 shots: the new-link screenshot must scroll to the new row.
14 (LNK-021 question): saving also writes the org's social links. Also invalidate /orgs/{id} after a save (the Brand page's read) and give me a divergence row.
