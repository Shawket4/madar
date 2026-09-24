//! Session & auth (PLAN §7.2, §R3). The core owns the live session; the host is
//! a dumb secure-bytes vault (`TokenStore`, backed by Keychain/Keystore).
//!
//! Two entry paths, one identity model:
//!   - **online `login`** — PIN (`name`+`pin`+device `branch_id`, org derived
//!     server-side) or email+password; mints a bearer, mirrors permissions, and
//!     caches the org's offline-auth bundle for later offline unlock.
//!   - **offline `unlock_offline`** — verifies a typed PIN against the cached
//!     org bundle (argon2id, byte-compatible with the backend). No token; the
//!     identity is the real server `user_id`. Sync forces a fresh online re-auth.
//!
//! This module holds the FFI types + pure logic; the exported `MadarCore`
//! methods that orchestrate the network live in `lib.rs`.

use madar_api::models;
use serde::{Deserialize, Serialize};

use crate::error::{CoreError, CoreResult};
use crate::store::Store;

/// kv key holding the org's offline-auth bundle (one org per device).
pub(crate) const BUNDLE_KEY: &str = "offline_auth_bundle";
/// kv key holding `{org_id, currency_code, tax_rate}` cached at online login, so
/// an offline unlock can build a complete `SessionSnapshot`.
pub(crate) const ORG_CONFIG_KEY: &str = "org_config";

// ── FFI surface ─────────────────────────────────────────────────────────────

/// Store key for the persisted session blob. The core owns session
/// durability end-to-end now: the blob lives PLAINLY in the core's SQLite,
/// protected by the OS's file-based encryption + token expiry + server-side
/// revocation (the deliberate threat-model call: an attacker who can read
/// app-private storage can also read process memory, and the logged-in UI
/// on a countertop POS is the bigger surface anyway — see the vault ADR in
/// the commit that removed flutter_secure_storage).
pub(crate) const K_SESSION_BLOB: &str = "session:blob";

/// PIN (tellers) xor email+password (managers/admins). Enforced in Rust, not the
/// all-`Option` wire.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Enum))]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum LoginMode {
    Pin,
    Email,
}

/// A login attempt. Field requirements depend on `mode` (validated in
/// `wire_login_request`): PIN needs `name`+`pin`+`branch_id`; Email needs
/// `email`+`password` (`org_id` optional).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct LoginRequest {
    pub mode: LoginMode,
    /// Teller display name (PIN mode).
    pub name: Option<String>,
    pub pin: Option<String>,
    /// The device's configured branch (PIN mode). The server derives the org
    /// from it; post-D13 the teller need not be assigned to it.
    pub branch_id: Option<String>,
    pub email: Option<String>,
    pub password: Option<String>,
    /// Optional org disambiguator (Email mode).
    pub org_id: Option<String>,
}

/// A selectable branch (device-setup picker).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct BranchView {
    pub id: String,
    pub name: String,
    pub is_active: bool,
    /// The org's logo URL (resolved per-branch), shown on the receipt header.
    /// The host persists this alongside the branch name at selection so the
    /// receipt preview/print can render the brand logo (with an asset fallback).
    pub org_logo_url: Option<String>,
}

/// The cached session the host renders chrome from. Money/tax are pre-resolved.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SessionSnapshot {
    pub user_id: String,
    pub display_name: String,
    pub role: String,
    pub org_id: Option<String>,
    pub branch_id: Option<String>,
    pub currency_code: String,
    /// Fraction, NOT a percentage: `0.14` is 14%.
    pub tax_rate: f64,
    /// `true` = menu prices already contain the tax, and the receipt breaks it
    /// out backwards rather than adding it on.
    pub tax_inclusive: bool,
    /// Fraction of the bill added as a service charge; `0` disables it.
    pub service_charge_rate: f64,
    /// Whether the service charge is itself taxed.
    pub service_charge_taxable: bool,
    /// Every dine-in sale belongs to a table.
    ///
    /// Changes what the till PUTS IN FRONT of a teller, not just what the
    /// server will accept: the floor becomes the home screen and a sale starts
    /// by picking a table. A refusal after the items are rung up is far too
    /// late to be useful.
    pub require_table_for_orders: bool,
    /// `false` for an offline-unlocked session (no live token; sync will force a
    /// fresh online re-auth before it flushes the queue).
    pub online: bool,
    /// `true` once `/auth/permissions` has been mirrored. While `false`
    /// (offline unlock), `has_permission` is optimistic — the backend is the
    /// authority and validates the teller at replay.
    pub permissions_loaded: bool,
}

impl SessionSnapshot {
    /// The tax policy to price under, in the shared engine's shape.
    ///
    /// Signed out, this is `TaxPolicy::default()` — tax-free. That is
    /// deliberate: a till with no session must not invent a rate, and the old
    /// `unwrap_or(0.0)` on the rate alone silently dropped a service charge and
    /// tax-inclusive pricing on the floor.
    pub(crate) fn tax_policy(&self) -> crate::tax::TaxPolicy {
        use std::str::FromStr;
        let rate = |r: f64| rust_decimal::Decimal::from_str(&r.to_string()).unwrap_or_default();
        crate::tax::TaxPolicy {
            tax_rate: rate(self.tax_rate),
            tax_inclusive: self.tax_inclusive,
            service_charge_rate: rate(self.service_charge_rate),
            service_charge_taxable: self.service_charge_taxable,
        }
    }

    /// The policy a COUNTER sale is priced under: a cart rung straight
    /// through the till (counter, takeaway, a parked cart) is a takeaway, and
    /// the service charge is dine-in only. The rule is the shared engine's
    /// (`TaxPolicy::for_sale`), pinned against the server by `tax_vectors.json`
    /// — pricing a counter cart with the branch's charge on it is the sale the
    /// server refused with "This till priced the order at …".
    pub(crate) fn counter_policy(&self) -> crate::tax::TaxPolicy {
        self.tax_policy()
            .for_sale(crate::tax::SaleChannel::Takeaway, false)
    }
}

// ── internal state (held by MadarCore) ─────────────────────────────────────

#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct PermissionEntry {
    pub resource: String,
    pub action: String,
    pub granted: bool,
}

/// The only grants assumed while a session's permissions are not loaded: ringing
/// up and taking payment for a sale, working a table's bill, and the kitchen
/// screen. Everything else waits for the real grants.
pub(crate) const SELL_WHILE_UNLOADED: &[(&str, &str)] = &[
    ("orders", "create"),
    ("orders", "read"),
    ("payments", "create"),
    ("open_tickets", "create"),
    ("open_tickets", "read"),
    ("open_tickets", "update"),
    ("kitchen_orders", "read"),
    ("kitchen_orders", "update"),
    ("menu_items", "read"),
    ("categories", "read"),
];

/// A person's effective capabilities (architecture E) as the server resolved
/// them: `GET /authz/me` online, the synced teller row's `capabilities` offline.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub(crate) struct AuthzGrants {
    pub capabilities: Vec<String>,
    #[serde(default)]
    pub ask_manager: Vec<String>,
    #[serde(default)]
    pub limits: std::collections::BTreeMap<String, madar_authz::Limits>,
    #[serde(default)]
    pub owner: bool,
}

/// The live session the core holds in memory (and persists, minus nothing, into
/// the host's secure blob).
#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct SessionState {
    pub snapshot: SessionSnapshot,
    pub permissions: Vec<PermissionEntry>,
    /// `None` for an offline-unlocked session.
    pub token: Option<String>,
    /// `None` until capabilities are known (an older backend, or not loaded yet);
    /// [`SessionState::can`] then answers from the legacy grid.
    #[serde(default)]
    pub authz: Option<AuthzGrants>,
}

impl SessionState {
    /// Does this session grant `resource`/`action`?
    ///
    /// Until the grants are loaded (an offline unlock on a device whose feed
    /// holds no row for this person, or a failed fetch) the answer is DENY,
    /// except for the plain selling acts in [`SELL_WHILE_UNLOADED`], so offline
    /// selling continues. Money exceptions (voids, refunds, discounts, cash
    /// movements, waivers) are never assumed: offering them on a guess used to
    /// dead-letter the sale at replay (audit S7).
    pub fn has_permission(&self, resource: &str, action: &str) -> bool {
        if !self.snapshot.permissions_loaded {
            return SELL_WHILE_UNLOADED.contains(&(resource, action));
        }
        self.permissions
            .iter()
            .any(|p| p.resource == resource && p.action == action && p.granted)
    }

    /// Like [`Self::has_permission`], but never optimistic: `false` until the
    /// grants are actually loaded. For acts the server would refuse on replay
    /// after the money is taken — removing a service charge — offering them on
    /// a guess would dead-letter a paid bill.
    pub fn has_granted_permission(&self, resource: &str, action: &str) -> bool {
        self.snapshot.permissions_loaded
            && self
                .permissions
                .iter()
                .any(|p| p.resource == resource && p.action == action && p.granted)
    }

    /// Does this session hold capability `key`? Ask this, never the role.
    ///
    /// - Capabilities known (server `/authz/me` or the feed's teller row): exact.
    /// - Otherwise, grants loaded from `/auth/permissions` (an older backend): a
    ///   capability with a legacy cell answers from that cell; a newer one
    ///   (no cell) from the role kind's registry defaults.
    /// - Nothing loaded: only the plain selling acts ([`SELL_WHILE_UNLOADED`]).
    pub fn can(&self, key: &str) -> bool {
        let Some(cap) = madar_authz::Cap::from_key(key) else {
            return false;
        };
        if let Some(a) = &self.authz {
            return a.capabilities.iter().any(|c| c == key);
        }
        let meta = cap.meta();
        match meta.legacy {
            Some((r, a)) => self.has_permission(r, a),
            None => {
                self.snapshot.permissions_loaded
                    && madar_authz::RoleKind::parse(&self.snapshot.role)
                        .map(|k| meta.defaults.contains(k))
                        .unwrap_or(false)
            }
        }
    }

    /// Not held, but the owner lets this person ask a manager to approve it.
    pub fn can_ask(&self, key: &str) -> bool {
        !self.can(key)
            && self
                .authz
                .as_ref()
                .map(|a| a.ask_manager.iter().any(|c| c == key))
                .unwrap_or(false)
    }

    /// The kind of work this person does on a device — `"kitchen"`, `"waiter"`
    /// or `"teller"` — from their capabilities, not their role name: someone who
    /// takes money works a till; someone who only reads the kitchen screen is
    /// the kitchen; everyone else works tables. It picks the route, the realtime
    /// topics, the alerts and the LAN advert (whose `role` older peers read with
    /// exactly these three meanings). With nothing loaded yet it falls back to
    /// the role's kind, since a guess from the selling defaults would put a
    /// kitchen screen on a till.
    pub fn work_kind(&self) -> &'static str {
        if self.authz.is_none() && !self.snapshot.permissions_loaded {
            return match self.snapshot.role.as_str() {
                "kitchen" => "kitchen",
                "waiter" => "waiter",
                _ => "teller",
            };
        }
        use madar_authz::Cap;
        let can = |c: Cap| self.can(c.key());
        if can(Cap::PaymentsTake) || can(Cap::TillOpen) {
            "teller"
        } else if can(Cap::KitchenDisplayRead) && !can(Cap::OrdersCreate) && !can(Cap::TicketsOpen) {
            "kitchen"
        } else {
            "waiter"
        }
    }

    /// Every capability key this session holds.
    pub fn capabilities(&self) -> Vec<String> {
        madar_authz::Cap::all()
            .map(|c| c.key())
            .filter(|k| self.can(k))
            .map(str::to_string)
            .collect()
    }

    /// Serialize for the host's secure vault.
    pub fn to_blob(&self) -> Vec<u8> {
        serde_json::to_vec(self).unwrap_or_default()
    }

    pub fn from_blob(blob: &[u8]) -> Option<SessionState> {
        serde_json::from_slice(blob).ok()
    }
}

// ── pure helpers ────────────────────────────────────────────────────────────

/// Validate the per-mode invariants and build the wire `LoginRequest`.
pub(crate) fn wire_login_request(req: &LoginRequest) -> CoreResult<models::LoginRequest> {
    let mut w = models::LoginRequest::new();
    match req.mode {
        LoginMode::Pin => {
            // PIN-only sign-in (POS_SIGNIN_OVERHAUL §8.5): the name is
            // optional — the backend finds the person by the PIN alone.
            let name = req
                .name
                .as_deref()
                .map(str::trim)
                .filter(|n| !n.is_empty())
                .map(str::to_string);
            let pin = nonblank(&req.pin, "pin")?;
            let branch = nonblank(&req.branch_id, "branch_id")?;
            let branch = uuid::Uuid::parse_str(&branch)
                .map_err(|_| invalid("branch_id", "not a valid uuid"))?;
            w.name = name.map(Some);
            w.pin = Some(Some(pin));
            w.branch_id = Some(Some(branch));
        }
        LoginMode::Email => {
            let email = nonblank(&req.email, "email")?;
            let password = nonblank(&req.password, "password")?;
            w.email = Some(Some(email));
            w.password = Some(Some(password));
            if let Some(org) = req.org_id.as_deref().filter(|s| !s.is_empty()) {
                let org = uuid::Uuid::parse_str(org)
                    .map_err(|_| invalid("org_id", "not a valid uuid"))?;
                w.org_id = Some(Some(org));
            }
        }
    }
    Ok(w)
}

/// Build the cached snapshot from a successful login. `permissions_loaded` is
/// flipped to `true` by the caller once `/auth/permissions` is mirrored.
pub(crate) fn snapshot_from_login(
    resp: &models::LoginResponse,
    branch_id: Option<String>,
) -> SessionSnapshot {
    SessionSnapshot {
        user_id: resp.user.id.to_string(),
        display_name: resp.user.name.clone(),
        role: resp.user.role.to_string(),
        org_id: resp.user.org_id.flatten().map(|u| u.to_string()),
        branch_id,
        currency_code: resp.currency_code.clone(),
        // The whole policy, not the flat `tax_rate` beside it: that field is
        // kept only so a build older than this one still parses the payload.
        tax_rate: resp.tax_policy.tax_rate,
        tax_inclusive: resp.tax_policy.tax_inclusive,
        service_charge_rate: resp.tax_policy.service_charge_rate,
        service_charge_taxable: resp.tax_policy.service_charge_taxable,
        // `#[serde(default)]` on the wire, so a server older than this one
        // simply means "no rule".
        require_table_for_orders: resp.require_table_for_orders.unwrap_or(false),
        online: true,
        permissions_loaded: false,
    }
}

pub(crate) fn permissions_from(resp: &models::AuthPermissionsResponse) -> Vec<PermissionEntry> {
    resp.permissions
        .iter()
        .map(|p| PermissionEntry {
            resource: p.resource.clone(),
            action: p.action.clone(),
            granted: p.granted,
        })
        .collect()
}

/// Cache the org's offline-auth bundle + a minimal org config so a later offline
/// unlock can verify a PIN and build a complete snapshot. Best-effort.
pub(crate) fn cache_bundle(
    store: &Store,
    bundle: &models::OfflineAuthBundle,
    snapshot: &SessionSnapshot,
) {
    if let Ok(json) = serde_json::to_string(bundle) {
        let _ = store.kv_put(BUNDLE_KEY, &json);
    }
    cache_org_config(store, snapshot);
}

/// Cache the org config an offline unlock rebuilds a session from.
///
/// Written at login AND whenever the policy changes under a running session,
/// so a device that unlocks offline tomorrow starts from the rate the shop
/// actually charges rather than the one in force when it last signed in.
pub(crate) fn cache_org_config(store: &Store, snapshot: &SessionSnapshot) {
    let cfg = serde_json::json!({
        "org_id": snapshot.org_id,
        "currency_code": snapshot.currency_code,
        "tax_rate": snapshot.tax_rate,
        "tax_inclusive": snapshot.tax_inclusive,
        "service_charge_rate": snapshot.service_charge_rate,
        "service_charge_taxable": snapshot.service_charge_taxable,
        "require_table_for_orders": snapshot.require_table_for_orders,
    });
    let _ = store.kv_put(ORG_CONFIG_KEY, &cfg.to_string());
}

/// Verify a typed PIN against the cached org bundle and build an offline
/// `SessionState`. Mirrors the backend's `auth::offline` (argon2id PHC).
pub(crate) fn unlock_from_bundle(
    store: &Store,
    name: &str,
    pin: &str,
    branch_id: &str,
) -> CoreResult<SessionState> {
    let raw = store
        .kv_get(BUNDLE_KEY)?
        .ok_or_else(|| CoreError::Unauthenticated {
            detail: "no offline bundle cached — sign in online once first".into(),
        })?;
    let bundle: models::OfflineAuthBundle = serde_json::from_str(&raw)?;

    // PIN-only (§8.5): no name, so try the PIN against every verifier in the
    // bundle. A few hundred ms per person on a tablet, and only while offline.
    let name = name.trim();
    if name.is_empty() {
        let mut hits = bundle.tellers.iter().filter(|t| {
            t.is_active
                && t.offline_pin_hash
                    .clone()
                    .flatten()
                    .is_some_and(|h| verify_offline_pin(pin, &h))
        });
        let teller = match (hits.next(), hits.next()) {
            (Some(t), None) => t,
            (Some(_), Some(_)) => {
                return Err(CoreError::Unauthenticated {
                    detail: PIN_NOT_UNIQUE_OFFLINE.into(),
                })
            }
            _ => {
                return Err(CoreError::Unauthenticated {
                    detail: "PIN not recognized.".into(),
                })
            }
        };
        return session_from_bundle_teller(store, &bundle, teller, branch_id);
    }

    // Resolve by name FIRST so we can give a precise reason instead of a blanket
    // "PIN not recognized" — a user who simply hasn't synced an offline verifier
    // yet would otherwise be told their (correct) PIN is wrong. The bundle carries
    // every PIN-login role (teller, waiter, kitchen), so this path serves all three.
    let by_name: Vec<&models::OfflineTellerCredential> = bundle
        .tellers
        .iter()
        .filter(|t| t.is_active && t.name.eq_ignore_ascii_case(name))
        .collect();
    if by_name.is_empty() {
        return Err(CoreError::Unauthenticated {
            detail: format!(
                "No active user named “{name}” on this device. Check the name, or sign in online once to refresh."
            ),
        });
    }
    // Same-named user exists but has no offline verifier → they've never logged
    // in online (the backend derives the verifier only on an online PIN login).
    if !by_name
        .iter()
        .any(|t| t.offline_pin_hash.clone().flatten().is_some())
    {
        return Err(CoreError::Unauthenticated {
            detail: format!(
                "“{name}” hasn’t signed in online on this device yet — connect once to enable offline unlock."
            ),
        });
    }
    let teller = by_name
        .into_iter()
        .find(|t| {
            t.offline_pin_hash
                .clone()
                .flatten()
                .map(|h| verify_offline_pin(pin, &h))
                .unwrap_or(false)
        })
        .ok_or_else(|| CoreError::Unauthenticated {
            detail: "PIN not recognized.".into(),
        })?;
    session_from_bundle_teller(store, &bundle, teller, branch_id)
}

/// Who in the offline bundle holds `pin` — a manager approving on this device
/// (phase 5). Exactly one active person with a verifier, or a refusal.
pub(crate) fn bundle_person_by_pin(store: &Store, pin: &str) -> CoreResult<(String, String)> {
    let raw = store
        .kv_get(BUNDLE_KEY)?
        .ok_or_else(|| CoreError::Unauthenticated {
            detail: "no offline bundle cached — sign in online once first".into(),
        })?;
    let bundle: models::OfflineAuthBundle = serde_json::from_str(&raw)?;
    let mut hits = bundle.tellers.iter().filter(|t| {
        t.is_active
            && t.offline_pin_hash
                .clone()
                .flatten()
                .is_some_and(|h| verify_offline_pin(pin, &h))
    });
    match (hits.next(), hits.next()) {
        (Some(t), None) => Ok((t.user_id.to_string(), t.name.clone())),
        (Some(_), Some(_)) => Err(CoreError::Unauthenticated {
            detail: PIN_NOT_UNIQUE_OFFLINE.into(),
        }),
        _ => Err(CoreError::Unauthenticated {
            detail: "PIN not recognized.".into(),
        }),
    }
}

/// The name of a person in the offline bundle, for showing who did something
/// while the till has no connection. `None` when this device never cached them.
pub(crate) fn bundle_person_name(store: &Store, user_id: &str) -> Option<String> {
    let raw = store.kv_get(BUNDLE_KEY).ok()??;
    let bundle: models::OfflineAuthBundle = serde_json::from_str(&raw).ok()?;
    bundle
        .tellers
        .iter()
        .find(|t| t.user_id.to_string() == user_id)
        .map(|t| t.name.clone())
}

/// The offline refusal when a PIN typed without a name opens more than one
/// person's verifier (pre-rollout duplicate PINs).
pub(crate) const PIN_NOT_UNIQUE_OFFLINE: &str = "this PIN belongs to more than one person";

/// The offline session for a teller the bundle vouched for.
fn session_from_bundle_teller(
    store: &Store,
    bundle: &models::OfflineAuthBundle,
    teller: &models::OfflineTellerCredential,
    branch_id: &str,
) -> CoreResult<SessionState> {
    // The whole policy, not just the rate: an offline unlock has to price a
    // cart exactly as the server would, and a service charge or tax-inclusive
    // pricing it never heard about is a bill the server will refuse.
    let cfg: serde_json::Value = match store.kv_get(ORG_CONFIG_KEY)? {
        Some(raw) => serde_json::from_str(&raw).unwrap_or_default(),
        None => serde_json::Value::Null,
    };
    let currency_code = cfg
        .get("currency_code")
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string();
    let tax_rate = cfg.get("tax_rate").and_then(|x| x.as_f64()).unwrap_or(0.0);
    let tax_inclusive = cfg
        .get("tax_inclusive")
        .and_then(|x| x.as_bool())
        .unwrap_or(false);
    let service_charge_rate = cfg
        .get("service_charge_rate")
        .and_then(|x| x.as_f64())
        .unwrap_or(0.0);
    let service_charge_taxable = cfg
        .get("service_charge_taxable")
        .and_then(|x| x.as_bool())
        .unwrap_or(true);
    let require_table_for_orders = cfg
        .get("require_table_for_orders")
        .and_then(|x| x.as_bool())
        .unwrap_or(false);

    let snapshot = SessionSnapshot {
        user_id: teller.user_id.to_string(),
        display_name: teller.name.clone(),
        role: teller.role.clone(),
        org_id: Some(bundle.org_id.to_string()),
        branch_id: Some(branch_id.to_string()),
        currency_code,
        tax_rate,
        tax_inclusive,
        service_charge_rate,
        service_charge_taxable,
        require_table_for_orders,
        online: false,
        permissions_loaded: false,
    };
    Ok(SessionState {
        snapshot,
        permissions: Vec::new(),
        token: None,
        authz: None,
    })
}

/// argon2id PHC verification — madar-shared's `madar_authz::pin`, the verify
/// the server's `auth::offline` runs too (params ride in the PHC string).
pub(crate) use madar_authz::pin::verify_offline_pin;

fn nonblank(field: &Option<String>, name: &'static str) -> CoreResult<String> {
    match field.as_deref().map(str::trim) {
        Some(s) if !s.is_empty() => Ok(s.to_string()),
        _ => Err(invalid(name, "is required")),
    }
}

fn invalid(field: &str, message: &str) -> CoreError {
    CoreError::Validation {
        field: field.to_string(),
        detail: message.to_string(),
    }
}

#[cfg(test)]
mod tests {
    /// The table rule is a POLICY the till acts on, not just a server check —
    /// so it has to survive the snapshot, the offline cache, and a server too
    /// old to send it.
    #[test]
    fn the_table_rule_survives_a_round_trip_through_the_offline_cache() {
        let store = Store::open(":memory:").unwrap();
        let mut snap = SessionSnapshot {
            user_id: "u".into(),
            display_name: "Mona".into(),
            role: "teller".into(),
            org_id: Some("o".into()),
            branch_id: Some("b".into()),
            currency_code: "EGP".into(),
            tax_rate: 0.14,
            tax_inclusive: false,
            service_charge_rate: 0.0,
            service_charge_taxable: true,
            require_table_for_orders: true,
            online: true,
            permissions_loaded: true,
        };
        cache_org_config(&store, &snap);

        let raw = store.kv_get(ORG_CONFIG_KEY).unwrap().expect("cached");
        let v: serde_json::Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(
            v.get("require_table_for_orders").and_then(|x| x.as_bool()),
            Some(true),
            "an offline unlock tomorrow must open on the floor too"
        );

        // And off is off, not merely absent.
        snap.require_table_for_orders = false;
        cache_org_config(&store, &snap);
        let raw = store.kv_get(ORG_CONFIG_KEY).unwrap().expect("cached");
        let v: serde_json::Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(
            v.get("require_table_for_orders").and_then(|x| x.as_bool()),
            Some(false)
        );
    }

    use super::*;

    fn pin_req() -> LoginRequest {
        LoginRequest {
            mode: LoginMode::Pin,
            name: Some("Sara".into()),
            pin: Some("1234".into()),
            branch_id: Some("00000000-0000-0000-0000-000000000001".into()),
            email: None,
            password: None,
            org_id: None,
        }
    }

    #[test]
    fn pin_request_validates_and_builds_wire() {
        let w = wire_login_request(&pin_req()).unwrap();
        assert_eq!(w.name, Some(Some("Sara".into())));
        assert_eq!(w.pin, Some(Some("1234".into())));
        assert!(w.branch_id.flatten().is_some());
        assert!(w.email.is_none());
    }

    #[test]
    fn pin_request_missing_branch_is_validation_error() {
        let mut r = pin_req();
        r.branch_id = None;
        assert!(matches!(
            wire_login_request(&r),
            Err(CoreError::Validation { .. })
        ));
    }

    #[test]
    fn pin_request_bad_branch_uuid_is_validation_error() {
        let mut r = pin_req();
        r.branch_id = Some("not-a-uuid".into());
        assert!(matches!(
            wire_login_request(&r),
            Err(CoreError::Validation { .. })
        ));
    }

    #[test]
    fn email_request_requires_email_and_password() {
        let r = LoginRequest {
            mode: LoginMode::Email,
            name: None,
            pin: None,
            branch_id: None,
            email: Some("a@b.com".into()),
            password: None,
            org_id: None,
        };
        assert!(matches!(
            wire_login_request(&r),
            Err(CoreError::Validation { .. })
        ));
    }

    #[test]
    fn offline_unlock_roundtrips_against_a_cached_bundle() {
        // Hash a PIN exactly as the backend would, stash a bundle, then unlock.
        let phc = backend_hash("4321");
        let bundle = serde_json::json!({
            "org_id": "00000000-0000-0000-0000-0000000000aa",
            "generated_at": "2026-06-19T10:00:00Z",
            "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
            "tellers": [{
                "user_id": "00000000-0000-0000-0000-0000000000bb",
                "name": "Sara", "role": "teller", "is_active": true,
                "offline_pin_hash": phc,
            }]
        });
        let store = Store::open("").unwrap();
        store.kv_put(BUNDLE_KEY, &bundle.to_string()).unwrap();
        store.kv_put(ORG_CONFIG_KEY, r#"{"org_id":"00000000-0000-0000-0000-0000000000aa","currency_code":"EGP","tax_rate":0.14}"#).unwrap();

        let s = unlock_from_bundle(
            &store,
            "sara",
            "4321",
            "00000000-0000-0000-0000-000000000001",
        )
        .unwrap();
        assert_eq!(s.snapshot.display_name, "Sara");
        assert_eq!(s.snapshot.currency_code, "EGP");
        assert_eq!(s.snapshot.tax_rate, 0.14);
        assert!(!s.snapshot.online);
        assert!(s.token.is_none());
        // optimistic permissions while offline
        assert!(s.has_permission("orders", "create"));

        // wrong PIN / unknown teller → unauthenticated
        assert!(unlock_from_bundle(
            &store,
            "Sara",
            "0000",
            "00000000-0000-0000-0000-000000000001"
        )
        .is_err());
        assert!(unlock_from_bundle(
            &store,
            "Nobody",
            "4321",
            "00000000-0000-0000-0000-000000000001"
        )
        .is_err());
    }

    #[test]
    fn offline_unlock_by_pin_alone_finds_the_one_person_or_refuses() {
        let bundle = serde_json::json!({
            "org_id": "00000000-0000-0000-0000-0000000000aa",
            "generated_at": "2026-06-19T10:00:00Z",
            "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
            "tellers": [
                {"user_id": "00000000-0000-0000-0000-0000000000bb", "name": "Sara",
                 "role": "teller", "is_active": true, "offline_pin_hash": backend_hash("246810")},
                {"user_id": "00000000-0000-0000-0000-0000000000cc", "name": "Omar",
                 "role": "teller", "is_active": true, "offline_pin_hash": backend_hash("135790")},
                {"user_id": "00000000-0000-0000-0000-0000000000dd", "name": "Dup",
                 "role": "teller", "is_active": true, "offline_pin_hash": backend_hash("135790")}
            ]
        });
        let store = Store::open("").unwrap();
        store.kv_put(BUNDLE_KEY, &bundle.to_string()).unwrap();
        let branch = "00000000-0000-0000-0000-000000000001";

        let s = unlock_from_bundle(&store, "", "246810", branch).unwrap();
        assert_eq!(s.snapshot.display_name, "Sara");
        match unlock_from_bundle(&store, "", "135790", branch) {
            Err(CoreError::Unauthenticated { detail }) => assert_eq!(detail, PIN_NOT_UNIQUE_OFFLINE),
            Err(other) => panic!("expected an ambiguous refusal, got {other:?}"),
            Ok(_) => panic!("a shared PIN must not pick someone"),
        }
        assert!(matches!(
            unlock_from_bundle(&store, "", "000000", branch),
            Err(CoreError::Unauthenticated { .. })
        ));
    }

    #[test]
    fn unlock_without_a_bundle_is_unauthenticated() {
        let store = Store::open("").unwrap();
        assert!(matches!(
            unlock_from_bundle(
                &store,
                "Sara",
                "1234",
                "00000000-0000-0000-0000-000000000001"
            ),
            Err(CoreError::Unauthenticated { .. })
        ));
    }

    /// Produce a real argon2id PHC string (default params, same as the backend's
    /// `Argon2::default()`), so the test exercises the live verifier rather than a
    /// brittle fixed vector. A deterministic salt avoids needing an RNG feature.
    fn backend_hash(pin: &str) -> String {
        use argon2::password_hash::SaltString;
        use argon2::{Argon2, PasswordHasher};
        let salt = SaltString::encode_b64(b"madar-test-salt").unwrap();
        Argon2::default()
            .hash_password(pin.as_bytes(), &salt)
            .unwrap()
            .to_string()
    }

    // ── wire_login_request: PIN mode ─────────────────────────────────────

    #[test]
    fn pin_request_without_a_name_is_pin_only() {
        // PIN-only sign-in (§8.5): no name on the wire at all.
        let mut r = pin_req();
        r.name = None;
        let w = wire_login_request(&r).unwrap();
        assert!(w.name.is_none());
        let json = serde_json::to_value(&w).unwrap();
        assert!(json.get("name").is_none(), "{json}");
    }

    #[test]
    fn pin_request_missing_pin_is_validation_error() {
        let mut r = pin_req();
        r.pin = None;
        assert!(
            matches!(wire_login_request(&r), Err(CoreError::Validation { field, .. }) if field == "pin")
        );
    }

    #[test]
    fn pin_request_blank_name_is_pin_only() {
        let mut r = pin_req();
        r.name = Some("   ".into());
        assert!(wire_login_request(&r).unwrap().name.is_none());
    }

    #[test]
    fn pin_request_trims_name_and_pin() {
        let mut r = pin_req();
        r.name = Some("  Sara  ".into());
        r.pin = Some("  1234 ".into());
        let w = wire_login_request(&r).unwrap();
        assert_eq!(w.name, Some(Some("Sara".into())));
        assert_eq!(w.pin, Some(Some("1234".into())));
    }

    #[test]
    fn pin_request_ignores_email_fields_and_leaves_them_unset() {
        let mut r = pin_req();
        r.email = Some("ignored@example.com".into());
        r.password = Some("ignored".into());
        r.org_id = Some("00000000-0000-0000-0000-0000000000ff".into());
        let w = wire_login_request(&r).unwrap();
        // PIN branch never copies email/password/org_id onto the wire.
        assert!(w.email.is_none());
        assert!(w.password.is_none());
        assert!(w.org_id.is_none());
    }

    #[test]
    fn pin_request_blank_branch_is_validation_error() {
        let mut r = pin_req();
        r.branch_id = Some("   ".into());
        assert!(
            matches!(wire_login_request(&r), Err(CoreError::Validation { field, .. }) if field == "branch_id")
        );
    }

    // ── wire_login_request: Email mode ───────────────────────────────────

    fn email_req() -> LoginRequest {
        LoginRequest {
            mode: LoginMode::Email,
            name: None,
            pin: None,
            branch_id: None,
            email: Some("manager@example.com".into()),
            password: Some("hunter2".into()),
            org_id: None,
        }
    }

    #[test]
    fn email_request_minimal_builds_wire() {
        let w = wire_login_request(&email_req()).unwrap();
        assert_eq!(w.email, Some(Some("manager@example.com".into())));
        assert_eq!(w.password, Some(Some("hunter2".into())));
        assert!(w.org_id.is_none());
        // PIN-only fields stay unset in email mode.
        assert!(w.name.is_none());
        assert!(w.pin.is_none());
        assert!(w.branch_id.is_none());
    }

    #[test]
    fn email_request_missing_password_is_validation_error() {
        let mut r = email_req();
        r.password = None;
        assert!(
            matches!(wire_login_request(&r), Err(CoreError::Validation { field, .. }) if field == "password")
        );
    }

    #[test]
    fn email_request_missing_email_is_validation_error() {
        let mut r = email_req();
        r.email = None;
        assert!(
            matches!(wire_login_request(&r), Err(CoreError::Validation { field, .. }) if field == "email")
        );
    }

    #[test]
    fn email_request_with_valid_org_id_is_parsed_onto_wire() {
        let mut r = email_req();
        r.org_id = Some("00000000-0000-0000-0000-0000000000aa".into());
        let w = wire_login_request(&r).unwrap();
        assert!(w.org_id.flatten().is_some());
    }

    #[test]
    fn email_request_empty_org_id_is_treated_as_absent() {
        let mut r = email_req();
        r.org_id = Some(String::new());
        // Empty string is filtered out, so it must NOT be a validation error and
        // org_id stays unset on the wire.
        let w = wire_login_request(&r).unwrap();
        assert!(w.org_id.is_none());
    }

    #[test]
    fn email_request_bad_org_id_uuid_is_validation_error() {
        let mut r = email_req();
        r.org_id = Some("not-a-uuid".into());
        assert!(
            matches!(wire_login_request(&r), Err(CoreError::Validation { field, .. }) if field == "org_id")
        );
    }

    #[test]
    fn email_request_trims_email_and_password() {
        let mut r = email_req();
        r.email = Some("  manager@example.com  ".into());
        r.password = Some("  hunter2  ".into());
        let w = wire_login_request(&r).unwrap();
        assert_eq!(w.email, Some(Some("manager@example.com".into())));
        assert_eq!(w.password, Some(Some("hunter2".into())));
    }

    // ── snapshot_from_login ──────────────────────────────────────────────

    fn login_resp(org: Option<&str>) -> models::LoginResponse {
        let mut user = models::UserPublic::new(
            uuid::Uuid::parse_str("00000000-0000-0000-0000-0000000000cc").unwrap(),
            true,
            "Mona".into(),
            models::UserRole::Teller,
        );
        user.org_id = org.map(|o| Some(uuid::Uuid::parse_str(o).unwrap()));
        models::LoginResponse {
            currency_code: "EGP".into(),
            open_till: None,
            require_table_for_orders: Some(false),
            tax_rate: 0.14,
            tax_policy: Box::new(models::TaxPolicyPublic {
                tax_rate: 0.14,
                tax_inclusive: false,
                service_charge_rate: 0.0,
                service_charge_taxable: true,
            }),
            token: "jwt.abc.def".into(),
            user: Box::new(user),
        }
    }

    #[test]
    fn snapshot_from_login_maps_all_fields() {
        let resp = login_resp(Some("00000000-0000-0000-0000-0000000000aa"));
        let snap = snapshot_from_login(&resp, Some("branch-7".into()));
        assert_eq!(snap.user_id, "00000000-0000-0000-0000-0000000000cc");
        assert_eq!(snap.display_name, "Mona");
        assert_eq!(snap.role, "teller");
        assert_eq!(
            snap.org_id.as_deref(),
            Some("00000000-0000-0000-0000-0000000000aa")
        );
        assert_eq!(snap.branch_id.as_deref(), Some("branch-7"));
        assert_eq!(snap.currency_code, "EGP");
        assert_eq!(snap.tax_rate, 0.14);
        assert!(snap.online);
        // The caller flips this later once /auth/permissions is mirrored.
        assert!(!snap.permissions_loaded);
    }

    #[test]
    fn snapshot_from_login_handles_no_org() {
        // org_id absent entirely (None) → snapshot org_id is None.
        let resp = login_resp(None);
        let snap = snapshot_from_login(&resp, None);
        assert!(snap.org_id.is_none());
        assert!(snap.branch_id.is_none());
    }

    #[test]
    fn snapshot_from_login_handles_explicit_null_org() {
        // org_id present but inner None (Some(None)) → flatten yields None.
        let mut resp = login_resp(None);
        resp.user.org_id = Some(None);
        let snap = snapshot_from_login(&resp, None);
        assert!(snap.org_id.is_none());
    }

    // ── permissions_from ─────────────────────────────────────────────────

    #[test]
    fn permissions_from_maps_each_item() {
        let resp = models::AuthPermissionsResponse {
            permissions: vec![
                models::UserPermissionItem::new("create".into(), true, "orders".into()),
                models::UserPermissionItem::new("void".into(), false, "orders".into()),
            ],
        };
        let perms = permissions_from(&resp);
        assert_eq!(perms.len(), 2);
        assert_eq!(perms[0].resource, "orders");
        assert_eq!(perms[0].action, "create");
        assert!(perms[0].granted);
        assert_eq!(perms[1].action, "void");
        assert!(!perms[1].granted);
    }

    #[test]
    fn permissions_from_empty_is_empty() {
        let resp = models::AuthPermissionsResponse {
            permissions: vec![],
        };
        assert!(permissions_from(&resp).is_empty());
    }

    // ── SessionState::has_permission ─────────────────────────────────────

    fn state_with(perms: Vec<PermissionEntry>, loaded: bool, online: bool) -> SessionState {
        SessionState {
            snapshot: SessionSnapshot {
                user_id: "u".into(),
                display_name: "n".into(),
                role: "teller".into(),
                org_id: None,
                branch_id: None,
                currency_code: "EGP".into(),
                tax_rate: 0.0,
                tax_inclusive: false,
                service_charge_rate: 0.0,
                service_charge_taxable: true,
                require_table_for_orders: false,
                online,
                permissions_loaded: loaded,
            },
            permissions: perms,
            token: if online { Some("t".into()) } else { None },
            authz: None,
        }
    }

    #[test]
    fn unloaded_grants_allow_selling_and_deny_money_exceptions() {
        let s = state_with(vec![], false, false);
        assert!(s.has_permission("orders", "create"));
        assert!(s.has_permission("payments", "create"));
        assert!(s.has_permission("open_tickets", "update"));
        for (r, a) in [
            ("orders", "delete"),
            ("refunds", "create"),
            ("tills", "update"),
            ("open_tickets", "delete"),
            ("discounts", "read"),
            ("orders", "waive_service"),
            ("anything", "at_all"),
        ] {
            assert!(!s.has_permission(r, a), "{r}:{a} assumed while unloaded");
        }
    }

    #[test]
    fn a_granted_permission_is_never_assumed() {
        let unloaded = state_with(vec![], false, false);
        assert!(!unloaded.has_granted_permission("orders", "waive_service"));
        let granted = state_with(
            vec![PermissionEntry { resource: "orders".into(), action: "waive_service".into(), granted: true }],
            true,
            true,
        );
        assert!(granted.has_granted_permission("orders", "waive_service"));
        let revoked = state_with(
            vec![PermissionEntry { resource: "orders".into(), action: "waive_service".into(), granted: false }],
            true,
            true,
        );
        assert!(!revoked.has_granted_permission("orders", "waive_service"));
    }

    #[test]
    fn has_permission_grants_matching_loaded_entry() {
        let s = state_with(
            vec![PermissionEntry {
                resource: "orders".into(),
                action: "create".into(),
                granted: true,
            }],
            true,
            true,
        );
        assert!(s.has_permission("orders", "create"));
    }

    #[test]
    fn has_permission_denies_unlisted_when_loaded() {
        let s = state_with(
            vec![PermissionEntry {
                resource: "orders".into(),
                action: "create".into(),
                granted: true,
            }],
            true,
            true,
        );
        assert!(!s.has_permission("orders", "void"));
        assert!(!s.has_permission("shifts", "create"));
    }

    #[test]
    fn has_permission_denies_explicitly_revoked_entry() {
        let s = state_with(
            vec![PermissionEntry {
                resource: "orders".into(),
                action: "void".into(),
                granted: false,
            }],
            true,
            true,
        );
        // Present but granted == false → denied.
        assert!(!s.has_permission("orders", "void"));
    }

    #[test]
    fn has_permission_requires_both_resource_and_action_to_match() {
        let s = state_with(
            vec![PermissionEntry {
                resource: "orders".into(),
                action: "create".into(),
                granted: true,
            }],
            true,
            true,
        );
        assert!(!s.has_permission("orders", "delete")); // right resource, wrong action
        assert!(!s.has_permission("menu", "create")); // wrong resource, right action
    }

    // ── SessionState blob round-trip ─────────────────────────────────────

    #[test]
    fn session_state_blob_roundtrips() {
        let s = state_with(
            vec![PermissionEntry {
                resource: "orders".into(),
                action: "create".into(),
                granted: true,
            }],
            true,
            true,
        );
        let blob = s.to_blob();
        assert!(!blob.is_empty());
        let back = SessionState::from_blob(&blob).expect("decode");
        assert_eq!(back.snapshot.user_id, s.snapshot.user_id);
        assert_eq!(back.token, s.token);
        assert_eq!(back.permissions.len(), 1);
        assert!(back.has_permission("orders", "create"));
    }

    #[test]
    fn from_blob_rejects_garbage() {
        assert!(SessionState::from_blob(b"not json at all").is_none());
        assert!(SessionState::from_blob(b"").is_none());
    }

    #[test]
    fn from_blob_roundtrips_offline_session_with_no_token() {
        let s = state_with(vec![], false, false);
        let blob = s.to_blob();
        let back = SessionState::from_blob(&blob).unwrap();
        assert!(back.token.is_none());
        assert!(!back.snapshot.online);
        assert!(!back.snapshot.permissions_loaded);
    }

    // ── cache_bundle ─────────────────────────────────────────────────────

    #[test]
    fn cache_bundle_persists_bundle_and_org_config() {
        let store = Store::open("").unwrap();
        let bundle: models::OfflineAuthBundle = serde_json::from_value(serde_json::json!({
            "org_id": "00000000-0000-0000-0000-0000000000aa",
            "generated_at": "2026-06-19T10:00:00Z",
            "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
            "tellers": []
        }))
        .unwrap();
        let snapshot = SessionSnapshot {
            user_id: "u".into(),
            display_name: "n".into(),
            role: "teller".into(),
            org_id: Some("00000000-0000-0000-0000-0000000000aa".into()),
            branch_id: Some("b".into()),
            currency_code: "EGP".into(),
            tax_rate: 0.14,
            tax_inclusive: false,
            service_charge_rate: 0.0,
            service_charge_taxable: true,
            require_table_for_orders: false,
            online: true,
            permissions_loaded: true,
        };
        cache_bundle(&store, &bundle, &snapshot);

        // Both keys are now populated and parseable.
        let stored_bundle = store.kv_get(BUNDLE_KEY).unwrap().expect("bundle stored");
        let _: models::OfflineAuthBundle = serde_json::from_str(&stored_bundle).unwrap();

        let cfg_raw = store.kv_get(ORG_CONFIG_KEY).unwrap().expect("cfg stored");
        let cfg: serde_json::Value = serde_json::from_str(&cfg_raw).unwrap();
        assert_eq!(cfg["org_id"], "00000000-0000-0000-0000-0000000000aa");
        assert_eq!(cfg["currency_code"], "EGP");
        assert_eq!(cfg["tax_rate"], 0.14);
    }

    #[test]
    fn cache_bundle_then_unlock_full_flow() {
        // End-to-end: cache from a snapshot, then unlock against the cached data.
        let store = Store::open("").unwrap();
        let phc = backend_hash("9999");
        let bundle: models::OfflineAuthBundle = serde_json::from_value(serde_json::json!({
            "org_id": "00000000-0000-0000-0000-0000000000aa",
            "generated_at": "2026-06-19T10:00:00Z",
            "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
            "tellers": [{
                "user_id": "00000000-0000-0000-0000-0000000000bb",
                "name": "Mona", "role": "teller", "is_active": true,
                "offline_pin_hash": phc,
            }]
        }))
        .unwrap();
        let snapshot = SessionSnapshot {
            user_id: "00000000-0000-0000-0000-0000000000bb".into(),
            display_name: "Mona".into(),
            role: "teller".into(),
            org_id: Some("00000000-0000-0000-0000-0000000000aa".into()),
            branch_id: Some("b".into()),
            currency_code: "USD".into(),
            tax_rate: 0.07,
            tax_inclusive: false,
            service_charge_rate: 0.0,
            service_charge_taxable: true,
            require_table_for_orders: false,
            online: true,
            permissions_loaded: true,
        };
        cache_bundle(&store, &bundle, &snapshot);

        let s = unlock_from_bundle(
            &store,
            "Mona",
            "9999",
            "00000000-0000-0000-0000-000000000002",
        )
        .unwrap();
        assert_eq!(s.snapshot.currency_code, "USD");
        assert_eq!(s.snapshot.tax_rate, 0.07);
        assert_eq!(
            s.snapshot.org_id.as_deref(),
            Some("00000000-0000-0000-0000-0000000000aa")
        );
        assert_eq!(
            s.snapshot.branch_id.as_deref(),
            Some("00000000-0000-0000-0000-000000000002")
        );
    }

    // ── unlock_from_bundle: edge cases ───────────────────────────────────

    /// Stash a one-teller bundle hashing `pin`, with the teller flagged
    /// `is_active`. Returns the open store.
    fn store_with_teller(name: &str, pin: &str, is_active: bool) -> Store {
        let phc = backend_hash(pin);
        let bundle = serde_json::json!({
            "org_id": "00000000-0000-0000-0000-0000000000aa",
            "generated_at": "2026-06-19T10:00:00Z",
            "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
            "tellers": [{
                "user_id": "00000000-0000-0000-0000-0000000000bb",
                "name": name, "role": "teller", "is_active": is_active,
                "offline_pin_hash": phc,
            }]
        });
        let store = Store::open("").unwrap();
        store.kv_put(BUNDLE_KEY, &bundle.to_string()).unwrap();
        store
    }

    #[test]
    fn unlock_right_pin_succeeds_case_insensitive_name() {
        let store = store_with_teller("Sara", "1234", true);
        // name match is ASCII-case-insensitive.
        let s = unlock_from_bundle(
            &store,
            "SARA",
            "1234",
            "00000000-0000-0000-0000-000000000001",
        )
        .unwrap();
        assert_eq!(s.snapshot.display_name, "Sara"); // canonical name from bundle
        assert_eq!(s.snapshot.role, "teller");
        assert!(!s.snapshot.online);
        assert!(!s.snapshot.permissions_loaded);
        assert!(s.token.is_none());
        assert!(s.permissions.is_empty());
    }

    #[test]
    fn unlock_wrong_pin_is_unauthenticated() {
        let store = store_with_teller("Sara", "1234", true);
        assert!(matches!(
            unlock_from_bundle(
                &store,
                "Sara",
                "0000",
                "00000000-0000-0000-0000-000000000001"
            ),
            Err(CoreError::Unauthenticated { .. })
        ));
    }

    #[test]
    fn unlock_unknown_name_is_unauthenticated() {
        let store = store_with_teller("Sara", "1234", true);
        assert!(matches!(
            unlock_from_bundle(
                &store,
                "Ghost",
                "1234",
                "00000000-0000-0000-0000-000000000001"
            ),
            Err(CoreError::Unauthenticated { .. })
        ));
    }

    #[test]
    fn unlock_inactive_teller_is_rejected_even_with_right_pin() {
        let store = store_with_teller("Sara", "1234", false);
        assert!(matches!(
            unlock_from_bundle(
                &store,
                "Sara",
                "1234",
                "00000000-0000-0000-0000-000000000001"
            ),
            Err(CoreError::Unauthenticated { .. })
        ));
    }

    #[test]
    fn unlock_teller_with_null_pin_hash_cannot_unlock() {
        // offline_pin_hash null → teller has never logged in online; no offline auth.
        let bundle = serde_json::json!({
            "org_id": "00000000-0000-0000-0000-0000000000aa",
            "generated_at": "2026-06-19T10:00:00Z",
            "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
            "tellers": [{
                "user_id": "00000000-0000-0000-0000-0000000000bb",
                "name": "Sara", "role": "teller", "is_active": true,
                "offline_pin_hash": null,
            }]
        });
        let store = Store::open("").unwrap();
        store.kv_put(BUNDLE_KEY, &bundle.to_string()).unwrap();
        assert!(matches!(
            unlock_from_bundle(
                &store,
                "Sara",
                "1234",
                "00000000-0000-0000-0000-000000000001"
            ),
            Err(CoreError::Unauthenticated { .. })
        ));
    }

    #[test]
    fn unlock_missing_org_config_yields_empty_currency_and_zero_tax() {
        // No ORG_CONFIG_KEY stored → currency "" and tax 0.0, but unlock still works.
        let store = store_with_teller("Sara", "1234", true);
        let s = unlock_from_bundle(
            &store,
            "Sara",
            "1234",
            "00000000-0000-0000-0000-000000000001",
        )
        .unwrap();
        assert_eq!(s.snapshot.currency_code, "");
        assert_eq!(s.snapshot.tax_rate, 0.0);
    }

    #[test]
    fn unlock_passes_through_branch_id_argument() {
        let store = store_with_teller("Sara", "1234", true);
        let s = unlock_from_bundle(&store, "Sara", "1234", "branch-xyz").unwrap();
        // branch_id comes from the caller (device config), not the bundle.
        assert_eq!(s.snapshot.branch_id.as_deref(), Some("branch-xyz"));
    }

    #[test]
    fn unlock_malformed_bundle_json_is_internal_error() {
        let store = Store::open("").unwrap();
        store
            .kv_put(BUNDLE_KEY, "{ this is not valid json")
            .unwrap();
        // serde error → From → CoreError::Internal.
        assert!(matches!(
            unlock_from_bundle(
                &store,
                "Sara",
                "1234",
                "00000000-0000-0000-0000-000000000001"
            ),
            Err(CoreError::Internal { .. })
        ));
    }

    #[test]
    fn unlock_picks_correct_teller_among_many() {
        let phc_a = backend_hash("1111");
        let phc_b = backend_hash("2222");
        let bundle = serde_json::json!({
            "org_id": "00000000-0000-0000-0000-0000000000aa",
            "generated_at": "2026-06-19T10:00:00Z",
            "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
            "tellers": [
                {"user_id": "00000000-0000-0000-0000-0000000000b1",
                 "name": "Alice", "role": "teller", "is_active": true, "offline_pin_hash": phc_a},
                {"user_id": "00000000-0000-0000-0000-0000000000b2",
                 "name": "Bob", "role": "manager", "is_active": true, "offline_pin_hash": phc_b},
            ]
        });
        let store = Store::open("").unwrap();
        store.kv_put(BUNDLE_KEY, &bundle.to_string()).unwrap();

        let bob = unlock_from_bundle(
            &store,
            "Bob",
            "2222",
            "00000000-0000-0000-0000-000000000001",
        )
        .unwrap();
        assert_eq!(bob.snapshot.display_name, "Bob");
        assert_eq!(bob.snapshot.role, "manager");
        assert_eq!(bob.snapshot.user_id, "00000000-0000-0000-0000-0000000000b2");

        // Alice's PIN against Bob's name must fail (no cross-match).
        assert!(unlock_from_bundle(
            &store,
            "Bob",
            "1111",
            "00000000-0000-0000-0000-000000000001"
        )
        .is_err());
    }

    // ── verify_offline_pin ───────────────────────────────────────────────

    #[test]
    fn verify_offline_pin_accepts_correct_and_rejects_wrong() {
        let phc = backend_hash("4242");
        assert!(verify_offline_pin("4242", &phc));
        assert!(!verify_offline_pin("0000", &phc));
        assert!(!verify_offline_pin("", &phc));
    }

    /// The one PHC string both sides verify (madar-shared's `TEST_PHC`,
    /// derived by the server's `hash_offline_pin` under a fixed salt).
    #[test]
    fn verify_offline_pin_accepts_the_shared_phc_string() {
        use madar_authz::pin::{TEST_PHC, TEST_PIN};
        assert!(verify_offline_pin(TEST_PIN, TEST_PHC));
        assert!(!verify_offline_pin("9999", TEST_PHC));
    }

    #[test]
    fn verify_offline_pin_rejects_malformed_phc() {
        // A non-PHC string can't be parsed → false, never panics.
        assert!(!verify_offline_pin("4242", "not-a-phc-hash"));
        assert!(!verify_offline_pin("4242", ""));
    }

    // ── LoginMode ────────────────────────────────────────────────────────

    #[test]
    fn login_mode_is_copy_and_eq() {
        let a = LoginMode::Pin;
        let b = a; // Copy
        assert_eq!(a, b);
        assert_ne!(LoginMode::Pin, LoginMode::Email);
    }
}

// Robustness of the offline PIN verifier — it gatekeeps offline login against an
// org bundle that a corrupt store or an attacker could feed it. It must FAIL
// CLOSED (reject), never panic, on any input.
#[cfg(test)]
mod pin_proptests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        /// Never panics, whatever the PIN/PHC strings are.
        #[test]
        fn verify_offline_pin_never_panics(pin in ".*", phc in ".*") {
            let _ = verify_offline_pin(&pin, &phc);
        }

        /// Anything that isn't a valid argon2 PHC (no leading `$…`) rejects.
        #[test]
        fn non_phc_always_rejects(pin in ".*", junk in "[^$]{0,64}") {
            prop_assert!(!verify_offline_pin(&pin, &junk));
        }
    }
}
