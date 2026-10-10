//! The dashboard's saved answers (`madar_core::api_cache`) for its Dart
//! transport: it saves each live answer, asks for a narrower range's answer
//! online, and for a saved one when the server cannot be reached. Binding
//! only: what is kept, under which key, for how long and what a narrower
//! range is are the core's. Synchronous, as the Dart cache it replaces
//! was (one small SQLite step per answer).
use flutter_rust_bridge::frb;
use madar_core::api_cache::{self, ApiCache};

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;
use crate::api::transport::ApiPair;

/// Who is asking: the person, the org and the branch in scope (`None`: every
/// branch).
pub struct CacheScope {
    pub user: String,
    pub org: Option<String>,
    pub branch: Option<String>,
}

/// One request as the dashboard sends it (query and headers in order).
pub struct CacheRequest {
    pub method: String,
    pub path: String,
    pub query: Vec<ApiPair>,
    pub headers: Vec<ApiPair>,
}

/// A saved answer: the JSON body as the server sent it, and when (epoch ms).
pub struct CachedAnswer {
    pub body: Vec<u8>,
    pub saved_at_ms: i64,
}

/// The branch whose zone a narrower range is cut in; `branch_id` `None`:
/// every branch, the org's zone.
pub struct ZoneOf {
    pub branch_id: Option<String>,
}

fn pairs(v: Vec<ApiPair>) -> Vec<(String, String)> {
    v.into_iter().map(|p| (p.key, p.value)).collect()
}

impl From<CacheScope> for api_cache::CacheScope {
    fn from(s: CacheScope) -> Self {
        api_cache::CacheScope { user: s.user, org: s.org, branch: s.branch }
    }
}

impl From<CacheRequest> for api_cache::CacheRequest {
    fn from(r: CacheRequest) -> Self {
        api_cache::CacheRequest {
            method: r.method,
            path: r.path,
            query: pairs(r.query),
            headers: pairs(r.headers),
        }
    }
}

#[frb(opaque)]
pub struct OfflineCache {
    inner: ApiCache,
}

impl OfflineCache {
    /// In memory: tests and mock mode. `fresh_ms`: the query stale time.
    #[frb(sync)]
    pub fn in_memory(fresh_ms: i64) -> Result<OfflineCache, MadarError> {
        Ok(OfflineCache { inner: ApiCache::in_memory(fresh_ms)? })
    }

    /// The branch whose zone `path`'s narrower ranges are cut in; `None`
    /// when none is needed.
    #[frb(sync)]
    pub fn zone_of(path: String) -> Option<ZoneOf> {
        api_cache::zone_branch(&path).map(|branch_id| ZoneOf { branch_id })
    }

    /// Makes `user_id` the owner; anyone else's answers are wiped first.
    #[frb(sync)]
    pub fn claim(&self, user_id: String) -> Result<(), MadarError> {
        Ok(self.inner.claim(&user_id)?)
    }

    /// Forgets everything (sign-out).
    #[frb(sync)]
    pub fn wipe(&self) -> Result<(), MadarError> {
        Ok(self.inner.wipe()?)
    }

    /// What was read may have changed: nothing held answers another range
    /// online.
    #[frb(sync)]
    pub fn forget_recent(&self) {
        self.inner.forget_recent();
    }

    /// Saves the server's 2xx answer (`headers` and `body` as it sent them),
    /// read at `at_ms`; the core drops what it does not keep.
    #[frb(sync)]
    pub fn save(
        &self,
        scope: CacheScope,
        request: CacheRequest,
        headers: Vec<ApiPair>,
        body: Vec<u8>,
        at_ms: i64,
    ) -> Result<(), MadarError> {
        Ok(self
            .inner
            .save(&scope.into(), &request.into(), &pairs(headers), &body, at_ms)?)
    }

    /// Online: a narrower range's answer from a wider one read live moments
    /// ago, or `None` (ask the server). `zone`: the zone [`Self::zone_of`]
    /// names, when known.
    #[frb(sync)]
    pub fn recent(
        &self,
        scope: CacheScope,
        request: CacheRequest,
        now_ms: i64,
        zone: Option<String>,
    ) -> Option<Vec<u8>> {
        self.inner
            .recent(&scope.into(), &request.into(), now_ms, zone.as_deref())
    }

    /// Offline: the saved answer, or one derived from a saved wider range,
    /// whichever was saved later.
    #[frb(sync)]
    pub fn saved(
        &self,
        scope: CacheScope,
        request: CacheRequest,
        zone: Option<String>,
    ) -> Result<Option<CachedAnswer>, MadarError> {
        Ok(self
            .inner
            .saved(&scope.into(), &request.into(), zone.as_deref())?
            .map(|s| CachedAnswer { body: s.body, saved_at_ms: s.saved_at_ms }))
    }
}

impl MadarBridge {
    /// The saved answers, in this core's own store.
    #[frb(sync)]
    pub fn offline_cache(&self, fresh_ms: i64) -> Result<OfflineCache, MadarError> {
        Ok(OfflineCache { inner: self.inner.api_cache(fresh_ms)? })
    }
}
