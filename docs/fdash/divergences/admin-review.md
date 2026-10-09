# admin / review divergences

| Row | Web | Flutter | Why |
|---|---|---|---|
| ADM-REV-013 | "Select all shown" is an unlabelled checkbox in the table's header cell. | A labelled checkbox "Select all shown" in the toolbar, beside "Show reviewed" (desktop only, as the header). Same rule: every open flag, disabled with none, ticked when all are picked. | kit: `DashColumn` takes no header widget, and the kit's own `selectable` puts a box on every row and selects the page only. Kit candidate: a header builder on `DashColumn` (or a per-row `canSelect` + whole-list select-all on `selectable`). |
| ADM-REV-015 | The partial toast shows each refused id's server reason raw, English in the Arabic UI too. | The server's one sentence ("no such open flag in this org") has words in both languages (`access.review.pendingNotOpen`, English unchanged); any other server English reads `errors.unknown` on an Arabic screen. | English inside the Arabic UI is a web bug (SPEC 6.3); pinned by `ADM-REV-015 bulk resolve (divergence) Arabic …`. |
| ADM-REV-010 | One `useReviewFlag` mutation: pressing a second row's "Mark reviewed" while one is pending moves the spinner to the second row. | Each pending row keeps its own spinner until its own call ends. | Port the intent (spinner on the row being saved). |
| ADM-REV-001 (intent) | No `route-prefetch.ts` case for `/access/review`. | The route's `prefetch:` warms the open flags when the Access "Review" tab is rested on. Pinned by `review_prefetch_test.dart`. | Owner intent rule. |
| ADM-REV-009 raw key | The raw key is a `<bdi>` that wraps freely. | It wraps to 2 lines, then is cut with an ellipsis; holding it shows the whole key. | Rows keep a bounded height; 2 lines covers the long dotted keys. |
