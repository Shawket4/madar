# Feature-port contract (Flutter → Slint), Madar POS

You are porting ONE feature package from the Flutter app to this Slint app.
The requirement is a 1:1 EXACT replica — same layouts, metrics, colors,
type sizes/weights, spacing, behaviors, animations. The Flutter source is
the specification; port it literally, comment-for-comment where comments
explain intent.

## Deliverables (write ONLY these files)
1. `ui/feature_<name>.slint` — all screens/sheets/widgets of the feature.
   Export one root component per screen (e.g. `SettingsScreen`) plus a
   `<Name>State` global for data/strings and callbacks-out. Sheets are
   `SheetFrame { open: ... }` overlays owned by the screen.
2. `src/feature_<name>.rs` — Rust glue: data structs mapping core views →
   slint structs, async core calls via `rt().spawn` + `invoke_from_event_loop`
   (copy the patterns in src/main.rs), localization setters (core.tr keys
   exactly as the Dart source uses them).
3. `NOTES-<name>.md` — wiring the integrator must do in app.slint/main.rs
   (imports, Screen enum entries, callback hookups), core APIs used, any
   parity compromise you had to make and why.

DO NOT EDIT any other file. Shared files (app.slint, main.rs, tokens.slint,
components.slint, kit.slint, sheet.slint, icons.slint, kds.slint,
auth.slint, Cargo.toml, build.rs) are read-only reference. If the kit lacks
a component you need, define it locally in your feature file and flag it in
NOTES for later promotion.

## The kit (import, don't reinvent)
- `tokens.slint`: `T` (all color roles, shadows, dark/rtl), `Sp`, `Rd`, `Ic`
- `components.slint`: `Press` (TactileScale), `Icon`, `Chip`+`Tone`,
  `Banner`, `Spinner`, `CTA`, `Field`, `SurfaceCard`, `SectionHeader`
- `kit.slint`: `MadarHeader`, `HeaderAction`, `MoneyText`, `SkeletonBlock/
  Row/List`, `EmptyState`, `ErrorState`, `ToastHost`, `Rsp` (width caps)
- `sheet.slint`: `SheetFrame` (scrim, drag-dismiss, springs, `dismissed`)
- `icons.slint`: `Icons.<name>` — every MadarIcon catalog name with dots →
  dashes (`'person.fill'` → `Icons.person-fill`). Compile-time verified.

## Slint gotchas (violating these costs hours — all battle-verified)
1. NEVER use `states` blocks with `in`/`out` transition animations — they
   silently break subtree rendering. Use inline ternary bindings +
   per-property `animate`.
2. Explicit `height:` does NOT feed layout sizing. Any composed component
   (esp. anything wrapping `Press`) must pin `preferred-height` AND
   `min-height` (and width equivalents when horizontal).
3. `transform-scale-*`/`transform-rotation` never on a component root; put
   them on an inner element. (`rotation-angle` is deprecated.)
4. No Text line-height → for multi-line display text, pre-split lines into
   fixed-height rows. No strikethrough → hairline Rectangle overlay at
   first-line center (see kds.slint LineRow). No letter-spacing tracking
   issues otherwise.
5. `@children` cannot be inside `if` conditionals — gate with
   `visible:` instead. Avoid `function` + Timer combos that ICE the
   compiler; prefer inlined callback statements (see sheet.slint).
6. Reserved property names: `max-width`, `height` conflicts — prefix custom
   ones (`sheet-max-width`).
7. RTL: no automatic mirroring. Every directional thing takes
   `T.rtl ? ... : ...` (x positions, chevron `transform-rotation: T.rtl ?
   180deg : 0deg`, sweep directions). Text bidi/shaping is automatic (Skia).
8. Springs don't exist; approximations: press = 160ms ease-out-back;
   sheet/slide = cubic-bezier(0.16,1,0.3,1) 420ms; standard fades = 220ms
   ease-out; bouncy pops = ease-out-back 260ms; `springOut` celebratory =
   cubic-bezier(0.34,1.56,0.64,1).
9. Scrolling: `Flickable` with `viewport-height: <content>.preferred-height`;
   grids are computed-column row loops (see kds.slint board).
10. Models: `in property <[StructName]>`; structs may contain `[T]` (nested
    ModelRc in Rust). Struct/global declarations must precede use in-file.

## Rust glue patterns (copy from src/main.rs)
- One tokio runtime: `rt()`. UI thread hops: `on_ui(app, |ui, app| ...)`.
- Async call shape: clone Arc, `rt().spawn(async move { ... })`, marshal
  results back with `invoke_from_event_loop`.
- Errors: `human_message(&core, &e)` (already in main.rs).
- Money: format in Rust with the exact Money.format algorithm (in
  `src/main.rs` or duplicate locally): `CODE W.FF`, uppercased code,
  leading `-`, empty code → bare amount. Time: `core.format_time(rfc, style)`.
- Localization: resolve every `tr key` used by the Dart source via
  `core.tr("key".into())` into the feature's slint global.

## Fidelity checklist before you finish
- Every metric literal in the Dart file appears in your port (grep your own
  output for the numbers).
- Every `tr('...')` key is wired.
- Light AND dark work (only use `T` roles, never hex).
- RTL positions mirrored.
- Empty/loading/error states ported, not just the happy path.
- All Dart animations have a Slint approximation, not omissions.
