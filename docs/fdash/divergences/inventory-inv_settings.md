# Inventory ▸ Settings: divergences from the web

Web: `src/features/inventory/settings-page.tsx` (v1.4.18). Flutter:
`packages/dashboard_features/inventory/lib/src/inv_settings/`. Tests named `(divergence)` pin each fix.

| Row | Web | Flutter | Why |
|---|---|---|---|
| INV-SET-006 | A negative or unreadable percent makes Save do nothing: no request, no message. | Still no request, but the field is marked and says why with the kit's number words ("0 % or more", "… is not a number"). | A Save that silently does nothing is a defect (SPEC 6.1). |
| INV-SET-006 | `useEffect` copies every new settings read into the field, overwriting what the person is typing. | The field follows the server until the person edits it; after a successful Save it follows the server again once the refetch lands. | The brief's re-seed rule: a background refresh must not clobber an edit. |
| INV-SET-009, -014 | English "1 ingredients" / "1 ingredients use this category" (the web's tables have no `_one` forms). | The unit's English supplement adds `inventory.settings.ingredientCount_one` and `deleteCategoryReassign_one`; Arabic is the web's. | Grammar bug in the web's English. |
| INV-SET-010 | The switch is disabled without `inventory.adjust`. | Same code, but unreachable: the shell's route gate (`caps: [inventory.adjust]`) shows Restricted first (see INV-ALL-006 in inventory-today.md). | Shell-wide rule; not this unit's to change. |
| INV-SET-010 | The "Packaging" word is a `<label>`: clicking the word toggles the switch. | Only the switch toggles; the word is plain text. | Small gap; the switch keeps its own aria label. |
| INV-SET-012 | The inventory notes a 409 duplicate on rename. | The backend's PATCH never changes the slug (unique key is `org_id, slug`), so a rename can only fail 400 (1–80 chars) or 404; the mock does the same. | Follows MadarRust `update_ingredient_category`. |
| INV-SET-003 | `prefetchRoute('/inventory/settings')` warms only the settings read. | The route also warms the categories read (the page's other first read). | SPEC 6.1 prefetch rule: warm the page's exact first-mount reads. |
| INV-ALL-006 | No route guard: without `inventory.adjust` the page renders. | The shell shows Restricted and reads nothing (pinned for `limited`). | Shell-wide rule; question for the owner (same as Today). |
| INV-SET-007 | (question) A failed settings read shows no error at all: the field is disabled and empty, Save disabled. | Ported as is. | Looks like an oversight, but it is the recorded behaviour. |
