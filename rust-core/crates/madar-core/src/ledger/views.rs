//! Ledger read paths: history rows, the drawer, the Z report, past tills,
//! refunds, order detail — local queries only, no network inside a read.

use serde_json::Value;

use super::report::Method;
use crate::store::Store;

/// The org payment methods as the till report needs them: the changefeed's
/// rows when the branch has them (they carry `created_at`), else the cached
/// catalogue.
pub(crate) fn payment_method_rows(store: &Store) -> Vec<Method> {
    let raw = store.kv_get(crate::menu::K_PAYMENT_METHODS).ok().flatten().unwrap_or_default();
    serde_json::from_str::<Vec<Value>>(&raw)
        .unwrap_or_default()
        .iter()
        .filter_map(Method::from_json)
        .collect()
}
