# Continue the Flutter dashboard parity program

State as of 2026-10-08, evening. Everything is committed on branch `feat/fdash-parity` in
`~/Desktop/Madar/wt-fdash-pos` (last commit: the checkpoint that added this file). Nothing is
running. Nothing has been pushed or merged into main.

## Done

- **Spec**: `docs/fdash/SPEC.md`, the contract every agent follows.
- **Inventory**: `docs/fdash/inventory/*.md`, 3,111 web behaviour rows over nine areas, each list
  checked by a second agent.
- **Foundation**, committed and tested:
  - `packages/dashboard_api`: a Dart client generated from MadarRust main's `openapi.json` (621
    operations), plus the mock server and the "Sabah Coffee" seed data;
  - `packages/dashboard_kit`: the UI kit (~13k lines);
  - `packages/dashboard_core`: text, permissions, scope and period, gateways, the generated nav,
    the shell (sidebar, header, phone bottom bar, sign-in, command palette, ask-a-manager) and the
    test harness;
  - `apps/dashboard`: runs in real mode, or in mock mode with `--dart-define=MADAR_MOCK=1`.
- **Backend wiring**, built and unit-tested but not yet run against a live backend:
  - generic `api_request` / `api_stream` in madar-core (`src/api_raw.rs`), which add the token,
    scope headers and EN/AR errors;
  - `xlsx_write` / `xlsx_read` in madar-frb-dashboard;
  - the regenerated bridge;
  - `apps/dashboard/lib/data/core_transport.dart`, and the real session, preferences and file
    gateways in `apps/dashboard/lib/real/`.

## In progress (code on disk, not yet verified)

- About 75k lines of page code across the eight areas. Every page unit has code and tests started.
- No unit has passed its independent verifier yet.
- The home page (overview) is partly built.
- `docs/fdash/PATTERNS.md` is not written yet.

## Remaining work, in order

1. **Foundation finish**: home page plus `PATTERNS.md`, integrator (whole workspace green), then
   three review lenses with fixes.
2. **Eight area workflows**, in parallel: builders continue from the files on disk, then
   verifier, then fix rounds, then the whole-area check, then commit.
3. **Final integration**:
   - the 133 app-wide `ADM-APP` rows, verified against the shell;
   - merge duplicated kit pieces;
   - nav and text parity checks;
   - full analyze, test and format runs.
4. **Real-backend check, by the main session itself** (not workflow agents):
   - start the film backend: `~/Desktop/Madar/.film-api-target/debug/madar-rust` on :8290
     against the scratch DB `e2e_film` (env vars in `film-capture/film.py` `step_api`, minus
     the Apple Wallet ones);
   - build and run the macOS app with `--dart-define=MADAR_API=http://localhost:8290`;
   - sign in as `nour@sabah.test` / `SabahFilm2026!` and walk every area in EN and AR;
   - repeat on the iPad simulator.

Estimate: about 6–7 hours of wall-clock time for steps 1–4.

## How to restart (new session) — CURRENT (2026-10-09, branch feat/fdash-parity-2)

The run moved from workflows to a per-unit Agent loop. **`docs/fdash/LEDGER.md` is the state**
(newest lines last): which units are DONE, BUILT (awaiting verify), VERIFIED (findings sent back),
running, and queued, plus the KIT / CORE / INTEGRATION / WEB FIX / OWNER Q to-do lines.

Loop, at most 20 agents at once:
1. **Builder** (general-purpose agent) per unit: authority preamble + "FIRST read
   docs/fdash/AGENT_BRIEF.md and follow it exactly. Your unit: area `X`, unit `Y` … web path …
   notes". If the unit's files already exist, it continues from them.
2. **Verifier** per built unit: same preamble + "FIRST read docs/fdash/VERIFIER_BRIEF.md … You are
   READ-ONLY". Its findings go back to a fixer (a new builder agent for that unit if the old one is
   gone), with the exact fixes.
3. Commit a unit when it is verified and fixed, with an explicit `git add` of its paths. Units that
   share files (sell; catalog_menu; catalog_offers) are committed per area.
4. When every unit is DONE: area checks, the foundation and kit sweep (the KIT/CORE/SEED lines in
   the ledger), integration (the INTEGRATION lines), then the real-backend check above.

Subagents can't write `.md` files: write divergence files yourself from their reports.

Builders still to launch, and units still to verify, are listed at the end of LEDGER.md under
"RESTART STATE".

## How to restart (old workflow method, superseded)

The workflow cache does not carry across sessions, so each workflow is launched fresh. Every
prompt tells agents to read their existing files and continue, not start over. The scripts are
in `docs/fdash/orchestration/`.

1. Open Claude Code in `~/Desktop/Madar` and paste:

   > Continue the Flutter dashboard parity program: read
   > ~/Desktop/Madar/wt-fdash-pos/docs/fdash/CONTINUE.md and follow "How to restart".

2. The session then launches:
   - **Foundation finish**: `Workflow({scriptPath:
     ".../docs/fdash/orchestration/fdash-foundation-v2.js", args: {finishOnly: true}})`. This
     skips the build and shell steps and runs the home page, integrator, review and fixes.
   - **Eight areas**: `Workflow({scriptPath: ".../docs/fdash/orchestration/fdash-area.js",
     args: <area entry from fdash-units.json> + {skipScaffold: true}})`, one per area. Use
     concurrency 5 for sell, team and setup, and 4 for the others (~35 agents in total).
   - **Watcher**: `python3 docs/fdash/orchestration/watch.py <workflows transcript dir>`, edited
     to the new run IDs. Gallery: `python3 docs/fdash/orchestration/gallery.py .shots && open
     .shots/index.html`.
3. In the first 10 minutes, check every journal for refusals and API errors. On 2026-10-08:
   - agents treated an owner side message as their task, so every prompt now starts with an
     authority preamble;
   - full-resolution screenshots caused API timeouts, so screenshots are now 1440×900 and agents
     read at most ~10 per pass.

## Rules that stay

- Tests only through `tool/fdash_test.py`: 8 machine-wide slots, a lock per package.
- Never push. Never touch production or `:5432` beyond `e2e_*` databases.
- Web bugs are not copied: each difference is logged in `docs/fdash/divergences/<area>-<unit>.md`
  for the owner to review.
