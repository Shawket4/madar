# team / team_board: divergences from the web

| Row | Web | Flutter | Why |
|---|---|---|---|
| TEAM-TEM-001 / 008 / 024 | Until the person's rights are known the reads are disabled (not loading), so the board flashes "—" cards and "Nobody is rostered today". | Skeletons until the rights are known; nothing is asked meanwhile. | A flash of a false empty state is a web defect (brief: never flash an empty state during a load). |
| TEAM-TEM-007 | `refetchInterval: 60_000`, counted from each fetch; paused while the tab is hidden. | A 60 s timer from page open that invalidates the presence; skipped while the app is not resumed. | Same cadence; React Query's per-fetch timer has no Riverpod equivalent. |
| TEAM-TEM-007 / TEAM-ALL-009 | Refetch on window focus per query, when that query's data is over 30 s old. | On app resume, when 30 s have passed since the board first loaded (or last resumed), the presence, the flags and the banner's checklist are asked again. | Approximation of focus refetch, as the area's other pages do. |
| TEAM-TEM-012 | An unknown flag kind's hint falls back to the cover's English sentence (`defaultValue`), untranslated. | Reads `dawam.flagHint_cover` in the person's language. | English inside the Arabic UI is a web bug. |
| TEAM-TEM-020 | "Confirming or rejecting a cover needs the cover right…" sits in the dialog footer. | It sits in the dialog body (the kit's footer holds buttons only). | Layout only. |
| TEAM-TEM-022 | `invalidateStaff()` runs after the toast. | Invalidation runs right after the answer, before the toast and even when the dialog is gone. | Brief rule: invalidate unconditionally after the await. |
| TEAM-TEM-029 | The reason chips sit between the input and the "A reason is needed" hint. | The hint sits under the input, the chips under it. | The kit's text field owns its description line; same words and behaviour. |
| TEAM-TEM-031 | The trailing pill and punch button never shrink (`shrink-0`): the name truncates instead. | The trailing part takes up to half the row and wraps the pill above the punch button when narrow. | Inventory row TEAM-TEM-031 asks for the wrap; keeps names readable on a phone. |
| mock | The board reads each person's day from `dawam_roster` (day edits, split days, branch zones). | The mock reads the standing weekly roster in Cairo time. | Mock limit (`ponytail:` comment in `team_board_mock.dart`); every seeded branch is in Cairo. |
