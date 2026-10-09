# team/employees: verifier findings to fix (NOT at parity)
1 MAJOR (005/ALL-020): headers and cells are cut at desktop and tablet ("WHATSAPP NUMB…", "STA…", "Front of …"). The web never cuts (whitespace-nowrap + scroll). Raise each column's minWidth to its widest header or content: about name 150, kind 112, branches 112, phone 156, staff app 96, role 136, device 168, department 136, status 112, salary 196.
2 MAJOR (016-029): EmployeeDialog copies the employee once; the PUT sends every field, so a stale copy is saved over newer data, and after its own "Sign the phone out" it still shows "Signed in on …". Look up the live row by id from the page's list read; re-seed all fields while untouched (_dirty set by every onChanged); always take deviceModel/deviceSince from the live row. Drop the TEAM-EMP-029 divergence row and re-run the sign-out tests.
3 MAJOR (032/030): "Make employee" with a preset user never fills the WhatsApp number (web: useEffect([pickedUser, linkable]), add-employees.tsx:143-146). Add ref.listen(linkableUsersProvider) plus a first-build check that fills _phone when kind is linked, _userId is set, _phone is empty and the user has a phone. Extend add_employee_test.dart:79 to expect +201110010101.
4 MAJOR (016/021/022/036): the hire date can't be cleared and the picker only steps by month; the web's date input can be emptied (hire_date: null) and the year typed. Add "Clear" (common.clear) to _MonthCard and a year jump or typed date; test both; remove that "question" divergence row.
5 minor (030): the Add dialog width should be 448 (web sm:max-w-md), not the kit's 512.
6 minor (034): PhoneField should always show its description (drop the `!invalid` condition).
7 minor (053/055): rebalance the import preview columns (e.g. name 3, phone 4, branch 3, salary 3, result 7).
8 minor (055/075): closing Import mid-run still toasts "{{added}} of {{total}} added": capture the toast host before the loop.
9 Intent warming (owner rule): employee rows opening the profile (onRowIntent), pagers, filter options, menu items, and the Departments and Import buttons if their dialogs read. Test per kind.
10 Replace the hand-written loading check at employees_page.dart:183 with awaitingFirst/failedFirst.
Note: attendanceErrorText now lives in team/lib/src/shared/attendance_errors.dart.
