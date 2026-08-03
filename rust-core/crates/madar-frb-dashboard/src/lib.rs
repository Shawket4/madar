//! FRB binding surface for the Madar MANAGEMENT DASHBOARD app. Thin by
//! construction: every method delegates to [`madar_core::MadarCore`]; types are
//! mirrored, never redefined. No business logic lives here.
//!
//! This is a SEPARATE bindings binary from `madar-frb` (the teller/POS bridge).
//! It exposes ONLY the dashboard surface (auth, scope, branches, analytics,
//! i18n) — the teller operations (checkout, till, KDS, printing, realtime) are
//! deliberately absent, so this binary neither links nor exports them.
pub mod api;
mod frb_generated;
