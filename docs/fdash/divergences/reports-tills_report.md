# Reports / Till sessions (`/reports/tills`): differences from the web

| Row | Web | Flutter | Why |
|---|---|---|---|
| REP-TIL-001, REP-ALL-030 rights still loading | Page renders with the read disabled (empty sentence) while /authz/me is in flight. | Blank until rights are known; on failure the shell's error (shell.accessLoadError) with Retry. | App-wide SH-10 (shell-frame.md), fixed on the web in v1.4.27. Pinned by tills_report_test "(divergence SH-10)" tests. |
| REP-TIL-022 hour labels on a narrow plot | interval={2} at every width; labels overlap on a phone. | Every third hour; every sixth/twelfth when too narrow. | Overlapping axis text is unreadable (SPEC 6.3). |
| REP-TIL-010 variance tint | color-mix in oklab, 50% toward foreground. | Color.lerp of the same tokens at 50% (sRGB). | No OKLAB mix in Flutter; near-identical shade. |
| REP-TIL-004 cancelled save | Browser downloads; no cancel. | Cancelled save writes nothing, no toast. | Platform difference. |
| REP-TIL-015/024 phone breakpoint (kit) | Cards under 768 px. | Under 760 (DashDataTable). | Kit rule. |
| REP-ALL-015 page after refresh (kit) | Any data refresh returns to page 1. | Only a new search does. | Kit behaviour. |
| Mock: force-closed Expected | Backend force_close stores closing_cash_system. | Seed leaves it null; mock computes it the backend's way. | Keeps REP-TIL-012 true on seeded data. |
