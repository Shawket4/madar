# feature_shift — the Till

Where the drawer lives. `TillScreen` is the teller shell's fourth tab (and
the manager's, listing every drawer at the branch). With no shift it is the
open-shift card; with one it shows the drawer's figures, the shift's rows,
cash in / out (inline on an iPad, pushed on a phone) and Close shift.

| Screen | Backed by |
|---|---|
| `TillScreen` | `currentShift/refreshShift`, `listTills` + `deviceConfig().tillId`, `shiftReport`, `listShiftOrders` + `shiftStats`, `listCashMovements`, `syncStatus`, `listShifts` (managers) |
| `CashInOutPanel` / `CashMovementsScreen` | `recordCashMovement(signed, note)`, `listCashMovements` |
| `CloseShiftScreen` | `shiftReport` (expected cash + its arithmetic), `closeShift(counted, note)` |
| `OpenShiftScreen` | `suggestedOpeningCashMinor`, `openShift` |
| `ShiftReportSheet` | `shiftReport` / `shiftReportFor`, `renderShiftReport` |
| `ShiftHistoryScreen` | `listShifts`, `shiftReportFor`, `listOrdersForShift` |
| `DrawersCard` | `listShifts`, `shiftReportFor` — read-only |

Not built because the bridge cannot back it: a refunds card, a tips word, a
Safe drop chip, Correct › (linked reversal), Suggested safe drop,
Force-close. Each is noted where it would have been.

## Seeing it

```
flutter test test/till_render_test.dart --dart-define=MADAR_RENDER=true
```

writes `build/render/till-*.png`: the iPad Till (light, and offline in the
dark), a manager's Till, the no-shift home, the close screen (short, and
matching), and the phone in Arabic. Look before you ship.
