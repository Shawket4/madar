# Madar Kitchen (مطبخ مدار)

The kitchen display, in React Native (Expo, TypeScript), to
[`docs/specs/kitchen-target-spec.md`](../../docs/specs/kitchen-target-spec.md).
**This is the design pass on mock data (APP-11):** nothing here talks to the
server or the Rust core yet.

## Run

```sh
cd apps/kitchen
npm install
npm run web        # browser, fastest to review
npm run ios        # iPad simulator (Expo Go)
npm run android    # Android tablet emulator (Expo Go)
npm test           # board rules + en/ar key parity (node --test)
npm run typecheck
```

Mock PINs: cooks `111111`, `222222`; manager `999999`.
Settings → *Mock tools* fakes the network (online / LAN only / offline) and
sends test orders.

## What's in the design

| Screen | Spec |
|---|---|
| Device setup: branch, then section(s) or expo, confirmed by a manager PIN | DV-1, KB-1, EX-1 |
| Section board: cards oldest first, age tint at 5 / 10 min, line and whole-part bump, rounds, voids struck through, notes | KB-2..4, OF-2, OF-4, OF-5 |
| All-day strip | KB-6 |
| Recall of parts bumped in the last 10 min | KB-4 |
| Offline / LAN-only banner with bumps waiting to sync | KB-7 |
| Staff PIN; bumping signed out asks for a PIN, then bumps | DV-2, DV-5 (proposed answer) |
| Expo: whole orders, each section waiting / cooking / done, ready lane, hand off, reprint | EX-1..4, PR-4 |
| Dark by default, light option; Arabic first with live RTL; Latin digits | APP-6, APP-7 |

## Layout (the dashboard's)

```
src/
  app.tsx              root: fonts, language, which screen the device shows
  theme/tokens.ts      system v2 tokens — same values as MadarDashboard globals.css
  components/ui/       primitives: Txt, Button (+ Segmented), Sheet
  components/app/      composed: StatusPill, EmptyState, SectionHeader, TopBar, NetBanner
  features/<name>/     board · expo · setup · auth · settings
  data/                types (named after madar-shared madar-kitchen), mock seed, Zustand store
  i18n/locales/        en.json, ar.json — every string through t()
```

## Not yet (by design)

- No core or backend: `data/store.ts` is the mock. Wiring replaces its
  actions with core calls through a `uniffi-bindgen-react-native` binding
  (APP-1) and its reads with React Query; the screens keep their hooks.
- `features/board/logic.ts` mirrors board rules that belong in `madar-core`
  `kds.rs` (APP-2); it goes when the binding lands.
- No chime audio (KB-5) or printing (PR-*); the switches and buttons are there.
- Accent and icon are placeholders (APP-5 is open): Madar teal and the Expo default.
