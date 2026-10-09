# admin / branch_setup (`/branch-setup`, ADM-BSU)

Web read at MadarDashboard `af50aa63` (main moved past `8edecde5` during the port: the only
branch-builder change is `localizeServerNames`, ported). Backend read at MadarRust
`origin/main` (`src/branch_plan`, `src/devices/activation.rs`).

| Row | Web | Flutter | Why |
|---|---|---|---|
| ADM-BSU-008 | The line legend and the counts still float over the error panel. | Hidden with the error, as while loading. | Visual defect. |
| ADM-BSU-009 | An empty plan's summary reads "Nothing placed yet" and "Every order has somewhere to go." together. | Ported as is. | Question: the checks are empty, so the all-clear is true, if odd. |
| ADM-BSU-011 | (checked against `use-scope.ts:84-87`, `route.tsx:104-108`: confirmed) The scope bar writes the store, the stored branch and `X-Branch-Id` before the blocked navigation; after Cancel they name the new branch while the URL and the editor stay on the old one. | Cancel puts the scope back (`setBranch(old)`: store, header and stored choice). | Web bug. |
| ADM-BSU-039 | (checked against `builder-canvas.tsx:141-157,363-375`: confirmed) A press focuses the card after the pointer handler ran (`tabIndex=0`, no `preventDefault`), and focusing an unselected card selects only it: Shift+click to drop an unfocused card from the selection ends with only that card selected. | A press never focuses a card (the page keeps focus), so Shift+click adds or drops as meant; Tab still focuses and selects. | Web bug; the intent is a toggle. |
| ADM-BSU-041, -088 | The port takes presses 24 px wide. | 44 px (the dot is the same 11 px). | SPEC tap-target rule. |
| ADM-BSU-044 | The shortcuts listen on the window, outside inputs, dialogs and menus. | They listen on the page, which takes focus when it opens and on every press on the canvas; text fields, the inspector, menus and dialogs keep their keys. Arrow keys never move focus between cards (the web has no directional focus). | Flutter routes keys through focus; the reach is the same in use. |
| ADM-BSU-053 | Enter commits the field and keeps focus. | Enter commits and the kit's field leaves focus; the blur that follows does not commit (or add an undo step) a second time. | Kit behaviour. |
| ADM-BSU-060 | (checked against `activation.rs:458-472`, `branch_plan/handlers.rs:845-858`: confirmed) Activation bumps no version and sends no event; the card stays "Not set up" until the plan is read again, and a save from an older draft writes the slot's empty device back. | Ported as is; the mock does the same (`activateSlotCode`). | Server behaviour, not the page's. |
| ADM-BSU-084 | A slot still naming a device retired on `/devices` shows "Not set up" but keeps the device in the draft, so every save is refused until that slot's device is set to None. | The plan as read lets go of devices no longer registered (as loading a version does), so the save goes through and clears the slot. | Web bug (inventory). Pinned by `ADM-BSU-084 (divergence)`. |
| ADM-BSU-085 | `useBlocker` asks before any in-app navigation; the browser prompts on closing or reloading the tab. | Asks before a branch switch, the "Item routing" link and a back/pop (`PopScope`). The sidebar, the palette and the header's links navigate without asking: the shell has no navigation guard (`DashRoute` has no `onExit`). No close-the-app prompt. | Missing core hook; see the report (core candidate). |
| ADM-BSU-004 | Inventory header: `routing_mode` "as stored". | The server sends the effective mode (`effective_routing_mode`: stored, else `kds` with an active station, else `till`); the mock does too. | Inventory correction, read from `handlers.rs:530-533`. |
| ADM-BSU-026 | The hint says "⌘S" on every platform. | Same words; the bundled test fonts have no ⌘ glyph (a box in the screenshots); the real app relies on the system font fallback. | Kit/font note. |
