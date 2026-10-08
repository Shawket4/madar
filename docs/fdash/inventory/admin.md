# Admin area: web parity inventory

Area package: `packages/dashboard_features/admin` (`dashboard_admin`).
Pages: `/orgs`, `/branches`, `/devices`, `/access/users`, `/access/roles`, `/access/review`, `/onboarding`.
App-wide pieces (owned by the shell, `apps/dashboard` + `dashboard_core`; rows marked page **app**): sign-in
(`/login`, the new screen), session guard, org picker, branch picker (scope bar), period picker, scope URL,
timezone sync, user menu, theme and language toggles, command palette, ask-a-manager, module gate, first-run
gate, sidebar, header, footer, toaster, crash screen, the 25 legacy redirect routes, live branch updates.

Web reference: `/Users/shawket/Desktop/Madar/MadarDashboard`, branch `main` @ `fc2faa42` (v1.4.18). Read-only.
Backend checked for server gates and refusal wording: `/Users/shawket/Desktop/Madar/MadarRust`
(`src/orgs/handlers.rs`, `src/orgs/onboarding.rs`, `src/orgs/provision.rs`, `src/branches/handlers.rs`,
`src/devices/handlers.rs`, `src/devices/activation.rs`, `src/client_seen/handlers.rs`, `src/users/handlers.rs`,
`src/authz/api.rs`, `src/auth/handlers.rs`, `src/auth/guards.rs`, `src/errors.rs`).

## How to read a row

`| id | behaviour | API call | gate | i18n keys | web source |`

- **id**: `ADM-<PAGE>-NNN`. Pages: `APP` (app-wide, page "app"), `ORG` `/orgs`, `BRA` `/branches`, `DEV`
  `/devices`, `USR` `/access/users`, `ROL` `/access/roles`, `REV` `/access/review`, `ONB` `/onboarding`.
- **API call**: `METHOD /path (operationId)`; operationId = the Orval hook name minus `use` = the
  `dashboard_api` method name. "–" = no call.
- **gate**: the client rule (what the web hides/disables) and, after `srv:`, the server rule the mock must
  enforce (a 403 envelope). Capability keys are the registry keys (`staff.users.edit`); `platform` = super
  admin (`authz.platform`); `owner` = `authz.owner`. "none" = shown to whoever reaches it.
- **i18n keys**: `key` "English from en.json". Every key exists in `en.json` and `ar.json` unless section 9
  says otherwise. Where the web's inline default differs from en.json, the en.json text is cited (it wins).
- **web source**: `alias:line` relative to `MadarDashboard/src/` (aliases below).
- Toasts are sonner toasts (top-centre, rich colours, close button). A failed call always toasts
  `getErrorMessage(e)` unless the row says otherwise; see ADM-APP-117 for how that text is chosen. An
  uncoded 403 always reads `errors.unauthorized` "You don't have permission to perform this action." in the
  active language.

## Contents

| § | Page | Rows |
|---|---|---|
| 0 | app-wide (page "app"): sign-in, session, shell, sidebar, org/branch/period pickers, scope URL, timezone, user menu, theme/language, command palette, ask-a-manager, module + first-run gates, realtime, 25 legacy redirects, data rules | ADM-APP-001 – ADM-APP-133 |
| 1 | `/orgs` Organizations (+ provision wizard, edit dialog) | ADM-ORG-001 – ADM-ORG-059 |
| 2 | `/branches` Branches (+ branch dialog) | ADM-BRA-001 – ADM-BRA-037 |
| 3 | `/devices` Devices (+ edit device, activation codes, client versions) | ADM-DEV-001 – ADM-DEV-029 |
| 4 | `/access/users` Users (+ section tabs, user dialog, branch access, person access sheet) | ADM-USR-001 – ADM-USR-058 |
| 5 | `/access/roles` Roles & Permissions (+ role dialog, ask-a-manager policy) | ADM-ROL-001 – ADM-ROL-024 |
| 6 | `/access/review` Review | ADM-REV-001 – ADM-REV-017 |
| 7 | `/onboarding` POS first-run wizard | ADM-ONB-001 – ADM-ONB-031 |
| 8 | Formatting rules and browser-side computations | – |
| 9 | Missing i18n keys and untranslated texts | – |
| 10 | Pieces shared with other areas | – |

Total: 388 rows (352 + 36 added by the critic pass of 2026-10-08, marked "(critic)"; 10 rows and two
shared-table bullets fixed by that pass are marked "(corrected)"). Extra web files the critic read: `main.tsx`,
`i18n/index.ts` (+ `detection.test.ts`), `lib/{excel,download,report-error,safe-storage,dialog-outside}.ts`,
`data/api/{custom-instance,stream-auth}.ts`, `hooks/use-route-prefetch.ts`, `components/app/{status-pill,empty-state,
segmented-control,export-button,image-uploader,timezone-select,combobox}.tsx`, `styles/globals.css` (sidebar tokens),
the shared tests (`module-gate`, `use-scope`, `presets`, `use-timezone`, `app.store`, `use-authz`, `page`, `data-table`,
`image-uploader`, `rate-limit`), and MadarRust `orgs/slugs.rs`, `authz/api.rs` (guards, role refusals),
`users/handlers.rs` (refusals), `auth/{routes,middleware}.rs`.

### File aliases

| alias | file (under `src/`) |
|---|---|
| root | `routes/__root.tsx` |
| rlogin | `routes/login.tsx` |
| ronb | `routes/onboarding.tsx` |
| ar | `routes/_app/route.tsx` |
| raccess | `routes/_app/access/route.tsx` (+ `index.tsx`, `users.tsx`, `roles.tsx`, `review.tsx`) |
| lp | `features/auth/login-page.tsx` |
| ag | `lib/auth-guard.ts` |
| as | `data/stores/auth.store.ts` |
| aps | `data/stores/app.store.ts` |
| cl | `data/api/client.ts` |
| err | `data/api/errors.ts` |
| qry | `data/api/query.ts` |
| authz | `data/authz/use-authz.ts` |
| hd | `components/layout/app-header.tsx` |
| sb | `components/layout/app-sidebar.tsx` |
| uisb | `components/ui/sidebar.tsx` |
| ft | `components/layout/app-footer.tsx` |
| opk | `components/layout/org-picker.tsx` |
| sc | `components/layout/scope-bar.tsx` |
| drp | `components/app/date-range-picker.tsx` |
| us | `data/scope/use-scope.ts` |
| pr | `data/scope/presets.ts` |
| tz | `data/scope/use-timezone.ts` |
| um | `components/layout/user-menu.tsx` |
| tt | `components/layout/theme-toggle.tsx` |
| lt | `components/layout/language-toggle.tsx` |
| cp | `components/layout/command-palette.tsx` |
| ll | `components/legal-links.tsx` (+ `config/legal.ts`) |
| nav | `config/nav.ts` |
| mg | `components/app/module-gate.tsx` |
| mods | `hooks/use-org-modules.ts` |
| og | `features/onboarding/gate.ts` |
| rt | `data/realtime/use-branch-realtime.ts` |
| sse | `data/realtime/sse.ts` |
| eb | `components/app/app-error-boundary.tsx` |
| demo | `components/app/demo-banner.tsx` |
| dt | `components/app/data-table.tsx` |
| xl | `lib/excel.ts` |
| iu | `components/app/image-uploader.tsx` |
| tzs | `components/app/timezone-select.tsx` |
| orgs | `features/orgs/orgs-page.tsx` |
| od | `features/orgs/org-dialog.tsx` |
| pw | `features/orgs/provision-wizard.tsx` |
| pv | `features/orgs/provision.ts` |
| sl | `features/orgs/social-links.tsx` |
| tr | `features/orgs/tax-rate.ts` |
| bp | `features/branches/branches-page.tsx` |
| bd | `features/branches/branch-dialog.tsx` |
| dp | `features/devices/devices-page.tsx` |
| ac | `features/devices/activation-codes.tsx` |
| dapi | `features/devices/api.ts` |
| up | `features/users/users-page.tsx` |
| ud | `features/users/user-dialog.tsx` |
| ba | `features/users/branch-assign-dialog.tsx` |
| pas | `features/access/person-access-sheet.tsx` |
| lb | `features/access/limits-button.tsx` |
| cg | `features/access/capability-groups.tsx` |
| cat | `features/access/catalog.ts` |
| rp | `features/access/roles-page.tsx` |
| rd | `features/access/role-dialog.tsx` |
| amc | `features/access/ask-manager-card.tsx` |
| rv | `features/access/review-page.tsx` |
| fd | `features/access/flag-detail.ts` |
| onp | `features/onboarding/onboarding-page.tsx` |
| sp | `features/onboarding/step-panel.tsx` |
| sn | `features/onboarding/step-navigator.tsx` |
| dm | `features/onboarding/dashboard-mirror.tsx` |
| cel | `features/onboarding/celebration.tsx` |
| ocfg | `features/onboarding/config.ts` |

### Shared table behaviour (applies to every `DataTable` row below; `dt`)

- (corrected) Loading: desktop draws skeleton rows (min(pageSize, 6)) inside the table grid; phone (<768) draws
  4 skeleton cards (~96 px tall) instead; stat cards show skeletons.
- (corrected) Error (query failed, not loading): `ErrorState` = danger glyph, title `common.loadFailed` "Couldn't load
  this", the error text (`getErrorMessage`) under it, and `common.retry` "Retry" that refetches. A failed load is never shown as empty.
- Empty: the page's `emptyState`; with no rows after a search the SAME page empty state shows (not
  "No results"), because the table only falls back to `common.noResults` when a page gives no empty state.
- Search (only where the page passes `searchPlaceholder`): one box (`common.search` "Search", aria-label the
  same), client-side, case-insensitive substring over the accessor columns whose value IN THE FIRST ROW is a
  string or number (TanStack `getColumnCanGlobalFilter`). Cells derived without an accessor (slug, email,
  address) are not searched; boolean columns are not searched; a column whose first row is null is not
  searched.
- Columns menu (desktop ≥768 only, unless `hideViewOptions`): outline button `common.columns` "Columns"
  with a checkbox per column that has a label; toggles visibility; the menu stays open while ticking.
- Pagination (client-side, `pageSize` default 10): footer `common.page` "Page {{current}} of {{total}}" with
  previous/next icon buttons (`common.previous` "Previous" / `common.next` "Next", chevrons mirrored in RTL,
  disabled at the ends), shown only when there is more than one page.
- Rows with `onRowClick` are focusable; Enter or Space opens the row; trailing row actions never open it.
- Phone (<768): each row becomes a card; the `phone: "title"` column leads; the other cells stack with their
  labels; row actions sit on the card. No column menu.
- No admin table has sortable headers (none uses `DataTableColumnHeader`).

---

## 0. App-wide (page "app")

### Header

| Field | Value |
|---|---|
| Web paths | `/login`, every `/_app/*` path (shell), `/onboarding` (guard only), the 25 legacy paths |
| Web files read | `routes/__root.tsx`, `routes/login.tsx`, `routes/onboarding.tsx`, `routes/_app/route.tsx`, `routes/_app/index.tsx`, all 25 redirect route files (section 0.13), `features/auth/login-page.tsx`, `components/brand/madar-wordmark.tsx`, `components/legal-links.tsx`, `config/legal.ts`, `components/layout/*` (app-header, app-sidebar, app-footer, command-palette, language-toggle, org-picker, scope-bar, theme-toggle, user-menu), `components/ui/sidebar.tsx`, `components/app/{module-gate,demo-banner,date-range-picker,app-error-boundary,combobox,restricted,page,section-tabs}.tsx`, `config/nav.ts`, `data/stores/{auth,app}.store.ts`, `data/scope/{use-scope,presets,use-timezone,use-page-search}.ts`, `data/authz/use-authz.ts`, `data/realtime/{use-branch-realtime,sse}.ts` (+ tests), `data/api/{client,errors,query,stream-auth}.ts`, `hooks/{use-org-modules,use-org-id,use-mobile,use-export-logo}.ts`, `lib/{auth-guard,format,week,theme}.ts`, `features/onboarding/{gate,config}.ts` (+ `gate.test.ts`), `features/public-shell/use-brand.ts`, `features/tills/redirect.ts`, `features/dawam/setup.ts` (nav set-up rule only). |
| Capabilities | Sign-in: none. Shell: signed-in. Nav leaves per `nav.ts` (ADM-APP-031/032). Branch picker: platform or owner. Org picker: platform (super admin). |
| Module | Module gate is app-wide (ADM-APP-076..085). |
| Realtime | The one branch stream (ADM-APP-086..090). |
| Generated API hooks | `useLogin` (login), `useGetMyAuthz` (getMyAuthz), `useListOrgs` (listOrgs), `useListBranches` (listBranches), `useGetOrg` (getOrg), `useGetOrgModules` (getOrgModules), `useGetOnboarding` (getOnboarding), `usePublicOrgBrand` (publicOrgBrand), realtime `stream` (read via `fetch`, not the hook). |
| Invalidation | Sign-out clears the whole query cache. Realtime events invalidate by key prefix (ADM-APP-088). No other mutation. |

### 0.1 Sign-in `/login`

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-001 | Opening `/login` while a token is stored redirects to `/` (no sign-in screen). | – | none | – | rlogin:9-13 |
| ADM-APP-002 | `/login?redirect=<path>` is accepted; after a successful sign-in the app goes to that path, else `/`. | – | none | – | rlogin:8, lp:37,62 |
| ADM-APP-003 | Screen layout: full-height surface in both themes; top bar = Madar wordmark (Arabic or English artwork by language, title `app.name`) at the start, theme toggle + language toggle at the end; one card (max ~384 px) centred; footer with legal links and copyright; decorative brand orbit (three hairline circles + dots, `aria-hidden`) bleeding off the end edge (mirrors in RTL). Wordmark follows the theme colour. | – | none | `app.name` "Madar" | lp:71-80,162-179 |
| ADM-APP-004 | Card heading and sub-line. | – | none | `auth.signInTitle` "Sign in to Madar", `auth.signInSubtitle` "Sign in to your account to continue" | lp:85-88 |
| ADM-APP-005 | Email field: label, email keyboard, autocomplete email, LTR in both languages, placeholder, 44 px tall. | – | none | `auth.email` "Email address", `auth.emailPlaceholder` "you@madar.com" | lp:92-112 |
| ADM-APP-006 | Email validation on submit (zod): empty → "This field is required"; not an email → "Enter a valid email" (under the field). Browser validation is off (`noValidate`). | – | none | `common.requiredField` "This field is required", `auth.errors.invalidEmail` "Enter a valid email" | lp:41-51,91 |
| ADM-APP-007 | Password field: label, obscured, autocomplete current-password, LTR; empty → "This field is required". | – | none | `auth.password` "Password", `common.requiredField` | lp:48,113-127 |
| ADM-APP-008 | Show/hide password: 44×44 icon button at the field's end (eye / eye-off), `aria-pressed`, label switches; toggles plain text. | – | none | `auth.showPassword` "Show password", `auth.hidePassword` "Hide password" | lp:128-136 |
| ADM-APP-009 | Submit by the full-width button or Enter in either field. | POST `/auth/login` (login) body `{email, password}` | none | `auth.signIn` "Sign in" | lp:58,91,143 |
| ADM-APP-010 | While the call runs the button shows a spinner, is disabled and reads "Signing in…". | – | none | `auth.signingIn` "Signing in…" | lp:143-145 |
| ADM-APP-011 | Success: token + user stored (persisted `madar.auth`), API token set, navigate to `redirect` or `/` (the shell then may send an owner to `/onboarding`, ADM-APP-084). | – | none | – | lp:59-63, as:25-28 |
| ADM-APP-012 | (corrected) Failure: error toast with the server's sentence, kind prefix stripped: 401 "Invalid credentials", "Account is disabled", "No password set for this account"; 400 "password is required for email login"; no network → `errors.networkError`; a user whose business is suspended/deleted → 403 coded `ORG_SUSPENDED` → "This business is suspended. Contact support to reactivate it."; sign-in is rate-limited → 429 → `errors.tooManyRequests` "Too many requests just now. Try again in a moment." (see ADM-APP-121). A login 401 does NOT trigger the session-expiry sign-out (no Bearer was sent). | – | srv: none | `errors.networkError` "Network error — please check your connection." | lp:64, err:157-163, cl:79-93, MadarRust auth/handlers.rs:389-404,619 |
| ADM-APP-013 | Legal links in the footer (`nav` labelled "Legal"), separated by "·", open the public legal site in a new tab / external browser: Privacy `https://legal.madar-pos.cloud/privacy-policy.html`, Terms `https://legal.madar-pos.cloud/terms-of-service.html`. | – | none | `legal.label` "Legal", `legal.privacy` "Privacy Policy", `legal.terms` "Terms of Service" | ll:12-37, config/legal.ts:8-13 |
| ADM-APP-014 | Copyright line with the current year. | – | none | `common.copyright` "© {{year}} Madar. All rights reserved." | lp:68,152-156 |
| ADM-APP-015 | Card fades up on entry; nothing animates under reduced motion. | – | none | – | lp:83 |
| ADM-APP-016 | Theme and language toggles work on this screen exactly as in the shell (ADM-APP-067/068). | – | none | see 067/068 | lp:76-79 |

### 0.2 Session, headers, capabilities

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-017 | Every shell path and `/onboarding` need a token: none → `/login?redirect=<full href>`. | – | signed-in | – | ag:32-36, ar:37, ronb:7 |
| ADM-APP-018 | A stored token whose JWT `exp` is more than 30 s past → sign out, then `/login?redirect=<href>` before any query fires. | – | – | – | ag:4-42 |
| ADM-APP-019 | Any call that sent a Bearer token to a non-`/public/` path and got 401: sign out ONCE (token, user, org, branch, query cache cleared) and hard-navigate to `/login?redirect=<path+search>` unless already on `/login`. | any | – | – | as:68-78, cl:79-93 |
| ADM-APP-020 | Request headers: `Authorization: Bearer`; `X-Org-Id` = picked org (super admin) or the user's org; `X-Branch-Id` = selected branch, or for `branch_manager`/`teller` their own `branch_id`. (Core transport adds these in real mode.) | all | – | – | as:80-105, cl:59-66 |
| ADM-APP-021 | Capabilities: `GET /authz/me` for every non-super-admin (stale 60 s); while loading, the last answer kept in storage (`madar.authz.<userId>`) stands in; a 404 falls back to the role's registry defaults; a super admin holds everything and nothing is fetched; `ready` is false until an answer exists. | GET `/authz/me` (getMyAuthz) | signed-in | – | authz:112-147 |
| ADM-APP-022 | Authz helpers used across the area: `can`, `canAny`, `canEverywhere` (held at every branch; falls back to `can`), `canAsk` (not held AND listed in `ask_manager`), `limitsOf`. | – | – | – | authz:50-82 |

### 0.3 Shell frame, header, footer, toaster, crash screen

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-023 | Shell = sidebar + inset column (demo banner, header, module-gated page, footer). | – | signed-in | – | ar:110-122 |
| ADM-APP-024 | Arabic switches the whole app to RTL, menus/popovers/sidebar included (sidebar on the right). | – | none | – | root:12-19, sb:184 |
| ADM-APP-025 | One toaster for the app: top-centre, rich colours, close button. | – | none | – | root:20 |
| ADM-APP-026 | Header (sticky, 56 px): sidebar toggle (aria "Toggle Sidebar"), command-palette button, then at the end: scope controls (inline ≥768, Filters popover <768), theme toggle, language toggle, user menu. At narrow widths the end cluster scrolls horizontally rather than clipping. | – | signed-in | `ui.sidebar.toggle` "Toggle Sidebar" | hd:8-27, uisb:255-300 |
| ADM-APP-027 | Keyboard: Ctrl/Cmd+B toggles the sidebar (desktop: expanded/icon rail; phone: open/close sheet). Desktop open state persisted (cookie `sidebar_state`, 7 days). | – | none | – | uisb:29-34,86-111 |
| ADM-APP-028 | Footer on every shell page: copyright (current year); "Powered by Madar" only when the org is on the custom-branding tier (`publicOrgBrand.custom_branding`); legal links (ADM-APP-013). Row on ≥640, stacked below. | GET `/public/orgs/brand?org_id=` (publicOrgBrand) | signed-in | `common.copyright`, `publicShell.poweredBy.generic` "Powered by Madar" | ft:14-37 |
| ADM-APP-029 | Crash screen when a page throws while rendering: warning icon, title, description, "Try again" resets the boundary. | – | none | `errors.boundaryTitle` "Something went wrong", `errors.boundaryDescription` "This screen hit an unexpected error. It has been reported — try again, and if it keeps happening reload the page.", `errors.boundaryRetry` "Try again" | eb:8-38 |
| ADM-APP-030 | Demo banner, demo builds only (`VITE_DEMO`): "You're exploring a live demo", time until reset ("{{time}}" as `Nm` / `Nh Nm`, ticks every minute), outline Reset button. Not rendered in a normal build (port only if the Flutter app has a demo mode). | – | demo build | `demo.title`, `demo.body` "Changes are temporary and reset in {{time}}.", `demo.reset` "Reset" | demo:12-54 |

### 0.4 Sidebar navigation

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-031 | Leaf visibility rule (sidebar AND command palette): module switched off → hidden; set-up leaf → only while the Dawam set-up is known incomplete and the person holds its caps; platform-only leaf → super admin only; leaf with caps → any-of; otherwise visible. A group with no visible entry is hidden; a parent with no visible child is hidden. | – | per leaf | – | nav:241-247, sb:189-192,240-242 |
| ADM-APP-032 | Groups in order with labels: Overview, Sell, Catalog, Basira, Reports, Inventory, Setup, Team, Administration. Administration leaves: Organizations `/orgs` (platform only), Branches `/branches` (`branches.read`), Devices `/devices` (`branches.edit` or `till.open`, module pos), Users & Permissions `/access/users` (`staff.users.read` or `staff.permissions.read`). (Other leaves: see each area's inventory.) | – | per leaf | `nav.overview`, `nav.sell`, `nav.catalog`, `nav.basira`, `nav.reports`, `nav.inventory`, `nav.setup`, `nav.team`, `nav.admin` "Administration", `nav.orgs` "Organizations", `nav.branches` "Branches", `nav.devices` "Devices", `nav.usersPermissions` "Users & Permissions" | nav:83-235 |
| ADM-APP-033 | Brand at the top (hidden in icon mode): the shop's own logo when it is on the branding tier and has one (alt = org name), else Madar's wordmark (Arabic/English artwork); links to `/` keeping scope. | GET `/public/orgs/brand?org_id=` (publicOrgBrand), stale 5 min, no retry | signed-in | `app.name` | sb:204-237, features/public-shell/use-brand.ts:87-117 |
| ADM-APP-034 | A group with more than 4 visible entries shows 4 and a muted row "{{count}} more" that expands it; expanded shows "Show less". The group is forced open when the current page is one of the hidden entries. | – | none | `nav.showMoreCount` "{{count}} more", `nav.showMore` "Show more" (tooltip), `nav.showLess` "Show less" | sb:56-179 |
| ADM-APP-035 | Parent entries (Menu, Inventory, Staff) are collapsibles, open by default when the path is under their base path; chevron rotates (mirrored in RTL). | – | none | `nav.menu`, `nav.inventory`, `nav.staff` | sb:74-108 |
| ADM-APP-036 | Active state: the most specific matching leaf wins (`/settings` is not active on `/settings/payment-methods`); `/` only on exact match. | – | none | – | sb:35-54 |
| ADM-APP-037 | Nav links carry ONLY the scope params (`branchId`, `preset`, `from`, `to`) and drop page params (`?edit`, `?order`…). On phone, tapping a link closes the sidebar sheet. | – | none | – | sb:193-200 |
| ADM-APP-038 | Icon-rail mode (desktop collapsed): entries show tooltips with their label. Phone (<768): the sidebar is an off-canvas sheet (18 rem) from the start edge, with a screen-reader title and description. | – | none | `ui.sidebar.title`, `ui.sidebar.description` | sb:81,112, uisb:185-205 |
| ADM-APP-039 | Hover/focus on an entry prefetches that page's data (performance only). | – | none | – | sb:83-84,96 |

### 0.5 Org picker (super admin)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-040 | Shown only to a super admin, first in the scope controls. | GET `/orgs` (listOrgs) only when super admin | platform | – | opk:31-37,56, sc:72 |
| ADM-APP-041 | Searchable combobox of every org (inactive included, with an "Inactive" hint), sorted by name (locale compare); the slug is a search keyword though not shown. | – | platform | `orgs.inactive` "Inactive" | opk:38-54 |
| ADM-APP-042 | Placeholder "Select a shop", search placeholder "Search shops…", empty "No shops found"; disabled while the list loads; dashed border while nothing is picked. | – | platform | `scope.pickOrg` "Select a shop", `scope.searchOrgs` "Search shops…", `scope.noOrgs` "No shops found" | opk:58-81 |
| ADM-APP-043 | Picking an org: stored (persisted `selectedOrgId` + logo), `X-Org-Id` changes for every call, the branch selection is cleared (URL `branchId` removed, persisted branch dropped) so no foreign branch id rides along. | – | platform | – | opk:62-69, aps:51-64 |
| ADM-APP-044 | A super admin with no org picked: org-scoped pages show their "Select an organization" states (BRA-002, USR-004); modules count as all on. | – | platform | – | hooks/use-org-id.ts, mods:39 |

### 0.6 Branch picker (scope bar)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-045 | Shown only to a platform user or an owner; anyone else has no branch control (the server scopes them). | – | platform or owner | – | sc:40-42,73-103 |
| ADM-APP-046 | While branches load: a box with a spinner and "Loading…". | GET `/branches?org_id=` (listBranches) | platform or owner | `common.loading` "Loading…" | sc:46-49,73-80 |
| ADM-APP-047 | Select (store icon): "All branches" first, then ACTIVE branches only. Shown even for a one-branch shop (so the org-level scope stays reachable). | – | platform or owner | `scope.allBranches` "All branches" | sc:81-102 |
| ADM-APP-048 | Changing it writes `branchId` into the URL (replace; "All branches" removes it), persists it and sets `X-Branch-Id`. | – | platform or owner | – | us:74-87 |
| ADM-APP-049 | Self-heal: a selected branch that is not one of this org's active branches (stale, deactivated, other org) resets to All branches once the list is known. | – | platform or owner | – | sc:52-60 |
| ADM-APP-050 | Phone (<768): org picker, branch picker and period picker move into an outline "Filters" icon button that opens a popover with the controls stacked full-width. | – | none | `common.filters` "Filters" | sc:122-137, hd:18-21 |

### 0.7 Period picker

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-051 | Trigger (calendar icon) shows the active preset's label, or for a custom range `fmtDate(from) → fmtDate(to)`, or "Custom" when dates are missing. | – | none | `scope.preset.today` "Today", `scope.preset.yesterday` "Yesterday", `scope.preset.7d` "Last 7 days", `scope.preset.30d` "Last 30 days", `scope.preset.mtd` "Month to date", `datePicker.custom` "Custom" | drp:129-143, sc:26-33,62-65 |
| ADM-APP-052 | Popover top: preset pills (active one filled); a pill applies at once (URL `preset`, `from`/`to` cleared) and closes. | – | none | as 051 | drp:82-85,146-158, us:88-91 |
| ADM-APP-053 | From/To summary: "From"/"To" with the picked days (`fmtDate`) or "—"; To previews the hovered day before the second tap. | – | none | `common.from` "From", `common.to` "To" | drp:162-181 |
| ADM-APP-054 | Month navigation: previous/next icon buttons (chevrons mirrored in RTL) and a month-and-year title. | – | none | `common.previous` "Previous", `common.next` "Next" | drp:117-118,183-192 |
| ADM-APP-055 | Calendar grid: weekday header starting SATURDAY; days of the month; today ringed; future days disabled; first tap = start, second = end (an earlier second tap swaps the two); the range is shaded with rounded ends; a third tap starts again. | – | none | – | drp:87-96,194-246, lib/week.ts:5-9 |
| ADM-APP-056 | Footer hint by state and Apply: Apply disabled until a start exists; a single day applies start-of-day..end-of-day; writes `preset=custom&from&to` and closes. | – | none | `datePicker.clickStart` "Click a start date", `datePicker.clickEnd` "Click an end date", `datePicker.rangeSelected` "Range selected", `datePicker.apply` "Apply" | drp:98-104,248-260, us:92-95 |
| ADM-APP-057 | Re-opening seeds the selection from the current from/to and opens on that month (or the current month). | – | none | – | drp:69-80 |

### 0.8 Scope in the URL and timezone

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-058 | Every shell URL may carry `branchId`, `preset` (`today` `yesterday` `7d` `30d` `mtd` `custom`), `from`, `to` (UTC ISO). A deep link opens the exact view. | – | none | – | ar:28-39, us:48-96 |
| ADM-APP-059 | Bare entry (no `branchId` AND no `preset`): the URL is filled (replace) from the persisted last-used branch and preset; a persisted `custom` becomes `30d`. Runs once per shell mount. | – | none | – | ar:81-100 |
| ADM-APP-060 | Default preset `30d`; `custom` without both dates falls back to `30d` (label says Last 30 days). | – | none | – | us:52-72, pr:9 |
| ADM-APP-061 | URL → store mirror: a link's `branchId` becomes the selected branch (header + persistence); its `preset` becomes the persisted default. | – | none | – | ar:102-108 |
| ADM-APP-062 | Active timezone: selected branch's `timezone` → org `timezone` (read only with no branch selected and `org.settings.read`) → for someone without `org.settings.read`, the first branch zone from the branch list → `Africa/Cairo`. Persisted; every formatter and period boundary uses it. | GET `/orgs/{id}` (getOrg), GET `/branches?org_id=` (listBranches) | none | – | tz:23-71 |

### 0.9 User menu, theme, language

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-063 | Round avatar button: initials (first letter of up to two words, uppercase) or a person icon; aria "Account". | – | signed-in | `common.account` "Account" | um:29-40, lib/format.ts:323-329 |
| ADM-APP-064 | Menu: name, email (if any), role label; separator; "Sign Out" in destructive colour. | – | signed-in | `roles.super_admin` "Super Admin", `roles.org_admin` "Organization Admin", `roles.branch_manager` "Branch Manager", `roles.teller` "Teller", `roles.waiter` "Waiter", `roles.kitchen` "Kitchen", `nav.signOut` "Sign Out" | um:42-58 |
| ADM-APP-065 | Sign out: token/user cleared, org + branch selection cleared, API context cleared, query cache cleared; go to `/login`. | – | signed-in | – | um:24-27, as:29-46 |
| ADM-APP-066 | Signing out from the menu goes to plain `/login` (no `?redirect`), so the next sign-in lands on `/`. The menu has no other item: language and theme are separate header buttons. | – | signed-in | – | um:24-27,42-58 |
| ADM-APP-067 | Theme toggle: ghost icon button (Monitor when following the system, else Moon/Sun by the resolved theme), aria "Toggle theme"; menu Light / Dark / System, current one highlighted; persisted. | – | none | `theme.toggle` "Toggle theme", `theme.light` "Light", `theme.dark` "Dark", `theme.system` "System" | tt:13-50 |
| ADM-APP-068 | Language toggle: one tap switches EN↔AR; the button shows the language you would switch TO ("ع" in English, "EN" in Arabic); direction flips; persisted. | – | none | `language.switch` "Switch language" | lt:6-23, aps:71-74 |

### 0.10 Command palette

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-069 | Header button: outline; icon only below 640 px; from 640 px "Search" text and a "⌘K" key hint; aria "Search". | – | signed-in | `common.search` "Search" | cp:50-61 |
| ADM-APP-070 | Ctrl+K / Cmd+K toggles the palette from anywhere in the shell. | – | signed-in | – | cp:32-41 |
| ADM-APP-071 | Dialog: title "Search" + description "Jump to any page" (screen-reader), input "Search…", empty "No results found". | – | signed-in | `common.search`, `commandPalette.hint` "Jump to any page", `common.searchPlaceholder` "Search…", `common.noResults` "No results found" | cp:63-71 |
| ADM-APP-072 | Lists every VISIBLE nav leaf (same rule as ADM-APP-031) under its group heading, with icon and label; typing matches the label or the path. | – | per leaf | nav labels | cp:72-93 |
| ADM-APP-073 | Choosing an entry closes the palette and navigates to the leaf path WITHOUT the scope params (unlike sidebar links): branch and period fall back to the URL defaults (All branches, 30d) and, through the URL→store mirror, the persisted branch is cleared too. Web behaviour (TanStack drops search when `search` is omitted); keep or flag to the owner. | – | per leaf | – | cp:43-46 |
| ADM-APP-074 | Hover/focus on an entry prefetches its data (performance only). | – | – | – | cp:84-85 |

### 0.11 Ask-a-manager

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-075 | The web has NO app-wide ask-a-manager dialog. "Ask a manager" is (a) `authz.canAsk(cap)` = not held but listed in `/authz/me.ask_manager`, used by pages that offer the act anyway (e.g. Team page deductions, team area), and (b) the business-wide policy "Hidden / Ask a manager" per approval capability on Roles & Permissions (ADM-ROL-019..021). The manager-PIN step itself happens on the POS. Nothing else to port here. | GET `/authz/me` (getMyAuthz) | – | – | authz:79, features/dawam/team-page.tsx:233, amc |

### 0.12 Module gate and first-run gate

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-076 | Org modules: `GET /orgs/{id}/modules` (stale 60 s) for anyone in the org; no org in scope (super admin, none picked) → all modules; unknown until answered (nothing module-tagged is shown on a guess). | GET `/orgs/{id}/modules` (getOrgModules) | srv: same org | – | mods:36-47 |
| ADM-APP-077 | Module of a path = the longest tagged prefix on a segment boundary: every nav leaf with a module (except `/`), plus `/staff` → dawam and `/analytics`, `/insights`, `/inventory`, `/menu`, `/delivery`, `/kitchen`, `/qr`, `/shifts`, `/reports/sales`, `/settings/{bookings,brand,links,combos,integrations,delivery,delivery-zones,kitchen-routing,kitchen-stations,payment-methods,qr}` → pos. So `/reports/staff` is dawam, `/reports/staff-pool` pos. Untagged paths (all of `/orgs`, `/branches`, `/access/*`, `/settings`) work for every org. | – | – | – | nav:249-299 |
| ADM-APP-078 | Tagged path, modules unknown and the read failed: error panel "Couldn't check what this business has switched on" + server message + Retry (refetch). | – | – | `dawam.modulesLoadError` "Couldn't check what this business has switched on", `common.retry` "Retry" | mg:23-34 |
| ADM-APP-079 | Tagged path, modules still loading: the page area renders nothing. | – | – | – | mg:35 |
| ADM-APP-080 | Tagged path, module off: empty state (blocks icon) "Not part of this business's plan" + the module's sentence. Typing the URL never reaches the page. | – | module | `dawam.moduleOffTitle` "Not part of this business's plan", `dawam.modulePosOff` "Madar POS is switched off for this business. Ask Madar to switch it on.", `dawam.moduleDawamOff` "Dawam by Madar is switched off for this business. Ask Madar to switch it on." | mg:36-49 |
| ADM-APP-081 | Admin pages: `/devices` is POS-tagged (a Dawam-only org gets ADM-APP-080 there and no Devices leaf); `/orgs`, `/branches`, `/access/*` are untagged; `/onboarding` is outside the shell and never gated. | – | module pos (devices) | – | nav:231 |
| ADM-APP-082 | Home `/` for a Dawam-only org redirects to `/staff/team` (overview area owns the home; listed because the gate skips `/`). | – | – | – | routes/_app/index.tsx:10-11, nav:279-280 |
| ADM-APP-083 | (Paired with 076) a module switched off also hides its nav leaves and palette entries. | – | module | – | nav:242 |
| ADM-APP-084 | First-run gate: an `org_admin` whose org has POS (modules known), whose checklist the server says is not complete, and who has not skipped this session is sent to `/onboarding`. The onboarding read fires only for org_admin, not skipped, POS on. Never for a Dawam-only org. | GET `/orgs/{id}/onboarding` (getOnboarding) | role org_admin; srv: `org.settings.read` + same org | – | ar:54-79, og:8-16 |
| ADM-APP-085 | Skip flag: `sessionStorage['madar.onboarding.skip'] = "1"` (set by "Skip for now") stops the gate for this browser session; storage unreadable → treated as not skipped. Flutter: an in-memory per-session flag. | – | – | – | ar:60-66, ocfg:90 |

### 0.13 Live branch updates (realtime)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-086 | One stream for the whole shell, open only while a branch is selected in the URL (none for All branches); re-opened when the branch changes; closed when leaving the shell. | – | signed-in | – | ar:50-52, rt:66-122 |
| ADM-APP-087 | (corrected) Stream request: `GET /realtime/stream?branch_id=<id>&topics=floor,tickets,bookings,delivery,tills`, `Accept: text/event-stream`, `Content-Type: application/json` and `Authorization: Bearer` read from the persisted session (`madar.auth`). `X-Org-Id` / `X-Branch-Id` are NOT sent: `authHeaders` looks for `orgId`/`branchId` in the persisted auth state, which only ever holds `{user, token}`, so the branch rides only in the query string. On reconnect it sends `Last-Event-ID` = last frame id. | GET `/realtime/stream` (stream) | srv: intersects topics with permissions | – | rt:26-29,82-88, data/api/stream-auth.ts |
| ADM-APP-088 | Event → refetch every query whose key starts with: `resync` → everything; `booking.*` → `/bookings`, `/floor`; `floor.*` `table.*` `transfer.*` → `/floor`; `ticket.table_changed` → `/floor`, `/open-tickets`; other `ticket.*` → `/open-tickets`, `/floor`; `delivery.*` → `/delivery-orders`; `kitchen.*` → `/kitchen`; `till.*` → `/tills`, `/reports`; `payment_methods.availability_changed` → `/payment-methods`; `branch.settings_changed` → `/branches` (admin: Branches page, branch picker, timezone); anything else → nothing. Events are nudges, never state. | – | – | – | rt:42-64, use-branch-realtime.test.ts |
| ADM-APP-089 | Reconnect backoff 1 s, 2 s, 5 s, 10 s, then 30 s; reset after a successful connect; a refused (non-2xx) stream retries on the same schedule. | – | – | – | rt:25-26,88-114 |
| ADM-APP-090 | SSE framing: frames end at a blank line; `:` lines (keep-alive) ignored; CRLF accepted; several `data:` lines joined with `\n`; default event name `message`; `id:` updates the resume cursor; a partial frame waits for the next chunk. | – | – | – | sse:7-47, sse.test.ts |

### 0.14 The 25 legacy redirect routes

Each is a `beforeLoad` redirect inside the shell (signed-in required first). Unless the row says otherwise the
old query string is NOT carried; the shell then re-hydrates branch/period from the persisted scope (ADM-APP-059).

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-091 | `/access` → `/access/users`. | – | signed-in | – | routes/_app/access/index.tsx:4-8 |
| ADM-APP-092 | `/analytics` → `/reports/operations`. | – | signed-in | – | routes/_app/analytics.tsx:4-8 |
| ADM-APP-093 | `/delivery` → `/settings/delivery`. | – | signed-in | – | routes/_app/delivery/index.tsx:3-7 |
| ADM-APP-094 | `/delivery/channels` → `/menu/pricing`. | – | signed-in | – | routes/_app/delivery/channels.tsx:5-9 |
| ADM-APP-095 | `/delivery/settings` → `/settings/delivery`. | – | signed-in | – | routes/_app/delivery/settings.tsx:4-8 |
| ADM-APP-096 | `/delivery/zones` → `/settings/delivery-zones`. | – | signed-in | – | routes/_app/delivery/zones.tsx:4-8 |
| ADM-APP-097 | `/insights/inventory-reports` → `/reports/inventory`. | – | signed-in | – | routes/_app/insights/inventory-reports.tsx:6-10 |
| ADM-APP-098 | `/insights/profitability` → `/reports/operations`. | – | signed-in | – | routes/_app/insights/profitability.tsx:4-8 |
| ADM-APP-099 | `/insights/sales` → `/reports/operations`. | – | signed-in | – | routes/_app/insights/sales.tsx:4-8 |
| ADM-APP-100 | `/insights/tables` → `/reports/operations`. | – | signed-in | – | routes/_app/insights/tables.tsx:4-8 |
| ADM-APP-101 | `/inventory` → `/inventory/today`. | – | signed-in | – | routes/_app/inventory/index.tsx:3-7 |
| ADM-APP-102 | `/inventory/items` → `/inventory/ingredients`. | – | signed-in | – | routes/_app/inventory/items.tsx:4-8 |
| ADM-APP-103 | `/inventory/reports` → `/reports/inventory`. | – | signed-in | – | routes/_app/inventory/reports.tsx:4-8 |
| ADM-APP-104 | `/kitchen/routing` → `/settings/kitchen-routing`. | – | signed-in | – | routes/_app/kitchen/routing.tsx:4-8 |
| ADM-APP-105 | `/kitchen/stations` → `/settings/kitchen-stations`. | – | signed-in | – | routes/_app/kitchen/stations.tsx:4-8 |
| ADM-APP-106 | `/menu` → `/menu/items`. | – | signed-in | – | routes/_app/menu/index.tsx:3-7 |
| ADM-APP-107 | `/menu/overrides` → `/menu/pricing`. | – | signed-in | – | routes/_app/menu/overrides.tsx:5-9 |
| ADM-APP-108 | `/menu/recipes` → `/menu/items`. | – | signed-in | – | routes/_app/menu/recipes.tsx:6-10 |
| ADM-APP-109 | `/permissions?user=<id>` → `/access/roles?user=<id>` (`user` carried; the Roles page accepts and ignores it). | – | signed-in | – | routes/_app/permissions.tsx:5-12, routes/_app/access/roles.tsx:6-10 |
| ADM-APP-110 | `/qr` → `/settings/qr`. | – | signed-in | – | routes/_app/qr.tsx:4-8 |
| ADM-APP-111 | `/reports/operations/profitability` → `/reports/operations`. | – | signed-in | – | routes/_app/reports/operations/profitability.tsx:4-8 |
| ADM-APP-112 | `/reports/operations/tables` → `/reports/operations`. | – | signed-in | – | routes/_app/reports/operations/tables.tsx:4-8 |
| ADM-APP-113 | `/reports/sales` → `/reports/operations`. | – | signed-in | – | routes/_app/reports/sales.tsx:4-8 |
| ADM-APP-114 | `/shifts?<anything>` → `/tills?<same params>`, replacing the history entry (every search param carried, e.g. `?report=x`). | – | signed-in | – | routes/_app/shifts.tsx:6-10, features/tills/redirect.ts:2-4 |
| ADM-APP-115 | `/users?edit=<id>&branches=<id>` → `/access/users?edit=<id>&branches=<id>` (both carried; the Users page opens the editor / branch access). | – | signed-in | – | routes/_app/users.tsx:5-13 |

### 0.15 App-wide data rules

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-APP-116 | Reads: stale after 30 s, kept 5 min, no refetch on window focus (Dawam reads opt in); never retried on 401/403/404/422; a 429 retried up to 3 times (2 s, 4 s, 8 s); anything else once. Mutations never retried. | – | – | – | qry:9-50 |
| ADM-APP-117 | Error wording (`getErrorMessage`): a known `code` → `errors.codes.<code>` (with vars); uncoded 429 → `errors.tooManyRequests`; uncoded 403 → `errors.unauthorized`; else the server's `error` (kind prefix "Conflict: " / "Forbidden: " … stripped) or `message`; no response → `errors.networkError`; then by status 401 `errors.sessionExpired`, 403 `errors.unauthorized`, 404 `errors.notFound`, 409 `errors.conflict`, 422 `errors.validation`, ≥500 `errors.server`; non-HTTP error → its message; else `errors.unknown`. | – | – | `errors.unauthorized` "You don't have permission to perform this action.", `errors.tooManyRequests`, `errors.networkError`, `errors.sessionExpired`, `errors.notFound`, `errors.conflict`, `errors.validation`, `errors.server`, `errors.unknown` | err:99-185 |
| ADM-APP-118 | Confirm dialogs (every destructive confirm in this area): title, description, Cancel, confirm button (red when destructive, with a red-tinted warning glyph); resolves true/false. | – | – | `common.cancel` "Cancel", `common.confirm` "Confirm" | components/app/confirm-dialog.tsx:23-82 |
| ADM-APP-119 | (critic) Shared table state: the page jumps back to page 1 whenever the rows change (a refetch after any change, a `branch.settings_changed` nudge, typing in the search) — TanStack's default page reset for client paging. Hidden columns (Columns menu) and the search text are component state: lost on leaving the page, never in the URL. | – | – | – | dt:145-175 |
| ADM-APP-120 | (critic) Every API call times out after 20 s; a timed-out or unreachable call has no response and reads `errors.networkError`. | any | – | `errors.networkError` "Network error — please check your connection." | cl:55-58, err:165-166 |
| ADM-APP-121 | (critic) Suspended business: sign-in for a user whose org is suspended/deleted is refused 403 coded `ORG_SUSPENDED` (toast "This business is suspended. Contact support to reactivate it."); mid-session every call for that org answers 403 `ORG_SUSPENDED` (not 401, so no sign-out): each page shows its error state with that sentence. `POST /auth/login` is rate-limited: 429 → "Too many requests just now. Try again in a moment.". | POST `/auth/login` → 403 / 429; any → 403 | srv | `errors.codes.ORG_SUSPENDED` "This business is suspended. Contact support to reactivate it.", `errors.tooManyRequests` "Too many requests just now. Try again in a moment." | err:140-150, MadarRust auth/handlers.rs:618-630, auth/middleware.rs:110-128, auth/routes.rs:26-29 |
| ADM-APP-122 | (critic) Unknown path (no route matches, e.g. `/foo`): the router's built-in not-found text "Not Found" (English, outside the shell, no sign-in check); there is no custom 404 page or key. Port: owner decision (copy, or a translated not-found). | – | – | – (no key) | main.tsx:55-63 (no `defaultNotFoundComponent`), routes/__root.tsx |
| ADM-APP-123 | (critic) First-launch language: the stored choice (`madar.lang`) wins; else the device's language list IN ORDER with regions stripped, first of en/ar (an `en-GB, ar` phone gets English); else English. `<html lang>`/`dir` follow every change. Theme: default "System" (follows the device's light/dark live while on System); stored under `madar.theme`. | – | none | – | i18n/index.ts:26-73, i18n/detection.test.ts, lib/theme.ts:1-55, aps:44-48 |
| ADM-APP-124 | (critic) Sidebar look: a dark ink surface in BOTH themes (light `#0D1A1E`, dark `#0A1417`, muted labels `#9DB0B6`/`#8FA4AB`), so Madar's wordmark is drawn white; a shop's own logo is not inverted. Widths: 16 rem expanded, 3 rem icon rail, 18 rem phone sheet. A thin rail button along the sidebar's inner edge (aria/title "Toggle Sidebar") also toggles expanded/icon mode on desktop. | – | none | `ui.sidebar.toggle` "Toggle Sidebar" | sb:203-259, uisb:29-34,285-300, styles/globals.css:88-90,142-144 |
| ADM-APP-125 | (critic) Status pills (Active/Inactive, On, Retired, code states, Reviewed, Up to date, Legacy, review reasons) always carry a tone glyph before the label, never colour alone: neutral circle, success check-circle, warning triangle, danger x-circle, info i-circle, accent dashed circle; md 24 px / sm 20 px. | – | – | – | components/app/status-pill.tsx:1-60, components/app/page.test.tsx:46-50 |
| ADM-APP-126 | (critic) Excel export engine (Organizations, Branches, Users): on press a loading toast "Gathering data…" that becomes "Exported {{count}} rows" (plural; Arabic zero/one/two/few/many/other forms) or, on any failure, "Export failed" — `exportToExcel` catches its own errors, so a page's `getErrorMessage` catch never fires. An empty list toasts "Nothing to export" (unreachable here: the button is disabled). Workbook: landscape, fit to width; row 1 banner = sheet title (bold, brand colour) with the logo at the start; row 2 "Generated: <full date-time>" (muted); header row 7 (white on brand) frozen; data below; padded to at least six columns. | – (client file; `ExportGateway`) | none | `excel.generating` "Gathering data…", `excel.done_one` "Exported {{count}} row", `excel.done_other` "Exported {{count}} rows", `excel.failed` "Export failed", `excel.nothingToExport` "Nothing to export", `excel.generated` "Generated" | xl:189-260,348-390 |
| ADM-APP-127 | (critic) Image uploader (org logo in the wizard and edit dialog, onboarding café logo): square dashed box (max 200 px); drag-and-drop onto it or tap to pick (PNG/JPEG/WebP, 5 MB); empty → image glyph + "Choose Image"; uploading → spinner + "Uploading..."; with an image → overlay icon buttons Replace (upload glyph, aria "Replace") and Remove (X, aria "Remove", only where removal is offered, spinner while removing) — always visible on touch screens, on hover/focus with a mouse. An error replaces the hint in red; a failed upload/remove shows the thrown error's RAW message (an API failure reads axios's English "Request failed with status code 4xx", not `getErrorMessage`) — web quirk, owner decision. A new image shows at once, before the refetch lands. | PUT `/orgs/{id}/logo` (uploadOrgLogo) | – | `uploader.choose` "Choose Image", `uploader.uploading` "Uploading...", `uploader.replace` "Replace", `uploader.remove` "Remove", `uploader.notAnImage`, `uploader.tooLarge` | iu:43-237 |
| ADM-APP-128 | (critic) Timezone select (wizard, edit org, branch dialog): options are the `GET /timezones` labels; search matches the label with "/" and "_" read as spaces (case-insensitive substring); a value already set shows even before the list loads; no match → "No results found"; the picked option shows a check. | GET `/timezones` (listTimezones) | none | `common.selectTimezone`, `common.searchTimezone`, `common.noResults` "No results found" | tzs:18-44, components/app/combobox.tsx:40-96 |
| ADM-APP-129 | (critic) Org picker: once a shop is picked there is no way back to "no shop" (no clear entry); the picked shop shows a check; matching is a case-insensitive substring over name + slug. | – | platform | – | opk:58-81, components/app/combobox.tsx:66-90 |
| ADM-APP-130 | (critic) Branch picker when the branch-list read fails: no error is shown; the select offers only "All branches" and the self-heal (ADM-APP-049) does not run. | GET `/branches?org_id=` → error | platform or owner | `scope.allBranches` | sc:46-60,81-102 |
| ADM-APP-131 | (critic) Web niceties, port where the platform has an equivalent: scroll position restored on back/forward; a quiet cross-fade between pages (off under reduced motion); every page fades in on mount; tooltips open after 200 ms. | – | – | – | main.tsx:55-63,122-123, components/app/page.tsx:63-74 |
| ADM-APP-132 | (critic) Error reporting: render crashes (ADM-APP-029) and API 5xx / unreachable failures are sent to Sentry when a DSN is configured (ordinary 4xx are not). Web telemetry; port only if the Flutter app has crash reporting (owner decision). | – | – | – | eb:26-37, cl:73-80, lib/report-error.ts:93-131 |
| ADM-APP-133 | (critic) Uncoded-403 rule, consequence for this area: every authz guard refusal (person access editor, role grants) and every user-management 403 ("You cannot delete yourself", "You cannot change your own role or deactivate yourself", "You do not have access to this user", "You can only delete users assigned to your branches", "You cannot assign a user to a branch you are not assigned to") reaches the person as `errors.unauthorized`; the server's sentence is never shown. The mock answers these as uncoded 403s; the UI shows the generic sentence. | any → 403 | srv | `errors.unauthorized` "You don't have permission to perform this action." | err:149-150, MadarRust authz/api.rs:340-361, users/handlers.rs:543-616,749-765 |

---

## 1. `/orgs` Organizations

### Header

| Field | Value |
|---|---|
| Web path | `/orgs` (`?edit=<id>` opens the editor, `?edit=new` opens the provision wizard) |
| Title | `orgs.title` "Organizations"; subtitle `orgs.subtitle` "Manage all coffee brands and franchises"; nav `nav.orgs` "Organizations" in `nav.admin` "Administration" |
| Web files read | `routes/_app/orgs.tsx`, `features/orgs/{orgs-page,org-dialog,provision-wizard,provision,social-links,tax-rate,util}.ts(x)` + tests (`org-dialog.test.tsx`, `provision.test.ts`, `social-links.test.ts`, `tax-rate.test.ts`), `features/users/row-action.tsx`, `components/app/{data-table,page,stat-card,stat-value,export-button,confirm-dialog,empty-state,status-pill,image-uploader,timezone-select,combobox,asset-image}.tsx`, `lib/excel.ts`, `hooks/use-export-logo.ts`, `data/scope/use-page-search.ts` |
| Capabilities | Nav: platform only (`superAdminOnly`). No `<Restricted>` and no client check on the page or its buttons. Server: every `/orgs` call here is super-admin only (`require_super_admin`) except `PUT /orgs/{id}/logo` (super admin, or an org member for their own org). |
| Module | none (untagged) |
| Realtime | none (only `resync` refetches) |
| Generated API hooks | `useListOrgs` (listOrgs), `deleteOrg`, `updateOrg`, `uploadOrgLogo`, `provisionOrg`, `useListTemplates` (listTemplates), `useListTimezones` (listTimezones), `createOrg` (dialog create mode, unreachable from this page — ORG-055), `usePublicOrgBrand` (export logo) |
| Invalidation | Every mutation → `invalidateOrgs()` = every query whose key starts with `/orgs` (list, `/orgs/{id}`, modules, onboarding). |

### Behaviours

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-ORG-001 | Sidebar and palette show Organizations only to a super admin. | – | platform | `nav.orgs` "Organizations" | nav:229 |
| ADM-ORG-002 | Page header with title, subtitle and actions Export + New. | – | none | `orgs.title` "Organizations", `orgs.subtitle` "Manage all coffee brands and franchises" | orgs:116-121 |
| ADM-ORG-003 | Loads every organization (unpaginated, active and inactive). | GET `/orgs` (listOrgs) | srv: super admin | – | orgs:35-36 |
| ADM-ORG-004 | Refusal: a non-super-admin who types `/orgs` sees the page frame; the list call is refused (403 "Super admin access required", uncoded) so the table shows its error state with `errors.unauthorized` + Retry; stats show 0 and Avg Tax "—"; Export disabled; New still visible (the wizard's create would be refused). | GET `/orgs` → 403 | srv: super admin | `errors.unauthorized` | orgs:35,128-133, MadarRust orgs/handlers.rs:443-447 |
| ADM-ORG-005 | Stat cards (2 per row, 4 from 1024 px): Total = all; Active = `is_active`; Inactive = not active; Avg Tax = mean of `tax_rate` fractions as a percent with up to 1 decimal ("14%"), "—" with no orgs. Skeletons while loading. | – | none | `common.total` "Total", `common.active` "Active", `common.inactive` "Inactive", `orgs.avgTax` "Avg Tax" | orgs:109-127 |
| ADM-ORG-006 | Column Name (card title on phone): 32 px logo (asset image) or a tile with the first two letters uppercased; name bold; slug in mono below. | – | none | `common.name` "Name" | orgs:55-65 |
| ADM-ORG-007 | Column Currency: code in a mono badge. | – | none | `orgs.currency` "Currency" | orgs:66 |
| ADM-ORG-008 | Column Tax rate (%): numeric/end-aligned, `formatRate` ("14%"; 4 dp max). | – | none | `orgs.taxRate` "Tax rate (%)" | orgs:67, tr:45-48 |
| ADM-ORG-009 | Column Custom branding: info pill "On" or muted "Off". | – | none | `orgs.customBranding` "Custom branding", `common.on` "On", `common.off` "Off" | orgs:68-78 |
| ADM-ORG-010 | Column Status: success pill "Active" / neutral pill "Inactive". | – | none | `common.status` "Status", `common.active`, `common.inactive` | orgs:79-85 |
| ADM-ORG-011 | Search box (shared table rules): matches name, currency code and the raw tax fraction (e.g. "0.14"); not slug. | – | none | `common.search` "Search" | orgs:142, dt:337-353 |
| ADM-ORG-012 | Columns menu (desktop): Name, Currency, Tax rate (%), Custom branding, Status can be hidden. | – | none | `common.columns` "Columns" | dt:355-376 |
| ADM-ORG-013 | Pagination 10 per page (shared rules). | – | none | `common.page`, `common.previous`, `common.next` | dt:553-584 |
| ADM-ORG-014 | Loading: skeleton rows + stat skeletons. | – | none | – | orgs:123-131 |
| ADM-ORG-015 | Error: error state with message + Retry (refetch). | GET `/orgs` | none | `common.retry` "Retry" | orgs:132-133 |
| ADM-ORG-016 | Empty (no orgs, or search matches none): building icon + "Organizations you add appear here". | – | none | `orgs.empty` "Organizations you add appear here" | orgs:143 |
| ADM-ORG-017 | Phone (<768): each org is a card led by the Name cell. | – | none | – | dt:231-330,386-424 |
| ADM-ORG-018 | Row click / Enter / Space → `?edit=<id>` → edit dialog. | – | none | – | orgs:141 |
| ADM-ORG-019 | Row action Edit: ghost pencil icon with tooltip/aria "Edit" → `?edit=<id>`. | – | none | `common.edit` "Edit" | orgs:136 |
| ADM-ORG-020 | Row action Delete: red trash icon, tooltip "Delete" → confirm "Delete {{name}}?" / "Every branch, user and menu under this organization is removed. This cannot be undone." with a red Delete. Cancel does nothing. | – | none | `common.delete` "Delete", `orgs.deleteTitle` "Delete {{name}}?", `orgs.deleteDescription` | orgs:47-51,137 |
| ADM-ORG-021 | Delete confirmed: call; success → refetch `/orgs*`, toast "Organization deleted"; failure → error toast. | DELETE `/orgs/{id}` (deleteOrg) | srv: super admin | `orgs.deletedToast` "Organization deleted" | orgs:49 |
| ADM-ORG-022 | (corrected) Export Excel (outline, download icon; disabled with no orgs; spinner while building): file `Madar-Organizations-<YYYY-MM-DD>.xlsx` (UTC date), one sheet named and titled "Organizations"; columns Name (text, w28), Slug (text, w20), Currency (text, w12), Tax rate (%) (number = percent, e.g. 14; w12), Status (Active/Inactive, w12). Header logo = the org's own when on the branding tier, else Madar's. Toasts come from the export engine (ADM-APP-126): loading "Gathering data…" → "Exported {{count}} rows", or "Export failed" on any failure — never `getErrorMessage` (the page's own catch is unreachable). | – (client file; `ExportGateway`) | none | `common.export` "Export Excel", `orgs.title`, `common.name`, `orgs.slug` "Slug", `orgs.currency`, `orgs.taxRate`, `common.status`, `common.active`, `common.inactive` | orgs:91-107,120, xl:348-386 |
| ADM-ORG-023 | New (plus icon) → `?edit=new` → provision wizard. | – | none | `common.new` "New" | orgs:120,145 |
| ADM-ORG-024 | Deep link `?edit=<id>`: the edit dialog opens once the list has loaded and contains that id (an unknown id opens nothing); `?edit=new` opens the wizard. Closing either removes `?edit` (history replace). | – | none | – | routes/_app/orgs.tsx:5-9, orgs:41-46,145-146 |

#### Provision wizard (New)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-ORG-025 | Dialog (scrolls inside 90 % height; phone = full-screen sheet): title "New Organization"; description "Step {{current}} of {{total}} · <step title>"; progress list (aria "Progress") of Business / First branch / Owner — done steps show a check, the current step is marked. | GET `/orgs/templates` (listTemplates) while open | platform | `orgs.newTitle` "New Organization", `orgs.wizard.stepOf` "Step {{current}} of {{total}}", `orgs.wizard.progress` "Progress", `orgs.wizard.stepBusiness` "Business", `orgs.wizard.stepBranch` "First branch", `orgs.wizard.stepOwner` "Owner" | pw:43,59-63,100-127 |
| ADM-ORG-026 | Step 1 Logo: image picker with hint; the file is kept locally (preview) and uploaded only after the org exists; Remove clears it. Accepts PNG/JPEG/WebP up to 5 MB; non-image → "Selected file must be an image"; too big → "Image size exceeds 5MB limit". | – | platform | `orgs.logo` "Logo", `orgs.logoHint` "Recommended: square PNG or SVG, at least 128×128 px", `uploader.choose` "Choose Image", `uploader.replace` "Replace", `uploader.remove` "Remove", `uploader.notAnImage`, `uploader.tooLarge` | pw:46-51,140-155, iu:48-49,87-97 |
| ADM-ORG-027 | Step 1 Organization Name (required, trimmed); every keystroke rewrites Slug = lowercase, spaces → "-", anything not a-z 0-9 "-" removed. | – | platform | `orgs.orgName` "Organization Name", `common.requiredField` | pw:156-162, pv:8-9,18 |
| ADM-ORG-028 | Step 1 Slug (mono, required, trimmed). | – | platform | `orgs.slug` "Slug", `common.requiredField` | pw:163-165, pv:19 |
| ADM-ORG-029 | Step 1 Template: radio cards from the templates list, name in the active language (`name_en`/`name_ar`), hint under `restaurant` and `cafe`; selected card bordered. Required: "Choose a template". A failed templates read shows the server message in red under the cards. | GET `/orgs/templates` (listTemplates) | platform | `orgs.wizard.template` "Template", `orgs.wizard.restaurantHint` "Tables, waiters and kitchen.", `orgs.wizard.cafeHint` "Counter service; the cashier marks items ready. No bookings.", `orgs.wizard.templateRequired` "Choose a template" | pw:166-199, pv:20 |
| ADM-ORG-030 | Step 1 Currency (mono, shown uppercase, default EGP, required); sent trimmed and uppercased. | – | platform | `orgs.currency`, `common.requiredField` | pw:200-203, pv:21,77 |
| ADM-ORG-031 | Step 1 Tax rate (%): number, step 0.1, default 0, 0..100 else "Enter a rate between 0 and 100"; sent as a fraction (÷100, 6 dp). | – | platform | `orgs.taxRate`, `orgs.taxRateRange` "Enter a rate between 0 and 100" | pw:204-206, pv:24-27,79, tr:40-43 |
| ADM-ORG-032 | Step 1 Timezone: searchable select of server timezones ("new york" finds America/New_York), default Africa/Cairo, required. | GET `/timezones` (listTimezones) | platform | `orgs.timezone` "Timezone", `common.selectTimezone` "Select timezone…", `common.searchTimezone` "Search timezones…" | pw:208-214, tzs:18-44 |
| ADM-ORG-033 | Step 1 Modules: checkboxes Madar POS (on by default) and Dawam by Madar; at least one else "Pick at least one module". | – | platform | `dawam.modules` "Modules", `dawam.modulePos` "Madar POS", `dawam.moduleDawam` "Dawam by Madar", `dawam.modulesAtLeastOne` "Pick at least one module" | pw:215-231, pv:29 |
| ADM-ORG-034 | Next validates only the current step's fields; Enter in a field acts as Next on steps 1-2 and as Create on step 3. | – | platform | `common.next` "Next" | pw:65-67,130-136,282-286 |
| ADM-ORG-035 | Step 2: Branch name (required), Address (optional), Phone (optional, phone keyboard, LTR). Blank optionals are left out of the request. | – | platform | `orgs.wizard.branchName` "Branch name", `orgs.wizard.address` "Address (optional)", `orgs.wizard.phone` "Phone (optional)" | pw:235-247, pv:31-35,84-88 |
| ADM-ORG-036 | Step 3: Owner name (required); Email (LTR) invalid → "Enter a valid email"; Password (new-password) under 8 chars → "At least 8 characters"; PIN optional, numeric keyboard, max 6, mono LTR, if given exactly 6 digits else "The PIN is exactly 6 digits". | – | platform | `orgs.wizard.ownerName` "Owner name", `orgs.wizard.email` "Email", `orgs.wizard.password` "Password", `orgs.wizard.pin` "PIN (optional, 6 digits)", `orgs.wizard.emailInvalid` "Enter a valid email", `orgs.wizard.passwordMin` "At least 8 characters", `orgs.wizard.pinInvalid` "The PIN is exactly 6 digits" | pw:249-262, pv:36-44 |
| ADM-ORG-037 | Step 3 summary box with the four defaults; the tax line shows the rate typed on step 1 (0 when blank). | – | platform | `orgs.wizard.summaryTitle` "The new organization starts with:", `orgs.wizard.summaryVoid` "A teller may void only their own sale, within 10 minutes.", `orgs.wizard.summaryRefund` "Refunds need a manager's approval.", `orgs.wizard.summaryWaiter` "Waiters can't refund.", `orgs.wizard.summaryTax` "Tax {{rate}}% unless set." | pw:97,264-272 |
| ADM-ORG-038 | Footer: step 1 Cancel (closes); steps 2-3 Back (previous step, values kept); Cancel/Back disabled while creating. | – | platform | `common.cancel` "Cancel", `common.back` "Back" | pw:276-281 |
| ADM-ORG-039 | Create: one call with `{name, slug, template, currency_code, timezone, tax_rate (fraction), modules, branch:{name, address?, phone?}, owner:{name, email, password, pin?}}`; then, if a logo was picked, upload it to the new org (a failed upload toasts its error but the org stays created); refetch `/orgs*`; toast "Organization created"; close. Button spinner while running. | POST `/orgs/provision` (provisionOrg); PUT `/orgs/{id}/logo` (uploadOrgLogo, multipart `logo`) | srv: super admin | `common.create` "Create", `orgs.createdToast` "Organization created" | pw:69-95, pv:72-91 |
| ADM-ORG-040 | Create refused 409 whose message mentions "slug" → jump to step 1 with that message under Slug; mentions "email" → step 3 with it under Email (message shown exactly as the server sent it, e.g. "Conflict: Slug 'x' is already taken"); any other failure → error toast. | POST `/orgs/provision` → 409 | srv: super admin | – | pw:84-91, pv:98-108 |

#### Edit organization dialog (`?edit=<id>`)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-ORG-041 | Dialog (90 % height scroll) title "Edit Organization" and description; fields prefilled from the org each time it opens. | – | none | `orgs.editTitle` "Edit Organization", `orgs.editDescription` "Update the details for this organization." | od:94-117,169-174 |
| ADM-ORG-042 | (corrected) Logo: picker showing the current logo; picking uploads at once; success refetches `/orgs*` and, if this is the org picked in the org picker, updates the stored logo. Upload/remove errors show under the picker in red as the thrown error's RAW message (an API failure reads axios's English "Request failed with status code 4xx", not `getErrorMessage`; ADM-APP-127). | PUT `/orgs/{id}/logo` (uploadOrgLogo) | srv: super admin or own org | `orgs.logo`, `orgs.logoHint`, `uploader.*` | od:177-188 |
| ADM-ORG-043 | Logo Remove (only when a logo exists): clears it; refetch; stored logo cleared if selected org; toast "Logo removed". | PATCH `/orgs/{id}` (updateOrg) `{logo_url: null}` | srv: super admin | `orgs.logoRemoved` "Logo removed" | od:189-194 |
| ADM-ORG-044 | Organization Name (required; no slug auto-fill while editing). | – | none | `orgs.orgName`, `common.requiredField` | od:213-219 |
| ADM-ORG-045 | Slug (mono, required). Server may refuse: taken → "Slug 'x' is already taken"; frozen on the branding tier → "This shop's short name is part of its web address…" (409 toast). | – | srv: super admin | `orgs.slug` | od:220-222, MadarRust orgs/handlers.rs:726-755 |
| ADM-ORG-046 | Currency (mono uppercase, required) and Tax rate (%) side by side; rate shown as percent (fraction ×100, 4 dp), 0..100 else "Enter a rate between 0 and 100". | – | none | `orgs.currency`, `orgs.taxRate`, `orgs.taxRateRange` | od:61-68,223-230, tr:29-32 |
| ADM-ORG-047 | Switch "Menu prices include tax" + hint. | – | none | `orgs.taxInclusive` "Menu prices include tax", `orgs.taxInclusiveHint` | od:235-250 |
| ADM-ORG-048 | Service charge (%) 0..100 + hint; switch "Tax the service charge" (default on). | – | none | `orgs.serviceCharge` "Service charge (%)", `orgs.serviceChargeHint` "0 for none. Shown as its own line on the bill.", `orgs.serviceChargeTaxable` "Tax the service charge", `orgs.taxRateRange` | od:76-81,252-273 |
| ADM-ORG-049 | Timezone select + hint (required). | GET `/timezones` (listTimezones) | none | `orgs.timezone`, `orgs.timezoneHint` "Default for all branches. A branch can override its own." | od:274-281 |
| ADM-ORG-050 | Receipt Footer (optional; empty sent as null). Switch Active (edit only). | – | none | `orgs.receiptFooter` "Receipt Footer", `common.active` | od:282-292 |
| ADM-ORG-051 | Switch "Every dine-in sale belongs to a table" + hint. | – | none | `orgs.requireTable`, `orgs.requireTableHint` | od:294-309 |
| ADM-ORG-052 | Switch "Custom branding" + hint. | – | none | `orgs.customBranding`, `orgs.customBrandingHint` | od:314-329 |
| ADM-ORG-053 | Modules box (super admin only): POS / Dawam checkboxes + hint; at least one ("Pick at least one module"). For anyone else the box is absent and `modules` is never sent. | – | platform | `dawam.modules`, `dawam.modulePos`, `dawam.moduleDawam`, `dawam.modulesHint` "Switching a module off hides its pages and keeps every record.", `dawam.modulesAtLeastOne` | od:331-352, org-dialog.test.tsx:51-80 |
| ADM-ORG-054 | Social links (edit only): heading + hint; eight LTR URL fields in card-print order Instagram, Facebook, TikTok, X, YouTube, WhatsApp, Talabat, Website (sample placeholders e.g. `https://instagram.com/yourshop`); each empty or a full `https://` URL else "Use the full address, starting with https://" (http refused, not upgraded). Sent: typed values (trimmed) plus `""` for links that existed and were cleared; never-set platforms are left out. | – | none | `orgs.socialLinks` "Where else to find you", `orgs.socialLinksHint`, `orgs.social.instagram` … `orgs.social.website`, `orgs.socialInvalid` "Use the full address, starting with https://" | od:361, sl:47-206, social-links.test.ts |
| ADM-ORG-055 | Save: sends `{name, slug, currency_code, tax_rate, receipt_footer, timezone, is_active, custom_branding, modules (super admin), tax_inclusive, service_charge_rate, service_charge_taxable, require_table_for_orders, social_links}` (rates as fractions); refetch `/orgs*`; toast "Organization updated"; close. Failure → error toast, dialog stays. Spinner on Save; Cancel disabled while saving. (The same dialog in create mode — `POST /orgs` multipart then `PATCH {modules}` when a super admin picked more than POS — is never opened by this page, because New opens the wizard; nothing to port.) | PATCH `/orgs/{id}` (updateOrg) | srv: super admin | `common.save` "Save", `common.cancel`, `orgs.updatedToast` "Organization updated" | od:121-166,363-366 |
| ADM-ORG-056 | Close by Cancel, Esc, outside tap or ✕ → `?edit` removed. | – | none | – | orgs:146 |
| ADM-ORG-057 | (critic) Server slug rules (wizard create and edit): the client only checks "required"; the server refuses with 400 "That short name cannot be empty / has to be at least three characters / is too long for a web address / may only use lowercase letters, numbers and hyphens / cannot start or end with a hyphen / cannot start with "xn--" / cannot be only numbers / is reserved." (kind prefix stripped) → error toast. In the wizard this is a toast on step 3 (only a 409 jumps back to a field). An Arabic-only Organization Name slugifies to an empty Slug, so step 1 stops on "This field is required" under Slug until a Latin slug is typed. Other wizard 400s (unknown template, owner name/email, password under 8, PIN not 6 digits) also toast. | POST `/orgs/provision`, PATCH `/orgs/{id}` → 400 | srv: super admin | `common.requiredField` | pv:8-9,98-107, pw:84-91,159, MadarRust orgs/slugs.rs:139-176, orgs/provision.rs:205-256 |
| ADM-ORG-058 | (critic) Edit dialog re-fills every field from the server row whenever that row is refetched while the dialog is open: uploading or removing the logo refetches `/orgs*`, so anything typed but not yet saved is silently replaced by the stored values. Web quirk; keep or flag to the owner. | PUT `/orgs/{id}/logo`, PATCH `/orgs/{id}` `{logo_url: null}` | platform | – | od:94-117,183-194, orgs:41-46 |
| ADM-ORG-059 | (critic) Edit dialog validation differs from the wizard: Name, Slug and Currency are NOT trimmed (a space-only value passes and is sent); Slug is never slugified while editing (any text is sent; ORG-057 rules apply server-side). Wizard Email has autocomplete off and is checked untrimmed (a leading space reads "Enter a valid email"). | – | – | `common.requiredField`, `orgs.wizard.emailInvalid` | od:56-86,124-135, pw:254-256, pv:36-39 |

---

## 2. `/branches` Branches

### Header

| Field | Value |
|---|---|
| Web path | `/branches` (`?edit=<id>` edits, `?edit=new` creates; Dawam set-up links to `/branches?edit=new`) |
| Title | `branches.title` "Branches"; subtitle `branches.subtitle` "Manage your branch locations and printer config"; nav `nav.branches` "Branches" |
| Web files read | `routes/_app/branches.tsx`, `features/branches/{branches-page,branch-dialog,util}.ts(x)` + `branch-till-settings.test.ts`, `features/orgs/tax-rate.ts`, `features/users/row-action.tsx`, shared table/page/export/confirm/timezone components, `lib/format.ts` (`egpToPiastres`, `piastresToEgp`), `features/dawam/setup-steps.tsx` (link in) |
| Capabilities | Nav `branches.read`. No `<Restricted>`; New/Edit/Delete are NOT gated client-side. Tax override block: platform only. Server: list `branches.read`; create `branches.create`; PATCH `branches.edit`; DELETE `branches.delete`. |
| Module | none (untagged) |
| Realtime | `branch.settings_changed` refetches `/branches*` (this list) |
| Generated API hooks | `useListBranches` (listBranches), `deleteBranch`, `createBranch`, `patchBranch`, `useListTimezones` (listTimezones), `usePublicOrgBrand` (export logo) |
| Invalidation | Every mutation → `invalidateBranches()` = keys starting `/branches`. |

### Behaviours

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-BRA-001 | Nav leaf visible with `branches.read`. | – | `branches.read` | `nav.branches` "Branches" | nav:230 |
| ADM-BRA-002 | No org in scope (super admin, none picked): title + empty state (branch icon) "Select an organization" / "Choose an organization from the sidebar to view and manage its branches."; nothing fetched. | – | platform | `branches.title`, `branches.pickOrg` "Select an organization", `branches.pickOrgDescription` | bp:33,108 |
| ADM-BRA-003 | Header title, subtitle, actions Export + New. | – | none | `branches.title` "Branches", `branches.subtitle` | bp:112-116 |
| ADM-BRA-004 | Loads every branch of the org (unpaginated, inactive included). | GET `/branches?org_id=<org>` (listBranches) | srv: `branches.read` | – | bp:33-34 |
| ADM-BRA-005 | Stats: Total, Active, With Printer (`printer_brand` set), Inactive. | – | none | `common.total`, `common.active`, `branches.withPrinter` "With Printer", `common.inactive` | bp:117-122 |
| ADM-BRA-006 | Column Name (phone title): branch icon tile; name; address with a pin icon below when present. | – | none | `common.name` | bp:52-63 |
| ADM-BRA-007 | Column Phone: LTR, or "—". | – | none | `branches.phone` "Phone" | bp:64-67 |
| ADM-BRA-008 | Column Printer: printer icon, brand (capitalised) and `ip:port` in mono LTR; or muted "No printer". | – | none | `branches.printer` "Printer", `branches.noPrinter` "No printer" | bp:68-76 |
| ADM-BRA-009 | Column Status pill Active/Inactive. | – | none | `common.status`, `common.active`, `common.inactive` | bp:77-83 |
| ADM-BRA-010 | Search: name, and phone/printer brand when the first row has them (shared rules; address not searched). | – | none | `common.search` | bp:137 |
| ADM-BRA-011 | Columns menu (Name, Phone, Printer, Status); pagination 10; loading skeletons; phone cards. | – | none | `common.columns`, `common.page` | dt |
| ADM-BRA-012 | Error state + Retry. | GET `/branches` | none | `common.retry` | bp:127-128 |
| ADM-BRA-013 | Empty: "Branches you add appear here". | – | none | `branches.empty` "Branches you add appear here" | bp:138 |
| ADM-BRA-014 | Row click / Enter / Space → `?edit=<id>`. Row action Edit (pencil, "Edit") → same. | – | none | `common.edit` | bp:131,136 |
| ADM-BRA-015 | Row action Delete → confirm "Delete {{name}}?" / "Its tills, printer settings and stock levels go with it. Past orders stay in reports." (red Delete). | – | none | `branches.deleteTitle` "Delete {{name}}?", `branches.deleteDescription`, `common.delete` | bp:44-48,132 |
| ADM-BRA-016 | Delete confirmed: success → refetch `/branches*`, toast "Branch deleted"; failure → error toast. | DELETE `/branches/{id}` (deleteBranch) | srv: `branches.delete` | `branches.deletedToast` "Branch deleted" | bp:46 |
| ADM-BRA-017 | Refusal: New, Edit, Delete are shown to everyone who reaches the page; without the server capability the save/delete fails with the `errors.unauthorized` toast. | any write → 403 | srv | `errors.unauthorized` | bp:115,129-134 |
| ADM-BRA-018 | (corrected) Export Excel (disabled with no branches): `Madar-Branches-<YYYY-MM-DD>.xlsx`, sheet/title "Branches"; columns Name (w28), Address ("—" when none, w32), Phone ("—", w18), Timezone (w18), Printer ("<brand> @ <ip>:<port>" or "—", w26), Status (w12). Toasts come from the export engine (ADM-APP-126): loading "Gathering data…" → "Exported {{count}} rows", or "Export failed" on any failure — never `getErrorMessage` (the page's own catch is unreachable). | – (client file) | none | `common.export`, `branches.title`, `common.name`, `branches.address` "Address", `branches.phone`, `branches.timezone` "Timezone", `branches.printer`, `common.status` | bp:89-106 |
| ADM-BRA-019 | New → `?edit=new` → create dialog. Deep links `?edit=<id>` (after the list loads) and `?edit=new` open the dialog; closing removes `?edit`. | – | none | `common.new` | bp:39-42,115,140 |

#### Branch dialog

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-BRA-020 | Title "New Branch" / "Edit Branch"; description = page subtitle; fields reset from the branch each open (defaults below for new). | – | none | `branches.newTitle` "New Branch", `branches.editTitle` "Edit Branch", `branches.subtitle` | bd:87-116,161-164 |
| ADM-BRA-021 | Branch Name (required). | – | none | `branches.branchName` "Branch Name", `common.requiredField` | bd:44,167-173 |
| ADM-BRA-022 | Phone (optional; blank → null). | – | none | `branches.phone` | bd:175-177 |
| ADM-BRA-023 | Timezone searchable select, default Africa/Cairo, required. | GET `/timezones` (listTimezones) | none | `branches.timezone`, `common.selectTimezone`, `common.searchTimezone` | bd:47,178-180 |
| ADM-BRA-024 | "Flag open bills as old after (hours)": whole number 1..168, default 3. Out of range / fraction shows zod's own English message (no i18n key, section 9). | – | none | `branches.oldBillHours` "Flag open bills as old after (hours)" | bd:65,183-185, branch-till-settings.test.ts |
| ADM-BRA-025 | "Standard drawer float": number ≥ 0, step 0.01, typed in pounds (shown from piastres ÷100); sent as piastres (×100 rounded); blank → null. | – | none | `branches.standardFloat` "Standard drawer float" | bd:66,113,139,186-188 |
| ADM-BRA-026 | Address (optional; blank → null). | – | none | `branches.address` | bd:190-192 |
| ADM-BRA-027 | Printer box: Printer Model select None (no printer) / Star TSP100 / Epson TM-T88. | – | none | `branches.printerConfig` "Printer Configuration", `branches.printerBrand` "Printer Model", `branches.brands.none` "None (no printer)", `branches.brands.star` "Star TSP100", `branches.brands.epson` "Epson TM-T88" | bd:194-209 |
| ADM-BRA-028 | Printer IP (mono, placeholder 192.168.1.100) and Port (number, default 9100) appear only when a model is chosen; with None, brand/IP/port are sent as null. | – | none | `branches.printerIp` "Printer IP", `branches.printerPort` "Port" | bd:119-127,210-219 |
| ADM-BRA-029 | Location (geofencing) box: hint; Latitude, Longitude (any decimals, mono), Radius (m) default 200; blank → null. (Web quirk: a numeric box typed into then cleared coerces to 0, not null.) | – | none | `branches.location` "Location (geofencing)", `branches.geoHint` "Optional. Used to auto-resolve which branch a device is at.", `branches.latitude` "Latitude", `branches.longitude` "Longitude", `branches.geoRadius` "Radius (m)" | bd:52-54,128-130,222-236 |
| ADM-BRA-030 | Tax override (super admin only): switch "This branch taxes differently" + hint; on when the branch has any of the four overrides. | – | platform | `branches.taxOverride` "This branch taxes differently", `branches.taxOverrideHint` | bd:85,103-107,250-267 |
| ADM-BRA-031 | Override on: Tax rate (%) and Service charge (%) (0..100, percent on screen, fraction on the wire), switches "Menu prices include tax" and "Tax the service charge". Override off: all four sent as explicit null (branch inherits the org). For a non-super-admin the block is hidden and the stored values are re-sent unchanged. | – | platform | `orgs.taxRate`, `orgs.serviceCharge`, `orgs.taxInclusive`, `orgs.serviceChargeTaxable` | bd:59-63,131-137,269-300 |
| ADM-BRA-032 | Active switch (edit only) + hint. | – | none | `common.active`, `branches.activeHint` "Inactive branches are hidden from the POS." | bd:304-311 |
| ADM-BRA-033 | Save (edit): one PATCH with name, address, phone, timezone, printer fields, geo fields, tax overrides, `old_bill_hours`, `standard_float`, `is_active`; refetch `/branches*`; toast "Branch updated"; close. | PATCH `/branches/{id}` (patchBranch) | srv: `branches.edit` | `common.save`, `branches.updatedToast` "Branch updated" | bd:118-156 |
| ADM-BRA-034 | Create: POST without till settings, then PATCH the new branch with `{old_bill_hours, standard_float}`; refetch; toast "Branch created"; close. | POST `/branches` (createBranch) `{org_id, …}`, PATCH `/branches/{newId}` (patchBranch) | srv: `branches.create` + `branches.edit` | `common.create`, `branches.createdToast` "Branch created" | bd:143-147 |
| ADM-BRA-035 | Failure → error toast, dialog stays; Save spinner; Cancel disabled while saving. | – | – | `common.cancel` | bd:150-155,313-316 |
| ADM-BRA-036 | (critic) Create is two calls (POST, then PATCH of the till settings). If the PATCH fails the branch already exists: the error toast shows, the dialog stays in create mode and pressing Create again makes a SECOND branch. Web quirk; keep or flag. | POST `/branches`, PATCH `/branches/{newId}` | srv: `branches.create` + `branches.edit` | – | bd:143-155 |
| ADM-BRA-037 | (critic) A cleared number box coerces to 0, not empty: Port (sent as 0 when a printer model is chosen), Radius, Latitude/Longitude (BRA-029). A printer with a model but no IP reads ":9100" in the table and "<brand> @ null:9100" in the export. Phone is a plain text box (no LTR, no phone keyboard); fields sit in fixed 2-/3-column grids at every width. | – | none | – | bd:27,49-54,119-130,175-177,215-236, bp:70-74,95 |

---

## 3. `/devices` Devices

### Header

| Field | Value |
|---|---|
| Web path | `/devices`; `?view=clients` (Client versions), `?days=7\|30\|90` (14 = default, omitted), `?all=true` (all clients, not only legacy) |
| Title | `devices.title` "Devices"; subtitle `devices.subtitle` "POS, kitchen and waiter devices that have signed in at this branch." |
| Web files read | `routes/_app/devices.tsx`, `features/devices/{devices-page,activation-codes,api}.ts(x)` + tests (`devices-page.test.tsx`, `client-versions.test.tsx`, `activation-codes.test.ts`), `components/app/{segmented-control,ledger-strip,section-header,status-pill,data-table,empty-state,confirm-dialog}.tsx`, `lib/format.ts` (`fmtStamp`) |
| Capabilities | Nav `branches.edit` or `till.open`. No `<Restricted>`. Activation codes section: `branches.edit` (hidden and not fetched otherwise). Server: list devices `branches.read`; PATCH device `branches.edit`; client versions `branches.edit`; activation codes `branches.edit`. |
| Module | pos (module gate) |
| Realtime | none directly (`resync` only) |
| Generated API hooks | `useListDevices` (listDevices), `useUpdateDevice` (updateDevice), `useListClientVersions` (listClientVersions), `useListCodes` (listCodes), `useCreateCode` (createCode), `useRevokeCode` (revokeCode) |
| Invalidation | updateDevice → keys starting `/devices` and `/tills`; createCode, revokeCode → keys starting `/devices/activation-codes`. |

### Behaviours

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-DEV-001 | Nav leaf for `branches.edit` or `till.open`, POS orgs only. | – | `branches.edit` / `till.open`; module pos | `nav.devices` "Devices" | nav:231 |
| ADM-DEV-002 | Header + segmented control "Devices" / "Client versions"; the choice lives in the URL (`?view=clients`; Devices = no param). | – | none | `devices.title`, `devices.subtitle`, `devices.tabDevices` "Devices", `devices.clients.title` "Client versions" | dp:56-70 |
| ADM-DEV-003 | Devices view with no branch selected (All branches; also a branch manager arriving without `branchId` in the URL, who has no branch picker): empty state (tablet icon) with title `tills.pickBranch` and hint. | – | none | `tills.pickBranch` "Select a branch to view its tills", `devices.pickBranchHint` "Devices are registered per branch." | dp:78-79 |
| ADM-DEV-004 | Devices table for the selected branch; 20 per page; no search; no columns menu. | GET `/devices?branch_id=<id>` (listDevices) | srv: `branches.read` | – | dp:91-102,170-194, dapi:41-43 |
| ADM-DEV-005 | Column Code (phone title): code in mono bold; a warning pill "Another device uses this code" when `code_conflict`. | – | none | `devices.code` "Code", `devices.codeConflict` "Another device uses this code" | dp:120-137, devices-page.test.tsx |
| ADM-DEV-006 | Columns Name (label or "—"), Type (`devices.kinds.<kind>`, unknown kinds raw), App ("<platform> · <app_version>" or "—"). | – | none | `devices.label` "Name", `devices.kind` "Type", `devices.kinds.pos` "POS", `devices.kinds.kds` "Kitchen screen", `devices.kinds.waiter` "Waiter", `devices.app` "App" | dp:138-149 |
| ADM-DEV-007 | Column Status: neutral "Retired" when `retired_at`, else success "Active". Column Last seen: `fmtStamp` (numeric). | – | none | `common.status`, `devices.retired` "Retired", `devices.active` "Active", `devices.lastSeen` "Last seen" | dp:150-166 |
| ADM-DEV-008 | Loading skeleton; error state + Retry; empty "No devices yet" + "A device appears here the first time it signs in at this branch." | – | none | `devices.empty` "No devices yet", `devices.emptyHint` | dp:171-193 |
| ADM-DEV-009 | Row click or the pencil row action (aria "Edit") opens the Edit device dialog. | – | none | `common.edit` | dp:178-185 |
| ADM-DEV-010 | Edit device dialog: title + hint; Code (mono, uppercase, max 6), Name, Retired switch row with hint; Cancel / Save. | – | none | `devices.edit` "Edit device", `devices.editHint` "The code prefixes this device's order numbers, e.g. 36B-12.", `devices.code`, `devices.label`, `devices.retired`, `devices.retiredHint` "Its code is freed for another device and it leaves the availability lists.", `common.cancel`, `common.save` | dp:376-431 |
| ADM-DEV-011 | Code validation: trimmed, uppercased, must match `^[A-Z0-9]{1,6}$` else "1–6 letters or digits" under the field. | – | none | `devices.codeInvalid` "1–6 letters or digits" | dp:369-373,408-410, dapi:34 |
| ADM-DEV-012 | Save: `{code, label (trimmed, blank → null), retired}`; success → toast "Saved", close, refetch `/devices*` and `/tills*`; failure → error toast (e.g. code already taken). Save spinner. | PATCH `/devices/{id}` (updateDevice) | srv: `branches.edit` | `common.saved` "Saved" | dp:384-395, dapi:63-65 |
| ADM-DEV-013 | Refusal: someone with only `till.open` sees the devices list (server allows `branches.read`) and can open the dialog, but Save is refused (`errors.unauthorized` toast); the Activation codes section is absent. | PATCH → 403 | srv: `branches.edit` | `errors.unauthorized` | ac:44,94 |
| ADM-DEV-014 | Activation codes section (with `branches.edit`): key icon, title, subtitle, "New code" button. | GET `/devices/activation-codes?branch_id=<id>` (listCodes) | `branches.edit`; srv: `branches.edit` | `devices.activation.title` "Activation codes", `devices.activation.subtitle` "Enter a code on a new tablet to bind it to this branch. Each code works once, for 24 hours.", `devices.activation.issue` "New code" | ac:42-45,107-119 |
| ADM-DEV-015 | Codes table (newest first, 10 per page, no search/columns menu): Code grouped "4072 1958" in LTR mono (free codes bold; others struck through and muted); Name; Type; Status pill free→success "Free", used→neutral "Used", expired→warning "Expired", revoked→danger "Withdrawn"; Expires / used = `fmtStamp(used_at ?? revoked_at ?? expires_at)`. | – | `branches.edit` | `devices.activation.code` "Code", `devices.label`, `devices.kind`, `common.status`, `devices.activation.states.free` "Free", `.used` "Used", `.expired` "Expired", `.revoked` "Withdrawn", `devices.activation.when` "Expires / used" | ac:32-40,50-92,120-128, activation-codes.test.ts |
| ADM-DEV-016 | Codes loading / error + Retry / empty "No codes yet" + hint. | – | `branches.edit` | `devices.activation.empty` "No codes yet", `devices.activation.emptyHint` "Issue a code, then type it on the tablet you are setting up." | ac:122-143 |
| ADM-DEV-017 | Row action "Withdraw" (only on free codes) → confirm "Withdraw this code?" / "A tablet can no longer be activated with it." (red Withdraw). Confirmed → call; success refetches codes (row turns Withdrawn), no toast; failure → error toast. | POST `/devices/activation-codes/{id}/revoke` (revokeCode) | srv: `branches.edit` | `devices.activation.revoke` "Withdraw", `devices.activation.revokeTitle` "Withdraw this code?", `devices.activation.revokeBody` | ac:96-105,129-135, dapi:59-61 |
| ADM-DEV-018 | New code dialog: title + hint; Tablet name (optional, max 120, placeholder "Front counter"); Type select POS / Kitchen screen / Waiter (default POS); Cancel / New code. | – | `branches.edit` | `devices.activation.issueTitle` "New activation code", `devices.activation.issueHint`, `devices.activation.labelField` "Tablet name (optional)", `devices.activation.labelPlaceholder` "Front counter", `devices.kind`, `devices.kinds.*`, `common.cancel`, `devices.activation.issue` | ac:149-216 |
| ADM-DEV-019 | Issue: `{branch_id, label (blank → null), kind}`; success → the dialog swaps to the issued code, large, grouped, LTR, plus "Done" (closes and resets the form); codes list refetched; failure → error toast. Button spinner. | POST `/devices/activation-codes` (createCode) | srv: `branches.edit` | `common.done` "Done" | ac:161-191, dapi:55-57 |
| ADM-DEV-020 | Changing the branch in the scope bar refetches devices and codes for that branch. | GET `/devices`, GET `/devices/activation-codes` | none | – | dp:50,82-83 |
| ADM-DEV-021 | Client versions view: ledger strip with three figures: "Clients seen" = rows; "On legacy paths" = rows with `last_legacy_at` (warning tint when >0, success when 0); "App versions" = distinct non-empty `app_version`. | – | none | `devices.clients.seen` "Clients seen", `devices.clients.onLegacy` "On legacy paths", `devices.clients.versions` "App versions" | dp:209-223 |
| ADM-DEV-022 | Client versions read: works with a branch or org-wide (All branches → no `branch_id`, and a Branch column appears). | GET `/devices/client-versions?branch_id?&legacy_only=<bool>&days=<n>` (listClientVersions) | srv: `branches.edit` | `tills.branch` "Branch" | dp:210,229,291-293, dapi:46-48 |
| ADM-DEV-023 | Window select (aria "Window"): "Last {{count}} days" for 7, 14, 30, 90; 14 is the default and is not written to the URL. | – | none | `devices.clients.window` "Window", `devices.clients.lastDays` "Last {{count}} days" | dp:31,234-241 |
| ADM-DEV-024 | Switch "Legacy clients only" (default on); turning it off writes `?all=true`. | – | none | `devices.clients.legacyOnly` "Legacy clients only" | dp:242-245 |
| ADM-DEV-025 | Client table (20 per page): Device (device code in mono, or "Unregistered client"; client string LTR truncated with the full text on hover/hold); [Branch]; Version (mono, or "—"); Last seen (`fmtStamp`); Last legacy hit: none → success "Up to date"; else warning "Legacy" + time, the last legacy kind (mono) with "+N" when several kinds, the last legacy path (mono LTR truncated, full on hover/hold). | – | none | `devices.clients.device` "Device", `devices.clients.unregistered` "Unregistered client", `devices.clients.version` "Version", `devices.lastSeen`, `devices.clients.lastLegacy` "Last legacy hit", `devices.clients.upToDate` "Up to date", `devices.clients.legacy` "Legacy" | dp:273-338, client-versions.test.tsx |
| ADM-DEV-026 | Client empty states: legacy-only → check icon "No legacy clients" + "Nothing used a pre-rework path in the last {{count}} days."; all → history icon "No clients seen" + "No app has called the server in the last {{count}} days.". Loading / error + Retry. | – | none | `devices.clients.noLegacy`, `devices.clients.noLegacyHint`, `devices.clients.none`, `devices.clients.noneHint` | dp:340-366 |
| ADM-DEV-027 | Refusal: without `branches.edit` the Client versions read is refused → error state (`errors.unauthorized`) + Retry. | GET `/devices/client-versions` → 403 | srv: `branches.edit` | `errors.unauthorized` | MadarRust client_seen/handlers.rs:63 |
| ADM-DEV-028 | URL is validated: `view` other than `clients` ignored; `days` outside 7/14/30/90 ignored; `all` true only for `true`/"true". | – | none | – | dp:39-46, client-versions.test.tsx:48-51 |
| ADM-DEV-029 | (critic) The Edit device dialog is page state, not URL (no deep link; a reload closes it); it re-fills from the device on every open; Esc / outside / ✕ / Cancel close it; Cancel stays enabled while saving. | – | none | – | dp:53,86,376-431 |

---

## 4. `/access/users` Users (Access section)

### Header

| Field | Value |
|---|---|
| Web path | `/access/users` (`/access` redirects here). URL: `?edit=<id>\|new` user editor, `?branches=<id>` branch access, `?access=<id>` person's access sheet. Legacy `/users?edit&branches` redirects here. |
| Title | `users.title` "Users"; subtitle `users.subtitle` "Manage staff accounts and access"; section tab `nav.users` "Users"; nav `nav.usersPermissions` "Users & Permissions" |
| Web files read | `routes/_app/access/{route,index,users}.tsx`, `routes/_app/users.tsx`, `features/users/{users-page,user-dialog,branch-assign-dialog,row-action,util}.tsx` + `user-dialog.test.tsx`, `features/access/{person-access-sheet,capability-groups,catalog,limits-button}.ts(x)` + tests (`person-access-sheet.test.tsx`, `catalog.test.ts`, `limits-button.test.ts`), `features/dawam/add-employees.tsx` (entry only), `components/app/{page,section-tabs,segmented-control}.tsx`, `generated/capabilities.ts` |
| Capabilities | Nav `staff.users.read` or `staff.permissions.read`. No `<Restricted>`. Row actions: Manage permissions `staff.permissions.read`; Edit `staff.users.edit`; Delete `staff.users.delete`; Make employee = Dawam on + `hr.staff.create` + user linkable; Assign branches by the user's ROLE only. New: not gated. Server: list `staff.users.read`; create `staff.users.create`; PATCH `staff.users.edit`; DELETE `staff.users.delete`; branch assign/unassign `staff.permissions.edit`; PIN suggestion `staff.users.create`; access read `staff.permissions.read` or `.edit`; overrides `staff.permissions.edit`; assignments `staff.users.edit`; explain `staff.permissions.read`. |
| Module | none (Make employee needs Dawam on) |
| Realtime | none |
| Generated API hooks | `useListUsers` (listUsers), `deleteUser`, `createUser`, `updateUser`, `suggestPin`, `useListOrgs` (listOrgs), `useLinkableUsers` (linkableUsers), `useListBranches` (listBranches), `useListUserBranches` (listUserBranches), `assignBranch`, `unassignBranch`, `useUserAccess` (userAccess), `setOverride`, `setAssignments`, `explain`, `useListRoles` (listRoles); Add-employee dialog hooks belong to the team area. |
| Invalidation | User create/update/delete and branch toggles → `invalidateUsers()` = keys starting `/users`. Overrides and assignments → `getUserAccessQueryKey(userId)` = `['/authz/users/{id}']` (all branch variants). |

### Behaviours

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-USR-001 | Access section tabs under the page title (also on the Roles and Review pages and on their refusal screens): Users, Roles & Permissions, Review (Review only with `approvals.review`). Active tab underlined; tabs keep only scope params (page params reset when switching); the tab bar scrolls sideways on narrow screens. | – | Review tab: `approvals.review` | `nav.users` "Users", `nav.rolesPermissions` "Roles & Permissions", `access.review.title` "Review" | raccess:14-28, components/app/page.tsx:80-128 |
| ADM-USR-002 | Nav leaf for `staff.users.read` or `staff.permissions.read`. | – | caps | `nav.usersPermissions` "Users & Permissions" | nav:232 |
| ADM-USR-003 | Header title, subtitle; actions Export + New. | – | none | `users.title` "Users", `users.subtitle` "Manage staff accounts and access" | up:137-141 |
| ADM-USR-004 | No org in scope (super admin, none picked): title + empty state "Select an organization" (no description). | – | platform | `users.pickOrg` "Select an organization" | up:116 |
| ADM-USR-005 | Loads every account of the org. | GET `/users?org_id=<org>` (listUsers) | srv: `staff.users.read` | – | up:42-43 |
| ADM-USR-006 | Stats: Total Users; Org Admins (`org_admin`); Branch managers (`branch_manager`); Tellers (`teller`). | – | none | `users.totalUsers` "Total Users", `users.orgAdmins` "Org Admins", `users.branchManagers` "Branch managers", `users.tellers` "Tellers" | up:71,142-147 |
| ADM-USR-007 | Columns: Name (phone title: initials avatar, name, email or "—"); Phone (LTR or "—"); Role badge (`roles.<role>`); Status pill. | – | none | `common.name`, `users.phone` "Phone", `users.role` "Role", `roles.*`, `common.status`, `common.active`, `common.inactive` | up:73-96 |
| ADM-USR-008 | Search: name, phone (when the first row has one) and the RAW role value (e.g. "branch_manager", not the translated label); email not searched. | – | none | `common.search` | up:157 |
| ADM-USR-009 | Columns menu; pagination 10; skeletons; error + Retry; phone cards. | – | none | `common.columns`, `common.page`, `common.retry` | dt |
| ADM-USR-010 | Empty: "Staff accounts you add appear here". | – | none | `users.empty` "Staff accounts you add appear here" | up:158 |
| ADM-USR-011 | Row click / Enter / Space → `?edit=<id>` for EVERYONE (only the pencil is gated); without `staff.users.edit` the Save is refused by the server. | – | none (srv `staff.users.edit`) | – | up:156 |
| ADM-USR-012 | Row action Manage permissions (shield, "Manage permissions") with `staff.permissions.read` → `?access=<id>` → access sheet. | – | `staff.permissions.read` | `users.permissions` "Manage permissions" | up:122-124 |
| ADM-USR-013 | Row action Assign branches (branch icon) only for users whose role is branch_manager, teller, waiter or kitchen (no capability check) → `?branches=<id>`. | – | role of the row | `users.assignBranches` "Assign branches" | up:119,125 |
| ADM-USR-014 | Row action Make employee (briefcase) only when the org has Dawam, the viewer holds `hr.staff.create`, and the user is in the linkable list → opens the Add employee dialog preset to "link this user" (dialog behaviour: team area inventory). Closing clears it. | GET `/staff/employees/linkable` (linkableUsers) only when allowed | module dawam + `hr.staff.create` | `dawam.makeEmployee` "Make employee" | up:56-63,126-128,162 |
| ADM-USR-015 | Row action Edit (pencil) with `staff.users.edit` → `?edit=<id>`. | – | `staff.users.edit` | `common.edit` | up:129 |
| ADM-USR-016 | Row action Delete (red trash) with `staff.users.delete` → confirm "Delete {{name}}'s account?" / "They can no longer sign in to the dashboard or the POS. Their past orders and tills stay on record." → call; success refetch `/users*` + toast "User deleted"; failure toast. | DELETE `/users/{id}` (deleteUser) | `staff.users.delete`; srv same | `users.deleteTitle` "Delete {{name}}'s account?", `users.deleteDescription`, `common.delete`, `users.deletedToast` "User deleted" | up:65-69,130 |
| ADM-USR-017 | (corrected) Export Excel (disabled with no users): `Madar-Users-<YYYY-MM-DD>.xlsx`, sheet/title "Users"; columns Name (w28), Email (header "Email address", "—", w30), Phone ("—", w18), Role (translated, w18), Status (w12). Toasts come from the export engine (ADM-APP-126): loading "Gathering data…" → "Exported {{count}} rows", or "Export failed" on any failure — never `getErrorMessage` (the page's own catch is unreachable). | – (client file) | none | `common.export`, `users.title`, `common.name`, `auth.email` "Email address", `users.phone`, `users.role`, `common.status` | up:98-114 |
| ADM-USR-018 | New (not gated) → `?edit=new`. | – | none (srv `staff.users.create`) | `common.new` | up:140 |
| ADM-USR-019 | (corrected) Deep links `?edit`, `?branches`, `?access` open their dialog/sheet once the list has the id; closing removes the param. The URL bypasses the row-action gates: `?edit` opens for anyone (USR-011), `?access` without `staff.permissions.read` (USR-051), `?branches` for an account of any role (USR-052). | – | none | – | routes/_app/access/users.tsx:4-13, up:49-54,160-163 |

#### User dialog (create / edit)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-USR-020 | Dialog title "New User" / "Edit User", description "Manage staff accounts and access"; reset on open (role default teller; PIN and password always start blank). | – | none | `users.newTitle` "New User", `users.editTitle` "Edit User", `users.subtitle` | ud:99-113,168-171 |
| ADM-USR-021 | Full Name (required). | – | none | `users.fullName` "Full Name", `common.requiredField` | ud:59,174-176 |
| ADM-USR-022 | Role select. Options by the viewer's role: super admin → all six; branch manager → Teller, Waiter, Kitchen; anyone else → all but Super Admin. | – | viewer role | `users.role`, `roles.*` | ud:22,50-53,180-189 |
| ADM-USR-023 | Super admin creating: an Organization select (all orgs, default the current one) beside Role, and Phone moves to its own row. Everyone else / editing: Phone beside Role. | GET `/orgs` (listOrgs) when super admin + create | platform | `users.org` "Organization", `users.phone` | ud:48,190-211 |
| ADM-USR-024 | PIN field: label "PIN (6 digits)" for teller/waiter/kitchen, else "Till PIN (optional)"; numeric keyboard, non-digits dropped as typed, max 6; placeholder "••••••" when editing; if given must be 6 digits ("PIN must be 6 digits"); creating a till role without a PIN → "PIN is required". | – | none | `users.pin6` "PIN (6 digits)", `users.pinOptional` "Till PIN (optional)", `users.pinError6` "PIN must be 6 digits", `users.pinRequired` "PIN is required" | ud:67,74-77,214-227 |
| ADM-USR-025 | Generate (outline, beside PIN): asks the server for a free PIN, fills it and validates; spinner; failure toast. | GET `/users/pin-suggestion` (suggestPin) | srv: `staff.users.create` | `users.generatePin` "Generate" | ud:149-160,221-223, user-dialog.test.tsx:79-88 |
| ADM-USR-026 | Email: label "Email (optional)" for till roles, else "Email address"; malformed → "Invalid email"; required for non-till roles ("Email is required"); a till role with a password but no email → "Email is required". | – | none | `users.emailOptional` "Email (optional)", `auth.email`, `common.invalidEmail` "Invalid email", `users.emailRequired` "Email is required" | ud:60,78-84,229-235 |
| ADM-USR-027 | Password: label "Password (optional)" for till roles, else "Password"; placeholder "Leave blank to keep" when editing; creating a non-till role without one → "Password is required". No client length rule. | – | none | `users.passwordOptional` "Password (optional)", `auth.password`, `users.leaveBlank` "Leave blank to keep", `users.passwordRequired` "Password is required" | ud:85-87,236-242 |
| ADM-USR-028 | Hint under the credentials by role. | – | none | `users.posCredHint2` "The PIN signs them in at a till. Add an email and password only if they also use the dashboard.", `users.dashCredHint2` "The email and password sign them in to the dashboard. Add a PIN if they also work a till." | ud:244-248 |
| ADM-USR-029 | Active Account switch (edit only) + hint. | – | none | `users.activeAccount` "Active Account", `users.activeHint` "Inactive users cannot log in" | ud:249-256 |
| ADM-USR-030 | Create: `{name, role, org_id (super admin's pick, else current org), email or null, phone or null, pin?, password?}` (both credentials sent when both filled); refetch `/users*`; toast "User created"; close. | POST `/users` (createUser) | srv: `staff.users.create` | `common.create`, `users.createdToast` "User created" | ud:115-144, user-dialog.test.tsx:64-77 |
| ADM-USR-031 | Edit: `{name, email or null, phone or null, role, is_active, pin?, password?}` (blank credentials omitted = keep); refetch; toast "User updated"; close. | PATCH `/users/{id}` (updateUser) | srv: `staff.users.edit` | `common.saveChanges` "Save Changes", `users.updatedToast` "User updated" | ud:126-130,260 |
| ADM-USR-032 | Failure (duplicate email, PIN in use, refusal) → error toast, dialog stays; submit spinner. | – | – | `common.cancel` | ud:139-143,258-261 |

#### Branch access dialog (`?branches=<id>`)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-USR-033 | Title "Branch Access", description "Toggle branch access for {{name}}". | – | role of the row | `users.branchAccess` "Branch Access", `users.branchAccessHint` "Toggle branch access for {{name}}" | ba:44-50 |
| ADM-USR-034 | Loads the user's org branches and their current assignments; two skeleton rows while loading; no branches → "No results found". (A failed assignments read shows every switch off.) | GET `/branches?org_id=<user org>` (listBranches), GET `/users/{id}/branches` (listUserBranches) | srv: `staff.users.read` | `common.noResults` "No results found" | ba:27-31,51-56 |
| ADM-USR-035 | One row per branch: name, address, switch on when assigned. Turning on assigns, off unassigns; then refetch assignments and `/users*`; no success toast; failure toast and the switch stays as it was. | POST `/users/{id}/branches` (assignBranch) `{branch_id}` / DELETE `/users/{id}/branches/{branchId}` (unassignBranch) | srv: `staff.permissions.edit` | – | ba:33-42,57-68 |
| ADM-USR-036 | Done closes (removes `?branches`). | – | none | `common.done` "Done" | ba:71-73 |

#### Person access sheet (`?access=<id>`)

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-USR-037 | Side sheet from the end edge (full width on phone, up to 672 px), title "{{name}}'s access", description. | – | `staff.permissions.read` | `access.personTitle` "{{name}}'s access", `access.personHint` "Their roles give them a starting point. Allow or deny single things here." | pas:111-117 |
| ADM-USR-038 | Loads the person's access for All branches (or the chosen branch); six skeleton rows while loading; a failed read leaves the body EMPTY (no error text, web behaviour). | GET `/authz/users/{id}[?branch_id=]` (userAccess); GET `/branches?org_id=` (listBranches) | srv: `staff.permissions.read` or `.edit` | – | pas:46-50,119-121 |
| ADM-USR-039 | (corrected) Locked: when the server says `can_edit=false` a note with a lock shows `locked_reason ?? access.locked`. `locked_reason` is a MACHINE CODE, always present when locked: `self` (your own access), `owner`, `not_dominant`, `not_above`, `missing_authority` (viewer lacks `staff.permissions.edit`) — and the web prints it raw (e.g. "missing_authority"), so the sentence "You can't change this person's access." practically never shows. Port: owner decision (copy the raw code or word it). Every editor below is inert. | – | srv | `access.locked` "You can't change this person's access." | pas:123-128 |
| ADM-USR-040 | Roles card: heading "Roles"; each assignment = role name (English or Arabic by language) and "All branches" or the branch names joined with "، " (Arabic comma, in both languages); none → "No roles". Edit button when editable. | – | `can_edit` | `access.roles` "Roles", `access.allBranches` "All branches", `access.noRolesHeld` "No roles", `common.edit` | pas:217-237 |
| ADM-USR-041 | Roles edit mode: every role except owner-kind roles, each with a checkbox; a ticked role shows "All branches" and, when that is off, one checkbox per branch. Cancel leaves without saving. | GET `/authz/roles` (listRoles) | `can_edit` | `access.allBranches`, `common.cancel` | pas:193-201,238-289 |
| ADM-USR-042 | Save roles: `{assignments:[{role_id, all_branches, branch_ids (empty when all)}]}`; leave edit mode; refetch access; no toast; failure → error toast (stays in edit). Save disabled while saving. | PUT `/authz/users/{id}/assignments` (setAssignments) | srv: `staff.users.edit` | `common.save` | pas:202-215,285-288 |
| ADM-USR-043 | "Where" select: All branches + each branch; changes which branch the list reads and which branch an Allow/Deny applies to. | GET `/authz/users/{id}?branch_id=` | none | `access.where` "Where", `access.allBranches` | pas:41-46,139-149 |
| ADM-USR-044 | Reason (optional) box (max 200) with hint; never required; sent trimmed (or null) with each change. | – | none | `access.reason` "Reason (optional)", `access.reasonHint` "Only if you want a note in the history. Nothing here is ever required." | pas:150-164, person-access-sheet.test.tsx:88-133 |
| ADM-USR-045 | Capability list (shown once the viewer's own authz is ready): registry groups in order, group heading EN/AR, rows = capability name + hint EN/AR; legacy capabilities never shown; advanced ones behind a collapsed "Advanced (N)" section (chevron). | – | none | `access.advanced` "Advanced" | pas:167, cg:28-89, cat:33-43, catalog.test.ts |
| ADM-USR-046 | Row control by source: `core` → "Always on" badge with lock; `owner` → "Owner" text; otherwise a 3-way segmented control: "Role: on" (or "Role: off" when no role grants it) / "Allow" / "Deny", selected = this person's override at the chosen branch, else the role option. Each row also has a Why? button. | – | none | `access.alwaysOn` "Always on", `access.owner` "Owner", `access.inheritOn` "Role: on", `access.inheritOff` "Role: off", `access.allow` "Allow", `access.deny` "Deny" | pas:72-109, cg:13-21 |
| ADM-USR-047 | Choosing Role/Allow/Deny: `{capability, effect: inherit\|allow\|deny, branch_id or null, reason or null, limits: null}`; refetch access; no toast; failure → error toast. Inert (no call) when the sheet is locked, the row is not editable, or that row is saving. | PUT `/authz/users/{id}/overrides` (setOverride) | srv: `staff.permissions.edit` | – | pas:54-70,90-102 |
| ADM-USR-048 | Limits button (capabilities with limits that are currently effective): ghost "Limit", or "Limited" when any limit (incl. own-only) is set. Popover: "Only their own" switch (if allowed); one number field per allowed limit — "Most per action (EGP)", "Most per action (%)", "Most per action", "Within minutes of the sale" — placeholder "No limit", digits and "." only; the over-limit sentence for the capability; Save. Save sends Allow with the limits and closes the popover. Money and value typed in pounds → ×100; percent → ×100 (basis points); minutes ×1; blank → null. | PUT `/authz/users/{id}/overrides` (setOverride) `{effect: "allow", limits}` | srv: `staff.permissions.edit` | `access.limit` "Limit", `access.limited` "Limited", `access.ownOnly` "Only their own", `access.maxAmount` "Most per action (EGP)", `access.maxPercent` "Most per action (%)", `access.maxValue` "Most per action", `access.maxAgeMinutes` "Within minutes of the sale", `access.noLimit` "No limit", `access.overLimitHint` "Over a limit, the till asks a manager.", `access.overLimitWaits` "Over the limit, it waits for someone with a higher limit, usually the owner.", `access.overLimitRefused` "Over the limit, it is refused.", `common.save` | pas:103-105, lb:20-123, limits-button.test.ts, person-access-sheet.test.tsx:107-158 |
| ADM-USR-049 | Why? (help icon, aria "Why?") popover: on every open asks the server; skeleton while loading; then the capability name, "Allowed"/"Not allowed", and the steps in words (owner, inactive, core role, role allows / does not allow / not at this branch, allowed / denied for this person, protected, limit, ask a manager, result not allowed; an unknown step kind shows raw). Failure → error toast. | GET `/authz/explain?user_id&capability[&branch_id]` (explain) | srv: `staff.permissions.read` | `access.why` "Why?", `access.resultAllowed` "Allowed", `access.resultNotAllowed` "Not allowed", `access.whyOwner` "Owner: holds everything", `access.whyInactive` "The account is switched off", `access.whyCore` "{{role}}: always on for this role", `access.whyNotHere` "{{role}}: not at this branch", `access.whyRoleGrants` "{{role}}: allows it", `access.whyRoleNot` "{{role}}: does not allow it", `access.whyAllow` "Allowed for this person", `access.whyDeny` "Denied for this person", `access.whyProtected` "An owner can never lose this", `access.whyLimit` "Allowed up to a limit", `access.whyAsk` "Can ask a manager to approve", `access.whyNotHeld` "Result: not allowed" | pas:295-358 |
| ADM-USR-050 | Closing the sheet removes `?access`. | – | none | – | up:161 |
| ADM-USR-051 | (critic) `?access=<id>` by URL opens the person's access sheet for ANYONE who reaches the page — only the shield row action checks `staff.permissions.read`. Without the capability the access read is refused (403) and the sheet body stays empty (USR-038). | GET `/authz/users/{id}` → 403 | by URL: none; srv: `staff.permissions.read` or `.edit` | – | up:50,122-124,161 |
| ADM-USR-052 | (critic) `?branches=<id>` by URL opens Branch Access for any account in the list, whatever its role (the branch_manager/teller/waiter/kitchen rule only decides whether the row action shows). | – | by URL: none | – | up:54,119-125,163 |
| ADM-USR-053 | (critic) Editing someone whose role is outside the viewer's options (a branch manager editing an Org Admin; an org admin editing a Super Admin) shows an EMPTY Role select (the value has no option); Save sends the stored role unchanged. The User dialog's Cancel stays enabled while saving; Full Name is not trimmed; Phone is plain text (no LTR). | – | viewer role | – | ud:50-53,101-110,180-189,202-210,258-261 |
| ADM-USR-054 | (critic) Server refusals the User dialog toasts (kind prefix stripped): 409 "Someone in this organization already uses that PIN", "Email already in use", "A teller, waiter or kitchen user with this name already exists in this organization"; 400 "A new PIN must be 6 digits", "Tellers, waiters and kitchen users require a PIN", "Admins and managers require a password", "Admins and managers require an email"; Generate with no org in scope → 400 "Choose an organization first". Every 403 (own role/deactivate self, user outside your branches, delete yourself) → `errors.unauthorized` (ADM-APP-133). | POST `/users`, PATCH `/users/{id}`, DELETE `/users/{id}`, GET `/users/pin-suggestion` | srv | `errors.unauthorized` | ud:139-160, up:65-69, MadarRust users/handlers.rs:23-31,61-63,88-95,246-320,594-616,749-765 |
| ADM-USR-055 | (critic) Branch Access details: a failed branches read shows the same "No results found" line (no error state); a switch is not disabled while its call runs (a second tap sends a second call); refusals ("You cannot assign a user to a branch you are not assigned to") are 403 → `errors.unauthorized`. | POST `/users/{id}/branches`, DELETE `/users/{id}/branches/{branchId}` | srv: `staff.permissions.edit` | `common.noResults`, `errors.unauthorized` | ba:27-42,51-69 |
| ADM-USR-056 | (critic) Access-editor refusals (Role/Allow/Deny, limits, role assignments): the server's guards — editing yourself, granting what you don't hold, a limit above your own, changing an owner, a person whose role is not below yours, someone who can do things you can't — are uncoded 403s, so each failed change toasts `errors.unauthorized`; nothing is optimistic, so the control keeps the server's state. | PUT `/authz/users/{id}/overrides`, PUT `/authz/users/{id}/assignments` → 403 | srv | `errors.unauthorized` | pas:54-70,202-215, MadarRust authz/api.rs:340-361 |
| ADM-USR-057 | (critic) Why? popover failure: error toast, and the popover keeps its skeleton until it is closed and reopened (which asks again). | GET `/authz/explain` → error | – | – | pas:302-311,342-344 |
| ADM-USR-058 | (critic) Sheet state: the Reason text is NOT cleared after a change — it rides every following Role/Allow/Deny/limit change until edited; Where and Reason reset only when the sheet is closed and reopened. A capability the server's answer does not list shows its name and hint with no control. On a locked sheet the 3-way controls look enabled but taps do nothing (no disabled styling). | – | – | – | pas:41-44,54-63,77-79,90-102 |

---

## 5. `/access/roles` Roles & Permissions

### Header

| Field | Value |
|---|---|
| Web path | `/access/roles`; `?role=<id>` selects the role; `?user=<id>` (old links, incl. `/permissions?user=`) accepted and ignored |
| Title | `nav.rolesPermissions` "Roles & Permissions"; subtitle `access.rolesSubtitle` "What each role may do. Change one person's access from Users." |
| Web files read | `routes/_app/access/roles.tsx`, `routes/_app/permissions.tsx`, `features/access/{roles-page,role-dialog,ask-manager-card,capability-groups,catalog,limits-button}.ts(x)` + `catalog.test.ts`, `components/app/{restricted,list-row,empty-state,confirm-dialog,segmented-control}.tsx`, `generated/capabilities.ts` (`ROLE_KIND_LABELS`, registry) |
| Capabilities | Page: `<Restricted>` once authz is ready unless `staff.permissions.read` or `staff.roles.manage` (roles are not fetched without them). Changing anything: `staff.roles.manage`. Server: list roles `staff.permissions.read` or `staff.roles.manage`; create/rename/delete/grants/policy write `staff.roles.manage`; policy read: any member. |
| Module | none |
| Realtime | none |
| Generated API hooks | `useListRoles` (listRoles), `setRoleGrant`, `deleteRole`, `createRole`, `renameRole`, `useGetPolicy` (getPolicy), `setPolicy` |
| Invalidation | grant/delete/create/rename → `getListRolesQueryKey()` = `['/authz/roles']`; setPolicy → `getGetPolicyQueryKey()` = `['/authz/policy']`. |

### Behaviours

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-ROL-001 | Refusal: authz ready and neither capability held → section tabs + lock empty state "Not available on this account" / "Only people who can see permissions can open this page."; roles never fetched. | – | `staff.permissions.read` or `staff.roles.manage` | `nav.rolesPermissions`, `common.restrictedTitle` "Not available on this account", `access.noAccess` "Only people who can see permissions can open this page." | rp:39-51, components/app/restricted.tsx:18-32 |
| ADM-ROL-002 | Header title + subtitle; "New role" button only with `staff.roles.manage`. | – | `staff.roles.manage` (button) | `access.rolesSubtitle`, `access.newRole` "New role" | rp:117-129 |
| ADM-ROL-003 | Layout: roles list (280 px) beside the selected role from 1024 px; stacked (list above) below. | – | none | – | rp:130 |
| ADM-ROL-004 | Roles list loading: five skeleton rows. | GET `/authz/roles` (listRoles) | srv: read caps | – | rp:43,132-133 |
| ADM-ROL-005 | Roles list error: "Couldn't load roles" + Retry (spinner while refetching). | – | – | `access.rolesLoadError` "Couldn't load roles", `common.retry` | rp:134-135 |
| ADM-ROL-006 | Roles list empty: shield icon "No roles yet". | – | – | `access.noRoles` "No roles yet" | rp:136-137 |
| ADM-ROL-007 | Role rows: name (EN or AR by language) and "<works-like label> · {{count}} person/people"; the selected row highlighted. Tap → `?role=<id>`. | – | none | `access.members` "{{count}} person" / "{{count}} people" (plural) | rp:53-57,138-150 |
| ADM-ROL-008 | Default selection: the `?role` match, else the first role of kind branch_manager, else the first role. | – | none | – | rp:45 |
| ADM-ROL-009 | Selected role card: name; sub-line "Works like {{kind}} on older tablets" (editable roles) or "The owner can do everything. This role cannot be changed." (owner role); "Built in" badge for system roles. | – | none | `access.behavesLike` "Works like {{kind}} on older tablets", `access.ownerHoldsAll`, `access.builtIn` "Built in" | rp:154-166 |
| ADM-ROL-010 | Rename (outline, pencil) with `staff.roles.manage` → rename dialog. | – | `staff.roles.manage` | `access.rename` "Rename" | rp:167-172 |
| ADM-ROL-011 | Delete (outline, trash) only with `staff.roles.manage` on non-system roles; disabled while anyone holds the role. Confirm "Delete this role?" / "Nobody holds it. This cannot be undone." (red Delete). | – | `staff.roles.manage`; not system; members = 0 | `common.delete`, `access.deleteRoleTitle` "Delete this role?", `access.deleteRoleBody` | rp:72-87,173-178 |
| ADM-ROL-012 | Delete confirmed: removes `?role` (falls back to the default selection), refetches roles; no toast; failure → error toast. | DELETE `/authz/roles/{id}` (deleteRole) | srv: `staff.roles.manage` | – | rp:80-86 |
| ADM-ROL-013 | Capability groups for an editable role (absent for the owner role): same grouping, names, hints and Advanced section as ADM-USR-045. | – | none | `access.advanced` | rp:181, cg |
| ADM-ROL-014 | Row control: capability core for this role's kind → "Always on" badge; otherwise a switch (aria-label = the capability key), on when granted (core grants of the kind count as held). Disabled without `staff.roles.manage`, for non-editable roles, or while that row saves. | – | `staff.roles.manage` | `access.alwaysOn` | rp:89-114, cat:30-31,60-64 |
| ADM-ROL-015 | Toggling: `{capability, granted}`; refetch roles; no toast; failure → error toast (switch returns). | PUT `/authz/roles/{id}/grants` (setRoleGrant) | srv: `staff.roles.manage` | – | rp:60-70 |
| ADM-ROL-016 | Limits button before the switch on granted capabilities that take limits (same popover as ADM-USR-048); Save sends `{capability, granted: true, limits}`. | PUT `/authz/roles/{id}/grants` | `staff.roles.manage` | `access.limit`, `access.limited`, … | rp:97-105 |
| ADM-ROL-017 | New role dialog: Name (English, LTR) and Name (Arabic, RTL) — each required, 1..80 chars trimmed (zod's own English messages, section 9); "Works like" select Branch manager / Teller / Waiter / Kitchen (EN/AR registry labels, default Teller); "Start from" select "The usual defaults" + existing roles of the chosen kind. Cancel / Save (disabled while submitting). | – | `staff.roles.manage` | `access.newRole`, `access.nameEn` "Name (English)", `access.nameAr` "Name (Arabic)", `access.kind` "Works like", `access.copyFrom` "Start from", `access.copyDefaults` "The usual defaults", `common.cancel`, `common.save` | rd:19-154 |
| ADM-ROL-018 | Create: `{name_en, name_ar, kind, copy_from or null}`; success closes, selects the new role (`?role=<id>`), refetches; failure → error toast. Rename dialog (title "Rename role", names only): `{name_en, name_ar}`, same success path. | POST `/authz/roles` (createRole); PATCH `/authz/roles/{id}` (renameRole) | srv: `staff.roles.manage` | `access.renameRole` "Rename role" | rd:57-71, rp:186-198 |
| ADM-ROL-019 | (corrected) Ask-a-manager card (only with `staff.roles.manage`, only if the registry has approval capabilities, and only while a role is selected — it renders under the selected role, see ROL-022): heading "When someone isn't allowed" + hint. | GET `/authz/policy` (getPolicy) | `staff.roles.manage` | `access.askTitle` "When someone isn't allowed", `access.askHint` "Hide the action, or let them ask a manager to approve it with their PIN." | rp:182, amc:20-47 |
| ADM-ROL-020 | Policy rows: one per approval capability (registry `approval` and not legacy), name EN/AR, segmented "Hidden" / "Ask a manager" (current from the policy list). Loading: one skeleton per capability. | – | `staff.roles.manage` | `access.hidden` "Hidden", `access.askManager` "Ask a manager" | amc:24-26,48-65, cat:56-57, catalog.test.ts:28 |
| ADM-ROL-021 | Changing a policy row: `{capability, ask_manager}`; refetch policy; no toast; failure → error toast; ignored while that row saves. | PUT `/authz/policy` (setPolicy) | srv: `staff.roles.manage` | – | amc:28-38,57 |
| ADM-ROL-022 | (critic) Ask-a-manager card placement: it renders under the selected role's capability list, so it is absent while roles load and when the list is empty or failed, and it shows (the same business-wide policy) under every selected role, the owner role included. A failed policy read shows every row as "Hidden" (no error state); the segmented control is not disabled while a row saves (taps ignored). | GET `/authz/policy` (getPolicy) | `staff.roles.manage` | `access.hidden` | rp:154-183, amc:22-66 |
| ADM-ROL-023 | (critic) Role server refusals (toasts): a grant on the owner role 409 "The owner role holds everything and cannot be edited"; delete 409 "Built-in roles cannot be deleted" / "People still hold this role. Move them to another role first."; create/rename 400 "A role needs an English and an Arabic name", "kind must be branch_manager, teller, waiter or kitchen"; guard refusals (granting what you don't hold, a limit above your own) are uncoded 403 → `errors.unauthorized`. Rename is offered for every role (built-in and owner included) and the server allows it. | PUT `/authz/roles/{id}/grants`, DELETE / POST / PATCH `/authz/roles…` | srv: `staff.roles.manage` | `errors.unauthorized` | rp:60-87,167-178, MadarRust authz/api.rs:560-590,640-670,686-730,752-772 |
| ADM-ROL-024 | (critic) New role dialog: changing "Works like" does not clear "Start from" — a role of another kind picked earlier stays chosen (the select then shows blank) and is still sent as `copy_from`. No description line under the title; Save is disabled while submitting (no spinner); Cancel stays enabled; the dialog starts blank (rename: prefilled names) each time it opens. | POST `/authz/roles` (createRole) | `staff.roles.manage` | – | rd:46-66,103-148 |

---

## 6. `/access/review` Review

### Header

| Field | Value |
|---|---|
| Web path | `/access/review` (no URL params) |
| Title | `access.review.title` "Review"; description `access.review.subtitle` "Offline acts the permission check did not back, and PINs tried at the wrong branch." |
| Web files read | `routes/_app/access/review.tsx`, `features/access/{review-page,flag-detail,catalog}.ts(x)` + `review-page.test.tsx` |
| Capabilities | Tab shown only with `approvals.review`. The page itself has no guard: anyone reaching the URL triggers the list read, which the server refuses without `approvals.review`. Picking and resolving: `approvals.review`. Server: list/review/bulk `approvals.review`. |
| Module | none |
| Realtime | none |
| Generated API hooks | `useListFlags` (listFlags), `useReviewFlag` (reviewFlag), `useBulkReviewFlags` (bulkReviewFlags) |
| Invalidation | review and bulk review → every key starting `/authz/flags`. |

### Behaviours

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-REV-001 | Review tab visible only with `approvals.review` (ADM-USR-001). | – | `approvals.review` | `access.review.title` | raccess:16-23 |
| ADM-REV-002 | Header title + description. | – | none | `access.review.title` "Review", `access.review.subtitle` | rv:184-188 |
| ADM-REV-003 | Loads flags (open only by default). | GET `/authz/flags` (listFlags) | srv: `approvals.review` | – | rv:51 |
| ADM-REV-004 | Refusal: without `approvals.review` no checkbox column, no bulk bar, no "Mark reviewed"; the read is refused → table error state (`errors.unauthorized`) + Retry. | GET `/authz/flags` → 403 | `approvals.review` | `errors.unauthorized` | rv:47,107-132,236-246, review-page.test.tsx:84-90 |
| ADM-REV-005 | Toolbar switch "Show reviewed" (off by default): on → `include_reviewed=true` and reviewed flags join the list. | GET `/authz/flags?include_reviewed=true` | none | `access.review.showReviewed` "Show reviewed" | rv:48,51,200-203 |
| ADM-REV-006 | Columns (20 per page, no search, no columns menu): [pick, with `approvals.review`, hidden on phone]; Person (author name or "—", phone title); What happened; Permission; When (`fmtStamp(occurred_at)`). | – | none | `access.review.person` "Person", `access.review.what` "What happened", `access.review.permission` "Permission", `access.review.when` "When" | rv:105-181,189-197 |
| ADM-REV-007 | What happened, plain flag: pill with the reason's words and tone — `stale_snapshot` info, `unauthorized_offline` danger, `pin_wrong_branch` warning, unknown reason neutral showing the raw value. | – | none | `access.review.reasons.stale_snapshot` "Done offline before a permission change reached the till", `access.review.reasons.unauthorized_offline` "Done offline without the permission", `access.review.reasons.pin_wrong_branch` "Correct PIN at a branch they don't work at" | rv:34-42,154-158 |
| ADM-REV-008 | What happened, staff-drink detail (`orders.staff_drink.record:<detail>`): the detail's sentence in a wrapping pill with its tone — comp_mismatch warning, overspent warning, device_overcounted info, duplicate_id warning, pool_off danger, no_eligible_items danger, item_not_eligible danger, note_required warning. Any other `cap:detail` keeps the plain reason. | – | none | `access.review.details.orders_staff_drink_record.{comp_mismatch,overspent,device_overcounted,duplicate_id,pool_off,no_eligible_items,item_not_eligible,note_required}` (e.g. "Staff drink: the till gave a different amount free than the server priced") | rv:143-153, fd:15-49, review-page.test.tsx:133-178 |
| ADM-REV-009 | Permission column: for a known staff-drink detail the capability's registry name (EN/AR, e.g. "Record a staff drink") with the raw key on hover/hold; otherwise the raw capability string in LTR mono (key never translated). | – | none | – (registry names) | rv:161-172 |
| ADM-REV-010 | Trailing cell: reviewed flag → success pill "Reviewed"; open flag + `approvals.review` → ghost "Mark reviewed" (spinner on that row while pending). | – | `approvals.review` | `access.review.reviewed` "Reviewed", `access.review.markReviewed` "Mark reviewed" | rv:236-246 |
| ADM-REV-011 | Mark reviewed: success refetches `/authz/flags*` (row leaves the open list), no toast; failure → error toast. | POST `/authz/flags/{id}/review` (reviewFlag) | srv: `approvals.review` | – | rv:52-60,242 |
| ADM-REV-012 | Row checkbox (aria "Select this action") only on open flags. | – | `approvals.review` | `access.review.selectOne` "Select this action" | rv:121-129 |
| ADM-REV-013 | Header checkbox (aria "Select all shown"): selects every OPEN flag in the list (never reviewed ones), clears when unticked; disabled with no open flags; ticked when all open flags are picked. | – | `approvals.review` | `access.review.selectAll` "Select all shown" | rv:62-66,109-119, review-page.test.tsx:105-112 |
| ADM-REV-014 | Bulk bar (≥1 picked): "{{count}} selected", note box (placeholder/aria "Note (optional)"), "Mark {{count}} reviewed" button (spinner), "Clear" empties the selection. Arabic button e.g. "تمييز 1 كمراجَع". | – | `approvals.review` | `access.review.selectedCount` "{{count}} selected", `access.review.notePlaceholder` "Note (optional)", `access.review.bulkResolve` "Mark {{count}} reviewed", `access.review.clearSelection` "Clear" | rv:204-233, review-page.test.tsx:124-130 |
| ADM-REV-015 | Bulk resolve: `{flag_ids, note (trimmed) or absent}`; all resolved → success toast "Resolved {{ok}}"; some pending → warning toast "Resolved {{ok}}, {{failed}} could not be resolved" with one description line per refused id "#<id>: <reason>"; then selection and note cleared and the list refetched. Error → error toast. | POST `/authz/flags/bulk-review` (bulkReviewFlags) | srv: `approvals.review` | `access.review.bulkDone` "Resolved {{ok}}", `access.review.bulkPartial` "Resolved {{ok}}, {{failed}} could not be resolved" | rv:80-103,217-228, review-page.test.tsx:92-122 |
| ADM-REV-016 | Empty: shield-check icon "Nothing to review" + hint. Loading skeleton; error + Retry; phone cards (no checkboxes on phone). | – | none | `access.review.empty` "Nothing to review", `access.review.emptyHint` "Flagged offline acts and wrong-branch PINs appear here." | rv:247-253 |
| ADM-REV-017 | (critic) Selection details: picks survive toggling "Show reviewed" and paging (20 per page); "Select all shown" ticks every open flag in the whole list — all pages, not only the visible one; the count and the bulk call use only picks that are still open in the current list. A single "Mark reviewed" shows no toast and other rows' buttons stay enabled while one is pending. | – | `approvals.review` | – | rv:48-78,109-129,236-246 |

---

## 7. `/onboarding` POS first-run wizard

### Header

| Field | Value |
|---|---|
| Web path | `/onboarding` (full screen, OUTSIDE the shell: no sidebar, header, footer or module gate) |
| Title | `onboarding.title` "Let's open your café" |
| Web files read | `routes/onboarding.tsx`, `routes/_app/route.tsx` (gate), `features/onboarding/{onboarding-page,step-panel,step-navigator,dashboard-mirror,celebration,config,gate}.ts(x)` + `gate.test.ts`, entry points of the reused dialogs (`features/branches/branch-dialog.tsx`, `features/users/user-dialog.tsx`, `features/payment-methods/payment-method-dialog.tsx`, `features/menu/{category-dialog,addon-dialog,menu-item-dialog}.tsx`, `features/recipes/create-ingredient-dialog.tsx`), `lib/translation.ts`, `lib/motion.ts` |
| Capabilities | Client: signed-in only (the shell sends org_admins of POS orgs here, ADM-APP-084). Server: read `org.settings.read` + same org; complete `org.settings.edit` (orgs:update) + same org, and only when every required step is done (409 otherwise); `PATCH /orgs/{id}` is SUPER-ADMIN ONLY (see ONB-014); logo upload: own org. The reused dialogs keep their own server rules. |
| Module | none (never module-gated; the gate only sends POS orgs) |
| Realtime | none |
| Generated API hooks | `useGetOnboarding` (getOnboarding), `useGetOrg` (getOrg), `completeOnboarding`, `updateOrg`, `uploadOrgLogo`, `useListCategories` (listCategories), `useListMenuItems` (listMenuItems); plus the reused dialogs' calls (createBranch/patchBranch, createUser/suggestPin, payment method, category, add-on, menu item, ingredient — owned by their areas). |
| Invalidation | Closing any step dialog, saving the café details, or uploading the logo → `['/orgs/{id}/onboarding']`. Completing → that key is SET to the server's answer (so the gate stops at once). |

### Behaviours

| id | behaviour | API call | gate | i18n keys | web source |
|---|---|---|---|---|---|
| ADM-ONB-001 | Route needs a session (ADM-APP-017); renders full screen without the shell. Reached by the first-run gate or by URL (any signed-in person; the server decides what they may read). | – | signed-in | – | ronb:6-9 |
| ADM-ONB-002 | Top bar: sparkles tile, title, sub-line, ghost "Skip for now". | – | none | `onboarding.title` "Let's open your café", `onboarding.subtitle` "A few quick steps — watch your dashboard come to life as you go.", `onboarding.skip` "Skip for now" | onp:105-114 |
| ADM-ONB-003 | Skip for now: sets the session skip flag (ADM-APP-085) and goes to `/`; the gate will not bring them back this session. | – | none | – | onp:91-98 |
| ADM-ONB-004 | Progress: pct = round(required steps done ÷ required steps × 100) (0 with none); "{{pct}}% ready to open" + a cheer: 100 → "Ready to open!", ≥75 → "Almost there!", ≥50 → "Halfway there!", >0 → "Nice start!", 0 → "Let's go!"; bar fills (animated width; instant with reduced motion). | GET `/orgs/{id}/onboarding` (getOnboarding) | srv: `org.settings.read` | `onboarding.readyPct` "{{pct}}% ready to open", `onboarding.cheer.done`, `.most`, `.half`, `.start`, `.go` | onp:53-66,117-130 |
| ADM-ONB-005 | Loading (or no org yet): three skeleton panels (the navigator one only from 1024 px). | – | none | – | onp:138-143 |
| ADM-ONB-006 | Error: red panel with alert icon "Couldn't load your setup" and an outline button reading `common.refresh` "Refresh" that refetches. | – | none | `onboarding.loadError` "Couldn't load your setup", `common.refresh` "Refresh" | onp:132-137 |
| ADM-ONB-007 | Layout: from 1024 px three columns (navigator 220 px · step panel · live mirror); below, the navigator is hidden and panel + mirror stack. | – | none | – | onp:145-173 |
| ADM-ONB-008 | Steps in order: org_profile, branch, payment_methods, ingredients, categories, menu_items, addons, recipes, team, go_live; stages: cafe (org_profile), branch, pay (payment_methods), menu (ingredients…recipes), team, live (go_live). Opens on the first step whose server status is not done (go_live when all done). | – | none | `onboarding.steps.<key>.title` (e.g. "Name your café", "Add your first branch", "How you get paid", "Stock your pantry", "Organize your menu", "Build your menu", "Add-ons & extras", "Recipes & costs", "Invite your team", "Open your café"), `onboarding.stages.*` | ocfg:51-73, onp:44-49 |
| ADM-ONB-009 | Navigator (≥1024): stage headings; each step button: check when done, lock when locked, else its icon; title; "Optional" badge for non-required steps (not on go_live); "{{count}} added" when count > 0 and not done; current step marked. go_live is disabled with a lock until the server says `can_complete`. Tapping selects the step. | – | none | `onboarding.navLabel` "Setup steps", `onboarding.stages.cafe` "Your café", `.branch` "Your branch", `.pay` "Get paid", `.menu` "Your menu", `.team` "Your team", `.live` "Go live", `onboarding.optional` "Optional", `onboarding.countAdded` "{{count}} added" | sn:15-87 |
| ADM-ONB-010 | Step panel header: the step's title and description. | – | none | `onboarding.steps.<key>.title`, `onboarding.steps.<key>.desc` | sp:57-60 |
| ADM-ONB-011 | Panel footer (not on go_live): ghost "Back" (disabled on the first step) and outline "Continue" (next step — from Invite your team it opens go_live even while go_live is locked in the navigator). | – | none | `onboarding.back` "Back", `onboarding.continue` "Continue" | sp:66-75, onp:71,157-159 |
| ADM-ONB-012 | (corrected) org_profile: logo picker (square, hint "PNG, JPG or WebP") uploads at once; success stores the org logo for the shell (ONB-030), refetches org + onboarding. A failed upload shows the raw thrown message under the picker (ADM-APP-127). Copy text beside it. | PUT `/orgs/{id}/logo` (uploadOrgLogo); GET `/orgs/{id}` (getOrg) | srv: own org | `onboarding.steps.org_profile.logoHint` "PNG, JPG or WebP", `onboarding.steps.org_profile.logoCopy` | sp:210-226 |
| ADM-ONB-013 | org_profile: "Café name" (prefilled from the org, placeholder "e.g. Madar Coffee") and "Currency" select EGP / USD / SAR / AED / GBP / EUR (prefilled, default EGP). | GET `/orgs/{id}` (getOrg) | none | `onboarding.steps.org_profile.name` "Café name", `.namePh` "e.g. Madar Coffee", `.currency` "Currency" | sp:35,183-191,228-247 |
| ADM-ONB-014 | "Save & continue": `{name (trimmed, omitted when blank), currency_code}`; success → refetch org, refresh onboarding, toast "Café details saved.", next step; failure → error toast. NOTE: the server allows this PATCH to a super admin only, so an owner gets the `errors.unauthorized` toast — the mock must refuse it the same way. | PATCH `/orgs/{id}` (updateOrg) | srv: super admin | `onboarding.steps.org_profile.save` "Save & continue", `onboarding.steps.org_profile.saved` "Café details saved." | sp:193-206,249, MadarRust orgs/handlers.rs:714-723 |
| ADM-ONB-015 | branch step: with count > 0 a success banner "{{count}} branch added — nicely done."; else dashed text; button "Add a branch" (filled) / "Add another branch" (outline) opens the Branch dialog in create mode (ADM-BRA-020..035); closing it refreshes the onboarding status. | dialog's own (POST `/branches`, PATCH `/branches/{id}`) | srv: `branches.create`/`.edit` | `onboarding.steps.branch.added`, `.empty` "No branch yet — add your first to put your café on the map.", `.cta` "Add a branch", `.addAnother` "Add another branch" | sp:87-92,136-177 |
| ADM-ONB-016 | payment_methods step: same pattern with the Payment method dialog (create; setup area). | dialog's own | dialog's | `onboarding.steps.payment_methods.added` "{{count}} payment methods ready.", `.empty`, `.cta` "Add a payment method", `.addAnother` | sp:93-98 |
| ADM-ONB-017 | ingredients step: same pattern with the Create ingredient dialog (inventory/recipes area). | dialog's own | dialog's | `onboarding.steps.ingredients.added`, `.empty`, `.cta` "Add an ingredient", `.addAnother` | sp:99-104 |
| ADM-ONB-018 | categories step: same pattern with the Category dialog (create; catalog_menu area). | dialog's own | dialog's | `onboarding.steps.categories.added`, `.empty`, `.cta` "Add a category", `.addAnother` | sp:105-110 |
| ADM-ONB-019 | addons step: same pattern with the Add-on dialog (create; catalog_menu area). | dialog's own | dialog's | `onboarding.steps.addons.added`, `.empty`, `.cta` "Add an add-on", `.addAnother` | sp:113-118 |
| ADM-ONB-020 | team step: same pattern with the User dialog in create mode (ADM-USR-020..032). | dialog's own (POST `/users`, GET `/users/pin-suggestion`) | srv: `staff.users.create` | `onboarding.steps.team.added`, `.empty`, `.cta` "Add a team member", `.addAnother` | sp:121-126 |
| ADM-ONB-021 | menu_items step: reads categories; none → warning "Add a category first — every item lives in one." and the button is disabled; count > 0 → "{{count}} on the menu board."; else the empty line; button "Add a menu item" / "Add another item" opens the Menu item dialog (create; catalog_menu area); closing refreshes. | GET `/categories?org_id=` (listCategories) | srv: menu read | `onboarding.steps.menu_items.needCategory`, `.added` "{{count}} on the menu board.", `.empty`, `.cta` "Add a menu item", `.addAnother` "Add another item" | sp:256-291 |
| ADM-ONB-022 | recipes step: intro text; reads items; none → "Add a menu item first, then come back to give it a recipe."; else the first 8 items (name in the active language) each with "Add recipe" opening the Menu item dialog on that item; closing refreshes. | GET `/menu-items?org_id=` (listMenuItems), GET `/categories?org_id=` (listCategories) | srv: menu read | `onboarding.steps.recipes.intro`, `.noItems`, `.addFor` "Add recipe" | sp:295-338 |
| ADM-ONB-023 | go_live: rocket tile (brand tint when ready), heading, sentence (ready / not ready), "Open my café" disabled unless `can_complete`, spinner while finishing. No footer. | – | srv `can_complete` | `onboarding.steps.go_live.heading` "Ready to open your café", `.ready`, `.notReady` "Finish the required steps (branch, payments, a category and a menu item) to open your café.", `.cta` "Open my café" | sp:342-362 |
| ADM-ONB-024 | Open my café: success → onboarding cache set to the answer, full-screen celebration (party icon, "Your café is open! 🎉", "Taking you to your dashboard…"; confetti hidden under reduced motion) for 1.8 s, then `/`. Failure (e.g. 409 "Onboarding cannot be completed: required steps missing (…)") → error toast, button enabled again. | POST `/orgs/{id}/onboarding/complete` (completeOnboarding) | srv: `org.settings.edit` + all required done | `onboarding.celebrate.title` "Your café is open! 🎉", `onboarding.celebrate.body` "Taking you to your dashboard…" | onp:73-89, cel:13-37, MadarRust orgs/onboarding.rs:104-140 |
| ADM-ONB-025 | Live mirror header: the org logo (or a store tile, brand-tinted once org_profile is done), org name or "Your café", "Dashboard", "Live preview". | GET `/orgs/{id}` (getOrg) | none | `onboarding.mirror.yourCafe` "Your café", `onboarding.mirror.dashboard` "Dashboard", `onboarding.mirror.preview` "Live preview" | dm:225-245 |
| ADM-ONB-026 | Mirror tiles (2 columns, 3 from 640 px): Branches, Payment methods, Categories, Menu items, Ingredients, Add-ons, Team. Not done → dashed locked tile with "—"; done → card with icon and the count counting up over ~1 s from its last value (instant under reduced motion), popping in. | – | none | `onboarding.mirror.branches` "Branches", `.payments` "Payment methods", `.categories` "Categories", `.items` "Menu items", `.ingredients` "Ingredients", `.addons` "Add-ons", `.team` "Team" | dm:40-142,248-252 |
| ADM-ONB-027 | Recipe cost coverage ring: `recipe_coverage` clamped 0..1, ring fill and "NN%" (rounded); title + hint; animated fill (none under reduced motion). | – | none | `onboarding.mirror.coverage` "Recipe cost coverage", `onboarding.mirror.coverageHint` "Add recipes to know every item's margin." | dm:145-180,253 |
| ADM-ONB-028 | Sales tile: locked "Today's sales" / "Unlocks with your first order" until `first_order` is done; then a decorative bar chart with "First sale in!". | – | none | `onboarding.mirror.sales` "Today's sales", `onboarding.mirror.salesLocked` "Unlocks with your first order", `onboarding.mirror.firstSale` "First sale in!" | dm:183-216,254 |
| ADM-ONB-029 | (critic) Leaving by browser/OS Back: the gate PUSHED `/onboarding` onto history, so Back lands on the shell page, whose gate sends the owner straight back while it still holds; only "Skip for now" or finishing gets out. | – | role org_admin | – | ar:77-79, onp:91-98 |
| ADM-ONB-030 | (critic) Uploading the café logo also writes this org into the shell's picked-org store (`setSelectedOrg(orgId, logo)`); for an owner (whose picked org is normally empty) that counts as an org change and clears the persisted branch selection. | PUT `/orgs/{id}/logo` | srv: own org | – | sp:215-221, aps:51-64 |
| ADM-ONB-031 | (critic) Step state: the active step is not in the URL (a reload reopens the first unfinished step); the café name / currency typed on org_profile are kept only while that step is shown (leaving and coming back re-reads the org); the Open my café button stays disabled after a successful finish while the celebration plays. | – | – | – | onp:30,44-49,73-89, sp:181-191,342-361 |

---

## 8. Formatting rules and values computed in the browser

App-wide (`lib/format.ts`, `data/scope/*`, `lib/week.ts`):

- Locale: English `en-GB`, Arabic `ar-EG`, ALWAYS Latin digits (`numberingSystem: "latn"`) and a true minus
  (U+2212) in numbers. Times 12-hour, meridiem uppercased ("06:02 PM"; Arabic keeps ص/م).
- Every date/time is shown in the ACTIVE timezone (ADM-APP-062), never the device's.
- `fmtDate` = `dd MMM yyyy` ("07 Oct 2026"); used by the period-picker label and From/To summary.
- `fmtStamp` (devices last seen, codes, client versions, review "When"): same day in the active zone → time
  only "06:02 PM"; same year → "12 Sep · 06:02 PM"; otherwise "31 Dec 2025 · 11:30 PM"; null → "—".
- Period picker month title: `Intl.DateTimeFormat(locale, {month: long, year: numeric, timeZone})` WITHOUT
  the Latin-digit option (in Arabic the year comes out in Arabic-Indic digits — web quirk); day cells are plain
  Latin numbers; weekday headers short names from Saturday.
- Preset ranges (active zone, calendar arithmetic so DST days stay 23/25 h): today = [00:00, 23:59:59.999];
  yesterday; 7d = today−6 … today; 30d = today−29 … today; mtd = 1st … today; each boundary converted to a UTC
  ISO "Z" instant. Custom range: start-of-day of the first pick to end-of-day of the last.
- Week starts Saturday (`WEEK_START = 6`).
- Initials (user menu, users table): first letter of the first two words, uppercased.
- Stat cards: integers via `fmtNumber`; Avg Tax via `fmtPercent` (percent, max 1 decimal).
- Excel exports: file `<prefix>-<YYYY-MM-DD>.xlsx` where the date is today's UTC date
  (`new Date().toISOString().slice(0,10)`); the branded header logo is the org's own only on the branding
  tier.

Per page:

- Orgs / branches: `tax_rate`, `service_charge_rate` are FRACTIONS on the wire (0.14) and PERCENT on screen
  (14): `fractionToPercent` = round(f×100, 4 dp); `percentToFraction` = round(p÷100, 6 dp); `formatRate` =
  "14%"; missing → 0. Org avg tax = arithmetic mean of fractions.
- Slug auto-fill (wizard; create-mode dialog): lowercase, trim, whitespace runs → "-", strip `[^a-z0-9-]`.
- Branch standard float: pounds on screen (piastres ÷ 100), piastres on the wire (round(pounds × 100)).
- Branch printer cell: `<brand> @ <ip>:<port>` in the export, `<ip>:<port>` LTR in the table.
- Activation code grouping: an 8-character code shows as "4072 1958"; any other length unchanged.
- Client versions KPIs: legacy count = rows with `last_legacy_at`; versions = distinct non-empty
  `app_version`; "+N" = `legacy_kinds.length − 1`.
- Devices App cell: `[platform, app_version]` non-empty values joined with " · ".
- Limits (access sheet + roles): `max_amount`, `max_value` typed in pounds → ×100 minor units; `max_percent`
  typed in % → ×100 basis points; `max_age_minutes` ×1; displayed back ÷ the same factor; blank → null;
  "Limited" when `own === true` or any numeric limit is non-null.
- Role-held set on Roles page: stored grants ∪ registry capabilities that are `core` for the role's kind.
- Review: flag capability cell `cap:detail` split at the first ":"; the detail's i18n key is
  `access.review.details.<cap with "." → "_">.<detail>`.
- Onboarding: pct = round(done_required ÷ total_required × 100); cheer thresholds 100/75/50/>0/0; coverage =
  round(clamp(recipe_coverage, 0, 1) × 100) %; first incomplete step drives the opening step.
- Person access assignments: branch names joined with "، " in both languages.
- User role options by viewer role (ADM-USR-022); a till role = teller, waiter, kitchen.

## 9. i18n keys missing from en.json / ar.json, and untranslated texts

A scan of every static `t()` call in the area's files (pages, dialogs, shell components) and every dynamic key
family (`roles.*`, `devices.kinds.*`, `devices.activation.states.*`, `scope.preset.*`,
`access.review.reasons.*`, `access.review.details.*`, `orgs.social.*`, `onboarding.stages.*`,
`onboarding.steps.*.{title,desc,added,empty,cta,addAnother}`, `onboarding.mirror.*`, `theme.*`, every nav
label) found **no key missing** from either `en.json` or `ar.json`. Nothing needs adding to the admin
supplement for keys.

Notes for the supplement / port (texts the web shows that have no key of their own):

| Where | Web text | Note |
|---|---|---|
| Branch dialog "Flag open bills as old after (hours)" (min 1, max 168, integer) | zod v4 defaults, English in both languages, e.g. "Too small: expected number to be >=1", "Too big: expected number to be <=168", "Invalid input: expected int, received number" | No i18n key on the web. The port needs words; reuse the web's English and add an Arabic in the admin supplement under a new key (record it as such), or show `errors.validation`. Owner decision. |
| Branch dialog tax/service rates (0..100) under the override, standard float (≥0) | zod v4 defaults ("Too small: expected number to be >=0", "Too big: expected number to be <=100") | Same as above. |
| Role dialog Name (English/Arabic) 1..80 | zod v4 defaults ("Too small: expected string to have >=1 characters", "Too big: expected string to have <=80 characters") | Same as above. |
| Login wordmark, legal links `·` separator, period trigger `→`, `⌘K` hint, "—" placeholders | literal symbols | Not translatable; keep. |
| Social link placeholders | `https://instagram.com/yourshop` … `https://yourshop.com` | Literal samples, not translated on the web. |
| Branch printer IP placeholder | `192.168.1.100` | Literal. |
| Onboarding currency options | EGP USD SAR AED GBP EUR | Literal codes. |
| Error-boundary fallback before React mounts | "Madar could not start in this browser…" (raw HTML, English) | Web-only bootstrap failure; no Flutter equivalent needed. |
| `features/onboarding/keep-building-card.tsx` (home, overview area) | `common.dismiss` "Dismiss" is MISSING from both files | Not an admin page; listed so the overview area owns it. |

Inline defaults that differ from en.json (en.json wins; listed so nobody copies the inline text):
`common.search` (inline "Search…", en "Search"), `orgs.taxRate` (inline "Tax Rate (%)", en "Tax rate (%)"),
`users.branchManagers` (inline "Branch Managers", en "Branch managers"), `users.deleteDescription` (inline
"…orders and shifts…", en "…orders and tills…"), `tills.pickBranch` (inline "Select a branch", en "Select a
branch to view its tills"), `common.refresh` on the onboarding error (inline "Retry", en "Refresh"),
`uploader.notAnImage` / `uploader.tooLarge` / `uploader.choose` / `uploader.replace` / `uploader.remove` /
`uploader.uploading` (en: "Selected file must be an image", "Image size exceeds 5MB limit", "Choose Image",
"Replace", "Remove", "Uploading..."), `common.copyright` (en "© {{year}} Madar. All rights reserved."),
`auth.email` used as a label elsewhere reads "Email address".

## 10. Pieces shared with other areas

Imported INTO admin from other feature folders:

| Piece | From | Used by | Owner area |
|---|---|---|---|
| `AddEmployeeDialog` (`features/dawam/add-employees.tsx`, prop `userId` = link this user) | dawam | Users ▸ Make employee (ADM-USR-014) | team |
| `useSetupProgress` (`features/dawam/setup.ts`) | dawam | sidebar + palette set-up leaf rule (ADM-APP-031) | team |
| `usePublicBrand` (`features/public-shell/use-brand.ts`) → `GET /public/orgs/brand` | public-shell | sidebar logo, footer "Powered by", every export logo (`useExportLogo`) | shell (core) |
| `PaymentMethodDialog` (`features/payment-methods/payment-method-dialog.tsx`) | payment-methods | Onboarding payment step (ADM-ONB-016) | setup |
| `CategoryDialog`, `AddonDialog`, `MenuItemDialog` (`features/menu/*`) | menu | Onboarding categories / addons / menu items / recipes steps | catalog_menu |
| `CreateIngredientDialog` (`features/recipes/create-ingredient-dialog.tsx`) | recipes | Onboarding ingredients step | inventory (or catalog_menu, whichever owns recipes) |
| `shiftsRedirect` (`features/tills/redirect.ts`) | tills | `/shifts` redirect (ADM-APP-114) | sell (logic is one line; shell can inline) |
| Shared web components | `components/app/*` | data-table, page + section tabs, export-button, confirm-dialog, empty-state/error-state, stat-card, status-pill, segmented-control, ledger-strip, section-header, list-row, image-uploader, timezone-select, combobox, restricted, module-gate, date-range-picker; `components/legal-links.tsx` | kit / shell |

Exported FROM admin and used by other areas (keep their public API stable):

| Piece | Used by |
|---|---|
| `features/users/row-action.tsx` (`RowAction`: ghost icon button + tooltip, destructive tint) | orgs, branches, staff employees / work shifts / attendance / rules / requests (team) |
| `features/orgs/tax-rate.ts` (`fractionToPercent`, `percentToFraction`, `formatRate`, `MAX_PERCENT`) | branch dialog, settings brand, discounts (catalog_offers), menu price-tax hint (catalog_menu) |
| `features/orgs/social-links.tsx` (`SocialLinksFields`, schema, patch) | settings ▸ brand pane, links admin pane (setup) |
| `features/branches/branch-dialog.tsx` | onboarding branch step |
| `features/branches/util.ts` (`invalidateBranches`) | Dawam set-up step (team) |
| `/branches?edit=new` deep link | Dawam set-up "Add a branch" (team D-024) |
| `features/users/user-dialog.tsx` | onboarding team step |
| `features/devices/api.ts` (availability hooks `useAvailability`, `useEffectiveMethods`, `usePutAvailability`, `allowListFor`) | payment-methods availability tab / allow-list editor (setup) |
| `features/onboarding/{config,gate}.ts`, `KeepBuildingCard` | shell first-run gate; home card (overview) |
| `features/access/*` | only the Users page (this area) |
