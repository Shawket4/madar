# Team / Attendance: differences from the web

`/staff/attendance` (the records, the headline cards, Add record, Correct record, Export Excel).
Web: `MadarDashboard` `main` @ v1.4.18 (checked against v1.4.20, unchanged here). One row per
difference; tests pinning a fix are named `'<ROW> …'` in
`packages/dashboard_features/team/test/attendance/`.

| Row | Web | Flutter | Why |
|---|---|---|---|
| TEAM-ATT-025 | With every branch in scope and a person who works at no branch, Save sets "Pick a branch" on the Branch field, which is not rendered: Save silently does nothing. | "Pick a branch" shows under the Employee field when there is no Branch field to carry it. | A check that silently blocks Save. |
| TEAM-ATT-029 / TEAM-ALL-025 | A time the field cannot read ("soon") reaches the form as typed; `fromZonedInput` turns `2026-10-08Tsoon` into `null`, so Save writes the record WITHOUT that punch. | The field says "Couldn't read …" and Save refuses while a typed time is unreadable (`stampReadable`); a day with no time yet still sends nothing, as on the web. | A save that drops what the person typed. |
| TEAM-ATT-029 / 035 | In and Out side by side (`grid-cols-2`), each a day + a time: in the 32 rem dialog the day trigger gets about 80 px and cuts the date. | In above Out, each the full width (day + a 136 px time), the zone note under them. | Layout: the day stays readable; same fields, same order. |
| TEAM-ATT-035 | The form resets whenever `initial` changes (the branch zone landing late), even over what the person typed; a background refresh never reaches it (the record is a snapshot). | The dialog follows the page's read of the record: a background refresh re-seeds it until the person edits anything, never after; the diff ("only what changed") is against what was seeded. | The brief's re-seed rule; an edit is never wiped. |
| TEAM-ATT-038 | The Employee/Status row keeps `sm:pt-[1.625rem]` after it wraps under the dates (≥ 640 px but too narrow for one line), leaving a gap. | Padded level with the date fields only while it sits beside them. | The padding's intent is the alignment. |
| TEAM-ATT-003 | usePeriodStartDay reads the rules with staleTime: 60 s. | Shares dashboard_core's staffAttendanceSettingsProvider (same request key, 30 s like every read). | The provider belongs to dashboard_core; a local copy with its own staleTime would send the same request twice. Effect: a background refetch after 30 s instead of 60 s, never a visible change. |
| TEAM-ATT-030 / 036 | The covered / closed-month notes are `border-dashed` boxes. | A local dashed painter (`_DashedNote`) on the kit's hairline colour. | The kit has no dashed box (kit candidate). |
