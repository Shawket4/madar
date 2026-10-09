# Kit batch 2 (packages/dashboard_kit)

Each item names the web behaviour to match. Before you start an item, check whether kit batch 1 or an area agent already did it (`git log -p packages/dashboard_kit`, the kit tests). Skip it if done and say so.

Rules:
- Edit only `packages/dashboard_kit` (lib + test). New APIs are optional parameters, so existing callers keep compiling.
- A behaviour change that breaks an area's test: fix that test only in an area whose area check is done (inventory, admin, setup, catalog_offers, overview). For the others (sell, catalog_menu, reports, team), list the failures in your reply and leave them.
- Every item gets a kit test. Run `python3 tool/fdash_test.py packages/dashboard_kit`, `--analyze` and `dart format` on the kit. At the end, run `apps/dashboard`.
- Don't commit.

## Charts (`charts.dart`)
1. **X-axis labels:**
   - Keep labels inside the plot (the fitInside clip at about charts.dart:295).
   - Thin labels by the width actually available, not by a fixed count. Overview hourly labels are cut today.
   - The vertical bar chart shows every label when they fit.
2. **Plot direction:** add an LTR option, so time runs left to right in Arabic like Recharts. Default it on for time axes and say so in the doc.
3. **Y ticks:** use Recharts-style nice ticks (1/2/2.5/5 × 10^n) and support values below zero.
4. **Horizontal bar chart:** reports operations and the Basira pieces need one. Basira also needs LTR charts with gaps.
5. **Trend area fill:** the web's is a flat 12% fill, not a gradient.

## Figures and numbers
6. **dashFigure:** in Arabic, inside a FittedBox, short numbers lose their last digit. Find the cause (probably intrinsic width vs the shaped Arabic-Indic digits) and fix it.
7. **DashNumberField:**
   - Show negatives as "-1", not "1-", in Arabic (wrap in an LTR isolate, or set the text direction).
   - Add an ungrouped option (no thousands separators, as for port boxes).
8. **DashNumberInput:** today it commits only on blur. Commit on every change, or when the form validates, so Save works without unfocusing first.
9. **Compact figures:** switch at 768, not 760, as on the web.

## Fields
10. **DashCheckboxField** crashes inside a Wrap (unbounded width). Make it work there.
11. **DashBilingualField:**
    - Enter submits (onSubmitted).
    - It switches to two columns by the screen breakpoint, as the web does, not by its own width.
12. **DashSelectField:** cap the menu at maxHeight 256 and scroll it.
13. **Phone field:** add a DashPhoneField with a country code, typed as digits, LTR in Arabic. Used by team employees and setup.
14. **DashDateField:**
    - Add Clear, and a year jump.
    - When there are only 220–360 px below, open the popover above, or cap its height.
    - Show the web's past-date warning border and icon.
15. **DashTimeFormField:** add onSubmitted, so Enter on an empty field with its list closed submits, as in the web's time-field.tsx.
16. **Search box:** trim the query, and give it a clear (×) button as the web does.
17. **hintTextDirection:** in DashTextInput's InputDecoration, so an LTR placeholder reads correctly in RTL.

## Tables and layout
18. **DashDataTable:**
    - Reset to page 1 when the rows change (a filter or search).
    - Esc in the search clears it.
    - The search is trimmed.
19. **DashTab:** add an icon slot.
20. **DashLedgerStrip:**
    - A 50 ms stagger on its tiles.
    - Equal-height tiles when one has a 44 pt action, without the label being cut on an Arabic phone.
21. **DashSectionHeader:** centre a 44 pt trailing control on the title line.
22. **DashSurface:**
    - A title-trailing slot and footer slots.
    - Actions wrap into one row on a phone.
23. **DashStatCard:** the skeleton's fixed 80 px widths overflow a narrow card (phone, 3 across). Cap them to the card's width.
24. **DashPageScaffold:**
    - A page fade-in, as the web's animate-in. Skip it under reduced motion.
    - The gutter is 32 at a width of 1024 or more (24 below).
25. **DashSkeleton:** with no width, it fills the available width instead of drawing nothing.
26. **DashProgressBar:** 8 px high.
27. **DashMenu:** close the menu BEFORE running onSelected. A dialog opened from a ⋯ menu must get focus and Esc. Check whether batch 1 did this.
28. **Transfers Items cell:** a summary built from several names. Give the kit a helper for its direction: by the first strong character, as with dashTextDirectionOf, or say why it can't be done.

Final reply:
- what you did, per item number, or why you skipped it;
- the new APIs;
- the test counts;
- any failures in other areas.

## Added after launch
29. **DashMoneyField.onSubmitted:** Enter in an amount field submits, as the web's forms do. Team's payroll money forms need it.
30. **Time range field:** if it's small, add a kit DashTimeRangeField matching the web's TimeRangeField: a start and an end, with next-day when the end falls before the start. Model it on team's `shared/time_range_field.dart` (`TeamTimeRangeField`). Don't switch team over to it; that's the team owner's job.
