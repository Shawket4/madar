# admin/branch_setup: verifier findings (3 major, 12 minor)
M1 (BSU-024): branch_setup_page.dart:1376 History menu shows "Loading…" on q.isLoading (true during a background refresh). Use q.awaitingFirst.
M2 (BSU-071/052/030): inspector.dart:437 "Remove from the plan" → variant: DashButtonVariant.outlineDanger (now in the kit).
M3 (BSU-004/005/069): branch_setup_mock.dart:743-777 _routes uses active categories only; the server keeps routes for every non-deleted category (MadarRust branch_plan/handlers.rs:171-176). Take the order from all non-deleted categories of the org, and keep _categories (active only) for the categories list. Add a test: a routed inactive category survives a save.
1 (BSU-070): a rest-press test for the "Item routing" link (bb-item-routing).
2 (BSU-006/089): the web has builder.names.sectionPrinter (en.json:6764, ar.json:6911) and core already has it. Delete the divergence row (reply) and the key from assets/i18n/branch_setup.{en,ar}.json.
3 (BSU-089): rename the two "ADM-BSU-006 … names the server gives …" tests to "ADM-BSU-006/089 …".
4 (BSU-086): the mock's 403 wording → "Forbidden: Permission denied: read|update|create|delete kitchen_stations" (handlers.rs:580,594,622,648,654), with matching tests (branch_setup_mock_test.dart:317,327).
5: builderErrorText (inspector.dart:1444-1481) → use the area's orgErrorWords, as branches_data.dart:41 does.
6 (BSU-072/076): the review dialog takes before/firstSave/routingNow/openItems once (branch_setup_page.dart:361-376); watch branchPlanProvider(_branch) inside the dialog builder.
7 (BSU-043): removeLink drops only the first match (plan.dart:604,609); use ..removeWhere((x) => x == link.to.id).
8 (BSU-069): a category in a blank-named section shows "in " (inspector.dart:1393-1400); test (owner[id] ?? '').isNotEmpty.
9 (BSU-057): a missing current device shows "Select" (inspector.dart:809); use placeholder: ''.
10 (BSU-047): the whole kitchen-chits row toggles, and its semantics are merged with the hint (inspector.dart:483-517).
11 mock fidelity:
- activateSlotCode (:638-651) refuses expired/revoked codes and updates the device row (kind/label from the code, retirement cleared, last seen now) per activation.rs:386-433;
- the version row stores the body as sent (:543);
- the PUT checks follow the server's order, with its parse-error sentences (:395-451);
- updated_at moves on every save (:1263);
- the never-saved plan keeps labels/IPs as typed (:864,896).
Run test/branch_setup and admin test/shared.
