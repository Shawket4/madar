# team/shifts (AT PARITY, minors) + team/schedule (1 major, minors)
## shifts
1 (SHF-014/022): the dialog copies the branch list once (shifts_page.dart _open, shift_dialog.dart _seed). Watch branchesProvider and re-apply the first-branch default while the form is untouched (web reset effect keyed on branches.length).
2 (SHF-024): rename the test 'Save shows its spinner while busy; a manager saving a business-wide block is refused in words' (shift_dialog_test.dart:525) to drop the refusal half; the next test covers it.
3: add a test: hold the POST, press Escape, release, expect the list re-read (save refreshes after the dialog closes).
4 (SHF-030): centre the roster cell menu on the cell (web align="center") if the kit popover supports it; otherwise log a kit candidate.
## schedule
1 MAJOR (ALL-022): remove lib/src/schedule/refresh_listener.dart. The core cache no longer refetches on a rebuild's re-listen (query_cache.dart; test query_cache_test.dart:59). Replace its uses (schedule_page.dart:511-516, coverage_card.dart:105, fairness_card.dart:281-283) with listenStaffRefreshFailure(ref, context, provider) per read, plus a ref.listen on the week's roster for _loadedAt (as the shifts page does). This also stops the refresh-failed toast firing during automatic retries.
2 (ALL-008): the Refresh icon must also spin for the coverage, fairness and audit reads when shown (anyFetching).
3 (SCH-004): _warmBranch also warms scheduleCoverageProvider(branch) while the coverage card is open and canEdit.
4: intent tests for Previous week, "Back to this week", the branch select options, and the /staff/shifts and /staff/employees links.
5 (SCH-008): the kit DashDateField has no intent hook: list it as a kit candidate.
6 (SCH-060/058): add tests that the preferences dialog and the coverage grid re-seed from a refresh until edited.
7 (SCH-062): give me a divergence row (reply): the change log shows a skeleton while loading, where the web flashes "No changes yet."
Run test/shifts, test/schedule and test/team_setup.
