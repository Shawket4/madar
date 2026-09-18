# Madar POS — Design Spec

The single design spec for the POS (`apps/madar`) on iPad (primary), desktop and phone,
in English and Arabic. Every number here is a token in `packages/design_system`; a screen
that needs a number not in this document needs this document changed first.

Components referenced: `MadarPageScaffold`, `MadarHeader`, `MadarContentFrame`,
`MadarDataTable`, `MadarListRow`, `MadarStatusPill`, `MadarStatCard`, `MadarSectionHeader`,
`EmptyState` / `ErrorState` / `Skeleton*`, `MadarSpinner`, `MadarFormat` / `MoneyText`.
Renders: `packages/design_system/test/components_render_test.dart`
(`--dart-define=MADAR_RENDER=true` → `build/render/spec-*.png`).

---

## 1. Size classes and grid

| Size class | Decided by | Chrome | Gutter | Content |
|---|---|---|---|---|
| **iPad landscape** (1194×834) | shortest side ≥ 600, width ≥ height | rail 88 + top bar 56 | 24 | page area 1106 |
| **iPad portrait** (834×1194) | shortest side ≥ 600, width < height | rail 88 + top bar 56 | 24 | page area 746 |
| **Desktop** (macOS/Windows/Linux window) | platform, not a phone | rail + top bar | 24 | page area ≥ 1012 |
| **Phone** (390×844, any orientation) | shortest side < 600 | top bar + bottom tabs 64 | 16 | full width |
| **Small iPad** (iPad 9th gen, 1080×810 / 810×1080) | a tablet, by the same rule | rail 88 + top bar 56 | 24 | page area 992 landscape, 722 portrait |
| **8" Android** (800×1280) | a tablet | rail 88 + top bar 56 | 24 | page area 712 |

`MadarLayout` (phone/tablet) stays the chrome switch; `MadarSizeClass` is the grid's finer
question. A widget deciding about its own box (a 340 cart column) still uses
`Responsive`/`LayoutBuilder`.

**Room.** Beyond phone/tablet, `MadarRoom` classes each window axis as `tight` / `snug`
/ `roomy` (height: < 640 / < 900 / ≥ 900; width: < 600 / < 1000 / ≥ 1000). A screen that
stacks a footer under a list, or a cart beside a grid, decides by this, never by a
per-screen pixel guess:

| Window | width | height | What changes |
|---|---|---|---|
| iPad landscape (1194×834, 1080×810) | roomy | snug | dense footers (compact kitchen button + note tile; Park beside Charge) |
| iPad portrait (834×1194, 810×1080), 8" Android | snug | roomy | 300 cart column (`Responsive.cartColumnWidthSnug`), compact sell tiles (112–160, three columns), Park above Charge, a round line's stepper under its name |
| Landscape phone (844×390) | roomy | tight | dense AND capped: the cart footer scrolls inside 52% of the height |
| Desktop window | roomy | roomy | the regular layout |

Nothing is hidden by room — reflow, scroll or shrink a label, never drop a control or a
figure. Centred dialog surfaces that lay their own card (the tablet Charge modal) sit in
`MadarKeyboardInset`, which pads by the keyboard and hands the card the height left.

Vertical rhythm on every page: header starts `Space.md` (12) under the top bar; body
starts `Space.lg` (16) under the header block; sections are `Space.xl` (24) apart.

## 2. Header anatomy — fixed title geometry

```text
 gutter ┌ slot 44 ┐12┌ Title — h1 28/700, centred in a 48 row ──────────┐ actions ┐ gutter
        │ ‹ | ☐   │  │ Subtitle — 13/500 secondary, 2 below, never moves │ 44 8 44 │
        └─────────┘  └───────────────────────────────────────────────────┘         ┘
                     below slot — 12 under the title block, full content width
```

**Decision: a page title carries no icon.** A pushed page shows its back tile in the 44px
leading slot (title at `gutter + 56`); a tab page has no slot and its title sits on the
gutter, aligned with the content under it. An empty reserved slot was tried and read as a
misaligned title.

Invariants (pinned by `components_test.dart` at all four size classes, LTR and RTL):
- The title's y is identical with and without subtitle, back tile, actions, and for every
  content width; its x moves only by the back tile.
- Subtitle grows the header downward. `below` grows it further. Nothing re-centres.
- Actions are 44 tiles or compact (44) controls, centred on the 48 title row, 8 apart. A
  taller control (a 52 search field) belongs in `below` — the row would grow and the title
  would move.
- One title line, ellipsised. Titles are the screen name, never data (not the till's name).

`MadarPageScaffold(width: …)` opts into the spec grid.

## 3. Content widths and alignment

| Mode | Cap (tablet/desktop) | Screens |
|---|---|---|
| `MadarContentWidth.full` | none | Sell, Floor, Orders (split), Queue, Till, Close shift |
| `MadarContentWidth.reading` | 880 | Past shifts, Settings, Me, Sync, Bills |
| `MadarContentWidth.form` | 560 | Cash in/out, Open shift (embedded) |

- **Leading edge = the header's leading edge = gutter.** Content is never centred in the
  leftover width. The header is capped at the same width, so trailing actions line up with
  the content's trailing edge.
- Phone: every mode runs full width.
- iPad split views (Orders + sale detail): master = `MadarDataTable` at flex, detail pane
  560 on the trailing side, both inside `full`, detail laid with `MadarContentFrame(gutter: false)`.
- Desktop ≥ 1100: Settings / Me may lay two reading-width columns side by side, still
  leading-aligned.
- A body that runs edge to edge (a floor canvas) passes `bodyInset: false`.

## 4. Typography

| Role | Style | Notes |
|---|---|---|
| Page title | `MadarType.h1` 28/700, tracking −0.4 | one per page |
| Sheet / pane title | `h2` 22/700 | |
| Card title | `h3` 18/600 | |
| Row title | `title` 16/600 | |
| Body | `body` 15/500 | table text cells |
| Meta | `bodySm` 13/500, `textSecondary` | second lines, subtitles |
| Section / column label | `label` 12/700, uppercase, tracking 0.8 | `textSecondary` (section), `textMuted` (column) |
| Figures in rows / cells | `numMd` / `money` 15 mono | tabular |
| Card figure | `moneyMd` 20 / `numXl` 30 mono | stat cards |
| Hero figure | `moneyDisplay` 30 / `moneyHero` 44 | Charge, shift takings |

Figures (money, times, refs, counts) are IBM Plex Mono with tabular figures; Plex Sans
Arabic is the mono styles' fallback so a figure string carrying an Arabic word renders.
Western digits in both languages.

## 5. Spacing and shape

Spacing scale `Space`: 4 · 8 · 12 · 16 · 24 · 32, and 20 (`card`) for card insets and row
insets. Radii: 10 small tiles, 12 controls, 16 cards, 20 sheets, pill for pills. Heights:
44 small/tiles/chips, 48 header row / segments, 52 fields, 56 buttons, 64 rows,
72 amount field. No other numbers in feature code.

## 6. Cards

- `MadarCard`: surface fill, 1px `borderLight`, radius 16, inset 20, no shadow.
  A card holding rows is `flush` (rows own their insets, hairlines reach the edge).
- A card has **either** a section header above it (preferred) **or** an `h3` title inside —
  never both, never a label-styled title inside.
- `MadarStatCard`: tracked label (+ optional glyph, optional pill), one mono figure
  (`minor` for money, `value` for anything else), optional meta. Rows of 2–4 on tablet
  (`Row` of `Expanded`, 16 apart), stacked on phone (`compact: true` for 4-up).

## 7. Section headers and list rows

**Section header** (`MadarSectionHeader`): 12/700 uppercase tracked label, optional glyph,
optional trailing (a count in mono, or a ghost compact "See all"). It never repeats the page
title ("BILLS" under "Bills" is wrong). 12 above its content.

**List rows** (`MadarListRow`) — 64 min height, inset 20, hairline between siblings, flush
in a card:

| Variant | Anatomy | Use |
|---|---|---|
| `.nav` | glyph · title / meta · value word · chevron | Settings, Me, Till links |
| `.ledger` | sign disc (+/− glyph, success/danger) · title / meta · **signed** money | Cash in/out, Z/X lines, Sync |
| `.bill` | 4px rail · title / meta · money over pill · optional compact CTA · chevron | Bills, Queue, Me's bills, phone table rows |
| `.pick` | glyph · title / meta · radio / check | Printer, till, language |

Meta is facts joined by `' · '`, figures wrapped in `MadarFormat.ltr`. Selected bill rows
tint `accentBg` and show an accent rail.

**Summary lines** (`MadarSummaryLine`) — the arithmetic under a list, never a list of their
own: label (body, `textSecondary`) at the start, mono figure at the end, 36 tall, 48 for the
emphasised total (`title` label, `moneyMd` figure). No inset, hairline or tap of their own;
they sit in the card's inset under the rows they sum (a sale's subtotal / tax / total, the
drawer's expected cash). `muted` for a line shown for the record, `strike` for a total that no
longer stands.

## 8. Data table

`MadarDataTable<T>` — every record list with columns.

- **Columns** `MadarColumn`: `id`, `label`, one of `text` / `minor` (`.money`) /
  `status` (`.status`) / `cell`; `flex` or fixed `width`; `align` start/end; `mono`,
  `emphasis`, `muted`; `priority` (0 never hides, higher hides first when narrow);
  `phone` role (auto/title/meta/value/status/hidden).
- **Header** 44, surface, column labels 12/700 tracked muted, full hairline under it,
  **sticky** when the table scrolls. Header, rows and skeleton rows are laid by one grid, so
  columns cannot misalign (the old Past-shifts bug); the trailing action and chevron slots
  are reserved in the header whenever rows have them.
- **Rows** 64, hairlines, **no zebra**. Optional 4px status rail (`rail`), selected row
  (`selected`, accentBg + accent rail) for split views, 44 trailing action (`trailing`),
  chevron when `onTap`. Money end-aligned mono; ref column mono emphasis; time mono muted.
- **Expandable rows** (`expandedBuilder`): chevron-down rotates; nested content sits on the
  page ground (`bg`) inset 20, typically a `framed: false, scrollable: false` table.
  `onExpansionChanged` for lazy loading.
- **Phone / < 600 wide**: header goes; each row becomes a `.bill` row — title (first text
  column), meta (other text columns, priority ≤ 2), value (last end-aligned figure),
  pill (status column).
- **Load more**: one 56 footer, ghost compact button → `MadarSpinner` while loading.
  Always "Load more" (never "Show more"), and it stays visible under empty search results.
- **State is required** (`MadarTableState`): `.loading()` skeleton rows in the table's own
  grid; `.data(rows)` with an empty list draws the required `empty` content;
  `.error(message, retryLabel, onRetry)` draws `ErrorState`. A failed load is never shown as
  empty.
- Framed in a card (radius 16) by default; the card hugs its rows and scrolls when taller
  than its space; `scrollable: false` inside another scroll view.

## 9. Formats (core-owned)

Source of truth: `rust-core/crates/madar-core/src/display.rs`, exposed on the bridge as
`formatMoney`, `formatStamp`, `formatElapsed`, `formatElapsedSince`, `currencyLabel`.
`MadarFormat` in the kit is a synchronous mirror for widgets and table cells; both test
suites read `docs/design/format_fixtures.json`.

| | English | Arabic |
|---|---|---|
| Money | `EGP 1,234.50` | `⁦1,234.50⁩ ج.م` (figure LTR-isolated, label after) |
| Negative | `−EGP 50.00` (U+2212) | `⁦−50.00⁩ ج.م` |
| Signed (ledger) | `+EGP 20.00` | `⁦+20.00⁩ ج.م` |
| No currency | `1,234.50` | `⁦1,234.50⁩` |
| Currency label | ISO code | EGP ج.م · SAR ر.س · AED د.إ · KWD د.ك · QAR ر.ق · BHD د.ب · OMR ر.ع · JOD د.أ · else code |
| Stamp, same day | `18:02` | `18:02` |
| Stamp, this year | `Sep 12 · 18:02` | `12 سبتمبر · 18:02` |
| Stamp, other year | `Dec 31, 2025 · 23:30` | `3 يناير 2025 · 07:00` |
| Elapsed | `0m` · `42m` · `1h 05m` · `1d 03h` | `42 د` · `1 س 05 د` · `1 ي 03 س` |

Rules: thousands grouped, always two decimals, seconds dropped from elapsed, 24-hour stamps
in the **branch** timezone (`formatStamp` converts; `MadarFormat.stamp` expects branch
wall-clock). Receipts keep their own `TimeStyle.receipt`. `Money.format` without a locale is
the English shape (for strings assembled outside widgets); `MoneyText` follows the app
language.

## 10. Status pills

`MadarStatusPill(MadarStatus(label, tone, glyph?))`: 26 tall, pill radius, tone wash,
glyph 14 + 13/600 label, sentence case. **Never colour alone**: a status without a glyph
takes its tone's (neutral ◯ hollow, accent ◐ half, success ✓ checkCircle, warning ⚠
alertTriangle, danger ⊗ xCircle). `MadarTag` (uppercase, 8 radius) remains for transient
card states ("NEW", "READY"). The core decides the state; Dart only maps it to a status.

## 11. Empty, loading, error

- **Loading content** → skeletons (`MadarDataTable` loading, `SkeletonList`,
  `SkeletonBlock` in the content's own geometry). One shared pulse per screen.
- **Spinner policy**: `MadarSpinner` only inside a control that is working (button, pill,
  load-more). No raw `CircularProgressIndicator` in feature code; no full-screen spinners.
- **Empty** → `EmptyState` (badge icon, 16/600 title, 13 message, optional action). Always a
  sentence that says what will appear, never bare "No data".
- **Error** → `ErrorState` (danger badge, message, primary Retry). Messages name what failed
  (not "printer" for a report load).

## 12. RTL rules

- Everything directional uses `…Directional` / `start`/`end`; rows, headers, tables and rails
  mirror.
- **Figures never mirror**: money, times, refs and counts inside text are LTR-isolated
  (`MadarFormat.ltr`, U+2066…U+2069); `MoneyText` and table mono cells do it for you.
  Never force a whole Arabic string to `TextDirection.ltr` (that produced `د12`).
- Chevrons use mirrored glyphs (`chevronBack`/`chevronForward`).
- Physical space never mirrors: the floor canvas uses `Positioned`.
- No raw codes in Arabic: payment methods, order types, op names, statuses come localised
  from the core.

## 13. Touch targets

44pt minimum (iOS) / 48dp (Android) for anything tappable; rows are 64 and fully tappable;
header actions and trailing table actions are 44 tiles; the phone never puts two 44 targets
closer than 8. Every gesture has a visible, tappable equivalent (no long-press-only
actions).

## 14. Motion

`MotionSpec.standardDuration` 220ms ease-out for colour/opacity/expand/rotate;
`gentleDuration` 300ms for page and tab swaps; springs for press (`pressScale` 0.97,
rows 0.985) and sheets. All motion honours `MediaQuery.disableAnimations` (durations go to
zero; feedback tones down, never disappears).

## 14a. Confirmations

One entry point: `showMadarConfirm` (design_system) — danger-filled verb
button, not dismissible by tapping past it, `false` on anything but the verb.
The title names what is lost ("Clear 3 items from the cart?", "Discard
Ahmed?"); strings come from core i18n, EN and AR.

**Confirms:** clear cart · remove a cart line (swipe) · discard a parked
order · void a bill / a line (reason sheet) · unseat · cancel a queued table
transfer · move onto an occupied table · decline a delivery (reason sheet) ·
discard a stuck sync item · sign out · reconfigure device · a cash-drawer
movement · refund (its own sheet).

**Does not confirm** (cheap, reversible, or already its own screen): qty −
on a line that stays above zero, rename, hold/park, move to a free table
(Undo toast), mark a table cleared, remove a discount or member (re-add in
one tap), close shift (a full screen with a count and a Close button).

## 15. Screen map

| Screen | Width | Header | Body components |
|---|---|---|---|
| Sell | full | title (table name when targeted) | catalog grid + cart column (existing) |
| Floor | full, `bodyInset:false` | section segments in `below` | floor canvas; list mode `.bill` rows |
| Orders | full split | subtitle scope · search + scope segments in `below` | `MadarDataTable` (#, Time, Type, Payment, Total, Status) + 560 sale detail pane; phone: collapsed rows → pushed detail |
| Sale detail (sheet/pane) | form | `MadarHeader` (collapse) | ledger rows for lines/payments, Void / Refund as visible buttons |
| Queue | full | segments in `below` | `.bill` rows |
| Bills | reading | — | `.bill` rows, section header only when grouped |
| Till | full | subtitle open-since | `MadarStatCard` row, `.nav` links, `.ledger` recent movements |
| Close shift | full (pushed) | back · subtitle | ledger arithmetic card, count form, post-close Z print |
| Cash in/out | form (pushed) | back | segmented in/out, amount field, reason picks, `.ledger` list |
| Past shifts | reading (pushed) | back · branch subtitle · date action | `MadarDataTable` (Teller, Opened, Length, Declared, Δ, Status; print action; expand → nested orders table) |
| Z / X report sheet | sheet | `MadarHeader` | stat cards + `MadarDataTable(framed:false)` for methods and movements |
| Open shift (embedded) | form | no brand panel | amount field + primary button |
| Settings | reading (pushed) | back | profile card, `.pick` rows (language, printer, till), `.nav` rows |
| Me | reading | — | profile card, `.bill` my bills, `.nav` version / diagnostics / legal |
| Sync | reading (pushed) | back · status subtitle | `.ledger`-style op rows with pill + retry action |
| Table history sheet | sheet | `MadarHeader` | `MadarDataTable(framed:false, scrollable:false)` |
| Sign-in / setup / station picker | form, no shell | none (split auth layout) | fields, `.pick` rows; skeleton while stations load |
| KDS | full | own board | tickets (existing) |

Migration: a screen moves by passing `width:` (and `glyph:` for tab roots) to
`MadarPageScaffold`, replacing its private row/table widgets with the components above, and
its states with `MadarTableState`. The legacy header path goes when the last screen moves.
