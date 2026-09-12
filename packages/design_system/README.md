# design_system — Madar POS, system v2

The visual system the till is built from. Every feature package imports this
and nothing else for colour, type, size, or chrome. The approved design is
`pos-ui-sketch.md` + the canvas ("Madar POS Redesign"); this package is that
design as Flutter.

## The system in one paragraph

Dark chrome around a paper work surface. Flat teal primary, ink-tinted (sunk
grey) secondary, filled danger. No gradients, no glows, no hairline-outline
buttons. 16px cards, 64px rows, 52px fields, 56px buttons (44 small), a 64px
money bar, 72px amount field. IBM Plex Sans Arabic for words, IBM Plex Mono
for every figure — tabular, always an LTR island. A 24-grid, 2.5-stroke
duotone glyph set that fills when a tab is active. Everything mirrors under
RTL except figures, the floor plan, the PIN pad and printed paper.

## Where things are

| Need | Use |
|---|---|
| Colour roles | `context.madarColors` — `bg surface surfaceAlt border borderLight textPrimary/Secondary/Muted accent accentDeep accentBg success danger warning (+Bg) chrome chromeAlt chromeRaised onChrome onChromeMuted` |
| Type | `MadarType.h1 h2 h3 title body bodySm label button buttonSm` · figures `money moneyMd moneyLg moneyDisplay moneyHero num numMd numLg` |
| Sizes | `Space`, `Radii.control/card/sheet`, `Metrics.*`, `IconSize.*` |
| Which device | `MadarLayout.of(context)` → `phone` / `tablet` (shortest side ≥ 600). `MadarLayoutSwitch`. Container-width decisions: `Responsive` / `ResponsiveBuilder` |
| Buttons | `MadarButton` (primary · secondary · ghost · danger · ink; regular 56 · compact 44), `MadarMoneyBar` (64, carries the amount), `MadarGlyphTile` |
| Fields | `MadarField`, `MadarAmountField` |
| Cards, rows | `MadarCard` (`flush:` for rows, `selected:` for a chosen tile), `MadarRow` (64, `bar:` for the state stripe), `MadarHairline.row()`, `MadarSectionHeader` |
| Chips etc. | `MadarChip` / `MadarChip.tile`, `MadarSegmented`, `MadarTag`, `MadarStepper` |
| Chrome | `MadarShellScaffold` (rail on tablet, bottom tabs on phone), `MadarRail`, `MadarTabBar`, `MadarTopBar`, `MadarOutboxPill` (`OutboxState.synced/queued/offline/stuck`), `MadarTab`, `MadarPerson`, `MadarBadge`, `MadarAvatar` |
| Icons | `MadarGlyphIcon(MadarGlyph.x, filled: active)`. `MadarIcon('sf.name')` still works and routes to the same set where it covers the name |
| Overlays | `showMadarSheet` (600 cap on a tablet), `showMadarModal` + `MadarModalBody` |
| In-page header | `MadarHeader` (48, h1, back tile) |

## Rules that are not optional

- **Strings arrive localised.** Nothing here calls `tr`; every label is a parameter.
- **Figures are mono and LTR.** Use `MoneyText`, `MadarType.num*`, or set `textDirection: TextDirection.ltr` yourself.
- **Logical directions only.** `EdgeInsetsDirectional`, `PositionedDirectional`, `start/end`. The glyph set mirrors what should mirror; do not flip by hand.
- **Disable honestly.** A disabled button takes `tooltip:`; a disabled money bar takes `reason:`.
- **Compatibility names** — `MadarButtonVariant.outline` (draws secondary), `MadarSectionHeader.tick`, `MadarHeader.tinted`, `MadarElevation.card/glow` (draw nothing) — exist so old screens compile. New code does not use them.

## Seeing it

```
flutter test test/controls_render_test.dart --dart-define=MADAR_RENDER=true
```

writes `build/render/kit-{light,dark}.png`, `shell-ipad-{light,dark}.png` and
`shell-phone-ar.png` with the real Plex faces loaded. Look before you ship.
`GalleryScreen` is the same thing on a device.
