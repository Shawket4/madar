//! One-time backfill of pre-B stores into the ledger rows (store step 4).
use rusqlite::Transaction;

use crate::error::CoreResult;

pub(crate) fn backfill(_tx: &Transaction<'_>) -> CoreResult<()> {
    Ok(())
}
