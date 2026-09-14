//! The core's sync scheduler (OFFLINE_B_DESIGN §6): what makes a pull happen.
//!
//! * Any realtime event (cloud SSE or LAN), a `resync` frame, a reconnect, or an
//!   acked outbox op NUDGES one changefeed pull: debounced, single-flight, and
//!   always after a drain (the backlog lands before the feed churns rows that are
//!   about to fold).
//! * While the SSE stream is DOWN a fallback poll pulls on a backoff (5 s → 60 s).
//!   This is the network half of the "realtime is the fast path, a gated poll is
//!   the fallback" rule in madar/CLAUDE.md — it moved into the core; the screens'
//!   `RealtimeGatedPoll` still re-reads locally on the same edge.
//!
//! Screens never pull. They read local rows and re-read when `watch_tables`
//! says a table changed.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Weak};
use std::time::Duration;

use crate::realtime::{EventListener, RealtimeEvent};
use crate::MadarCore;

/// How long a nudge waits for more nudges before pulling.
pub(crate) const NUDGE_DEBOUNCE: Duration = Duration::from_millis(250);
/// The fallback poll's first and longest interval while realtime is down.
pub(crate) const POLL_MIN: Duration = Duration::from_secs(5);
pub(crate) const POLL_MAX: Duration = Duration::from_secs(60);

/// The next fallback-poll interval: doubles, capped.
pub(crate) fn next_poll_interval(current: Duration) -> Duration {
    (current * 2).clamp(POLL_MIN, POLL_MAX)
}

/// Scheduler state kept on the core.
#[derive(Default)]
pub(crate) struct SchedulerState {
    /// A nudge is waiting out its debounce.
    pub nudge_pending: AtomicBool,
    /// The fallback poll loop is running.
    pub poll_running: AtomicBool,
    /// Pulls started by the scheduler (tests read it).
    pub pulls_started: AtomicU64,
}

impl MadarCore {
    /// Ask for a drain + incremental pull soon. Cheap and idempotent: nudges
    /// inside the debounce window collapse into one pull. A no-op without a
    /// tokio runtime or a session.
    pub(crate) fn nudge_sync(&self) {
        if self.current_session().is_none() {
            return;
        }
        if self.scheduler.nudge_pending.swap(true, Ordering::SeqCst) {
            return;
        }
        let (Some(me), Ok(handle)) = (self.self_arc(), tokio::runtime::Handle::try_current()) else {
            self.scheduler.nudge_pending.store(false, Ordering::SeqCst);
            return;
        };
        handle.spawn(async move {
            tokio::time::sleep(NUDGE_DEBOUNCE).await;
            me.scheduler.nudge_pending.store(false, Ordering::SeqCst);
            me.scheduler.pulls_started.fetch_add(1, Ordering::Relaxed);
            let _ = me.drain_outbox().await;
            let _ = me.pull(false).await;
        });
    }

    /// [`Self::nudge_sync`] once `delay` has passed (a paced drain resumes).
    pub(crate) fn nudge_sync_after(&self, delay: Duration) {
        let (Some(me), Ok(handle)) = (self.self_arc(), tokio::runtime::Handle::try_current()) else {
            return;
        };
        let weak: Weak<MadarCore> = Arc::downgrade(&me);
        drop(me);
        handle.spawn(async move {
            tokio::time::sleep(delay).await;
            if let Some(core) = weak.upgrade() {
                core.nudge_sync();
            }
        });
    }

    /// Start the fallback poll if it is not running. It exits by itself once
    /// the session ends; while the SSE stream is connected it only sleeps.
    pub(crate) fn ensure_fallback_poll(&self) {
        if self.scheduler.poll_running.swap(true, Ordering::SeqCst) {
            return;
        }
        let (Some(me), Ok(handle)) = (self.self_arc(), tokio::runtime::Handle::try_current()) else {
            self.scheduler.poll_running.store(false, Ordering::SeqCst);
            return;
        };
        let weak: Weak<MadarCore> = Arc::downgrade(&me);
        drop(me);
        handle.spawn(async move {
            let mut interval = POLL_MIN;
            loop {
                tokio::time::sleep(interval).await;
                let Some(core) = weak.upgrade() else { return };
                if core.current_session().is_none() {
                    core.scheduler.poll_running.store(false, Ordering::SeqCst);
                    return;
                }
                if core.realtime_live() {
                    interval = POLL_MIN;
                    continue;
                }
                core.scheduler.pulls_started.fetch_add(1, Ordering::Relaxed);
                let _ = core.drain_outbox().await;
                let ok = core.pull(false).await.is_ok();
                interval = if ok { POLL_MIN } else { next_poll_interval(interval) };
            }
        });
    }
}

/// Wraps the host-facing listener: records the SSE connection state and turns
/// every event into a pull nudge, then forwards unchanged.
pub(crate) struct SyncNudgeListener {
    pub inner: Arc<dyn EventListener>,
    pub core: Weak<MadarCore>,
    pub connected: Arc<AtomicBool>,
}

impl EventListener for SyncNudgeListener {
    fn on_event(&self, event: RealtimeEvent) {
        if let Some(core) = self.core.upgrade() {
            core.store.emit_changes(crate::changes::tables_for_event(&event.event_type));
            core.nudge_sync();
        }
        self.inner.on_event(event);
    }

    fn on_connection_changed(&self, connected: bool) {
        self.connected.store(connected, Ordering::Relaxed);
        if let Some(core) = self.core.upgrade() {
            core.store.emit_changes([crate::changes::SYNC]);
            if connected {
                // A reconnect may have missed events: catch up once.
                core.nudge_sync();
            } else {
                core.ensure_fallback_poll();
            }
        }
        self.inner.on_connection_changed(connected);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fallback_poll_backs_off_to_a_ceiling() {
        let mut d = POLL_MIN;
        let mut seen = vec![d];
        for _ in 0..6 {
            d = next_poll_interval(d);
            seen.push(d);
        }
        assert_eq!(seen[1], Duration::from_secs(10));
        assert_eq!(*seen.last().unwrap(), POLL_MAX);
        assert!(seen.windows(2).all(|w| w[1] >= w[0]));
    }
}
