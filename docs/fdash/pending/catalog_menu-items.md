# catalog_menu/items: verifier findings to fix (NOT at parity)
1 MAJOR (090/110): in Arabic the add-on search can't find what it shows: items_data.dart:174 matches only the English name while chips and the picker show translated names. Give addonPickerGroups the language and match the raw or the translated name; Arabic test "MENU-ITEMS-090 (divergence) Arabic search …"; add a line to divergence 110.
2 MAJOR (103/105): a failed GET /recipes/addons/{id} opens the builder empty, and Save then overwrites the real lines (addon_recipe_dialog.dart:90-99). When it failed with no data, render DashErrorState with Retry (retrying while loading) instead of the builder; "(divergence)" test + divergence row.
3 minor (040): the web caches add-on costs for 60 s (costing.ts COST_STALE): `ref.webCache(staleTime: const Duration(seconds: 60))` on addonCostsProvider.
4 minor (077): the Category select and its "+" take half the width from 640 (web sm:grid-cols-2): use the add-on dialog's two-column row with an empty second cell.
5 minor (AREA-011): Esc already closes showDashConfirm: add a test (Escape → no DELETE) and drop the "not reached" note.
6 minor (091): if the add-on selection changed but the modifier groups read hasn't arrived or failed, addonAttachments sends groups: [] and detaches every group. Block Save in that case and log a divergence row.
7 minor, tests: 081 asserts a fresh GET /costing/catalog after the job poll; 106 tests focus as well as hover; 021 checks the switch is disabled while saving.
8 nit: remove the raw fontSize: 12 in MenuTabsBar (use a type token).
9 Replace the hand-written loading check at items_page.dart:313 with awaitingFirst/failedFirst.
10 Intent warming (owner rule): move the card and Next warm-ups onto DashEditableCardGrid's onItemIntent/onPageIntent (drop the custom pager if the kit's now covers it), and wire the tabs (items/add-ons/categories), filter options, menu items and the add-on recipe button. Test per kind.
Don't touch the recipe builder re-seed question (an owner question; recipes owns it).
