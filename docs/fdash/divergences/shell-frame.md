# Shell (frame, router, sign-in): differences from the web

One line per difference: what the web does, what Flutter does, why.

| Row | Web | Flutter | Why |
|---|---|---|---|
| SH-01 sign-in screen | The task named commit 111bad16 (the centred card); web `main` has since reverted it (157d4f70, 93246e45) to the split screen with a three.js showcase. | Ports web `main`: the split screen (ink brand panel at >= 1024 wide, form alone below), with the web's own 2D orbit (`orbit-2d.tsx`) as the panel's picture. | `main` is the reference (SPEC §1) and the owner reverted 111bad16; the i18n tables (synced from `main`) no longer have 111bad16's `auth.signInTitle`. The web draws the same 2D orbit wherever its 3D cannot run. |
| SH-02 sign-in refusal | Shows the server's English sentence (`Invalid credentials`), even in Arabic. | A 401 from sign-in shows `auth.errors.invalid` in the active language; other failures show `ApiException.message`. | English inside the Arabic UI is a bug to port the intent of (SPEC §6.3). |
| SH-03 header colour | Paper header (`bg-background`) with outline controls. | Ink header (chrome) with its controls in the dark palette in both themes. | Owner decision: "ink sidebar and header". |
| SH-04 user menu | Name, email, role, Sign out; theme and language are separate header buttons. | The same, plus Language and Light/Dark/System in the menu; the separate toggles stay. | Owner decision: "user menu (language, theme, sign out)". |
| SH-05 phone navigation | No bottom bar; a sidebar sheet behind the header's trigger. | Bottom bar Home / Orders / Reports / More; More opens the full sidebar as a drawer. Reports opens the first report the person sees in sidebar order (Legal for a Dawam-only owner). | Owner decision. |
| SH-06 icon rail parents | In the folded icon rail a parent (Menu, Inventory, Staff) cannot show its children; its click does nothing visible. | A parent's icon on the rail unfolds the sidebar and opens that group. | Port the intent; a dead control is a defect. |
| SH-07 scope in the URL | Branch and period live in the URL (`?branchId&preset&from&to`) and every nav link carries them. | They live in the scope provider (persisted, as the web's store); a link that names them (`?branchId=…&preset=…`) still sets them. Nav links go to the bare path. | No visible URL on a native app; deep links keep working. |
| SH-08 not-found page | TanStack's bare "Not Found". | An empty state in the frame ("Page not found", a way back home), words in the shell supplement. | The web shows no designed page; a bare word is not a page. |
| SH-09 page placeholder | — | An area page not yet ported shows its title and "This page is on its way" (shell supplement). | Temporary until each area lands. |
| SH-10 page gate while permissions load | A page renders with every action hidden until `/authz/me` answers; if it fails the page stays that way. | Blank while loading; on a failure an error state with Retry (`shell.accessLoadError`). | A page that silently hides everything after a failure reads as "no access". |
| SH-11 Restricted on set-up-only | — | `/staff/setup` opens for whoever holds `hr.rules.edit` even when the checklist is complete (only the nav hides it), as the web's `SetupPage` does. dashboard_core's `DashRoute.allows` would refuse it; the shell does not use that rule for set-up pages. | Web parity. |
| SH-12 org picker unpicked | Dashed border while no shop is picked. | The select's "active" emphasis (the kit has no dashed variant). | Kit limitation. |
| SH-13 scope sheet on phone | A 240-wide popover under the filters button. | A bottom sheet with the same controls. | Phone layout. |
| SH-14 sidebar scrolls to the active page | The rail does not scroll to the active item. | The active row is scrolled into view when the page changes. | A deep link to a page low in the list otherwise hides its row. |
| SH-15 screen-reader scope | — | The page area is its own semantics scope; without it the nested navigator's route barrier hid the sidebar and header from screen readers. | Accessibility defect found in testing. |
| SH-16 email and password fields | Web `main` has no `dir` on the inputs (111bad16 had `dir="ltr"`). | No forced direction (follows web `main`). | Parity. |
| SH-17 coded refusals | `getErrorMessage` fills `errors.codes.<CODE>` with `codedVars` formatting (dates, weekdays, statuses). | Real mode passes `errors.codes.<CODE>` filled with the raw vars to `CoreTransport`; the `codedVars` formatting is not ported. | Question: needs a shared port in dashboard_core. |
