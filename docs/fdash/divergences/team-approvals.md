# team / approvals: divergences from the web

| Row | Web | Flutter | Why |
|---|---|---|---|
| TEAM-APR-007 | Detail lines join shift names, titles and reasons with dates as plain text; in Arabic a Latin shift name pulls the date's figures into its run ("Morning · 11" then "أكتوبر 2026"). | Each typed name or line is wrapped in a first-strong isolate (U+2068…U+2069), so the date reads whole. | Web bidi bug (TEAM-ALL-013 intent: figures read correctly in Arabic). |
| TEAM-MNY-039 (Review advance) | An installments value outside 1–24 or a fraction shows zod's English message. | Shows the field's own range words (`dawam.installmentsHint`). | English inside the Arabic UI is a web bug. |
| TEAM-MNY-033 (Reject dialog) | A reason over 500 characters shows zod's English message. | Shows `staff.noteTooLong`. | Same as above. |
| TEAM-APR-005 | `failedEmpty` (error and no data) shows the section error at once, during React Query's retry too. | `failedFirst` (dashboard_core `DashAsyncState`): the skeleton stays during the automatic retry; the error shows after it. | Brief rule: no error flash during a retry (matches the web's own retry timing, TEAM-ALL-023). |
| mock | The backend computes labour-limit warnings when a claim is approved. | The mock answers no warnings; the test overrides the answer to drive the warning toast. | Mock scope: the day-view figures belong to the Schedule unit. |
