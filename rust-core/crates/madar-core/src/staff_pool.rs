//! The staff drinks pool — what a branch may give its own people in a day, and
//! the one place that decides it.
//!
//! The shop used to ring a staff drink as its own zero-priced twin of the real
//! item ("Latte staff" beside "Latte"). That hid staff consumption in a second
//! menu item nobody kept a recipe on, so the stock was never deducted and the
//! menu grew a shadow copy of itself. The pool replaces it: the REAL item is
//! rung, at zero, against an allowance that belongs to the BRANCH and resets
//! every business day.
//!
//! ## The rules (owner, 2026-09-19)
//!
//! * **The pool belongs to the branch, per day** — not to a person. There is no
//!   "who is this for" picker and a staff drink is never attributed to a staff
//!   member.
//! * **A note is REQUIRED.** Whitespace is not a note. The act is refused
//!   without one, because the note is the only record of who drank it and why,
//!   in the teller's own words.
//! * **Eligibility is a list.** Only the items in it count. An EMPTY list means
//!   the pool is off — a pool with no eligible items is not a pool.
//! * **An overspend is allowed and MARKED, never blocked.** The drink was
//!   already made and the sale already happened; refusing it after the fact
//!   would only lose the record. The (allowance+1)th drink of the day lands
//!   with `overspent: true`, and that flag is what the review queue, the
//!   reports and the Z report read.
//! * **The day is the branch's business day** — the same local-midnight to
//!   local-midnight boundary the Z report and the backend's
//!   `service_day_bounds` use, in the branch's timezone. Never midnight UTC:
//!   a shop in Cairo closing at 01:00 must not have its pool turn over while
//!   the last order is still being rung.
//!
//! ## One copy
//!
//! The till decides offline and the server re-decides at replay, so the rule
//! runs on both sides: it lives in madar-shared (`madar_money::staff_pool`),
//! pinned by its `staff_pool_vectors.json`. This module re-exports it; only the
//! business date keeps the till's `YYYY-MM-DD` string form.

pub use madar_money::staff_pool::{
    decide, note_is_given, pool_state, StaffDrinkDecision, StaffDrinkRefusal, StaffPoolDay,
    StaffPoolSettings,
};

/// The branch-local business date of an instant, `YYYY-MM-DD` — the same
/// boundary the Z report and the backend's `service_day_bounds` use
/// (`madar_money::staff_pool::business_date_of`).
pub fn business_date_of(tz: chrono_tz::Tz, at: chrono::DateTime<chrono::Utc>) -> String {
    madar_money::staff_pool::business_date_of(tz, at).to_string()
}
