# Admin / Devices (`/devices`): differences from the web

One line per difference: what the web does, what Flutter does, why. Rows marked "question" port
the web's behaviour as it is and ask the owner whether it is intended.

| Row | Web | Flutter | Why |
|---|---|---|---|
| ADM-DEV-023, -026 (Arabic) | "Last {{count}} days" and the two empty hints have one Arabic form, "آخر {{count}} يوم", so the window reads "آخر 7 يوم" / "آخر 30 يوم". | The supplement adds the `_few` (3–10: "أيام") and `_many` (11–99: "يومًا") forms, so 7 reads "آخر 7 أيام" and 14 / 30 / 90 read "يومًا". | Arabic grammar: a number of days 3–10 takes the plural, 11–99 the accusative singular. The English is unchanged. Pinned by `client_versions_test` "ADM-DEV-023 (divergence)…". |
| ADM-DEV-029 (owner rule) | The Edit device dialog fills from the device when it opens and never again. | It also re-fills when a background refresh of the devices list lands, until a field is changed. | The brief's rule for forms seeded from cached data: a copy taken once would save stale values over newer ones. Pinned by `devices_page_test` "ADM-DEV-029 a refresh that lands re-seeds…". |
