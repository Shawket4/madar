# Madar POS — Product Context

## Register

**Product.** Design serves the task. The POS is an operational tool used mid-shift; the interface must disappear into the work. (The marketing/brand surface lives elsewhere; nothing in this repo is a landing page.)

## Users & Purpose

- **Tellers** in Egyptian cafés/restaurants, standing at a till, often under queue pressure, on mid-range tablets/desktops. Primary job: ring sales fast, park/resume held orders, manage floor tables.
- **Waiters** on handhelds: fire dine-in tickets in rounds, table-aware but never table-blocked.
- **Kitchen** staff on wall displays (KDS), glanceable at distance.
- Bilingual **English/Arabic (RTL)** — every string comes from the shared Rust core's i18n; layout must mirror cleanly.
- **Offline-first is the product's soul**: every action applies instantly against a local mirror and syncs later. UI must never imply a network wait.

## Brand & Personality

Ink-on-paper calm, teal accent (`#0D6273` light / `#2E94A6` dark), one type family, restrained color: tone is reserved for **state** (success/warning/danger/accent), never decoration. Money is the hero on money surfaces (heavy teal, tabular figures). Existing design system: `packages/design_system` — `MadarColors` (semantic tokens + `*Bg` tinted pairs, full dark theme), `MadarType`, `Space`, `Radii`, `MadarIcon` (SF-symbol-style names → Lucide), `MadarHaptics`, sheets/toasts/chips. The Flutter app is a pixel-and-behavior port of the Kotlin/Swift natives — consistency with them is a feature.

## Anti-references

- No decorative gradients, glassmorphism, or card-grids of identical tiles.
- No color-only state signaling (status always pairs tone with an icon/label).
- No orchestrated load choreography — the till loads into the task; motion is 150–250ms state feedback only.

## Accessibility

Touch-first hit targets (≥44px), haptic confirmation on selection/impact, contrast per WCAG AA on both themes, RTL-mirrored icons and layout.
