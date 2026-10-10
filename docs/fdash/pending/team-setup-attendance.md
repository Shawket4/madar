# team/team_setup + team/attendance: verifier findings to fix (both NOT at parity)
## team_setup
1 MAJOR (SET-013): "Add a branch" (setup_branches_step.dart:66-71) needs onIntent: () => ref.prefetchRoute('/branches?edit=new') (it warms adminBranchesProvider(orgId)). Add an intent test.
2 MAJOR (SET-027/036): step 2 "Add employee" (setup_steps.dart:60-65) needs onIntent warming linkableUsersProvider. Give SetupPeopleStep an onAddIntent and wire it in team_setup_page.dart (~212). Add an intent test.
3 minor: links to /staff/shifts (setup_steps.dart:288), /staff/rules (:617), /staff/schedule and /staff/team (team_setup_page.dart:541,548) get onIntent: () => ref.prefetchRoute(path).
4 minor: add intent tests in test/team_setup.
## attendance
1 MAJOR (ALL-023, ATT-020, ATT-007/008, ALL-010/022): loading and error ignore automatic retries.
- attendance_page.dart:228-231: loading: recordsQ.awaitingFirst; errorMessage only when recordsQ.hasError && !recordsQ.retrying. Cards (:612): summary.awaitingFirst / summary.failedFirst.
- Shared team helpers: shared/staff_query.dart:135 failedEmpty → v.hasError && !v.hasValue && !v.retrying; shared/refresh_toast.dart:26 returns early when next.retrying.
- Test with a ProviderContainer(retry: webRetry): one 500 → skeleton then rows, no error frame. Run test/team_setup, test/employees, test/schedule, test/payroll and test/approvals too, because the shared helpers change.
2 MAJOR (intent):
- "Add record" (attendance_page.dart:198-202) warms staffActiveEmployeesProvider, staffWorkShiftsProvider and attendanceListProvider(attendanceWindow(d, addDays(d, 40))) with d = teamTodayIsoOf(ref).
- The employee picker DashSelect (:562) and the status DashFilterSelect (:580) get onOptionIntent warming attendanceListProvider(k) and attendanceSummaryProvider(k) for that option's key.
- The kit's DashDateRangeField has no quick-pill intent hook: log it as a kit candidate.
- Add an intent test.
3 MAJOR (polish): "LATE / LEFT EAR…" is cut on desktop EN. Raise that column's minWidth (attendance_page.dart:434) from 128 to ~168.
4 minor (ATT-003): the web reads the settings with a 60 s staleTime (dawam/period.ts:9). Use webCache(staleTime: 60 s) for this page's read if it is local, else reword the divergence's reason.
