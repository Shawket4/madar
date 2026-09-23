//! What a bill adds up to, and the only place that decides it.
//!
//! The engine lives in madar-shared (`madar_money::tax`), the one copy both the
//! till and the server run. It used to be here, kept in step with the server's
//! copy by a hand-copied `tax_vectors.json`; the vectors are madar-money's own
//! tests now. This module keeps the paths the core already imports.

pub use madar_money::tax::{
    compute, discount_amount, negative_part, refund_split, Breakdown, Discount, Minor,
    NegativePart, SaleChannel, TaxPolicy,
};
