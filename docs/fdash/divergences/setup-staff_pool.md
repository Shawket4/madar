# Setup / Staff drinks (`/settings/staff-pool`): differences from the web

One line per difference: what the web does, what Flutter does, why. Rows marked "question" port
the web's behaviour as it is and ask the owner whether it is intended.

| Row | Web | Flutter | Why |
|---|---|---|---|
| SET-SPL-021 (permissions loading) | While the person's grants are still loading, the read is disabled and the pane shows "Couldn't load the staff drinks settings" with Retry (a failure flashed before anything failed). | The two-card skeleton until the grants are known; if they fail to load, the shell's access error with Retry (`AuthzLoadError`). | An error state during a normal load is a defect (the brief: never flash a failure during a load). The no-organisation case is ported as the web has it. |
| SET-SPL-013 kit | The chip's × is a 12 px glyph in a ~16 px button inside a 22 px badge. | The × is the kit's `DashIconButton` (a 44 pt target), so a chip is taller. | Touch-target rule (SPEC section 2). |
| SET-SPL-011 kit | The picker is a popover at every width. | A 288 px popover from 760 wide; below, the kit's picker sheet (`showDashPickerSheet`) with the same note, search, list and Clear. | The kit's phone pattern for every select. |
| SET-SPL-002 / 003 | The skeleton and the load failure replace the whole pane, its header included. | The pane's title and description stay above the skeleton and the failure. | The settings panes' shared scaffold; the header does not depend on the read. Question if the owner wants the web's bare state. |
| SET-SPL (intent) | No `route-prefetch.ts` case for `/settings/staff-pool`. | The route's `prefetch:` warms the settings for the branch in scope (and the menu when items are chosen), only for a person with `org.settings.read`/`.edit`. | Owner intent rule, without asking a read the person would be refused. |
