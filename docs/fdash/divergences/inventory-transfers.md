# Inventory ▸ Transfers: divergences from the web

Web: `src/features/inventory/{transfers-page,transfer-dialog}.tsx` (v1.4.18). Flutter:
`packages/dashboard_features/inventory/lib/src/transfers/`. Tests named `(divergence)` pin each fix.

| Row | Web | Flutter | Why |
|---|---|---|---|
| INV-TRF-028 | The dialog's source-stock read has no error UI: a FAILED read makes the picker say "This branch has nothing on hand to send. Count it first." | A failed read shows the server's words and a Retry link above the picker; the picker never claims "nothing on hand" for a failed read. | Bug: it sends someone to count a branch that does hold stock, because a request failed (same fix as the Waste dialog). |
| INV-TRF-028 | While the source stock loads, the picker's empty text is "No results found". | It says "Loading…" (`common.loading`) until the answer lands. | Spec rule: never show "no results" during a load. |
| INV-TRF-002, INV-TRF-023 | `prefetchRoute('/inventory/transfers')` warms the list only with a branch picked. | With All branches it warms the all-branches list the page reads first (same as Purchasing). | Owner's intent-warming rule: the hover warms the page's exact first read; harmless and saves a round trip. |
| INV-ALL-006 | No route guard: typing `/inventory/transfers` without `inventory.transfers.read` renders the page and the list shows its 403. | The shell's route gate (`DashRoute.caps`, owned by the shell) shows `Restricted` and reads nothing. A 403 the server sends anyway still shows its words in the table (pinned). | Shell-wide rule (as the other inventory units); not this unit's to change. Question for the owner. |
| INV-TRF-008 | The note textarea is 3 rows and grows without limit. | 3 lines, growing to 6 then scrolling. | Kit text input; same words and behaviour. |
