# Setup / Delivery (`/settings/delivery`, `/settings/delivery-zones`): differences from the web

One line per difference: what the web does, what Flutter does, why.

| Row | Web | Flutter | Why |
|---|---|---|---|
| SET-DLV-013 / 022 hidden invalid field | A wrong value inside a switched-off channel (e.g. a distance of 0, then Outside switched off) blocks Save with its message hidden: Save does nothing. | Save is still blocked, and a toast says why ("Distance must be greater than 0" / "Fee cannot be negative"). | A Save that silently does nothing is a web bug (SPEC 6.1, 6.3). Pinned by "SET-DLV-013 SET-DLV-022 (divergence)…". |
| SET-DLV-017 auto-reject minutes | The PUT body omits `auto_reject_minutes`, so the backend's upsert stores null and every save from this page clears the auto-reject window set elsewhere. | The value read is sent back unchanged. | A save that wipes a field the page does not show is data loss (SPEC 6.3). Pinned by "SET-DLV-017 (divergence)…". |
| SET-DLV-022 background refresh | `form.reset` runs on every new read, so a background refetch overwrites what the person was typing. | The form follows a refresh only until the person edits it; after a save the refetch refills it. | The brief's rule for forms seeded from cached data. Pinned by "SET-DLV-022 a background refresh refills an untouched form…". |
| SET-DZN-017 / 018 / 021 name translations | The zone body has no `name_translations`; the backend's serde default stores JSON null, so an edit wipes the zone's translations. | An edit sends the zone's own `name_translations` back; a create sends `{}`. | An edit that erases data the dialog does not show is a web bug. Pinned by "SET-DZN-021 (divergence)…". |
| SET-DZN-022 refresh while open | The dialog seeds its fields once per open; a background refresh of the list while it is open leaves it on the old values. | Until the person types, an open editor follows a refresh (the zone's new values, a new zone's new default km and name). | The brief's rule for forms seeded from cached data. Pinned by "SET-DZN-022 an open editor follows a refresh…". |
| SET-DZN-004 Retry spinner (kit) | ErrorState's Retry spins while the refetch runs. | The table's error Retry does not spin: `DashDataTable` takes no `retrying` flag. | Kit gap, reported as a kit candidate; the request and outcome are the same. |
