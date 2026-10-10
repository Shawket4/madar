# Owner fixes (2026-10-10): the answers to the parity program's open questions

The divergence rows named here live in `/Users/shawket/Desktop/Madar/wt-fdash-pos/docs/fdash/divergences/`. Read each one before starting its item. Every fix lands in the BACKEND (MadarRust), the WEB dashboard (MadarDashboard) and, later, the Flutter dashboard (madar). Flutter waits until another session's work merges; it is not part of this round.

## Rules for every repo
- **Deployed clients never break** (non-negotiable). The released POS and Dawam builds keep working. Check every backend change against the released client tags in `/Users/shawket/Desktop/Madar/madar` (`git tag`; the latest POS 0.13.x and Dawam tags) and the generated `madar-api` client there. Prefer additive changes: new fields or endpoints, looser permissions. If a change could break a deployed client, don't make it; say why in your reply.
- Tests at every layer. Backend: typed Rust tests, using throwaway Postgres clusters as described in MadarRust/CLAUDE.md. Never use :5432 beyond read-only. Web: vitest and the repo's lint.
- Never push or open PRs. Commit on your branch in your worktree, with clear commit messages ending in the Co-Authored-By line from your instructions. Never git stash. Never touch production.
- Arabic is first-class: every new string gets EN and AR.

## Backend (MadarRust)
- **B1** Supplier update (`inventory-purchasing.md`, "the backend update keeps the old contact name/email/phone when cleared"): a cleared field must clear. Make an explicit empty value or null clear it, while an absent field still means "leave as is", so older clients keep their behaviour.
- **B2** Stock count un-count (`inventory-counts.md`): clearing a counted figure must un-count it on the server. Add an endpoint or field to remove a line's counted figure. Finalize must then treat that line as not counted.
- **B3** Brand links (`setup-brand_appearance.md` SET-BRD-017): `PATCH /orgs/{id}` is super-admin only, so a shop owner's links save is refused. Let a shop owner, through the right capability (check the authz registry in madar-shared), save the brand/links fields of THEIR OWN org. Every other org field stays super-admin only.
- **B4** Staff-pool settings (`setup-staff_pool.md`): `GET` staff-pool settings for a branch returns the org's row labelled with the branch id. The client then can't tell "follows the organisation" from a branch override. Add an additive field such as `inherited: bool`, or a source field, to the response.
- **B5** Combo settings (`setup-combo_settings.md`): the page opens for `menu.combos.edit` alone, but the backend read needs `org.settings.read`. Let the combo settings read accept `menu.combos.edit` (or the cap the web page gates on).
- **B6** Over-receive (`inventory-transfers.md`): the doc says 409 OVER_RECEIVE_NEEDS_NOTE, but the backend returns 400. Return 409 with that code IF no deployed client depends on 400; otherwise fix the doc and say so.
- Then regenerate `openapi.json` (`cargo run --bin export-openapi`) and commit it.

## Web (MadarDashboard)
- **W1** In-page table filters trim the search (the kit DataTable, Discounts, and any other in-page filter), as the server searches already do. Owner: keep trimming and extend it to the web.
- **W2** Swap groups' effect badge is highlighted again (`catalog_menu-groups.md` MENU-GRP-008; the 13 Sep design-system change made the `default` badge look like `secondary`). Owner: keep the highlight and bring it back on the web.
- **W3** Seats field (`sell-floor.md`): it silently ignores whole numbers outside 0–99. Show an error message (EN/AR) instead.
- **W4** Loyalty (`setup-loyalty.md` SET-LOY-083): an invalid value in a hidden field blocks Save. Validate only the visible fields, or reveal and focus the invalid one; follow the row's hint.
- **W5** Payment methods (`setup-payment_methods.md` SET-PAY-039): the tellers/devices panel says "No tellers…" while loading or after a failed load. Show loading and error states instead.
- **W6** Team reports (`team-team_reports.md`): a failed report's cards read 0 beside the error. Show '—', as Attendance does.
- **W7** Basira heatmap (`reports-basira.md`): it is mirrored in Arabic. Keep it left to right, like the charts.
- **W8** Studio (`catalog_menu-studio.md` MENU-STUDIO-065/067/018 and the Options row):
  - Don't seed a preset step's note box with the library note. Show the library note as a placeholder or hint, so saving doesn't copy it as the drink's own note.
  - The preview shows the raw "one_size": show nothing, or the right word.
  - Gate the Options section on its capability.
- **W9** (after the backend lands; the orchestrator will tell you) Consume B1, B2, B4 and B6 in the web: regenerate the Orval client from the backend worktree's openapi.json.
- Each fix gets a vitest test where the repo has them for that page. Run `npm run lint`, `npm run test` and `npm run build`.

## Backend DONE (wt-owner-api fix/owner-answers; commits 2bea132..36c6bcf; openapi regenerated)
The wire contract the clients consume:
- **B1** `PATCH /purchasing/suppliers/{id}`: an absent field is left as is; null or blank clears it; values are stored trimmed.
- **B2** `PUT /stocktakes/{id}/items`: `counted_qty` is required and nullable. Null un-counts the line (clears the count, variance_reason and counted_by); finalize skips it.
- **B3** `PATCH /orgs/{id}`: a body with only `social_links` and/or `logo_url: null` needs org.settings.edit in the caller's own org. Every other field stays super-admin only.
- **B4** `GET /staff-pool/settings`: a new `inherited: bool`, true when the branch has no override of its own. Read it instead of comparing branch_id.
- **B5** `GET /settings/combos`: accepts org.settings.read OR menu.combos.edit.
- **B6** receive over-receive: 409 OVER_RECEIVE_NEEDS_NOTE (it was 400). Clients map it by code.
Checked against POS v0.9.0–v0.13.6, Dawam staff-v1.0.0–1.0.2, dash-v0.1.1 and web origin/main: none of them breaks.

## Web DONE (wt-owner-dash fix/owner-answers; 1a309c77..261c077c; lint, 4651 tests and the build all pass)
Behaviour the Flutter round must match:
- **W1:** the DataTable filters on a trimmed search, and a box of only spaces filters nothing. Also the count search, the Combobox and the two item pickers. Combos trims before sending.
- **W2:** a swap group's effect badge is filled (primary); other effects are secondary. Flutter's GroupBadgeVariant.filled already matches.
- **W3 Seats** (floor/util.ts parseSeats):
  - On blur or Enter, anything that isn't a whole number 0–99 is refused. That includes a blank box, which used to save 0.
  - The refused value stays in the box, marked aria-invalid.
  - floor.errSeats shows under the label/seats row; typing clears it.
- **W4 loyalty:** these fields are hidden in their cases:
  - the earn rate, in stamps mode;
  - the cap, when the cap is off;
  - the birthday and win-back gifts, when those are off.

  Hidden fields never block Save. The cap and gifts are blanked (sent null). A hidden earn rate keeps a valid edit, else the saved rate. The summary ignores hidden errors.
- **W5 payment methods:** tellers and devices each show a skeleton while loading. A failure with nothing to show reads "Couldn't load this", then the server message, and a Retry for that list only. "No tellers/devices" shows only for an empty answer, and the count chip waits for the data.
- **W6 team reports:** every stat card on all 4 tabs shows "—" when its report failed with nothing to show (failedEmpty).
- **W7 Basira heatmap:** dir="ltr" (labels on the left, hours left to right).
- **W8 Studio:**
  - A server note equal to the library note (per language) seeds an empty box; the library note is the placeholder; untouched steps re-fill when the library arrives.
  - The preview gives `one_size` no chip, so there's no Size row.
  - Options is gated on menu.items.edit: without it, the controls are disabled, add/remove/clear are hidden, an empty section reads "No options yet", and Save skips options.
- **W9:**
  - **B2:** clearing a held figure sends {org_ingredient_id, counted_qty:null} in the autosave and in the save before Finalize. A row never counted is never sent as null.
  - **B4:** inherited = branchId && data.inherited === true; it drives the note and the "Follow the organisation" offer.
  - **B1:** a cleared contact sends null.
  - **B6:** worded by its code at 400 or 409.

## Flutter round (madar, worktree /Users/shawket/Desktop/Madar/wt-owner-pos, branch fix/owner-answers-flutter off local main 7f651d2b)
The API client is already regenerated (84cc1ee3). Match the web behaviour in "Web DONE" above and the contract in "Backend DONE".

Rules:
- STAY OUT of these; another session (madar-92) owns them:
  - `packages/dashboard_core/lib/src/data/offline*.dart`
  - `packages/dashboard_core/lib/src/session/session.dart`
  - `packages/dashboard_core/lib/src/shell/session_guard.dart`
  - `packages/dashboard_core/lib/src/testing/harness.dart`
  - `apps/dashboard/lib/boot/*`
  - `rust-core/crates/madar-frb-dashboard/src/api/{rules,offline}.rs`
  - the generated bridge files
- Business rules run in Rust (`package:rust_bridge_dashboard/rules.dart`). Never add a Dart copy of a rule. If a rule you need is missing, say so in your reply.
- Before running tests, `rust-core/target/release/libmadar_frb_dashboard.dylib` must exist. The orchestrator is building it; if it's missing, wait and check again. Every test folder has a `flutter_test_config.dart` calling `await loadRulesForTest();`, so give any new test folder one too.
- Tests: `python3 tool/fdash_test.py <package> [files]` and `--analyze`. Also `dart format`.
- For each fix, update or delete its divergence row in docs/fdash/divergences/. Commit on the branch, each message ending with the Co-Authored-By line. Never push. Never git stash.

Split:
- **Agent F1, setup + admin:**
  - W4 loyalty hidden fields;
  - W5 payment-methods tellers/devices states;
  - the Links preview's wide layout (setup-links.md: the web has narrow AND wide; port the wide one);
  - B4 staff_pool `inherited`;
  - B5 combo settings (remove any workaround);
  - B3 brand links (SET-BRD-017: the save now works for an owner with org.settings.edit; remove the question row and any refusal workaround; the mock must match the server's new rule).
- **Agent F2, catalog_menu + sell + reports + team:**
  - W8 studio (notes as placeholder, no one_size chip, Options gated on menu.items.edit);
  - W2 (check the groups badge);
  - W3 floor Seats;
  - W7 Basira heatmap LTR;
  - W6 team reports '—'.
- **Agent F3, inventory + catalog_offers + kit search:**
  - W9 B2 count un-count (send counted_qty null; the mock must handle it);
  - B1 supplier clear (send null; the mock clears);
  - B6 over-receive 409 (the mock answers 409; wording by code);
  - W1 trim: check the count search, item pickers, combobox and combos trim-before-send in Flutter (the kit already trims tables).

## STATE AT STOP (2026-10-10; the owner paused the work; resume from here)
- **Backend:** DONE, committed on wt-owner-api fix/owner-answers (2bea132..36c6bcf). Not pushed.
- **Web:** DONE, committed on wt-owner-dash fix/owner-answers (1a309c77..261c077c). Not pushed.
- **Flutter** (wt-owner-pos fix/owner-answers-flutter, off local main 7f651d2b; the rules dylib is built in rust-core/target/release):
  - **DONE and committed:**
    - 84cc1ee3 API client regenerated;
    - 45153969 W4 loyalty;
    - afb203eb W5 payment methods;
    - f610f89c B4 staff drinks inherited;
    - b5373262 B5 combo settings read. F1 had been about to add a page test after SET-CMB-005 for the combos-editor-only person; check whether it's needed.
  - **WIP** (the "WIP: owner fixes in progress" commit; finish, test, then squash or reword):
    - F2 studio W8 (studio_model, studio_steps, studio_preview, studio_options, menu_studio_page and their tests): was writing the model test;
    - F3 inventory B2 count un-count, B1 supplier clear and B6 over-receive 409 (count_editor, counts_data, inventory_lib, the counts/purchasing/transfers mocks and tests): was editing the divergence rows;
    - F3 W1 combos trim test (catalog_offers combos_page_test).
  - **NOT STARTED:**
    - F1: the Links wide preview layout, B3 brand links;
    - F2: W2 groups badge check, W3 floor Seats, W7 Basira heatmap LTR, W6 team reports '—';
    - F3: W1 trim in the Flutter count search, item pickers and combobox.
  - **Then:**
    - run every dashboard package, `flutter analyze .` and the dart format check;
    - ask the owner whether to merge the three branches (backend, web, Flutter). Nothing merges or pushes without the owner's word.
- **Coordination:** madar-92 owns Step 1b (the offline cache → core SQLite) on feat/dashboard-offline-core. Stay out of the offline*/session/session_guard/harness/boot files and the frb rules/offline.rs and generated bindings.
- **Open owner question:** Q1, whether to share the Dawam manager views or scrub them from Dawam.

## DONE (2026-10-10, resumed after the pause)
- **Flutter branch fix/owner-answers-flutter:** every F1, F2 and F3 item is committed. Local main is merged in up to 6dcdba3e, the offline cache in the core.
- **Final pass:** `flutter analyze .` and the dart format check are clean. Tests: api 68, kit 219, core 182, app 165, admin 886, menu 1051, offers 540, inventory 900, overview 149, reports 1068, sell 763, setup 1135, team 1278 (8,404 in all).
- **Waiting for the owner:** the merges of the three branches (wt-owner-api, wt-owner-dash, wt-owner-pos). Deploy order: the backend before any web or Flutter release, because a cleared count sends counted_qty:null, which the old backend refuses.
