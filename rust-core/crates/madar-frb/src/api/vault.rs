//! Host-vault inversion: the core's `TokenStore` callback becomes a Dart
//! `Stream<VaultCommand>`. The Dart side persists the opaque blob to secure
//! storage IMMEDIATELY on each event (fire-and-forget by design — same
//! durability class as the native hosts).
use crate::frb_generated::StreamSink;

/// One command from the core's token custody to the host vault.
pub enum VaultCommand {
    /// Persist this opaque session blob (Keychain/Keystore equivalent).
    Save { blob: Vec<u8> },
    /// Wipe the persisted blob (logout / hard expiry).
    Clear,
}

pub(crate) struct SinkTokenStore(pub(crate) StreamSink<VaultCommand>);

impl madar_core::session::TokenStore for SinkTokenStore {
    fn save_blob(&self, blob: Vec<u8>) {
        // A closed sink (hot restart teardown) drops the command; the next
        // login re-persists. Never block or panic on the core's thread.
        let _ = self.0.add(VaultCommand::Save { blob });
    }

    fn clear_blob(&self) {
        let _ = self.0.add(VaultCommand::Clear);
    }
}
