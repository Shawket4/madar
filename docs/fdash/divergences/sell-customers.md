# Sell / Customers (`/customers`): differences from the web

One line per difference: what the web does, what Flutter does, why. Rows marked "question" port
the web's behaviour as it is and ask the owner whether it is intended.

| Row | Web | Flutter | Why |
|---|---|---|---|
| SELL-ALL-017 (all error words on this page) | `getErrorMessage` shows the backend's `error` sentence (kind prefix stripped), which is English, in the Arabic UI too. | Uses the `ApiException.message` first (kind prefix stripped): in real mode the core has already worded it in the active language; the envelope's English `error` is only a fallback. Coded refusals and uncoded 403/429 read exactly as on the web. The adjust "note required" refusal is still recognised from the envelope's English sentence, so its field error shows in both languages. | English inside the Arabic UI is a web bug (SPEC 6.3). Pinned by `customers_data_test` "SELL-ALL-017 error wording" and "the adjust note required refusal…". |
| SELL-CUS-035 merge picker | The 20 suggestions are read when the dialog opens; the typed search survives closing and reopening the popover (it resets when the dialog reopens). | The suggestions are read when the picker opens; each opening starts with an empty search. The request is the same (`GET /customers?limit=20[&q=]`, 300 ms debounce, the opened customer left out). | Platform: the picker is a popover on a wide screen and a full-height sheet on a phone, whose search lives with it. Question: whether keeping the typed search matters. |
| SELL-CUS-043, SELL-CUS-053 phone layout | The ledger and the recent orders are tables on every width (`overflow-x-auto`). | Below 760 they are stacked rows (ledger: what + amount, date, branch and "View order"; orders: ref + total, branch · status, date), same data and links. | SPEC 6.1: below 760 a table becomes rows/cards. |
| SELL-CUS-012 Last visit dash | "—" in the muted colour. | "—" in the figure colour of the numeric column (the table's own numeric cell). | Kit: the numeric column renders its text; a muted dash would need its own cell. Cosmetic. |
