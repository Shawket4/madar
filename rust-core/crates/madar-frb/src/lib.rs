//! FRB binding surface for the Flutter app. Thin by construction: every method
//! delegates to [`madar_core::MadarCore`]; types are mirrored, never redefined
//! with different semantics. No business logic lives here.
pub mod api;
mod frb_generated;
