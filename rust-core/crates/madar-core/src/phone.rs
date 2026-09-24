//! The one canonical phone form: E.164 digits without `+` (`201001234567`).
//!
//! The rule is madar-shared's (`madar_ids::phone`), the one copy the backend
//! runs too; the backend's SQL `phone_canonical` and the dashboard's
//! `src/lib/phone.ts` are pinned to it by `madar_ids::vectors::PHONE`.

pub use madar_ids::phone::{canonical, digits};
