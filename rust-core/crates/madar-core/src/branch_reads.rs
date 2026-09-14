//! The branch's settings reads — kitchen routing mode, kitchen stations,
//! delivery settings, the loyalty programme — from the synced `branch_settings`
//! row (the changefeed carries them; MadarRust
//! `20260917090000_sync_feed_branch_reads.sql`). No read touches the network.
//!
//! A backend older than that migration sends the row without these fields.
//! Then, and only then, the field is FILLED ONCE from its legacy endpoint in
//! the background (online, at most once per core session per field, under
//! [`crate::ledger_ops::FETCH_TIMEOUT`]) into the device's store; the read
//! answers from that fill until the feed carries the field. Never on a timer.

use std::collections::HashSet;
use std::sync::Mutex;

use serde::de::DeserializeOwned;
use serde_json::Value;

use crate::error::CoreError;
use crate::{changes, sync_pull, MadarCore};

/// Row fields and the store key holding a legacy fill of each.
pub(crate) const F_ROUTING: (&str, &str) = ("kitchen_routing_effective", crate::kds::K_ROUTING_MODE);
pub(crate) const F_STATIONS: (&str, &str) = ("kitchen_stations", "cache:kds_stations");
pub(crate) const F_DELIVERY: (&str, &str) = ("delivery", "cache:delivery_settings");
pub(crate) const F_LOYALTY: (&str, &str) = ("loyalty", crate::K_LOYALTY_SETTINGS);

/// Fields already filled (or being filled) this session.
#[derive(Default)]
pub(crate) struct FillState {
    asked: Mutex<HashSet<&'static str>>,
    /// Tills filled from the server this session (`ledger_ops::fill_till_soon`),
    /// with the newest feed seq the device held for the till at that fill.
    tills: Mutex<std::collections::HashMap<String, i64>>,
    /// One-off attempts made this session.
    attempts: Mutex<HashSet<String>>,
    /// Tills with a fill running now.
    filling: Mutex<HashSet<String>>,
}

impl FillState {
    /// Has this till been filled since the feed last moved it? (`newest` = the
    /// newest feed seq the device now holds for the till.)
    pub(crate) fn till_filled(&self, till_id: &str, newest: i64) -> bool {
        self.tills.lock().unwrap_or_else(|e| e.into_inner()).get(till_id).is_some_and(|at| newest <= *at)
    }
    /// Start a till fill; `false` when one is already running.
    pub(crate) fn begin_fill(&self, till_id: &str) -> bool {
        self.filling.lock().unwrap_or_else(|e| e.into_inner()).insert(till_id.to_string())
    }
    pub(crate) fn end_fill(&self, till_id: &str) {
        self.filling.lock().unwrap_or_else(|e| e.into_inner()).remove(till_id);
    }
    /// Was this till filled successfully before (whatever the feed did since)?
    pub(crate) fn till_ever_filled(&self, till_id: &str) -> bool {
        self.tills.lock().unwrap_or_else(|e| e.into_inner()).contains_key(till_id)
    }
    /// `true` the first time `key` is asked for this session.
    pub(crate) fn first_attempt(&self, key: &str) -> bool {
        self.attempts.lock().unwrap_or_else(|e| e.into_inner()).insert(key.to_string())
    }
    pub(crate) fn mark_till_filled(&self, till_id: &str, newest: i64) {
        self.tills.lock().unwrap_or_else(|e| e.into_inner()).insert(till_id.to_string(), newest);
    }
}

/// Where a branch read's answer came from.
pub(crate) enum Source<T> {
    /// The synced row carries the field (`None` = the field is present and null).
    Feed(Option<T>),
    /// The row lacks the field; this is what a legacy fill stored, if any.
    Fill(Option<T>),
}

impl<T> Source<T> {
    pub(crate) fn value(self) -> Option<T> {
        match self {
            Source::Feed(v) | Source::Fill(v) => v,
        }
    }
}

impl MadarCore {
    /// A branch settings field: the synced row's, else the stored legacy fill.
    pub(crate) fn branch_field<T: DeserializeOwned>(&self, field: (&'static str, &'static str)) -> Result<Source<T>, CoreError> {
        let branch = self.session_branch_id()?;
        if let Some(v) = sync_pull::branch_setting(&self.store, &branch, field.0) {
            return Ok(Source::Feed(if v.is_null() { None } else { serde_json::from_value(v).ok() }));
        }
        let raw = self.store.kv_get(field.1).ok().flatten();
        Ok(Source::Fill(raw.and_then(|r| {
            // A legacy fill is stored as the value itself, or (older builds) a
            // one-element list of it.
            let v: Value = serde_json::from_str(&r).unwrap_or(Value::String(r));
            serde_json::from_value::<T>(v.clone())
                .ok()
                .or_else(|| v.as_array().and_then(|a| a.first()).and_then(|x| serde_json::from_value(x.clone()).ok()))
        })))
    }

    /// Fill a field the feed does not carry, once, in the background. `fetch`
    /// returns the value to store (serialised as the read expects it).
    pub(crate) fn fill_branch_field_once<F, Fut>(&self, field: (&'static str, &'static str), fetch: F)
    where
        F: FnOnce(std::sync::Arc<MadarCore>, String) -> Fut + Send + 'static,
        Fut: std::future::Future<Output = Result<Value, CoreError>> + Send + 'static,
    {
        let Ok(branch) = self.session_branch_id() else { return };
        if sync_pull::branch_setting(&self.store, &branch, field.0).is_some()
            || !self.current_session().map(|s| s.online).unwrap_or(false)
            || self.scheduler.manual.load(std::sync::atomic::Ordering::SeqCst)
        {
            return;
        }
        if !self.branch_fills.asked.lock().unwrap_or_else(|e| e.into_inner()).insert(field.0) {
            return;
        }
        let (Some(me), Ok(handle)) = (self.self_arc(), tokio::runtime::Handle::try_current()) else { return };
        handle.spawn(async move {
            if let Ok(v) = fetch(me.clone(), branch).await {
                if me.store.kv_put(field.1, &v.to_string()).is_ok() {
                    me.store.emit_changes([changes::SYNC]);
                }
            }
        });
    }

    /// After a manager's write the server re-emits the settings row; until the
    /// next pull brings it, the local row carries the answer the write returned.
    pub(crate) fn patch_branch_field(&self, field: (&'static str, &'static str), value: &Value) {
        let Ok(branch) = self.session_branch_id() else { return };
        if sync_pull::branch_setting(&self.store, &branch, field.0).is_some() {
            let _ = sync_pull::patch_branch_setting(&self.store, &branch, field.0, value);
        } else {
            let _ = self.store.kv_put(field.1, &value.to_string());
        }
        self.store.emit_changes([changes::SYNC]);
    }
}
