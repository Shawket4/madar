# Catalog / Menu area: web parity inventory

Area: `catalog_menu`. Pages: `/menu/items`, `/menu/items/$itemId` (Menu Studio, incl. the recipe grid
and the recipe builder from `features/recipes`), `/menu/groups`, `/menu/pricing`, `/menu/bases`,
`/menu/packaging`. (`/menu/combos*` and `/menu/deals` belong to the combos/deals area.)

Web reference: `/Users/shawket/Desktop/Madar/MadarDashboard`, branch `main` @ `fc2faa42` (v1.4.18). Read-only.
Critic pass (2026-10-08): every file in `src/features/menu/**` and `src/features/recipes/**` re-read; 21 rows added
(marked **(critic)**) and 6 rows corrected (marked **(corrected)**).
All paths below are relative to that repo.

## How to read a row

`| id | behaviour | API call | gate | i18n keys | web source |`

- **API call**: `METHOD /path` + Orval operation name (= `dashboard_api` method). "—" = no call (local draft state).
- **gate**: the web's check. `menu.items.read`, `menu.items.edit`, `recipes.read`, `recipes.edit`,
  `menu.combos.edit`, `menu.packaging_rules.apply` are capabilities (`authz.can`, any-of). "—" = shown to
  anyone who reaches the page (the server decides; a refusal comes back as an error toast).
- **i18n keys**: the web keys; English in quotes is the **en.json** text (which sometimes differs from the
  inline default in the source; en.json wins because the port syncs the JSON). Keys marked **(missing)**
  are not in en.json/ar.json (see §9).
- Toasts are `sonner`. "toast.error(server)" = `toast.error(getErrorMessage(e))`, the server's words.
- "Changes saved" = `common.savedChanges`.
- Responsive: the web's `useIsMobile()` breakpoint is **768 px** (pricing page); the shared grids use
  Tailwind `sm` 640 / `lg` 1024 / `xl` 1280 columns. Flutter uses the SPEC's 760 px split.

### Query-key invalidation helpers (exact predicates)

| Helper | File | Invalidates every query whose key[0] starts with |
|---|---|---|
| `invalidateCatalog()` | `src/features/menu/util.ts:15-30` | `/menu-items`, `/categories`, `/addon-items`, `/branch-menu-overrides`, `/branch-addon-overrides`, `/catalog`, `/costing` (NOT `/modifier-groups`, `/recipe-bases`, `/packaging-rules`, `/inventory`) |
| `invalidateRecipes()` | `src/features/recipes/util.ts:14-27` | `/recipes`, `/menu-items`, `/addon-items`, `/costing`, `/inventory` |
| `invalidateStudio(itemId)` | `src/features/menu/studio/util.ts:17-33` | exact `/menu-items/{id}/studio`, exact `/menu-items/{id}/cost`, plus prefixes `/menu-items`, `/categories`, `/catalog`, `/costing`, `/modifier-groups` |
| `invalidateIngredientCosts(orgId,itemId)` | `studio/util.ts:41-44` | exact `/inventory/orgs/{orgId}/catalog` + `invalidateStudio(itemId)` |
| `invalidatePricingOverrides()` | `src/features/menu/pricing/util.ts:17-27` | `/branch-menu-overrides`, `/branch-addon-overrides`, `/delivery/channel-overrides`, `/delivery/channel-addon-overrides`, and any `/menu-items/…/studio` |

Generated query keys are `[url]` or `[url, params]` (e.g. `listMenuCatalog` → `["/costing/catalog", params]`,
`listCatalog` → `["/inventory/orgs/{orgId}/catalog"]`, `getStudio` → `["/menu-items/{id}/studio"]`).
React Query defaults (`src/data/api/query.ts:42-48`): staleTime 30 s, gcTime 5 min, **no refetch on
window focus**, mutations never retried.

### Operation → HTTP map (every call this area makes)

| Operation | Method + path |
|---|---|
| listMenuCatalog | GET `/costing/catalog` (org_id, category_id, search, has_recipe, page, per_page ≤500, branch_id) |
| listCategories | GET `/categories?org_id` |
| listAddonItems | GET `/addon-items?org_id` |
| listAddonCatalog | GET `/addon-items/catalog` (org_id, search, page, per_page) |
| listAddonCosts | GET `/costing/addon-items?org_id` |
| listBranchMenuOverrides | GET `/branch-menu-overrides?branch_id` |
| listBranchAddonOverrides | GET `/branch-addon-overrides?branch_id` |
| listChannelAddonOverrides | GET `/delivery/channel-addon-overrides?branch_id&channel` |
| listMenuItems | GET `/menu-items?org_id[&full=true]` |
| getMenuItem | GET `/menu-items/{id}` |
| getStudio | GET `/menu-items/{id}/studio` |
| getItemCost | GET `/menu-items/{id}/cost` (only invalidated here, never read in this area) |
| createMenuItem | POST `/menu-items` |
| updateMenuItem | PATCH `/menu-items/{id}` |
| deleteMenuItem | DELETE `/menu-items/{id}` |
| duplicateItem | POST `/menu-items/{id}/duplicate` |
| putSizes | PUT `/menu-items/{id}/sizes` (returns StudioAggregate) |
| putSizeRecipe | PUT `/menu-item-sizes/{sizeId}/recipe` |
| putSizeBase | PUT `/menu-item-sizes/{sizeId}/base` |
| putModifierGroups | PUT `/menu-items/{id}/modifier-groups` |
| putItemOptions | PUT `/menu-items/{id}/options` |
| putRecipeSteps | PUT `/recipes/steps/{menuItemId}` |
| listStepPresets | GET `/recipes/step-presets` |
| getRecipeLink / deleteRecipeLink | GET / DELETE `/menu-items/{id}/recipe-link` |
| previewMenuItem | POST `/menu-items/{id}/preview` (read as a query) |
| putMeal | PUT `/menu-items/{id}/meal` (via combos `setItemMeal`) |
| uploadMenuItemImage | POST `/uploads/menu-items/{menuItemId}` (multipart, field `image`) |
| asset job poll | GET `/assets/jobs/{jobId}` (custom, every 3 s for ≤60 s) |
| createCategory / updateCategory / deleteCategory | POST `/categories` / PATCH `/categories/{id}` / DELETE `/categories/{id}` |
| reorderCategories | PUT `/categories/order` |
| listGroups | GET `/modifier-groups?org_id[&include_inactive=true]` |
| createGroup / patchGroup / deleteGroup | POST `/modifier-groups` / PATCH `/modifier-groups/{gid}` / DELETE `/modifier-groups/{gid}` |
| getGroupUsage | GET `/modifier-groups/{gid}/usage` |
| createOption | POST `/modifier-groups/{gid}/options` |
| patchOption / deleteOption | PATCH / DELETE `/modifier-options/{oid}` |
| putOptionRecipe | PUT `/modifier-options/{oid}/recipe` (body = array of lines) |
| listAddonIngredients | GET `/recipes/addons/{addonItemId}` |
| listCatalog | GET `/inventory/orgs/{orgId}/catalog` |
| createCatalogItem / updateCatalogItem | POST `/inventory/orgs/{orgId}/catalog` / PATCH `/inventory/orgs/{orgId}/catalog/{id}` |
| listIngredientCategories | GET `/inventory/orgs/{orgId}/categories` |
| putPriceOverride / deletePriceOverride | PUT / DELETE `/menu-price-overrides` |
| listBases / createBase | GET / POST `/recipe-bases` |
| patchBase / deleteBase | PATCH / DELETE `/recipe-bases/{id}` |
| putBaseLines | PUT `/recipe-bases/{id}/lines` |
| getBaseUsage | GET `/recipe-bases/{id}/usage` |
| listRules / createRule | GET / POST `/packaging-rules` |
| patchRule / deleteRule | PATCH / DELETE `/packaging-rules/{id}` |
| applyRules | POST `/packaging-rules/apply` |
| listBranches | GET `/branches?org_id` |
| getOrg | GET `/orgs/{id}` |
| listCombos / getCombo | GET `/combos` / GET `/combos/{id}` |

## Contents

| § | Page | Rows |
|---|---|---|
| 0 | Area-wide | MENU-AREA-001 – 014 |
| 1 | `/menu/items` Menu (items, add-ons, categories + their dialogs) | MENU-ITEMS-001 – 115 |
| 2 | Recipe builder (`features/recipes`, inside the item dialog and the add-on recipe dialog) | MENU-RCP-001 – 023 |
| 3 | `/menu/items/$itemId` Menu Studio | MENU-STUDIO-001 – 113 |
| 4 | `/menu/groups` Choice groups (+ group editor, usage dialog) | MENU-GRP-001 – 050 |
| 5 | `/menu/pricing` Pricing & availability | MENU-PRC-001 – 033 |
| 6 | `/menu/bases` Recipe bases | MENU-BAS-001 – 018 |
| 7 | `/menu/packaging` Packaging rules | MENU-PKG-001 – 016 |
| 8 | Formatting and browser-side computations | – |
| 9 | Missing i18n keys | – |
| 10 | Shared pieces | – |
| | **Total** | **382 rows** (361 + 21 critic) |

---

## 0. Area-wide

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-AREA-001 | Sidebar group "Catalog" ▸ parent "Menu" (icon UtensilsCrossed, basePath `/menu`) with leaves in order: Items (CupSoda), Choice groups (ListChecks), Combos, Deals, Pricing & Availability (SlidersHorizontal), Recipe bases (Layers), Packaging rules (Package). Combos/Deals are the combos area's. Parent shows when ≥1 leaf visible; active for any path under `/menu`. | — | per leaf | `nav.catalog` "Catalog", `nav.menu` "Menu", `nav.items` "Items", `nav.choiceGroups` "Choice groups", `nav.pricingAvailability` "Pricing & Availability", `nav.recipeBases` "Recipe bases", `nav.packagingRules` "Packaging rules" | `src/config/nav.ts:101-121` |
| MENU-AREA-002 | Leaf caps: Items, Choice groups, Recipe bases, Packaging rules need `menu.items.read`; Pricing & Availability needs `menu.items.edit`. Every leaf is module `pos` (hidden when the org lacks POS). | — | caps + module `pos` | – | `src/config/nav.ts:110-118`, `leafVisible` `:240-246` |
| MENU-AREA-003 | Command palette lists the same leaves with the same gates. | — | same | same | `src/components/layout/command-palette.tsx` (uses `leafVisible`) |
| MENU-AREA-004 | Module gate: every `/menu/**` path is module `pos`. Modules unknown → renders nothing; modules read failed → ErrorState "Couldn't check what this business has switched on" + server message + Retry; POS off → EmptyState (Blocks icon) "Not part of this business's plan" / "Madar POS is switched off for this business. Ask Madar to switch it on." | GET org modules (shell) | module `pos` | `dawam.modulesLoadError`, `dawam.moduleOffTitle`, `dawam.modulePosOff` | `src/components/app/module-gate.tsx:17-52`, `src/config/nav.ts:258` |
| MENU-AREA-005 | `/menu` redirects to `/menu/items`. | — | — | – | `src/routes/_app/menu/index.tsx:3-7` |
| MENU-AREA-006 | `/menu/recipes` (retired) redirects to `/menu/items` (search params dropped). The cost-missing warning links (§1) still point at `/menu/recipes?item=…` / `?addon=…`, so they land on `/menu/items`. | — | — | – | `src/routes/_app/menu/recipes.tsx:6-10`, `src/components/app/cost-cells.tsx:25-39` |
| MENU-AREA-007 | `/menu/overrides` (retired) redirects to `/menu/pricing`. | — | — | – | `src/routes/_app/menu/overrides.tsx:5-9` |
| MENU-AREA-008 | No route-level capability guard and no `<Restricted>` on any page of this area: a person without the nav cap who types the URL sees the page; reads/writes the server refuses come back as error toasts or (where the page has no error state) as the empty state. | — | — | – | route files; no `Restricted` import in `src/features/menu/**` |
| MENU-AREA-009 | No realtime anywhere in the area (no SSE subscriptions). Data refreshes only on own mutations (invalidation) and on mount/stale (30 s). No refetch on window focus. | — | — | – | `src/data/api/query.ts:42-48` |
| MENU-AREA-010 | No org in scope (platform admin, none picked): Items and Groups show EmptyState (Store icon) "Select an organization to manage its menu"; Pricing shows its header + "Select an organization to manage pricing"; Bases/Packaging render with queries disabled (→ their empty state). | — | — | `menu.pickOrg`, `menu.pricing.pickOrg` | `menu-items-page.tsx:346-353`, `groups-page.tsx:138-144`, `pricing-availability-page.tsx:1231-1238`, `bases-page.tsx:50`, `packaging-rules-page.tsx:56` |
| MENU-AREA-011 | Confirm dialogs are the shared `ConfirmProvider` alert dialog: title + description, Cancel (`common.cancel` "Cancel") and the confirm button (`common.confirm` "Confirm" unless a label is given); `destructive` adds a red warning badge and a destructive confirm button. Esc/outside click = cancel. | — | — | `common.cancel`, `common.confirm` | `src/components/app/confirm-dialog.tsx:33-89` |
| MENU-AREA-012 | Shared top-bar branch scope (`useScope`): Items page shows per-branch availability toggles only when ONE branch is scoped; Pricing needs one branch. | — | — | – | `menu-items-page.tsx:86`, `pricing-availability-page.tsx:1026-1027` |
| MENU-AREA-013 | (critic) Enter in a single-line input inside any dialog FORM (category, item, add-on, group editor, base editor, packaging rule, grid "Scale") submits it, exactly like pressing Save/Apply (browser implicit submission). The lines grids catch Enter only when a cell exists below (focus moves down), so Enter on the LAST row submits the dialog; the "Size label, e.g. Cup" box catches Enter only when non-blank (adds the column; a label that already exists just clears the box, nothing added). Not forms: the studio grid, the pricing matrix, inline card cells (Enter commits the cell) and the fix-cost popover (Enter submits the cost). | (that dialog's save call) | (that dialog's) | – | `label-grid-editor.tsx:48-59, 188-194`; `bases-page.tsx:233`; `packaging-rules-page.tsx:310`; `group-editor-dialog.tsx:330`; `recipe-grid.tsx:563`; `fix-cost-popover.tsx:84-89` |
| MENU-AREA-014 | (critic) No loading state for the org ingredient catalog inside editors: until `GET /inventory/orgs/{orgId}/catalog` lands, seeded lines read "Unknown ingredient" (studio grid, base editor, rule dialog, group per-size grid), the "+ ingredient" / ingredient comboboxes are empty, unit costs are unknown ("—" / "Cost incomplete") and no "Set cost" chip shows (it needs the catalog row). Everything fills in when the read returns. | GET `/inventory/orgs/{orgId}/catalog` listCatalog | — | `modeling.grid.unknownIngredient` | `recipe-grid.tsx:190-197, 211`; `label-grid-editor.tsx:66-69`; `use-ingredient-picker.ts:8-21` |

---

## 1. `/menu/items` Menu

- **Title**: `nav.menu` "Menu"; subtitle `menu.subtitle` "Categories, items and addons" + the price-tax hint.
- **Route**: `src/routes/_app/menu/items.tsx` → `MenuItemsPage`.
- **Files read**: `src/features/menu/menu-items-page.tsx`, `menu-item-dialog.tsx`, `category-dialog.tsx`,
  `category-reorder-list.tsx`, `addon-dialog.tsx`, `addon-recipe-dialog.tsx`, `branch-availability-switch.tsx`,
  `price-tax-hint.tsx`, `costing.ts`, `util.ts`; shared `src/components/app/editable-cards.tsx`,
  `cost-cells.tsx`, `export-button.tsx`, `bilingual-field.tsx`, `image-uploader.tsx`, `asset-image.tsx`,
  `segmented-control.tsx`, `empty-state.tsx`, `confirm-dialog.tsx`; `src/lib/excel.ts`, `export-all.ts`,
  `bulk-runner.ts`, `normalize.ts`, `format.ts`; tests `menu-items-page.test.tsx`, `menu-item-dialog.test.tsx`,
  `menu-item-dialog-groups.test.tsx`, `menu-item-price.test.tsx`, `category-reorder-list.test.tsx`,
  `price-tax-hint.test.tsx`; (critic) also `src/hooks/use-export-logo.ts`, `src/features/public-shell/use-brand.ts`,
  `src/data/api/client.ts`, `src/lib/bulk-runner.ts`. Dead code not ported: `branch-override-dialog.tsx`,
  `branch-addon-override-dialog.tsx`, `overrides-export.ts` (imported nowhere).
- **Gates**: nav `menu.items.read`; recipe filter `recipes.read`; "New group" link in the add-on dialog
  `menu.items.edit`. Everything else on this page is ungated (server decides).
- **Module**: `pos`. **Realtime**: none.
- **Hooks**: `useListCategories`, `useListAddonItems`, `useListMenuCatalog` (keepPreviousData),
  `useListAddonCosts` (only on the Add-ons tab, staleTime 60 s), `useListBranchMenuOverrides` +
  `useListBranchAddonOverrides` (only with one branch scoped), `useGetOrg` (tax hint); mutations
  `useDeleteMenuItem`, `useDeleteOption`, `useDeleteCategory`, `useReorderCategories`, `useCreateCategory`,
  `useUpdateCategory`; imperative `updateMenuItem`, `patchOption`, `updateCategory`, `duplicateItem`,
  `createMenuItem`, `listMenuCatalog` (export), `getStudio`, `putPriceOverride`, `deletePriceOverride`,
  `createOption`, `useListGroups`, `listAddonIngredients`, `putOptionRecipe`, `useListCatalog`,
  `useGetMenuItem`, `putSizes`, `putSizeRecipe`, `putModifierGroups`, `uploadMenuItemImage`.
- **Invalidation**: every mutation on this page → `invalidateCatalog()`; the item dialog save also →
  `invalidateRecipes()`; new ingredient → `invalidateRecipes()`.

### 1a. Page shell, tabs, scope hint

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-ITEMS-001 | Header: title "Menu", subtitle "Categories, items and addons" and under it the price-tax hint line (MENU-ITEMS-002). | GET `/orgs/{id}` getOrg | menu.items.read (nav) | `nav.menu`, `menu.subtitle` | `menu-items-page.tsx:372-375` |
| MENU-ITEMS-002 | Price-tax hint: hidden when the org has no tax (`tax_rate` ≤ 0 or org not loaded); inclusive org → "Prices include tax (14%) · branches may override"; exclusive → "Tax (14%) is added at checkout · branches may override". Rate = `fraction×100` rounded 4 dp + "%". Arabic: "تُضاف الضريبة (14%) عند الدفع". | GET `/orgs/{id}` getOrg | — | `menu.priceIncludesTax`, `menu.priceExcludesTax`, `menu.priceTaxBranchNote` | `price-tax-hint.tsx:15-30`; test `price-tax-hint.test.tsx:20-41` |
| MENU-ITEMS-003 | Segmented tabs under the header: Items / Add-ons / Categories, each with a count badge (`fmtNumber`, mono): items = server `total` of the current query; add-ons = full add-on list length; categories = category count. Default tab Items. Tab is NOT in the URL. | — | — | `nav.items` "Items", `menu.addons` "Addons", `menu.categories` "Categories" | `menu-items-page.tsx:88, 376-384, 583-585` |
| MENU-ITEMS-004 | Branch hint (Items and Add-ons tabs, when no single branch is scoped): Store icon + "Select a branch in the top bar to toggle per-branch availability here." | — | — | `menu.branchToggleHint` | `menu-items-page.tsx:389-394` |
| MENU-ITEMS-005 | No org: header "Menu" + EmptyState (Store) "Select an organization to manage its menu". | — | — | `nav.menu`, `menu.pickOrg` | `menu-items-page.tsx:346-353` |

### 1b. Items tab (card grid)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-ITEMS-006 | Items list: server-paged 24 per page. Request params: org_id, category_id (filter), search (debounced), has_recipe (filter), page (1-based), per_page 24. Previous page stays on screen while the next one loads. | GET `/costing/catalog` listMenuCatalog | menu.items.read | – | `menu-items-page.tsx:120-136` |
| MENU-ITEMS-007 | Loading: 8 skeleton cards (h-28) while the first load / an uncached fetch runs (`isLoading || (isFetching && !data)`). | — | — | – | `menu-items-page.tsx:420`; `editable-cards.tsx:445-450` |
| MENU-ITEMS-008 | Empty: EmptyState (UtensilsCrossed) "No items yet" — also shown when a filter/search matches nothing (no separate "no results" words). | — | — | `menu.noItems` | `menu-items-page.tsx:423`; `editable-cards.tsx:451-452` |
| MENU-ITEMS-009 | Error: the web has NO error state for this read; a failed catalog read leaves no data and renders the empty state (MENU-ITEMS-008). Port the same (do not invent an ErrorState). | GET `/costing/catalog` | — | `menu.noItems` | `menu-items-page.tsx:176, 420-423` |
| MENU-ITEMS-010 | Search box (toolbar start, full width on phone, 224 px from `sm`), placeholder "Search", server-side: debounced 300 ms → `search` param; changing it resets to page 1. | GET `/costing/catalog?search=` | — | `common.search` "Search" | `menu-items-page.tsx:97-98, 112-115, 414-416`; `editable-cards.tsx:409-414` |
| MENU-ITEMS-011 | Category filter select: "All categories" (default) + every category (translated name, in list order) → `category_id`; resets to page 1. | GET `/costing/catalog?category_id=` | — | `menu.allCategories` | `menu-items-page.tsx:426-432` |
| MENU-ITEMS-012 | Recipe filter select (aria-label "Recipe"): "Any recipe" (default) / "No recipe" / "Has a recipe" → `has_recipe` omitted / false / true; resets to page 1. | GET `/costing/catalog?has_recipe=` | recipes.read | `menu.recipeFilter`, `menu.recipeAll`, `menu.recipeMissing`, `menu.recipeHas` | `menu-items-page.tsx:92-94, 125, 433-442` |
| MENU-ITEMS-013 | Refusal: without `recipes.read` the recipe filter is hidden and `has_recipe` is never sent. | — | recipes.read | – | `menu-items-page.tsx:94, 125, 433` |
| MENU-ITEMS-014 | Pagination (only when > 1 page): "Page {{current}} of {{total}}" + Previous / Next icon buttons (chevrons mirrored in RTL), Previous disabled on page 1, Next disabled on the last. | GET `/costing/catalog?page=` | — | `common.page`, `common.previous`, `common.next` | `menu-items-page.tsx:417-419`; `editable-cards.tsx:461-483` |
| MENU-ITEMS-015 | Card layout: grid 1 col (phone) / 2 (≥640) / 3 (≥1024) / 4 (≥1280). Each card: image tile 44 px (asset image, else legacy `image_url`, else CupSoda icon), title = translated name (bold), "⋯" actions menu, a 2-col field grid (Price, Category, Active), a footer (cost lines + branch toggle). | — | — | – | `menu-items-page.tsx:355-368, 397-410`; `editable-cards.tsx:296-354, 454-458`; test `menu-items-page.test.tsx:111-131` |
| MENU-ITEMS-016 | Inline rename: click the title → text input (autofocus); Enter or blur commits when changed (trimmed); Esc cancels; unchanged = no call. Success → toast "Changes saved" + invalidate; failure → toast.error(server). | PATCH `/menu-items/{id}` updateMenuItem `{name}` | — | `common.savedChanges` | `menu-items-page.tsx:201-208, 266`; `editable-cards.tsx:45-133` |
| MENU-ITEMS-017 | Price field is READ-ONLY: shows the item's "from" price (lowest size, `base_price`) as money; clicking does nothing (no editor). | — | — | `common.price` "Price" | `menu-items-page.tsx:269-272`; test `menu-item-price.test.tsx:229-258` |
| MENU-ITEMS-018 | Inline category: select of all categories (translated names); choosing a different one commits. | PATCH `/menu-items/{id}` `{category_id}` | — | `common.category`, `common.savedChanges` | `menu-items-page.tsx:273`; `editable-cards.tsx:78-93` |
| MENU-ITEMS-019 | Inline Active switch: toggling commits immediately. | PATCH `/menu-items/{id}` `{is_active}` | — | `common.active`, `common.savedChanges` | `menu-items-page.tsx:274`; `editable-cards.tsx:74-76` |
| MENU-ITEMS-020 | Cost footer per card (one line per SKU/size): size label (only when >1 size), cost money, food-cost chip (% with icon: <30 % green CheckCircle, 30–40 % amber AlertTriangle, >40 % red AlertCircle), and when `cost_missing` a warning icon link (title "Add ingredient costs to compute this") to `/menu/recipes?item=` (→ redirects to `/menu/items`). No SKUs → "—". | — (data from `sku_costs`) | — | `menu.costMissingFix` | `menu-items-page.tsx:405`; `cost-cells.tsx:9-56` |
| MENU-ITEMS-021 | Branch availability toggle in the footer (only when one branch is scoped): "Available at this branch" switch; on = no override or override `is_available` ≠ false. Disabled while saving. | GET `/branch-menu-overrides?branch_id` listBranchMenuOverrides | — | `menu.overrides.available` | `menu-items-page.tsx:139-148, 406-408`; `branch-availability-switch.tsx:84-139` |
| MENU-ITEMS-022 | Toggle an item OFF at the branch: reads the item's studio, then for EVERY size writes a branch-scope override `is_available:false` keeping any branch price. Toast "Changes saved", invalidate catalog. Error → toast.error(server). | GET `/menu-items/{id}/studio` getStudio; PUT `/menu-price-overrides` putPriceOverride `{scope:"branch", branch_id, target_type:"menu_item_size", target_id:sizeId, price:<branch price or null>, is_available:false}` per size | — | `common.savedChanges` | `branch-availability-switch.tsx:97-134` |
| MENU-ITEMS-023 | Toggle an item ON at the branch: per size, a row with no branch price is DELETED (only if a row exists); a row with a price is PUT with `is_available:null` (keeps the price). | DELETE / PUT `/menu-price-overrides` | — | `common.savedChanges` | `branch-availability-switch.tsx:109-127` |
| MENU-ITEMS-024 | "New item" button (toolbar end, primary, Plus icon) opens the item dialog in create mode (§1f); if a category filter is active it is the dialog's default category. | — | — | `menu.newItem` "New item" | `menu-items-page.tsx:421-422, 575` |
| MENU-ITEMS-025 | Card actions (⋯) for a normal item: "Open full editor (sizes, translations)" → `/menu/items/{id}` (Menu Studio); "Duplicate"; "Delete" (destructive styling). | — | — | `menu.grid.fullEditor`, `menu.grid.duplicate`, `common.delete` | `menu-items-page.tsx:464-484` |
| MENU-ITEMS-026 | Card actions for a combo (`kind === "combo"`): "Open combo editor (slots, availability)" → `/menu/combos/{id}`; NO Duplicate; Delete still offered. | — | — | `menu.grid.comboEditor` | `menu-items-page.tsx:160-164, 466-469`; test `menu-items-page.test.tsx:133-155` |
| MENU-ITEMS-027 | Duplicate (from the grid, no confirm): server deep copy (sizes, recipes, modifier attachments, options, overrides), then the copy is set INACTIVE; toast "Duplicated {{name}}"; invalidate. Error → toast.error(server). | POST `/menu-items/{id}/duplicate` duplicateItem; PATCH `/menu-items/{newId}` `{is_active:false}` | — | `menu.grid.duplicated` | `menu-items-page.tsx:234-246` |
| MENU-ITEMS-028 | Delete item: confirm (destructive) title `Delete "{{name}}"?`, description "It leaves the POS menu at every branch, with its sizes, recipe and branch prices. Past orders keep their lines.", confirm "Delete" → delete; toast "Changes saved"; invalidate. Cancel = nothing. Error → toast.error(server). | DELETE `/menu-items/{id}` deleteMenuItem | — | `common.confirmDelete`, `menu.deleteItemConsequence`, `common.delete`, `common.savedChanges` | `menu-items-page.tsx:186-195, 293-295, 480-482` |
| MENU-ITEMS-029 | Export button ("Export Excel", outline, Download icon) in the toolbar; shows a spinner while busy. | — | — | `common.export` "Export Excel" | `menu-items-page.tsx:443-447`; `export-button.tsx:22-32` |
| MENU-ITEMS-030 | Export run: walks the catalog query with the CURRENT category/search/recipe filters, 500 per request, header `X-Madar-Export: 1`, until empty page/total; > 50,000 rows → error toast "That is about {{rows}} rows, and a spreadsheet built in the browser tops out around {{max}}. Narrow the dates or the branch and try again." | GET `/costing/catalog` listMenuCatalog (paged) | — | `export.tooLarge` | `menu-items-page.tsx:304-313`; `export-all.ts:30-99` |
| MENU-ITEMS-031 | (corrected) Export file: `Madar-Menu-YYYY-MM-DD.xlsx` (UTC date). 3 sheets, each with the logo banner (the org's OWN logo when its public brand has `custom_branding`, else Madar's `/madar.svg`; see MENU-ITEMS-114), "Generated: <date time>" sub-line, zebra rows: **Items** (title "Items") Name (26) · Category (20) · Price money (14, SUM total) · Status Active/Inactive (12), with a TOTALS row; **Categories** Name (24) · Status (12), no totals; **Add-ons** (title "Addons") Name (24) · Type (16) · Price money (14, SUM) · Status (12), TOTALS row. Categories and add-ons are the full lists (the add-on type filter is ignored). | — | — | `nav.items`, `menu.categories`, `menu.addons`, `common.name`, `common.category`, `common.price`, `common.status`, `common.active`, `common.inactive`, `menu.addonType`, `excel.totals` "TOTALS", `excel.generated` | `menu-items-page.tsx:314-338`; `excel.ts:189-300, 373, 380-386`; `src/hooks/use-export-logo.ts` |
| MENU-ITEMS-032 | Export toasts: loading "Gathering data…" → success "Exported {{count}} rows" (plural, total of all sheets) or "Export failed"; nothing to export → "Nothing to export". | — | — | `excel.generating`, `excel.done`, `excel.failed`, `excel.nothingToExport` | `excel.ts:350-393` |
| MENU-ITEMS-033 | "Paste rows" button (outline, ClipboardPaste) opens the paste dialog. | — | — | `grid.pasteRows` "Paste rows" | `editable-cards.tsx:418-423`; `menu-items-page.tsx:450` |
| MENU-ITEMS-034 | Paste dialog step 1: title "Paste rows", description "Paste rows from a spreadsheet (tab- or comma-separated), one row per line.", monospace textarea (8 rows, placeholder `Latte⇥45⏎Cappuccino⇥40`). Delimiter = tab if any line has one, else comma; blank lines dropped; cells trimmed. "Next" disabled while there are no rows; Cancel closes. | — | — | `grid.pasteTitle`, `grid.pasteHint`, `common.next`, `common.cancel` | `editable-cards.tsx:135-139, 143-197, 240-247` |
| MENU-ITEMS-035 | Paste dialog step 2 (map): one select per column "Column {{n}}" with "— ignore —" + Name / "Price (EGP)" / Category / Description; defaults map column i → i-th field (name, base_price, category, description). Preview table with row numbers; ignored columns struck through; invalid rows tinted red with the reason; summary "{{valid}} of {{total}} rows are valid". | — | — | `grid.column`, `grid.ignore`, `grid.pasteSummary`, `common.name`, `common.price`, `common.category`, `common.description` | `editable-cards.tsx:199-238, 245`; `menu-items-page.tsx:451-456` |
| MENU-ITEMS-036 | Paste row validation: empty name → "Name required"; price not a number or < 0 → "Invalid price"; category not matching an existing category name (case-insensitive, trimmed) → "Category must match an existing category". | — | — | `menu.grid.nameRequired`, `menu.grid.priceInvalid`, `menu.grid.categoryUnknown` | `menu-items-page.tsx:457-463` |
| MENU-ITEMS-037 | "Create {{count}}" (disabled when 0 valid; spinner) creates the valid rows, 4 at a time: `{org_id, name, base_price: round(price×100), category_id (by name), description or null}`. Dialog closes and resets after. | POST `/menu-items` createMenuItem ×N | — | `grid.createN` | `editable-cards.tsx:177-187, 248-251`; `menu-items-page.tsx:248-263`; `bulk-runner.ts:18-48` |
| MENU-ITEMS-038 | Paste result toast: all ok → "Created {{count}} items"; some failed → error toast "Created {{ok}}, {{failed}} failed" with action "Retry failed" (re-runs only the failed rows). Always invalidates the catalog. | POST `/menu-items` | — | `menu.grid.bulkCreated`, `menu.grid.bulkCreateFailed`, `menu.grid.retryFailed` | `menu-items-page.tsx:255-262` |

### 1c. Add-ons tab (card grid)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-ITEMS-039 | Add-ons list: all add-ons, loaded on page mount (powers the tab badge). Client-side search + client pagination 24 per page. | GET `/addon-items?org_id` listAddonItems | — | – | `menu-items-page.tsx:135, 487-503` |
| MENU-ITEMS-040 | Add-on cost rollup loaded only while the Add-ons tab is active (cached 60 s). | GET `/costing/addon-items?org_id` listAddonCosts | — | – | `menu-items-page.tsx:137`; `costing.ts:11-14` |
| MENU-ITEMS-041 | Loading: 8 skeleton cards while the add-on list loads. | — | — | – | `menu-items-page.tsx:503` |
| MENU-ITEMS-042 | Empty (no add-ons, or nothing matches search/type): EmptyState (Tag) "No add-ons yet". No error state (failed read → empty). | — | — | `menu.noAddons` | `menu-items-page.tsx:506`; `editable-cards.tsx:451-452` |
| MENU-ITEMS-043 | Search "Search" (client): matches `name + type`, case/diacritic-insensitive (NFKD, strips Latin accents and Arabic tashkeel); resets to page 1. | — | — | `common.search` | `menu-items-page.tsx:502`; `editable-cards.tsx:377-389`; `src/lib/normalize.ts` |
| MENU-ITEMS-044 | Type filter select (only when ≥1 type exists): "All types" + each distinct `addon_type` (raw value, sorted). | — | — | `menu.allTypes` | `menu-items-page.tsx:290-291, 507-517` |
| MENU-ITEMS-045 | Client pagination (same pager as MENU-ITEMS-014) when > 24 add-ons after filtering. | — | — | `common.page`, `common.previous`, `common.next` | `editable-cards.tsx:383-389, 461-483` |
| MENU-ITEMS-046 | Add-on card: Tag icon tile, title (translated name), fields Type (text), Price (money), Active (switch); footer: cost line (cost money, food-cost chip = cost/price when price > 0, missing-cost link to `/menu/recipes?addon=`) + branch toggle when one branch is scoped. | — | — | `menu.addonType` "Type", `common.price`, `common.active` | `menu-items-page.tsx:279-284, 487-500`; `cost-cells.tsx:59-69` |
| MENU-ITEMS-047 | Inline rename add-on → patch the option's name. Toast "Changes saved". | PATCH `/modifier-options/{oid}` patchOption `{name}` | — | `common.savedChanges` | `menu-items-page.tsx:209-223` |
| MENU-ITEMS-048 | Inline price (money): click → number input pre-filled in EGP; commit when changed and ≥ 0 (invalid/negative silently ignored) → piastres. | PATCH `/modifier-options/{oid}` `{price}` | — | `common.savedChanges` | `menu-items-page.tsx:215, 282`; `editable-cards.tsx:56-72` |
| MENU-ITEMS-049 | Inline Active switch. | PATCH `/modifier-options/{oid}` `{is_active}` | — | `common.savedChanges` | `menu-items-page.tsx:216, 283` |
| MENU-ITEMS-050 | Inline Type edit (web quirk): the Type cell opens a text input, but the commit maps only name/price/active, so a type change sends an EMPTY patch and still toasts "Changes saved" (the type never changes; moving groups = recreate). Port: same visible behaviour (or render read-only and note it). | PATCH `/modifier-options/{oid}` `{}` | — | `common.savedChanges` | `menu-items-page.tsx:209-223, 281` |
| MENU-ITEMS-051 | Branch toggle for an add-on (one branch scoped): reads branch add-on overrides; OFF → PUT branch-scope row `is_available:false` keeping any price; ON with no price → DELETE the row; ON with a price → PUT `is_available:null`. Toast "Changes saved"; invalidate. Switch disabled while saving. | GET `/branch-addon-overrides?branch_id`; PUT/DELETE `/menu-price-overrides` `{scope:"branch", branch_id, target_type:"modifier_option", target_id}` | — | `menu.overrides.available`, `common.savedChanges` | `menu-items-page.tsx:143, 149-153, 496-498`; `branch-availability-switch.tsx:39-82` |
| MENU-ITEMS-052 | "New add-on" button opens the add-on dialog (create). | — | — | `menu.newAddon` "New add-on" | `menu-items-page.tsx:504-505, 576` |
| MENU-ITEMS-053 | Add-on actions (⋯): "Edit" (opens add-on dialog with the add-on), "Edit recipe" (opens the add-on recipe dialog), "Delete" (destructive). | — | — | `common.edit`, `menu.addonRecipe.edit` "Edit recipe", `common.delete` | `menu-items-page.tsx:518-530` |
| MENU-ITEMS-054 | Delete add-on: confirm (destructive) `Delete "{{name}}"?` / "It is removed from every item that offers it. If orders used it, it is deactivated instead so history stays intact." / "Delete" → delete option; toast "Changes saved"; invalidate. | DELETE `/modifier-options/{oid}` deleteOption | — | `common.confirmDelete`, `menu.deleteAddonConsequence`, `common.delete` | `menu-items-page.tsx:194, 526` |
| MENU-ITEMS-055 | Hovering the Add-ons tab label pre-loads the add-on list and costs (perf only). | GET `/addon-items`, GET `/costing/addon-items` | — | – | `menu-items-page.tsx:169-173, 381` |

### 1d. Categories tab

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-ITEMS-056 | Categories list (all, server order = POS order): client search + client pagination 24. | GET `/categories?org_id` listCategories | — | – | `menu-items-page.tsx:132, 542-553` |
| MENU-ITEMS-057 | Loading skeleton cards; empty EmptyState (Tag) "No categories yet" (also when search matches nothing). No error state. | — | — | `menu.noCategories` | `menu-items-page.tsx:550-553` |
| MENU-ITEMS-058 | Search (client) matches `name + translated name`, normalized. | — | — | `common.search` | `menu-items-page.tsx:549` |
| MENU-ITEMS-059 | Category card: image tile (asset/legacy url, else Tag icon), title (translated name), Active switch field. No footer. | — | — | `common.active` | `menu-items-page.tsx:285-288, 547` |
| MENU-ITEMS-060 | Inline rename category. | PATCH `/categories/{id}` updateCategory `{name}` | — | `common.savedChanges` | `menu-items-page.tsx:224-231` |
| MENU-ITEMS-061 | Inline Active switch. | PATCH `/categories/{id}` `{is_active}` | — | `common.savedChanges` | `menu-items-page.tsx:287` |
| MENU-ITEMS-062 | "New category" button opens the category dialog (create). | — | — | `menu.newCategory` "New category" | `menu-items-page.tsx:551-552, 578` |
| MENU-ITEMS-063 | Category actions (⋯): "Edit" (category dialog), "Delete". | — | — | `common.edit`, `common.delete` | `menu-items-page.tsx:561-570` |
| MENU-ITEMS-064 | Delete category: confirm (destructive) `Delete "{{name}}"?` / "The category and its kitchen routing are removed. Its items stay on the menu without a category." → delete; toast; invalidate. | DELETE `/categories/{id}` deleteCategory | — | `common.confirmDelete`, `menu.deleteCategoryConsequence` | `menu-items-page.tsx:195, 566` |
| MENU-ITEMS-065 | "Reorder" button (outline, toolbar) shown only when > 1 category → reorder mode. | — | — | `menu.categoriesReorder` "Reorder" | `menu-items-page.tsx:554-560` |
| MENU-ITEMS-066 | Reorder mode: "Done" button (top end) returns to the grid; hint "Drag to reorder — this is the order the POS shows categories in."; ordered list rows: drag handle, image tile (36 px), translated name, Move up / Move down icon buttons (up disabled on first, down on last). Loading → nothing; empty → "No categories yet". | — | — | `menu.categoriesDoneReordering` "Done", `menu.categoriesReorderHint`, `menu.studio.steps.moveUp` "Move up", `menu.studio.steps.moveDown` "Move down", `menu.noCategories` | `menu-items-page.tsx:532-540`; `category-reorder-list.tsx:95-183`; test `category-reorder-list.test.tsx:18-38` |
| MENU-ITEMS-067 | Reorder by drag (pointer after 4 px; keyboard: Space pick up, arrows move, Space drop; handle aria-label `Drag "{{name}}" to reorder`) or by the arrows: list reorders at once (optimistic) and the whole order is saved; success toast "Changes saved" + invalidate; failure → list rolls back to the server order + toast.error(server). | PUT `/categories/order` reorderCategories `{org_id, ordered_ids}` | — | `menu.categoriesDragToReorder`, `common.savedChanges` | `category-reorder-list.tsx:54-93, 145-153` |

### 1e. Category dialog (`category-dialog.tsx`; also opened from the item dialog and the studio)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-ITEMS-068 | Open/close: title "New category" / "Edit category", description "Categories group your menu items."; Cancel closes; reset on every open (name, Arabic name from `name_translations.ar`, active). | — | — | `menu.newCategory`, `menu.editCategory`, `menu.categoryDesc`, `common.cancel` | `category-dialog.tsx:54-62, 95-100, 120-123` |
| MENU-ITEMS-069 | Field Name (EN) required — zod `min(1)` "This field is required"; Name (Arabic) optional, label "Name (ع)", RTL. | — | — | `common.name`, `common.requiredField`, `bilingualField.arabicLabel` | `category-dialog.tsx:38-46, 103`; `bilingual-field.tsx:16-55` |
| MENU-ITEMS-070 | Field Active switch (default on). Web quirk: on CREATE the switch value is NOT sent (a new category is always created active); on edit it is sent. | — | — | `common.active` | `category-dialog.tsx:105-118, 82-92` |
| MENU-ITEMS-071 | Save (spinner while pending): create → `{org_id, name, name_translations:{ar} or omitted}`; edit → `{name, name_translations, is_active}`. Success: toast "Changes saved", invalidate catalog, close; a created category is handed back (the item dialog / studio auto-selects it). Error → toast.error(server), dialog stays. | POST `/categories` createCategory / PATCH `/categories/{id}` updateCategory | — | `common.save`, `common.savedChanges` | `category-dialog.tsx:64-92, 124-126` |

### 1f. Item dialog (`menu-item-dialog.tsx`, create from this page; edit mode reached from onboarding)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-ITEMS-072 | Open/close: title "New item" (create) / "Edit item" (edit); description "Define the product, price and category."; scrollable (max 92 vh), wide (672 px). Cancel closes. Every open resets the form (create: one Price box at 0, category = active filter or empty, active on; staged image and add-on search cleared). | — | — | `menu.newItem`, `menu.editItem`, `menu.itemDesc`, `common.cancel` | `menu-item-dialog.tsx:143-167, 301-306, 633-636` |
| MENU-ITEMS-073 | Edit mode loads the full item (sizes from `all_sizes` incl. the hidden `one_size`, only active sizes, prices in EGP; offered add-on ids). | GET `/menu-items/{id}` getMenuItem | — | – | `menu-item-dialog.tsx:79, 170-186` |
| MENU-ITEMS-074 | Loads the ingredient catalog, all add-ons and the modifier groups while open. | GET `/inventory/orgs/{orgId}/catalog` listCatalog; GET `/addon-items` listAddonItems; GET `/modifier-groups` listGroups | — | – | `menu-item-dialog.tsx:80-84` |
| MENU-ITEMS-075 | Name (EN) required "This field is required"; Name (ع) optional. | — | — | `common.name`, `common.requiredField`, `bilingualField.arabicLabel` | `menu-item-dialog.tsx:89-90, 309` |
| MENU-ITEMS-076 | Description (EN) and Description (ع), textareas, optional. | — | — | `common.description` | `menu-item-dialog.tsx:91-92, 310` |
| MENU-ITEMS-077 | Category select (placeholder "Select category", translated names) — required "This field is required". | — | — | `common.category`, `menu.selectCategory`, `common.requiredField` | `menu-item-dialog.tsx:93, 315-343` |
| MENU-ITEMS-078 | "+" outline icon button next to the category (tooltip "New category") opens the category dialog on top; the created category is selected and validated. | POST `/categories` (via MENU-ITEMS-071) | — | `menu.newCategory` | `menu-item-dialog.tsx:336-338, 646-654` |
| MENU-ITEMS-079 | Active switch (label after the switch). Web quirk: on CREATE `is_active` is not sent (new items are created active even if switched off); on edit it is sent. | — | — | `common.active` | `menu-item-dialog.tsx:347-358, 202-204` |
| MENU-ITEMS-080 | Image (create): label "Image"; picking a file only stages it (local preview), hint "Uploads after the item is saved"; Remove (×) drops the staged file. Uploaded after the item is saved. | POST `/uploads/menu-items/{id}` uploadMenuItemImage (after save) | — | `menu.itemImage`, `menu.imageAfterSave` | `menu-item-dialog.tsx:362-363, 389-410, 232-234` |
| MENU-ITEMS-081 | Image (edit): picking uploads immediately; the server may answer "processing" with an asset job → the box shows a spinner + "Processing…" (role=status) and polls the job every 3 s for up to 60 s; done → shows the tile and invalidates the catalog; failed → "The image could not be processed". Hint "PNG/JPG/WebP, up to 5 MB". | POST `/uploads/menu-items/{id}`; GET `/assets/jobs/{jobId}` | — | `menu.imageHint`, `uploader.processing`, `uploader.processingFailed` | `menu-item-dialog.tsx:364-388`; `image-uploader.tsx:64-80`; test `menu-item-dialog.test.tsx:87-107` |
| MENU-ITEMS-082 | Image (edit) remove button (only when the item has an image or asset) → clears it at once (`image_url: null` also clears the asset); invalidate. | PATCH `/menu-items/{id}` `{image_url:null}` | — | `uploader.remove` | `menu-item-dialog.tsx:379-386`; test `menu-item-dialog.test.tsx:78-85` |
| MENU-ITEMS-083 | (corrected) Image uploader shared behaviour: empty box button "Choose Image" (spinner "Uploading..."); drag-and-drop onto the box; with an image: Replace (upload icon) and Remove (×) buttons (always visible on touch, on hover with a mouse); client refusals: not an image → "Selected file must be an image"; > 5 MB → "Image size exceeds 5MB limit"; upload error → its message under the box. That text is the raw JS error message, NOT the server's words: an API failure shows Axios's technical text (e.g. "Request failed with status code 413") under the box, with no toast and no `getErrorMessage`; a failed Remove (item dialog edit: PATCH `image_url:null`) shows the same way under the box. A failed processing job shows the job's own `error` text when present, else "The image could not be processed". Accepts png/jpeg/webp. | — | — | `uploader.choose`, `uploader.uploading`, `uploader.replace`, `uploader.remove`, `uploader.notAnImage`, `uploader.tooLarge` | `image-uploader.tsx:43-238` (errors `:66-80, 88-128`); `src/data/api/client.ts:68-97` (errors are not rewritten) |
| MENU-ITEMS-084 | Price section, single-price item (exactly one size labelled `one_size`): heading "Price", one "Price (EGP)" input (step 0.01, min 0) with the price-tax hint under it, and "Add a size to charge different prices for different sizes.". The `one_size` label is never shown. No item-level price field exists anywhere. | — | — | `menu.priceSection`, `common.price`, `menu.addSizeHint` | `menu-item-dialog.tsx:414-456`; test `menu-item-price.test.tsx:93-146` |
| MENU-ITEMS-085 | "Add size" (outline, Plus): from single-price mode the sentinel label is blanked (so both sizes must be named) and a new empty size row is added; heading becomes "Sizes". | — | — | `menu.addSize`, `menu.sizes` | `menu-item-dialog.tsx:421-435`; test `menu-item-price.test.tsx:206-226` |
| MENU-ITEMS-086 | Multi-size rows: Label (placeholder "Large") required "This field is required"; Price (EGP) ≥ 0; "Remove size" icon (aria "Remove size") disabled while only one size remains. | — | — | `menu.sizeLabel` "Label", `common.price`, `menu.removeSize`, `common.requiredField` | `menu-item-dialog.tsx:98-106, 457-502`; test `menu-item-price.test.tsx:178-204` |
| MENU-ITEMS-087 | (corrected) Sizes array min 1 → "An item needs at least one price." No field renders this array-level error. It IS reachable in EDIT mode: the form opens with `sizes: []` until the full item read lands (and stays empty if that read fails), the Price section shows the "Sizes" heading with no rows, and Save then fails validation with NOTHING visible (no message, no toast, no request). In create mode the last remove is disabled, so it cannot happen there. | — (GET `/menu-items/{id}` pending/failed) | — | `menu.needsOneSize` | `menu-item-dialog.tsx:79, 106, 148-157, 170-186, 418` |
| MENU-ITEMS-088 | Recipe section: heading "Recipe" + "What this item consumes, per size"; embedded recipe builder (§2) in deferred mode (no own save), one block per size label (or "One size"), plus any size label still on saved recipe rows; "New ingredient" not offered here. | — | — | `menu.recipe`, `menu.recipeHint` | `menu-item-dialog.tsx:119-136, 505-521` |
| MENU-ITEMS-089 | Add-ons section: heading "Addons" + "Which addons customers can pick for this item" (missing key). Selected add-ons as chips with × (aria "Remove"); none → "No addons selected — the full org catalog applies." (missing key). | — | — | `menu.addons`, `menu.addonsHint` (missing), `menu.addonsEmpty` (missing), `common.remove` | `menu-item-dialog.tsx:524-555` |
| MENU-ITEMS-090 | Add-on picker: search box "Search addons…" (client, name contains, case-insensitive); groups by add-on type, header = humanized type (`milk_type` → "Milk", `extra_shot` → "Extra Shot") + "(n)", per-group "Select all" / "Deselect all"; each add-on a toggle chip (selected = filled); nothing matches → "No addons match" (missing key). List scrolls (max 208 px). | — | — | `menu.searchAddons`, `common.selectAll`, `common.deselectAll`, `menu.noAddonsMatch` (missing) | `menu-item-dialog.tsx:57-60, 271-297, 557-629` |
| MENU-ITEMS-091 | Save (spinner): validates; then in order — create `{org_id, name, name_translations, description|null, description_translations, category_id, base_price = lowest size price}` or update `{…, is_active}` (never `base_price`); replace sizes `{label, price, sort i, is_active:true}`; for every size returned, replace that size's recipe with the builder's rows for that label (only rows linked to a catalog ingredient); (create) upload staged image; offered add-ons → group attachments (each selected add-on's type → the group whose `legacy_addon_type` (or name) equals it, `{group_id, sort, included_option_ids}`), sent ONLY when the selection changed (an emptied selection sends `groups: []`). | POST `/menu-items` or PATCH `/menu-items/{id}`; PUT `/menu-items/{id}/sizes` putSizes; PUT `/menu-item-sizes/{sid}/recipe` putSizeRecipe ×sizes; POST `/uploads/menu-items/{id}`; PUT `/menu-items/{id}/modifier-groups` putModifierGroups | — | – | `menu-item-dialog.tsx:188-261`; tests `menu-item-price.test.tsx:101-176`, `menu-item-dialog-groups.test.tsx:100-140` |
| MENU-ITEMS-092 | Save success: toast "Changes saved"; invalidate catalog AND recipes; close. Failure at any step: toast.error(server); dialog stays open (earlier writes stand). | — | — | `common.save`, `common.savedChanges` | `menu-item-dialog.tsx:262-268, 637-639` |

### 1g. Add-on dialog (`addon-dialog.tsx`; also used by onboarding)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-ITEMS-093 | Open/close: title "New add-on" / "Edit add-on"; description "Add-ons are modifiers like extra shots or milk types."; reset on open (price shown in EGP). Loads groups while open. | GET `/modifier-groups?org_id` listGroups | — | `menu.newAddon`, `menu.editAddon`, `menu.addonDesc` | `addon-dialog.tsx:62-63, 88-98, 139-144` |
| MENU-ITEMS-094 | Name (EN) required "This field is required"; Name (ع) optional. | — | — | `common.name`, `common.requiredField` | `addon-dialog.tsx:73-74, 147` |
| MENU-ITEMS-095 | Group select "Group" (placeholder "Select…"): only shared groups (`legacy_addon_type` set); required "This field is required". | — | — | `menu.groups.addonGroup`, `common.select`, `common.requiredField` | `addon-dialog.tsx:66, 75, 149-168` |
| MENU-ITEMS-096 | Editing: the group select shows the add-on's current group (found by option id) and is DISABLED, with the note "The type (group) can't change — recreate the add-on to move it." | — | — | `menu.addonTypeLocked` | `addon-dialog.tsx:101-104, 155, 169-172` |
| MENU-ITEMS-097 | Create: "New group" link (Plus) under the select opens the choice-group editor (§4c) on top; after it saves, groups refetch and the new group is selected. | (group editor calls) | menu.items.edit | `menu.groups.new` "New group" | `addon-dialog.tsx:68, 173-177, 222-233` |
| MENU-ITEMS-098 | Refusal: without `menu.items.edit` the "New group" link is hidden. | — | menu.items.edit | – | `addon-dialog.tsx:173` |
| MENU-ITEMS-099 | "Default price (EGP)" number (step 0.01, min 0) — zod `coerce.number().min(0)` (zod default English message on < 0). | — | — | `menu.defaultPrice` | `addon-dialog.tsx:76, 182-194` |
| MENU-ITEMS-100 | Active switch (default on). | — | — | `common.active` | `addon-dialog.tsx:196-210` |
| MENU-ITEMS-101 | Save: create → new option in the chosen group `{name, name_translations, price (piastres), is_active}`; edit → patch the option with the same fields. Toast "Changes saved", invalidate catalog, close. Error → toast.error(server). | POST `/modifier-groups/{gid}/options` createOption / PATCH `/modifier-options/{oid}` patchOption | — | `common.save`, `common.savedChanges` | `addon-dialog.tsx:106-134, 212-219` |

### 1h. Add-on recipe dialog (`addon-recipe-dialog.tsx`)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-ITEMS-102 | Open from "Edit recipe": title "Add-on recipe"; description "<add-on name> — Ingredients deducted from stock when this add-on is chosen."; width 672 px. Close by Esc/×. | — | — | `menu.addonRecipe.title`, `menu.addonRecipe.desc` | `addon-recipe-dialog.tsx:72-80` |
| MENU-ITEMS-103 | Loads the add-on's ingredient lines (spinner while loading) and the ingredient catalog. | GET `/recipes/addons/{id}` listAddonIngredients; GET `/inventory/orgs/{orgId}/catalog` listCatalog | — | – | `addon-recipe-dialog.tsx:40-54, 81-86` |
| MENU-ITEMS-104 | Body: the recipe builder (§2) with ONE column "One size", margin computed against the add-on's default price, "New ingredient" offered, no copy-from, its own "Save recipe" footer. | — | — | `recipes.oneSize` | `addon-recipe-dialog.tsx:87-104` |
| MENU-ITEMS-105 | Save recipe: replace-set of lines linked to a catalog ingredient `[{ingredient_id, quantity, unit}]` → invalidate catalog → toast "Recipe saved" → close. Error → toast.error(server), dialog stays dirty. | PUT `/modifier-options/{oid}/recipe` putOptionRecipe | — | `recipes.builder.saved` | `addon-recipe-dialog.tsx:56-70` |

### 1i. Items page: non-visible behaviours (no driven test needed)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-ITEMS-106 | Hover/focus an item card or its ⋯ button pre-loads the item and its studio. | GET `/menu-items/{id}`, GET `/menu-items/{id}/studio` | — | – | `menu-items-page.tsx:156-159`; `editable-cards.tsx:309-334` |
| MENU-ITEMS-107 | Hover/focus "Next" pre-loads the next items page. | GET `/costing/catalog?page=n+1` | — | – | `menu-items-page.tsx:165-168`; `editable-cards.tsx:475-476` |

### 1j. Critic additions

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-ITEMS-108 | (critic) Web quirk: the three tabs render the SAME `EditableCardGrid` instance (same slot, no `key`), so its internal state survives tab switches: the client-side search text and page typed on Add-ons carry over to Categories (and back) and survive a trip through Items (Items shows its own page-level search instead). E.g. search "milk" on Add-ons → Categories opens filtered by "milk" with "milk" in its box. Page state also persists across tabs: category filter, recipe filter, items search/page, add-on type filter, category reorder mode. Port: one shared client search/page for Add-ons + Categories (or document the deviation). | — | — | `common.search` | `menu-items-page.tsx:388-572`; `editable-cards.tsx:359-389` |
| MENU-ITEMS-109 | (critic) Inline title edits have no client validation: clearing an item / add-on / category name and pressing Enter (or blurring) sends `{name: ""}`; the server decides, a refusal → toast.error(server) and the card shows the old name again (no invalidation on failure). Inline money edits that are blank / negative / non-numeric are dropped silently instead (MENU-ITEMS-048). | PATCH `/menu-items/{id}` · `/modifier-options/{oid}` · `/categories/{id}` `{name:""}` | — | – | `editable-cards.tsx:56-71`; `menu-items-page.tsx:197-231` |
| MENU-ITEMS-110 | (critic) Untranslated (raw `name`, English even in the Arabic UI) in: the delete confirms' title `Delete "{{name}}"?` (items, add-ons, categories), the grid duplicate toast "Duplicated {{name}}", the add-on recipe dialog description "<name> — …", the item dialog's selected add-on chips and picker chips, and the add-on dialog's Group select (group `name`). Cards, filters, category selects and the export use the translated name. | — | — | `common.confirmDelete`, `menu.grid.duplicated`, `menu.addonRecipe.desc` | `menu-items-page.tsx:242, 293-295, 480, 526, 566`; `addon-recipe-dialog.tsx:78`; `menu-item-dialog.tsx:539, 620`; `addon-dialog.tsx:162-166` |
| MENU-ITEMS-111 | (critic) Paste details: no header-row detection (a pasted header line is just row 1, normally "Invalid price"); the map step has no Back button (Cancel / Esc / outside click discards the pasted text and mapping; reopening starts empty); category cells match the raw English category `name` only (trimmed, case-insensitive), so an Arabic category name never matches; price cells go through `parseFloat`, so "45 EGP" is accepted as 45; created rows send `description` = mapped text or null and nothing else (no `is_active`, no sizes). | POST `/menu-items` | — | `menu.grid.categoryUnknown`, `menu.grid.priceInvalid` | `editable-cards.tsx:135-139, 177-187, 240-252, 485`; `menu-items-page.tsx:248-263, 457-463` |
| MENU-ITEMS-112 | (critic) Item dialog recipe rows are keyed by size LABEL and never move with a rename: renaming a size (Small → Regular), or leaving single-price mode ("Add size" blanks the `one_size` label), keeps the existing rows in a section under the OLD label ("One size" for `one_size`) and shows an empty section for the new label. Save writes each returned size's recipe from the rows carrying THAT size's label only, so the renamed size's recipe is replaced with its (usually empty) section; the old-label rows are not written to it. No warning. | PUT `/menu-item-sizes/{sid}/recipe` | — | `recipes.oneSize` | `menu-item-dialog.tsx:119-127, 221-230, 421-431` |
| MENU-ITEMS-113 | (critic) Add-on dialog, edit: the disabled Group select is filled only once the groups read returns. Saving before that (or after that read fails) fails validation: "This field is required" under the DISABLED Group select, nothing written. Create in an org with no shared group: the select is empty and only a person with `menu.items.edit` gets the "New group" way out. | GET `/modifier-groups?org_id` | — | `common.requiredField` | `addon-dialog.tsx:62-66, 75, 100-104, 155, 173` |
| MENU-ITEMS-114 | (critic) Non-visible read: on mount the page reads the org's public brand for the export logo only (`useExportLogo`): `custom_branding` true → the workbook logo is the org's `logo_url`; otherwise (or while loading / on failure, no retry) Madar's own logo. | GET `/public/orgs/brand?org_id` (usePublicOrgBrand, stale 5 min) | — | – | `menu-items-page.tsx:110, 330-332`; `src/hooks/use-export-logo.ts`; `src/features/public-shell/use-brand.ts:87-115`; `excel.ts:373` |
| MENU-ITEMS-115 | (critic) Arabic-name payloads differ by editor; copy them exactly: the category, item and add-on DIALOGS send `name_translations: {ar}` only when the Arabic box is non-empty and OMIT the field otherwise (create and edit; the item dialog does the same for `description_translations`); the studio sends `{}` when empty (MENU-STUDIO-015); the group editor sends `{...existing, ar: <text or "">}` on edit and `{}`/`{ar}` on create (group and options). For menu items and categories the server MERGES translations (and backfills missing languages), so emptying the Arabic box never removes a stored Arabic name there. | POST/PATCH `/categories`, `/menu-items`; POST `/modifier-groups/{gid}/options`; PATCH `/modifier-options/{oid}` | — | `bilingualField.arabicLabel` | `category-dialog.tsx:82-91`; `menu-item-dialog.tsx:190-196`; `addon-dialog.tsx:112-129`; `menu-studio-page.tsx:391-399`; `group-editor-dialog.tsx:206, 221, 254, 267`; backend `MadarRust/src/menu/handlers.rs:727-733, 1379-1391` |


---

## 2. Recipe builder (`src/features/recipes/recipe-builder.tsx`, `create-ingredient-dialog.tsx`)

Used by the item dialog (deferred, sizes = the item's labels, no "New ingredient") and the add-on recipe
dialog (standalone save, one size, "New ingredient" on). Gates: none (server decides). Files read:
`recipe-builder.tsx`, `create-ingredient-dialog.tsx`, `util.ts`. Shared with onboarding
(`CreateIngredientDialog`).

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-RCP-001 | Seeds rows from the initial rows whenever their content changes (size, ingredient id/name/unit, quantity as text). | — | — | – | `recipe-builder.tsx:69-84` |
| MENU-RCP-002 | Toolbar "Copy from…" combobox — only when copy sources are given; NO caller in this area passes any, so it never shows. Port only if a caller needs it (copies the source's rows, mapping unknown sizes to the base size, de-duplicating by size+ingredient). | — | — | `recipes.builder.copyFrom` | `recipe-builder.tsx:134-153, 177-187` |
| MENU-RCP-003 | "New ingredient" (outline, Plus) in the toolbar when allowed (add-on recipe dialog only) → create-ingredient dialog. | — | — | `recipes.newIngredient` | `recipe-builder.tsx:188-192` |
| MENU-RCP-004 | Scale toggle "Scale from {{base}}" (switch, end of toolbar) — only with > 1 size (item dialog with several sizes). | — | — | `recipes.builder.scaleFromBase` | `recipe-builder.tsx:197-202` |
| MENU-RCP-005 | Scaling panel: "Multiply {{base}} quantities by:"; one factor input per non-base size ("×" prefix, step 0.05, placeholder 1.5); "Apply scaling" replaces every non-base size's rows with the base rows × factor (rounded to 3 dp). A size whose factor field was never touched uses ×1; a field cleared to empty (or ≤ 0) LOSES all its rows (web quirk). | — | — | `recipes.builder.scaleHint`, `recipes.builder.applyScaling` | `recipe-builder.tsx:119-132, 206-237` |
| MENU-RCP-006 | One section per size: pill with the size label ("One size" for `one_size`). | — | — | `recipes.oneSize` | `recipe-builder.tsx:240-260` |
| MENU-RCP-007 | Section header "Cost": Σ(cost_per_unit × qty) over the size's rows; "—" if no rows or any row lacks a positive unit cost or a numeric quantity. | — | — | `recipes.builder.estimate` "Cost" | `recipe-builder.tsx:242-248, 262-270` |
| MENU-RCP-008 | Section header margin ("margin"): `(price − cost)/price` shown only when cost is known and the size price > 0; colour green ≥ 60 %, normal ≥ 30 %, amber below. Price = that size's price, else the item's lowest size price. | — | — | `recipes.builder.margin` | `recipe-builder.tsx:249-250, 271-283`; `menu-item-dialog.tsx:128-136` |
| MENU-RCP-009 | Row ingredient combobox: active catalog ingredients (label = name, hint = unit word, search also matches the ingredient category); placeholder = the row's current name or "Ingredient"; picking sets name and unit. Search box "Search", empty "No results found". | — | — | `recipes.ingredient`, `units.*`, `common.search`, `common.noResults` | `recipe-builder.tsx:89-94, 299-311`; `combobox.tsx:40-97` |
| MENU-RCP-010 | Row quantity input (number, step 0.001, min 0, placeholder "0.000", end-aligned) + unit word. | — | — | `units.*` | `recipe-builder.tsx:314-327` |
| MENU-RCP-011 | Row line cost (unit cost × qty, money) or "—". | — | — | – | `recipe-builder.tsx:290-292, 330-335` |
| MENU-RCP-012 | Row remove (trash, aria "Remove ingredient"). | — | — | `recipes.builder.removeIngredient` | `recipe-builder.tsx:338-347` |
| MENU-RCP-013 | Dashed "Add ingredient" button per size adds an empty row (unit g). | — | — | `recipes.addIngredient` | `recipe-builder.tsx:117, 353-360` |
| MENU-RCP-014 | Rows that count: name set and quantity a finite number > 0; others are dropped silently on save. | — | — | – | `recipe-builder.tsx:100-109` |
| MENU-RCP-015 | Deferred mode (item dialog): no footer; the cleaned rows stream to the dialog on every edit. | — | — | – | `recipe-builder.tsx:111-114, 367` |
| MENU-RCP-016 | Standalone footer: "Unsaved changes" (amber) while dirty; "Save recipe" (Save icon) disabled until dirty, spinner while saving; after success the rows become the new baseline. | (caller's save) | — | `recipes.builder.unsaved`, `recipes.builder.saveAll` | `recipe-builder.tsx:155-168, 367-376` |
| MENU-RCP-017 | Create-ingredient dialog: title "Create ingredient", description "Define what each item and add-on consumes". | — | — | `recipes.createIngredient`, `recipes.subtitle` | `create-ingredient-dialog.tsx:67-73` |
| MENU-RCP-018 | Field Name (autofocus); Save disabled until a non-blank name. | — | — | `inventory.catalog.name` "Name" | `create-ingredient-dialog.tsx:75, 96` |
| MENU-RCP-019 | Field Category select: ingredient categories; defaults to the one with slug `general`, else the first. | GET `/inventory/orgs/{orgId}/categories` listIngredientCategories | — | `inventory.catalog.category` | `create-ingredient-dialog.tsx:40-46, 77-83` |
| MENU-RCP-020 | Field Unit select: g / kg / ml / L / pcs (translated `units.*`), default g. | — | — | `inventory.catalog.unit`, `units.g/kg/ml/l/pcs` | `create-ingredient-dialog.tsx:18, 84-90` |
| MENU-RCP-021 | Field "Cost / unit (EGP)" (number, step 0.0001, min 0, placeholder "—"), optional (blank → null). | — | — | `inventory.catalog.costPerUnit` | `create-ingredient-dialog.tsx:92` |
| MENU-RCP-022 | Save: create the catalog ingredient `{name (trimmed), category_id|null, unit, cost_per_unit (piastres)|null}`; invalidate recipes; append a row for it to the FIRST size (empty qty); toast "Changes saved"; close and reset. Error → toast.error(server). Cancel closes. | POST `/inventory/orgs/{orgId}/catalog` createCatalogItem | — | `common.save`, `common.cancel`, `common.savedChanges` | `create-ingredient-dialog.tsx:48-65, 94-97`; `recipe-builder.tsx:378-385` |
| MENU-RCP-023 | (critic) No discard guard: closing the add-on recipe dialog (Esc / × / outside click) or cancelling/closing the item dialog with unsaved builder edits drops them silently; the add-on recipe dialog has no Cancel button at all. "Unsaved changes" appears only in the standalone footer. | — | — | `recipes.builder.unsaved` | `addon-recipe-dialog.tsx:72-108`; `menu-item-dialog.tsx:301, 633-636`; `recipe-builder.tsx:367-376` |


---

## 3. `/menu/items/$itemId` Menu Studio

- **Title**: the item's translated name, else `menu.studio.untitled` "Untitled item"; while loading a skeleton; on error `menu.studio.itemTitle` "Menu item".
- **Route**: `src/routes/_app/menu/items_.$itemId.tsx` (un-nested from the list; `?tab=` search param).
- **Files read**: `src/features/menu/studio/menu-studio-page.tsx`, `util.ts`, `section-item.tsx`,
  `section-steps.tsx`, `step-preview.tsx`, `section-modifiers.tsx`, `section-options.tsx`, `section-meal.tsx`,
  `fix-cost-popover.tsx`, `preview/preview-panel.tsx`, `preview/preview-model.ts`;
  `src/features/menu/recipe/recipe-grid.tsx`, `grid-model.ts`, `base-picker.tsx`, `recipe-link-bar.tsx`;
  `src/features/combos/api.ts`, `meal.ts`, `use-menu-options.ts`; tests `menu-studio-page.test.tsx`,
  `menu-studio-detach-all.test.tsx`, `preview-panel.test.tsx`, `preview-model.test.ts`,
  `recipe/grid-model.test.ts`, `recipe/modeling-authz.test.tsx`.
- **Gates**: reached via the Items page (`menu.items.read`); grid/base/link editing `menu.items.edit`;
  steps editing `recipes.edit`; meal editing `menu.combos.edit`; preview section `menu.items.read`;
  "Edit group"/"New group" in modifiers `menu.items.edit`. Item details, options, modifiers rules,
  Duplicate and Save are ungated (server decides).
- **Module**: `pos`. **Realtime**: none.
- **Hooks**: `useGetStudio`, `useListCatalog`, `useListBases`, `useGetRecipeLink`, `getGetMenuItemQueryOptions`
  (linked copies), `useListCategories`, `useListStepPresets`, `useListGroups`, `useGetMenuItem` (meal),
  `useCombos`/`useCombo`/`useMenuOptions` (combos feature: `listCombos`, `getCombo`, `listMenuItems?full=true`,
  `listCategories`, `listBranches`), `previewMenuItem` (as query); writes `updateMenuItem`,
  `uploadMenuItemImage`, `putSizes`, `putSizeRecipe`, `putRecipeSteps`, `putModifierGroups`,
  `putItemOptions`, `duplicateItem`, `putSizeBase`, `deleteRecipeLink`, `updateCatalogItem`, `putMeal`,
  plus the group editor's calls (§4c).
- **Invalidation**: Save → `invalidateStudio(itemId)` + `invalidateCatalog()`; base change →
  `invalidateStudio`; unlink → `invalidateStudio` + `getRecipeLink` key; cost fix →
  `invalidateIngredientCosts`; new group dialog closed → `invalidateStudio`; meal apply →
  `getMenuItem` key only.

### 3a. Page shell, load, deep links, save bar

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-STUDIO-001 | Load the item aggregate (sizes+recipes+costs, modifier groups, options, steps, availability, link info). | GET `/menu-items/{id}/studio` getStudio | menu.items.read (via list) | – | `menu-studio-page.tsx:123-124` |
| MENU-STUDIO-002 | Loading: reading-width page, header with back button and a title skeleton, three section skeletons (176/288/160 px). | — | — | – | `menu-studio-page.tsx:535-549` |
| MENU-STUDIO-003 | Error (e.g. unknown id): header "Menu item" + back; ErrorState "Could not load this item" + server message + Retry (spinner while refetching). | GET `/menu-items/{id}/studio` (retry) | — | `menu.studio.itemTitle`, `menu.studio.loadError`, `common.retry` | `menu-studio-page.tsx:551-563` |
| MENU-STUDIO-004 | Header: back button (aria "Back") → `/menu/items` keeping the current search params; title = translated name or "Untitled item"; when the item is inactive a neutral "Inactive" pill under the title. | — | — | `common.back`, `menu.studio.untitled`, `common.inactive` | `menu-studio-page.tsx:305, 565, 572-581` |
| MENU-STUDIO-005 | Header action "Branch & channel pricing →" (ghost, arrow mirrored in RTL) links to `/menu/pricing` (keeps search params). | — | — | `menu.studio.pricingLink` | `menu-studio-page.tsx:584-589` |
| MENU-STUDIO-006 | Header action "Duplicate" (outline, Copy icon) → confirm (non-destructive) "Duplicate this item?" / "Creates a new item with the same sizes, recipes, modifiers, options and overrides. The copy has no order history." / confirm "Duplicate" → duplicate → toast "Item duplicated" → navigate to the copy's studio. The copy is NOT deactivated here (unlike the grid). Error → toast.error(server). | POST `/menu-items/{id}/duplicate` duplicateItem | — | `menu.grid.duplicate`, `menu.studio.duplicateTitle`, `menu.studio.duplicateDesc`, `menu.studio.duplicated` | `menu-studio-page.tsx:307-325, 590-592` |
| MENU-STUDIO-007 | Deep link `?tab=`: once loaded, scrolls to the mapped section once per item: basics→Item details, sizes/recipe→Sizes, steps→Steps, modifiers→Modifiers, options→Options; `availability` or anything else stays at the top (pricing link is its home). | — | — | – | `menu-studio-page.tsx:82-89, 290-302`; route `items_.$itemId.tsx:10-15` |
| MENU-STUDIO-008 | Sections in order, each with a heading + description, separated by dividers: Item details · Sizes, price & recipe · How it's made · Modifiers · Options · Make it a meal · Preview (only with `menu.items.read`). | — | — | `menu.studio.basics.title`, `menu.studio.basics.desc`, `menu.studio.sections.sizesTitle`, `menu.studio.sections.sizesDesc`, `menu.studio.sections.stepsTitle`, `menu.studio.sections.stepsDesc`, `menu.studio.tabs.modifiers`, `menu.studio.modifiers.desc`, `menu.studio.tabs.options`, `menu.studio.options.desc`, `combos.meal.title`, `combos.meal.desc`, `modeling.preview.title`, `modeling.preview.desc` | `menu-studio-page.tsx:598-739, 763-791` |
| MENU-STUDIO-009 | Dirty marker: a section with unsaved edits shows an amber "Unsaved" pill after its heading (Item details, Sizes, Steps, Modifiers, Options; never Meal/Preview). | — | — | `menu.studio.unsaved` | `menu-studio-page.tsx:181-205, 782-784` |
| MENU-STUDIO-010 | Sticky save bar (bottom centre, only while ≥ 1 section is dirty): "{{count}} unsaved changes" (count = dirty SECTIONS, max 5), "Discard" (ghost), "Save" (spinner; both disabled while saving). | — | — | `menu.studio.unsavedN`, `menu.studio.discard`, `common.save` | `menu-studio-page.tsx:742-756` |
| MENU-STUDIO-011 | Discard: every section is re-seeded from the server aggregate (drafts, staged image, removed image all dropped). | — | — | – | `menu-studio-page.tsx:327-329` |
| MENU-STUDIO-012 | Background refetches (e.g. after a cost fix or a base change) re-seed only the sections that are NOT dirty; a different item id forces a full re-seed. | — | — | – | `menu-studio-page.tsx:211-275` |
| MENU-STUDIO-013 | Leave guard: while anything is dirty, closing/reloading the browser tab asks the browser's "leave site?" prompt. In-app navigation (back button, links) is NOT guarded. Flutter: no in-app guard (desktop window close only, if at all). | — | — | – | `menu-studio-page.tsx:278-287` |
| MENU-STUDIO-014 | Save validation (first failure → error toast, nothing written): name blank → "Item name is required"; a size label blank → "Every size needs a label"; duplicate label → "Size labels must be unique — “{{label}}” repeats"; size price not a number ≥ 0 → "Enter a valid price for “{{name}}”"; a written step with neither English nor Arabic name → "Every written step needs a name"; an option name blank → "Every option needs a name"; option price invalid → "Enter a valid price for “{{name}}”". | — | — | `menu.studio.validate.nameRequired`, `.sizeLabel`, `.sizeLabelDup`, `.priceFor`, `.stepName`, `.optionName` | `menu-studio-page.tsx:336-375` |
| MENU-STUDIO-015 | Save step 1 — item details (only if dirty): PATCH name, name_translations (`{ar}` or `{}`), description\|null, description_translations (`{ar}` or `{}`), category_id\|null, is_active, and `image_url:null` when the image was removed; then upload the staged image file. | PATCH `/menu-items/{id}` updateMenuItem; POST `/uploads/menu-items/{id}` uploadMenuItemImage | — | – | `menu-studio-page.tsx:388-409` |
| MENU-STUDIO-016 | Save step 2 — sizes (if sizes OR any recipe is dirty): replace-set `{label (trimmed), price (piastres), sort i, is_active:true}` in column order; new sizes adopt the returned ids. | PUT `/menu-items/{id}/sizes` putSizes | — | – | `menu-studio-page.tsx:413-431` |
| MENU-STUDIO-017 | Save step 3 — recipes: for each new or recipe-dirty size, replace its OWN lines (`{ingredient_id, quantity, unit}` with a numeric quantity); base/rule/linked lines are never sent; skipped entirely when the item's recipe follows another item. | PUT `/menu-item-sizes/{sizeId}/recipe` putSizeRecipe | — | – | `menu-studio-page.tsx:433-449`; `grid-model.ts:35-38` |
| MENU-STUDIO-018 | Save step 4 — steps (if dirty AND `recipes.edit`): replace-set; preset → `{kind:"preset", preset_slug, note|null, note_ar|null}`; written → `{kind:"custom", title|null, title_ar|null, note|null, note_ar|null}` (all trimmed). | PUT `/recipes/steps/{menuItemId}` putRecipeSteps | recipes.edit | – | `menu-studio-page.tsx:454-479` |
| MENU-STUDIO-019 | Save step 5 — modifiers (if dirty): replace-set in current order `{group_id, sort, min_override, max_override, is_required_override, included_option_ids (null = all)}`. Removing every group sends `groups: []` and nothing else is written. | PUT `/menu-items/{id}/modifier-groups` putModifierGroups | — | – | `menu-studio-page.tsx:482-499`; test `menu-studio-detach-all.test.tsx:142-173` |
| MENU-STUDIO-020 | Save step 6 — options (if dirty): replace-set `{id?, name (trimmed), price, is_active, recipe: [{ingredient_id, quantity, unit}] or null}` (recipe only when an ingredient and a numeric quantity are set). | PUT `/menu-items/{id}/options` putItemOptions | — | – | `menu-studio-page.tsx:502-521` |
| MENU-STUDIO-021 | Save success: invalidate studio + catalog; one toast "Changes saved"; the refetch re-baselines every section. | — | — | `common.savedChanges` | `menu-studio-page.tsx:524-526` |
| MENU-STUDIO-022 | Save failure in a step: error toast "Couldn't save {{section}}: {{error}}" where section = "Item details" / "Sizes, price & recipe" / "the recipe for “{{label}}”" / "the steps" / "Modifiers" / "Options"; save stops; earlier steps stay saved (their sections no longer dirty); retrying Save re-runs only what is still dirty. | — | — | `menu.studio.saveFailedIn`, `menu.studio.basics.title`, `menu.studio.sections.sizesTitle`, `menu.studio.sectionRecipeFor`, `menu.studio.sectionSteps`, `menu.studio.tabs.modifiers`, `menu.studio.tabs.options` | `menu-studio-page.tsx:377-383, 402-405, 424-427, 444-447, 474-477, 494-497, 516-519` |

### 3b. Item details section (`section-item.tsx`)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-STUDIO-023 | Layout: image box on the start side (stacked above on phone), fields beside it. | — | — | – | `section-item.tsx:53-127` |
| MENU-STUDIO-024 | Image: picking a file STAGES it (local preview, uploaded on Save); hint "PNG/JPG/WebP, up to 5 MB"; same client refusals as MENU-ITEMS-083. Section becomes dirty. | — (Save → MENU-STUDIO-015) | — | `menu.imageHint`, `uploader.*` | `section-item.tsx:55-64`; `menu-studio-page.tsx:610-613` |
| MENU-STUDIO-025 | Image remove (only when there is a staged file or a server image/asset): drops the staged file, or stages removal (Save sends `image_url:null`). No removal offered when neither exists. | — | — | `uploader.remove` | `menu-studio-page.tsx:567-568, 614-621`; test `menu-studio-page.test.tsx:81-99` |
| MENU-STUDIO-026 | Name (EN) / Name (ع) inputs (no zod; blank EN name caught by Save → MENU-STUDIO-014). | — | — | `common.name`, `bilingualField.arabicLabel` | `section-item.tsx:68` |
| MENU-STUDIO-027 | Description (EN) / (ع) textareas. The Arabic description is always seeded EMPTY (the aggregate doesn't return it); typing one sends `{ar}`, leaving it empty sends `{}`. | — | — | `common.description` | `section-item.tsx:69-75`; `studio/util.ts:139-148` |
| MENU-STUDIO-028 | Category searchable combobox (placeholder "Select category", translated names) + "+" button (tooltip "New category") → category dialog; the created category is selected (dirty). | GET `/categories` listCategories; POST `/categories` (dialog) | — | `common.category`, `menu.selectCategory`, `menu.newCategory` | `section-item.tsx:39-48, 77-107, 130-138` |
| MENU-STUDIO-029 | Active switch with hint "Inactive items are hidden from every menu." | — | — | `common.active`, `menu.studio.basics.activeHint` | `section-item.tsx:108-124` |

### 3c. Sizes, price & recipe section (recipe grid)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-STUDIO-030 | Grid: rows = ingredients, columns = sizes (in size order), a Price row on top, cells = quantity in the ingredient's unit, a footer Cost · margin row, horizontal scroll inside a bordered box. Rows order: own/linked first, then base lines, then packaging-rule lines (stable within each). | — | — | – | `recipe-grid.tsx:286-492`; `grid-model.ts:68-91` |
| MENU-STUDIO-031 | Ingredient catalog for the grid: org ingredients (active ones offered for adding; hint unit word; search also matches category). | GET `/inventory/orgs/{orgId}/catalog` listCatalog | — | `units.*` | `menu-studio-page.tsx:127-138` |
| MENU-STUDIO-032 | Ingredient cell: name (or "Unknown ingredient"); muted for non-own rows; lock badge with source: base → "Base: {{name}}", packaging rule → "Packaging rule", linked → "Follows {{name}}". | — | — | `modeling.grid.unknownIngredient`, `modeling.grid.tagBase`, `modeling.grid.tagRule`, `modeling.grid.tagLinked` | `recipe-grid.tsx:171-216` |
| MENU-STUDIO-033 | "swappable · default of {{group}}" badge on a milk / coffee-bean ingredient row (not rule rows) when an attached group offers an option using an ingredient of the same category. | — | — | `modeling.grid.swappable` | `recipe-grid.tsx:192, 206-210`; `grid-model.ts:155-175`; `menu-studio-page.tsx:164-174` |
| MENU-STUDIO-034 | "Set cost" amber chip on an ingredient with no unit cost (only when editable) → popover (MENU-STUDIO-061). | — | menu.items.edit | `menu.studio.recipe.setCost` | `recipe-grid.tsx:193, 211` |
| MENU-STUDIO-035 | Editable quantity cell (own row, editable grid): text input, decimal keyboard, placeholder "—", aria "{{ingredient}} in {{size}}"; typing keeps only digits and one decimal point (comma → dot); focus selects the text; unit word after it. | — | menu.items.edit | `modeling.grid.cellAria`, `units.*` | `recipe-grid.tsx:105, 218-258` |
| MENU-STUDIO-036 | Read-only cell (non-own row, or read-only grid): "{{qty}} {{unit}}" or "—" when the size has no such line. | — | — | `units.*` | `recipe-grid.tsx:225-232` |
| MENU-STUDIO-037 | Keyboard: Enter or ↓ moves to the same column one row down; Shift+Enter or ↑ one row up (the Price row is row −1, so ↓ from Price enters the first ingredient). Tab moves across. Footer hint: "Enter or ↓ moves down a column, Tab moves across. Greyed rows come from a base, a packaging rule or a linked item and are edited there." | — | — | `modeling.grid.hint` | `recipe-grid.tsx:86-102, 494-499` |
| MENU-STUDIO-038 | Remove an own ingredient row (trash, aria "Remove ingredient") — removes it from every size. | — | menu.items.edit | `recipes.builder.removeIngredient` | `recipe-grid.tsx:260-276`; `grid-model.ts:120-121` |
| MENU-STUDIO-039 | "+ ingredient" combobox row under the grid: offers active ingredients not already an own row; picking adds an own row (blank cell in every size, unit from the catalog) and focuses its cell in the first size. | — | menu.items.edit | `modeling.grid.addIngredient` | `recipe-grid.tsx:131-136, 435-456`; `grid-model.ts:113-118` |
| MENU-STUDIO-040 | Price row: "Price (EGP\|ج.م)" row header; one input per size (decimal, cleaned like quantities, aria "Price of {{size}}"); cell tinted when the price differs from the saved one. Disabled without `menu.items.edit`. | — | menu.items.edit | `common.price`, `modeling.grid.priceAria` | `recipe-grid.tsx:400-423` |
| MENU-STUDIO-041 | Column header: the `one_size` sentinel shows the fixed word "Price" (not renameable); any other size shows a label input (placeholder "e.g. Small", aria "Label"), disabled without `menu.items.edit`. Header tinted when the column is new, renamed or its recipe is dirty. | — | menu.items.edit | `menu.priceSection`, `menu.studio.sizes.labelPh`, `menu.sizeLabel` | `recipe-grid.tsx:318-339` |
| MENU-STUDIO-042 | "+ Size" button in the last header cell (editable grid): adds a size (price "0", blank label, blank cells for every own row); if the item only had `one_size`, that label is blanked so both must be named. | — | menu.items.edit | `modeling.grid.addSize` "Size" | `recipe-grid.tsx:149-169, 308-311` |
| MENU-STUDIO-043 | Column actions menu (⋯, aria "Size actions"; hidden without `menu.items.edit`): "Move earlier" (disabled on first), "Move later" (disabled on last) — arrows mirrored in RTL. | — | menu.items.edit | `modeling.grid.columnActions`, `modeling.grid.moveLeft`, `modeling.grid.moveRight` | `recipe-grid.tsx:140-148, 340-358` |
| MENU-STUDIO-044 | Column menu "Copy from ▸" submenu (only when not read-only; disabled with < 2 sizes): lists the other sizes (label or "Untitled size"); picking replaces this size's OWN lines with that size's own lines (base/rule/linked lines kept). | — | menu.items.edit | `modeling.grid.copyFrom`, `modeling.grid.untitledSize` | `recipe-grid.tsx:359-378`; `grid-model.ts:136-143` |
| MENU-STUDIO-045 | Column menu "Scale ×…" opens the scale dialog for that size. | — | menu.items.edit | `modeling.grid.scale` | `recipe-grid.tsx:379-381` |
| MENU-STUDIO-046 | Column menu "Remove size" (destructive styling, no confirm) removes the column — even the last one (no guard; the server decides on Save). | — | menu.items.edit | `menu.removeSize` | `recipe-grid.tsx:384-390` |
| MENU-STUDIO-047 | Scale dialog: title "Scale {{size}}", description "Multiplies the own amounts. Pick another size to start from its amounts instead (e.g. Double = Single × 2)."; "Start from" select (every size, default this one); "Multiply by" (decimal, default "1") must be a number > 0 → "Enter a number above 0"; Cancel / Apply. Same size → multiply its own quantities; another size → copy that size's own lines × factor. Quantities rounded to 3 dp; blanks stay blank. | — | menu.items.edit | `modeling.grid.scaleTitle`, `modeling.grid.scaleDesc`, `modeling.grid.scaleFrom`, `modeling.grid.factor`, `modeling.grid.factorInvalid`, `modeling.grid.apply`, `common.cancel` | `recipe-grid.tsx:501-513, 518-611`; `grid-model.ts:124-150` |
| MENU-STUDIO-048 | Footer "Cost · margin" per size: no lines → "—"; while the column is new / recipe-dirty / price-changed → browser estimate prefixed "≈ " (sum of cost × qty over lines with a quantity; incomplete if a line has no ingredient, no unit cost or a bad quantity); otherwise the server's cost; incomplete or unknown → "Cost incomplete"; else money + " · " + margin % (only when price > 0). | — | — | `modeling.grid.cost`, `menu.studio.recipe.incomplete` | `recipe-grid.tsx:70-84, 458-490` |
| MENU-STUDIO-049 | Read-only grid without `menu.items.edit`: no input cells (values as text), price inputs disabled, label inputs disabled, no ⋯ menus, no "+ Size", no "+ ingredient", no remove buttons, no "Set cost". | — | menu.items.edit | – | `recipe-grid.tsx:127-128`; test `modeling-authz.test.tsx:56-93` |
| MENU-STUDIO-050 | (corrected) Linked copy (recipe follows another item): banner "This recipe follows {{name}}. Unlink it to edit amounts here."; the grid treats itself as read-only (`readOnly = followsName != null || !menu.items.edit`): quantity cells render as text, no "+ ingredient" row, no row remove buttons, no "Set cost" chips, no "+ Size" button, and the column ⋯ menu drops "Copy from" and "Scale ×…". With `menu.items.edit` the size label inputs, the Price row inputs and the column ⋯ menu (Move earlier / Move later / Remove size) stay enabled. Base picker replaced by an empty slot. Save still runs putSizes but skips every recipe write. | GET `/menu-items/{id}/recipe-link` getRecipeLink | labels/prices/column menu: menu.items.edit | `modeling.grid.followsReadOnly` | `recipe-grid.tsx:127-128, 211, 264, 289-295, 308-314, 335-393, 415, 435`; `menu-studio-page.tsx:154-175, 439, 647-656` |
| MENU-STUDIO-051 | Base picker (toolbar start): label "Base" + select: "None", "Different per size" (disabled, only when sizes disagree), the active bases plus any inactive base already in use. Disabled without `menu.items.edit`, while busy, when no saved size exists, or while the sizes section is dirty — then the note "Save or discard size changes to change the base." | GET `/recipe-bases` listBases | menu.items.edit | `modeling.base.label`, `modeling.base.none`, `modeling.base.mixed`, `modeling.base.saveFirst` | `base-picker.tsx:29-89`; `menu-studio-page.tsx:156-158, 647-653` |
| MENU-STUDIO-052 | Base picker apply: sets the base on EVERY saved size, one call each; toast "Base applied to {{count}} sizes" or "Base removed"; the studio refetches (base lines appear greyed). Error → toast.error(server) and still refetch. | PUT `/menu-item-sizes/{sizeId}/base` putSizeBase `{base_id|null}` | menu.items.edit | `modeling.base.applied`, `modeling.base.cleared` | `base-picker.tsx:37-55`; `menu-studio-page.tsx:652` |
| MENU-STUDIO-053 | "Manage bases" link next to the picker → `/menu/bases`. | — | — | `modeling.base.manage` | `base-picker.tsx:80-82` |
| MENU-STUDIO-054 | Link bar (follows): "Recipe follows <source name link → its studio>" + "Out of sync" badge when the server says it drifted. | GET `/menu-items/{id}/recipe-link` | — | `modeling.linked.follows`, `modeling.linked.outOfSync` | `recipe-link-bar.tsx:32-69` |
| MENU-STUDIO-055 | Unlink (ghost, Unlink icon; `menu.items.edit` only) → confirm (non-destructive) "Unlink this recipe?" / "The current lines stay as this item's own recipe and stop following {{name}}." / "Unlink" → toast "Recipe unlinked" → refetch studio + link. Error → toast.error(server). | DELETE `/menu-items/{id}/recipe-link` deleteRecipeLink | menu.items.edit | `modeling.linked.unlink`, `modeling.linked.unlinkTitle`, `modeling.linked.unlinkDesc`, `modeling.linked.unlinked` | `recipe-link-bar.tsx:34-52, 63-67`; `menu-studio-page.tsx:663-666` |
| MENU-STUDIO-056 | Link bar (source with copies): "Linked copies:" + comma-separated links to each copy's studio, named from each copy's item read (else "Copy {{n}}"). | GET `/menu-items/{copyId}` ×N | — | `modeling.linked.copies`, `modeling.linked.copyN` | `recipe-link-bar.tsx:72-86`; `menu-studio-page.tsx:160-163` |
| MENU-STUDIO-057 | Refusal: without `menu.items.edit` the Unlink button is hidden. | — | menu.items.edit | – | `recipe-link-bar.tsx:30, 63` |
| MENU-STUDIO-058 | Section dirty = sizes (label/price list) differ OR any size's own-recipe signature differs (sourced lines never make it dirty). | — | — | – | `studio/util.ts:250-254`; `menu-studio-page.tsx:186-199` |
| MENU-STUDIO-059 | Seeding: only active sizes, sorted by `sort`; price as EGP text; quantities as plain numbers (trailing zeros dropped); sources normalised (null → own). | — | — | – | `studio/util.ts:150-172` |
| MENU-STUDIO-060 | Responsive: the grid scrolls horizontally on narrow screens; the toolbar (base picker, link bar) wraps. | — | — | – | `recipe-grid.tsx:297`; `menu-studio-page.tsx:646` |
| MENU-STUDIO-061 | "Set cost" popover: ingredient name, "Cost per {{unit}} (EGP)", number input (step 0.01, autofocus, placeholder 0.00, Enter submits) + Save (spinner). Invalid/negative → "Enter a valid cost". Success → toast "Ingredient cost set", close, refresh catalog + studio (costs recompute). Error → toast.error(server). | PATCH `/inventory/orgs/{orgId}/catalog/{id}` updateCatalogItem `{cost_per_unit}` | menu.items.edit | `menu.studio.recipe.costPerUnit`, `menu.studio.recipe.invalidCost`, `menu.studio.recipe.costSet`, `common.save` | `fix-cost-popover.tsx:19-98`; `menu-studio-page.tsx:532` |

### 3d. How it's made (steps) section

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-STUDIO-062 | Step library loaded for names/animations. | GET `/recipes/step-presets` listStepPresets | — | – | `section-steps.tsx:40-42` |
| MENU-STUDIO-063 | Empty: dashed box "No steps yet. Add the order of preparation so anyone can make this the same way." | — | — | `menu.studio.steps.empty` | `section-steps.tsx:62-66` |
| MENU-STUDIO-064 | Step row: grip glyph (decorative; no drag), number (1…), 44 px still animation frame (preset) or Sparkles glyph (written step), content, actions. | — | — | – | `section-steps.tsx:68-81`; `step-preview.tsx:27-75` |
| MENU-STUDIO-065 | Preset step: library name (Arabic name when the UI is Arabic and one exists) and its note line: the library note, else "From the library"; a slug no longer in the library → slug as name + "This step is no longer in the library". | — | — | `menu.studio.steps.fromLibrary`, `menu.studio.steps.retired` | `section-steps.tsx:43-46, 84-94` |
| MENU-STUDIO-066 | Written step: two inputs — "What to do" (aria "Step (English)") and "بالعربية" (RTL, aria "Step (Arabic)"). | — | recipes.edit (else disabled) | `menu.studio.steps.titlePlaceholder`, `menu.studio.steps.titleEn`, `menu.studio.steps.titlePlaceholderAr`, `menu.studio.steps.titleAr` | `section-steps.tsx:95-113` |
| MENU-STUDIO-067 | Per-step note (any step): two small inputs, max 280 chars each: "For this drink — e.g. 40ml condensed milk" (aria "Note (English)") and "ملاحظة لهذا المشروب" (RTL, aria "Note (Arabic)"). On a preset it replaces the library note; blank keeps the library's. | — | recipes.edit (else disabled) | `menu.studio.steps.notePlaceholder` (missing), `menu.studio.steps.noteEn` (missing), `menu.studio.steps.notePlaceholderAr` (missing), `menu.studio.steps.noteAr` (missing) | `section-steps.tsx:118-138` |
| MENU-STUDIO-068 | Row actions: Move up (disabled first), Move down (disabled last), Remove (trash, aria "Remove"). | — | recipes.edit | `menu.studio.steps.moveUp`, `menu.studio.steps.moveDown`, `common.remove` | `section-steps.tsx:48-58, 141-165` |
| MENU-STUDIO-069 | "Add a step" (outline, Plus) opens the library picker; "Write your own" (ghost, Type icon) appends an empty written step. | — | recipes.edit | `menu.studio.steps.addFromLibrary`, `menu.studio.steps.addCustom` | `section-steps.tsx:171-185` |
| MENU-STUDIO-070 | Library picker dialog: title "Add a step", description "Each of these plays on the till while the drink is made. Pick one, or write your own if nothing fits."; loading → 6 skeleton tiles; empty → "The animation library is empty."; else a 2-col (3 from 640 px) grid of tiles: 72 px playing animation (only while on screen), name, note (2 lines). Tap a tile → appends that preset and closes. Footer: "Write your own" (appends written step, closes) and "Close". | GET `/recipes/step-presets` | recipes.edit | `menu.studio.steps.pickTitle`, `menu.studio.steps.pickDesc`, `menu.studio.steps.noPresets`, `menu.studio.steps.addCustom`, `common.close` | `section-steps.tsx:187-245` |
| MENU-STUDIO-071 | Animation source: `${API base}${animation_url}` Lottie (dotLottie), looping; plays only while visible (rows hold a still frame). | GET `<api>/…animation` (asset) | — | – | `step-preview.tsx:27-75` |
| MENU-STUDIO-072 | Refusal: without `recipes.edit` steps and notes are shown with every input disabled and no move/remove/add controls; Save skips steps. | — | recipes.edit | – | `menu-studio-page.tsx:116, 454, 682`; `section-steps.tsx:100-185` |
| MENU-STUDIO-073 | Seeding written steps: a step whose Arabic name equals its English name seeds the Arabic box EMPTY (so saving doesn't invent an Arabic name). Missing `recipe_steps` = no steps. | — | — | – | `studio/util.ts:222-243` |

### 3e. Modifiers section (`section-modifiers.tsx`)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-STUDIO-074 | Org groups loaded for the attach picker. | GET `/modifier-groups?org_id` listGroups | — | – | `section-modifiers.tsx:45-46` |
| MENU-STUDIO-075 | Empty: EmptyState (Layers) "No modifier groups attached". | — | — | `menu.studio.modifiers.empty` | `section-modifiers.tsx:108-109` |
| MENU-STUDIO-076 | Attached group card: name, humanized legacy type badge (when set), "Single choice"/"Multi choice" badge. | — | — | `menu.studio.modifiers.single`, `menu.studio.modifiers.multi` | `section-modifiers.tsx:29-33, 112-124` |
| MENU-STUDIO-077 | "Edit group" (ghost, pencil) → `/menu/groups?edit=<groupId>` (opens that group's editor). | — | menu.items.edit | `menu.groups.editGroup` | `section-modifiers.tsx:125-131` |
| MENU-STUDIO-078 | Detach (trash, aria "Detach") removes the group from the draft (no confirm). | — | — | `menu.studio.modifiers.detach` | `section-modifiers.tsx:84, 132-141` |
| MENU-STUDIO-079 | Option chips (allowlist): every option of the group as a toggle chip (aria-pressed; check icon + filled when offered; "+price" when > 0). Toggling removes/adds it; when all are offered again it collapses to "all" (null). Group with no options → "This group has no options yet." | — | — | `menu.studio.modifiers.noOptions` | `section-modifiers.tsx:86-98, 144-174` |
| MENU-STUDIO-080 | Option recipe list (read-only; only when some option has a recipe): per option name, "+price", recipe lines "ingredient qty unit" joined " · " or "no stock", and "cost X" (with "+" when incomplete). | — | — | `menu.groups.studio.noStock`, `menu.groups.studio.cost` | `section-modifiers.tsx:176-199` |
| MENU-STUDIO-081 | Per-item rules: "Required" switch; "Min" number (≥ 0, integer, blank → 0); "Max" number (blank = unlimited, placeholder "∞", ≥ 0). | — | — | `menu.studio.modifiers.required`, `.min`, `.max`, `.unlimited` | `section-modifiers.tsx:201-230` |
| MENU-STUDIO-082 | "Attach a group…" combobox: active, reusable (not another item's options set), not-yet-attached groups; hint = humanized type or "options"; disabled when nothing left. Picking appends it with the group's own min/max/required and all options offered. | — | — | `menu.studio.modifiers.attach`, `menu.studio.modifiers.option` | `section-modifiers.tsx:50-80, 236-245` |
| MENU-STUDIO-083 | "New group" (outline, Plus; disabled without org) opens the choice-group editor (create, §4c); the saved group is attached to the draft; closing the dialog refreshes the studio. | (group editor calls) | menu.items.edit | `menu.groups.new` | `section-modifiers.tsx:100-104, 246-261` |
| MENU-STUDIO-084 | Refusal: without `menu.items.edit`, "Edit group" and "New group" are hidden (detach, chips, rules stay). | — | menu.items.edit | – | `section-modifiers.tsx:48, 125, 246` |

### 3f. Options section (`section-options.tsx`)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-STUDIO-085 | Option row: Name (placeholder "e.g. Extra shot"), "Price (EGP)" (number, step 0.01, min 0), Active switch, Remove (trash, aria "Remove"). | — | — | `common.name`, `menu.studio.options.namePh`, `common.price`, `common.active`, `common.remove` | `section-options.tsx:36-80` |
| MENU-STUDIO-086 | "Deducts" ingredient combobox (placeholder "No deduction"); picking sets the unit from the catalog. | — | — | `menu.studio.options.deducts`, `menu.studio.options.noDeduction` | `section-options.tsx:82-97` |
| MENU-STUDIO-087 | With an ingredient: quantity input (step 0.001, placeholder 0.000, aria "Quantity") + unit word; "Cost {{cost}}" (unit cost × qty) when known; "Clear" link removes the deduction. | — | — | `common.quantity`, `menu.studio.options.cost`, `common.clear`, `units.*` | `section-options.tsx:98-127` |
| MENU-STUDIO-088 | Dashed "Add option" appends `{name "", price "0", active, unit g}`. | — | — | `menu.studio.options.add` | `section-options.tsx:30-31, 133-140` |
| MENU-STUDIO-089 | Seeding: only the first recipe line of an option is editable (quantity as a plain number, unit default g). | — | — | – | `studio/util.ts:201-213` |

### 3g. Make it a meal section (`section-meal.tsx`; applies immediately, outside Save)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-STUDIO-090 | Reads the item's current meal target, the org's combos (≤ 200) and the menu options (items with sizes, categories, branches). | GET `/menu-items/{id}` getMenuItem; GET `/combos?per_page=200` listCombos; GET `/menu-items?org_id&full=true`; GET `/categories`; GET `/branches` | — | – | `section-meal.tsx:39-43`; `use-menu-options.ts:56-63` |
| MENU-STUDIO-091 | Item is a combo: dashed box "This item is a combo. Its slots and prices are set in the combo editor." + "Open the combo editor →" link to `/menu/combos/{id}`. | — | — | `combos.meal.isCombo`, `combos.meal.openEditor` | `section-meal.tsx:79-91` |
| MENU-STUDIO-092 | No combos: dashed box (UtensilsCrossed) "No combos yet. Create one first, then point this item at it." + "Combos →" link to `/menu/combos`. | — | — | `combos.meal.noCombos`, `combos.title` | `section-meal.tsx:93-108` |
| MENU-STUDIO-093 | "Combo" select: "Not offered" + each combo (translated name); changing clears the slot. | — | menu.combos.edit (else disabled) | `combos.meal.combo`, `combos.meal.none` | `section-meal.tsx:113-135` |
| MENU-STUDIO-094 | "Fills the slot" select (only once a combo is chosen): slots whose choices admit this item (its own item choice first, else its category); placeholder "Loading…" while the combo loads, else "Choose a slot"; a combo with exactly one admitting slot auto-selects it; none → red alert "That combo has no slot for this item." | GET `/combos/{id}` getCombo | menu.combos.edit (else disabled) | `combos.meal.slot`, `common.loading`, `combos.meal.pickSlot`, `errors.codes.MEAL_TARGET_INVALID` | `section-meal.tsx:53-59, 136-157`; `combos/meal.ts:19-28` |
| MENU-STUDIO-095 | Preview line "The till offers: Make it a meal {{delta}}" (signed money) when combo+slot+item are known (formula §8). | — | — | `combos.meal.preview` | `section-meal.tsx:61, 160-164`; `combos/meal.ts:61-79` |
| MENU-STUDIO-096 | "Apply" (combo chosen) / "Turn off" (Not offered) button: disabled unless changed, while busy, or with a combo but no slot; spinner. Writes target or nulls; toast "Make it a meal is set" / "Make it a meal is off"; refetches the item. Error → toast.error(server). | PUT `/menu-items/{id}/meal` putMeal `{combo_id, slot_id}` or `{combo_id:null, slot_id:null}` | menu.combos.edit | `combos.meal.apply`, `combos.meal.turnOff`, `combos.meal.saved`, `combos.meal.cleared` | `section-meal.tsx:65-76, 166-170`; `combos/api.ts:89-90` |
| MENU-STUDIO-097 | "Discard" (ghost, only while changed) restores the saved combo/slot. | — | menu.combos.edit | `combos.discard` | `section-meal.tsx:171-184` |
| MENU-STUDIO-098 | Refusal: without `menu.combos.edit` the selects are disabled and no Apply/Discard buttons show. | — | menu.combos.edit | – | `section-meal.tsx:37, 121, 139, 166` |

### 3h. Preview section (`preview/preview-panel.tsx`)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-STUDIO-099 | Shown only with `menu.items.read`. Dry run of the SAVED item (edits need Save first). | — | menu.items.read | – | `menu-studio-page.tsx:151, 726-738` |
| MENU-STUDIO-100 | Query: debounced 300 ms after any selection change; body `{size_label?, option_ids, quantity ≥1, service_mode}`; key `["/menu-items", id, "preview", body]` (so every studio save refreshes it); previous result kept while refetching (small spinner next to the price). | POST `/menu-items/{id}/preview` previewMenuItem | menu.items.read | – | `preview-panel.tsx:94-97, 201, 258-265`; `preview-model.ts:8, 80-92` |
| MENU-STUDIO-101 | "Size" chips (active sizes in order); the server's chosen size is highlighted until one is picked. | — | — | `modeling.preview.size` | `preview-panel.tsx:109-121` |
| MENU-STUDIO-102 | One chip row per attached group with offered active options (required groups marked "*"); option chip shows "+price" (no currency, ≤2 decimals) and "(default)" on the recipe default. Single-choice (or max 1) replaces; a required single choice can't be cleared; multi toggles up to max. Untouched groups use the server's defaults. | — | — | `modeling.preview.default` | `preview-panel.tsx:122-137`; `preview-model.ts:39-73`; test `preview-model.test.ts:30-66` |
| MENU-STUDIO-103 | "Item options" chips for active item-only options (toggle). | — | — | `modeling.preview.itemOptions` | `preview-panel.tsx:138-147` |
| MENU-STUDIO-104 | "Service" chips: Takeaway (default) / Dine-in. | — | — | `modeling.preview.service`, `modeling.preview.takeaway`, `modeling.preview.dineIn` | `preview-panel.tsx:148-155` |
| MENU-STUDIO-105 | "Quantity" stepper: − (aria "Decrease", disabled at 1), value, + (aria "Increase"). | — | — | `modeling.preview.quantity`, `modeling.preview.decrease`, `modeling.preview.increase` | `preview-panel.tsx:156-181` |
| MENU-STUDIO-106 | Result "Price": line "150 + 55 + 30 = 235", options with zero delta omitted, "(…) × q = total" when quantity > 1. | — | — | `modeling.preview.price` | `preview-panel.tsx:42-47, 196-202` |
| MENU-STUDIO-107 | Result "Deducts": "Nothing is deducted" or a list "name · qty unit" + source word (recipe/swap/option/packaging) + " · note"; skipped lines struck through and muted. | — | — | `modeling.preview.deducts`, `modeling.preview.noDeductions`, `modeling.preview.source.*`, `units.*` | `preview-panel.tsx:203-226` |
| MENU-STUDIO-108 | Result "Cost": money + " (partial, some costs missing)" when costs are missing + " · margin {{pct}}" when known. | — | — | `modeling.preview.cost`, `modeling.preview.costPartial`, `modeling.preview.margin` | `preview-panel.tsx:227-236` |
| MENU-STUDIO-109 | Warnings: each with an amber triangle, a mono badge with the rule code and the server message; none → "No issues found". | — | — | `modeling.preview.noIssues` | `preview-panel.tsx:237-249`; test `preview-panel.test.tsx:49-65` |
| MENU-STUDIO-110 | Loading (no data yet): two skeleton lines. Error with no data: red "Couldn't run the preview: {{error}}". | — | — | `modeling.preview.error` | `preview-panel.tsx:185-194` |
| MENU-STUDIO-111 | Phone: each preview row stacks (label above chips). | — | — | – | `preview-panel.tsx:65-75` |

### 3i. Critic additions

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-STUDIO-112 | (critic) Options section with no item-only options: no empty-state text, only the dashed "Add option" button. The section is ungated (no cap check): a read-only person can stage options and Save; the server decides. | — | — | `menu.studio.options.add` | `section-options.tsx:34-141` |
| MENU-STUDIO-113 | (critic) Preview chips use RAW labels: the Size row lists every active size's stored label, so a simple (single-price) item shows one chip reading "one_size" (the grid shows "Price" for the same size); group rows are labelled with the raw group `name`; option and item-option chips show raw option names. | — | menu.items.read | `modeling.preview.size` | `preview-panel.tsx:88-147` |


---

## 4. `/menu/groups` Choice groups

- **Title**: `menu.groups.title` "Choice groups"; subtitle `menu.groups.subtitle` "Milk, beans, flavours, extras: the choices the cashier offers on items."
- **Route**: `src/routes/_app/menu/groups.tsx` (`?edit=<groupId>|new`).
- **Files read**: `src/features/menu/groups/groups-page.tsx`, `group-editor-dialog.tsx`, `group-model.ts`,
  `group-usage-dialog.tsx`, `option-size-grid.tsx`, `use-group-usage.ts`; `recipe/label-grid-editor.tsx`,
  `recipe/label-model.ts`, `recipe/grid-model.ts`; tests `groups-page.test.tsx`, `group-model.test.ts`.
- **Gates**: nav `menu.items.read`; create/reorder/edit/delete/usage apply `menu.items.edit`
  (`useCan`); a read-only person can open a group's editor read-only and the usage dialog read-only.
- **Module**: `pos`. **Realtime**: none.
- **Hooks**: `useListGroups({org_id, include_inactive:true})`, `getGetGroupUsageQueryOptions` per group
  (`useQueries`), `useListCatalog`, `useListGroups({org_id})`, `useListIngredientCategories`,
  `useGroupSizeLabels` (usage + `getMenuItem` per attached item), `useListMenuItems` (usage dialog);
  writes `patchGroup`, `deleteGroup`, `createGroup`, `createOption`, `patchOption`, `deleteOption`,
  `putOptionRecipe`, `listGroups`, `getStudio`, `putModifierGroups`.
- **Invalidation**: reorder/delete → refetch groups + `invalidateCatalog()`; editor save →
  `invalidateCatalog()` (+ the page refetches groups via `onSaved`); usage apply → `invalidateCatalog()` +
  every key starting `/catalog`, containing `/studio`, or starting `/modifier-groups`.

### 4a. List

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-GRP-001 | Header: "Choice groups" + subtitle; action "New group" (Plus) → sets `?edit=new`. | — | menu.items.edit (button) | `menu.groups.title`, `menu.groups.subtitle`, `menu.groups.new` | `groups-page.tsx:146-158` |
| MENU-GRP-002 | No org: EmptyState (Store) "Select an organization to manage its menu" (no header). | — | — | `menu.pickOrg` | `groups-page.tsx:138-144` |
| MENU-GRP-003 | Data: all groups incl. inactive; only SHARED groups shown (`legacy_addon_type` set; item-private "Options" sets are hidden); sorted by `sort`, then name. | GET `/modifier-groups?org_id&include_inactive=true` listGroups | menu.items.read | – | `groups-page.tsx:45, 61-65` |
| MENU-GRP-004 | Loading: nothing rendered under the header. No error state: a failed read shows the empty state. | — | — | – | `groups-page.tsx:160` |
| MENU-GRP-005 | Empty: EmptyState (Layers) "No choice groups yet". | — | — | `menu.groups.empty` | `groups-page.tsx:160-161` |
| MENU-GRP-006 | Row: [drag handle], name (bold) + Arabic name below (RTL, if any) — the name is a button opening the editor (for everyone; read-only without the cap). | — | — | – | `groups-page.tsx:265-290` |
| MENU-GRP-007 | Badge pick rule: "Pick exactly 1" / "Pick up to {{count}}" / "Pick any number" (derived from selection_type/min/max/required, §8). | — | — | `menu.groups.pick.exactlyOneShort`, `menu.groups.pick.upToShort`, `menu.groups.pick.anyShort` | `groups-page.tsx:245-251`; `group-model.ts:47-57` |
| MENU-GRP-008 | Badge effect (filled when it swaps): swaps beans → "Swaps the drink's beans"; swaps another non-milk category → "Swaps an ingredient"; swaps milk → "Swaps the drink's milk"; adds → "Adds ingredients"; none → "Nothing to stock (just a note or a price)"; unknown → "Adds ingredients or nothing". Swap = `effect === "swaps"` or legacy type milk_type/coffee_type. | — | — | `menu.groups.effect.swapsBeans`, `.swapsOther`, `.swapsMilk`, `.adds`, `.none`, `.addsOrNothing` | `groups-page.tsx:252-263` |
| MENU-GRP-009 | Badge "{{count}} option(s)" (plural) and "Inactive" when the group is off. | — | — | `menu.groups.optionCount`, `common.inactive` | `groups-page.tsx:299-306` |
| MENU-GRP-010 | "Used on {{count}} item(s)" link button (plural; "…" and disabled until that group's usage loads) → usage dialog. One usage request per group. | GET `/modifier-groups/{gid}/usage` getGroupUsage ×groups | — | `menu.groups.usedOn` | `groups-page.tsx:66-67, 309-311`; `use-group-usage.ts:11-34` |
| MENU-GRP-011 | Row actions (with the cap): Move up / Move down (disabled at ends and while saving), Edit (pencil, aria "Edit"), Delete (trash, aria "Delete"). | — | menu.items.edit | `menu.studio.steps.moveUp`, `menu.studio.steps.moveDown`, `common.edit`, `common.delete` | `groups-page.tsx:313-330` |
| MENU-GRP-012 | Reorder by drag (pointer ≥ 4 px, keyboard sensor; handle aria "Drag {{name}} to reorder") or arrows: optimistic; then patches `sort` = new index on every group whose position changed, one by one; list `aria-busy` while saving; toast "Changes saved"; failure → order restored + toast.error(server); always refetch + invalidate catalog. | PATCH `/modifier-groups/{gid}` patchGroup `{sort}` ×moved | menu.items.edit | `menu.groups.dragToReorder`, `common.savedChanges` | `groups-page.tsx:83-115, 165, 243, 271-281` |
| MENU-GRP-013 | Delete: confirm (destructive) "Delete {{name}}?" / "If items still offer it or orders used it, it is switched off instead, so history stays intact." / "Delete" → delete; toast "Changes saved"; refetch + invalidate. Error → toast.error(server). | DELETE `/modifier-groups/{gid}` deleteGroup | menu.items.edit | `menu.groups.deleteTitle`, `menu.groups.deleteConsequence`, `common.delete`, `common.savedChanges` | `groups-page.tsx:117-136` |
| MENU-GRP-014 | Refusal: without `menu.items.edit` — no "New group", no drag handles, no move/edit/delete buttons; names still open the editor read-only; "Used on" still opens the usage dialog read-only. | — | menu.items.edit | – | `groups-page.tsx:57, 152, 271, 314`; test `groups-page.test.tsx:48-70` |
| MENU-GRP-015 | Deep link `?edit=<id>` opens that group's editor (unknown id → nothing); `?edit=new` opens the create editor only with the cap. Closing the editor removes `?edit` (history replace). Used by the studio's "Edit group". | — | new: menu.items.edit | – | `groups-page.tsx:59, 78-81, 187-200`; route `groups.tsx:4-10` |
| MENU-GRP-016 | Phone: rows wrap (badges and actions flow to new lines). | — | — | – | `groups-page.tsx:269` |

### 4b. Usage dialog (`group-usage-dialog.tsx`)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-GRP-017 | Title "Items offering {{name}}"; description "Tick the items that offer this group. Per-item rules (required, which options) stay editable in each item's editor." Opened from "Used on" or the editor's "Manage…". | — | — | `menu.groups.usage.title`, `menu.groups.usage.desc` | `group-usage-dialog.tsx:112-120`; `groups-page.tsx:196, 201-212` |
| MENU-GRP-018 | Lists every non-deleted menu item (sorted by name) with a checkbox pre-ticked when it uses the group. | GET `/menu-items?org_id` listMenuItems | — | – | `group-usage-dialog.tsx:40-53` |
| MENU-GRP-019 | Search input (placeholder/aria "Search"): name contains (case-insensitive). | — | — | `common.search` | `group-usage-dialog.tsx:55, 121-126` |
| MENU-GRP-020 | Row: checkbox, name, "Inactive" badge for inactive items, "Required"/"Optional" badge for items currently using it (from usage `is_required`). List scrolls (max 50 vh). | — | — | `common.inactive`, `menu.groups.usage.required`, `menu.groups.usage.optional` | `group-usage-dialog.tsx:127-149` |
| MENU-GRP-021 | Apply (disabled until the ticks differ; spinner): for each added/removed item reads its studio and rewrites its attachments keeping the others' overrides/allowlists; an added group goes last with the group's own min/max/required and all options; a removed one is dropped. Per-item failure → toast.error(server) and continue. After: invalidate; if none failed → toast "Changes saved" + close (else stays open). | GET `/menu-items/{id}/studio` getStudio + PUT `/menu-items/{id}/modifier-groups` putModifierGroups per changed item | menu.items.edit | `menu.groups.usage.apply`, `common.savedChanges` | `group-usage-dialog.tsx:64-110, 150-158` |
| MENU-GRP-022 | Refusal: read-only → checkboxes disabled, no Apply (Cancel only). | — | menu.items.edit | `common.cancel` | `group-usage-dialog.tsx:133, 154` |

### 4c. Group editor dialog (`group-editor-dialog.tsx`; also opened from the add-on dialog and the studio)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-GRP-023 | Title "New choice group" / "Edit choice group"; description "A set of choices the cashier offers on an item, like Milk or Red Bull Type."; scrollable (max 90 dvh), 768 px wide. | — | — | `menu.groups.editor.newTitle`, `.editTitle`, `.desc` | `group-editor-dialog.tsx:313-322` |
| MENU-GRP-024 | Reads while open: ingredient catalog, all groups (for new-group sort and legacy type collisions), ingredient categories, and (editing) the size labels of items the group is attached to. | GET `/inventory/orgs/{orgId}/catalog`; GET `/modifier-groups?org_id`; GET `/inventory/orgs/{orgId}/categories`; GET `/modifier-groups/{gid}/usage` + GET `/menu-items/{id}` per attached item | — | – | `group-editor-dialog.tsx:101-108`; `use-group-usage.ts:40-53` |
| MENU-GRP-025 | Loading: spinner while seeding (an old swap group without `swap_category_id` waits for the ingredient categories). Seeded once per opening (a background refetch never wipes typing). | — | — | – | `group-editor-dialog.tsx:127-173, 324-328` |
| MENU-GRP-026 | Name (EN) required — trimmed min 1 "This field is required"; Name (ع). | — | — | `common.name`, `common.requiredField` | `group-editor-dialog.tsx:332`; `group-model.ts:157-158` |
| MENU-GRP-027 | "What does choosing do?" radio group: "Nothing to stock (just a note or a price)" / "Adds ingredients" (default for new) / "Swaps the drink's [Ingredient category ▾] for the chosen one". Picking a category in the inline combobox also selects "swaps". | — | — | `menu.groups.editor.effectLabel`, `menu.groups.effect.none`, `.adds`, `.swapsPrefix`, `.swapsSuffix`, `menu.groups.editor.swapCategoryPh` | `group-editor-dialog.tsx:334-393` |
| MENU-GRP-028 | Swaps requires a category → "Pick the ingredient category this group swaps" (under the combobox). | — | — | `menu.groups.editor.swapNeedsCategory` | `group-model.ts:167-170` |
| MENU-GRP-029 | Editing + "Nothing" selected → note "Saving as Nothing removes the ingredient lines from these options." | — | — | `menu.groups.editor.noneClears` | `group-editor-dialog.tsx:394-398` |
| MENU-GRP-030 | "Customer must pick": swaps → info text "Exactly 1. A drink has one milk and one bean, so a swap group always takes exactly one choice." (no control); otherwise segmented "Exactly 1" / "Up to…" / "Any number" (default Any for new). | — | — | `menu.groups.editor.pickLabel`, `.swapExactlyOne`, `menu.groups.pick.exactlyOne`, `.upTo`, `.any` | `group-editor-dialog.tsx:306-310, 401-440` |
| MENU-GRP-031 | (corrected) "Up to…" count input (number, min 1, step 1, aria "Most choices"). In the web the dialog is a `<form>` without `noValidate`, so 0, negatives and decimals are stopped by the BROWSER's own validation bubble (min=1/step=1) before zod runs; zod's "Must be at least 1" appears only for an emptied box ("" → 0). The same native layer guards the option "Adds (EGP)" price (step 0.01, min 0: > 2 decimals or negative blocked) and the line "Amount" (min 0: negative blocked; 0 passes to zod → "Enter an amount above 0"). Flutter has no native layer: show the zod messages ("Must be at least 1", zod default for a negative price, "Enter an amount above 0"). | — | — | `menu.groups.editor.upToCount`, `menu.groups.editor.maxAtLeastOne`, `menu.groups.editor.qtyPositive` | `group-editor-dialog.tsx:330, 416-436, 596, 692-700`; `group-model.ts:135, 146, 160` |
| MENU-GRP-032 | Options legend "Options" + help per effect: swaps → "The drink's own recipe decides the default and the amount (e.g. Latte 280 g). Choosing Oat pours 280 g of Oat Milk instead. The price is what the option adds on top."; adds → "These amounts are deducted on top of the drink's recipe whenever the option is chosen."; none → "Choosing an option only changes the price and the ticket. No stock moves." | — | — | `menu.groups.editor.optionsLabel`, `.swapHelp`, `.addsHelp`, `.noneHelp` | `group-editor-dialog.tsx:443-452` |
| MENU-GRP-033 | Swaps with no active ingredient to offer (after the catalog loads): red note — category set → "No active ingredient is in this category yet. Put them in it under Inventory settings."; no category → "Pick the ingredient category this group swaps." | — | — | `menu.groups.editor.noSwapIngredients`, `menu.groups.editor.swapPickCategory` | `group-editor-dialog.tsx:453-459` |
| MENU-GRP-034 | Option row fields: Name (placeholder "e.g. Oat") required "This field is required"; "Arabic name" (RTL); "Adds (EGP)" price ≥ 0; Active switch; "Default" switch; Remove (trash, aria "Remove option"). One line on desktop, stacked on phone. | — | — | `common.name`, `menu.groups.editor.optionNamePh`, `.arabicName`, `.priceAdds`, `common.active`, `.isDefault`, `.removeOption` | `group-editor-dialog.tsx:561-638`; `group-model.ts:140-154` |
| MENU-GRP-035 | Default rule: in a single-choice group (swaps, Exactly 1, or Up to 1) turning one option's Default on turns every other option's Default off; multi-choice groups may have several defaults. | — | — | – | `group-editor-dialog.tsx:471-477` |
| MENU-GRP-036 | Swaps option: "Uses ingredient" combobox limited to active ingredients of the chosen category (hint unit) — required "Pick the ingredient this option pours". | — | — | `menu.groups.editor.usesIngredient`, `.swapNeedsIngredient` | `group-editor-dialog.tsx:190-196, 640-651`; `group-model.ts:172-174` |
| MENU-GRP-037 | Adds option: "Deducts" block with a "Different amounts per size" switch (on when any line has a size label). Off → line list (MENU-GRP-038/039). | — | — | `menu.groups.editor.deducts`, `modeling.options.perSize` | `group-editor-dialog.tsx:652-731`; `option-size-grid.tsx:50-80` |
| MENU-GRP-038 | Adds line: ingredient combobox (active ingredients; picking sets the unit), "Amount" (number, step any, min 0) > 0 → "Enter an amount above 0"; unit word; remove (aria "Remove ingredient"). Same ingredient twice for the same size → "This ingredient is already on this option". | — | — | `menu.groups.editor.amount`, `.qtyPositive`, `.removeLine`, `.duplicateIngredient`, `common.requiredField` | `group-editor-dialog.tsx:664-717`; `group-model.ts:133-139, 175-186` |
| MENU-GRP-039 | "Add ingredient" (ghost) appends a line; "Cost X" shows when every line has a costed ingredient whose unit matches the line. | — | — | `menu.groups.editor.addLine`, `menu.groups.editor.cost` | `group-editor-dialog.tsx:549-559, 719-728` |
| MENU-GRP-040 | Per-size on: grid "All sizes" column + one column per size label (the attached items' labels plus labels already on lines); cells blank = no line; "+ ingredient" combobox; "Size label, e.g. Cup" input + "Size column" button (disabled blank or duplicate; Enter adds); × (aria "Remove column") on every column except All sizes; empty grid "No ingredients yet."; hint "A size column replaces the All sizes amount for that size. Tills that predate per-size amounts use All sizes." | — | — | `modeling.grid.allSizes`, `modeling.grid.addIngredient`, `modeling.grid.sizeLabelPh`, `modeling.grid.addLabel`, `modeling.grid.removeColumn`, `modeling.grid.noLines`, `modeling.options.perSizeHint`, `modeling.grid.cellAria` | `option-size-grid.tsx:81-99`; `label-grid-editor.tsx:33-213`; `label-model.ts:19-75` |
| MENU-GRP-041 | Per-size off again: keeps only the unlabelled (All sizes) lines. | — | — | – | `option-size-grid.tsx:64-73` |
| MENU-GRP-042 | "Add option" (outline, Plus) appends an empty option (price "0", active, not default). | — | — | `menu.groups.editor.addOption` | `group-editor-dialog.tsx:481-490` |
| MENU-GRP-043 | Editing with usage known: "Used on {{count}} items" + "Manage…" link → usage dialog. | — | — | `menu.groups.usedOn`, `menu.groups.manage` | `group-editor-dialog.tsx:493-502` |
| MENU-GRP-044 | Footer: Cancel (or "Close" when read-only) + Save (spinner; hidden when read-only). Read-only: every control disabled. | — | menu.items.edit | `common.cancel`, `common.close`, `common.save` | `group-editor-dialog.tsx:331, 505-514` |
| MENU-GRP-045 | (corrected) Save, group: edit → PATCH `{name, name_translations (merged, ar), selection_type, min_selections, max_selections (null = any), is_required, is_active, effect, swap_category_id (swaps only, else null)}`; create → POST `{name, name_translations, selection fields, sort = length of the editor's own `GET /modifier-groups?org_id` read (no `include_inactive`; item-private option sets counted too, 0 if not loaded), effect, swap_category_id, legacy_addon_type: null for swaps else derived from the name (§8)}` then PATCH `{is_active:false}` if created switched off. | PATCH `/modifier-groups/{gid}` patchGroup / POST `/modifier-groups` createGroup | menu.items.edit | – | `group-editor-dialog.tsx:198-230`; `group-model.ts:27-43, 81-99` |
| MENU-GRP-046 | Save, options: delete removed options; for kept options PATCH only when name, Arabic name, price, active, default, sort or swap ingredient changed `{name, name_translations, price, is_active, is_default, sort, replaces_ingredient_id|null}`; new options → POST `{name, name_translations, price, is_active, replaces_ingredient_id}` then PATCH `{sort, is_default}`. | DELETE / PATCH `/modifier-options/{oid}`; POST `/modifier-groups/{gid}/options` createOption | menu.items.edit | – | `group-editor-dialog.tsx:232-275` |
| MENU-GRP-047 | Save, recipes: per option, when its line set changed, replace it: swaps → one line `{ingredient, quantity 1, unit from catalog (else pcs), size_label null}`; adds → its lines with size labels; none → `[]`. | PUT `/modifier-options/{oid}/recipe` putOptionRecipe | menu.items.edit | – | `group-editor-dialog.tsx:276-287`; `group-model.ts:202-218` |
| MENU-GRP-048 | Save success: toast "Changes saved", invalidate catalog, re-read groups to hand the fresh group to the caller (page refetch / add-on dialog select / studio attach), close. Error → toast.error(server), stays open. | GET `/modifier-groups?org_id` listGroups | — | `common.savedChanges` | `group-editor-dialog.tsx:290-300` |

### 4d. Critic additions

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-GRP-049 | (critic) Hidden fields are still validated on Save and their message has nowhere to render: an invalid "Up to…" count (e.g. emptied) later hidden by picking "Exactly 1" / "Any number" or by switching to Swaps, or an "Adds ingredients" line left blank/zero and then hidden by switching the effect to Nothing / Swaps (or by turning "Different amounts per size" on before editing the grid), blocks Save with NO visible message, no toast and no request. | — | menu.items.edit | `menu.groups.editor.maxAtLeastOne`, `menu.groups.editor.qtyPositive`, `common.requiredField` | `group-model.ts:132-189`; `group-editor-dialog.tsx:404-439, 640-731`; `option-size-grid.tsx:64-73` |
| MENU-GRP-050 | (critic) Usage dialog states: no loading indicator (the list is just empty until `GET /menu-items` returns), no empty / no-match text (a search with no hits leaves an empty bordered box), item names raw (untranslated), combos and inactive items listed, whole list rendered (no paging). Opened from the editor's "Manage…" it stacks on top of the still-open editor. | GET `/menu-items?org_id` listMenuItems | — | – | `group-usage-dialog.tsx:40-55, 127-149`; `groups-page.tsx:187-212` |


---

## 5. `/menu/pricing` Pricing & availability

- **Title**: `menu.pricing.title` "Pricing & availability" (nav: `nav.pricingAvailability` "Pricing & Availability");
  subtitle `menu.pricing.matrixSubtitle` "Set the effective price and availability for every scope side by side — in-store and each delivery channel."
- **Route**: `src/routes/_app/menu/pricing.tsx`.
- **Files read**: `src/features/menu/pricing/pricing-availability-page.tsx`, `pricing/util.ts`; test
  `pricing-availability-page.test.tsx`; `src/hooks/use-mobile.ts`.
- **Gates**: nav `menu.items.edit`; no in-page guard (a read-only person typing the URL can stage edits; the
  server refuses each write → "Saved 0, N failed").
- **Module**: `pos`. **Realtime**: none.
- **Hooks**: `useListBranches`, `useListMenuCatalog` (keepPreviousData), `useListAddonCatalog`
  (keepPreviousData), `useListBranchAddonOverrides`, `useListChannelAddonOverrides` ×4, `useGetStudio` per
  expanded item; writes `putPriceOverride`, `deletePriceOverride`.
- **Invalidation**: after Save → `invalidatePricingOverrides()`.

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-PRC-001 | Header title + subtitle. | — | menu.items.edit (nav) | `menu.pricing.title`, `menu.pricing.matrixSubtitle` | `pricing-availability-page.tsx:1474-1486` |
| MENU-PRC-002 | No org: header + EmptyState (Store) "Select an organization to manage pricing". | — | — | `menu.pricing.pickOrg` | `pricing-availability-page.tsx:1231-1238` |
| MENU-PRC-003 | Branches loading: a 448 px bar skeleton + a big block skeleton. | GET `/branches?org_id` listBranches | — | – | `pricing-availability-page.tsx:1037-1041, 1328-1332` |
| MENU-PRC-004 | "All branches" or no branch scoped: EmptyState (Store) "Pick a specific branch" / "Branch and channel overrides need a concrete branch. Choose one in the branch picker at the top." | — | — | `menu.pricing.pickBranchTitle`, `menu.pricing.pickBranchHint` | `pricing-availability-page.tsx:1333-1341` |
| MENU-PRC-005 | Toolbar under the header (one branch scoped): segmented "Menu items" / "Add-ons" (default Menu items; not in URL), the active tab's search box (placeholder/aria "Search"), the branch name with a Store icon, and the legend at the end. | — | — | `menu.pricing.menuItems`, `menu.pricing.addonItems`, `common.search` | `pricing-availability-page.tsx:1303-1326` |
| MENU-PRC-006 | Legend: tinted swatch "Unsaved", ↳ "Inherited (muted)", red eye-off "Hidden here". | — | — | `menu.pricing.legendDirty`, `.legendInherited`, `.legendHidden` | `pricing-availability-page.tsx:1282-1297` |
| MENU-PRC-007 | Switching the scoped branch drops every staged edit. | — | — | – | `pricing-availability-page.tsx:1056-1061` |
| MENU-PRC-008 | Items tab data: 24 per page, server search (debounced 300 ms). Web quirk: changing the search does NOT reset to page 1. | GET `/costing/catalog` listMenuCatalog `{org_id, search, page, per_page:24}` | — | – | `pricing-availability-page.tsx:1029-1032, 1080-1089` |
| MENU-PRC-009 | Items tab states: loading → big skeleton; error → ErrorState "Couldn't load items" + server message + Retry (spinner); empty → EmptyState (UtensilsCrossed) "No menu items". | — | — | `menu.pricing.loadError`, `menu.pricing.noItems`, `common.retry` | `pricing-availability-page.tsx:1346-1356` |
| MENU-PRC-010 | Desktop (≥ 768 px) matrix: header row "Item / size" (sticky first column) · "Catalog (ref)" · "In-store" · "In-mall" · "Outside" · "Umbrella" · "Pickup"; horizontal scroll with the first column sticky. | — | — | `menu.pricing.itemColumn`, `menu.pricing.col_catalog`, `menu.pricing.readonly` "ref", `.col_in_store`, `.col_in_mall`, `.col_outside`, `.col_umbrella`, `.col_pickup` | `pricing-availability-page.tsx:784-827, 1373-1386` |
| MENU-PRC-011 | Item row (collapsed): chevron, image tile (asset/legacy/CupSoda), translated name, "Expand to price sizes"; a dot when any of its cells is dirty. Tap → expand ("Collapse"). | — | — | `menu.pricing.expandHint`, `menu.pricing.collapseHint` | `pricing-availability-page.tsx:632-698`; test `pricing-availability-page.test.tsx:46-68` |
| MENU-PRC-012 | Expanding an item loads its studio (sizes + this branch's branch/channel override rows); loading → skeleton row; error → "Couldn't load items"; no sizes → "No sizes to price". | GET `/menu-items/{id}/studio` getStudio | — | `menu.pricing.loadError`, `menu.pricing.noSizes` | `pricing-availability-page.tsx:576-628, 700-719` |
| MENU-PRC-013 | Size sub-row: size label pill (+ "inactive" for inactive sizes), Catalog cell (size price, money, read-only), then five editable cells. | — | — | `menu.pricing.inactive` | `pricing-availability-page.tsx:720-742, 475-481` |
| MENU-PRC-014 | Editable cell price input (number, decimal keyboard, aria "Price ({{currency}})"): an explicit override at this scope shows its EGP value bold; an inherited cell is blank with the effective price as muted placeholder (integer, or up to 2 decimals trimmed). Typing a value makes it explicit; blanking it (then Save) returns to inheritance. | — | — | `menu.pricing.priceAria` | `pricing-availability-page.tsx:330-379, 483-488` |
| MENU-PRC-015 | Under the input: "Set here" when a price is typed; else "↳ Branch" (channel cell inheriting the branch price) or "↳ Catalog" with a tooltip "↳ branch"/"↳ catalog". | — | — | `menu.pricing.explicit`, `.branchPrice`, `.catalogPrice`, `.fromBranch`, `.fromCatalog` | `pricing-availability-page.tsx:400-413` |
| MENU-PRC-016 | Availability toggle (eye / eye-off, role switch, aria "Available"/"Hidden", tooltip "Hide at this scope"/"Show at this scope"): red when hidden, muted when inherited. Starts at the effective availability (channel → branch → available). | — | — | `menu.pricing.available`, `.hidden`, `.markHidden`, `.markAvailable` | `pricing-availability-page.tsx:415-446` |
| MENU-PRC-017 | Clear (×, tooltip/aria "Remove override") — shown on an explicit, not-yet-edited cell; stages blank price + available (Save deletes the row). | — | — | `menu.pricing.clearOverride` | `pricing-availability-page.tsx:380-397, 530-534` |
| MENU-PRC-018 | Dirty cell: tinted background; the draft is dropped automatically when it matches the server again (count stays honest). | — | — | – | `pricing-availability-page.tsx:184-195, 239-254, 465` |
| MENU-PRC-019 | Add-ons tab data: 24 per page with server search (no page reset on search, as items), plus the branch add-on overrides and one channel-override read per channel. | GET `/addon-items/catalog` listAddonCatalog `{org_id, search, page, per_page:24}`; GET `/branch-addon-overrides?branch_id`; GET `/delivery/channel-addon-overrides?branch_id&channel=in_mall|outside|umbrella|pickup` ×4 | — | – | `pricing-availability-page.tsx:1033-1035, 1084-1162` |
| MENU-PRC-020 | Add-ons states: loading (add-ons or branch overrides) → skeleton; error → ErrorState "Couldn't load items" + message + Retry (refetches both); empty → EmptyState (Tag) "No add-ons". | — | — | `menu.pricing.loadError`, `menu.pricing.noAddons` | `pricing-availability-page.tsx:1394-1403` |
| MENU-PRC-021 | Add-on matrix row (desktop): Tag tile, translated name, dirty dot; header first column "Add-on"; Catalog = default price; five editable cells. | — | — | `menu.pricing.addonColumn` | `pricing-availability-page.tsx:751-780, 1422-1436` |
| MENU-PRC-022 | Phone (< 768 px): no table — one card per item (tap header to expand, same hints/dot) or add-on; inside, per size: label pill, a "Catalog (ref)" line with the price, then one row per scope (label + the same control with 36–40 px touch targets). Same staged edits as desktop. | — | — | `menu.pricing.col_*`, `menu.pricing.readonly` | `pricing-availability-page.tsx:835-1009, 1358-1371, 1405-1420` |
| MENU-PRC-023 | Pagination per tab (only > 1 page): "Page {{current}} of {{total}}", Previous/Next (RTL-mirrored chevrons). | — | — | `common.page`, `common.previous`, `common.next` | `pricing-availability-page.tsx:1253-1280, 1390, 1440` |
| MENU-PRC-024 | Floating save bar (fixed, bottom centre above the safe area, only while ≥ 1 cell is dirty; a 64 px spacer keeps the last row clear): "{{count}} unsaved changes" (count = dirty cells), "Discard" (drops all), "Save" (spinner; both disabled while saving). Edits survive tab and page switches until saved/discarded. | — | — | `menu.pricing.unsavedN`, `menu.pricing.discard`, `common.save` | `pricing-availability-page.tsx:1446-1467` |
| MENU-PRC-025 | Save validation: a typed price that is not a number ≥ 0 → error toast "Enter a valid price for {{name}}" (item or add-on name); nothing written. | — | — | `menu.pricing.invalidPriceFor` | `pricing-availability-page.tsx:309-318, 1189-1193` |
| MENU-PRC-026 | Save writes (all in parallel): per dirty cell — price typed or hidden → PUT `{scope: "branch" (In-store) or "branch_channel", branch_id, channel (null for In-store), target_type "menu_item_size"/"modifier_option", target_id, price (piastres)|null, is_available: false|null}`; blank + available and a row existed → DELETE same identity; else nothing. | PUT / DELETE `/menu-price-overrides` putPriceOverride / deletePriceOverride | menu.items.edit (server) | – | `pricing-availability-page.tsx:277-307, 1186-1208` |
| MENU-PRC-027 | Save result: all ok → toast "Saved {{count}} changes" + clear; some failed → error toast "Saved {{ok}}, {{failed}} failed" and only the failed cells stay dirty. Always refresh the override reads and expanded studios. | — | — | `menu.pricing.savedN`, `menu.pricing.savedPartial` | `pricing-availability-page.tsx:1209-1228`; `pricing/util.ts:17-27` |
| MENU-PRC-028 | Only cells of expanded items (any page visited) and add-ons on the CURRENT add-on page are collected; a dirty add-on cell on another page stays counted but is not written (web quirk). | — | — | – | `pricing-availability-page.tsx:1167-1184` |
| MENU-PRC-029 | (critic) Web quirk: a channel cannot be shown when the In-store (branch) cell hides the target. The channel cell starts hidden (inherited); toggling it to available stages a change (tinted, counted), but Save plans NO write for it (`is_available: null`, no price, no channel row → nothing), still counts it in "Saved {{count}} changes", and after the refresh the cell is hidden again. With an explicit channel price the PUT carries `is_available: null`, which still inherits the branch's hide. | (none for that cell) | — | `menu.pricing.savedN` | `pricing-availability-page.tsx:161-169, 184-195, 277-307, 1196-1216` |
| MENU-PRC-030 | (critic) Because a new search keeps the current page (MENU-PRC-008/019), searching from page 2+ can return an empty page: "No menu items" / "No add-ons" shows and the pager is hidden (≤ 1 page), so the only way back is clearing the search. | GET `/costing/catalog` · `/addon-items/catalog` with `page` > total_pages | — | `menu.pricing.noItems`, `menu.pricing.noAddons` | `pricing-availability-page.tsx:1080-1087, 1253-1254, 1355-1356, 1402-1403` |
| MENU-PRC-031 | (critic) The invalid-price toast looks the item's name up on the CURRENT items page only: a bad price staged on an item expanded on another page reads "Enter a valid price for " with an empty name. | — | — | `menu.pricing.invalidPriceFor` | `pricing-availability-page.tsx:1170-1176, 1189-1192` |
| MENU-PRC-032 | (critic) The four channel add-on override reads have no loading or error handling: while pending or after a failure their cells render as inherited (no channel override) and edits are planned as if no channel row existed. Only the add-on list and the branch add-on overrides drive the skeleton / ErrorState. | GET `/delivery/channel-addon-overrides?branch_id&channel` ×4 | — | – | `pricing-availability-page.tsx:1098-1162, 1394-1401` |
| MENU-PRC-033 | (critic) Size sub-rows (desktop and phone) list EVERY size from the studio aggregate sorted by `sort`, with the raw stored label: a simple item's single size reads "one_size"; inactive sizes are included (with "inactive") and editable like the others. | GET `/menu-items/{id}/studio` | — | `menu.pricing.inactive` | `pricing-availability-page.tsx:585-618, 720-742, 990-1003` |


---

## 6. `/menu/bases` Recipe bases

- **Title**: `modeling.bases.title` "Recipe bases"; subtitle `modeling.bases.subtitle` "Lines several drinks share. Edit once and every size using the base follows."
- **Route**: `src/routes/_app/menu/bases.tsx`. **Files read**: `src/features/menu/recipe/bases-page.tsx`,
  `label-grid-editor.tsx`, `label-model.ts`, `use-ingredient-picker.ts`, `grid-model.ts`; (critic) test `label-model.test.ts`
  (round-trip, blank cells dropped, the All sizes column can never be removed).
- **Gates**: nav `menu.items.read`; New/Edit/Delete `menu.items.edit`. **Module**: `pos`. **Realtime**: none.
- **Hooks**: `useListBases`, `useGetBaseUsage`, `useListCatalog`; writes `createBase`, `patchBase`,
  `putBaseLines`, `deleteBase`.
- **Invalidation**: create/save/delete → `getListBasesQueryKey()` (`/recipe-bases`) + `invalidateCatalog()`.

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-BAS-001 | Header (reading width): title + subtitle; "New base" (Plus, small). | — | menu.items.edit (button) | `modeling.bases.title`, `modeling.bases.subtitle`, `modeling.bases.new` | `bases-page.tsx:74-89` |
| MENU-BAS-002 | Data: all bases of the org (server scopes; only fetched with an org). | GET `/recipe-bases` listBases | menu.items.read | – | `bases-page.tsx:50` |
| MENU-BAS-003 | Loading: one 160 px skeleton. | — | — | – | `bases-page.tsx:90-91` |
| MENU-BAS-004 | Error: ErrorState "Could not load recipe bases" + server message + Retry. | GET `/recipe-bases` | — | `modeling.bases.loadError`, `common.retry` | `bases-page.tsx:92-97` |
| MENU-BAS-005 | Empty: EmptyState (Layers3) "No recipe bases yet" / "Create one for lines many drinks share, then pick it in an item's recipe." | — | — | `modeling.bases.empty`, `modeling.bases.emptyHint` | `bases-page.tsx:98-103` |
| MENU-BAS-006 | Row: name + "Inactive" pill when off; sub-line "Affects {{items}} items / {{sizes}} sizes · {{count}} lines". | — | — | `modeling.bases.affects`, `modeling.bases.lineCount`, `common.inactive` | `bases-page.tsx:105-121` |
| MENU-BAS-007 | Row actions (with the cap): Edit (pencil, aria "Edit"), Delete (trash, aria "Delete"). | — | menu.items.edit | `common.edit`, `common.delete` | `bases-page.tsx:122-137` |
| MENU-BAS-008 | Refusal: without `menu.items.edit` no "New base" and no row actions (list is read-only). | — | menu.items.edit | – | `bases-page.tsx:52, 83, 122` |
| MENU-BAS-009 | Delete: confirm (NOT destructive-styled) `Delete "{{name}}"?` / "Sizes using this base lose its lines. Their own lines stay." / "Delete" → toast "Base deleted"; invalidate. Error → toast.error(server). | DELETE `/recipe-bases/{id}` deleteBase | menu.items.edit | `modeling.bases.deleteTitle`, `modeling.bases.deleteDesc`, `common.delete`, `modeling.bases.deleted` | `bases-page.tsx:54-72` |
| MENU-BAS-010 | Editor dialog (768 px): title "New base" / "Edit base"; description = "Affects {{items}} items / {{sizes}} sizes" once the usage loads (edit), else "Amounts in the All sizes column apply to every size; a size column overrides it." Reset on every open. | GET `/recipe-bases/{id}/usage` getBaseUsage (edit) | — | `modeling.bases.new`, `modeling.bases.edit`, `modeling.bases.affects`, `modeling.bases.editorDesc` | `bases-page.tsx:152-231` |
| MENU-BAS-011 | Name (EN) required (trimmed) "This field is required"; Name (ع). | — | — | `common.name`, `common.requiredField` | `bases-page.tsx:169-177, 234` |
| MENU-BAS-012 | Active switch. | — | — | `common.active` | `bases-page.tsx:235-246` |
| MENU-BAS-013 | Lines grid (ingredients × "All sizes" + size-label columns): cells blank = no line; "+ ingredient" combobox (active ingredients not yet in the grid); "Size label, e.g. Cup" + "Size column" (disabled blank/duplicate; Enter adds); × on size columns (not All sizes); "No ingredients yet."; remove row (trash); Enter/↓ and Shift+Enter/↑ move within a column; digits + one dot only. | GET `/inventory/orgs/{orgId}/catalog` listCatalog | — | `modeling.grid.allSizes`, `modeling.grid.addIngredient`, `modeling.grid.sizeLabelPh`, `modeling.grid.addLabel`, `modeling.grid.removeColumn`, `modeling.grid.noLines`, `recipes.builder.removeIngredient`, `recipes.ingredient`, `modeling.grid.cellAria` | `bases-page.tsx:247-256`; `label-grid-editor.tsx:33-213` |
| MENU-BAS-014 | "Used by" collapsible (when the usage lists sizes): "item name · size label" per size. | — | — | `modeling.bases.usedBy` | `bases-page.tsx:257-270` |
| MENU-BAS-015 | Save create: POST `{name (trim), name_ar|null, is_active, lines:[{size_label|null, ingredient_id, quantity, unit, sort}]}` → toast "Base created". | POST `/recipe-bases` createBase | menu.items.edit (server) | `modeling.bases.created` | `bases-page.tsx:191-196` |
| MENU-BAS-016 | Save edit: PATCH name/name_ar/is_active only if changed; PUT lines only if the lines changed; toast "Base saved · {{count}} sizes updated" (sum of `sizes_changed`). | PATCH `/recipe-bases/{id}` patchBase; PUT `/recipe-bases/{id}/lines` putBaseLines | menu.items.edit (server) | `modeling.bases.saved` | `bases-page.tsx:197-208` |
| MENU-BAS-017 | Save end: invalidate bases + catalog; close. Error → toast.error(server), stays open. Cancel closes. | — | — | `common.save`, `common.cancel` | `bases-page.tsx:209-214, 271-278` |
| MENU-BAS-018 | (critic) Editing with nothing changed: Save sends no request, still toasts "Base saved · 0 sizes updated", invalidates bases + catalog and closes. The lines diff compares the cleaned list (blank cells dropped), so typing then clearing a cell counts as no change. | — | — | `modeling.bases.saved` | `bases-page.tsx:197-211` |


---

## 7. `/menu/packaging` Packaging rules

- **Title**: `modeling.packaging.title` "Packaging rules"; subtitle `modeling.packaging.subtitle` "Cups, lids and straws added to sizes automatically. The most specific matching rule wins."
- **Route**: `src/routes/_app/menu/packaging.tsx`. **Files read**: `src/features/menu/recipe/packaging-rules-page.tsx`,
  `label-grid-editor.tsx`, `use-ingredient-picker.ts`, `grid-model.ts`; test `modeling-authz.test.tsx`.
- **Gates**: nav `menu.items.read`; New/Edit/Delete `menu.items.edit`; Apply `menu.packaging_rules.apply`.
  **Module**: `pos`. **Realtime**: none.
- **Hooks**: `useListRules`, `useListCategories`, `useListMenuCatalog({per_page:500})`, `useListCatalog`;
  writes `applyRules`, `createRule`, `patchRule`, `deleteRule`.
- **Invalidation**: apply → `invalidateCatalog()`; create/edit/delete → `getListRulesQueryKey()` (`/packaging-rules`) only.

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| MENU-PKG-001 | Header (reading width): title + subtitle; actions "Apply rules" (outline, Play, spinner) and "New rule" (Plus). | — | apply: menu.packaging_rules.apply; new: menu.items.edit | `modeling.packaging.title`, `.subtitle`, `.apply`, `.new` | `packaging-rules-page.tsx:110-132` |
| MENU-PKG-002 | Data: rules; plus categories and up to 500 menu items (for match labels and pickers). | GET `/packaging-rules` listRules; GET `/categories`; GET `/costing/catalog?per_page=500` | menu.items.read | – | `packaging-rules-page.tsx:56, 64-77` |
| MENU-PKG-003 | Loading skeleton; error ErrorState "Could not load packaging rules" + message + Retry; empty EmptyState (Package) "No packaging rules yet" / "e.g. Iced drinks · Cup → 16oz cup, lid, straw." | — | — | `modeling.packaging.loadError`, `.empty`, `.emptyHint`, `common.retry` | `packaging-rules-page.tsx:150-163` |
| MENU-PKG-004 | Row: name + "Inactive" pill; sub-line "<item> · <category> · <size label>" (only the set matches; "—" for an unknown id) or "Every size", then " → " and the lines "ingredient qty" joined ", " (or "—"). | — | — | `modeling.packaging.matchAll`, `common.inactive` | `packaging-rules-page.tsx:165-184` |
| MENU-PKG-005 | Row actions (with the cap): Edit, Delete. | — | menu.items.edit | `common.edit`, `common.delete` | `packaging-rules-page.tsx:185-200` |
| MENU-PKG-006 | Refusal: without the caps the Apply and New buttons and the row actions are hidden. | — | caps | – | `packaging-rules-page.tsx:59-61, 120-129`; test `modeling-authz.test.tsx:37-54` |
| MENU-PKG-007 | Apply rules: runs the server apply; shows an Alert under the header "Rules applied" / "{{seen}} sizes checked · {{withRule}} matched a rule · {{changed}} changed · {{manual}} keep hand-entered packaging" (stays until the next apply); invalidate catalog. Error → toast.error(server). | POST `/packaging-rules/apply` applyRules | menu.packaging_rules.apply | `modeling.packaging.appliedTitle`, `.appliedBody` | `packaging-rules-page.tsx:81-92, 133-149` |
| MENU-PKG-008 | Delete: confirm (not destructive-styled) `Delete "{{name}}"?` / "Sizes keep their current packaging until rules are applied again." / "Delete" → delete; refresh rules. NO success toast. Error → toast.error(server). | DELETE `/packaging-rules/{id}` deleteRule | menu.items.edit | `modeling.packaging.deleteTitle`, `.deleteDesc`, `common.delete` | `packaging-rules-page.tsx:94-107` |
| MENU-PKG-009 | Rule dialog (672 px): title "New rule" / "Edit rule"; description "Leave a match empty to match any. An item match beats category + size, which beats either alone." Reset on every open. | — | — | `modeling.packaging.new`, `.edit`, `.matchHelp` | `packaging-rules-page.tsx:258-308` |
| MENU-PKG-010 | Name required (trimmed) "This field is required". | — | — | `common.name`, `common.requiredField` | `packaging-rules-page.tsx:241-242, 311-323` |
| MENU-PKG-011 | "Menu category" combobox: "Any" + categories (translated). | — | — | `modeling.packaging.matchCategory`, `modeling.packaging.any` | `packaging-rules-page.tsx:325-338` |
| MENU-PKG-012 | "Size label" text input (placeholder "Any"). | — | — | `modeling.packaging.matchSize`, `modeling.packaging.any` | `packaging-rules-page.tsx:339-350` |
| MENU-PKG-013 | "Item" combobox: "Any" + items (names). Three match fields side by side from 640 px, stacked on phone. | — | — | `modeling.packaging.matchItem` | `packaging-rules-page.tsx:324, 351-365` |
| MENU-PKG-014 | Active switch. | — | — | `common.active` | `packaging-rules-page.tsx:366-377` |
| MENU-PKG-015 | Lines grid: one fixed column "Quantity" (no size columns), "+ ingredient", remove, keyboard as MENU-BAS-013. | GET `/inventory/orgs/{orgId}/catalog` | — | `common.quantity`, `modeling.grid.addIngredient`, `modeling.grid.noLines` | `packaging-rules-page.tsx:255-278, 378-384` |
| MENU-PKG-016 | Save: POST/PATCH `{name (trim), match_category_id|null, match_size_label (trim)|null, match_item_id|null, is_active, lines:[{ingredient_id, quantity, unit}]}`; toast "Rule saved. Apply rules to update existing sizes."; refresh rules; close. Error → toast.error(server). Cancel closes. | POST `/packaging-rules` createRule / PATCH `/packaging-rules/{id}` patchRule | menu.items.edit (server) | `modeling.packaging.saved`, `common.save`, `common.cancel` | `packaging-rules-page.tsx:280-298, 385-392` |


---

## 8. Formatting and browser-side computations

### Formatting (`src/lib/format.ts`)

- **Money is minor units (piastres)**: `egpToPiastres(egp) = Math.round(egp × 100)`; `piastresToEgp(p) = p / 100`.
  Every input in this area is typed in pounds and sent in piastres.
- **`fmtMoney(p)`**: null/undefined/non-finite → "—" (unknown, not free). 2 decimals, en-US grouping, Latin
  digits always (also in Arabic). EN: `EGP 1,234.50`; AR: `‎1,234.50‎ ج.م` (figure wrapped in LRI…PDI, then
  the Arabic label). Negative uses U+2212 "−". `signed: true` adds "+" (meal delta). `currency:false,
  fractionDigits:0` (preview chips/price line) = figure only, 0–2 decimals.
- **`currencyLabel()`**: "EGP" / "ج.م" (DEFAULT_CURRENCY EGP; other codes have Arabic labels). Used in the
  studio grid Price row, the paste column header and the pricing aria label. **Hard-coded "(EGP)"** (not
  translated, also in Arabic) in: item dialog "Price (EGP)" labels, studio options "Price (EGP)", and the
  en.json texts "Default price (EGP)", "Adds (EGP)", "Cost / unit (EGP)", "Cost per {{unit}} (EGP)".
- **`fmtNumber`**: Intl, locale `en-GB` / `ar-EG`, `numberingSystem: latn`, minus → U+2212 (tab count
  badges, preview deduction quantities).
- **`fmtPercent(ratio)`**: Intl percent, max 1 decimal, Latin digits (margins, food-cost chips).
- **Units**: `units.{g,kg,ml,l,pcs}` → g/kg/ml/L/pcs, Arabic جم/كجم/مل/لتر/قطعة; `fmtUnit` (no i18n) maps
  l → "L" (group editor, studio modifiers recipe list).
- **Tax rate** (`formatRate`): fraction × 100 rounded to 4 dp + "%".
- **Dates/timezones**: none on these pages. Only the Excel export: file name date = `new Date().toISOString()
  .slice(0,10)` (UTC date), sheet sub-line "Generated: <fmtDateTimeFull(now)>" in the active zone.
- **Translated names**: `getTranslatedName` = `name_translations.ar` when the UI language starts with "ar"
  and an Arabic name exists, else `name`. Applies to items, categories, add-ons, combos, slots. Groups
  lists show `name` (+ Arabic below); the studio modifiers, add-on dialog group select, packaging item
  options and usage dialog show the raw `name`.
- **Quantity inputs in grids**: keep digits and one "." (comma → "."). Rounding to 3 dp on scale/copy
  (`Math.round(q×1000)/1000`), blanks stay blank.
- **Native constraints**: the web's dialogs use `<input type=number step=0.01 min=0>` inside a form
  without `noValidate`, so the browser blocks submit for > 2 decimals or negatives in those fields (item
  dialog prices, add-on default price). Zod default messages (no app error map, zod v4, English only):
  `min(0)` on numbers → "Too small: expected number to be >=0"; non-numeric coerce → "Invalid input:
  expected number, received NaN".

### Computations done in the browser (port these exactly)

1. **Humanized add-on type** (item dialog picker, studio modifier badges): strip a trailing `_type`, `_` →
   space, capitalise each word (`milk_type` → "Milk"). `menu-item-dialog.tsx:57-60`, `section-modifiers.tsx:29-33`.
2. **Item "from" price on create** = min of the size prices (piastres). `menu-item-dialog.tsx:201`.
3. **Add-on selection → group attachments** (item dialog): type → group whose `legacy_addon_type ?? name`
   equals it; one attachment per type in first-seen order; written only when the order-free selection key
   changed. `menu-item-dialog.tsx:63, 242-258`.
4. **Recipe builder estimate/margin**: estimate = Σ cost_per_unit × qty, null if any row lacks a positive
   cost or numeric qty; margin = (price − est)/price when price > 0; colours ≥ 0.6 success, ≥ 0.3 neutral,
   else warning; price for a size = that size's price else min of all sizes. `recipe-builder.tsx:95-98, 242-250`.
5. **Food-cost chip**: add-on pct = cost/price (price > 0); thresholds < 0.30 green, ≤ 0.40 amber, else red.
   Item pct comes from the server (`food_cost_pct`). `cost-cells.tsx:9-22, 61`.
6. **Studio dirty signatures** (`studio/util.ts:247-273`): item = [name, name_ar, description,
   description_ar, category_id, is_active]; sizes = [[label, price]…]; recipe per size = own payload
   [[ingredient_id, Number(qty), unit]…] (lines with blank/non-numeric qty excluded); modifiers =
   [[group_id, min, max, is_required, sorted allowlist|null]…]; options = [[id, name, price, active,
   ingredient_id, quantity, unit]…]; steps = [[kind, slug, trimmed title, title_ar, note, note_ar]…].
   Dirty count = number of dirty sections.
7. **Studio grid pivot** (`grid-model.ts:70-91`): one row per (source, ingredient); order own/linked (0),
   base (1), rule (2), stable within; `setCell`/`addRow`/`removeRow`/`copyColumn`/`scaleColumn` only touch
   own lines.
8. **Studio grid cost footer**: estimate when the column is new, recipe-dirty, or its price changed
   (skip lines with blank qty; incomplete if no ingredient / no positive unit cost / bad qty), else
   server `cost_piastres`/`cost_incomplete`; margin = (price − cost)/price when complete and price > 0.
   `recipe-grid.tsx:70-84, 463-471`.
9. **Swappable badge**: ingredient category slug ∈ {milk, coffee_bean} and some attached group has an
   option whose recipe/`replaces_ingredient_id` ingredient shares that slug → that group's name.
   `grid-model.ts:155-175`.
10. **Base picker value**: no saved sizes → None; all saved sizes share one base (or none) → it; else
    "mixed". Offered bases = active ∪ currently used. `base-picker.tsx:34-35, 71-73`.
11. **Option row cost** (studio options) = unit cost × qty when both known; group editor adds-option cost =
    Σ cost × qty only when every line's ingredient is costed AND the line unit equals the ingredient unit.
12. **Modifiers allowlist**: toggling builds from "all" when null; collapses back to null when every
    option is offered. `section-modifiers.tsx:86-98`. Seeding: `included_option_ids = null` when every
    option is `included`.
13. **Meal delta** (`combos/meal.ts:19-79`): slot admits the item if a choice names the item, else a
    choice names its category. `pickExtra(choice, item, sizeLabel)` = choice surcharge + (size ≠ included
    size ? owner's size surcharge for that label, else max(0, chosen size price − included size price) :
    0); included size = choice's `included_size_label` else the item's cheapest active size. Delta =
    combo price + pickExtra(own choice, item, none) + Σ over slots (picks = slot.min, minus 1 for this
    item's slot) × default pick extra (default item or first item choice, at the slot's default size) −
    item's price at its included size. Not shown when any piece is missing.
14. **Preview selection** (`preview-model.ts`): groups = attached groups sorted, single when
    `selection_type single` or max 1, required when `is_required` or min > 0, options = included & active;
    groups with no options dropped. Picks per group explicit else the server default; single: tapping the
    picked one clears it unless required; multi: add unless at max. Body quantity = max(1, floor(q)).
    Price line: base and non-zero option deltas joined " + ", "(…) × q" when q > 1, " = total".
15. **Choice-group model** (`group-model.ts`): pick rule ↔ fields — Exactly 1 → single, min 1, max 1,
    required; Up to n → (n = 1 ? single : multi), min 0, max n, not required; Any → multi, 0, null, not
    required. Reading back: max 1 and (required or min ≥ 1) → Exactly 1; no max → single ? Up to 1 : Any;
    else Up to max. Swaps always save as Exactly 1. Legacy type for a new non-swap group: name
    lower-cased, non-alphanumerics → "_", trimmed; blank, a swap type, or starting `milk`/`coffee` →
    "extra"; taken by another group → suffix `_2`, `_3`… Effect read-back: explicit `effect`, else
    milk_type/coffee_type → swaps, else adds if any option has lines, else none. Seed swap category:
    `swap_category_id`, else the category whose slug is `milk`/`coffee_bean` for legacy swap types.
16. **Label grids** (bases, option per-size): column `*` = All sizes (lines with `size_label` null), one
    column per label; to wire: blank cells dropped, `*` → `size_label: null`. `label-model.ts`.
17. **Pricing resolution** (`pricing-availability-page.tsx:145-170, 184-195, 277-307`): In-store cell:
    price = branch ?? catalog, explicit when branch price set, from "catalog"; available = branch ?? true.
    Channel cell: price = channel ?? branch ?? catalog, explicit when channel price set, from "branch" if a
    branch price exists else "catalog"; available = channel ?? branch ?? true. Pristine draft: price text
    only when explicit; available = effective. Dirty = trimmed price text differs or availability differs.
    Write plan: price typed (→ piastres) or hidden → PUT {price|null, is_available false|null}; else a
    prior row at this scope → DELETE; else nothing. Placeholder = effective price in EGP, integer or 2-dp
    with trailing zeros trimmed.
18. **Branch availability toggles** (items page): MENU-ITEMS-022/023/051 rules.
19. **Paste rows**: delimiter tab if any line contains one else comma; default column mapping by
    position; validation as MENU-ITEMS-036; category matched by trimmed lower-case name.
20. **Export walk**: `page = floor(offset/500)+1`, `per_page 500`, stop on an empty page or when the
    total is reached; refuse above 50,000.

---

## 9. Missing i18n keys (not in `src/i18n/locales/en.json` nor `ar.json`)

| key | inline default (English) | used at | suggested Arabic (MSA) |
|---|---|---|---|
| `menu.addonsHint` | Which addons customers can pick for this item | `menu-item-dialog.tsx:528` | الإضافات التي يمكن للعميل اختيارها لهذا الصنف |
| `menu.addonsEmpty` | No addons selected — the full org catalog applies. | `menu-item-dialog.tsx:553` | لم تُختر أي إضافات — تُطبَّق كل إضافات المؤسسة. |
| `menu.noAddonsMatch` | No addons match | `menu-item-dialog.tsx:575` | لا توجد إضافات مطابقة |
| `menu.studio.steps.notePlaceholder` | For this drink — e.g. 40ml condensed milk | `section-steps.tsx:123` | لهذا المشروب — مثلًا 40 مل حليب مكثف |
| `menu.studio.steps.noteEn` | Note (English) | `section-steps.tsx:124` | ملاحظة (بالإنجليزية) |
| `menu.studio.steps.notePlaceholderAr` | ملاحظة لهذا المشروب (the default is already Arabic) | `section-steps.tsx:132` | ملاحظة لهذا المشروب |
| `menu.studio.steps.noteAr` | Note (Arabic) | `section-steps.tsx:134` | ملاحظة (بالعربية) |

Not keys, but untranslated English the port must also cover: zod default messages (§8 "Native
constraints"); the hard-coded "(EGP)" suffixes (§8); the paste textarea placeholder `Latte⇥45⏎Cappuccino⇥40`;
the size label placeholder "Large" in the item dialog; "0.000"/"0.00"/"1.5"/"—" placeholders.

en.json vs inline defaults that differ (the port uses en.json): `menu.subtitle` "Categories, items and
addons"; `menu.itemDesc` "Define the product, price and category."; `menu.grid.fullEditor` "Open full editor
(sizes, translations)"; `menu.grid.duplicated` "Duplicated {{name}}"; `menu.grid.bulkCreated` "Created
{{count}} items"; `menu.grid.bulkCreateFailed` "Created {{ok}}, {{failed}} failed"; `menu.grid.nameRequired`
"Name required"; `menu.grid.categoryUnknown` "Category must match an existing category"; `menu.addons`
"Addons"; `menu.costMissingFix` "Add ingredient costs to compute this"; `common.search` "Search";
`grid.pasteRows` "Paste rows"; `grid.ignore` "— ignore —"; `grid.pasteSummary` "{{valid}} of {{total}} rows
are valid"; `excel.generating` "Gathering data…"; `uploader.choose` "Choose Image"; `uploader.replace`
"Replace"; `uploader.remove` "Remove"; `uploader.notAnImage` "Selected file must be an image";
`uploader.tooLarge` "Image size exceeds 5MB limit"; `recipes.builder.margin` "margin".

---

## 10. Pieces shared with other areas

| Piece | Lives in | Used here by | Also used by |
|---|---|---|---|
| `CategoryDialog`, `AddonDialog`, `MenuItemDialog` | `src/features/menu/` | items page, studio, item dialog | onboarding (`src/features/onboarding/step-panel.tsx:27-30, 288, 334`) |
| `CreateIngredientDialog`, `RecipeBuilder`, `invalidateRecipes` | `src/features/recipes/` | item dialog, add-on recipe dialog | onboarding; inventory (catalog) |
| `GroupEditorDialog` | `src/features/menu/groups/` | groups page, add-on dialog, studio modifiers | – |
| `ONE_SIZE` | `src/features/menu/util.ts` | item dialog, studio grid | combos (`use-menu-options.ts:17`), orders (`order-detail-sheet.tsx:37`) |
| `setItemMeal`/`putMeal`, `useCombos`, `useCombo`, `mealDelta`, `slotsAdmitting`, `useMenuOptions` | `src/features/combos/` | studio "Make it a meal" | combos area |
| `formatRate` | `src/features/orgs/tax-rate.ts` | price-tax hint | org settings |
| `EditableCardGrid` (inline cells, paste dialog, pager) | `src/components/app/editable-cards.tsx` | items page tabs | other card grids |
| `ItemCostCell`, `AddonCostCell`, `FoodCostChip`, `CostMissingLink` | `src/components/app/cost-cells.tsx` | items/add-ons cards | reports/inventory |
| `ExportButton`, `exportToExcel`, `fetchAllPages`, `EXPORT_REQUEST` | `src/components/app/export-button.tsx`, `src/lib/excel.ts`, `src/lib/export-all.ts` | items export | every export |
| `ImageUploader`, `AssetImage`, `useAssetJob` | `src/components/app/image-uploader.tsx`, `asset-image.tsx` | item dialog, studio, tiles | org logo, branches, combos |
| `BilingualField`, `Combobox`, `SegmentedControl`, `EmptyState`/`ErrorState`, `ConfirmProvider`, `Page`/`PageHeader`, `StatusPill` | `src/components/app/` | everywhere | everywhere |
| `ModuleGate`, nav config | `src/components/app/module-gate.tsx`, `src/config/nav.ts` | area gate | shell |
| `useScope` (branch scope), `useOrgId`, `useAuthz`/`useCan` | `src/data/scope`, `src/hooks`, `src/data/authz` | items toggles, pricing | shell |
| `LabelGridEditor`, `label-model`, `grid-model` | `src/features/menu/recipe/` | bases, packaging, group editor, studio grid | – |
