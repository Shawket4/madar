# Setup / Links & QR codes (`/settings/links-qr`): differences from the web

The merged page of the web's da5faf63 (2026-11-06): the links page editor, the menu without prices
and every QR code under one set of output switches. Its codes' rows are in `setup-qr.md`, the links
editor's in `setup-links.md`.

| Row | Web | Flutter | Why |
|---|---|---|---|
| SET-LQR-001 chips | 32 px pills (`h-8`). | 44 px pills (`DashMetrics.control`). | The 44 pt touch-target rule. |
| SET-LQR-002, 003 scrolling | `scrollIntoView({block: "start"})` with `scroll-mt-4` (16 px above the section). | `Scrollable.ensureVisible` to the section's top edge (no 16 px margin); the chip's scroll eases over 320 ms (none under reduced motion), a `?section=` landing jumps. | The shell's scroller has no scroll-margin; the section headers carry their own top space. |
| SET-LQR-004 redirect query | TanStack's `redirect({search: {section: "codes"}})`. | The generated legacy redirect carries a fixed `set: {section: codes}` (`LegacyRedirect.set`, new): `gen_dashboard_nav.mjs` now tells a search value the redirect sets itself from one it keeps (a probe value). | The nav generator used to read any search on a redirect as "keys kept", which would have dropped `section=codes`. |
| SET-LQR-005 nav generation | The web's nav has since moved Settings › Loyalty into Rewards by Madar (`/rewards/*`, 656ef339, 2026-10-23), which this app has not ported. | `gen_dashboard_nav.mjs` leaves the web-only `/rewards` pages out (`WEB_ONLY`, now a path or anything under it) and keeps Loyalty where it was (`FLUTTER_KEEPS`: the Setup leaf after Branch setup, the Ways to sell pane after Bookings, its redirect to `/rewards/programme` dropped). So the rail here reads Delivery, Bookings, Loyalty, Links & QR codes. | Regenerating straight from the web would have put six dead Rewards links in the sidebar and sent Loyalty to a page that does not exist here. Drop both entries when Rewards is ported. |
| SET-LQR-007 prefetch | Warms the menu-display read, the links page read (`branding`) and the tables (`online`, with a branch). | Also warms the public links page the editor's preview reads (with `branding`), so the section opens whole from the cache. | The app's prefetch rule warms a page's first-mount reads; the preview is one. |
