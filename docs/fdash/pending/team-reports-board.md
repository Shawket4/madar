# team/team_reports (2 major) + team/team_board (AT PARITY, minors)
NOTE: the orchestrator already switched Arabic durations to a right-to-left isolate in dashboard_core fmtElapsedMs/fmtDuration and in team/lib/src/shared/team_format.dart fmtHours ("9 س 4 د" reads hours first). Update every team test that pinned the old LTR-isolated Arabic string (test/team_reports/team_reports_tabs_test.dart, test/attendance/attendance_page_test.dart, test/shared/shared_test.dart, any other), and remove the TEAM-ALL-013 "ported as the web" line from divergences/team-team_reports.md (reply with the new row: Arabic durations are RTL-isolated, a web bug not copied).
## team_reports
1 MAJOR (RPT-031, ALL-020): money and period cells cut on desktop ("EGP 167,00…", "01 Sept 202…", "OVERTIME HO…"). In team_reports_page.dart ReportTable, pass a per-column minWidth (money and Period ~160–220) so the table scrolls instead of cutting. Re-shoot the payroll tab at desktop and tablet.
2 MAJOR (ALL-013): see the NOTE (done in shared); update the tests.
## team_board
3 minor (TEM-010/024/008): replace failedEmpty(...) at team_board_page.dart:297, 367, 438 with .failedFirst. Drop the area copy at shared/staff_query.dart:136 if nothing else uses it (grep first).
4 minor: intent test for "Log an expense advance": rest, press, expect one GET /staff/employees?employment_status=active.
5 minor (TEM-005): assert each dialog's own title (team_board_page_test.dart:143).
6 minor (TEM-003/004): add one save from the board each: assert the POST body and that the board's reads refresh.
7 minor (TEM-022/030): tests that a flag or punch save still refreshes when the dialog closed mid-request.
8 minor (ALL-016): the rules banner button (shared rules_banner.dart) gets onIntent: () => ref.prefetchRoute(target).
Run test/team_reports, test/team_board, test/attendance, test/shared, test/payroll and test/schedule.
