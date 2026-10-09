# Inventory ▸ Today: divergences from the web

Web: `src/features/inventory/today-page.tsx` (v1.4.18; unchanged at v1.4.20). Flutter:
`packages/dashboard_features/inventory/lib/src/today/`. Tests named `(divergence)` pin each fix.

| Row | Web | Flutter | Why |
|---|---|---|---|
| INV-ALL-024 | "View all" (→ `/inventory/ingredients`) and "Count this branch's stock" (→ `/inventory/counts`) navigate without search params, so the branch falls back to All branches and the period to the default. | The scope (branch, period) is kept: it lives in the shell's scope provider, not the URL. | Likely a web bug (the inventory marks it a quirk to reproduce only if the owner confirms). |
| INV-ALL-006 | No route guard: typing `/inventory/today` without `inventory.read` renders the page and every read shows its own 403 state. | The shell's route gate (`DashRoute.caps`, owned by the shell) shows `Restricted` and reads nothing. A 403 the server sends anyway still shows its words in the low-stock table (pinned). | Shell-wide rule (same as Ingredients); not this unit's to change. Question for the owner. |
| INV-TOD-010 | The four KPI cards stagger in, 50 ms apart (`staggerContainer(0.05)` + `listItem`: 160 ms, 6 px rise). | The strip fades up 6 px in 160 ms as one piece. | Kit: `DashLedgerStrip` takes data items, not widgets, so a per-card delay needs a kit change (kit candidate). |
| INV-TOD-011, -022 | The section header is `items-end` with a 32 px `sm` trailing control, so "View all" and "Log waste" sit level with the title. | The kit's compact button is 44 pt (tap-target rule), so the trailing control rises ~10 px above the title's baseline. The Arriving header is held to the same 44 pt so the two side-by-side titles still line up. | Kit: `DashSectionHeader` end-aligns a taller trailing control (kit candidate: centre it on the title). |
| INV-TOD-038 | (question) The day bounds are memoized on the timezone only: a page left open across midnight keeps yesterday's deliveries cutoff and waste start until it is reopened. | Ported as is (`todayBoundsProvider` reads the clock once per visit, recomputed on a zone change). | Looks like a web oversight, but it is the recorded behaviour; question for the owner. |
| INV-TOD-032 KPIs at 1024 (kit) | `lg:grid-cols-4` goes by the screen width: 4 KPIs in one row at 1024. | The kit's `DashLedgerStrip` counts columns by its own width: 2×2 at 1024. Pinned by the tablet test. | Kit limit; fix in the kit sweep. |
| INV-TOD-020 / INV-TOD-026 failed background refresh | A failed refresh after the list loaded replaces the list with the error. | The rows stay; the error shows only while `failedFirst`. | Core loading/error rule (SPEC 6.1). |
