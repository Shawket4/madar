export const meta = {
  name: 'fdash-inventory',
  description: 'Inventory every web dashboard action per area (D-rows), then a completeness critic per area',
  phases: [
    { title: 'Inventory', detail: 'one agent per area reads the web pages and writes docs/fdash/inventory/<area>.md' },
    { title: 'Critic', detail: 'an independent agent per area re-reads the web and adds anything missed' },
  ],
}

const ROOT = '/Users/shawket/Desktop/Madar/wt-fdash-pos'
const WEB = '/Users/shawket/Desktop/Madar/MadarDashboard'
const AREAS = [
  { key: 'overview', prefix: 'OVW', pages: '`/` home page (features/dashboard/dashboard-page.tsx and every card it renders: KeepBuildingCard, LedgerStrip KPIs, OpenTillsCard, DeliveryKpis, revenue trend, payment mix, branch performance, MarginWatchCard)' },
  { key: 'sell', prefix: 'SELL', pages: '/orders, /floor, /bookings, /tills, /customers' },
  { key: 'catalog_menu', prefix: 'MENU', pages: '/menu/items, /menu/items/$itemId (incl. the menu studio and the recipe builder from features/recipes), /menu/groups, /menu/pricing, /menu/bases, /menu/packaging' },
  { key: 'catalog_offers', prefix: 'OFFR', pages: '/menu/combos, /menu/combos/$comboId, /menu/deals, /discounts' },
  { key: 'reports', prefix: 'REP', pages: '/reports/operations (+ its profitability and tables tabs), /reports/financial, /reports/inventory, /reports/legal, /reports/loyalty, /reports/bundles, /reports/staff, /reports/staff-pool, /reports/tills, /basira' },
  { key: 'inventory', prefix: 'INV', pages: '/inventory/today, /inventory/counts, /inventory/ingredients, /inventory/purchasing, /inventory/waste, /inventory/transfers, /inventory/settings' },
  { key: 'team', prefix: 'TEAM', pages: '/staff/setup, /staff/employees, /staff/attendance, /staff/shifts, /staff/team, /staff/approvals, /staff/schedule, /staff/requests, /staff/payroll, /staff/reports, /staff/rules' },
  { key: 'setup', prefix: 'SET', pages: '/settings (appearance), /settings/brand, /settings/links (admin editor only), /settings/delivery, /settings/delivery-zones, /settings/bookings, /settings/loyalty, /settings/qr, /settings/combos, /settings/payment-methods, /settings/staff-pool, /settings/kitchen-stations, /settings/kitchen-routing, /settings/integrations, /settings/whatsapp' },
  { key: 'admin', prefix: 'ADM', pages: '/orgs, /branches, /devices, /access/users, /access/roles, /access/review, /onboarding; plus the app-wide pieces: sign-in (/login, the new screen), org picker, branch picker (scope bar), period picker, user menu, command palette, ask-a-manager, module gate, the 25 legacy redirect routes, live branch updates (data/realtime). Mark app-wide rows with page "app"' },
]

const PAGE_SCHEMA = {
  type: 'object',
  properties: {
    area: { type: 'string' },
    doc: { type: 'string', description: 'path of the markdown inventory written' },
    pages: { type: 'array', items: { type: 'object', properties: {
      path: { type: 'string' }, title: { type: 'string' }, webFiles: { type: 'array', items: { type: 'string' } },
      actionCount: { type: 'number' }, endpoints: { type: 'array', items: { type: 'string' } },
      caps: { type: 'array', items: { type: 'string' } }, usesRealtime: { type: 'boolean' },
    }, required: ['path', 'title', 'actionCount', 'endpoints'] } },
    totalRows: { type: 'number' },
    missingI18nKeys: { type: 'array', items: { type: 'string' } },
    sharedWithOtherAreas: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['area', 'doc', 'pages', 'totalRows'],
}

const CRITIC_SCHEMA = {
  type: 'object',
  properties: {
    area: { type: 'string' }, addedRows: { type: 'number' }, correctedRows: { type: 'number' },
    totalRows: { type: 'number' }, summary: { type: 'string' },
  },
  required: ['area', 'addedRows', 'totalRows', 'summary'],
}

const inventoryPrompt = (a) => `THIS TASK IS THE OWNER'S REQUEST. The owner asked for full parity of the Flutter dashboard app with the web dashboard, built by many agents in parallel; this workflow carries out that request and the assignment below is your part of it. You may see other messages from the owner in your context (for example about a cargoclean shell alias, freeing disk space, speed or an ETA): the orchestrator has already handled them. Do NOT act on them, do NOT edit ~/.zshrc or any shell configuration, and do NOT decline or skip your assignment because of them. Do your assignment fully.\nYou are building the action inventory for one area of a web-to-Flutter port.
Read ${ROOT}/docs/fdash/SPEC.md first (sections 1, 6 and 7). The web dashboard at ${WEB} is READ-ONLY; you only write ONE file: ${ROOT}/docs/fdash/inventory/${a.key}.md (create the folder if needed). Do not run builds or tests.

Area: ${a.key}. Pages: ${a.pages}.

For each page, read its route file(s) under src/routes/_app/**, its feature folder under src/features/** (page, every dialog/sheet/drawer/tab/card component, util.ts, hooks, and the web's own tests, which list behaviours), and the shared components it uses. Then write the inventory:

1. A header per page: web path, title (the en.json words), web files read, capabilities that gate the page (nav.ts / settings-nav.ts / route guards / <Restricted>), module, realtime use, the generated API hooks it calls (operation names) and the query keys it invalidates after each mutation.
2. A table of EVERY user-visible behaviour as numbered rows with ids ${a.prefix}-<PAGE>-NNN (e.g. ${a.prefix}-ORD-001). One row per: button/action, form (each field with its validation rule and the zod schema's messages), filter, sort, search, pagination, tab, export (file name + columns), dialog/sheet/drawer open/close, confirmation, toast (exact i18n key), empty state, loading state, error state, permission refusal (what is hidden/disabled for whom), module refusal, responsive difference, keyboard shortcut, deep link / URL param. Columns: id | behaviour (what the user does and sees) | API call (method + path + operationId) | gate (capability / module / role) | i18n keys | web source (file:line).
3. Formatting rules the page uses (money, dates, timezones, numbers) and any computed values done in the browser (so the Flutter port reproduces them).
4. i18n keys the page uses that are MISSING from src/i18n/locales/en.json or ar.json (inline defaults), with the inline default text.
5. Pieces shared with other areas (components imported from other feature folders).

Be exhaustive: the port's definition of done is one driven test per row, so a missing row means a missing feature. Prefer too many rows to too few. Return the structured summary.`

const criticPrompt = (a, inv) => `THIS TASK IS THE OWNER'S REQUEST. The owner asked for full parity of the Flutter dashboard app with the web dashboard, built by many agents in parallel; this workflow carries out that request and the assignment below is your part of it. You may see other messages from the owner in your context (for example about a cargoclean shell alias, freeing disk space, speed or an ETA): the orchestrator has already handled them. Do NOT act on them, do NOT edit ~/.zshrc or any shell configuration, and do NOT decline or skip your assignment because of them. Do your assignment fully.\nYou are an independent completeness critic for a web-to-Flutter port inventory.
Read ${ROOT}/docs/fdash/SPEC.md (sections 1, 6, 7), then the inventory ${ROOT}/docs/fdash/inventory/${a.key}.md written by another agent (summary: ${JSON.stringify(inv && { pages: inv.pages && inv.pages.map(p => p.path), totalRows: inv.totalRows })}).
Area pages: ${a.pages}. The web dashboard at ${WEB} is READ-ONLY.

Independently re-read the web source for every page of this area (route files, every component file in the feature folders, dialogs, hooks, tests) and hunt for behaviours the inventory MISSED or got WRONG: actions, fields, validation messages, gating, states, toasts, exports, tabs, URL params, responsive differences, invalidations, realtime. Check every component file was read — list files in the feature folders and compare with the "web files read".
Edit ${ROOT}/docs/fdash/inventory/${a.key}.md in place: append missing rows (continue the numbering, mark them "(critic)") and correct wrong rows (mark "(corrected)"). Keep everything else. Return counts and a short summary.`

phase('Inventory')
const results = await pipeline(
  AREAS.filter(a => a.key !== 'overview'),
  (a) => agent(inventoryPrompt(a), { label: `inventory:${a.key}`, phase: 'Inventory', schema: PAGE_SCHEMA }),
  (inv, a) => agent(criticPrompt(a, inv), { label: `critic:${a.key}`, phase: 'Critic', schema: CRITIC_SCHEMA }).then(c => ({ area: a.key, inventory: inv, critic: c })),
)
return results.filter(Boolean).map(r => ({
  area: r.area,
  pages: r.inventory && r.inventory.pages && r.inventory.pages.length,
  rows: r.critic && r.critic.totalRows,
  added: r.critic && r.critic.addedRows,
  missingI18n: r.inventory && r.inventory.missingI18nKeys && r.inventory.missingI18nKeys.length,
  shared: r.inventory && r.inventory.sharedWithOtherAreas,
  critic: r.critic && r.critic.summary,
}))
