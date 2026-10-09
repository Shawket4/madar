# Setup / Kitchen (`/settings/kitchen-stations`, `/settings/kitchen-routing`): differences from the web

One line per difference: what the web does, what Flutter does, why. Rows marked "question" port
the web's behaviour as it is and ask the owner whether it is intended.

| Row | Web | Flutter | Why |
|---|---|---|---|
| SET-KST-018 emptied port | `z.coerce.number` turns an emptied Port field into `0`, and `0` is sent as the printer port. | An emptied Port is sent as `null` (no port); an empty IP as `null`, as on the web. | The web's own `numOrNull` shows the intent is "no port"; a port of 0 is a web bug (SPEC 6.3). Pinned by `kitchen_stations_test` "SET-KST-018 (divergence)…". |
| SET-KST-016 port input | `<Input type="number">` also accepts `-`, `.` and `e`. | The Port field takes digits only. | A port is a whole positive number; same outcome for every valid value. |
| SET-KST-014 name placeholder | The literal "Grill" in both languages (English inside the Arabic UI). | Supplement key `kitchen.stationNamePlaceholder` ("Grill" / "الشواية"). | No hard-coded UI text (SPEC 2); English inside the Arabic UI is a web bug. |
| SET-KST-017 switch cards | Only the label and the switch toggle a switch card. | A tap anywhere on the card toggles it (the switch stays its own 44-pt control). | Touch targets (SPEC 2); same outcome. |
| SET-KST-019 refresh while open | The dialog resets only when it opens (or its station object changes); a background refresh of the list while it is open leaves the form on the old values. | While nothing has been touched, the form follows a background refresh of its station (a live `kitchen.*` event, a refetch); once edited, it keeps what was typed. | The brief's rule for forms seeded from cached data: a copy taken once would save stale values over newer ones. Pinned by "SET-KST-019 an untouched editor follows a background refresh…". |
| SET-KST-009 Retry spin | The table's Retry refetches the list. | The same; the kit's `DashDataTable` error state has no busy spinner for a manual Retry. | Kit limit (reported as a kit candidate). |
| SET-KST-008 / SHL-021 printer search | The DataTable uses TanStack's default `getColumnCanGlobalFilter`: a column is searched only if the first row's value is a string, so when the first station has no printer, "epson" finds nothing. | The search always covers the name and the printer model. | Whether a column is searched shouldn't depend on which station sorts first: a web bug (SPEC 6.3). |
