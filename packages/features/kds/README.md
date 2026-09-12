# feature_kds

The kitchen board. A device, not a shell: a `kitchen`-role iPad on the pass
shows `KitchenDisplayScreen` and nothing else.

## What it draws

- One ink top bar: station · branch · live dot · open count · the outbox
  pill · settings.
- Tickets by station in an adaptive grid (four columns on an iPad landscape,
  one on a phone). Each card: the table label largest, the round, the age
  in mono, the lines with their check toggles, one **Bump all**.
- Age tint at 5 and 10 minutes; a fully bumped card turns green and carries
  a READY tag (the server closes it; the board is never a history).
- Banners for offline / reconnecting, and for taps the server refused
  (Retry · Discard). A refused tap also says so in a toast — never swallowed.

## Where the truth lives

`kdsList` in the core overlays the still-queued bumps from the outbox onto
the server feed, so any two readers of the core agree about every line.
`kdsRevisionProvider` is bumped after every mutation and every live
`kdsProvider(stationId)` reloads — the board and Queue's Kitchen segment
(routing mode `till`, mounted as `KdsBoardBody(stationId: null)`) therefore
show the same lines at the same moment, whichever screen bumped.

## Seeing it

```
flutter test test/kds_render_test.dart --dart-define=MADAR_RENDER=true
```

writes `build/render/kds-*.png`: iPad light, iPad dark, phone, and the
Arabic board mirrored.
