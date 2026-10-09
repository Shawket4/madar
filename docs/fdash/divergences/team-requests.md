# team / requests: divergences from the web

| Row | Web | Flutter | Why |
|---|---|---|---|
| TEAM-REQ-011 | The row's meta joins the window, title, reason, "Decided by {{name}}", the notes and the cancel words as plain text; in Arabic an English reason pulls the date's figures into its run. | Each typed name, title, reason and note sits in a first-strong isolate (U+2068…U+2069), as Approvals does. | Web bidi bug (TEAM-ALL-013 intent: figures read correctly in Arabic). |
| TEAM-REQ-045 | The From date is a typed field; emptying it says "Pick a date" on Save. | The kit's date field is a picker that is never empty (it opens on today), so the message cannot arise and is not ported. | kit |
| TEAM-REQ-045 | — | The kit's calendar popover overflows when 220–360 px are left under its field (the leave form's To at 1440×900); the test runs that check in a taller window. | kit candidate: `DashPopover` should flip or cap the date panel. |
| TEAM-REQ-020 | ApproveWithPayDialog shows the request it was opened with. | The dialog is shared with Approvals and follows a fresher copy of the request: on Requests, the page's own list for the filters in force (no extra read); on Approvals, the pending list. Untouched, the switch follows a refreshed paid_default. | Seeded-form rule (brief). |
| mock | A decision reprices the covered days and an approved correction rewrites its punch. | The mock records the decision only. | Mock scope: no page of this unit reads the effect. |

| TEAM-REQ-018 | After a successful reject the web reads nothing again, so the rejected request stays listed as pending until the next refetch. | A successful reject re-reads /staff, so the row leaves the pending list at once. | Web bug, not copied. |
