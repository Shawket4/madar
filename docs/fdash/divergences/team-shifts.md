# Team / Work shifts: differences from the web

`/staff/shifts` (the shift list, the Work shift dialog, the standing roster grid; the dialog is also
Set-up step 3's "New shift"). Web: `MadarDashboard` `main` @ v1.4.18. One row per difference; tests
are in `packages/dashboard_features/team/test/shifts/`.

| Row | Web | Flutter | Why |
|---|---|---|---|
| TEAM-SHF-026 / 028 | The grid gets `shifts = []` while the shift list's first load is in flight, so once the roster and people arrive first it says "Create a work shift first — there is nothing to assign yet." until the list lands. | The grid keeps its four skeleton bars until the shift list has answered too (`ScheduleGrid.shiftsLoading`). | Web bug: a "nothing to assign" flash during a load (the brief's "never flash an empty state during a load"). Pinned by `TEAM-SHF-026 loading: four skeleton bars`. |
| TEAM-ALL-009 | Reads refetch on window focus after 30 s (`refetchOnWindowFocus`). | The page refetches its three reads on app resume after 30 s; dialogs are never refetched this way. | Platform: Flutter has no window focus event; resume is the inventory's stated mapping. |
