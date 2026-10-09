# catalog_menu/studio: verifier findings to fix (NOT at parity)
1 MAJOR (085/080): English in the Arabic screen: studio_options.dart:92 and :97 hard-code "(EGP)" → `'${t('common.price')} (${fmt.currencyLabel()})'`; studio_modifiers.dart:181 uses fmtUnit(r.unit) ("1 ml") → unitWord(t, r.unit). Arabic tests + two divergence rows.
2 (025): an item with a processing image and no legacy image_url gets no Remove: count a processing image as removable (menu_studio_page.dart:474).
3 (054): "Out of sync" should be the neutral outline badge, not a warning colour (studio_grid.dart:1203).
4 (052): the base picker reads ref.read(apiProvider) inside its loop (studio_grid.dart:1049): read the API once before the loop.
5 (012): test that opening another item (via a linked-copy link) with drafts pending replaces every draft.
6 (085 layout): the option Name box stretches, with the trash at the row's end.
7 (070): in the step picker, "Write your own" goes at the start and Close at the end.
8 nit: raw spacing numbers → tokens (studio_steps.dart:161,191,333; studio_modifiers.dart:139-140,381; studio_preview.dart:130,347,355; studio_grid.dart:441).
9 Intent warming (owner rule): section tabs (?tab=), linked-copy links to another item, the base picker and step library if they read on open, menu items. Test per kind.
