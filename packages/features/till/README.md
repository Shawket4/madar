# feature_till — the Till

Where the drawer lives. `TillScreen` is the teller shell's fourth tab (and
the manager's, listing every drawer at the branch). With no till it is the
open-till card; with one it shows the drawer's figures, the till's rows,
cash in / out (inline on an iPad, pushed on a phone) and Close till.

| Screen | Backed by |
|---|---|
| `TillScreen` | `currentTill/refreshTill`, `branchOpenTills`, `openBillsNotice`, `tillReport`, `listTillOrders` + `tillStats`, `listCashMovements`, `syncStatus`, `listTills` (managers) |
| `CashInOutPanel` / `CashMovementsScreen` | `recordCashMovement(signed, note)`, `listCashMovements` |
| `CloseTillScreen` | `tillReport` (expected cash), `closeTillPreview` (methods used, last-till warning), `closeTill(counted, note, reconciliation)` |
| `OpenTillScreen` | `suggestedOpeningCashMinor`, `checkTillElsewhere`, `openBillsNotice`, `openTill` → `OpenTillOutcome`, `forceCloseTill` |
| `TillSyncStrip` | `syncOnTillOpenStatus`, `syncNow` |
| `TillReportSheet` | `tillReport` / `tillReportFor`, `renderTillReport` |
| `TillHistoryScreen` | `listTills`, `tillReportFor`, `listOrdersForTill` |
| `DrawersCard` | `listTills`, `tillReportFor` — read-only |

Not built because the bridge cannot back it: a refunds card, a tips word, a
Safe drop chip, Correct › (linked reversal), Suggested safe drop. Each is noted where it would have been.

## Seeing it

```
flutter test test/till_render_test.dart --dart-define=MADAR_RENDER=true
```

writes `build/render/till-*.png`: the iPad Till (light, and offline in the
dark), a manager's Till, the no-till home, the close screen (short, and
matching), and the phone in Arabic. Look before you ship.
