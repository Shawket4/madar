# Team / Reports: differences from the web

`/staff/reports` (attendance & discipline, labour vs sales, overtime & payroll, advances; CSV per
table). Web: `MadarDashboard` `main` (`features/dawam/reports-page.tsx`, unchanged since v1.4.18).
One row per difference; tests are named `'<ROW> …'` in
`packages/dashboard_features/team/test/team_reports/`.

| Row | Web | Flutter | Why |
|---|---|---|---|
| TEAM-ALL-007 | `usePeriodStartDay()` runs before the `<Restricted>` return, so a person with no tab still fires `GET /staff/attendance/settings`. | A refused person's page asks for nothing. | The inventory's rule for guarded pages ("nothing is requested"); the read only picks the opening dates of a page they cannot use. |
| TEAM-RPT-003 | `usePeriodStartDay` reads the settings with its own `staleTime: 60 s`. | The page shares dashboard_core's `staffAttendanceSettingsProvider` (the app's 30 s). | Shared read owned by the foundation; at most one extra background refetch. Kit/core candidate: a staleTime on the shared read. |
| TEAM-RPT-005 | Each tab trigger carries an icon (CalendarClock, Scale, Banknote, HandCoins). | Labels only. | Kit: `DashTab` has no icon slot (kit candidate). |
| TEAM-RPT-007 | `downloadBlob` cannot fail. | A failed file save toasts its words. | Never a silent failure. |
| TEAM-ALL-013 Arabic durations | Arabic `fmtHours` ("9 س 4 د") sits in an LTR isolate, so it renders "9 د 4 س": minutes read first. | Arabic durations (`fmtHours`, `fmtMinutes`, core `fmtElapsedMs`/`fmtDuration`) sit in an RTL isolate and read hours first; a negative keeps its minus inside the isolate. | Web bidi bug, not copied. |
