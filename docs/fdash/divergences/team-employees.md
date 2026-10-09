# Team / Employees: differences from the web

`/staff/employees` (Employees, the profile, Add employee, Import, Departments, the salary calculator).
Web: `MadarDashboard` `main` @ v1.4.18. One row per difference; tests pinning a fix are named
`'<ROW> …'` in `packages/dashboard_features/team/test/employees/`.

| Row | Web | Flutter | Why |
|---|---|---|---|
| TEAM-EMP-074 | The table's global filter only searches a column whose value on the FIRST loaded row is a string or number (tanstack `getColumnCanGlobalFilter`): a list whose first person has no number, role or department silently stops matching on those. | Always searches the six accessor values (name, kind key, number, role key, department, status key); job title, branches, Staff app, phone model and salary stay unsearched. | Web bug: what is searchable depends on who sorts first. |
| TEAM-EMP-005 | Branch names joined with the Arabic comma "، " in both languages. | Joined with `common.listSeparator` (", " in English, "، " in Arabic). | Arabic punctuation inside English text. |
| TEAM-EMP-038 | "To add them: …" joins the missing items with ", " in both languages. | `common.listSeparator`. | English comma inside Arabic text. |
| TEAM-EMP-018 / 034 | A number longer than 32 characters fails zod's default `max` with zod's English sentence. | "At most 32 characters" (`common.atMostChars`). | English shown in the Arabic UI. |
| TEAM-EMP-026 | `pay_account` is checked against 64 characters even while hidden (Cash), so a long old account blocks Save with an error nobody can see. | Checked only while the account box is shown (bank or wallet); Cash sends `null` anyway. | A check that silently blocks Save. |
| TEAM-EMP-050 | The browser's own file input ("Choose File" / "No file chosen", in the browser's language). | A "Choose a file" button and the file's name or "No file chosen" (supplement `teamEmployees.chooseFile`, `teamEmployees.noFileChosen`, EN + AR). Picks through `FileGateway` (`xlsx`, `csv`). | No browser control in Flutter; same words. |
| TEAM-EMP-075 | An unreadable `.xlsx` toasts ExcelJS's own (English, technical) error message. | A file that is not a workbook (not a zip) is refused before reading; the toast says `errors.unknown` in the person's language. | Raw library errors shown to people. |
| TEAM-EMP-051 | `exceljs` `eachRow({includeEmpty: false})` drops blank rows before numbering, so rows after a blank one are misnumbered. | Rows as `ExportGateway.readXlsx` returns them (the core keeps the sheet's rows); CSV numbering matches the web. | Question: depends on the core reader; the web's numbering promise is "as in the sheet". |
| TEAM-EMP-060 / 061 | The dialog lists `departmentsQ.data ?? []`: "No departments yet." while the list loads and when it fails (a person without `hr.staff.read`). | Skeletons while it loads; a failed read with nothing to show says the refusal with Retry. | Never say "none" before (or instead of) the answer. |
| TEAM-EMP-032 | "Everyone with a Madar account is already an employee." shows while the linkable list loads, and when it fails. | Only for a real empty answer; a failed read shows its words. | Same. |
| TEAM-EMP-070 | The calculator reads the rules with `staleTime: 60 s`. | Shares dashboard_core's `staffAttendanceSettingsProvider` (the same request key, 30 s like every read). | One request per key; the age only changes when a background refetch happens. |
| TEAM-EMP-017…028 | zod + react-hook-form: the first issue per field, cross-field refinements only once the fields parse. | Every field's problem at once after the first Save (the profile) or once the field changed (Add, `mode: onChange`). | Same words and the same refusals; the order of appearance differs. |
| TEAM-ALL-023 | Reads retry (429 three times, others once) before the error shows. | dashboard_core's `webRetry` in the app; the test harness turns retries off. | Owned by dashboard_core; not driven by this unit's tests. |

| TEAM-EMP-016 / 021 / 022 / 036 | `<input type="date">`: typed day, month and year, clearable. | A small month dialog (on every screen size) with a Year dropdown, Today, and Clear once a date is set. Clear sends `null`. Words: `teamEmployees.year`. | Flutter has no native date input. The kit's date field has no Clear or year jump, and its popover gets cut off inside a dialog (kit candidate), hence the local `EmployeeDateField`. |
