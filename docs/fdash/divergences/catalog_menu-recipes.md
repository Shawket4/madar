# catalog_menu / recipes: divergences from the web

The recipe builder and the create-ingredient dialog (`features/recipes`, MENU-RCP-001..023).

| Row | Web | Flutter | Why |
|---|---|---|---|
| MENU-RCP-005 | "Apply scaling" rebuilds the rows from the base size's rows plus the scaled ones, so a size whose factor box was cleared, holds 0 or is not a number loses every row (and so does a row whose size is not in `sizes`). | Only sizes with a factor above zero are replaced; any other size keeps its rows. Pinned by `MENU-RCP-005 (divergence) …`. | Data loss: clearing a factor box evidently means "leave this size alone". |
| MENU-RCP-004/005 | The switch, the hint and the factor labels print the raw size label, so a `one_size` base reads "Scale from one_size". | `one_size` reads "One size" there too, as in the section pill. | The sentinel is never meant to be shown (MENU-ITEMS-084). |
| MENU-RCP-002 | A "Copy from…" combobox exists, but no caller passes copy sources, so it never shows. | Not ported. | Never visible on the web; port it if a host ever needs it. |
| MENU-RCP-010, 021 | `type=number` boxes: the browser lets "-" and "e" through and refuses Arabic-Indic digits. | The boxes keep digits and one decimal point; a comma or `٫` reads as the point, Arabic-Indic digits as Latin. | Same intent (a non-negative decimal), and an Arabic keyboard works. |
| MENU-RCP-010 | The quantity box has no accessible name (only its placeholder). | It is named "<ingredient> in <size>" (`modeling.grid.cellAria`). | Accessibility rule (SPEC §2). |
| MENU-RCP-016 | A failed save rethrows into `void save()`: an unhandled promise rejection after the host's toast. | The builder swallows it after the host's toast; the rows stay unsaved. | No visible difference; no stray error. |
| MENU-RCP-023 | No discard guard: closing the add-on recipe dialog or the item dialog with unsaved builder edits drops them silently. | Ported as is (the builder has no close of its own; the hosts decide). | Question: a product choice or a lost-edit bug? The hosts (items unit) own the close. |
| MENU-AREA-014 (builder) | No loading or error state for the ingredient catalog: until it lands (or after it fails) the picker opens on "No results found"; a failed read is silent. | The picker says "Loading…" while the catalog loads; a failed read with nothing to show puts "Couldn't load the ingredients" + the server's words + Retry above the sizes (Retry asks only that read; the picker repeats the failure). The rows stay editable either way. Pinned by `error (divergence) …`. | The brief's state rule: never "no results" during a load; an error with Retry when it failed with no data. |
| MENU-RCP-019 | The category select is empty while the categories load and stays empty, silently, if the read fails. | "Loading…" in a disabled select while it loads; a failure says "Couldn't load ingredient categories" with Retry. Save still works (the server files the ingredient under General). | Same state rule. |
