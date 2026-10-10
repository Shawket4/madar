# setup / brand_appearance: divergences from the web

Unit: `/settings` Appearance, `/settings/brand` Brand, the settings shell (SET-APP, SET-BRD, SET-SHL).

| Row | Web | Flutter | Why |
|---|---|---|---|
| SET-BRD-015 | `form.reset` runs whenever the saved links change, even while the person is typing. | The form re-seeds from the saved links only until the person edits; a save clears the edit so the re-read re-seeds it. | Brief rule: a background refresh never overwrites an edit in progress (the web's reset loses typing). |
| SET-BRD-021 | A file can be dragged onto the box (border turns primary; a dropped `image/*` of any type is sent; a drop during an upload is ignored). | Picker only. The same file can be picked again; a cancelled pick sends nothing. The desktop picker offers png/jpeg/webp, like the web's accept list; the phone gallery picker cannot filter by type. | Platform/kit: `DashImageUploader` has no drop target and the app has no desktop drop dependency. Kit candidate. |
| SET-BRD-007 | The Replace overlay also shows on keyboard focus (`focus-within`). | The kit's uploader shows it on hover, and always on touch devices. | Kit (`DashImageUploader`); reported, not forked. |
| SET-BRD-002 / SET-SHL-020 | No org in scope: the uploaders stay live and an upload goes to `/orgs//logo` and fails. | The uploaders are disabled until an org is picked. | Web defect: a request with an empty id. |
| SET-BRD-018 | The stamp row's `aria-label` is English in every language ("3 of 5 collected"). | The stamp row is hidden from screen readers; the figure and its translated "of 5 orders" line are read as one. | Web defect: English inside the Arabic UI. |
| SET-BRD-018 | Letter-spacing (tracking) on the program name and the member labels in every language. | No tracking in Arabic. | Tracking pulls Arabic letters apart and breaks their joins. |
| SET-BRD-018 | (inventory) "logo repainted in the foreground colour when `brand_logo_is_mark`". | The logo always sits on a white plate, as `card-face.tsx` does at v1.4.18 and today. | Inventory correction, not a divergence: the web source wins. |
| SET-BRD-011 | The root domain comes from `VITE_API_URL`, else the dashboard's own hostname. | From the app's `MADAR_API` define (default `https://api.madar-pos.cloud`); no hostname fallback. | Platform: an app has no page hostname. |
| SET-SHL-021 | Table search eligibility is decided by the first row's value types (TanStack's default), so a column can silently stop being searchable. | Every column with text is searched, whatever the first row holds. Pinned by `SET-SHL-021 (divergence)` (kit `DashDataTable` behaviour). | Web defect: search results depend on row order. |
| SET-BRD-017 (resolved, B3) | `PATCH /orgs/{id}` with nothing but `social_links` (and/or `logo_url`) is the org's own to save: `org.settings.edit` in the caller's own org. Any other field stays super-admin only (`UpdateOrgRequest::brand_only`, MadarRust c1abad9). | The same: the owner's links Save lands. Both mocks (setup's and admin's) apply the server's rule through the core mock's `requireOrgPatch`. Pinned by `SET-BRD-017 the owner saves (B3)` and the two mock tests (`PATCH (B3)`, admin's `the mock's PATCH /orgs/{id}`). | Owner answer 2026-10-10. Not a divergence: the web and the server agree. |

| SET-SHL-013 (brand) | `route-prefetch.ts` has no case for `/settings/brand`: pointing at it warms nothing. | Pointing at the Brand rail row, picker option or palette row warms `GET /orgs/{id}` when an org is in scope; opening it asks nothing more. | Intent beyond the web (owner rule). |
