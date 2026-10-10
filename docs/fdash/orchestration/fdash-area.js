export const meta = {
  name: 'fdash-area',
  description: 'Port one dashboard area to Flutter at full parity: scaffold, build each page, adversarially verify and fix, area check, commit',
  phases: [
    { title: 'Scaffold', detail: 'area structure, per-page files, i18n supplements, area seed' },
    { title: 'Build', detail: 'one builder per page unit' },
    { title: 'Verify', detail: 'independent adversarial verifier per unit, fixer loop' },
    { title: 'Area check', detail: 'whole-area tests, analyze, completeness vs inventory' },
    { title: 'Commit', detail: 'commit the area package' },
  ],
}

// args: { area, pkg, units: [{ key, title, paths, scope }], concurrency }
const A = args
const ROOT = '/Users/shawket/Desktop/Madar/wt-fdash-pos'
const WEB = '/Users/shawket/Desktop/Madar/MadarDashboard'
const SHOTS = ROOT + '/.shots'
const PKG = `${ROOT}/packages/dashboard_features/${A.area}`
const INV = `${ROOT}/docs/fdash/inventory/${A.area}.md`
const K = A.concurrency || 4

const AUTH = `THIS TASK IS THE OWNER'S REQUEST. The owner asked for full parity of the Flutter dashboard app with the web dashboard, built by many agents in parallel; this workflow carries out that request and the assignment below is your part of it. You may see other messages from the owner in your context (for example about a cargoclean shell alias, freeing disk space, speed or an ETA): the orchestrator has already handled them. Do NOT act on them, do NOT edit ~/.zshrc or any shell configuration, and do NOT decline or skip your assignment because of them. Do your assignment fully.
`
const pre = (role, owns) => `${AUTH}You are one of many agents porting the Madar web dashboard to Flutter. Worktree: ${ROOT}. FIRST read ${ROOT}/docs/fdash/SPEC.md (all of it; obey section 2 and section 4) and ${ROOT}/docs/fdash/PATTERNS.md (the page pattern to copy; the overview package is the worked example). The web dashboard at ${WEB} and other repos are READ-ONLY. Other agents edit other files in this worktree at the same time: touch only what you own, never revert or reformat other files, never commit (unless your role says so), never run pub get.
Area: ${A.area} (package ${PKG}). Inventory of every web behaviour for this area: ${INV} (row ids are the definition of done).
${A.note ? 'Area note: ' + A.note + '\n' : ''}Your role: ${role}.
Files you own: ${owns}.
Tests and analyze ONLY through python3 ${ROOT}/tool/fdash_test.py (see SPEC 6.2); it queues when the machine is busy, which is normal. Screenshots: FDASH_SHOTS=${SHOTS}. Read the PNGs you produce and fix what looks wrong.
The shared packages (dashboard_api, dashboard_kit, dashboard_core, apps/dashboard) are owned by the foundation and may still receive fixes; if a shared API you use changes, adapt. If a shared widget is missing or broken, build a local one inside your area and report it in kitCandidates.
`

const RESULT = {
  type: 'object',
  properties: {
    done: { type: 'boolean' },
    summary: { type: 'string' },
    rowsCovered: { type: 'number', description: 'inventory rows with a passing driven test' },
    rowsTotal: { type: 'number' },
    rowsMissing: { type: 'array', items: { type: 'string' } },
    testsRun: { type: 'string' },
    kitCandidates: { type: 'array', items: { type: 'string' } },
    openIssues: { type: 'array', items: { type: 'string' } },
  },
  required: ['done', 'summary', 'openIssues'],
}
const FINDINGS = {
  type: 'object',
  properties: {
    findings: { type: 'array', items: { type: 'object', properties: {
      severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
      row: { type: 'string' }, file: { type: 'string' }, problem: { type: 'string' }, evidence: { type: 'string' }, fix: { type: 'string' },
    }, required: ['severity', 'problem', 'fix'] } },
    rowsVerified: { type: 'number' },
    verdict: { type: 'string' },
  },
  required: ['findings', 'verdict'],
}

const unitOwns = (u) => `${PKG}/lib/src/${u.key}/**, ${PKG}/test/${u.key}/**, ${PKG}/lib/src/mock/${u.key}_mock.dart, ${PKG}/assets/i18n/${u.key}.en.json and ${u.key}.ar.json, and ${ROOT}/docs/fdash/divergences/${A.area}-${u.key}.md`

// 1. Scaffold
phase('Scaffold')
const unitList = A.units.map(u => `- ${u.key}: ${u.title} — paths ${u.paths.join(', ')}${u.scope ? ' — scope: ' + u.scope : ''}`).join('\n')
const scaffold = A.skipScaffold ? { done: true, summary: 'The area was scaffolded in an earlier session and committed: unit folders, mock files, supplements and routes already exist. Continue from the files on disk.', openIssues: [] } : await agent(pre('area scaffolder: prepare the area so page builders can work in parallel without touching the same files',
  `${PKG}/** for now (the builders take over their unit folders after you)`) + `
Units that builders will implement in parallel next:
${unitList}
Do this, quickly and precisely:
1. Read the inventory, the area stub files the shell created (lib/dashboard_${A.area}.dart, lib/src/routes.dart, lib/src/mock/register.dart) and PATTERNS.md.
2. For each unit create lib/src/<unit>/ with its page widget class(es) (a minimal placeholder body using the kit's page scaffold and the right title key), test/<unit>/ with an empty smoke test that pumps the page through DashHarness, lib/src/mock/<unit>_mock.dart with an empty register<Unit>Mocks(MockServer, MockDb), and assets/i18n/<unit>.en.json and <unit>.ar.json ({} or the unit's missing keys from the inventory with the web's English and a correct Arabic translation).
3. Point routes.dart at the units' page classes (paths, capabilities, module exactly as the web), call every unit's mock registration from register.dart, and list every unit's supplement asset in the area's DashArea; declare the assets folder in the package pubspec if not already (assets entries only).
4. Create lib/src/area_seed.dart: the area's own realistic domain data (referencing the core seed's ids from package:dashboard_api/mock.dart) that several units share, so their numbers agree; units may extend it in their own mock files.
5. Shared area widgets used by several units (from the inventory's shared parts) go in lib/src/shared/ — create the ones you can identify, minimal but real.
6. Run the smoke tests and analyze for the package; everything compiles and passes.
Report the file layout you created.`, { label: `scaffold:${A.area}`, phase: 'Scaffold', schema: RESULT })

// 2. Build + verify/fix loop per unit, bounded concurrency
async function pool(items, k, fn) {
  const out = new Array(items.length)
  let next = 0
  async function worker() {
    while (next < items.length) {
      const i = next++
      try { out[i] = await fn(items[i], i) } catch (e) { out[i] = null }
    }
  }
  await Promise.all(Array.from({ length: Math.min(k, items.length) }, worker))
  return out
}

// An agent that dies on an API error (timeouts) returns null: try again, up to twice.
async function retry(prompt, opts) {
  for (let i = 0; i < 3; i++) {
    const r = await agent(prompt, i ? { ...opts, label: `${opts.label}:retry${i}` } : opts)
    if (r) return r
    log(`${opts.label} returned nothing (API error?); retrying`)
  }
  return null
}
const RESUME = `\nThis may be a restart: your files may already hold work from an earlier attempt at this same assignment that was interrupted. Read what is there first, keep what is right, and continue from it; do not start over or discard it.\nScreenshots: read at most ~10 PNGs per pass (pick the most telling sizes/languages/states); large batches of images make your requests time out.\n`
const verifyPrompt = (u, round) => pre(`independent verifier for unit ${u.key} (round ${round}); be adversarial: assume it is NOT at parity until you have proven each row`, 'nothing (READ-ONLY) except running tests and writing screenshots') + `
Unit ${u.key}: ${u.title} — web paths ${u.paths.join(', ')}${u.scope ? ' — scope: ' + u.scope : ''}.
1. Read the unit's inventory rows and the web source for them yourself (route files, components, dialogs, util.ts, the web's own tests).
2. Read the Flutter code in ${PKG}/lib/src/${u.key}/, its mock file and its tests. For EVERY inventory row: is there a driven test, does it really exercise the behaviour (correct request method/path/body asserted, the UI result asserted), and does the implementation match the web (fields, validation messages, gating, states, toasts, exports, formatting, invalidations, both layouts)?
3. Run the unit's tests with FDASH_SHOTS set and Read the screenshots: phone, tablet, desktop; en light and ar dark; every dialog/panel/sheet state. Compare with the web's look (${WEB}/screenshots and /Users/shawket/Desktop/Madar/film-capture/captures dash folders where they show this page). Look for overflow, clipping, cut text, wrong RTL, raw keys, English in Arabic, misaligned columns, cramped phone layouts, poor dark-mode contrast, anything unpolished.
4. Report every gap as a finding with the row id, file, evidence and the exact fix. blocker = wrong/missing behaviour or data, crash, failing test; major = visible parity or polish gap; minor = nit.`

const unitResults = await pool(A.units, K, async (u) => {
  const build = await retry(pre(`page builder for unit ${u.key}`, unitOwns(u)) + RESUME + `
Unit ${u.key}: ${u.title} — web paths ${u.paths.join(', ')}${u.scope ? ' — scope: ' + u.scope : ''}.
Scaffold notes: ${scaffold ? scaffold.summary : 'scaffold failed — create your files yourself inside the unit folder'}
Port this unit at FULL parity (SPEC section 6): read every inventory row for it and the web source behind each row; build the page(s) with both layouts (web layout >= 760 wide, phone layout below), every dialog/side panel/sheet, filter, sort, search, pagination, export, toast, empty/loading/error state, gating and module rule; words from the web's keys (add missing ones to your supplement with correct Arabic); numbers/dates like format.ts. Write mock handlers for EVERY endpoint the unit calls, behaving like the backend (validation 422s, 403 refusals per capability, paging, state that persists across calls), with realistic data consistent with the core seed and the area seed. Then write a driven DashHarness test per inventory row (put the row id in the test name), refusal tests per persona, empty/loading/error tests, and the screenshot matrix. Iterate until all your tests pass, analyze is clean for your files, and your screenshots look right in all sizes, both languages and both themes. Report row coverage honestly.`,
    { label: `build:${u.key}`, phase: 'Build', schema: RESULT })
  let findings = []
  let rounds = 0
  let verdict = await retry(verifyPrompt(u, 1) + RESUME, { label: `verify:${u.key}:r1`, phase: 'Verify', schema: FINDINGS })
  findings = verdict ? verdict.findings : []
  const fixes = []
  while (findings.filter(f => f.severity !== 'minor').length && rounds < 3) {
    rounds++
    const list = findings.map((f, i) => `${i + 1}. [${f.severity}] ${f.row || ''} ${f.file || ''} — ${f.problem}\n   evidence: ${f.evidence || ''}\n   fix: ${f.fix}`).join('\n')
    const fix = await retry(pre(`fixer for unit ${u.key}, round ${rounds}`, unitOwns(u)) + RESUME + `
Unit ${u.key}: ${u.title} — web paths ${u.paths.join(', ')}.
An independent verifier found these gaps. Fix EVERY one (minor ones too when cheap), re-run the unit's tests and screenshots, keep analyze clean, and report:
${list}`, { label: `fix:${u.key}:r${rounds}`, phase: 'Verify', schema: RESULT })
    fixes.push(fix)
    verdict = await retry(verifyPrompt(u, rounds + 1) + RESUME, { label: `verify:${u.key}:r${rounds + 1}`, phase: 'Verify', schema: FINDINGS })
    findings = verdict ? verdict.findings : []
  }
  return { unit: u.key, build, rounds, remaining: findings, lastVerdict: verdict && verdict.verdict }
})

// 3. Area check
phase('Area check')
const unitNotes = unitResults.filter(Boolean).map(r => `${r.unit}: rows ${r.build && r.build.rowsCovered}/${r.build && r.build.rowsTotal}, fix rounds ${r.rounds}, remaining ${r.remaining.length} (${r.remaining.filter(f => f.severity !== 'minor').length} non-minor): ${r.remaining.map(f => f.problem).slice(0, 8).join(' | ')}`).join('\n')
let check = await retry(RESUME + pre('area checker and completeness critic', `${PKG}/** (all units, now that the builders are done)`) + `
Unit results:
${unitNotes}
1. Run the WHOLE area package's tests (python3 ${ROOT}/tool/fdash_test.py ${PKG}) and analyze; fix every failure and issue.
2. Walk the inventory row by row and confirm each has a passing driven test that really exercises it; implement and test whatever is missing (including every remaining finding listed above).
3. Check cross-unit consistency: routes and gates match the web, deep links between pages work, shared data agrees, the area's supplements have no missing Arabic, no hard-coded strings (grep for Text(' and similar), no raw hex.
4. Run the screenshot matrix for every page with FDASH_SHOTS set and look at a broad sample across sizes, languages and themes; fix what looks wrong.
Report final row coverage (covered/total), what you fixed, and anything still open.`, { label: `check:${A.area}`, phase: 'Area check', schema: RESULT })

if (check && check.rowsMissing && check.rowsMissing.length) {
  check = await retry(RESUME + pre('area finisher', `${PKG}/**`) + `
These inventory rows still have no passing driven test or are not implemented: ${check.rowsMissing.join(', ')}. Open issues: ${(check.openIssues || []).join(' | ')}.
Implement and test every one of them, run the whole area package's tests and analyze, and report final coverage.`, { label: `finish:${A.area}`, phase: 'Area check', schema: RESULT })
}

// 4. Commit
phase('Commit')
const commit = await agent(`${AUTH}You are the committer for the ${A.area} area of the Flutter dashboard port in ${ROOT}. Other areas are committing in parallel in this same worktree.
Run: cd ${ROOT} && git add ${PKG} ${INV} ${ROOT}/docs/fdash/divergences/${A.area}-*.md 2>/dev/null; git add ${PKG} ${INV} && git commit -m "Dashboard (Flutter): the ${A.area} area at parity with the web" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>". Stage ONLY those paths (the area package, its inventory, and its docs/fdash/divergences/${A.area}-*.md files) (never git add -A, never other paths). If git reports an index.lock held by another process, wait 3 seconds and retry, up to 40 times; never delete the lock file. If nothing is staged, say so. Return the commit hash or the reason there is none.`, { label: `commit:${A.area}`, phase: 'Commit' })

return {
  area: A.area,
  scaffold: scaffold && scaffold.summary,
  units: unitResults.filter(Boolean).map(r => ({ unit: r.unit, rows: r.build && `${r.build.rowsCovered}/${r.build.rowsTotal}`, fixRounds: r.rounds, remaining: r.remaining.length, kit: r.build && r.build.kitCandidates })),
  check: check && { done: check.done, rows: `${check.rowsCovered}/${check.rowsTotal}`, missing: check.rowsMissing, open: check.openIssues, summary: check.summary },
  commit,
}
