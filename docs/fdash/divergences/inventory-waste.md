# Inventory ▸ Waste: divergences from the web

Web: `src/features/inventory/{waste-page,waste-dialog}.tsx` (v1.4.18). Flutter:
`packages/dashboard_features/inventory/lib/src/waste/`. Tests named `(divergence)` pin each fix.

| Row | Web | Flutter | Why |
|---|---|---|---|
| INV-WST-015, INV-WST-031 | The dialog has no error UI for its branch-stock read: a failed read leaves the picker empty and shows "This branch has no stock on record yet. Count it first" (`every` over no rows is true). | A failed stock read shows the server's words and a Retry link in place of the count-first banner; the banner shows only for a real answer with no activity. Loading still shows neither, as the web. | Bug: telling someone to count a branch that does have stock, because a request failed, sends them to the wrong fix. |
| INV-ALL-024 | "Count it first" links to `/inventory/counts` without search params, so the branch falls back to All branches and the period to the default. | The scope (branch, period) is kept: it lives in the shell's scope provider, not the URL. | Likely a web bug (the inventory marks it a quirk to reproduce only if the owner confirms); same as Today and Ingredients. |
| INV-ALL-006 | No route guard: typing `/inventory/waste` without `inventory.waste.read` renders the page and both reads show their 403 states. | The shell's route gate (`DashRoute.caps`, owned by the shell) shows `Restricted` and reads nothing. A 403 the server sends anyway still shows its words in the log (pinned). | Shell-wide rule (same as Today and Ingredients); not this unit's to change. Question for the owner. |
| INV-ALL-021 | The log search skips a column whose value in the FIRST row is null (e.g. Reason or By when the newest line has none), for every row. | Date, Branch, Ingredient, Quantity, Reason and By are always searched over their raw values. Both trim the typed text (W1). | First-row rule is a web quirk (inventory: port only if the owner confirms). |
| INV-WST-012 date search text | The Date column is searched by the raw `occurred_at ?? created_at` text from the server (e.g. `2026-10-08T09:29:00Z`). | It is searched by the parsed time written back out in UTC; only times with no fraction of a second differ (`…T09:29:00.000Z`). | Platform limit: the generated `StockMovement` keeps only the parsed time, not the original text. |
