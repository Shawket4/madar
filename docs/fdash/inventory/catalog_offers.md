# Catalog offers area: web parity inventory

Area package: `packages/dashboard_features/catalog_offers` (`dashboard_catalog_offers`).
Pages: `/menu/combos`, `/menu/combos/:comboId` (`new` creates), `/menu/deals`, `/discounts`.

Web reference: `/Users/shawket/Desktop/Madar/MadarDashboard`, branch `main` @ `fc2faa42` (v1.4.18). Read-only.
Backend checked for capability gates and list semantics: `/Users/shawket/Desktop/Madar/MadarRust`
(`src/combos/handlers.rs`, `src/combos/routes.rs`, `src/deals/handlers.rs`, `src/discounts/handlers.rs`,
`src/discounts/wire.rs`, `src/menu/handlers.rs` (delete), `src/uploads/handlers.rs` (image), `src/errors.rs`,
`src/permissions/checker.rs`).

## How to read a row

`| id | behaviour | API call | gate | i18n keys | web source |`

- **API call**: method + path + operationId (= the `dashboard_api` method name). "none" = no request.
- **gate**: what the web hides/disables client-side, then (after "server:") what the backend refuses with a 403.
  Capabilities are the dotted keys (`menu.items.read`); the legacy pair the server checks is in brackets.
- **i18n keys**: `key` "English as in en.json". Every key listed exists in both `en.json` and `ar.json`
  (checked one by one, section 4) unless flagged.
- **web source**: `file:line`, relative to `MadarDashboard/src/`. Abbreviations:
  `cp` = `features/combos/combos-page.tsx`, `ce` = `features/combos/combo-editor-page.tsx`,
  `se` = `features/combos/slots-editor.tsx`, `we` = `features/combos/windows-editor.tsx`,
  `ep` = `features/combos/economics-panel.tsx`, `cfs` = `features/combos/form-schema.ts`,
  `cu` = `features/combos/util.ts`, `capi` = `features/combos/api.ts`, `mo` = `features/combos/use-menu-options.ts`,
  `dp` = `features/deals/deals-page.tsx`, `dd` = `features/deals/deal-dialog.tsx`,
  `dfs` = `features/deals/form-schema.ts`, `pe` = `features/deals/pool-editor.tsx`, `du` = `features/deals/util.ts`,
  `xp` = `features/discounts/discounts-page.tsx`, `xd` = `features/discounts/discount-dialog.tsx`,
  `xu` = `features/discounts/util.ts`, `dt` = `components/app/data-table.tsx`.
- Toasts are sonner `toast.success` / `toast.error`. A failed mutation toasts `getErrorMessage(e)` (OFFR-ALL-004)
  unless the row says otherwise.
- Web tests that pin a row are named in the behaviour cell ("Test: …").

## Contents

| § | Page | Rows |
|---|---|---|
| 0 | Area-wide (nav, module gate, tables, errors, caching) | OFFR-ALL-001 – 019 (015–019 critic) |
| 1 | `/menu/combos` Combos list | OFFR-CMB-001 – 037 (034–037 critic) |
| 2 | `/menu/combos/:comboId` Combo editor (+ slots, choices, windows, price check, save bar) | OFFR-CED-001 – 089 (081–089 critic) |
| 3 | `/menu/deals` Deals list + deal dialog (+ pool editor) | OFFR-DEA-001 – 050 (048–050 critic) |
| 4 | `/discounts` Discounts list + discount dialog + export | OFFR-DSC-001 – 045 (040–045 critic) |

Total: 240 rows (213 original + 27 added by the critic pass; 5 rows corrected, see section 8).

---

## 0. Area-wide

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-ALL-001 | Sidebar group "Catalog" holds the parent "Menu" (icon UtensilsCrossed, basePath `/menu`, active for any `/menu/*` path) whose leaves, in order, are Items, Choice groups, **Combos** (icon Sandwich, `/menu/combos`), **Deals** (icon TicketPercent, `/menu/deals`), Pricing & Availability, Recipe bases, Packaging rules; then the top-level leaf **Discounts** (icon BadgePercent, `/discounts`) in the same group. The parent shows only when one of its leaves is visible. Same entries in the command palette. | none | Combos and Deals leaves: `menu.items.read`; Discounts leaf: `discounts.read`; all module `pos` | `nav.catalog` "Catalog", `nav.menu` "Menu", `nav.combos` "Combos", `nav.deals` "Deals", `nav.discounts` "Discounts" | `config/nav.ts:99-122` |
| OFFR-ALL-002 | Module gate. Every path of the area (and `/menu/combos/<id>` by prefix) belongs to module `pos`. POS switched off for the org → EmptyState (icon Blocks) "Not part of this business's plan" / "Madar POS is switched off for this business. Ask Madar to switch it on."; modules not known yet → blank body; modules read failed → ErrorState "Couldn't check what this business has switched on" + server message + Retry. Nav leaves are also hidden when the module is off. | GET `/orgs/{orgId}/modules` getOrgModules (shell) | module `pos` | `dawam.moduleOffTitle`, `dawam.modulePosOff`, `dawam.modulesLoadError`, `common.retry` "Retry" | `components/app/module-gate.tsx:17-51`; `config/nav.ts:277-298` |
| OFFR-ALL-003 | Before the person's rights are known (`authz.ready` false) no page shows its Restricted state; the combos list, the combo editor and the deals page ask for nothing until `can(menu.items.read)` is true. A platform admin holds every right. | GET `/authz/me` getMyAuthz (shell) | none | none | `data/authz/use-authz.ts:50-78,112-141`; `cp:52,73`; `ce:84,88-89`; `dp:38,41-42` |
| OFFR-ALL-004 | Failed-mutation wording (`getErrorMessage`): a coded refusal reads `errors.codes.<CODE>` in the user's language (with `vars`; `vars.field` re-worded by the caller's `fieldLabel`); an uncoded 429 → "Too many requests just now. Try again in a moment."; an uncoded 403 → "You don't have permission to perform this action."; otherwise the server's `error` text with its "Kind: " prefix stripped, or `message`; no response → "Network error — please check your connection."; 401 → session expired; 404 → "Not found.". | n/a | none | `errors.codes.*`, `errors.tooManyRequests`, `errors.unauthorized`, `errors.networkError`, `errors.sessionExpired`, `errors.notFound` | `data/api/errors.ts:97-175` |
| OFFR-ALL-005 | Query defaults: stale after 30 s, kept 5 min, NO refetch on window focus; retry never on 401/403/404/422, a 429 up to 3 times (2 s, 4 s, 8 s), anything else once; mutations never retried. The price-check query has `retry: false`. Menu options (items, categories, branches) are stale after 5 min. | n/a | none | none | `data/api/query.ts:9-49`; `capi:85`; `mo:61-63` |
| OFFR-ALL-006 | (corrected) Live updates: the area's own reads (combos, deals, discounts, menu items, categories) are not in the branch realtime event map; only a `resync` frame (invalidates every query) refreshes them. BUT the shell's one stream (for the scope branch, mounted in `routes/_app/route.tsx:52`) invalidates `/branches` on `branch.settings_changed`, so the branch pick list refetches live: branch names in the deal dialog's Branches rows, the windows' Branch selects, the deals "When" column and the price check's "Prices at {{branch}}" line follow it. No polling, except a still-processing image (OFFR-ALL-016). | none | none | none | `data/realtime/use-branch-realtime.ts:51-63`; `mo:63` |
| OFFR-ALL-007 | `invalidateCombos()` after ANY combo, deal or deal-branch write: invalidates every query whose first key starts with `/combos`, `/deals`, `/settings/combos`, `/reports/bundles`, `/menu-items`, `/costing` (so the combos list, a combo, the price check, the deals list, the combo settings, the Bundles report, menu items and costing all refetch). | n/a | none | none | `cu:162-171` |
| OFFR-ALL-008 | `invalidateDiscounts()` after any discount write: every query whose first key starts with `/discounts`. | n/a | none | none | `xu:7-10` |
| OFFR-ALL-009 | Desktop table (shared DataTable): sticky header (11 px uppercase muted labels), 56 px rows, no zebra, hover wash; a clickable row is focusable and Enter or Space opens it; numeric columns (`meta.numeric`) are mono, tabular, end-aligned, bidi-isolated; trailing row-action cell (`sr-only` header "Actions") whose clicks never open the row; no column sorting anywhere in this area (headers are plain text). | none | none | `common.actions` "Actions" | `dt:281-322,437-541` |
| OFFR-ALL-010 | "Columns" menu (desktop only, outline button with sliders icon, end-aligned in the table toolbar): a checkbox per column that has a `meta.label`; unticking hides that column (not persisted). | none | none | `common.columns` "Columns" | `dt:356-377` |
| OFFR-ALL-011 | Phone layout (web breakpoint < 768 px; Flutter < 760): each row becomes a card; the column marked `phone: "title"` (else the first) leads in 16 px semibold; the row actions sit top-end; the other cells follow as label/value pairs in two columns (label = `meta.label` or the header text); the whole card is one tap target that opens the row; loading = 4 skeleton cards; the Columns menu is hidden. | none | none | none | `dt:231-279,386-427`; `hooks/use-mobile.ts:3` |
| OFFR-ALL-012 | (corrected) Table states: loading → skeleton rows (min(page size, 6), desktop); error → ErrorState, EVEN when rows were already shown (a failed background refetch, after its one retry, replaces the loaded rows with the error state: the table is fed `query.error`, which React Query sets while keeping the old data) → "Couldn't load this" + server message + Retry (refetches); zero rows → the page's `emptyState` (or "No results found" when none given). Error wins over empty. | none | none | `common.loadFailed` "Couldn't load this", `common.retry` "Retry", `common.noResults` "No results found" | `dt:217-229,382-385`; `components/app/empty-state.tsx:54-81` |
| OFFR-ALL-013 | Pagination footer (only when more than one page and no error): "Page {{current}} of {{total}}" + Previous / Next icon buttons (chevrons mirrored in RTL), disabled at the ends. | none | none | `common.page` "Page {{current}} of {{total}}", `common.previous` "Previous", `common.next` "Next" | `dt:553-585` |
| OFFR-ALL-014 | Confirm dialog (shared): modal alert dialog; destructive confirms show a red warning badge; title, description, Cancel ("Cancel") and the confirm button (red when destructive). Esc, outside click and Cancel all resolve "no" and nothing happens. | none | none | `common.cancel` "Cancel", `common.confirm` "Confirm" | `components/app/confirm-dialog.tsx:33-95` |
| OFFR-ALL-015 | (critic) Client-paginated tables (Deals, Discounts; 10 per page) jump back to page 1 whenever the list data changes: any refetch that returns different rows (after a create, an edit, a delete, a discount status toggle, a `resync`) resets the page index (TanStack `autoResetPageIndex`, on because their pagination is not manual); a change of the discount search resets it too. The combos list (server pagination, manual) keeps its page. Test: toggle a discount's status on page 2 → the table is back on page 1. | none | none | none | `dt:150-175`; `@tanstack/table-core` `RowPagination._autoResetPageIndex` (fired by `getCoreRowModel` / `getFilteredRowModel`) |
| OFFR-ALL-016 | (critic) Images on the asset pipeline (`AssetImage`): a ready asset shows its `tile` variant (else `thumb`, else `full`) with a srcset, lazily; no asset → the legacy URL; an asset still `{status: "processing", job_id}` shows a skeleton in its tile and polls GET `/assets/jobs/{job_id}` every 3 s for at most 60 s; when the job ends (done or failed) EVERY query is invalidated (the page refetches) and a done job's variants show at once. Used by the combos list thumbnail (`sizes="128px"`). Mock: GET `/assets/jobs/{id}` → `{id, status: queued/running/done/failed, result, error}`. | GET `/assets/jobs/{id}` (hand-written `customInstance`, not in the generated client) | none | none | `components/app/asset-image.tsx:50-152`; `cp:115-116` |
| OFFR-ALL-017 | (critic) An open deal or discount dialog re-seeds its form from the list row whenever that row object changes (the reset effect depends on `[open, deal / discount]`): a background refetch that brings changed data while it is open (a `resync` frame; React Query's `refetchOnReconnect` and refetch-on-mount-when-stale are left on) throws away what was being typed. The combo editor does not (it seeds once per combo id, OFFR-CED-006). Reproduce: re-seed when the row's VALUE changed (React Query keeps the same object when the data is equal). | none | none | none | `dd:79-81`; `xd:52-66`; `dp:46`; `xp:45`; `data/api/query.ts:37-48` |
| OFFR-ALL-018 | (critic) While the person's rights are not known yet (`authz.ready` false: a first sign-in with no grants remembered in local storage; otherwise the last answer is replayed at once): the combos list asks nothing and shows the "No combos yet" empty state with no New combo button; the deals page shows "No deals yet" with no New deal; an existing combo's editor shows the error state "Couldn't load this combo" with no message and a Retry (pressing it fetches the combo anyway); `/discounts` is unaffected (no capability check). Each switches to the real page when `/authz/me` answers. | none (Retry: GET `/combos/{id}`) | none | `combos.empty`, `deals.empty`, `combos.loadError`, `common.retry` | `cp:73,194`; `dp:41,165`; `ce:88,195-218`; `data/authz/use-authz.ts:106-141` |
| OFFR-ALL-019 | (critic) Deal and discount dialogs: Enter in a text field submits the form (the discount form still runs the browser's own min/max/step check first, OFFR-DSC-030); Cancel, the × (top end, accessible name "Close") and Esc stay active while a save runs: closing mid-save lets the request finish, and its toast, the list refresh (and, for a deal, the branch calls) still happen. | none | none | `common.close` "Close" | `dd:133,340-349`; `xd:86-130`; `components/ui/dialog.tsx:76-83` |

---

## 1. Page `/menu/combos` (Combos list)

| Field | Value |
|---|---|
| Web path | `/menu/combos` (file route `/_app/menu/combos`), no search params of its own. |
| Title | `combos.title` "Combos"; sidebar `nav.combos` "Combos". Description `combos.subtitle` "Meal deals and fixed bundles: a set price for items picked from slots. Each item keeps its own recipe, station and stock." |
| Web files read | `routes/_app/menu/combos.tsx`, `features/combos/combos-page.tsx` (+ `combos-page.test.tsx`), `features/combos/api.ts`, `types.ts`, `util.ts`, `components/app/data-table.tsx`, `empty-state.tsx`, `status-pill.tsx`, `confirm-dialog.tsx`, `restricted.tsx`, `asset-image.tsx`, `page.tsx`, `lib/format.ts`, `lib/translation.ts`, `lib/use-debounced.ts`, `config/nav.ts`, `data/authz/use-authz.ts`, `generated/capabilities.ts`, generated `api.ts` + models (`ListCombosParams`, `ComboSummary`, `PaginatedCombos`); backend `combos/handlers.rs:500-560`, `menu/handlers.rs:1520-1530`. |
| Capabilities | Nav: `menu.items.read`. Page: `<Restricted>` without `menu.items.read`. In-page: New combo + row Edit/Delete need `menu.combos.edit`; "Channels and margin" link needs any of `org.settings.read`, `menu.combos.edit`. Server: list `menu.items.read`; delete is a menu-item delete = `menu.items.delete` [menu_items:delete] (NOT `menu.combos.edit`). |
| Module | `pos`. |
| Realtime | None (OFFR-ALL-006). |
| Generated API hooks / ops | `listCombos` (via `useCombos`, key `["/combos", params]`), `useListCategories` (`listCategories`, key `["/categories", {org_id}]`), `deleteMenuItem` (via `deleteCombo`). |
| Invalidated after mutations | Delete → `invalidateCombos()` (OFFR-ALL-007). |

### Endpoints

| # | Method + path | operationId | Params / body | Enabled when | Server gate |
|---|---|---|---|---|---|
| C1 | GET `/combos` | `listCombos` | `q` (debounced search, omitted when empty), `category_id` (omitted for all), `is_active` (true/false, omitted for both), `page` (1-based), `per_page` = 25 | `menu.items.read` AND an org in scope | `menu.items.read`; org from the token |
| C2 | GET `/categories` | `listCategories` | `org_id` | same | menu read |
| C3 | DELETE `/menu-items/{id}` | `deleteMenuItem` | none | on confirm | `menu.items.delete` [menu_items:delete] |

Backend semantics for the mock: C1 returns `{data, page, per_page, total, total_pages}` of `ComboSummary`
(`id, name, name_translations, category_id, image_url, image?, price (piastres), slot_count, is_fixed, is_active,
available_now, margin_default ("0.5933" string or null), warning_count, window_count`); only `kind = combo`,
not deleted; `q` matches the English name OR the Arabic name (case-insensitive, `%`/`_` escaped); ordered by
name then id; `per_page` clamped 1–200.

### Rows

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-CMB-001 | Opening `/menu/combos` (nav leaf "Combos" under Catalog ▸ Menu) renders the list page inside the shell. | none | nav `menu.items.read`, module `pos` | `nav.combos` "Combos" | `routes/_app/menu/combos.tsx:5-7`; `config/nav.ts:114` |
| OFFR-CMB-002 | Without `menu.items.read` (once rights are known): page header "Combos" and a lock EmptyState "Not available on this account" / "Your account can't see the menu. The owner can give you access."; no filters, no table, and NO request is made (list disabled). Test: "without menu.items.read: shows the restricted state and fetches nothing". | none | `menu.items.read` | `combos.title` "Combos", `common.restrictedTitle` "Not available on this account", `combos.noAccess` "Your account can't see the menu. The owner can give you access." | `cp:190-192`; `components/app/restricted.tsx:18-33` |
| OFFR-CMB-003 | Header: title "Combos" and the description sentence. | none | `menu.items.read` | `combos.title`, `combos.subtitle` | `cp:200-205` |
| OFFR-CMB-004 | Ghost button "Channels and margin" with a trailing arrow (arrow mirrored in RTL) navigates to `/settings/combos` (Settings ▸ Combos and deals, setup area). Hidden for people with neither right. | none | any of `org.settings.read`, `menu.combos.edit` | `combos.channelsLink` "Channels and margin" | `cp:54,208-215` |
| OFFR-CMB-005 | Primary button "+ New combo" opens the editor at `/menu/combos/new`. Hidden without `menu.combos.edit`. Test: "with menu.items.read only … offers no New combo"; "with menu.combos.edit as well: offers New combo". | none | `menu.combos.edit` | `combos.new` "New combo" | `cp:53,216-220` |
| OFFR-CMB-006 | Search box under the header (search icon at the start; full width on phone, 240 px from 640 px): placeholder and accessible name "Search combos". Typing is debounced 300 ms, then sent to the server as `q` (empty → omitted). Server matches English or Arabic name. | GET `/combos` listCombos (`q`) | `menu.items.read` | `combos.searchPlaceholder` "Search combos" | `cp:56-57,225-234` |
| OFFR-CMB-007 | Category filter (select, accessible name "Category"): first option "All categories", then every category of the org by its translated name (Arabic name in Arabic when present). Choosing one sends `category_id`; "All categories" omits it. | GET `/combos` listCombos (`category_id`); GET `/categories` listCategories | `menu.items.read` | `combos.allCategories` "All categories", `combos.col.category` "Category" | `cp:58,74,235-247` |
| OFFR-CMB-008 | Status filter (select, accessible name "Status"): "Active and inactive" (default, omits `is_active`), "Active" (`is_active=true`), "Inactive" (`is_active=false`). | GET `/combos` listCombos (`is_active`) | `menu.items.read` | `combos.allStatuses` "Active and inactive", `common.active` "Active", `common.inactive` "Inactive", `combos.col.status` "Status" | `cp:59,248-257` |
| OFFR-CMB-009 | Any change to the (debounced) search, the category or the status returns to page 1. | GET `/combos` (`page=1`) | none | none | `cp:60-61` |
| OFFR-CMB-010 | The list request: 25 per page, page from the footer; asked only with `menu.items.read` and an org in scope; rows come in the server's order (name A→Z). Test asserts `{ enabled: true }` with the right. | GET `/combos` listCombos | `menu.items.read` (client + server) | none | `cp:43,63-73`; `capi:59-64` |
| OFFR-CMB-011 | Column "Combo" (phone card title; not in the Columns menu): 40 px rounded tile with the combo image (asset variant, else legacy `image_url`) or a muted UtensilsCrossed icon; the English `name` in semibold (never translated, in both languages) followed by a secondary badge "Fixed" when `is_fixed`; under it the Arabic name (`name_translations.ar`, right-to-left, muted) when present. Test: the badge shows only on the fixed combo. | none | none | `combos.col.name` "Combo", `combos.fixed` "Fixed" | `cp:105-135` |
| OFFR-CMB-012 | Column "Category": the category's translated name, or "—" when none or unknown. | none | none | `combos.col.category` "Category" | `cp:75-78,136-141` |
| OFFR-CMB-013 | Column "Price" (numeric): `fmtMoney(price)` in semibold. Test: `fmtMoney(15000)` shown. | none | none | `combos.col.price` "Price" | `cp:142-147` |
| OFFR-CMB-014 | Column "Slots" (numeric): `slot_count`. | none | none | `combos.col.slots` "Slots" | `cp:148-153` |
| OFFR-CMB-015 | Column "Margin" (numeric): when `warning_count > 0` a small amber pill with a warning triangle "{{count}} warnings" (plural: "1 warning"; Arabic six forms), then the default margin `fmtRate(margin_default)` ("60%", "—" when null). Test: the chip "2 warnings" shows only on the combo with warnings. | none | none | `combos.col.margin` "Margin", `combos.warningCount` (`_one` "{{count}} warning", `_other` "{{count}} warnings") | `cp:154-171`; `cu:68-78` |
| OFFR-CMB-016 | Column "Status": inactive → neutral pill "Inactive"; active and `available_now` → green pill "On sale now"; active but not now (outside its windows / nothing sellable) → accent pill "Not on sale now". | none | none | `combos.col.status` "Status", `common.inactive` "Inactive", `combos.availableNow` "On sale now", `combos.notNow` "Not on sale now" | `cp:172-185` |
| OFFR-CMB-017 | Clicking a row (or Enter/Space on a focused row; tapping a phone card) opens `/menu/combos/{id}` for EVERY reader; without `menu.combos.edit` the editor opens read-only (OFFR-CED-013). | none | `menu.items.read` | none | `cp:80,269` |
| OFFR-CMB-018 | Row action pencil (accessible name "Edit") opens the editor for that combo. | none | `menu.combos.edit` | `common.edit` "Edit" | `cp:270-275` |
| OFFR-CMB-019 | Row action trash (red, accessible name "Delete") opens the confirm: title "Delete {{name}}?" (the combo's name in the current language: Arabic name in Arabic when present), body "It leaves the menu at every branch and on every channel. Past orders keep their lines and still show in the Bundles report.", red confirm "Delete". Test: two Delete buttons with the right. | none | `menu.combos.edit` | `combos.deleteTitle` "Delete {{name}}?", `combos.deleteBody`, `common.delete` "Delete" | `cp:82-92,276-284` |
| OFFR-CMB-020 | Cancelling the delete confirm (Cancel, Esc, outside) does nothing: no request, no toast. | none | none | `common.cancel` | `cp:93` |
| OFFR-CMB-021 | Confirming the delete: the combo is deleted as a menu item; success toast "Combo deleted"; `invalidateCombos()` refetches the list (and every other combos/deals/menu-items read). | DELETE `/menu-items/{id}` deleteMenuItem | client `menu.combos.edit`; server `menu.items.delete` [menu_items:delete] | `combos.deleted` "Combo deleted" | `cp:94-97`; `capi:76` |
| OFFR-CMB-022 | Delete refused or failed → error toast with `getErrorMessage` (a combos-only editor without `menu.items.delete` gets the uncoded 403 → "You don't have permission to perform this action."). The row stays. | DELETE `/menu-items/{id}` | as above | `errors.unauthorized` (and any coded message) | `cp:98-100` |
| OFFR-CMB-023 | Without `menu.combos.edit`: no "New combo", no Edit/Delete row actions (the empty action cell remains), no button in the empty state. Test: "offers no New combo … no Delete". | none | `menu.combos.edit` | none | `cp:216,270-287,305` |
| OFFR-CMB-024 | Server pagination: page count = `total_pages`; footer "Page N of M" with Previous/Next only when `total_pages > 1` (OFFR-ALL-013); Next/Previous ask for the next/previous page with the same filters. | GET `/combos` listCombos (`page`) | none | `common.page`, `common.previous`, `common.next` | `cp:194-195,288-291` |
| OFFR-CMB-025 | Empty, no filter in use: EmptyState (icon UtensilsCrossed) "No combos yet" / "A combo sells several items at one price: a burger meal with a side and a drink, or a coffee and a cake." + "+ New combo" button (with `menu.combos.edit`) opening `/menu/combos/new`. | none | button: `menu.combos.edit` | `combos.empty` "No combos yet", `combos.emptyHint`, `combos.new` | `cp:292-312` |
| OFFR-CMB-026 | Empty with a search, category or status filter in use: "No combo matches these filters", no description, no button. | none | none | `combos.emptyFiltered` "No combo matches these filters" | `cp:196,295-310` |
| OFFR-CMB-027 | Loading (first load of a page/filter): skeleton rows in the table grid (phone: 4 skeleton cards). | none | none | none | `cp:265`; `dt:324-332,388-389` |
| OFFR-CMB-028 | List failed: ErrorState "Couldn't load this" + the server's words + Retry (refetches C1). | GET `/combos` (retry) | none | `common.loadFailed`, `common.retry` | `cp:266-267`; `dt:217-224` |
| OFFR-CMB-029 | Columns menu (desktop): Category, Price, Slots, Margin, Status can be hidden; Combo cannot. | none | none | `common.columns` + the column labels | `cp:139,145,151,157,175`; `dt:356-377` |
| OFFR-CMB-030 | Phone (< 760 Flutter / < 768 web): filters wrap, search full width; each combo is a card titled by the Combo cell (thumbnail, name, Fixed badge, Arabic line) with Edit/Delete top-end and Category, Price, Slots, Margin, Status as label/value pairs; tapping the card opens the editor. | none | none | as above | `cp:108,225`; `dt:231-279,386-427` |
| OFFR-CMB-031 | No org in scope (platform admin who has not picked an org): the list is never asked, so the page shows the "No combos yet" empty state (not an error). Web quirk; reproduce. | none | none | `combos.empty`, `combos.emptyHint` | `cp:73-74,194` |
| OFFR-CMB-032 | Arabic UI: header, filters, columns, pills in Arabic; the combo name column still shows the English `name` as its main line with the Arabic name under it; category names and the delete confirm name use the Arabic translation. Money and percentages keep Latin digits (section 1.1). | none | none | Arabic of every key above | `cp:76,83,123-130` |
| OFFR-CMB-033 | The list is reached from elsewhere: Menu ▸ Items opens a combo-kind item in this editor (`/menu/combos/{id}`), and the menu studio's "Meal" section links to `/menu/combos` and to a combo (catalog_menu area). Deep links `/menu/combos` work with the shell's scope params. | none | none | none | `features/menu/menu-items-page.tsx:163`; `features/menu/studio/section-meal.tsx:84,101` |
| OFFR-CMB-034 | (critic) The search text, category, status and page live only in the page's memory, not in the URL: coming back from the editor (Back, browser back, sidebar) starts again at page 1 with no search and no filter. The search box has no clear button. | none | none | none | `cp:56-61` |
| OFFR-CMB-035 | (critic) Web quirk for the orchestrator: opening a combo (row click, row Edit, "New combo" in the header or the empty state) and the "Channels and margin" link navigate WITHOUT the shell's scope search params (`navigate({to, params})` / `<Link to>` with no `search`; the router then drops every search param), so the URL loses `branchId`/`preset`/`from`/`to` and the shell mirrors that into its store: the scope falls back to All branches and the default period. The editor's Back, its post-create URL replace and its two link rows (OFFR-CED-059) do the same. Consequence: a combo opened from the list after picking a branch shows "Prices at organisation prices" and asks the price check with `branch_id: null`. The sidebar keeps scope (`keepScope`). Decide whether to copy this. | none | none | `combos.econ.orgPrices` | `cp:80,210,217,306`; `ce:134,154,412-421`; `routes/_app/route.tsx:99-104`; `data/scope/use-scope.ts:49-53`; `@tanstack/router-core` `router.js:1144-1146` |
| OFFR-CMB-036 | (critic) Deleting the only combo of the last page (page > 1) leaves the page index where it was and the server answers an empty page: the table shows the empty state ("No combos yet" + New combo, or "No combo matches these filters"). If two or more pages remain the footer reads e.g. "Page 3 of 2" with Previous enabled and Next disabled; if only ONE page remains the footer is hidden and the person is stuck on the empty state until a filter changes or the page is reopened. No automatic step back. | GET `/combos` (`page` past the end) | none | `combos.empty`, `combos.emptyFiltered`, `common.page` | `cp:60,194-196,288-291`; `dt:181,553-585` |
| OFFR-CMB-037 | (critic) The Category filter and the Category column read `/categories` on their own: while it loads, or if it fails, the filter offers only "All categories" and every Category cell reads "—"; no error is shown for it. | GET `/categories` listCategories | `menu.items.read` | `combos.allCategories` | `cp:74-78,239-246` |

### 1.1 Formatting and computed values (combos list)

- Money: `fmtMoney(piastres)` (`lib/format.ts:100-117`): piastres ÷ 100, two decimals, grouped thousands, Latin digits,
  true minus U+2212; EN `EGP 1,234.50`, AR `⁦1,234.50⁩ ج.م` (figure LTR-isolated, currency label after). null → "—".
- Rate: `fmtRate(v)` (`cu:68-78`): the wire string fraction ("0.5933") → `Intl.NumberFormat(locale, {style: "percent",
  maximumFractionDigits: 1, numberingSystem: "latn"})` with locale `en-GB` / `ar-EG` → EN "59.3%", AR "59.3‎%‎"
  (with LRM marks); null/blank/non-numeric → "—"; minus signs replaced by U+2212.
- Status pill logic: `!is_active` → Inactive; else `available_now` ? On sale now : Not on sale now.
- Category name lookup: `getTranslatedName(category, lang)` = Arabic `name_translations.ar` when the UI is Arabic and it
  exists, else `name`; unknown id → "—".
- Arabic sub-line: `arOf(name_translations)` = the `ar` string or nothing.
- Search debounce 300 ms (`lib/use-debounced.ts`).

---

## 2. Page `/menu/combos/:comboId` (Combo editor)

| Field | Value |
|---|---|
| Web path | `/menu/combos/$comboId` (file route `/_app/menu/combos_/$comboId`, un-nested from the list); `comboId = "new"` creates. |
| Title | Header title = the name being typed, else `combos.new` "New combo" (new) / `combos.untitled` "Untitled combo"; Restricted/error title `combos.title` "Combos" (or "New combo"). |
| Web files read | `routes/_app/menu/combos_.$comboId.tsx`, `features/combos/combo-editor-page.tsx` (+ `combo-editor-page.test.tsx`), `slots-editor.tsx`, `windows-editor.tsx`, `economics-panel.tsx`, `form-schema.ts` (+ `form-schema.test.ts`), `util.ts`, `api.ts`, `types.ts`, `use-menu-options.ts`, `features/menu/util.ts` (`ONE_SIZE`), `components/app/image-uploader.tsx`, `combobox.tsx`, `segmented-control.tsx`, `date-picker.tsx`, `time-picker.tsx`, `components/inputs/time-field.tsx`, `status-pill.tsx`, `empty-state.tsx`, `restricted.tsx`, `confirm-dialog.tsx`, `page.tsx`, `data/scope/use-scope.ts`, `data/api/errors.ts`, `lib/format.ts`, generated models (`Combo`, `ComboWrite`, `ComboSlotWrite`, `ComboChoiceWrite`, `SaleWindow`, `ComboEconomics`, `ComboEconomicsRequest`, `ComboWarning`); backend `combos/handlers.rs` (gates at :514,601,655,679,778), `combos/codes.rs`, `uploads/handlers.rs:147-200`. |
| Capabilities | Page: `<Restricted>` without `menu.items.read` (default body). Editing (every control, Save bar, Delete, add/remove/move buttons): `menu.combos.edit`; without it the page is read-only. Server: GET combo and price check `menu.items.read` (at the branch when one is sent); create/update `menu.combos.edit`; delete `menu.items.delete` [menu_items:delete]; image upload `menu.items.edit` [menu_items:update] + same org. |
| Module | `pos` (prefix `/menu/combos`). |
| Realtime | None. The price check re-asks when the shell's branch scope changes. |
| Generated API hooks / ops | `getCombo` (via `useCombo`, key `["/combos/{id}", {}]`), `createCombo`, `updateCombo`, `comboEconomics` (key `["/combos/economics", body]`), `deleteMenuItem`, `uploadMenuItemImage`, `useListMenuItems` (`listMenuItems`, key `["/menu-items", {org_id, full: true}]`), `useListCategories` (`["/categories", {org_id}]`), `useListBranches` (`["/branches", {org_id}]`). |
| Invalidated after mutations | Create, update, delete → `invalidateCombos()` (OFFR-ALL-007). The image upload invalidates nothing extra (it runs before the same invalidation). |

### Endpoints

| # | Method + path | operationId | Params / body | Enabled when | Server gate |
|---|---|---|---|---|---|
| E1 | GET `/combos/{id}` | `getCombo` | none (no `branch_id`) | not `new` AND `menu.items.read` | `menu.items.read` |
| E2 | GET `/menu-items` | `listMenuItems` | `org_id`, `full=true` | `menu.items.read` AND org | menu read |
| E3 | GET `/categories` | `listCategories` | `org_id` | same | menu read |
| E4 | GET `/branches` | `listBranches` | `org_id` | same | branch read |
| E5 | POST `/combos/economics` | `comboEconomics` | `ComboWrite` from the economics mapping (section 2.2) + `branch_id` (scope branch or null) | the mapping is not null; 450 ms after the form settles | `menu.items.read` at `branch_id` |
| E6 | POST `/combos` | `createCombo` | `ComboWrite` (section 2.2) | Save on `new` | `menu.combos.edit` |
| E7 | PUT `/combos/{id}` | `updateCombo` | `ComboWrite` with slot and choice `id`s kept | Save on an existing combo | `menu.combos.edit` |
| E8 | POST `/uploads/menu-items/{id}` | `uploadMenuItemImage` | multipart field `image` (the picked file) | after a successful E6/E7 when an image is pending | `menu.items.edit` [menu_items:update] + same org |
| E9 | DELETE `/menu-items/{id}` | `deleteMenuItem` | none | Delete confirmed | `menu.items.delete` [menu_items:delete] |

Backend semantics for the mock: E1/E6/E7 return `Combo` (`id, kind:"combo", name, name_translations, category_id,
description, description_translations, is_active, price, image_url, is_fixed, available_now, windows[], slots[] (each
with `id, name, name_translations, sort, min, max, default_item_id, default_size_label, choices[] (id, menu_item_id |
category_id, surcharge, included_size_label, size_surcharges[{size_label, surcharge}], sort)`), economics, created_at,
updated_at`). E5 returns `ComboEconomics` (`branch_id, price, list_default, list_min, list_max, cost_default|null,
cost_max|null, margin_default|null, margin_worst|null, min_margin|null` (string fractions), `saving_default,
warnings[{code, vars}]`). Refusals: `COMBO_SLOTS_REQUIRED`, `COMBO_SLOT_INVALID {slot_index}`, `COMBO_NESTED`,
`COMBO_KIND_LOCKED` (coded 4xx with `code` + `vars`).

### Rows: page frame, states, header

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-CED-001 | `/menu/combos/new` opens an empty editor in create mode; `/menu/combos/{id}` loads that combo. | E1 (existing only) | `menu.items.read` | none | `ce:78-79,88` |
| OFFR-CED-002 | Without `menu.items.read`: Restricted page titled "New combo" (new) or "Combos" with the DEFAULT body "This is managed by Madar. Get in touch if you need a change here." (no account-specific text, unlike the list). Test: "says the page isn't theirs without menu.items.read". | none (E1–E4 disabled) | `menu.items.read` | `common.restrictedTitle`, `common.restrictedBody`, `combos.new`, `combos.title` | `ce:192-193`; `components/app/restricted.tsx:25-28` |
| OFFR-CED-003 | Data the editor reads: the combo (E1) and the pick lists (E2 items, E3 categories, E4 branches; all asked once, stale after 5 min). Items exclude combos and deleted items (a combo never contains a combo). | E1–E4 | `menu.items.read` | none | `ce:88-89`; `mo:56-107` |
| OFFR-CED-004 | Loading an existing combo: header with the back button and a 224 px title skeleton, then two skeleton blocks (176 px and 288 px tall). | E1 | none | `common.back` "Back" | `ce:195-205` |
| OFFR-CED-005 | Load failed or not found: header (back + "Combos") and ErrorState "Couldn't load this combo" + the server's words + Retry (spinner while refetching). | E1 (retry) | none | `combos.loadError` "Couldn't load this combo", `common.retry` | `ce:206-218` |
| OFFR-CED-006 | Seeding: the form is filled from the combo once per combo id; a background refetch never overwrites what is being typed; `new` starts from the empty combo (name blank, price blank, active on, ONE slot "At least 1 / At most 1" with ONE empty item choice, no windows). Test: "opens with its category shown and nothing unsaved". | none | none | none | `ce:102-115`; `cfs:145-186` |
| OFFR-CED-007 | Header back button (accessible name "Back", arrow mirrored in RTL) returns to `/menu/combos` (no confirm, even with unsaved changes). Title = the Name field as typed (live), else "New combo" (new) or "Untitled combo". | none | none | `common.back`, `combos.new` "New combo", `combos.untitled` "Untitled combo" | `ce:134,230,239-241`; `components/app/page.tsx:175-190` |
| OFFR-CED-008 | Subtitle pill (info): "Fixed bundle" while every slot has exactly one item choice (no category) with At least = At most; otherwise "Meal deal". Updates live as slots change. | none | none | `combos.fixedBundle` "Fixed bundle", `combos.mealDeal` "Meal deal" | `ce:222-228,244-246`; `cu:109-114` |
| OFFR-CED-009 | Subtitle pill "Inactive" (neutral) while the "On the menu" switch is off. | none | none | `common.inactive` "Inactive" | `ce:247-251` |
| OFFR-CED-010 | Subtitle pill "Read only" (neutral) without `menu.combos.edit`. Test: "is read-only without menu.combos.edit … Read only". | none | `menu.combos.edit` | `combos.readOnly` "Read only" | `ce:252-256` |
| OFFR-CED-011 | Header action "Delete" (outline, red text, trash icon) on an existing combo → confirm "Delete {{name}}?" (the name as currently in the form, English field) with body `combos.deleteBody` and red "Delete". Not shown on `new` or without the right. | none | `menu.combos.edit` | `common.delete`, `combos.deleteTitle`, `combos.deleteBody` | `ce:170-180,259-265` |
| OFFR-CED-012 | Delete confirmed: toast "Combo deleted", `invalidateCombos()`, unsaved-state cleared, navigate to `/menu/combos`. Failure → error toast (`getErrorMessage`), stays. Cancel → nothing. | E9 DELETE `/menu-items/{id}` deleteMenuItem | client `menu.combos.edit`; server `menu.items.delete` | `combos.deleted` "Combo deleted" | `ce:181-189` |
| OFFR-CED-013 | Read-only (no `menu.combos.edit`): every field, select, switch, segmented control, day toggle, time/date picker and the image box disabled (disabled fieldsets); no Add slot / Add an item / Add a whole category / Add a window / Move / Remove buttons for slots and choices; no Save bar; no Delete. (Window remove and "Every day/Clear" stay visible but disabled.) Test: Name and Slot name disabled, no Save, no Delete. | none | `menu.combos.edit` | none | `ce:220,276,386,404,438`; `se:62,113,125,193,368`; `we:67,206` |
| OFFR-CED-014 | Responsive: ≥1024 px two columns — the form (General, Slots, Availability, Branches and channels) and a 20 rem "Price check" aside that stays in view (sticky) while scrolling; below 1024 px one column with the price check after the sections. Paired fields sit side by side from 640 px; slot fields are a 4-column row (name, Arabic name, At least, At most) from 640 px. The page keeps 96 px bottom padding for the floating save bar. | none | none | none | `ce:238,272,290,305,351,426`; `se:140` |

### Rows: General section

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-CED-015 | Section heading "General". | none | none | `combos.sections.general` "General" | `ce:275` |
| OFFR-CED-016 | Image box (dashed square, max 200 px): empty → "Choose Image" with an image icon; click (or drop a file on it) opens the file chooser (PNG/JPEG/WebP). The picked file is held as a pending preview (shown at once) and is NOT uploaded until Save. Hint under it "PNG/JPG/WebP, up to 5 MB". Existing combo shows its `image_url`. | none (upload happens on Save, OFFR-CED-073) | `menu.combos.edit` | `uploader.choose` "Choose Image", `menu.imageHint` "PNG/JPG/WebP, up to 5 MB" | `ce:97-99,229,278-287`; `components/app/image-uploader.tsx:88-113,207-218,234` |
| OFFR-CED-017 | Image refused in the browser: not an image → red line "Selected file must be an image"; bigger than 5 MB → "Image size exceeds 5MB limit" (replaces the hint). Nothing becomes pending. | none | none | `uploader.notAnImage` "Selected file must be an image", `uploader.tooLarge` "Image size exceeds 5MB limit" | `components/app/image-uploader.tsx:91-98,235` |
| OFFR-CED-018 | With an image shown: overlay buttons Replace (upload icon, accessible name "Replace") opens the chooser again; Remove (red ×, accessible name "Remove") appears ONLY for a pending, unsaved image and drops it (back to the saved image or empty). A saved image cannot be removed here. Overlay visible on touch devices, revealed on hover/focus elsewhere. Dragging a file over highlights the box. | none | `menu.combos.edit` | `uploader.replace` "Replace", `uploader.remove` "Remove" | `ce:280-284`; `components/app/image-uploader.tsx:131-205` |
| OFFR-CED-019 | Field "Name" (required): blank on Save → red line "This field is required." under it, field marked invalid. | none | `menu.combos.edit` | `combos.name` "Name", `combos.errors.required` "This field is required." | `ce:291-299`; `cfs:81` |
| OFFR-CED-020 | Field "Name (Arabic)" (right-to-left, optional). Saved as `name_translations.ar` (trimmed; blank → `{}`). | none | `menu.combos.edit` | `combos.nameAr` "Name (Arabic)" | `ce:300-303`; `cfs:189` |
| OFFR-CED-021 | Field "Combo price" (decimal keyboard, LTR mono) in EGP: required, a number ≥ 0 → otherwise "Enter an amount of 0 or more." (blank, "-5", junk). Under it, when no error, the hint "Covers each slot's included size. Extras, bigger sizes and add-ons are added on top." A price above the items' value is NOT an error (warning only). Test: "refuses a blank or negative price but never looks at margins". | none | `menu.combos.edit` | `combos.price` "Combo price", `combos.errors.money` "Enter an amount of 0 or more.", `combos.priceHint` | `ce:306-326`; `cfs:87-90` |
| OFFR-CED-022 | Field "Category" (select): "No category" + the org's categories (translated names). Hint "Where the combo shows on the till and the menus." An existing combo shows its category even when the categories arrive after the combo, and a re-save keeps it (test "keeps the category when the categories load after the combo"). | none | `menu.combos.edit` | `combos.col.category` "Category", `combos.noCategory` "No category", `combos.categoryHint` | `ce:327-349` |
| OFFR-CED-023 | Fields "Description" and "Description (Arabic)" (2-row text areas; Arabic right-to-left; optional). Blank description → `null`; Arabic → `description_translations.ar`. | none | `menu.combos.edit` | `combos.description` "Description", `combos.descriptionAr` "Description (Arabic)" | `ce:351-360`; `cfs:290-291` |
| OFFR-CED-024 | Switch "On the menu" with hint "Off hides it everywhere without deleting it." (default on). | none | `menu.combos.edit` | `combos.active` "On the menu", `combos.activeHint` | `ce:361-373` |

### Rows: Slots section

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-CED-025 | Section heading "Slots" with the description "What the customer picks. One slot with one item and a fixed count makes a fixed bundle; several choices make a meal deal." | none | none | `combos.sections.slots` "Slots", `combos.sections.slotsDesc` | `ce:378-387` |
| OFFR-CED-026 | Slot card header: title = the slot's name, else "Slot {{n}}" (1-based); under it "Pick {{count}}" when At least = At most (plural forms; Arabic "اختر صنفًا واحدًا"…), else "Pick {{min}} to {{max}}". Live. | none | none | `combos.slots.slotN` "Slot {{n}}", `combos.slots.pickExactly` (`_one`/`_other` "Pick {{count}}"), `combos.slots.pickRange` "Pick {{min}} to {{max}}" | `se:107-123` |
| OFFR-CED-027 | Move up / Move down icon buttons reorder slots (Move up disabled on the first, Move down on the last). The order is the saved `sort` (0-based position). | none | `menu.combos.edit` | `combos.slots.moveUp` "Move up", `combos.slots.moveDown` "Move down" | `se:57,126-131`; `cfs:295` |
| OFFR-CED-028 | Remove this slot (red trash) removes the slot immediately, no confirm. | none | `menu.combos.edit` | `combos.slots.remove` "Remove this slot" | `se:58,133-135` |
| OFFR-CED-029 | Field "Slot name" (placeholder "Drink"): required → "This field is required." | none | `menu.combos.edit` | `combos.slots.name` "Slot name", `combos.slots.namePlaceholder` "Drink", `combos.errors.required` | `se:141-145`; `cfs:59` |
| OFFR-CED-030 | Field "Slot name (Arabic)" (right-to-left, placeholder "مشروب"); saved as `name_translations.ar`. | none | `menu.combos.edit` | `combos.slots.nameAr` "Slot name (Arabic)" | `se:146-149` |
| OFFR-CED-031 | Fields "At least" and "At most" (number, LTR mono; defaults 1 and 1). Rules, shown on one line under the row (the At least error first): not a whole number 0–10 → "Use a whole number from 0 to 10."; At most = 0 → "\"At most\" must be 1 or more."; At least > At most → "\"At least\" can't be more than \"At most\"." Test: min 3 / max 2 shows the min-over-max message and no request is made. | none | `menu.combos.edit` | `combos.slots.min` "At least", `combos.slots.max` "At most", `combos.errors.pickRange`, `combos.errors.maxZero`, `combos.errors.minOverMax` | `se:150-159`; `cfs:61-62,97-100` |
| OFFR-CED-032 | When At least = 0, hint "At least 0 makes this slot optional: the customer may skip it." | none | none | `combos.slots.optionalHint` | `se:160-162` |
| OFFR-CED-033 | "Choices" list (label) with one choice row each (rows OFFR-CED-040–049); buttons "Add an item" (tag icon, adds an item choice) and "Add a whole category" (folder icon, adds a category choice). | none | `menu.combos.edit` | `combos.slots.choices` "Choices", `combos.slots.addItem` "Add an item", `combos.slots.addCategory` "Add a whole category" | `se:164-203` |
| OFFR-CED-034 | A slot with no choices on Save → "Add at least one choice to this slot." under its list. Test. | none | none | `combos.errors.noChoices` | `se:192`; `cfs:101` |
| OFFR-CED-035 | Field "Default pick" (select): "The first choice" (none) + every item the slot's choices admit (item choices, plus every item of each category choice; de-duplicated, menu order). Changing it also clears the default size. Hint "Pre-selected on the till, used for the default margin, and applied when a synced sale arrives without picks." | none | `menu.combos.edit` | `combos.slots.default` "Default pick", `combos.slots.defaultFirst` "The first choice", `combos.slots.defaultHint` | `se:95-105,205-232` |
| OFFR-CED-036 | A default that is not one of the slot's item choices, in a slot without any category choice → "The default must be one of this slot's choices." | none | none | `combos.errors.defaultNotChoice` | `se:228`; `cfs:115-121` |
| OFFR-CED-037 | Field "Default size" (select), shown only when the default item has more than one active size: "The included size" (none) + the item's sizes ("Standard" for the single-price `one_size`). | none | `menu.combos.edit` | `combos.slots.defaultSize` "Default size", `combos.slots.includedSize` "The included size", `combos.oneSize` "Standard" | `se:233-254`; `mo:51-52` |
| OFFR-CED-038 | "Add a slot" (outline, plus) appends an empty slot (At least 1, At most 1, one empty item choice). | none | `menu.combos.edit` | `combos.slots.add` "Add a slot" | `se:62-66`; `cfs:155-164` |
| OFFR-CED-039 | Every slot removed, then Save → "Add at least one slot." under the slots. | none | none | `combos.errors.slotsRequired` "Add at least one slot." | `se:46,61`; `cfs:95` |

### Rows: a choice row (inside a slot)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-CED-040 | Segmented control "Item" / "Category" picks what the choice points at; switching clears the item/category, the covered size and the size extras. | none | `menu.combos.edit` | `combos.choice.item` "Item", `combos.choice.category` "Category" | `se:307-316` |
| OFFR-CED-041 | (corrected) Item picker (searchable combobox; placeholder "Choose an item"): opens a list of every non-combo, non-deleted item, switched-off items INCLUDED (they get the "Inactive" badge once picked, OFFR-CED-044), sorted by name (current language), each with its cheapest active size price on the right; a search box ("Search") matches the item name or its category's name; nothing matches → "No results found"; the chosen one is ticked. Picking clears the covered size and size extras. Test: pick "Burger" → body has `menu_item_id: "burger"`. | none | `menu.combos.edit` | `combos.choice.pickItem` "Choose an item", `common.search` "Search", `common.noResults` "No results found" | `se:287-296,319-325`; `components/app/combobox.tsx:40-97` |
| OFFR-CED-042 | Category picker (select; placeholder and accessible name "Choose a category"); picking clears the size settings. Once chosen, hint "{{count}} items today; new items in it join automatically." (plural forms). | none | `menu.combos.edit` | `combos.choice.pickCategory` "Choose a category", `combos.choice.categoryCount` (`_one` / `_other`) | `se:327-345` |
| OFFR-CED-043 | Nothing chosen on Save → "Choose an item or a category." under the picker; the same item (or category) twice in one slot → "This choice is already in the slot." on the second. | none | none | `combos.errors.choiceTarget`, `combos.errors.choiceDuplicate` | `se:340`; `cfs:103-112` |
| OFFR-CED-044 | A switched-off item shows a secondary badge "Inactive" under the picker. | none | none | `common.inactive` | `se:346-350` |
| OFFR-CED-045 | A choice whose item id is no longer in the pick list (deleted item) gets an amber border. | none | none | none | `se:305` |
| OFFR-CED-046 | Field "Extra charge" (decimal, LTR mono, placeholder "0", 112 px): EGP added when this choice is picked; blank = 0; negative or junk → "Enter an amount of 0 or more." under the row. | none | `menu.combos.edit` | `combos.choice.surcharge` "Extra charge", `combos.errors.money` | `se:352-367,374`; `cfs:36-39,50` |
| OFFR-CED-047 | Remove this choice (red trash) drops the choice at once. Test: removing the only choice then Save → "Add at least one choice to this slot.". | none | `menu.combos.edit` | `combos.choice.remove` "Remove this choice" | `se:183,368-372` |
| OFFR-CED-048 | "Size the price covers" (select; shown only when the choice has more than one size: an item's active sizes, or the union of size labels of a category's items): "The cheapest size" (default) + each size ("Standard" for `one_size`). Choosing a size removes any extra typed for that size. | none | `menu.combos.edit` | `combos.choice.includedSize` "Size the price covers", `combos.choice.cheapest` "The cheapest size", `combos.oneSize` | `se:376-399` |
| OFFR-CED-049 | (corrected) "Other sizes cost": one small money box per size other than the covered one, labelled by the size (accessible name "Extra for {{size}}"). Which sizes: an item choice lists every active size except the covered one, SMALLER ones included (their placeholder reads "+0.00 difference"); a category choice left on "The cheapest size" has no covered label, so it lists EVERY size of the category, the cheapest too. Placeholder for an item choice "+{{amount}} difference" (that size's price minus the covered size's price, never below 0, money without currency) and "the difference" for a category choice; typing sets that size's extra, clearing the box removes it (= the size's usual difference). Errors: NO text is ever shown under these boxes. Junk ("abc") marks the box invalid at once (before Save); a negative amount is marked invalid only after a Save attempt; either way Save is refused with only the toast "Some fields need attention before saving." and the scroll to the box (OFFR-CED-071). Hint "Left blank, a bigger size costs its usual price difference." | none | `menu.combos.edit` | `combos.choice.otherSizes` "Other sizes cost", `combos.choice.sizeExtra` "Extra for {{size}}", `combos.choice.differenceAmount` "+{{amount}} difference", `combos.choice.difference` "the difference", `combos.choice.blankMeansDifference` | `se:282-302,400-436` |

### Rows: Availability section (shared windows editor; the deal dialog reuses it)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-CED-050 | Section heading "Availability" with "Optional. With no window it is on sale whenever the menu is." | none | none | `combos.sections.availability` "Availability", `combos.sections.availabilityDesc` | `ce:389-393` |
| OFFR-CED-051 | No window: dashed box with a calendar-clock icon, "Always available" / "Add a window to limit it to certain days, hours, dates or one branch." | none | none | `combos.windows.always` "Always available", `combos.windows.alwaysHint` | `we:51-61` |
| OFFR-CED-052 | "Add a window" (outline, plus) appends a window: every day, no hours, no dates, all branches. | none | `menu.combos.edit` | `combos.windows.add` "Add a window" | `we:206-210`; `cfs:166-174` |
| OFFR-CED-053 | Window card: legend "Window {{n}}"; red trash "Remove this window" removes it at once (no confirm). | none | `menu.combos.edit` | `combos.windows.windowN` "Window {{n}}", `combos.windows.remove` "Remove this window" | `we:67-82` |
| OFFR-CED-054 | "Days": seven toggle buttons Sun Mon Tue Wed Thu Fri Sat (Sunday first; pressed = filled primary, `aria-pressed`), each flips its day; a text button "Every day" selects all seven, and reads "Clear" when all seven are on (clears all). | none | `menu.combos.edit` | `combos.windows.days` "Days", `combos.windows.day.sun`…`sat` "Sun"…"Sat", `combos.windows.everyDay` "Every day", `combos.windows.clearDays` "Clear" | `we:84-114`; `cu:16-22` |
| OFFR-CED-055 | No day selected on Save → "Pick at least one day." under the days. | none | none | `combos.errors.noDays` | `we:115-119`; `cfs:124` |
| OFFR-CED-056 | "Hours (optional)": From and To time fields (type "930", "9:30 pm", or pick a quarter hour from the list; shown on the 12-hour clock; clearable ×; placeholders "From"/"To"). Only one set → "Set both times, or neither."; both equal → "The start and end times can't be the same."; To earlier than From → muted hint "Runs past midnight into the next day." | none | `menu.combos.edit` | `combos.windows.hours` "Hours (optional)", `combos.windows.from` "From", `combos.windows.to` "To", `combos.errors.hoursPair`, `combos.errors.hoursSame`, `combos.windows.crossesMidnight`, `inputs.clearTime` "Clear the time", `inputs.timeUnreadable` | `we:122-148`; `cfs:125-128`; `components/app/time-picker.tsx:21-32` |
| OFFR-CED-057 | "Dates (optional)": First day and Last day date pickers (calendar popover, day only); Last day before First day → "The last day can't be before the first."; when either is set a text button "Clear the dates" empties both. | none | `menu.combos.edit` | `combos.windows.dates` "Dates (optional)", `combos.windows.fromDate` "First day", `combos.windows.toDate` "Last day", `combos.errors.datesOrder`, `combos.windows.clearDates` "Clear the dates", `datePicker.*` | `we:149-183`; `cfs:129-131` |
| OFFR-CED-058 | "Branch" select: "All branches" (default) + each branch by its translated name. | none | `menu.combos.edit` | `combos.windows.branch` "Branch", `combos.windows.allBranches` "All branches" | `we:186-201` |

### Rows: Branches and channels section

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-CED-059 | Section "Branches and channels" with two link rows (arrow end, mirrored in RTL): "Branch prices and on/off" / "A branch or delivery channel can have its own combo price, or not sell it, in Pricing & Availability." → `/menu/pricing`; "Where combos are sold" / "POS, QR, online and delivery are switched for every combo at once, with branch exceptions, in Settings." → `/settings/combos`. Shown to every reader regardless of rights (the target pages gate themselves). | none | none | `combos.sections.branches` "Branches and channels", `combos.branches.pricing`, `combos.branches.pricingHint`, `combos.branches.channels`, `combos.branches.channelsHint` | `ce:410-423,475-488` |

### Rows: Price check panel (live economics)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-CED-060 | Panel "Price check" with the line "Prices at {{scope}}": scope = the shell's selected branch name ("—" if unknown) or "organisation prices" when all branches are selected. | none | `menu.items.read` | `combos.econ.title` "Price check", `combos.econ.pricesAt` "Prices at {{scope}}", `combos.econ.orgPrices` "organisation prices" | `ce:231,426-436`; `ep:119-126` |
| OFFR-CED-061 | Not enough to ask (no valid price, or no slot with a chosen item/category and valid min/max): "Enter a price and at least one slot with a choice to see the figures."; no request. | none | none | `combos.econ.needsInput` | `ep:127-128`; `cfs:305-319` |
| OFFR-CED-062 | The request: the economics mapping of the form (section 2.2) plus `branch_id` (the scope branch or null), sent 450 ms after the form stops changing; asked again only when that body (or the branch) changes; never retried. Nothing is saved. | E5 POST `/combos/economics` comboEconomics | `menu.items.read` at the branch | none | `ce:117-121`; `ep:117`; `capi:80-86` |
| OFFR-CED-063 | Loading: five skeleton lines; the panel is `aria-busy` while any fetch runs. | E5 | none | none | `ep:120,129-134` |
| OFFR-CED-064 | Failed: "The price check is unavailable right now. You can still save." with the server's words under it (role status). Save stays available. | E5 | none | `combos.econ.failed` | `ep:135-139` |
| OFFR-CED-065 | Figures (label left, mono value right): "Combo price" = price; "Bought separately" = `list_default` with hint "{{min}} to {{max}}" when `list_min ≠ list_max`; "Customer saves" = `saving_default`, green when > 0 else amber; "Cost (default picks)" = `cost_default` or "Unknown", hint "Up to {{amount}}" when `cost_max` is known and differs; "Margin (default picks)" and "Margin (costliest picks)" = `fmtRate`, amber when below the minimum; "Your minimum" = `fmtRate(min_margin)` or "Not set". | none | none | `combos.econ.price`, `combos.econ.listValue` "Bought separately", `combos.econ.range`, `combos.econ.saving` "Customer saves", `combos.econ.cost`, `combos.econ.unknown` "Unknown", `combos.econ.worstCost` "Up to {{amount}}", `combos.econ.margin`, `combos.econ.marginWorst`, `combos.econ.minMargin` "Your minimum", `combos.econ.noMinimum` "Not set" | `ep:41-76` |
| OFFR-CED-066 | Warnings list (accessible name "Warnings"; amber rows with a triangle): `MARGIN_BELOW_MIN` "Margin {{margin}} is below your minimum {{min}}."; `NO_SAVING` "Customers save nothing versus ordering separately."; `COST_UNKNOWN` "{{item}} has no known cost, so the margin is incomplete." (item name from the pick list, else "An item"); `SLOT_EMPTY_NOW` "{{slot}} has no choice that can be sold right now." (slot name from the form, else "A slot"); `CHOICE_INACTIVE` "{{item}} is switched off, so it can't be picked."; any other code "Check this combo ({{code}})." No warnings → green "No warnings.". Always: "Warnings never stop you saving." Test: "shows the warnings and still saves" (margin 40% vs 55%, Fries cost unknown). | none | none | `combos.econ.warnings`, `combos.warnings.MARGIN_BELOW_MIN`, `.NO_SAVING`, `.COST_UNKNOWN`, `.SLOT_EMPTY_NOW`, `.CHOICE_INACTIVE`, `.unknown`, `.anItem`, `.aSlot`, `combos.econ.noWarnings`, `combos.econ.neverBlocks` | `ep:78-99`; `cu:123-152`; `ce:431-434` |
| OFFR-CED-067 | Changing the branch in the shell's scope bar re-asks the price check with the new `branch_id` and relabels "Prices at …". | E5 | none | `combos.econ.pricesAt` | `ce:86,231`; `ep:117` |

### Rows: Save bar, save, errors

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-CED-068 | Floating pill at the bottom centre (only with `menu.combos.edit`) with a status: "Unsaved changes" (form changed or an image pending), "Not saved yet" (new and untouched), "All changes saved". Test: an opened combo shows no "Unsaved changes". | none | `menu.combos.edit` | `combos.unsaved` "Unsaved changes", `combos.notSavedYet` "Not saved yet", `combos.allSaved` "All changes saved" | `ce:123,438-443` |
| OFFR-CED-069 | "Discard" (ghost; existing combo with changes) puts the form back to the loaded combo and drops a pending image. Disabled while saving. | none | `menu.combos.edit` | `combos.discard` "Discard" | `ce:444-448` |
| OFFR-CED-070 | Save button "Create combo" (new) / "Save" (existing); disabled while saving, and on an existing combo while nothing changed; spinner while saving; a second press during a save is ignored. | none | `menu.combos.edit` | `combos.create` "Create combo", `common.save` "Save" | `ce:136-137,449-451` |
| OFFR-CED-071 | Save with errors: every failing field shows its red line, an error toast "Some fields need attention before saving.", and the page scrolls the first invalid field to the middle; no request. After the first Save attempt errors re-check as you type. Test: "refuses min above max and a slot with no choices … without calling the server". | none | none | `combos.fixErrors` "Some fields need attention before saving." | `ce:91-96,162-168` |
| OFFR-CED-072 | Create: POST the combo (section 2.2 body; e.g. name "Burger meal", price 150 → 15000, one slot "Main" 1/1 with the Burger choice, surcharge 0, no windows); then (if an image is pending) upload it to the new id; success toast "Combo created"; `invalidateCombos()`; the URL is replaced by `/menu/combos/{newId}` (no extra history entry) and the form reseeded from the answer. Test: "creates a valid combo in piastres and opens it". | E6 POST `/combos` createCombo (+ E8) | client `menu.combos.edit`; server `menu.combos.edit` | `combos.created` "Combo created" | `ce:139-154`; `cfs:285-297` |
| OFFR-CED-073 | Update: PUT the whole combo with each slot's and choice's `id` kept (the server diffs in place); then the pending image if any; toast "Changes saved"; form reset to the saved answer ("All changes saved"); `invalidateCombos()`. Test: price 160 → `price: 16000`, slot ids `["s-main","s-side"]`, toast "Changes saved". | E7 PUT `/combos/{id}` updateCombo (+ E8) | `menu.combos.edit` | `common.savedChanges` "Changes saved" | `ce:141,149-153` |
| OFFR-CED-074 | Image upload after a successful save: multipart field `image`. If it fails, an error toast "The combo was saved, but its image wasn't: {{error}}" (server words); the combo save still counts (its success toast also shows) and the pending image is dropped. A person with `menu.combos.edit` but not `menu.items.edit` hits this (server 403). | E8 POST `/uploads/menu-items/{id}` uploadMenuItemImage | server `menu.items.edit` [menu_items:update] | `combos.imageFailed` | `ce:142-149`; `capi:77` |
| OFFR-CED-075 | Save refused `COMBO_SLOT_INVALID` with `vars.slot_index` → toast "Check the slot \"{{slot}}\"." naming that slot from the form (its name, else "Slot {{n}}"). Any other failure → `getErrorMessage` (e.g. `COMBO_SLOTS_REQUIRED` "Add at least one slot.", `COMBO_NESTED` "A combo can't contain another combo.", `COMBO_KIND_LOCKED`, 403). The form keeps what was typed. | E6/E7 | none | `errors.codes.COMBO_SLOT_INVALID` "Check the slot \"{{slot}}\".", `combos.slots.slotN`, `errors.codes.COMBO_SLOTS_REQUIRED`, `errors.codes.COMBO_NESTED`, `errors.codes.COMBO_KIND_LOCKED` | `ce:65-75,155-157` |
| OFFR-CED-076 | Leaving with unsaved changes: on the web only a browser reload/close asks "Leave site?" (beforeunload) while changes are unsaved and the person can edit; in-app navigation (Back, sidebar) does NOT ask and drops the changes. Flutter: reproduce as no in-app prompt (app close is not interceptable). | none | `menu.combos.edit` | none | `ce:123-132` |
| OFFR-CED-077 | Price field and every money box accept EGP with decimals; the wire gets integer piastres rounded half away (19.99 → 1999). | none | none | none | `cu:98-105`; `lib/format.ts:47` |
| OFFR-CED-078 | Keyboard: Tab order follows the sections; Enter in a text field submits the form (Save) when the person can edit; Esc closes an open select/combobox/date/time popover; the item combobox and the time list are arrow-key navigable (↓ opens, ↑/↓ move, Enter picks). | none | none | none | `ce:269-271`; `components/inputs/time-field.tsx:150-176` |
| OFFR-CED-079 | Arabic UI: all labels in Arabic, right-to-left layout; the Arabic name/description/slot-name boxes stay right-to-left in both languages; price, numbers, money and times stay LTR with Latin digits. | none | none | Arabic of every key above | `ce:302,310-312,358`; `se:148,152,156` |
| OFFR-CED-080 | (corrected) Deep link `/menu/combos/{id}` with an id that does not exist → the error state of OFFR-CED-005. The message is the server's own words, not "Not found.": a well-formed unknown id answers 404 `{error: "Not found: Combo not found"}` → "Combo not found" (kind prefix stripped, English, no retry); a malformed id answers 400 `{error: "Bad request: can not parse …"}` → that text without "Bad request: " (retried once before the error shows). "Not found." (`errors.notFound`) appears only for a 404 with no `error`/`message` body. | E1 | none | `combos.loadError`, `errors.notFound` | `ce:206-218`; `data/api/errors.ts:99-175`; backend `combos/handlers.rs:492-498`, `main.rs:293-295`, `errors.rs:20,252-275` |
| OFFR-CED-081 | (critic) Pressing the ALREADY selected "Item" or "Category" segment of a choice still clears its item/category, its covered size and its size extras (the segmented control always reports a change). The deal pool editor behaves the same (OFFR-DEA-048). | none | `menu.combos.edit` | `combos.choice.item`, `combos.choice.category` | `se:307-316`; `components/app/segmented-control.tsx:29-35` |
| OFFR-CED-082 | (critic) "At least" / "At most" are number boxes kept as text and coerced: a BLANK box counts as 0. A blank "At least" is accepted as 0 (the optional hint shows, the slot saves `min: 0`, and the card header reads "Pick  to {{max}}" with the minimum left empty); a blank "At most" → "\"At most\" must be 1 or more."; a decimal (1.5) or a number above 10 → "Use a whole number from 0 to 10.". No browser bubble (the form is `noValidate`). | none | `menu.combos.edit` | `combos.errors.maxZero`, `combos.errors.pickRange`, `combos.slots.optionalHint`, `combos.slots.pickRange` | `cfs:61-62,97-100`; `se:108,119-123,150-162` |
| OFFR-CED-083 | (critic) Money boxes (Combo price, Extra charge, size extras; also the deal Price) read the text with JS `Number()`: surrounding spaces are fine and ".5" is 0.50, but thousands separators ("1,000") and Arabic-Indic digits ("١٥٠") are refused with "Enter an amount of 0 or more." (price / extra charge) or the invalid mark (size extras); "1e2" reads as 100. Parse the same way. | none | none | `combos.errors.money` | `cu:98-102`; `cfs:36-39,87-90`; `dfs:66-67` |
| OFFR-CED-084 | (critic) The image after Save: the upload answers `status: "processing"` (the server converts it in the background) and the editor ignores that job. After Save the pending preview is dropped and the box shows the combo's `image_url` from the save answer / refetch, which is still the OLD image (the empty "Choose Image" box for a new combo) until the conversion finishes and the combo is read again; the editor never polls. The editor also never passes the asset group to the box, so a combo whose image exists only as an asset (no legacy `image_url`) shows the empty box here although the list shows its thumbnail. | E8 (answer `{image_url: old, asset_job_id, status: "processing"}`) | none | `uploader.choose` | `ce:142-150,229,278-287`; backend `uploads/handlers.rs:113-133` |
| OFFR-CED-085 | (critic) Image picking details: the file chooser offers PNG/JPEG/WebP only (`accept`), but a DROPPED file is only checked for `image/*` and ≤ 5 MB, so a dropped GIF, SVG or HEIC becomes the pending image. Drops are ignored read-only; the box is dimmed (50 %) when read-only and its empty button is disabled. | none | `menu.combos.edit` | `uploader.notAnImage`, `uploader.tooLarge` | `components/app/image-uploader.tsx:48-49,88-98,131-152,208-213` |
| OFFR-CED-086 | (critic) After "Create combo" the URL is replaced by `/menu/combos/{newId}` and the editor asks GET `/combos/{newId}` (a new query): the loading skeleton (OFFR-CED-004) shows until it answers, then the form already reset from the create answer (not re-seeded). The same `invalidateCombos()` also refetches the open pick list `/menu-items` and the price check. Mock: answer GET `/combos/{newId}`. | E1 GET `/combos/{newId}` | `menu.items.read` | none | `ce:150-154,195-205` |
| OFFR-CED-087 | (critic) `/menu/combos/new` opened by a reader without `menu.combos.edit` (deep link; the list offers no button): the empty create form renders read-only: title "New combo", pills "Meal deal" and "Read only", every control disabled, no Add buttons, no save bar, price check "Enter a price and at least one slot with a choice to see the figures."; only the pick lists are asked. | E2–E4 | `menu.items.read` | `combos.new`, `combos.mealDeal`, `combos.readOnly`, `combos.econ.needsInput` | `ce:192,220-256,438` |
| OFFR-CED-088 | (critic) A choice whose item is not in the pick list (deleted, or the pick list still loading) shows the placeholder "Choose an item" in its picker (with the amber border of OFFR-CED-045), keeps its id and re-sends it on Save, and is left out of the "Default pick" options. While `/menu-items` is loading, EVERY saved item choice shows this state for a moment. | none | none | `combos.choice.pickItem` | `se:96-105,280,305`; `components/app/combobox.tsx:45,61` |
| OFFR-CED-089 | (critic) Date pickers (First day / Last day, also in the deal dialog): a popover calendar with previous / next month buttons (accessible names "Previous" / "Next", chevrons mirrored in RTL), the month title in the UI language, weekday headers starting on SATURDAY (week start 6), today ringed, the chosen day filled; picking a day closes it; footer "Today" shortcut plus the chosen date (or "Click a day"); no past or future limit; the trigger shows `fmtDate` ("01 Oct 2026") or the placeholder. | none | `menu.combos.edit` | `datePicker.today` "Today", `datePicker.clickDay` "Click a day", `common.previous`, `common.next` | `components/app/date-picker.tsx:67-210`; `lib/week.ts:11-17` |

### 2.1 Formatting and computed values (combo editor)

- Money in forms: `moneyIn(text)` = blank → null; `Number(text)` finite → `Math.round(n*100)` piastres; junk → NaN.
  `moneyOut(p)` = `String(p/100)` (no grouping, no trailing zeros: 15000 → "150", 1250 → "12.5") (`cu:98-105`).
- Money shown: `fmtMoney` (section 1.1). Size-difference placeholder uses `fmtMoney(diff, {currency: false})` → "8.00"
  (AR LTR-isolated) (`se:421`).
- Rates: `fmtRate` (section 1.1). "Below minimum" = `rateOf(margin) < rateOf(min_margin)` when both known (`ep:43-44`).
- Fixed bundle rule `isFixedShape` (`cu:109-114`): at least one slot and EVERY slot has min = max, exactly one choice,
  that choice an item (not a category).
- Weekday mask (`cu:16-22`): bit 0 = Sunday … bit 6 = Saturday; 127 = every day; toggle = XOR of the day's bit.
- Times: `hhmm()` normalises "H:MM[:SS]" → "HH:MM", hour ≤ 23, minute ≤ 59, else empty (`cu:34-42`); the time field
  emits `HH:MM:SS`, stored as `HH:MM`. Display in the field: 12-hour clock in both languages (`APP_HOUR_CYCLE`).
- Dates: `YYYY-MM-DD` strings; "Last day before First day" compares the strings (`cfs:129`). Date picker shows
  `fmtDate` (`en-GB`/`ar-EG`, "01 Oct 2026") in the active branch timezone.
- Pick lists (`mo:65-106`): items = `GET /menu-items?full=true` minus `kind == "combo"` minus deleted; each item's sizes =
  `all_sizes` (else `sizes`) with `is_active !== false`, `{label, price_override}` sorted by price ascending; none →
  one `{label: "one_size", price: base_price}`; items sorted by translated name with `localeCompare(lang)`;
  `itemsOfCategory(id)`; `categorySizeLabels(id)` = union of those items' size labels; `cheapestSize` = first size.
  "one_size" is displayed "Standard" (`combos.oneSize`).
- Default-pick options (`se:96-105`): for each choice in order, the item itself or every item of the category,
  de-duplicated.
- Choice covered size: `included_size_label` or (item) the cheapest size; "Other sizes" = labels ≠ covered size;
  placeholder diff = `max(0, sizePrice − coveredPrice)` for item choices only (`se:280-285,404-406`).
- Warning texts fill `{{item}}` from the pick list and `{{slot}}` from the form's slot with that `id` (`ce:431-434`).

### 2.2 Form ↔ wire (what Save sends; mock-server request matchers)

`toWire` (`cfs:255-297`): `{ name: trim, name_translations: {ar: trim} or {}, category_id: id or null, description:
trim or null, description_translations: {ar} or {}, is_active, price: piastres (blank → 0), windows: [ {branch_id|null,
weekdays, starts_at "HH:MM"|null, ends_at "HH:MM"|null (both or neither), valid_from|null, valid_to|null} ],
slots: [ {id?, name: trim, name_translations, sort: index, min, max, default_item_id|null,
default_size_label (only when a default item is set; blank → null), choices: [ {id?, menu_item_id (item) | null,
category_id (category) | null, surcharge: piastres (blank → 0), included_size_label|null, size_surcharges: only the
typed, valid rows [{size_label, surcharge piastres}], sort: index} ] } ] }`. Test (`form-schema.test.ts`): weekdays
62, "12:00:00"→"12:00", XL left blank → no row, Large "8" → 800.

`fromWire` (`cfs:218-253`): slots and choices sorted by `sort`; ids kept; a choice is "category" when `category_id`
is set; surcharge 0 → "" (blank).

`toEconomicsBody` (`cfs:305-330`): null when the price is blank/invalid/negative; drops choices with no target; drops
slots with no choice, non-integer min/max, max < 1 or min > max; null when no slot is left; else `{name: trimmed or
"—", name_translations: {}, category_id, description: null, is_active, price, windows: [], slots}` (slot name blank →
"—"). The panel adds `branch_id`.

---

## 3. Page `/menu/deals` (Deals)

| Field | Value |
|---|---|
| Web path | `/menu/deals` (file route `/_app/menu/deals`); search param `edit` = `<dealId>` or `new` opens the dialog (`?edit=new`). |
| Title | `deals.title` "Deals"; sidebar `nav.deals` "Deals". Description `deals.subtitle` "Mix and match and buy X get Y. The till suggests a deal when the cart qualifies; QR and online checkout apply the best one." |
| Web files read | `routes/_app/menu/deals.tsx`, `features/deals/deals-page.tsx` (+ `deals-page.test.tsx`), `deal-dialog.tsx` (+ `deal-dialog.test.tsx`), `form-schema.ts` (+ `form-schema.test.ts`), `pool-editor.tsx`, `util.ts`, `features/combos/api.ts`, `types.ts`, `util.ts`, `form-schema.ts` (window schema + `E`), `windows-editor.tsx`, `use-menu-options.ts`, `data/scope/use-page-search.ts`, `components/app/data-table.tsx`, `combobox.tsx`, `segmented-control.tsx`, `confirm-dialog.tsx`, `restricted.tsx`, `components/ui/dialog`, `data/api/errors.ts`; generated `DealRule`, `DealWrite`, `DealPoolEntry`, `DealBranchOverride`, `SaleWindow`; backend `deals/handlers.rs` (gates at :193,218,262,307,340,387), `combos/routes.rs:30-45`. |
| Capabilities | Nav: `menu.items.read`. Page: `<Restricted>` without `menu.items.read` (default body). New deal, row Edit/Delete, dialog editing and Save: `menu.deals.edit`; without it rows open a read-only dialog. Server: list `menu.items.read`; create/update/delete `menu.deals.edit`; branch on/off `menu.deals.edit` AT that branch. |
| Module | `pos`. |
| Realtime | None. |
| Generated API hooks / ops | `listDeals` (via `useDeals`, key `["/deals", {}]`), `createDeal`, `updateDeal`, `deleteDeal`, `putDealBranch`, `deleteDealBranch`, plus the menu pick lists `listMenuItems` (`full=true`), `listCategories`, `listBranches`. |
| Invalidated after mutations | Create/update (after the branch calls), delete → `invalidateCombos()` (OFFR-ALL-007), which covers `/deals`. |

### Endpoints

| # | Method + path | operationId | Params / body | Enabled when | Server gate |
|---|---|---|---|---|---|
| D1 | GET `/deals` | `listDeals` | none (the page passes `{}`; the API also takes `is_active`) | `menu.items.read` (no org check) | `menu.items.read`; org from the token |
| D2 | GET `/menu-items`, `/categories`, `/branches` | `listMenuItems` (`org_id`, `full=true`), `listCategories`, `listBranches` (`org_id`) | | `menu.items.read` AND org | menu/branch read |
| D3 | POST `/deals` | `createDeal` | `DealWrite` (section 3.2) | Create deal | `menu.deals.edit` |
| D4 | PUT `/deals/{id}` | `updateDeal` | `DealWrite` | Save | `menu.deals.edit` |
| D5 | PUT `/deals/{id}/branches/{branchId}` | `putDealBranch` | `{ is_active: bool }` | after D3/D4, one per branch newly set on/off | `menu.deals.edit` at that branch |
| D6 | DELETE `/deals/{id}/branches/{branchId}` | `deleteDealBranch` | none | after D3/D4, one per branch set back to "Follow the deal" | `menu.deals.edit` at that branch |
| D7 | DELETE `/deals/{id}` | `deleteDeal` | none | delete confirmed | `menu.deals.edit` |

Backend semantics for the mock: D1 returns a plain array of `DealRule` (`id, name, name_translations, kind
("n_for_price"|"buy_get"), qty, price|null, get_qty|null, get_percent|null, max_per_order|null, is_active, sort,
pool[{menu_item_id|null, category_id|null, size_label|null}], reward_pool[], windows[SaleWindow],
branch_overrides[{branch_id, is_active}], sell?, created_at, updated_at`). Refusal `DEAL_INVALID {field}` (field in
`name, qty, price, get_qty, get_percent, max_per_order, pool, reward_pool, windows`).

### Rows: list

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-DEA-001 | Opening `/menu/deals` (nav leaf "Deals" under Catalog ▸ Menu) renders the page; `?edit=…` is kept in the URL alongside the shell's scope params. | none | nav `menu.items.read`, module `pos` | `nav.deals` "Deals" | `routes/_app/menu/deals.tsx:5-10`; `config/nav.ts:115` |
| OFFR-DEA-002 | Without `menu.items.read`: Restricted "Deals" with the default body ("This is managed by Madar…"); GET `/deals` is not asked. Test: "says the page isn't theirs without menu.items.read, and asks for nothing" (`useDeals({}, {enabled:false})`). | none | `menu.items.read` | `deals.title`, `common.restrictedTitle`, `common.restrictedBody` | `dp:41,144` |
| OFFR-DEA-003 | Header: title "Deals" and the description sentence. | none | `menu.items.read` | `deals.title` "Deals", `deals.subtitle` | `dp:148-153` |
| OFFR-DEA-004 | "+ New deal" (primary) sets `?edit=new` (replacing the history entry) which opens the empty dialog. Hidden without `menu.deals.edit`. Test: "offers New deal … update({edit:"new"})". | none | `menu.deals.edit` | `deals.new` "New deal" | `dp:154-160` |
| OFFR-DEA-005 | Reads: the deals (D1) and the pick lists (D2) used for names in the list and for the dialog. | D1, D2 | `menu.items.read` | none | `dp:41-42` |
| OFFR-DEA-006 | Row order: by `sort` ascending, then name A→Z. | none | none | none | `dp:43` |
| OFFR-DEA-007 | Column "Deal" (phone card title): English `name` semibold (not translated) with the Arabic name as a right-to-left muted line under it when present. | none | none | `deals.col.name` "Deal" | `dp:69-86` |
| OFFR-DEA-008 | Column "Rule": N for a price → "Any {{count}} for {{price}}" (price via fmtMoney); buy-get with percent ≥ 100 (or none) → "Buy {{buy}}, get {{get}} free"; otherwise "Buy {{buy}}, get {{get}} at {{percent}}% off". Test: "Buy 2, get 1 free". | none | none | `deals.col.rule` "Rule", `deals.rule.nForPrice`, `deals.rule.buyGetFree`, `deals.rule.buyGetOff` | `dp:87-92`; `du:11-24` |
| OFFR-DEA-009 | Column "Counts" (muted, max 2 lines): the pool as names — an item by name, a category as "All {{name}}", with " (size)" appended when the entry names a size (raw size label) — joined by ", " (Arabic "، "); "—" when empty; when a separate reward list exists " → " + that list. Test: "All Bites". | none | none | `deals.col.pool` "Counts", `deals.pool.categoryNamed` "All {{name}}", `combos.listSeparator` | `dp:93-103`; `du:26-36` |
| OFFR-DEA-010 | Column "When": no window → "Always available"; one window → its summary "days · hours · dates · branch" (e.g. "Every day · 12:00 to 16:00 · 2026-10-01 to … · All branches"); several → "{{count}} windows" (plural). | none | none | `deals.col.when` "When", `combos.windows.always`, `combos.windows.everyDay`, `combos.windows.day.*`, `combos.windows.hoursRange`, `combos.windows.datesRange`, `combos.windows.allBranches`, `deals.windowsCount` | `dp:104-120`; `cu:25-63` |
| OFFR-DEA-011 | Column "Status": green "Active" / neutral "Inactive", plus a small info pill "{{count}} branch exceptions" (plural) when the deal has branch overrides. | none | none | `combos.col.status` "Status", `common.active`, `common.inactive`, `deals.branchExceptions` | `dp:121-139` |
| OFFR-DEA-012 | Clicking a row (Enter/Space, or tapping a phone card) sets `?edit=<id>` and opens that deal in the dialog — editable with `menu.deals.edit`, read-only without. Test: "opens a deal read-only: no Save" / "opens a deal editable with menu.deals.edit". | none | `menu.items.read` | none | `dp:46-47,169` |
| OFFR-DEA-013 | Row action pencil ("Edit") → `?edit=<id>`. | none | `menu.deals.edit` | `common.edit` | `dp:173-175` |
| OFFR-DEA-014 | Row action trash ("Delete") → confirm "Delete {{name}}?" (translated name) / "Tills stop suggesting it and checkout stops applying it. Orders that used it keep it, and it stays in the Bundles report." / red "Delete". Cancel → nothing. | none | `menu.deals.edit` | `deals.deleteTitle` "Delete {{name}}?", `deals.deleteBody`, `common.delete` | `dp:49-57,176-178` |
| OFFR-DEA-015 | Delete confirmed → toast "Deal deleted", `invalidateCombos()` (list refetches). Failure → error toast. | D7 DELETE `/deals/{id}` deleteDeal | `menu.deals.edit` (client + server) | `deals.deleted` "Deal deleted" | `dp:58-64` |
| OFFR-DEA-016 | Without `menu.deals.edit`: no New deal, no Edit/Delete row actions, no button in the empty state. Test: "lists the deals read-only with menu.items.read alone". | none | `menu.deals.edit` | none | `dp:155,170-181,188` |
| OFFR-DEA-017 | Empty: EmptyState (icon BadgePercent) "No deals yet" / "For example: any two pastries for 90, or buy two coffees and get a cookie free." + "+ New deal" (with the right). | none | button: `menu.deals.edit` | `deals.empty`, `deals.emptyHint`, `deals.new` | `dp:182-195` |
| OFFR-DEA-018 | Loading: skeleton rows; failed: ErrorState "Couldn't load this" + server words + Retry. | D1 | none | `common.loadFailed`, `common.retry` | `dp:165-167` |
| OFFR-DEA-019 | Client-side pagination, 10 deals per page (footer when more than 10). | none | none | `common.page`, `common.previous`, `common.next` | `dt:131,172` |
| OFFR-DEA-020 | Columns menu (desktop): Rule, Counts, When, Status. | none | none | `common.columns` | `dp:90,96,107,124` |
| OFFR-DEA-021 | Phone: card titled by the Deal cell, Edit/Delete top-end, Rule / Counts / When / Status as label/value pairs; tap opens the dialog (full-screen sheet in Flutter). | none | none | as above | `dp:72`; `dt:386-427` |
| OFFR-DEA-022 | Deep links: `?edit=new` opens the new-deal dialog only with `menu.deals.edit` (test "does not open a new deal without menu.deals.edit, even from the URL"); `?edit=<id>` opens once the list has loaded and contains it; an unknown id opens nothing (the param stays). | none | `menu.deals.edit` for `new` | none | `dp:45-47` |
| OFFR-DEA-023 | Closing the dialog (Cancel/Close, ×, Esc, outside click, or after a save) removes `edit` from the URL (history replaced). | none | none | none | `dp:200-202`; `data/scope/use-page-search.ts:14-21` |

### Rows: deal dialog

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-DEA-024 | Dialog title "New deal" / "Edit deal"; description "The till suggests it when the cart qualifies and the teller applies it. QR and online checkout apply the best deal by themselves." Scrolls inside (max 92 % of the viewport height), 672 px wide on desktop. Test: heading "Edit deal". | none | `menu.items.read` | `deals.new`, `deals.edit` "Edit deal", `deals.dialogHint` | `dd:121-131` |
| OFFR-DEA-025 | Every time it opens the form is reset: from the deal, or the defaults (Name blank, kind N for a price, How many 2, Price blank, Get 1, Percent off 100, Most times blank, Deal is on, one empty item entry, reward list off, no windows, every branch "Follow the deal"). | none | none | none | `dd:79-81`; `dfs:117-132,148-165` |
| OFFR-DEA-026 | Field "Name" (placeholder "Any 2 bites for 90"): required → "This field is required." | none | `menu.deals.edit` | `deals.fields.name` "Name", `deals.namePlaceholder`, `deals.errors.required` "This field is required." | `dd:136-144`; `dfs:46` |
| OFFR-DEA-027 | Field "Name (Arabic)" (right-to-left, optional). | none | `menu.deals.edit` | `deals.fields.nameAr` "Name (Arabic)" | `dd:145-148` |
| OFFR-DEA-028 | "Kind" segmented control: "N for a price" / "Buy X get Y"; switches which number fields show. Test: clicking "Buy X get Y" shows "Buy". | none | `menu.deals.edit` | `deals.fields.kind` "Kind", `deals.kind.nForPrice` "N for a price", `deals.kind.buyGet` "Buy X get Y" | `dd:151-168` |
| OFFR-DEA-029 | N for a price: "How many" (number) must be a whole number 2–20 → "Use a whole number from 2 to 20."; "Price" (decimal, EGP) must be ≥ 0 and not blank → "Enter a price of 0 or more.". | none | `menu.deals.edit` | `deals.fields.qtyN` "How many", `deals.fields.price` "Price", `deals.errors.qtyN`, `deals.errors.price` | `dd:170-186`; `dfs:64-67` |
| OFFR-DEA-030 | Buy X get Y: "Buy" 1–20 → "Use a whole number from 1 to 20."; "Get" 1–20 → "Use a whole number from 1 to 20."; "Percent off" (hint "100 = free") 1–100 → "Use a percentage from 1 to 100." (the field is marked invalid). Test: percent 150 refused on the field, no request. | none | `menu.deals.edit` | `deals.fields.qtyBuy` "Buy", `deals.fields.get` "Get", `deals.fields.getPercent` "Percent off", `deals.fields.percentHint` "100 = free", `deals.errors.qtyBuy`, `deals.errors.getQty`, `deals.errors.percent` | `dd:187-192,355-383`; `dfs:68-74` |
| OFFR-DEA-031 | Live preview line (shaded) under the numbers, reading the rule as it will show in the list (fallbacks: count 0, price 0, get 1, percent 100). Test: "Any 2 for EGP 90.00". | none | none | `deals.rule.*` | `dd:87-94,194` |
| OFFR-DEA-032 | "Items that count": the pool editor (rows OFFR-DEA-033–036) with list name "Items that count"; empty list on Save → "Add at least one item or category."; hint "A deal covers the item price at its size; add-ons are always charged." | none | `menu.deals.edit` | `deals.fields.pool` "Items that count", `deals.errors.poolEmpty`, `deals.pool.hint` | `dd:196-218`; `dfs:79` |
| OFFR-DEA-033 | Pool entry: "Item"/"Category" segmented (switching clears the target and size); item combobox ("Choose an item", options with cheapest price, search by name or category, "No results found") or category select ("Choose a category"). Test: picks Category → Bites. | none | `menu.deals.edit` | `combos.choice.item`, `combos.choice.category`, `combos.choice.pickItem`, `combos.choice.pickCategory`, `common.search`, `common.noResults` | `pe:38-83` |
| OFFR-DEA-034 | Pool entry size: when the item (or the category's items) has more than one size, a "Size" select: "Any size" (default) + each size ("Standard" for `one_size`). Changing the item/category clears it. | none | `menu.deals.edit` | `deals.pool.size` "Size", `deals.pool.anySize` "Any size", `combos.oneSize` | `pe:47,84-98` |
| OFFR-DEA-035 | Pool entry remove (red trash, "Remove from the list"); entry with nothing chosen on Save → "Choose an item or a category." on that entry. Test: "refuses a pool entry with nothing chosen, on the entry". | none | `menu.deals.edit` | `deals.pool.remove` "Remove from the list", `deals.errors.poolTarget` | `pe:99-116`; `dfs:80-86` |
| OFFR-DEA-036 | Under the list: "Add an item" and "Add a whole category" (hidden read-only). | none | `menu.deals.edit` | `combos.slots.addItem`, `combos.slots.addCategory` | `pe:121-130` |
| OFFR-DEA-037 | Buy X get Y only: bordered box "Reward items" with switch and hint "Off: the free or discounted item comes from the same list. On: from its own list (buy 2 coffees, get a cookie)."; switched on → a second pool editor ("Reward items"); empty → "Add the reward items, or switch the separate list off."; entries checked like the pool. Hidden for N for a price (a leftover reward list is ignored and sent as `[]`). | none | `menu.deals.edit` | `deals.fields.rewardPool` "Reward items", `deals.reward.hint`, `deals.errors.rewardEmpty` | `dd:220-261`; `dfs:87-90` |
| OFFR-DEA-038 | "Most times per order" (number; hint "Blank = no limit"): blank or a whole number ≥ 1 → otherwise "Use a whole number of 1 or more, or leave it blank." | none | `menu.deals.edit` | `deals.fields.maxPerOrder`, `deals.fields.maxHint`, `deals.errors.maxPerOrder` | `dd:263-270`; `dfs:75-78` |
| OFFR-DEA-039 | "Availability": the same windows editor as the combo editor (rows OFFR-CED-051–058: Always available, Add a window, days, hours, dates, branch, and the same errors). | none | `menu.deals.edit` | `combos.sections.availability` + `combos.windows.*` + `combos.errors.noDays/hoursPair/hoursSame/datesOrder` | `dd:272-288`; `dfs:91-101` |
| OFFR-DEA-040 | "Branches" (only when the org has at least one branch): hint "Each branch follows the deal's switch unless set on or off here." and one row per branch with a select (accessible name = branch name): "Follow the deal" / "On here" / "Off here"; opens with the deal's overrides. | none | `menu.deals.edit` | `deals.fields.branches` "Branches", `deals.branchesHint`, `deals.branch.follow` "Follow the deal", `combos.settings.on` "On here", `combos.settings.off` "Off here" | `dd:290-325`; `dfs:163` |
| OFFR-DEA-041 | Switch "Deal is on" (default on). | none | `menu.deals.edit` | `deals.fields.active` "Deal is on" | `dd:327-336` |
| OFFR-DEA-042 | Footer: "Cancel" (with the right) or "Close" (read-only) closes without saving; "Create deal" (new) / "Save" (existing) submits, spinner and disabled while saving; no submit button read-only. | none | submit: `menu.deals.edit` | `common.cancel`, `common.close` "Close", `deals.create` "Create deal", `common.save` | `dd:340-349` |
| OFFR-DEA-043 | Save with errors: the red lines appear on the fields/entries; no request, no toast. | none | none | the `deals.errors.*` / `combos.errors.*` keys above | `dd:133`; `dfs:62-102` |
| OFFR-DEA-044 | Create: POST the deal (`sort` = number of deals currently listed); then the branch calls (D5/D6) for branches set on/off; toast "Deal created"; `invalidateCombos()`; dialog closes. Test body: `{name:"Any 2 bites for 90", name_translations:{}, kind:"n_for_price", qty:2, price:9000, get_qty:null, get_percent:null, max_per_order:null, sort:7, is_active:true, pool:[{category_id:"bites", menu_item_id:null, size_label:null}], reward_pool:[], windows:[]}`, no branch calls. | D3 POST `/deals` createDeal (+ D5/D6) | `menu.deals.edit` | `deals.created` "Deal created" | `dd:95-105`; `dfs:167-186` |
| OFFR-DEA-045 | Update: PUT the deal with its own `sort`; then, in order, a PUT `{is_active}` for every branch newly set "On here"/"Off here" (or flipped) and a DELETE for every branch moved back to "Follow the deal"; toast "Changes saved"; refresh; close. Test: Zamalek on→follow = DELETE b-1, Dokki follow→on = PUT b-3 true, Maadi unchanged = no call. | D4 PUT `/deals/{id}` updateDeal, D5 PUT `/deals/{id}/branches/{branchId}` putDealBranch, D6 DELETE `/deals/{id}/branches/{branchId}` deleteDealBranch | `menu.deals.edit` (branch calls: at that branch) | `common.savedChanges` "Changes saved" | `dd:98-104`; `dfs:193-208` |
| OFFR-DEA-046 | Save failed: error toast; `DEAL_INVALID {field}` names the field in the dialog's words ("Check the deal's \"Percent off\"." etc.); the dialog stays open with what was typed; if the deal call itself failed no branch call is made. (Web quirk: if the deal saved but a branch call failed, the toast shows, nothing is refreshed and the dialog stays open; pressing "Create deal" again would create a second deal.) Test: "surfaces a failed save as a toast and keeps the dialog open". | D3/D4/D5/D6 | none | `errors.codes.DEAL_INVALID` "Check the deal's \"{{field}}\".", `deals.fields.name/qty/price/getQty/getPercent/maxPerOrder/pool/rewardPool/windows` | `dd:44-55,106-111` |
| OFFR-DEA-047 | Read-only dialog (no `menu.deals.edit`): every field disabled, no add/remove entry buttons, no "Add a window", footer "Close" only. Test: "is read-only without edit rights". | none | `menu.deals.edit` | `common.close` | `dd:85,134,342-348`; `pe:99,121` |
| OFFR-DEA-048 | (critic) Pool entries are looser than combo choices: NO duplicate rule (the same item or category may be listed twice), no "Inactive" badge for a switched-off item, no amber border for a missing one (its picker just reads "Choose an item" and the id is re-sent); the item picker lists switched-off items too. Pressing the already selected "Item"/"Category" segment clears the entry's pick and size (as OFFR-CED-081). | none | `menu.deals.edit` | `combos.choice.pickItem` | `pe:38-117`; `dfs:79-90` |
| OFFR-DEA-049 | (critic) Save order and partial failure: the deal call, then every branch PUT one after another, then every branch DELETE one after another, each awaited; the first failing call stops the rest (later branch calls are never sent), shows the error toast, keeps the dialog open and refreshes nothing. | D3/D4, then D5…, then D6… | `menu.deals.edit` | `errors.*` | `dd:95-111`; `dfs:193-208` |
| OFFR-DEA-050 | (critic) The "Counts" and "When" columns take names from the pick lists, which load on their own: while they load (or if they fail) an item reads "—", a category "All —" and a window's branch "—"; the list itself still shows. | D2 | none | `deals.pool.categoryNamed` | `dp:42,99-100,115`; `du:26-36`; `cu:61` |

### 3.1 Formatting and computed values (deals)

- Rule text `dealRuleText` (`du:11-24`): price `fmtMoney(price ?? 0)`; get defaults to 1; free when `get_percent ?? 100 ≥ 100`.
- Pool text `poolText` (`du:26-36`): category → "All {{name}}" (name "—" if unknown), item → name or "—"; size appended
  as ` (label)` using the RAW label (a `one_size` entry would read "(one_size)"; web quirk); joined with
  `combos.listSeparator`.
- Window summary `windowSummary` (`cu:45-63`), parts joined by " · ": weekdays (127 → "Every day", else short day
  names Sunday-first joined by the separator), hours "{{from}} to {{to}}" as raw 24-hour `HH:MM` when both set, dates
  "{{from}} to {{to}}" as raw `YYYY-MM-DD` with "…" for an open end, then the branch name ("—" if unknown) or "All
  branches". (Raw times/dates here are the web's behaviour; reproduce.)
- Sort: `a.sort - b.sort || a.name.localeCompare(b.name)` (`dp:43`).
- Integers (`dfs:37-40`): a blank or non-integer string is invalid; numbers are parsed with `Number(trim)`.

### 3.2 Form ↔ wire (deals)

`dealToWire` (`dfs:167-186`): `{name: trim, name_translations: {ar: trim} or {}, kind, qty: Number, price: (N for
price) piastres (blank → 0) else null, get_qty: (buy-get) Number else null, get_percent: (buy-get) Number else null,
max_per_order: Number or null (blank), sort, is_active, pool: [{menu_item_id (item) | null, category_id (category) |
null, size_label | null}], reward_pool: (buy-get AND switch on) entries else [], windows: windowToWire[]}`.
`dealFromWire` (`dfs:148-165`): price shown only for N for price (`moneyOut`), get 1 / percent 100 when null, cap blank
when null/0, reward switch on only for buy-get with a non-empty reward list, branches from `branch_overrides`
(`is_active` true → "on", false → "off"). `branchChanges` (`dfs:193-208`): compare before/after per branch id; equal →
nothing; after "inherit" → DELETE; else PUT `{is_active: after == "on"}`.

---

## 4. Page `/discounts` (Discounts)

| Field | Value |
|---|---|
| Web path | `/discounts` (file route `/_app/discounts`); search param `edit` = `<discountId>` or `new` opens the dialog. |
| Title | `discounts.title` "Discounts"; sidebar `nav.discounts` "Discounts". Subtitle `discounts.subtitle` "Percentage and fixed-amount discounts". |
| Web files read | `routes/_app/discounts.tsx`, `features/discounts/discounts-page.tsx`, `discount-dialog.tsx`, `util.ts` (+ `discount-schema.test.ts`), `discount-attribution.ts` (+ test; used by other areas), `features/orgs/tax-rate.ts`, `components/app/data-table.tsx`, `stat-card.tsx`, `export-button.tsx`, `bilingual-field.tsx`, `confirm-dialog.tsx`, `empty-state.tsx`, `status-pill.tsx`, `lib/excel.ts`, `lib/format.ts` (`rateOf`, money), `hooks/use-export-logo.ts`, `features/public-shell/use-brand.ts`, `lib/route-prefetch.ts`, generated `Discount`, `CreateDiscountRequest`, `UpdateDiscountRequest`; backend `discounts/routes.rs`, `discounts/handlers.rs`, `discounts/wire.rs`, `permissions/checker.rs`. |
| Capabilities | Nav: `discounts.read`. The page itself has NO client capability check: no `<Restricted>`, and New discount, Export, Edit, Delete and the status toggle are shown to everyone who reaches it. Server: list `discounts.read` [discounts:read]; create `discounts.create` [discounts:create]; PATCH `discounts.edit` [discounts:update]; delete `discounts.delete` [discounts:delete]; all also require the same org (super admin passes). |
| Module | `pos`. |
| Realtime | None. |
| Generated API hooks / ops | `useListDiscounts` (`listDiscounts`, key `["/discounts", {org_id}]`), `createDiscount`, `updateDiscount`, `deleteDiscount`; `usePublicOrgBrand` (`publicOrgBrand`, key `["/public/orgs/brand", {org_id}]`) for the export logo. Route hover prefetches `listDiscounts`. |
| Invalidated after mutations | Every write → `invalidateDiscounts()` (`/discounts*`). |

### Endpoints

| # | Method + path | operationId | Params / body | Enabled when | Server gate |
|---|---|---|---|---|---|
| X1 | GET `/discounts` | `listDiscounts` | `org_id` | an org in scope | `discounts.read` + same org |
| X2 | POST `/discounts` | `createDiscount` | `{org_id, name, name_translations?: {ar}, dtype: "percentage"|"fixed", value, is_active}` | Create | `discounts.create` + same org |
| X3 | PATCH `/discounts/{id}` | `updateDiscount` | dialog: `{name, name_translations (omitted when Arabic blank), dtype, value, is_active}`; status toggle: `{is_active}` | Save / toggle | `discounts.edit` [discounts:update] + same org |
| X4 | DELETE `/discounts/{id}` | `deleteDiscount` | none | confirm | `discounts.delete` + same org |
| X5 | GET `/public/orgs/brand` | `publicOrgBrand` | `org_id` | org in scope (stale 5 min, no retry) | public |

Backend semantics for the mock: X1 returns an unpaginated array of `Discount` (`id, org_id, name, name_translations,
dtype, value (LEGACY integer: 0–100 for a percentage, piastres for fixed), value_rate (fraction for a percentage, e.g.
0.14; piastres for fixed), is_active, created_at, updated_at`). On write the web sends `value` as a FRACTION for a
percentage (0.14) and piastres for fixed; the server stores the fraction (≤ 1) and answers with both spellings.

### Rows

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-DSC-001 | Opening `/discounts` (nav leaf "Discounts" in Catalog) renders the page; `?edit=…` opens the dialog (rows 027+). | X1 | nav `discounts.read`, module `pos` | `nav.discounts` "Discounts" | `routes/_app/discounts.tsx:5-10`; `config/nav.ts:121` |
| OFFR-DSC-002 | No org in scope (platform admin): header "Discounts" and EmptyState (icon Tag) "Select an organization"; nothing asked. | none | none | `discounts.title`, `discounts.pickOrg` "Select an organization" | `xp:36,128` |
| OFFR-DSC-003 | No page-level refusal: a person reaching the URL without `discounts.read` sees the page and the list's error state (403 → "You don't have permission to perform this action." + Retry). A person with `discounts.read` only sees New / Edit / Delete / toggle and is refused by the server on use (error toast with the same words). Reproduce: show the actions, surface the server's refusal. | X1–X4 | server only | `errors.unauthorized` | `xp:29-172` |
| OFFR-DSC-004 | Header: title "Discounts", subtitle "Percentage and fixed-amount discounts"; actions "Export Excel" then "+ New discount". | none | none | `discounts.title`, `discounts.subtitle` | `xp:136-145` |
| OFFR-DSC-005 | Four stat cards (2 columns, 4 from 1024 px): "Total" (all discounts), "Active" (is_active), "Percentage" (dtype percentage), "Fixed amount" (dtype fixed); skeletons while the list loads. | X1 | none | `common.total` "Total", `common.active` "Active", `discounts.percentage` "Percentage", `discounts.fixed` "Fixed amount" | `xp:130-132,146-151` |
| OFFR-DSC-006 | "Export Excel" (outline, download icon): disabled when there is no discount; spinner while exporting. | none | none | `common.export` "Export Excel" | `xp:141`; `components/app/export-button.tsx:25-31` |
| OFFR-DSC-007 | Export: a loading toast "Gathering data…", then the file `Madar-Discounts-YYYY-MM-DD.xlsx` (UTC date) downloads; one sheet "Discounts" with the shop's logo (own-branding tier) or Madar's, title "Discounts", line "Generated: <date time>", frozen header, columns: Discount name (translated; text, width 28), Type ("Percentage"/"Fixed amount"; text, 16), Value (number: percentage as 0–100, fixed as EGP; 14), Status ("Active"/"Inactive"; 12); rows = every discount in list order; toast becomes "Exported {{count}} rows" (plural); on failure "Export failed". | X5 (logo) | none | `discounts.discountName`, `common.type`, `discounts.value`, `common.status`, `discounts.title`, `excel.generating` "Gathering data…", `excel.generated` "Generated", `excel.done` (`_one`/`_other`), `excel.failed` "Export failed" | `xp:39,111-126`; `lib/excel.ts:348-392`; `hooks/use-export-logo.ts:16-19` |
| OFFR-DSC-008 | "+ New discount" sets `?edit=new` → the new-discount dialog. | none | none (server `discounts.create` on save) | `discounts.new` "New discount" | `xp:142` |
| OFFR-DSC-009 | Search box above the table (placeholder and accessible name "Search"): filters in the browser over the raw English name, the type code ("percentage"/"fixed") and the legacy value number; returns to page 1. A search that matches nothing shows the page's empty state "No discounts yet" (web quirk). | none | none | `common.search` "Search", `discounts.empty` | `xp:166-167`; `dt:339-354` |
| OFFR-DSC-010 | Column "Discount name": a 32 px tile with a Percent icon (percentage) or Banknote icon (fixed) and the translated name (Arabic when the UI is Arabic and present). Phone card title. | none | none | `discounts.discountName` "Discount name" | `xp:69-82` |
| OFFR-DSC-011 | Column "Type": outline badge "Percentage" or "Fixed amount". | none | none | `common.type` "Type", `discounts.percentage`, `discounts.fixed` | `xp:83` |
| OFFR-DSC-012 | Column "Value" (numeric): percentage → `formatRate(value_rate)` ("14%", "12.5%"); fixed → `fmtMoney(value_rate)` ("EGP 50.00"). | none | none | `discounts.value` "Value" | `xp:52-53,84` |
| OFFR-DSC-013 | Column "Status": the pill IS a button — green "Active" / neutral "Inactive", accessible name "Deactivate discount" / "Activate discount". Clicking flips `is_active` at once (no confirm, no success toast), the pill is disabled while that request runs, the list refetches; failure → error toast. The click never opens the row. | X3 PATCH `/discounts/{id}` updateDiscount `{is_active}` | server `discounts.edit` | `common.status` "Status", `common.active`, `common.inactive`, `discounts.deactivate` "Deactivate discount", `discounts.activate` "Activate discount" | `xp:48,55-60,85-105` |
| OFFR-DSC-014 | Clicking a row (Enter/Space; tapping a phone card) sets `?edit=<id>` → the edit dialog. | none | none | none | `xp:165` |
| OFFR-DSC-015 | Row action pencil ("Edit") → `?edit=<id>`. | none | none | `common.edit` | `xp:160` |
| OFFR-DSC-016 | Row action trash ("Delete") → confirm "Delete \"{{name}}\"?" (the RAW English name, even in Arabic) / "Cashiers can no longer apply it at checkout. Past orders keep the discount they were given." / red "Delete". Cancel → nothing. | none | none | `common.confirmDelete` "Delete \"{{name}}\"?", `discounts.deleteConsequence`, `common.delete` | `xp:61-62,161` |
| OFFR-DSC-017 | Delete confirmed → list refetches, toast "Discount deleted"; failure → error toast. | X4 DELETE `/discounts/{id}` deleteDiscount | server `discounts.delete` | `discounts.deletedToast` "Discount deleted" | `xp:63` |
| OFFR-DSC-018 | Empty: EmptyState (icon Tag) "No discounts yet" / "Create your first discount to use at checkout." (no button in it). | none | none | `discounts.empty`, `discounts.emptyHint` | `xp:167` |
| OFFR-DSC-019 | Loading: skeleton rows (and stat-card skeletons); failed: ErrorState "Couldn't load this" + server words + Retry. | X1 | none | `common.loadFailed`, `common.retry` | `xp:155-157` |
| OFFR-DSC-020 | Client-side pagination, 10 per page (footer when more than 10). | none | none | `common.page`, `common.previous`, `common.next` | `dt:131,172` |
| OFFR-DSC-021 | Columns menu (desktop): only "Value" can be hidden (the only column with a label). | none | none | `common.columns`, `discounts.value` | `xp:84`; `dt:179,356-377` |
| OFFR-DSC-022 | Phone: stat cards 2×2; each discount a card titled by its name with Edit/Delete top-end and Type, Value, Status as label/value pairs (the status pill stays tappable). | none | none | as above | `xp:146`; `dt:231-279` |
| OFFR-DSC-023 | Deep links: `?edit=new` opens the new dialog for anyone; `?edit=<id>` opens once the list holds that id; an unknown id opens nothing. Closing the dialog (Cancel, ×, Esc, outside, after save) removes `edit` (history replaced). | none | none | none | `xp:43-46,169` |

### Rows: discount dialog

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OFFR-DSC-024 | Dialog title "New discount" / "Edit discount"; description "Percentage and fixed-amount discounts". Mounted only while open. | none | none | `discounts.newTitle` "New discount", `discounts.editTitle` "Edit discount", `discounts.subtitle` | `xd:85-91`; `xp:169` |
| OFFR-DSC-025 | On open the form is filled: name, Arabic name, type, value (percentage → `value_rate × 100` rounded to 4 places, e.g. 14; fixed → EGP, e.g. 50), active; new → empty names, Percentage, 0, active. | none | none | none | `xd:46-66` |
| OFFR-DSC-026 | Bilingual name: "Discount name" (required → "This field is required") and its Arabic box (right-to-left) labelled "Discount name (ع)" in English (Arabic UI: "اسم الخصم (إنجليزي)", see section 5). | none | none | `discounts.discountName`, `bilingualField.arabicLabel` "{{label}} (ع)", `common.requiredField` "This field is required" | `xd:94`; `components/app/bilingual-field.tsx:16-56`; `xu:27` |
| OFFR-DSC-027 | "Type" select: "Percentage" (percent icon) / "Fixed amount" (banknote icon); switching changes the value label, hint and limits. | none | none | `discounts.dtype` "Type", `discounts.percentage`, `discounts.fixed` | `xd:96-107` |
| OFFR-DSC-028 | Value box (number, step 0.5, min 0; max 100 for a percentage): label "Percentage (%)" or "Amount (EGP)"; hint "100% makes the order free." or "More than the order comes to just makes it free — it never pays the customer back." Blank counts as 0. | none | none | `discounts.percentageValue` "Percentage (%)", `discounts.amountValue` "Amount (EGP)", `discounts.percentHint`, `discounts.fixedHint` | `xd:108-119` |
| OFFR-DSC-029 | Value rules: below 0 or not a number → "A discount can't be less than zero."; a percentage above 100 → "Enter a percentage between 0 and 100. 100% makes the order free."; 0 and exactly 100 % are allowed; a fixed amount has no ceiling (200 EGP, 100000 EGP fine). Tests: `discount-schema.test.ts` (5 cases). | none | none | `discounts.valueNegative`, `discounts.percentRange` | `xu:24-58` |
| OFFR-DSC-030 | Browser-native limits (the web form has no `noValidate`): a value that is not a multiple of 0.5, below 0, or above 100 for a percentage is stopped by the browser's own bubble before the form rules run, so in a browser the rules above surface only through it. Flutter has no native bubble: the port must still refuse these values before sending (show the row-029 line for below 0 / above 100, and refuse a value that is not a multiple of 0.5); the exact wording for the 0.5 step is an orchestrator decision (the web has no key for it). | none | none | none (browser text) | `xd:93,111` |
| OFFR-DSC-031 | Switch "Active" on a muted panel with hint "Inactive discounts can't be applied at checkout." | none | none | `common.active`, `discounts.activeHint` | `xd:121-126` |
| OFFR-DSC-032 | Footer: "Cancel" closes; "Create" (new) / "Save" (edit) submits with a spinner while busy. | none | none | `common.cancel`, `common.create` "Create", `common.save` | `xd:127-130` |
| OFFR-DSC-033 | Create: sends `org_id`, `name` exactly as typed (not trimmed; the rule is only "not empty", so spaces pass), `name_translations: {ar}` only when an Arabic name is typed, `dtype`, `value` = percentage → fraction (14 → 0.14, rounded to 6 places) / fixed → piastres (50 → 5000), `is_active`; list refetches; toast "Discount created"; dialog closes. | X2 POST `/discounts` createDiscount | server `discounts.create` | `discounts.createdToast` "Discount created" | `xd:68-77` |
| OFFR-DSC-034 | Update: PATCH with `name`, `name_translations` (omitted when the Arabic box is blank, so a cleared Arabic name is NOT removed; web quirk), `dtype`, `value`, `is_active`; toast "Discount updated"; closes. | X3 PATCH `/discounts/{id}` updateDiscount | server `discounts.edit` | `discounts.updatedToast` "Discount updated" | `xd:70-76` |
| OFFR-DSC-035 | Save failed → error toast (`getErrorMessage`), dialog stays open with the values. | X2/X3 | none | `errors.*` | `xd:78-82` |
| OFFR-DSC-036 | Save with a rule broken: the red line under the field (FormMessage), no request, no toast. | none | none | as rows 026/029 | `xd:93` |
| OFFR-DSC-037 | Esc, × or clicking outside closes the dialog without saving (same as Cancel). | none | none | none | `xd:86` |
| OFFR-DSC-038 | Phone: the dialog becomes a full-screen sheet (Flutter rule); fields stack (the name pair stacks below 640 px; Type/Value stay two columns). | none | none | none | `xd:95`; `components/app/bilingual-field.tsx:19` |
| OFFR-DSC-039 | Arabic UI: page, stats, table, dialog in Arabic; value figures LTR with Latin digits; percentage text "14%" (no Intl, same in both languages). | none | none | Arabic of the keys above | `features/orgs/tax-rate.ts:46-48` |
| OFFR-DSC-040 | (critic) "Export Excel" always writes EVERY discount (the whole list in server order), even while the table search narrows the rows. | X5 (logo) | none | `excel.done` | `xp:111-120` |
| OFFR-DSC-041 | (critic) The search box is an `<input type="search">` (search icon at the start; full width on phone, 288 px from 640 px): the browser's own clear × and Esc empty it. Matching is a case-insensitive substring test (TanStack `includesString`), untrimmed, over `name`, `dtype` and the legacy `value` only (columns whose first row holds a string or number; `is_active` is a boolean and is skipped; the Arabic name is never searched). | none | none | `common.search` | `dt:339-354`; `xp:70,83,84,86`; `@tanstack/table-core` `GlobalFiltering.getColumnCanGlobalFilter`, `filterFns.includesString` |
| OFFR-DSC-042 | (critic) List failed: the table shows the error state, while the four stat cards show 0 (no skeleton, no error) and Export stays disabled. | X1 | none | `common.loadFailed` | `xp:130-151`; `dt:217-224` |
| OFFR-DSC-043 | (critic) Row order is the server's: `ORDER BY name` (the English name, database collation), unchanged in the Arabic UI; the page never re-sorts. Mock: return discounts sorted by `name`. | X1 | none | none | backend `discounts/handlers.rs:86-92`; `xp:37` |
| OFFR-DSC-044 | (critic) An existing discount whose value is not a multiple of 0.5 (12.25 %, EGP 10.25) opens with that value and CANNOT be re-saved from the dialog, not even for a name-only change: the browser's step check blocks Save until the value is moved to a 0.5 step (consequence of OFFR-DSC-030). | none | none | none (browser text) | `xd:58-62,111` |
| OFFR-DSC-045 | (critic) Value field details: its hint line stays visible and the rule's red line appears UNDER it (both shown; the combo price field swaps one for the other); switching Type keeps the typed number as it is (14 % becomes 14 EGP, no conversion, no clearing). Desktop dialog width 512 px (the default; the deal dialog is 672 px). | none | none | `discounts.percentHint`, `discounts.fixedHint` | `xd:95-119`; `components/ui/dialog.tsx:66` |

### 4.1 Formatting and computed values (discounts)

- `rateOf(d)` (`lib/format.ts:350-354`): `value_rate ?? (dtype === "percentage" ? value / 100 : value)` — always read
  `value_rate`; `value` is the legacy integer.
- `formatRate(fraction)` (`features/orgs/tax-rate.ts:46-48`) = `fractionToPercent(f) + "%"`, where
  `fractionToPercent(f) = round(f × 100 × 10000) / 10000` (plain JS number to string: 0.125 → "12.5%"); not localised.
- `percentToFraction(p) = round(p / 100 × 1e6) / 1e6`; `egpToPiastres(egp) = Math.round(egp × 100)`;
  `piastresToEgp(p) = p / 100`.
- Stats: counts over the whole (unpaginated) list.
- Export Value column: percentage → `fractionToPercent(rateOf(d))`; fixed → `piastresToEgp(rateOf(d))`; number cells.
- Excel file name date = `new Date().toISOString().slice(0, 10)` (UTC); "Generated" line uses `fmtDateTimeFull` in the
  active timezone.

---

## 5. i18n keys missing from the web's en.json / ar.json

**None.** Every key the four pages and their shared pieces use was checked against both files
(flattened, with plural suffixes): all `combos.*`, `deals.*`, `discounts.*` keys, `combos.windows.day.sun…sat`,
`deals.fields.getQty/qty/windows/…` (the DEAL_INVALID field words), `errors.codes.COMBO_SLOT_INVALID`,
`errors.codes.DEAL_INVALID`, `common.*` (`active, inactive, edit, delete, cancel, close, save, savedChanges, create,
search, status, total, type, confirmDelete, requiredField, restrictedTitle, restrictedBody, back, loadFailed, retry,
noResults, columns, page, previous, next, actions, export, confirm, select, details`), `uploader.*`, `datePicker.*`,
`inputs.clearTime/timePlaceholder/times/timeUnreadable`, `bilingualField.arabicLabel`, `menu.imageHint`, `excel.*`,
`nav.*`, `dawam.moduleOffTitle/modulePosOff/modulesLoadError`, `errors.*`. No area supplement is needed.

Plural keys the Flutter i18n must resolve with CLDR rules (Arabic has all six forms in ar.json):
`combos.warningCount`, `combos.slots.pickExactly`, `combos.choice.categoryCount`, `deals.windowsCount`,
`deals.branchExceptions`, `excel.done`.

Inline defaults that DIFFER from en.json (en.json wins, so the screen shows the en.json words):

| Key | Inline default in the code | en.json (shown) | Where |
|---|---|---|---|
| `common.search` | "Search…" | "Search" | `xp:166`; `components/app/combobox.tsx:73` |
| `common.confirmDelete` | `Delete "${d.name}"?` (template literal) | "Delete \"{{name}}\"?" | `xp:62` |
| `uploader.choose` | "Upload image" | "Choose Image" | `components/app/image-uploader.tsx:216` |
| `uploader.replace` / `uploader.remove` | "Replace image" / "Remove image" | "Replace" / "Remove" | `components/app/image-uploader.tsx:188,199` |
| `uploader.notAnImage` / `uploader.tooLarge` | "That's not an image file" / "Image is too large" | "Selected file must be an image" / "Image size exceeds 5MB limit" | `components/app/image-uploader.tsx:92,96` |
| `excel.generating` | "Generating spreadsheet…" | "Gathering data…" | `lib/excel.ts:355` |

Copy defects in the web's files worth knowing (reproduce as-is unless the orchestrator decides otherwise):
- `bilingualField.arabicLabel` ar = "{{label}} (إنجليزي)" ("(English)") on the ARABIC name box of the discount dialog.
- `discounts.amountValue` hard-codes "(EGP)" whatever the org currency.

---

## 6. Pieces shared with other areas

| Piece | Web file | Also used by |
|---|---|---|
| `useCombos`, `useCombo`, `setItemMeal`, `useMenuOptions`, `mealDelta`, `slotsAdmitting` | `features/combos/api.ts`, `use-menu-options.ts`, `meal.ts` | catalog_menu (menu studio "Meal" section `features/menu/studio/section-meal.tsx`; PUT `/menu-items/{id}/meal`) |
| `useBundlesReport`, `useComboMix`, `fmtRate`, `rateOf`, `sizeLabelText`, `BundleKind` | `features/combos/api.ts`, `util.ts`, `use-menu-options.ts`, `types.ts` | reports (`/reports/bundles` page and mix dialog) |
| `ComboSettingsPage`, `useComboSettings`, `saveComboSettings`, `putBranchChannels`, `deleteBranchChannels`, `percentToRate`, `rateToPercent` | `features/combos/combo-settings-page.tsx`, `api.ts`, `util.ts` | setup (`/settings/combos`, linked from OFFR-CMB-004 and OFFR-CED-059) |
| `orderRows`, `dealsOf`, `orderDealsTotal`, `ComboHeaderRow`, `ComboPartNote`, `DealLineNote`, `ComboLineFields` | `features/combos/order-lines.ts`, `combo-order-lines.tsx`, `types.ts` | sell (order detail sheet) |
| `discountAttribution`, `discountKindLabel`, `bpsLabel` | `features/discounts/discount-attribution.ts` | sell (order detail sheet), reports (legal ▸ audit tab) |
| `formatRate`, `fractionToPercent`, `percentToFraction`, `MAX_PERCENT` | `features/orgs/tax-rate.ts` | admin/setup (org tax rate) → better in dashboard_core formatters |
| `ONE_SIZE` | `features/menu/util.ts` | catalog_menu |
| Combo editor entry from Menu ▸ Items (combo-kind items open `/menu/combos/{id}`) | `features/menu/menu-items-page.tsx:163` | catalog_menu |
| `WindowsEditor`, window schema (`windowSchema`, `E`, `windowFromWire/ToWire`), `newKey` | `features/combos/windows-editor.tsx`, `form-schema.ts` | combo editor + deal dialog (both this area) |
| `DataTable`, `EmptyState`/`ErrorState`, `Restricted`, `ConfirmProvider/useConfirm`, `ExportButton`, `StatCard`, `StatusPill`, `ImageUploader`, `AssetImage`, `Combobox`, `SegmentedControl`, `DatePicker`, `TimePicker`/`TimeField`, `BilingualField`, `Page`/`PageHeader` | `components/app/*`, `components/inputs/time-field.tsx` | every area → dashboard_kit |
| `exportToExcel`, `useExportLogo` | `lib/excel.ts`, `hooks/use-export-logo.ts` | every exporting page → kit/core |
| `getErrorMessage`, `fmtMoney`, `fmtPercent`, `rateOf`, `egpToPiastres`, `piastresToEgp`, `getTranslatedName`, `useDebounced`, `usePageSearch`, `useScope`, `useAuthz`, `ModuleGate` | `data/api/errors.ts`, `lib/format.ts`, `lib/translation.ts`, `lib/use-debounced.ts`, `data/scope/*`, `data/authz/use-authz.ts`, `components/app/module-gate.tsx` | shell / dashboard_core |

## 7. Notes for the orchestrator

1. Web quirks kept as rows (decide whether parity means copying them): combo delete is gated client-side by
   `menu.combos.edit` but the server checks `menu.items.delete` (OFFR-CMB-021/022, OFFR-CED-012); the combo image
   upload needs `menu.items.edit` server-side (OFFR-CED-074); `/discounts` has no client capability gating at all
   (OFFR-DSC-003); a filtered-to-nothing discount search shows "No discounts yet" (OFFR-DSC-009); the deals "When" and
   "Counts" columns show raw `HH:MM`, raw ISO dates and raw size labels (section 3.1); a deal saved whose branch call
   then fails can be created twice (OFFR-DEA-046); a cleared Arabic discount name is not cleared (OFFR-DSC-034); the
   discount dialog relies on the browser's native step/min/max checks (OFFR-DSC-030); combos list with no org shows the
   empty state, not an error (OFFR-CMB-031).
2. The combo editor is a full page (not a dialog) at every width; deals and discounts edit in dialogs (desktop) /
   full-screen sheets (phone, SPEC 6.1).
3. Mock handlers needed: `/combos` (GET list with q/category_id/is_active/page/per_page, POST), `/combos/{id}`
   (GET, PUT), `/combos/economics` (POST), `/menu-items/{id}` (DELETE), `/uploads/menu-items/{id}` (POST multipart),
   `/menu-items?full=true`, `/categories`, `/branches`, `/deals` (GET, POST), `/deals/{id}` (PUT, DELETE),
   `/deals/{id}/branches/{branchId}` (PUT, DELETE), `/discounts` (GET, POST), `/discounts/{id}` (PATCH, DELETE),
   `/public/orgs/brand`; 403 envelopes `{error: "Forbidden: …"}` (uncoded) for personas without the caps above; coded
   refusals `COMBO_SLOT_INVALID {slot_index}`, `COMBO_SLOTS_REQUIRED`, `COMBO_NESTED`, `DEAL_INVALID {field}`.
4. Personas for refusal tests: reader (`menu.items.read` only), combos editor (`menu.items.read` + `menu.combos.edit`,
   no `menu.items.delete`/`menu.items.edit`), deals editor (`menu.items.read` + `menu.deals.edit`), no-menu
   (`orders.read` only), teller for discounts (`discounts.read` only), owner (all).

## 8. Critic pass (independent re-read, 2026-10-08)

Re-read against `MadarDashboard` `fc2faa42`: the four route files (+ `routes/_app/menu/route.tsx`, a bare `<Outlet/>`),
every file in `features/combos`, `features/deals`, `features/discounts`, and the shared pieces they use
(`components/app/data-table.tsx`, `image-uploader.tsx`, `asset-image.tsx`, `combobox.tsx`, `segmented-control.tsx`,
`date-picker.tsx`, `time-picker.tsx`, `bilingual-field.tsx`, `export-button.tsx`, `restricted.tsx`, `page.tsx`,
`components/ui/dialog.tsx`, `button.tsx`, `lib/excel.ts`, `lib/week.ts`, `data/api/query.ts`, `data/api/errors.ts`,
`data/authz/use-authz.ts`, `data/scope/use-scope.ts`, `use-page-search.ts`, `data/realtime/use-branch-realtime.ts`,
`routes/_app/route.tsx`), plus TanStack Table / Router internals where a behaviour comes from them, and the backend
(`discounts/handlers.rs` order, `uploads/handlers.rs` processing answer, `errors.rs`, `main.rs` extractor errors).

Feature-folder files not covered by this inventory's "web files read" are all owned by other areas (section 6):
`combo-settings-page.tsx` (+ test) → setup; `meal.ts` (+ test) → catalog_menu; `order-lines.ts` (+ test),
`combo-order-lines.tsx` → sell. Nothing in the area was left unread.

- Corrected (5): OFFR-ALL-006 (`/branches` is refreshed by `branch.settings_changed`; the only poll is a processing
  image), OFFR-ALL-012 (a failed background refetch replaces loaded rows with the error state), OFFR-CED-041 (the item
  picker includes switched-off items), OFFR-CED-049 (no error text under size boxes; which sizes get a box),
  OFFR-CED-080 (the not-found message is the server's "Combo not found", not "Not found.").
- Added (27): OFFR-ALL-015–019, OFFR-CMB-034–037, OFFR-CED-081–089, OFFR-DEA-048–050, OFFR-DSC-040–045.
- New web quirks for note 7.1: the combos navigations drop the shell scope (OFFR-CMB-035, the most visible: the price
  check then always reads organisation prices); the stuck empty page after deleting the last combo of the last page
  (OFFR-CMB-036); client tables jump to page 1 after any change (OFFR-ALL-015); open dialogs re-seed on a changed row
  (OFFR-ALL-017); an existing discount off the 0.5 step cannot be re-saved (OFFR-DSC-044); the editor never shows the
  new image until it is re-read (OFFR-CED-084); a dropped non-PNG/JPEG/WebP image is accepted (OFFR-CED-085).
- Extra mock route: GET `/assets/jobs/{id}` (processing thumbnails, OFFR-ALL-016). The mock should also answer GET
  `/combos/{newId}` right after a create (OFFR-CED-086), return discounts sorted by `name` (OFFR-DSC-043), and answer a
  well-formed unknown combo id with 404 `{error: "Not found: Combo not found"}` (OFFR-CED-080).
