# Team / Schedule: differences from the web

`/staff/schedule` (the week bar, the grid, open shifts, suggestions, holidays, the day editor,
coverage needs, preferences, fairness). Web: `MadarDashboard` `main` @ v1.4.18. One row per
difference; tests are in `packages/dashboard_features/team/test/schedule/`.

| Row | Web | Flutter | Why |
|---|---|---|---|
| TEAM-SCH-040…046 | The day editor is `sm:max-w-lg` (512 px). | The day editor is `DashMetrics.dialogWide` (672 px) on wide screens; full screen on a phone as every dialog. | Kit: `DashTimeField`'s list is exactly as wide as its field, and the end time's length hints ("8 h 30 min · next day") overflowed it at 512. Same content, same order. Reported as a kit candidate. |
| TEAM-SCH-017 / 072 | The preferences button is 32 px on a phone (`size-8`), the name cell up to 12 rem. | The button is the 44 pt tap target the spec requires; the phone name column is 168 px with tighter padding so typical names still fit. | Accessibility rule (tap targets ≥ 44 pt). |
| TEAM-SCH-060 | The dialog seeds from the person as they were when it opened. | It seeds from the latest roster and re-seeds while untouched, so a background refresh never leaves stale preferences to save. | Brief rule: forms seeded from cached data re-seed until edited. |
| TEAM-ALL-009 | `refetchOnWindowFocus` after 30 s for the roster, the 45-day holidays read, the suggestions and the fairness reads (not the coverage editor). | The same reads refetch on app resume when the last answer is 30 s old or more; re-opening the page refetches stale reads through `webCache()`. | No window focus in Flutter; app resume is its equivalent. |
| TEAM-SCH-006 / 071 | The week range sits in a `<bdi>`. | Plain text in the paragraph's direction (the first strong character is the same as the page's), so an Arabic range reads right to left. | Same result; an LTR isolate scrambled the Arabic range. |
| TEAM-SCH-062 change log loading | While the change log loads, the preferences dialog briefly shows "No changes yet." | A skeleton shows while it loads; "No changes yet." appears only for a real empty answer. | The loading/empty rule: never show an empty state during a load. Web bug not copied. |
