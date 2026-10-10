//! The management dashboard's saved API answers, so a relaunch with no network
//! still shows the latest data it has (the owner's requirement): the body of
//! every successful GET it may keep, keyed by the person, the org and branch
//! in scope and the request.
//!
//! - One person's answers at a time: [`ApiCache::claim`] wipes anyone else's,
//!   a save for someone who is not the owner is dropped, and sign-out wipes it
//!   all ([`ApiCache::wipe`]). Not encrypted: an on-device store, as the POS's
//!   and Dawam's are (owner, 2026-10-10).
//! - Bounded: past [`DEFAULT_MAX_BYTES`] the least recently used answers go,
//!   down to 90 % of it.
//! - A narrower date range is answered from a wider answer held when every
//!   figure of it is provably the server's own ([`derive`]): online from an
//!   answer read live in the last `fresh_ms` (as a fresh cache hit), offline
//!   from a saved one.
//!
//! Only the dashboard opens it. Its table is created here, never by a
//! [`crate::schema`] step, so a POS or Dawam store keeps its shape and
//! version.

mod derive;

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};

use rusqlite::{Connection, OptionalExtension, params};

use crate::error::CoreResult;
use crate::store::Store;

/// 64 MB: weeks of every page a busy owner opens.
pub const DEFAULT_MAX_BYTES: i64 = 64 * 1024 * 1024;

const TABLE: &str = "CREATE TABLE IF NOT EXISTS api_cache (
  prefix   TEXT NOT NULL,     -- user|org|branch|GET path
  query    TEXT NOT NULL,     -- the query sorted by name, as JSON pairs
  user_id  TEXT NOT NULL,
  size     INTEGER NOT NULL,
  saved_at INTEGER NOT NULL,  -- epoch ms
  used     INTEGER NOT NULL,  -- LRU order: higher = read or saved later
  -- Last: the scans above never walk a large answer's overflow pages.
  body     BLOB NOT NULL,     -- the JSON the server sent
  PRIMARY KEY (prefix, query)
)";

/// Who is asking, as far as the server's answer depends on it.
#[derive(Clone, Debug)]
pub struct CacheScope {
    pub user: String,
    pub org: Option<String>,
    /// The branch picked in the scope bar (`None`: every branch).
    pub branch: Option<String>,
}

/// One request as the dashboard sends it.
#[derive(Clone, Debug)]
pub struct CacheRequest {
    pub method: String,
    pub path: String,
    /// In order; a name may repeat.
    pub query: Vec<(String, String)>,
    pub headers: Vec<(String, String)>,
}

/// A saved answer: the JSON body as the server sent it, and when.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SavedAnswer {
    pub body: Vec<u8>,
    pub saved_at_ms: i64,
}

/// Paths whose answers are never saved: sign-in and identity, the public
/// pages (guest tokens), the till sync and stream, a device's own grants.
const NEVER_SAVED_PREFIXES: &[&str] = &["/auth/", "/public/", "/sync/", "/realtime/", "/devices/me/"];

/// Whether `req`'s answer may be saved: a GET, not an export (`X-Madar-Export`
/// is counted and rate-limited, never answered from a cache), not a secret
/// (the offline sign-in bundle holds PIN hashes and the LAN secret; a
/// suggested PIN).
pub fn keepable(req: &CacheRequest) -> bool {
    let path = req.path.as_str();
    req.method.eq_ignore_ascii_case("GET")
        && !req.headers.iter().any(|(k, _)| k.eq_ignore_ascii_case("x-madar-export"))
        && !NEVER_SAVED_PREFIXES.iter().any(|p| path.starts_with(p))
        && path != "/users/pin-suggestion"
        && !matches!(
            path.strip_prefix("/orgs/").and_then(|r| r.split_once('/')),
            Some((org, "offline-auth-bundle")) if !org.is_empty()
        )
}

/// The branch whose zone a narrower range of `path` is cut in: `Some(None)`
/// for every branch (the org's zone), `None` when no deriver needs a zone.
pub fn zone_branch(path: &str) -> Option<Option<String>> {
    derive::zone_branch(path)
}

fn prefix(scope: &CacheScope, path: &str) -> String {
    format!(
        "{}|{}|{}|GET {path}",
        scope.user,
        scope.org.as_deref().unwrap_or(""),
        scope.branch.as_deref().unwrap_or("")
    )
}

/// The query sorted by name (a name's values keep their order: the sort is
/// stable). The language is not in the key: no GET body depends on it (one
/// that does takes it as a query parameter).
fn canonical_query(query: &[(String, String)]) -> String {
    let mut q = query.to_vec();
    q.sort_by(|a, b| a.0.cmp(&b.0));
    serde_json::to_string(&q).unwrap_or_default()
}

fn is_json(headers: &[(String, String)]) -> bool {
    headers
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case("content-type"))
        .is_some_and(|(_, v)| v.to_ascii_lowercase().contains("json"))
}

struct Live {
    query: Vec<(String, String)>,
    body: Vec<u8>,
    at_ms: i64,
}

#[derive(Default)]
struct State {
    /// The person the saved answers belong to; `None`: nothing is saved.
    owner: Option<String>,
    /// Answers read live in the last `fresh_ms` that a deriver can narrow,
    /// by (prefix, query).
    live: HashMap<(String, String), Live>,
    /// Requests a deriver answered online, and when: asked again within
    /// `fresh_ms` it is a refetch, which goes to the server.
    derived_at: HashMap<(String, String), i64>,
}

/// The saved answers. Lock order: the state, then the store.
pub struct ApiCache {
    store: Arc<Store>,
    max_bytes: i64,
    /// The dashboard's query stale time.
    fresh_ms: i64,
    state: Mutex<State>,
}

impl ApiCache {
    /// Over `store` (the dashboard core's own), creating its table.
    pub fn open(store: Arc<Store>, fresh_ms: i64) -> CoreResult<ApiCache> {
        store.with_conn(|c| Ok(c.execute_batch(TABLE)?))?;
        Ok(ApiCache { store, max_bytes: DEFAULT_MAX_BYTES, fresh_ms, state: Mutex::default() })
    }

    /// In memory: tests and the dashboard's mock mode.
    pub fn in_memory(fresh_ms: i64) -> CoreResult<ApiCache> {
        Self::open(Arc::new(Store::open("")?), fresh_ms)
    }

    fn state(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Makes `user` the owner; anyone else's answers are wiped first.
    pub fn claim(&self, user: &str) -> CoreResult<()> {
        let mut s = self.state();
        self.store
            .with_conn(|c| Ok(c.execute("DELETE FROM api_cache WHERE user_id <> ?1", [user])?))?;
        if s.owner.as_deref() != Some(user) {
            *s = State { owner: Some(user.to_string()), ..State::default() };
        }
        Ok(())
    }

    /// Forgets everything, the owner too.
    pub fn wipe(&self) -> CoreResult<()> {
        let mut s = self.state();
        *s = State::default();
        self.store.with_conn(|c| Ok(c.execute("DELETE FROM api_cache", [])?))?;
        Ok(())
    }

    /// What was read may have changed (a write, a realtime nudge, a refresh by
    /// hand): nothing held so far answers for another range online.
    pub fn forget_recent(&self) {
        self.state().live.clear();
    }

    /// Saves the server's answer to `req`, read at `at_ms`. Dropped unless it
    /// is a keepable GET with a JSON body for the owner, no larger than the
    /// bound.
    pub fn save(
        &self,
        scope: &CacheScope,
        req: &CacheRequest,
        headers: &[(String, String)],
        body: &[u8],
        at_ms: i64,
    ) -> CoreResult<()> {
        let size = body.len() as i64;
        if !keepable(req) || size == 0 || size > self.max_bytes || !is_json(headers) {
            return Ok(());
        }
        let mut s = self.state();
        if s.owner.as_deref() != Some(scope.user.as_str()) {
            return Ok(());
        }
        let key = (prefix(scope, &req.path), canonical_query(&req.query));
        if derive::is_source(&req.path) {
            let fresh = self.fresh_ms;
            s.live.retain(|_, v| at_ms - v.at_ms < fresh);
            s.live.insert(key.clone(), Live { query: req.query.clone(), body: body.to_vec(), at_ms });
        }
        self.store.with_conn(|c| {
            c.execute(
                "INSERT INTO api_cache (prefix, query, user_id, size, saved_at, used, body)
                 VALUES (?1, ?2, ?3, ?4, ?5, (SELECT COALESCE(MAX(used), 0) + 1 FROM api_cache), ?6)
                 ON CONFLICT (prefix, query) DO UPDATE SET user_id = excluded.user_id,
                   body = excluded.body, size = excluded.size,
                   saved_at = excluded.saved_at, used = excluded.used",
                params![key.0, key.1, scope.user, size, at_ms, body],
            )?;
            evict(c, self.max_bytes, &key)
        })
    }

    /// Online: `req`'s narrower range derived exactly from a wider answer read
    /// live in the last `fresh_ms`. `None` when there is none, or when this
    /// request was answered so in the last `fresh_ms` (asked again, it is a
    /// refetch, which goes to the server). `zone`: the zone [`zone_branch`]
    /// names, when known for certain.
    pub fn recent(&self, scope: &CacheScope, req: &CacheRequest, now_ms: i64, zone: Option<&str>) -> Option<Vec<u8>> {
        if !keepable(req) {
            return None;
        }
        let (d, want) = derive::want(req, zone)?;
        let mut s = self.state();
        let fresh = self.fresh_ms;
        s.live.retain(|_, v| now_ms - v.at_ms < fresh);
        s.derived_at.retain(|_, at| now_ms - *at < fresh);
        let key = (prefix(scope, &req.path), canonical_query(&req.query));
        if s.derived_at.contains_key(&key) {
            return None;
        }
        let source = prefix(scope, d.source_of(&req.path));
        let out = s
            .live
            .iter()
            .filter(|(k, _)| k.0 == source && **k != key)
            .find_map(|(_, v)| if d.covers(&v.query, &want) { d.derive(&v.body, &want) } else { None })?;
        s.derived_at.insert(key, now_ms);
        Some(out)
    }

    /// Offline: the saved answer to `req`, or one derived from a saved wider
    /// range, whichever was saved later.
    pub fn saved(&self, scope: &CacheScope, req: &CacheRequest, zone: Option<&str>) -> CoreResult<Option<SavedAnswer>> {
        if !keepable(req) {
            return Ok(None);
        }
        let _s = self.state();
        let key = (prefix(scope, &req.path), canonical_query(&req.query));
        self.store.with_conn(|c| {
            let mut best = read(c, &key)?;
            let Some((d, want)) = derive::want(req, zone) else {
                return Ok(best);
            };
            let source = prefix(scope, d.source_of(&req.path));
            let candidates = c
                .prepare("SELECT query, saved_at FROM api_cache WHERE prefix = ?1 ORDER BY saved_at DESC")?
                .query_map([&source], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))?
                .collect::<Result<Vec<_>, _>>()?;
            for (query, at) in candidates {
                if source == key.0 && query == key.1 {
                    continue;
                }
                if best.as_ref().is_some_and(|b| at <= b.saved_at_ms) {
                    break;
                }
                let Ok(pairs) = serde_json::from_str::<Vec<(String, String)>>(&query) else {
                    continue;
                };
                if !d.covers(&pairs, &want) {
                    continue;
                }
                let Some(wider) = read(c, &(source.clone(), query))? else {
                    continue;
                };
                if let Some(body) = d.derive(&wider.body, &want) {
                    best = Some(SavedAnswer { body, saved_at_ms: wider.saved_at_ms });
                    break;
                }
            }
            Ok(best)
        })
    }
}

impl crate::MadarCore {
    /// The management dashboard's saved API answers, in this core's store.
    pub fn api_cache(&self, fresh_ms: i64) -> CoreResult<ApiCache> {
        ApiCache::open(self.store.clone(), fresh_ms)
    }
}

/// The answer under `key`, marked used.
fn read(c: &Connection, key: &(String, String)) -> CoreResult<Option<SavedAnswer>> {
    let hit = c
        .query_row(
            "SELECT body, saved_at FROM api_cache WHERE prefix = ?1 AND query = ?2",
            params![key.0, key.1],
            |r| Ok(SavedAnswer { body: r.get(0)?, saved_at_ms: r.get(1)? }),
        )
        .optional()?;
    if hit.is_some() {
        c.execute(
            "UPDATE api_cache SET used = (SELECT MAX(used) + 1 FROM api_cache)
             WHERE prefix = ?1 AND query = ?2",
            params![key.0, key.1],
        )?;
    }
    Ok(hit)
}

/// Past `max` bytes, the least recently used answers go (never `keep`, the
/// one just saved) until 90 % of it is left.
fn evict(c: &Connection, max: i64, keep: &(String, String)) -> CoreResult<()> {
    let mut total: i64 = c.query_row("SELECT COALESCE(SUM(size), 0) FROM api_cache", [], |r| r.get(0))?;
    if total <= max {
        return Ok(());
    }
    let target = max * 9 / 10;
    let oldest = c
        .prepare("SELECT prefix, query, size FROM api_cache ORDER BY used")?
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, i64>(2)?)))?
        .collect::<Result<Vec<_>, _>>()?;
    for (p, q, size) in oldest {
        if total <= target {
            break;
        }
        if p == keep.0 && q == keep.1 {
            continue;
        }
        c.execute("DELETE FROM api_cache WHERE prefix = ?1 AND query = ?2", params![p, q])?;
        total -= size;
    }
    Ok(())
}

#[cfg(test)]
mod tests;
