//! The server-signed permission snapshot (PERMISSIONS_ARCHITECTURE §4.4).
//!
//! An activated device (it holds a credential from its activation code) fetches
//! `GET /devices/me/authz-snapshot`: every person who may sign in at its branch,
//! resolved there, signed by the server's Ed25519 key. The public keys come from
//! `GET /auth/authz-keys` over TLS and are kept on the device (trust on first
//! use, refreshed once when a snapshot names a key the device does not have).
//!
//! The snapshot is verified when it arrives AND every time it is read, so
//! editing the stored copy grants nothing. An offline unlock prefers the
//! verified snapshot's grants for the person over the feed's teller row when
//! the snapshot is at least as new (by org epoch).
//!
//! No expiry (locked owner decision): the server sets `expires_at` to the far
//! future, and `check_binding` still refuses a snapshot for another device or
//! branch.

use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use madar_authz::snapshot::{check_binding, SignedSnapshot, SnapshotBody, SnapshotProblem};

use crate::session::AuthzGrants;
use crate::MadarCore;

pub(crate) const K_AUTHZ_KEYS: &str = "authz:keys";
pub(crate) const K_AUTHZ_SNAPSHOT: &str = "authz:snapshot";

fn unhex<const N: usize>(s: &str) -> Option<[u8; N]> {
    let s = s.trim();
    if s.len() != N * 2 {
        return None;
    }
    let mut out = [0u8; N];
    for (i, c) in s.as_bytes().chunks(2).enumerate() {
        out[i] = u8::from_str_radix(std::str::from_utf8(c).ok()?, 16).ok()?;
    }
    Some(out)
}

/// Verify `signed` against the published keys (`[{kid, public_key}]` JSON) and
/// its binding to this device and branch.
pub(crate) fn verify(
    signed: &SignedSnapshot,
    keys_json: &str,
    device_id: &str,
    branch_id: &str,
    now: i64,
) -> Result<(), SnapshotProblem> {
    let keys: Vec<serde_json::Value> = serde_json::from_str(keys_json).unwrap_or_default();
    let key = keys
        .iter()
        .find(|k| k.get("kid").and_then(|x| x.as_str()) == Some(signed.kid.as_str()))
        .and_then(|k| k.get("public_key").and_then(|x| x.as_str()))
        .and_then(unhex::<32>)
        .ok_or(SnapshotProblem::UnknownKey)?;
    let vk = VerifyingKey::from_bytes(&key).map_err(|_| SnapshotProblem::UnknownKey)?;
    let sig = unhex::<64>(&signed.sig).ok_or(SnapshotProblem::BadSignature)?;
    vk.verify(&signed.body.signing_bytes(), &Signature::from_bytes(&sig))
        .map_err(|_| SnapshotProblem::BadSignature)?;
    check_binding(&signed.body, device_id, branch_id, now)
}

/// The grants a verified snapshot holds for one person.
pub(crate) fn grants_for(body: &SnapshotBody, user_id: &str) -> Option<AuthzGrants> {
    let u = body.user(user_id).filter(|u| u.active)?;
    Some(AuthzGrants {
        capabilities: u.eff.caps.keys().into_iter().map(str::to_string).collect(),
        ask_manager: u
            .eff
            .ask_manager
            .keys()
            .into_iter()
            .map(str::to_string)
            .collect(),
        limits: u
            .eff
            .limits
            .iter()
            .filter_map(|(id, l)| madar_authz::Cap::from_id(*id).map(|c| (c.key().to_string(), *l)))
            .collect(),
        owner: u.eff.owner,
    })
}

impl MadarCore {
    fn device_credential(&self) -> Option<String> {
        self.store
            .kv_get(crate::K_DEVICE_CREDENTIAL)
            .ok()
            .flatten()
            .filter(|t| !t.is_empty())
    }

    async fn fetch_authz_keys(&self) -> Option<String> {
        let keys = self.api.get_with_headers("/auth/authz-keys", &[]).await.ok()?;
        let _ = self.store.kv_put(K_AUTHZ_KEYS, &keys);
        Some(keys)
    }

    /// Fetch, verify and keep this device's snapshot. Best-effort and silent: a
    /// device bound the old way has no credential, an older backend has no
    /// endpoint, and either way the feed's teller rows stand in.
    pub(crate) async fn refresh_authz_snapshot(&self) {
        let Some(token) = self.device_credential() else { return };
        let Some(branch) = crate::device::load(&self.store).branch_id else { return };
        let device = self.lan_device_id();
        let Ok(text) = self
            .api
            .get_with_headers(
                "/devices/me/authz-snapshot",
                &[("X-Madar-Device", &device), ("X-Madar-Device-Token", &token)],
            )
            .await
        else {
            return;
        };
        let Ok(signed) = serde_json::from_str::<SignedSnapshot>(&text) else { return };
        let now = chrono::Utc::now().timestamp();
        let mut keys = self.store.kv_get(K_AUTHZ_KEYS).ok().flatten().unwrap_or_default();
        let mut result = verify(&signed, &keys, &device, &branch, now);
        if result == Err(SnapshotProblem::UnknownKey) {
            if let Some(fresh) = self.fetch_authz_keys().await {
                keys = fresh;
                result = verify(&signed, &keys, &device, &branch, now);
            }
        }
        if result.is_ok() {
            let _ = self.store.kv_put(K_AUTHZ_SNAPSHOT, &text);
        }
    }

    /// Whether this device holds a server-signed permission snapshot that
    /// verifies for its bound branch right now (diagnostics and scenarios).
    pub fn has_verified_authz_snapshot(&self) -> bool {
        crate::device::load(&self.store)
            .branch_id
            .is_some_and(|b| self.verified_snapshot(&b).is_some())
    }

    /// The stored snapshot, re-verified now; `None` when absent or not valid.
    pub(crate) fn verified_snapshot(&self, branch: &str) -> Option<SnapshotBody> {
        let raw = self.store.kv_get(K_AUTHZ_SNAPSHOT).ok().flatten()?;
        let keys = self.store.kv_get(K_AUTHZ_KEYS).ok().flatten()?;
        let signed: SignedSnapshot = serde_json::from_str(&raw).ok()?;
        let now = chrono::Utc::now().timestamp();
        verify(&signed, &keys, &self.lan_device_id(), branch, now).ok()?;
        Some(signed.body)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};
    use madar_authz::snapshot::SnapshotUser;
    use madar_authz::{Cap, EffectiveSet};

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    fn signed(key: &SigningKey, body: SnapshotBody) -> SignedSnapshot {
        SignedSnapshot {
            kid: "k1".into(),
            sig: hex(&key.sign(&body.signing_bytes()).to_bytes()),
            body,
        }
    }

    fn body() -> SnapshotBody {
        let mut eff = EffectiveSet::default();
        eff.caps.insert(Cap::PosSignIn);
        SnapshotBody {
            v: SnapshotBody::VERSION,
            spec_version: madar_authz::SPEC_VERSION,
            org_id: "o".into(),
            branch_id: "b".into(),
            device_id: "d".into(),
            org_epoch: 7,
            issued_at: 1,
            expires_at: i64::MAX,
            policy: Default::default(),
            users: vec![SnapshotUser {
                user_id: "u".into(),
                name: "Sara".into(),
                legacy_role: "teller".into(),
                is_owner: false,
                active: true,
                eff,
            }],
        }
    }

    #[test]
    fn only_an_untouched_snapshot_for_this_device_and_branch_verifies() {
        let key = SigningKey::from_bytes(&[7u8; 32]);
        let keys = serde_json::json!([{"kid": "k1", "public_key": hex(key.verifying_key().as_bytes())}]).to_string();
        let s = signed(&key, body());
        assert_eq!(verify(&s, &keys, "d", "b", 100), Ok(()));
        assert_eq!(verify(&s, &keys, "other", "b", 100), Err(SnapshotProblem::WrongDevice));
        assert_eq!(verify(&s, &keys, "d", "other", 100), Err(SnapshotProblem::WrongBranch));
        assert_eq!(verify(&s, "[]", "d", "b", 100), Err(SnapshotProblem::UnknownKey));

        // Granting yourself something after the fact breaks the signature.
        let mut forged = s.clone();
        forged.body.users[0].eff.caps.insert(Cap::TillForceClose);
        assert_eq!(verify(&forged, &keys, "d", "b", 100), Err(SnapshotProblem::BadSignature));

        // Someone else's key signing a generous body is not trusted.
        let rogue = signed(&SigningKey::from_bytes(&[9u8; 32]), body());
        assert_eq!(verify(&rogue, &keys, "d", "b", 100), Err(SnapshotProblem::BadSignature));

        let g = grants_for(&s.body, "u").unwrap();
        assert!(g.capabilities.contains(&Cap::PosSignIn.key().to_string()));
        assert!(grants_for(&s.body, "nobody").is_none());
    }
}
