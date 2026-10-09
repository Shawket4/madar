# Setup / Bookings (`/settings/bookings`): differences from the web

One line per difference: what the web does, what Flutter does, why. Rows marked "question" port
the web's behaviour as it is and ask the owner whether it is intended.

| Row | Web | Flutter | Why |
|---|---|---|---|
| SET-BKG-004 / 019 | A failed or refused settings read leaves the dialog on "Loading…" for ever (no error, no words, Save disabled). | The server's words with Retry inside the dialog (Save stays disabled); Retry asks again. Tests `SET-BKG-004 (divergence)`, `SET-BKG-019 (refusal)`. | A spinner that never ends hides a refusal; same choice as sell's dialog (SELL-BKG-079). |
| SET-BKG-017 | The dialog is not keyed by branch, so after picking another branch "Edit rules" opens on the previous branch's draft (Save enabled) until the new read lands, and a Save in that window PUTs the previous branch's whole settings. | Every open is a fresh dialog keyed by the branch: "Loading…" until that branch's read arrives; it can only save that branch. | The inventory's corrected row: a stale draft saved over another branch is a defect. |
| SET-BKG-020 | Any change of the read (a `booking.*` event while open) overwrites the draft, edits included. | The draft follows a refreshed read only until the person edits; after that their edits are kept. | The brief: a form seeded from cached data re-seeds until edited (a re-copy would silently drop typing). |
| SET-BKG-014 | `await invalidateBookings()` then close; the invalidation runs only if the save resolved inside the still-mounted dialog. | `/bookings` and `/floor` are invalidated through the realtime bus unconditionally after the PUT, before the toast and the close. | The brief's mutation rule (never behind `mounted`). |
| SET-BKG-010 | `type="number"` inputs accept a minus sign or decimals (the server then refuses). | Digits only. | Every field is a whole, non-negative number on the wire; same as sell's dialog. |
| seam | One dialog component shared by the Bookings page and this pane. | `dashboard_setup` cannot import `dashboard_sell`, so the pane has a local port (`booking_rules_dialog.dart`, provider `bookingRulesProvider`, same request and key). Integration seam: a `bookingSettings` opener in dashboard_core's `AreaOpeners` (like `customerSheet`) would let both pages open sell's one dialog. | Package boundaries; logged for the foundation. |
| prefetch | `route-prefetch.ts` has no case for `/settings/bookings`. | No `prefetch:`; "Edit rules" warms the dialog's read on intent (owner rule). | Ported. |
| SET-BKG-010 / 011 | The numbers are `type="number"` boxes with no length limit (the largest valid value is 2880). | Digits only, at most six (every valid value fits); a longer paste stops at six instead of overflowing the parse. Test `SET-BKG-010 SET-BKG-011`. | A 20-digit paste crashed the parse; six digits never refuse a value the server accepts. |
