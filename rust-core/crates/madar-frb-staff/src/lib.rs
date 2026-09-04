//! FRB binding surface for the Madar EMPLOYEE STAFF app. Thin by construction:
//! every method delegates to [`madar_core::MadarCore`]; types are mirrored, never
//! redefined. No business logic lives here.
//!
//! This is a SEPARATE bindings binary from `madar-frb` (teller/POS) and
//! `madar-frb-dashboard` (management). It exposes ONLY employee self-service —
//! clock in/out, own attendance, own leave, own payslips. The POS operations
//! (checkout, till, KDS, printing) and the whole admin surface (rosters,
//! approvals, payroll runs, anyone else's salary) are deliberately absent, so
//! this binary neither links nor exports them. That matters more here than in the
//! other two: this is the binary that ends up on every employee's personal phone.
pub mod api;
mod frb_generated;
