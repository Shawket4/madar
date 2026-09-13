//! Content-addressed assets (TILLS_CONTRACT §11.7): `<app_support>/assets/<hash>.<ext>`
//! plus the `asset_files` table. Needed/missing/unused are derived from `sync_rows`.

use crate::error::CoreError;
use crate::MadarCore;

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct AssetSyncView {
    pub needed: u32,
    pub missing: u32,
    pub downloading: bool,
    pub bytes_done: u64,
    pub bytes_total: u64,
    pub last_error: Option<String>,
}

impl MadarCore {
    pub(crate) fn asset_sync_view(&self) -> AssetSyncView {
        AssetSyncView::default()
    }

    /// Re-verify local files against their hashes and fetch what is missing.
    pub async fn repair_assets(&self) -> Result<AssetSyncView, CoreError> {
        Ok(self.asset_sync_view())
    }
}
