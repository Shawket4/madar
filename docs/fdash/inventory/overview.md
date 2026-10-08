# Overview area: web parity inventory

Area package: `packages/dashboard_features/overview` (`dashboard_overview`).
Pages: `/` (home, "Dashboard" in the sidebar).

Web reference: `/Users/shawket/Desktop/Madar/MadarDashboard`, branch `main` @ `fc2faa42` (v1.4.18). Read-only.
Backend checked for capability gates and response semantics: `/Users/shawket/Desktop/Madar/MadarRust`
(`src/reports/handlers.rs`, `src/insights/handlers.rs`, `src/tills/handlers.rs`, `src/orgs/onboarding.rs`,
`src/orgs/handlers.rs`).

The home has **no mutations** (no POST/PATCH/DELETE, no toasts, no forms, no exports, no dialogs). Its
behaviours are reads, scope reactions, links, popovers, a dismissible card, and the loading, empty, error
and refusal states of eight cards. Every row below is still a driven test.

## How to read a row

`| id | behaviour | API call | gate | i18n keys | web source |`

- **API call**: method + path + operationId (= the `dashboard_api` method name, lowerCamelCase).
  `{scopeBranchId}` = the selected branch id, or the all-branches sentinel
  `00000000-0000-0000-0000-000000000000` when "All branches" is selected (`ALL_BRANCHES_ID`,
  `src/data/scope/use-scope.ts:19`). `from`/`to` = the scope's UTC ISO instants (section 3.3).
- **gate**: client gate (what the web hides) and/or server gate (what the backend refuses with a 403
  envelope). The web home has no `<Restricted>` and no client capability check except on the
  Keep-building card; everything else is fetched for everyone and a 403 lands in that card's error
  (or zero) state. Server gates use the capability key; the backend's legacy pair is in brackets.
- **web source**: `file:line` relative to `MadarDashboard/src/`. `dp` = `features/dashboard/dashboard-page.tsx`.
- Strings are cited as `key` "English". All keys exist in `en.json`/`ar.json` unless listed in section 4.

---

## Page `/` (home)

| Field | Value |
|---|---|
| Web path | `/` (file route `/_app/` inside the authenticated app shell) |
| Title | Page `<h1>` = `dashboard.greetingName` "Welcome back, {{name}}" (or `dashboard.greeting` "Welcome back"). Sidebar label `nav.dashboard` "Dashboard" in group `nav.overview` "Overview". No document-title change. |
| Web files read | `routes/_app/index.tsx`, `routes/_app/route.tsx`, `features/dashboard/dashboard-page.tsx`, `features/onboarding/keep-building-card.tsx`, `features/onboarding/config.ts`, `features/onboarding/gate.ts` (+ `gate.test.ts`), `features/tills/open-tills-card.tsx` (+ `open-tills-card.test.tsx`), `features/tills/api.ts`, `features/tills/till-badges.tsx`, `features/insights/margin-watch-card.tsx`, `features/insights/signals.ts`, `features/insights/util.ts` (`TINT`), `components/app/delivery-kpis.tsx`, `components/app/ledger-strip.tsx`, `components/app/stat-card.tsx`, `components/app/stat-value.tsx`, `components/app/chart-card.tsx`, `components/app/chart-tooltip.tsx`, `components/app/empty-state.tsx`, `components/app/progress-bar.tsx`, `components/app/section-header.tsx`, `components/app/status-pill.tsx`, `components/app/page.tsx`, `components/app/module-gate.tsx`, `components/layout/scope-bar.tsx`, `components/layout/app-sidebar.tsx` (home link), `config/nav.ts`, `data/scope/use-scope.ts`, `data/scope/presets.ts`, `data/scope/use-timezone.ts`, `data/realtime/use-branch-realtime.ts`, `data/api/query.ts`, `data/api/client.ts`, `data/authz/use-authz.ts`, `hooks/use-org-modules.ts`, `hooks/use-org-id.ts`, `hooks/use-mobile.ts`, `lib/format.ts`, `lib/route-prefetch.ts`, `data/config/constants.ts`, `styles/globals.css` (payment and chart tokens), `routes/_app/reports/operations/profitability.tsx`, `routes/_app/tills.tsx`, `routes/onboarding.tsx`, generated `data/api/generated/api.ts` and models. |
| Capabilities gating the page | None. Route needs a signed-in session only (`requireAuth`, `routes/_app/route.tsx:37`). Nav leaf `{ module: "pos", to: "/" }` has no `caps` (`config/nav.ts:87`). No `<Restricted>`. Card-level: Keep-building card needs `Cap.orgSettingsEdit` (`org.settings.edit`) client-side. Server: every sales/insights read needs `orders.read` [orders:read]; open tills need `till.read` [tills:read] + branch access; onboarding needs `org.settings.read` [orgs:read] + same org; modules need same org only. |
| Module | `pos` in the nav. `ModuleGate` deliberately does NOT tag `/` (`config/nav.ts:279-280`); instead `routes/_app/index.tsx` redirects a Dawam-only org to `/staff/team` and renders nothing until modules are known. |
| Realtime | Indirect. The shell's single branch stream (`useBranchRealtime(search.branchId)`, `routes/_app/route.tsx:52`) runs only while a branch is selected; event `till.*` invalidates every query key starting `/tills` or `/reports` (open tills, branch sales, timeseries, comparison, delivery sales refetch); `resync` invalidates everything. `/insights` (margin watch) and `/orgs` (onboarding) are not invalidated by any event except `resync`. `delivery.*` invalidates only `/delivery-orders` (not the home's delivery KPIs). |
| Generated API hooks called | `useBranchSales` (branchSales), `useBranchSalesTimeseries` (branchSalesTimeseries), `useOrgBranchComparison` (orgBranchComparison), `useBranchDeliverySales` (branchDeliverySales), `useMarginWatch` (marginWatch), `useListOpenTills` via `useOpenTills` (listOpenTills), `useGetOnboarding` (getOnboarding; also the shell's first-run gate), `useGetOrgModules` via `useOrgModulesState` (getOrgModules). Shell, not this page: `useListBranches`, `useGetOrg`, `useGetMyAuthz`. |
| Query keys invalidated after mutations | None: the page has no mutations. Realtime invalidations above. Query defaults: `staleTime` 30 s, `gcTime` 5 min, no refetch on window focus, retry: never on 401/403/404/422, a 429 up to 3 times (2 s, 4 s, 8 s), anything else once (`data/api/query.ts:9-49`). |

### Endpoints (exact params the page sends)

| # | Method + path | operationId | Query params | Enabled when | Server gate |
|---|---|---|---|---|---|
| E1 | GET `/reports/branches/{branchId}/sales` | `branchSales` | `from`, `to` (never `limit`, `exclude_items`) | a branch is selected | `orders.read` + branch access |
| E2 | GET `/reports/branches/{scopeBranchId}/sales/timeseries` | `branchSalesTimeseries` | `from`, `to`, `granularity` = `hourly` (preset today or yesterday) else `daily` | an org is in scope | `orders.read` + branch access |
| E3 | GET `/reports/orgs/{orgId}/comparison` | `orgBranchComparison` | `from`, `to` | an org is in scope | `orders.read` + same org (NOT narrowed to the caller's branches) |
| E4 | GET `/reports/branches/{scopeBranchId}/delivery-sales` | `branchDeliverySales` | `from`, `to` | an org is in scope | `orders.read` + branch access |
| E5 | GET `/insights/branches/{scopeBranchId}/margin-watch` | `marginWatch` | `from`, `to` (never `cost_basis`; server uses snapshot) | an org is in scope | `orders.read` + branch access |
| E6 | GET `/tills/branches/{branchId}/open` | `listOpenTills` | none | a branch is selected | `till.read` + branch access |
| E7 | GET `/orgs/{orgId}/onboarding` | `getOnboarding` | none | org in scope AND `can(org.settings.edit)` AND not dismissed this session | `org.settings.read` + same org |
| E8 | GET `/orgs/{orgId}/modules` | `getOrgModules` | none (staleTime 60 s) | org in scope (shell + home redirect) | same org |

Backend semantics the mock server must reproduce: E2 returns only periods that have orders (no
zero-filled gaps), each `period` a naive wall-clock string `YYYY-MM-DDTHH:MM:SS` in the scope's zone;
with the sentinel id it rolls up the caller's branches (a branch manager: only theirs). E3 returns every
non-deleted branch of the org (zero-sales branches included), ordered by `total_revenue` desc, for anyone
in the org. E4 always returns the four channels `in_mall`, `outside`, `umbrella`, `pickup` (zero-filled),
revenue/orders over delivered orders only. E5 `top` and `bottom` hold at most 3 rows each (only rows with a
known margin). E6 is newest first. E7 has 10 steps (`org_profile`, `branch`, `payment_methods`,
`categories`, `menu_items`, `ingredients`, `recipes`, `addons`, `team`, `first_order`). Money fields
are integer piastres.

### Layout, top to bottom

1. Page header (greeting + scope subtitle).
2. Keep-building card (conditional).
3. KPI strip (LedgerStrip, dense) and directly under it the Open tills card (branch scope only).
4. Grid: Revenue trend (2/3 width at >= 1024 px) + Payment mix (1/3).
5. Branch performance.
6. Margin watch.
7. Delivery section (section header + delivery KPI strip + channel cards).

### 2.1 Routing, shell, scope

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OVW-HOME-001 | Opening `/` while signed out redirects to the sign-in screen (with the return address); signed in, the home renders inside the app shell (sidebar, header with scope controls, footer). | none | signed in | none | `routes/_app/route.tsx:35-39` |
| OVW-HOME-002 | While the org's modules are not yet known, the home body renders NOTHING (blank content area, shell visible). This includes a failed modules read: `/` has no module tag, so the ModuleGate error state ("Couldn't check…" + Retry) is NOT shown on the home; the body stays blank. | GET `/orgs/{orgId}/modules` getOrgModules | same org | none | `routes/_app/index.tsx:7-9`; `components/app/module-gate.tsx:21-22`; `config/nav.ts:279-280`; `hooks/use-org-modules.ts:36-42` |
| OVW-HOME-003 | Dawam-only org (modules contain `dawam` and not `pos`): `/` immediately replace-redirects to `/staff/team` (no history entry for `/`). | GET `/orgs/{orgId}/modules` getOrgModules | module | none | `routes/_app/index.tsx:10-12` |
| OVW-HOME-004 | Org with `pos` (or with neither module) renders the dashboard home. | none | module `pos` | none | `routes/_app/index.tsx:13` |
| OVW-HOME-005 | Platform admin with no org picked: modules count as all, the home renders; every org-keyed read is disabled, so: KPI cards show 0 (not loading), Revenue trend / Payment mix / Branch performance / Margin watch show their empty sentences, Delivery shows four zero cards and no channel cards, no Open tills card, no Keep-building card, subtitle "All branches". | none | platform | `dashboard.noSalesPeriod`, `insights.watch.empty` | `hooks/use-org-modules.ts:39`; `dp:72,79-89` |
| OVW-HOME-006 | First-run redirect (shell-owned, pre-empts the home): role `org_admin`, org has `pos`, onboarding `completed === false`, not skipped this session (`sessionStorage["madar.onboarding.skip"] === "1"` means skipped) → navigate to `/onboarding`. Never for a Dawam-only org, never before modules are known, never for other roles (a platform admin is not redirected). | GET `/orgs/{orgId}/onboarding` getOnboarding | role org_admin; module pos | none | `routes/_app/route.tsx:58-79`; `features/onboarding/gate.ts:8-16`; test `features/onboarding/gate.test.ts:13-21` |
| OVW-HOME-007 | Bare entry with no `branchId` and no `preset` in the URL: the URL is rewritten in place (replace) with the last-used branch and preset; a persisted `custom` is replaced by the default `30d`. Runs once per shell mount. | none | none | none | `routes/_app/route.tsx:83-100` |
| OVW-HOME-008 | Sidebar: group "Overview" with one leaf "Dashboard" (icon layout-dashboard), shown to every signed-in person of a POS org (hidden for a Dawam-only org), active only when the path is exactly `/`. The sidebar logo also links to `/`. Both links keep `branchId`, `preset`, `from`, `to`. Command palette lists it with the same gate (shell). | none | module `pos` | `nav.overview` "Overview", `nav.dashboard` "Dashboard" | `config/nav.ts:84-88`; `components/layout/app-sidebar.tsx:45,200,208` |
| OVW-HOME-009 | Hovering/focusing the sidebar "Dashboard" entry warms the home's first reads with identical params (branch sales when a branch is picked; timeseries + comparison when an org is in scope). Optional in Flutter (no visible behaviour), listed for completeness. | E1, E2, E3 | none | none | `lib/route-prefetch.ts:63-76` |
| OVW-HOME-010 | Deep link `?branchId=<uuid>`: the home opens scoped to that branch (branch KPIs and payment mix from E1, Open tills card shown, realtime stream connected). The selection is mirrored to the app store (persisted, sent as `X-Branch-Id`). | E1, E6 | branch access (server) | none | `routes/_app/route.tsx:28-33,104-108`; `data/scope/use-scope.ts:53,79` |
| OVW-HOME-011 | Deep link `?preset=` one of `today`, `yesterday`, `7d`, `30d`, `mtd`: from/to resolve to day boundaries in the active timezone (section 3.3); no preset → `30d`. | E1-E5 | none | none | `data/scope/presets.ts:9,21-45`; `data/scope/use-scope.ts:52` |
| OVW-HOME-012 | Deep link `?preset=custom&from=<iso>&to=<iso>`: the exact instants are sent. `custom` missing either date falls back to `30d` and the subtitle says "Last 30 days". | E1-E5 | none | `scope.preset.30d` | `data/scope/use-scope.ts:57-72`; test `data/scope/use-scope.test.ts:29-50` |
| OVW-HOME-013 | Changing the branch in the shell's branch picker (only owners and platform admins have one): every home read refetches for the new scope; picking "All branches" hides the Open tills card and switches KPIs and payment mix to the comparison roll-up; the realtime stream reconnects for the new branch (or closes for All). | E1-E6 | picker: `authz.platform` or `authz.owner` | `scope.allBranches` | `components/layout/scope-bar.tsx:40-41,90-101`; `dp:79-126` |
| OVW-HOME-014 | Changing the period preset in the shell: every period read refetches with new from/to; the trend switches granularity (hourly for Today and Yesterday, daily for 7d, 30d, MTD and Custom). | E1-E5 | none | `scope.preset.*` | `dp:75`; `data/scope/use-scope.ts:88-91` |
| OVW-HOME-015 | Applying a custom range in the shell: reads refetch with the picked instants, trend is daily, subtitle period reads "Custom". | E1-E5 | none | `scope.preset.custom` "Custom" | `data/scope/use-scope.ts:92-95`; `dp:151` |
| OVW-HOME-016 | Branch manager (not owner, not platform): no branch picker, URL has no `branchId`, so the home is in "All branches" scope: no Open tills card; E2, E4, E5 roll up only the manager's branches (server), but E3 returns every org branch, so the KPI strip, payment mix and branch performance show ORG-WIDE figures while the trend shows only the manager's branches (web/backend quirk; the mock must reproduce the endpoint semantics, not "fix" them). | E2-E5 | server scope | `scope.allBranches` | `components/layout/scope-bar.tsx:40-41`; MadarRust `reports/handlers.rs:1588-1660,2900-2933` |
| OVW-HOME-017 | A stale `branchId` (not an active branch of this org) self-heals to "All branches" (owner/platform; shell-owned). | none | owner/platform | none | `components/layout/scope-bar.tsx:51-60` |

### 2.2 Page header

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OVW-HOME-018 | Title is the greeting with the signed-in person's name; without a name, "Welcome back". 28 px bold, truncated on one line. | none | none | `dashboard.greetingName` "Welcome back, {{name}}", `dashboard.greeting` "Welcome back" | `dp:143-145,177`; `components/app/page.tsx:199-204` |
| OVW-HOME-019 | Subtitle segment 1 (store icon): "All branches" when none selected; the selected branch's name looked up in the comparison rows (E3); "Branch" while E3 is loading/failed or the branch is not in it. | E3 | none | `scope.allBranches` "All branches", `scope.branch` "Branch" | `dp:148-150,180-182` |
| OVW-HOME-020 | Subtitle segment 2 (calendar icon): the preset label: Today, Yesterday, Last 7 days, Last 30 days, Month to date, Custom. A custom range shows only the word, not the dates. | none | none | `scope.preset.today` "Today", `scope.preset.yesterday` "Yesterday", `scope.preset.7d` "Last 7 days", `scope.preset.30d` "Last 30 days", `scope.preset.mtd` "Month to date", `scope.preset.custom` "Custom" | `dp:54-61,151,184-186` |
| OVW-HOME-021 | Subtitle segment 3: "Cairo time" when the active zone is `Africa/Cairo`; otherwise "{{city}} time" where city = last IANA segment with `_` → space (e.g. `America/New_York` → "New York time"; Arabic "بتوقيت New York", city stays as written). Active zone = branch zone → org zone → first zone of the person's branches → Cairo. | none | none | `common.cairoTime` "Cairo time", `common.timezoneLabel` "{{city}} time" | `dp:152-158,188`; `data/scope/use-timezone.ts:65-71` |
| OVW-HOME-022 | Segments separated by a muted "·", wrapping onto further lines on narrow widths. No header actions, no back button, no tabs. | none | none | none | `dp:176-191` |

### 2.3 Keep-building card (onboarding nudge)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OVW-HOME-023 | Shown between the header and the KPIs only when: an org is in scope, the person holds `org.settings.edit`, it was not dismissed this browser session, onboarding loaded, it has steps, and not every step is done. | GET `/orgs/{orgId}/onboarding` getOnboarding | client `org.settings.edit`; server `org.settings.read` | none | `features/onboarding/keep-building-card.tsx:37-43`; `dp:192` |
| OVW-HOME-024 | Title counts finished steps over all steps (backend sends 10), e.g. "Your café is open · 6/10 set up"; body line under it; sparkles glyph tile on the start side. | E7 | as 023 | `onboarding.nudge.title` "Your café is open · {{done}}/{{total}} set up", `onboarding.nudge.body` "Keep building — add recipes, your team and more to unlock cost insights." | `keep-building-card.tsx:39-41,55-66` |
| OVW-HOME-025 | "Keep building →" button opens the full-screen set-up wizard `/onboarding` (outside the shell; scope params not carried). Arrow points the reading direction (mirrored in Arabic). | none | as 023 | `onboarding.nudge.cta` "Keep building" | `keep-building-card.tsx:67-69` |
| OVW-HOME-026 | Dismiss (X, top-end corner, icon-only, accessible name "Dismiss"): hides the card at once and for the rest of the browser session (`sessionStorage["madar.onboarding.nudge.dismissed"] = "1"`); the onboarding read stops; a new session shows it again. Storage failure is ignored (card still hides for this view). | none | as 023 | `common.dismiss` "Dismiss" (MISSING, section 4) | `keep-building-card.tsx:24-30,45-52,70-77`; `features/onboarding/config.ts:91` |
| OVW-HOME-027 | Hidden when every step is done (done >= total) or the step list is empty. | E7 | as 023 | none | `keep-building-card.tsx:43` |
| OVW-HOME-028 | No skeleton while loading and no error state: hidden while loading and when the read fails (including a 403 for someone with edit but not read). | E7 | as 023 | none | `keep-building-card.tsx:43` |
| OVW-HOME-029 | Refusal: a person without `org.settings.edit` (branch manager, limited) never sees it and no onboarding request is made. | none | client `org.settings.edit` | none | `keep-building-card.tsx:37-38` |
| OVW-HOME-030 | A platform admin scoped to a shop sees it (they hold every capability) and can dismiss it; they are never redirected into the wizard (row 006). | E7 | platform | as 024 | `keep-building-card.tsx:32-38` |
| OVW-HOME-031 | Responsive: one row at every width (glyph, text block that truncates/wraps, button); the X stays pinned to the top-end corner. | none | none | none | `keep-building-card.tsx:55-78` |

### 2.4 KPI strip

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OVW-HOME-032 | Branch selected: Revenue = `total_revenue` (net of refunds), Orders = `total_orders`, Voided = `voided_orders`, Tips = `total_tips` (0 when absent), all from branch sales. | GET `/reports/branches/{branchId}/sales` branchSales | server `orders.read` | see 036 | `dp:79,94-103` |
| OVW-HOME-033 | All branches: the four figures are the SUMS over every comparison row (`total_revenue`, `total_orders`, `voided_orders`, `total_tips`). | GET `/reports/orgs/{orgId}/comparison` orgBranchComparison | server `orders.read` | see 036 | `dp:87,104-112` |
| OVW-HOME-034 | Avg ticket = round(revenue / orders) in piastres; 0 when there are no orders (computed in the browser, NOT the server's `avg_order_value`). | E1 or E3 | none | `dashboard.avgTicket` | `dp:115` |
| OVW-HOME-035 | Tips card appears only when tips are non-zero (5 cards); otherwise 4 cards. Tips are never part of Revenue or of a payment-method bucket. | E1 or E3 | none | `dashboard.tips` "Tips" | `dp:160-172` |
| OVW-HOME-036 | Card order, glyph and label: Revenue (coins, money), Orders (receipt, count), Avg ticket (trending-up, money), Voided (ban, count), Tips (hand-coins, money). Glyphs are muted. | none | none | `dashboard.revenue` "Revenue", `nav.orders` "Orders", `dashboard.avgTicket` "Avg ticket", `dashboard.voided` "Voided", `dashboard.tips` "Tips" | `dp:164-172`; `components/app/stat-card.tsx:124-128` |
| OVW-HOME-037 | Voided card glyph turns warning-tinted when voided > 0, muted when 0. | none | none | none | `dp:168`; `stat-card.tsx:17-25` |
| OVW-HOME-038 | Loading: each card is a skeleton (label bar, glyph square, value bar) while the source read loads (branch sales in branch scope, comparison in all scope). Cards in a row share one height. | E1 or E3 | none | none | `dp:116`; `stat-card.tsx:68-82` |
| OVW-HOME-039 | Value fits its slot: money tries "EGP 1,234.56" → "EGP 1,235" → "EGP 1.2K"; counts try "12,345" → "12.3K"; each at font sizes 20, 18, 16, 15, 14 px (dense) before stepping down a representation; refits on resize. | none | none | none | `components/app/stat-value.tsx:16-22,85-118`; `stat-card.tsx:29-30` |
| OVW-HOME-040 | When a value had to be shortened it becomes a dotted-underline button; tapping it opens a popover with the card label (small, uppercase, muted) and the exact figure. Unshortened values are plain text. | none | none | label keys of 036 | `stat-value.tsx:120-155` |
| OVW-HOME-041 | Count-up: on first reveal each figure animates from 0 to its value over 1100 ms (ease-out-quart), counts tick through whole numbers; later value changes jump; reduced motion shows the value at once. | none | none | none | `stat-value.tsx:59-82,122-127`; `lib/motion.ts:38` |
| OVW-HOME-042 | Error: the strip has NO error state. All-branches scope with E3 failing → every card shows 0. Branch scope with E1 failing → the cards fall back to the org-wide E3 sums (web quirk, reproduce). | E1, E3 | none | none | `dp:94-113` |
| OVW-HOME-043 | Refusal: a persona without `orders.read` gets 403 on E1/E3 → all cards 0 (no refusal words on this strip). | E1, E3 | server `orders.read` | none | `dp:94-113`; MadarRust `reports/handlers.rs` `branch_sales`, `org_branch_comparison` |
| OVW-HOME-044 | Responsive: 2 columns on a phone; from 640 px 2 columns (4 cards) or 3 columns (5 cards); from 1024 px 4 or 5 columns in one row. Gap 12 px, 16 px from 640 px. | none | none | none | `components/app/ledger-strip.tsx:32-38,55-63` |

### 2.5 Open tills card

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OVW-HOME-045 | Rendered directly under the KPI strip ONLY when a branch is selected; absent on "All branches". | GET `/tills/branches/{branchId}/open` listOpenTills | server `till.read` + branch access | none | `features/tills/open-tills-card.tsx:13-17`; `dp:195` |
| OVW-HOME-046 | Loading: one skeleton block 96 px tall. | E6 | none | none | `open-tills-card.tsx:16` |
| OVW-HOME-047 | Header row: wallet glyph, "Open tills", and the count of open tills. | E6 | none | `dashboard.openTills` "Open tills" | `open-tills-card.tsx:24-29` |
| OVW-HOME-048 | "View all" link (top end of the card) opens `/tills`. It passes no search params, so the scope is DROPPED: `/tills` opens with "All branches" + "Last 30 days" and the stored branch resets (web quirk; see notes). | none | none | `common.viewAll` "View all" | `open-tills-card.tsx:30-32`; router-core `applyNext` (`!dest.search → {}`) |
| OVW-HOME-049 | Empty: "No open till" and count 0. | E6 | none | `dashboard.noOpenTill` "No open till" | `open-tills-card.tsx:34-35`; test `open-tills-card.test.tsx:16-19` |
| OVW-HOME-050 | One row per open till in server order (newest first): teller name (bold) and the device code (monospace) when present; rows divided by hairlines. | E6 | none | none | `open-tills-card.tsx:37-43`; test `open-tills-card.test.tsx:11-15` |
| OVW-HOME-051 | Verification pill: `unverified` → warning pill "Not verified" (shield-question glyph); `lan` → neutral pill "Verified on LAN" (wifi glyph); `server` and `legacy` → no pill. | E6 | none | `tills.verification.unverified` "Not verified", `tills.verification.lan` "Verified on LAN" | `features/tills/till-badges.tsx:23-38` |
| OVW-HOME-052 | Flag pill: a till opened while another was open shows a warning pill "Opened while another till was open". On the home there is NO "See the other till" link (no handler passed). | E6 | none | `tills.flagged` "Opened while another till was open" | `till-badges.tsx:40-62`; test `open-tills-card.test.tsx:12-14` |
| OVW-HOME-053 | Time open since `opened_at`: "0m", "42m", "1h 05m", "1d 03h" (Arabic "42 د", "1 س 05 د", LTR-isolated). Computed when the card renders; it does not tick on a timer (changes on refetch). | E6 | none | none | `open-tills-card.tsx:47`; `lib/format.ts:201-225` |
| OVW-HOME-054 | Error, including a 403 for a persona without `till.read`: shown exactly like the empty state ("No open till", count 0); no error words, no retry. | E6 | server `till.read` | `dashboard.noOpenTill` | `open-tills-card.tsx:16` (`q.data ?? []`) |
| OVW-HOME-055 | Live: a `till.*` realtime event (till opened, closed, flagged…) refetches the list; `resync` too. | E6 | none | none | `data/realtime/use-branch-realtime.ts:60,51` |
| OVW-HOME-056 | Responsive: each row wraps, name/device first, pills and time after. | none | none | none | `open-tills-card.tsx:39-48` |

### 2.6 Revenue trend card

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OVW-HOME-057 | Card "Revenue trend"; 2/3 of the row at >= 1024 px, full width below. Reads the timeseries for the scope (the all-branches sentinel rolls every branch together). | GET `/reports/branches/{scopeBranchId}/sales/timeseries` branchSalesTimeseries | server `orders.read` | `dashboard.revenueTrend` "Revenue trend" | `dp:82-86,202-206` |
| OVW-HOME-058 | Loading: a 256 px skeleton. | E2 | none | none | `dp:207-208` |
| OVW-HOME-059 | Error: "Couldn't load the revenue trend" with a danger glyph and a Retry button that refetches E2. A 403 (no `orders.read`) lands here. | E2 | server `orders.read` | `dashboard.trendFailed` "Couldn't load the revenue trend", `common.retry` "Retry" | `dp:209-210`; `components/app/empty-state.tsx:54-82` |
| OVW-HOME-060 | Empty (no periods returned): "Sales for this period will appear here." | E2 | none | `dashboard.noSalesPeriod` "Sales for this period will appear here." | `dp:211-212` |
| OVW-HOME-061 | Area chart of `revenue` per period: brand colour (chart-1) 2 px line, 12 % fill, monotone curve, dashed horizontal grid only, 256 px tall; draws in over 1100 ms unless reduced motion. | E2 | none | none | `dp:214-257` |
| OVW-HOME-062 | X axis: period labels via fmtPeriod, hourly "8 Oct, 02:00 PM" / "8 أكتوبر، 02:00 م", daily "8 Oct" / "8 أكتوبر"; at least 24 px between ticks (labels thin out). | E2 | none | none | `dp:221-228`; `lib/format.ts:278-287` |
| OVW-HOME-063 | Y axis: compact money ticks ("EGP 1.2K"), 64 px wide; on the LEFT in English and on the RIGHT in Arabic; the plot itself stays left-to-right in both languages (oldest period at the left). | E2 | none | none | `dp:229-236`; `components/app/chart-card.tsx:39-40` |
| OVW-HOME-064 | Hover (tap on touch) a point: tooltip with the period (fmtPeriod) as heading and a row: colour dot, "Revenue", full money. | E2 | none | `dashboard.revenue` "Revenue" | `dp:237-244`; `components/app/chart-tooltip.tsx:19-46` |
| OVW-HOME-065 | Live: `till.*` and `resync` events refetch the trend (only while a branch is selected, since the stream needs one). | E2 | none | none | `use-branch-realtime.ts:51,60` |

### 2.7 Payment mix card

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OVW-HOME-066 | Card "Payment mix", 1/3 of the row at >= 1024 px. Data: branch scope → branch sales `revenue_by_method`; all scope → the per-method SUM of every comparison row's `revenue_by_method`. Methods with value <= 0 dropped; sorted by value, largest first. | E1 or E3 | server `orders.read` | `dashboard.payments` "Payment mix" | `dp:118-128,265-266` |
| OVW-HOME-067 | Loading: 256 px skeleton while the KPI source read loads. | E1 or E3 | none | none | `dp:267-268` |
| OVW-HOME-068 | Error: "Couldn't load the payment mix" + Retry; Retry refetches E1 in branch scope, E3 in all scope. | E1 or E3 | server `orders.read` | `dashboard.paymentsFailed` "Couldn't load the payment mix", `common.retry` | `dp:269-274` |
| OVW-HOME-069 | Empty (no method with money): "Sales for this period will appear here." | E1 or E3 | none | `dashboard.noSalesPeriod` | `dp:275-276` |
| OVW-HOME-070 | Donut (160 px area, inner radius 48, outer 72, 2° gaps, no stroke), one slice per method. Colour: cash → success, card → info, digital_wallet → violet, mixed → warning, talabat_online and talabat_cash → two Talabat oranges (theme tokens, dark variants); any other method → chart palette colour by its position. Animates unless reduced motion. | E1 or E3 | none | none | `dp:279-305`; `data/config/constants.ts:29-36`; `styles/globals.css:72-85,137-139` |
| OVW-HOME-071 | Legend under the donut, one line per method: colour dot, method name (translated; a custom method code shows the raw code), money (full), share of the total (one decimal, e.g. "62.4%"). | E1 or E3 | none | `payments.cash` "Cash", `payments.card` "Card", `payments.digital_wallet` "Digital Wallet", `payments.mixed` "Mixed", `payments.talabat_online` "Talabat Online", `payments.talabat_cash` "Talabat Cash" (fallback = raw code) | `dp:306-321` |
| OVW-HOME-072 | Hover (tap) a slice: tooltip row with the slice colour, the raw method key as the series name, and "<translated method>: <money>". | E1 or E3 | none | `payments.<method>` | `dp:296-302`; `chart-tooltip.tsx:35-43` |

### 2.8 Branch performance card

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OVW-HOME-073 | Card "Branch performance": the comparison rows sorted by revenue (largest first), at most 6. Shown in BOTH scopes (with a branch selected it still ranks every org branch). | GET `/reports/orgs/{orgId}/comparison` orgBranchComparison | server `orders.read` + same org | `dashboard.branchPerformance` "Branch performance" | `dp:135-141,329` |
| OVW-HOME-074 | Loading: 160 px skeleton. | E3 | none | none | `dp:330-331` |
| OVW-HOME-075 | Error: "Couldn't load branch performance" + Retry (refetch E3). | E3 | server `orders.read` | `dashboard.branchesFailed` "Couldn't load branch performance", `common.retry` | `dp:332-333` |
| OVW-HOME-076 | Empty only when the org has no branches: "Sales for this period will appear here." Branches with no sales are still listed (0 orders, minimum bar). | E3 | none | `dashboard.noSalesPeriod` | `dp:334-335` |
| OVW-HOME-077 | Row: rank (1-6, monospace), branch name (truncated), "<count> orders" (count with thousands grouping), a bar = branch revenue / top revenue (never under 2 %, accessible name "Revenue share for <name>"), and the revenue at the end. Rows are not tappable. | E3 | none | `dashboard.ordersWord` "orders", `dashboard.branchRevenueBar` "Revenue share for {{name}}" | `dp:343-370` |
| OVW-HOME-078 | Revenue figure: full money at >= 768 px; under 768 px the compact form ("EGP 1.2K") as a dotted-underline button that opens a popover with the full figure. | E3 | none | none | `dp:367-369`; `components/app/ledger-strip.tsx:88-115`; `hooks/use-mobile.ts:3` |
| OVW-HOME-079 | Rows stagger in (40 ms apart) on first render unless reduced motion. | none | none | none | `dp:337-347` |

### 2.9 Margin watch card

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OVW-HOME-080 | Card "Margin watch" for the scope (sentinel = org-wide over the caller's branches). | GET `/insights/branches/{scopeBranchId}/margin-watch` marginWatch | server `orders.read` + branch access | `insights.watch.title` "Margin watch" | `features/insights/margin-watch-card.tsx:23-44`; `dp:377` |
| OVW-HOME-081 | Loading: 160 px skeleton. | E5 | none | none | `margin-watch-card.tsx:45-46` |
| OVW-HOME-082 | Error: "Couldn't load margin watch" + Retry; while the retry is in flight the button shows a spinner and is disabled. A 403 (no `orders.read`) lands here. | E5 | server `orders.read` | `insights.watch.loadFailed` "Couldn't load margin watch", `common.retry` | `margin-watch-card.tsx:47-53`; `components/ui/button.tsx:67-74` |
| OVW-HOME-083 | Empty: no data, or (no top rows AND no bottom rows AND revenue 0): "Margins appear here once items sell in this period". | E5 | none | `insights.watch.empty` "Margins appear here once items sell in this period" | `margin-watch-card.tsx:41,54-55` |
| OVW-HOME-084 | Headline: gross margin `totals.margin_known` as full money (large, monospace), then the margin percent `margin_pct / 100` as a percent (one decimal) when not null. | E5 | none | none | `margin-watch-card.tsx:59-65` |
| OVW-HOME-085 | Change vs the previous equal period, shown only when `prev_margin_known > 0`: delta = (margin_known − prev) / prev; >= 0 → green up-right arrow + percent; < 0 → red down-right arrow + absolute percent; screen readers also hear "vs previous period". | E5 | none | `insights.watch.vsPrev` "vs previous period" | `margin-watch-card.tsx:36-39,66-81`; `features/insights/util.ts:12-16` |
| OVW-HOME-086 | Tallies line (only when either is > 0): "{{count}} open signals" when `open_signals > 0`; "{{count}} items missing cost" when `rows_cost_unknown > 0`. Plural forms (EN one/other; AR all six). | E5 | none | `insights.watch.openSignals`, `insights.watch.costUnknown` | `margin-watch-card.tsx:84-103` |
| OVW-HOME-087 | Two lists: "Top earners" (green dots) and "Needs attention" (amber dots); side by side from 640 px, stacked below. | E5 | none | `insights.watch.top` "Top earners", `insights.watch.bottom` "Needs attention" | `margin-watch-card.tsx:105-116,144-145` |
| OVW-HOME-088 | A list with no rows says "No results found". | E5 | none | `common.noResults` "No results found" | `margin-watch-card.tsx:146-147` |
| OVW-HOME-089 | Row: item name, plus " · <size label>" unless the size label is `one_size`; the row's margin as full money at the end ("—" when null). Name truncates. | E5 | none | none | `margin-watch-card.tsx:150-168` |
| OVW-HOME-090 | Row second line: the FIRST flag's plain-language reason when the row has flags; otherwise, when `quantity_sold > 0`, "{{count}} sold" plus " · <margin %>" when `margin_pct` is not null; otherwise nothing. | E5 | none | `insights.watch.sold` | `margin-watch-card.tsx:169-176` |
| OVW-HOME-091 | Flag reasons by kind (money params are piastres, percents 0-100 shown with up to one decimal): below_cost "Sells below cost — margin {{margin}}"; below_target "Margin {{marginPct}}% is under the {{targetPct}}% target" + when `adaptive_bar > 0` " (bar raised {{pts}} pts — these are often dismissed)"; cost_spike "{{ingredient}} cost moved {{pct}}% this period"; price_candidate with `caution: true` → the caution sentence with `|last_margin_per_day_delta|`; with a numeric `elasticity` → the learned sentence (forecast floored at 0); else "Top seller under target — suggested price {{price}}"; removal_candidate "No sales this period"; recipe_incomplete "Recipe incomplete — cost unknown"; unknown kind → the raw kind. | E5 | none | `insights.signals.reason.below_cost`, `.below_target`, `.adaptive_note`, `.cost_spike`, `.price_candidate_caution`, `.price_candidate_learned`, `.price_candidate`, `.removal_candidate`, `.recipe_incomplete` | `features/insights/signals.ts:46-112` |
| OVW-HOME-092 | Footer link "Menu profitability →" (under a hairline) opens `/reports/operations/profitability`, which redirects to `/reports/operations`; scope params are DROPPED (no search passed). Arrow mirrored in Arabic. | none | none (target page: `orders.read` nav gate) | `insights.watch.viewAll` "Menu profitability" | `margin-watch-card.tsx:118-126`; `routes/_app/reports/operations/profitability.tsx:4-8`; `config/nav.ts:136` |
| OVW-HOME-093 | Not refreshed by any realtime event except `resync` (key starts `/insights`). | E5 | none | none | `use-branch-realtime.ts:50-64` |

### 2.10 Delivery section

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OVW-HOME-094 | Section header "Delivery" with the line "By channel" under it (plain section, not a card). | none | none | `delivery.kpisTitle` "Delivery", `delivery.byChannel` "By channel" | `dp:380-381`; `components/app/section-header.tsx:11-47` |
| OVW-HOME-095 | Totals strip (4 cards, regular size): Delivery revenue (coins, money, `total_revenue`), Delivered orders (receipt, count, `total_orders`), Avg ticket (trending-up, money, server `avg_order_value`), Delivery fees (truck, money, `total_delivery_fees`). Same fit, popover and count-up behaviour as rows 039-041 at sizes 24, 22, 20, 18, 16 px. | GET `/reports/branches/{scopeBranchId}/delivery-sales` branchDeliverySales | server `orders.read` | `delivery.revenue` "Delivery revenue", `delivery.deliveredOrders` "Delivered orders", `dashboard.avgTicket` "Avg ticket", `delivery.fees` "Delivery fees" | `components/app/delivery-kpis.tsx:35-40,47`; `dp:89,385` |
| OVW-HOME-096 | Loading: the four cards as skeletons plus two skeleton channel cards. | E4 | none | none | `delivery-kpis.tsx:49-56` |
| OVW-HOME-097 | Error: "Couldn't load delivery sales" + Retry replaces the whole section body (strip and channel cards); bordered error card. A 403 (no `orders.read`) lands here. | E4 | server `orders.read` | `dashboard.deliveryFailed` "Couldn't load delivery sales", `common.retry` | `dp:382-383` |
| OVW-HOME-098 | One card per channel the server returns (backend always sends `in_mall`, `outside`, `umbrella`, `pickup`, zero-filled): header with glyph + label + share of delivery revenue (one decimal; "0%" when total is 0). Labels: in_mall "In-mall delivery" (store glyph), outside "Outside delivery" (bike glyph); ANY other channel (umbrella, pickup) shows its RAW code with a store glyph, in both languages (web quirk: `delivery.umbrella`/`delivery.pickup` exist in en/ar but are not used here). | E4 | none | `delivery.inMall` "In-mall delivery", `delivery.outside` "Outside delivery" | `delivery-kpis.tsx:13-16,57-69` |
| OVW-HOME-099 | Channel revenue (large, monospace): full money at >= 768 px; compact + popover with the full figure under 768 px. | E4 | none | none | `delivery-kpis.tsx:71-73` |
| OVW-HOME-100 | Channel bar: revenue / the largest channel revenue, never under 2 % of it; accessible name "Revenue share". | E4 | none | `delivery.revenueShare` "Revenue share" | `delivery-kpis.tsx:43,75-80` |
| OVW-HOME-101 | Channel footer: "Delivered orders <n>" and "Delivery fees <money>"; when `cancelled_orders > 0` a warning pill "<n> cancelled" at the end. | E4 | none | `delivery.deliveredOrders`, `delivery.fees`, `delivery.cancelled` "cancelled" | `delivery-kpis.tsx:82-98` |
| OVW-HOME-102 | No empty state: a period with no deliveries shows zero cards and four zero channel cards; an empty `channels` array shows no channel cards. | E4 | none | none | `delivery-kpis.tsx:42,57` |
| OVW-HOME-103 | Responsive: channel cards one column on a phone, two columns from 640 px; totals strip as row 044 (2 columns, 4 from 1024 px). | none | none | none | `delivery-kpis.tsx:48`; `ledger-strip.tsx:35` |
| OVW-HOME-104 | Live: `till.*` and `resync` events refetch delivery sales (key starts `/reports`); `delivery.*` events do NOT (they invalidate `/delivery-orders` only). | E4 | none | none | `use-branch-realtime.ts:51,58,60` |

### 2.11 Cross-cutting

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| OVW-HOME-105 | Retry policy on every home read: no automatic retry on 401, 403, 404, 422; a 429 retried up to 3 times (2 s, 4 s, 8 s); any other failure retried once; data fresh for 30 s; no refetch on window focus. Each card's Retry button refetches only that card's read. | E1-E8 | none | none | `data/api/query.ts:9-49` |
| OVW-HOME-106 | Realtime stream only while a branch is selected (topics `floor,tickets,bookings,delivery,tills`); "All branches" has no live refresh at all; backoff 1, 2, 5, 10, 30 s on drops. | stream `GET /realtime/stream?branch_id&topics` (shell) | server intersects topics with caps | none | `routes/_app/route.tsx:52`; `use-branch-realtime.ts:26-29,66-122` |
| OVW-HOME-107 | Persona without `orders.read` (e.g. a Dawam-only persona forced onto a POS org, or `limited`): KPI cards 0, trend / payment mix / branch performance / margin watch / delivery show their error states with Retry; nothing is hidden on the client. | E1-E5 | server `orders.read` | the five `*Failed` keys | `dp` throughout |
| OVW-HOME-108 | Responsive page frame: side gutter 16 px (phone), 24 px from 640 px, 32 px from 1024 px; 24 px between sections; content capped at 1600 px, start-aligned. | none | none | none | `components/app/page.tsx:27-31,63-75` |
| OVW-HOME-109 | Entrance motion: page fades in; KPI section fades up; trend + payment cards stagger 60 ms; stat cards stagger 50 ms; branch rows 40 ms. All off under reduced motion (Flutter: `MediaQuery.disableAnimations`). | none | none | none | `dp:193,198-205`; `ledger-strip.tsx:57-62`; `page.tsx:65-70` |
| OVW-HOME-110 | Right-to-left: whole page mirrors (glyph tiles, end-aligned figures, X at top-end, links' arrows point left); chart plots stay left-to-right with the Y axis moved right; money is LTR-isolated with the Arabic currency label after the figure ("⁦1,234.50⁩ ج.م"); figures use Western digits. | none | none | none | `dp:65,230`; `chart-card.tsx:39-40`; `lib/format.ts:49-93` |
| OVW-HOME-111 | Keyboard: no page shortcuts (Ctrl/Cmd+K palette is the shell's). Tab reaches, in page order: Keep building, Dismiss, any shortened KPI value (popover), View all, Retry buttons of failed cards, branch revenue popovers (phone), Menu profitability, channel revenue popovers (phone). Popovers close on Escape or outside tap; focus rings visible. | none | none | none | `keep-building-card.tsx:67-77`; `stat-value.tsx:137-152`; `ledger-strip.tsx:100-113`; `margin-watch-card.tsx:119-126` |
| OVW-HOME-112 | Language switch (shell) re-renders every label, plural, money, number, percent and date on the page without refetching. | none | none | all above | `lib/format.ts:8-11,75` |
| OVW-HOME-113 | Theme switch (shell): chart, payment and status colours come from theme tokens and change with light/dark (Talabat oranges and violet have dark variants). | none | none | none | `styles/globals.css:72-85,99-139` |

---

## 3. Formatting rules and browser-side computations

### 3.1 Formatters (`src/lib/format.ts`), reproduce exactly

| Formatter | Rule | Examples |
|---|---|---|
| `fmtMoney(piastres)` (lines 100-116) | piastres / 100; `en-US` grouping, exactly 2 decimals (`maxFractionDigits: 0` → whole pounds); `null`/`undefined`/non-finite → "—"; true minus U+2212; zero never signed. EN: `<sign>EGP <figure>`. AR: `LRI <sign><figure> PDI` + space + `ج.م`. Currency label is ALWAYS the constant `DEFAULT_CURRENCY` "EGP" (`currencyLabel()` called with no code), not the org currency. | `EGP 1,234.50`; `−EGP 50.00`; AR `⁦1,234.50⁩ ج.م` |
| `fmtMoneyCompact(piastres)` (123-132) | `en-US` compact notation, max 1 decimal, Latin "K"/"M" in BOTH languages, same EN/AR shape as money. | `EGP 1.2K`, `EGP 1.2M`; AR `⁦1.2K⁩ ج.م` |
| `fmtNumber(n)` (135-136) | `Intl.NumberFormat(en-GB or ar-EG, latn digits)`, `null` → 0, true minus. | `12,345` (both languages) |
| `fmtNumberCompact(n)` (141-144) | locale compact, max 1 decimal, latn digits (Arabic gets the Arabic word). | EN `2.2K`; AR `2.2 ألف` |
| `fmtPercent(ratio)` (147-150) | locale percent, max 1 decimal, latn digits, true minus. | EN `12.3%`; AR `12.3‎%‎` (ICU inserts LRM marks around %) |
| `fmtShare(part, total)` (153-156) | total 0 → `fmtPercent(0)`; else part/total. | `0%`, `62.4%` |
| `fmtPeriod(iso, granularity)` (278-287) | hourly → `{month: short, day: numeric, hour: 2-digit, minute: 2-digit}`; daily → `{month: short, day: numeric}`; 12-hour clock, latn digits, in the ACTIVE timezone, "am/pm" uppercased to "AM/PM" (Arabic ص/م untouched). | EN hourly `8 Oct, 02:00 PM`, daily `8 Oct`; AR `8 أكتوبر، 02:00 م`, `8 أكتوبر` |
| `fmtElapsedMs` / `fmtDuration(start)` (201-225) | minutes floored; `<m>m` under an hour, `<h>h <mm>m` under a day, `<d>d <hh>h` beyond; negative/invalid → 0; `null` start → "—". AR units ي/س/د with a space, LTR-isolated. Against "now" at render. | `42m`, `1h 05m`, `1d 03h`; AR `1 س 05 د` |
| Locales | EN → `en-GB`, AR → `ar-EG`, always `numberingSystem: latn` | |

Timeseries period strings are naive wall-clock times in the scope zone (no offset). The web parses
them with `new Date(iso)` (device-local) and then formats in the active zone, which equals the naive
value only when the device zone equals the scope zone. Port note: render the naive wall-clock
fields as they are (this is what the web shows for a device in the branch's zone); flagged for the
orchestrator in the notes.

### 3.2 Values computed in the browser

| Value | Rule | Source |
|---|---|---|
| KPI source | branch selected AND branch sales loaded → branch sales; otherwise sums over comparison rows (also the error fallback, row 042) | `dp:94-113` |
| Avg ticket | `orders ? Math.round(revenue / orders) : 0` (piastres) | `dp:115` |
| Tips card | present iff tips is truthy (non-zero) | `dp:169-171` |
| Voided accent | warning iff voided > 0 | `dp:168` |
| KPI loading | branch ? `branchSales.isLoading` : `comparison.isLoading` | `dp:116` |
| Payment map | branch → `revenue_by_method`; all → per-key sum over branches of `Number(v) || 0`; then entries with value > 0, sorted desc | `dp:46-52,118-126` |
| Payment total / share | sum of kept values; share = `fmtShare(value, total)` | `dp:128,317` |
| Slice colour | `PAYMENT_COLORS[method]` else `chartColor(index in sorted list)` (6-colour cycle: brand, info, success, warning, violet, destructive) | `dp:293,312`; `chart-card.tsx:9-18` |
| Granularity | `hourly` iff preset is today or yesterday; else `daily` | `dp:75` |
| Trend points | `{period, revenue, orders}` per timeseries row (only `revenue` drawn) | `dp:130-133` |
| Ranked branches | sort by `total_revenue` desc, take 6, `pct = revenue / max(1, max revenue)`, bar width `max(2, pct*100)` % | `dp:135-141,361` |
| Branch label | name from comparison rows by `branch_id`, else "Branch"; none selected → "All branches" | `dp:148-150` |
| Timezone label | `Africa/Cairo` → "Cairo time"; else city = last `/` segment, `_` → space | `dp:154-158` |
| Margin delta | `prev_margin_known > 0 ? (margin_known − prev)/prev : null` | `margin-watch-card.tsx:36-39` |
| Margin empty | `!data OR (top empty AND bottom empty AND totals.revenue === 0)` | `margin-watch-card.tsx:41` |
| Margin percent | `margin_pct / 100` → fmtPercent (server sends 0-100) | `margin-watch-card.tsx:64,174` |
| Signal percents | `fmtNumber(v, {maximumFractionDigits: 1})` for margin_pct, target_pct, adaptive_bar, pct | `signals.ts:46` |
| Channel bar | `maxRev = max(1, ...revenues)`; value `max(maxRev * 0.02, revenue)` over `maxRev` | `delivery-kpis.tsx:43,76` |
| Channel share | `fmtShare(c.revenue, data.total_revenue)` | `delivery-kpis.tsx:67` |
| Onboarding counts | done = steps with `done`; total = steps length | `keep-building-card.tsx:39-41` |
| StatValue ladder | money: full → whole pounds → compact; count: full → compact; duplicates removed; dense sizes 20/18/16/15/14 px, regular 24/22/20/18/16 px; first that fits the measured width wins | `stat-value.tsx:16-22,85-118`; `stat-card.tsx:29-30` |
| Concise values | under 768 px show compact + popover; else full | `ledger-strip.tsx:88-115`; `hooks/use-mobile.ts:3` |

### 3.3 Period and timezone

- Active zone: selected branch's `timezone` → org `timezone` (only fetched for someone with
  `org.settings.read` and no branch picked) → first non-empty zone among the person's branches → `Africa/Cairo`
  (`data/scope/use-timezone.ts:23-71`).
- Presets (`data/scope/presets.ts:21-45`), day boundaries in the active zone, sent as UTC `Z` instants:
  today = [start of today, 23:59:59.999 today]; yesterday = that for yesterday; 7d = start of day −6 → end of
  today; 30d = start of day −29 → end of today; mtd = start of the 1st → end of today. DST days stay 23/25 h.
- Default preset `30d`; `custom` needs both `from` and `to` or it becomes `30d`.

---

## 4. i18n keys missing from the web's en.json / ar.json

| Key | Inline default (EN) | Where | Arabic to add in the area supplement |
|---|---|---|---|
| `common.dismiss` | "Dismiss" | `features/onboarding/keep-building-card.tsx:73` (aria-label of the X) | "إغلاق" |

Related observations (keys present, but worth knowing):

- `scope.preset.custom` exists as "Custom" / "مخصص"; the home's inline default "Custom range" is never
  shown. Use the file's value.
- `dashboard.ordersWord` is not pluralised ("orders" / "طلب" for every count). Keep as is.
- `delivery.umbrella` "Umbrella delivery" / "توصيل للمظلات" and `delivery.pickup` "Pickup" / "استلام"
  exist but the home's channel cards do not use them (raw codes shown, row 098).
- `payments.<code>` falls back to the raw method code for org-defined methods (row 071).
- `tills.flaggedLink` "See the other till" is not used on the home (row 052).
- Every other key the home uses is present in both files (checked one by one): `dashboard.greetingName`,
  `dashboard.greeting`, `scope.branch`, `scope.allBranches`, `scope.preset.*`, `common.cairoTime`,
  `common.timezoneLabel`, `dashboard.revenue`, `nav.orders`, `dashboard.avgTicket`, `dashboard.voided`,
  `dashboard.tips`, `dashboard.revenueTrend`, `dashboard.trendFailed`, `dashboard.noSalesPeriod`,
  `dashboard.payments`, `dashboard.paymentsFailed`, `payments.*`, `dashboard.branchPerformance`,
  `dashboard.branchesFailed`, `dashboard.ordersWord`, `dashboard.branchRevenueBar`, `delivery.kpisTitle`,
  `delivery.byChannel`, `dashboard.deliveryFailed`, `onboarding.nudge.title`, `onboarding.nudge.body`,
  `onboarding.nudge.cta`, `dashboard.openTills`, `common.viewAll`, `dashboard.noOpenTill`,
  `tills.verification.unverified`, `tills.verification.lan`, `tills.flagged`, `insights.watch.*`
  (title, loadFailed, empty, vsPrev, openSignals, costUnknown, top, bottom, viewAll, sold),
  `common.noResults`, `insights.signals.reason.*`, `delivery.revenue`, `delivery.deliveredOrders`,
  `delivery.fees`, `delivery.inMall`, `delivery.outside`, `delivery.revenueShare`, `delivery.cancelled`,
  `common.retry`, `nav.dashboard`, `nav.overview`.

---

## 5. Pieces shared with other areas

| Piece | Web file | Also used by |
|---|---|---|
| `KeepBuildingCard`, `NUDGE_DISMISS_KEY`, `ONBOARDING_SKIP_KEY`, `sendsToOnboarding` | `features/onboarding/keep-building-card.tsx`, `config.ts`, `gate.ts` | admin area (`/onboarding` wizard) and the shell's first-run gate |
| `OpenTillsCard` / `OpenTillsList`, `useOpenTills` | `features/tills/open-tills-card.tsx`, `features/tills/api.ts` | sell area owns `features/tills` (`/tills`); only the home renders the card |
| `VerificationBadge`, `FlagBadge` | `features/tills/till-badges.tsx` | sell area (`/tills` list and till report) |
| `MarginWatchCard` | `features/insights/margin-watch-card.tsx` | home only, but its helpers are the reports area's |
| `signalReason`, `TINT` | `features/insights/signals.ts`, `features/insights/util.ts` | reports area (`/reports/operations` profitability tab, decisions, repricing) |
| `DeliveryKpis` | `components/app/delivery-kpis.tsx` | home only |
| `LedgerStrip`, `ConciseValue`, `StatCard`, `StatValue` | `components/app/ledger-strip.tsx`, `stat-card.tsx`, `stat-value.tsx` | many areas (orders delivery channels, reports, inventory, tills, devices…) → kit |
| `ChartCard`, `chartColor`, `CHART_AXIS_TICK`, `ChartTooltipContent` | `components/app/chart-card.tsx`, `chart-tooltip.tsx` | reports, inventory, analytics → kit |
| `EmptyState`, `ErrorState`, `ProgressBar`, `SectionHeader`, `StatusPill`, `Page`/`PageHeader` | `components/app/*` | every area → kit |
| `PAYMENT_COLORS`, `PAYMENT_METHODS`, `APP_TZ` | `data/config/constants.ts` | orders, reports, tills |
| Scope (`useScope`, presets, `ALL_BRANCHES_ID`), timezone sync, realtime, modules, authz | `data/scope/*`, `data/realtime/*`, `hooks/use-org-modules.ts`, `data/authz/use-authz.ts` | shell (dashboard_core) |
| Formatters | `lib/format.ts` | every area (dashboard_core / kit) |

## 6. Notes for the orchestrator

1. Web quirks reproduced as rows, flagged so someone decides whether parity means copying them:
   (a) "View all" (row 048) and "Menu profitability" (row 092) drop the branch/period scope;
   (b) branch-scope KPIs fall back to org-wide sums when branch sales fails (row 042);
   (c) Open tills error looks like "No open till" (row 054);
   (d) umbrella/pickup channel cards show raw codes (row 098);
   (e) a branch manager's KPIs come from the org-wide comparison (row 016, backend);
   (f) timeseries naive timestamps are parsed device-local (section 3.1).
2. The home has no mutations, so there are no invalidations to mirror; the only writes are two
   `sessionStorage` flags (nudge dismissed, wizard skipped), which in Flutter should be in-memory,
   per app session.
3. Mock handlers needed for this page: E1-E8 with the semantics listed under "Endpoints", plus the
   403 envelope for personas lacking `orders.read`, `till.read`, `org.settings.read`.
