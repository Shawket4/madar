//! The core's sync scheduler (OFFLINE_B_DESIGN §6): what makes a pull happen.
//!
//! * Any realtime event (cloud SSE or LAN), a `resync` frame, a reconnect, or an
//!   acked outbox op NUDGES one changefeed pull: debounced, single-flight, and
//!   always after a drain (the backlog lands before the feed churns rows that are
//!   about to fold).
//! * While the SSE stream is DOWN a fallback poll pulls on a backoff (5 s → 60 s;
//!   a pull that brought changes keeps 5 s, an empty one backs off).
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

/// How long a CONNECTED stream may stay silent before the fallback poll stops
/// trusting it. "Connected" only means the socket is open: a stream can be
/// deaf — a server-side cursor problem, a proxy holding frames — and the device
/// would then sit online and stale forever, because the poll used to skip every
/// beat while `realtime_live()`. The server sends a keep-alive every 20s but
/// the core only records real events, so this is sized well past a genuinely
/// quiet branch's gaps and still bounded: at worst the device is two minutes
/// stale before it checks for itself.
pub(crate) const REALTIME_SILENCE_GRACE: Duration = Duration::from_secs(120);

/// May the fallback poll skip this beat? Only while the stream is BOTH
/// connected and has spoken within the grace — a connected stream that has gone
/// silent is not evidence of freshness, it is the shape of the deaf-stream bug.
pub(crate) fn poll_skips(live: bool, silence_ms: u64) -> bool {
    live && silence_ms <= REALTIME_SILENCE_GRACE.as_millis() as u64
}

/// The next fallback-poll interval: doubles, capped.
pub(crate) fn next_poll_interval(current: Duration) -> Duration {
    (current * 2).clamp(POLL_MIN, POLL_MAX)
}

/// The fallback poll's next interval after a pull that applied `applied` rows
/// (`None` = it failed): changes keep the quick beat, nothing new backs off.
pub(crate) fn after_poll(current: Duration, applied: Option<u32>) -> Duration {
    match applied {
        Some(n) if n > 0 => POLL_MIN,
        _ => next_poll_interval(current),
    }
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
    /// This core's pull single-flight.
    pub pull_flight: crate::sync_pull::PullFlight,
    /// Manual scheduling (the simulation harness): nothing is spawned; nudges and
    /// poll requests are only counted, and the harness runs them when it decides.
    pub manual: AtomicBool,
    /// Nudges asked for since the harness last took them.
    pub nudges_wanted: AtomicU64,
    /// The fallback poll was asked to run.
    pub poll_wanted: AtomicBool,
    /// Monotonic ms (process uptime) of the last realtime event or connect.
    /// 0 = nothing yet this process.
    pub last_realtime_ms: AtomicU64,
}

/// Process-uptime clock for the silence grace. Deliberately NOT the wall clock:
/// a tablet whose clock jumps (see the LAN skew work) must not make the stream
/// look silent for hours, or fresh.
fn uptime_ms() -> u64 {
    use std::sync::OnceLock;
    static START: OnceLock<std::time::Instant> = OnceLock::new();
    START.get_or_init(std::time::Instant::now).elapsed().as_millis() as u64 + 1
}

impl MadarCore {
    /// Record that the realtime stream just spoke (an event, or a connect).
    pub(crate) fn mark_realtime_activity(&self) {
        self.scheduler
            .last_realtime_ms
            .store(uptime_ms(), Ordering::Relaxed);
    }

    /// Has a connected stream been silent past [`REALTIME_SILENCE_GRACE`]?
    pub(crate) fn realtime_gone_quiet(&self) -> bool {
        let last = self.scheduler.last_realtime_ms.load(Ordering::Relaxed);
        if last == 0 {
            return true;
        }
        !poll_skips(true, uptime_ms().saturating_sub(last))
    }

    /// Switch this core to manual scheduling (see [`SchedulerState::manual`]).
    #[doc(hidden)]
    pub fn set_manual_scheduling(&self, on: bool) {
        self.scheduler.manual.store(on, Ordering::SeqCst);
    }

    /// Take the nudges asked for since the last call (manual scheduling).
    #[doc(hidden)]
    pub fn take_nudges(&self) -> u64 {
        self.scheduler.nudges_wanted.swap(0, Ordering::SeqCst)
    }

    /// Whether the fallback poll was asked for (manual scheduling), clearing it.
    #[doc(hidden)]
    pub fn take_poll_wanted(&self) -> bool {
        self.scheduler.poll_wanted.swap(false, Ordering::SeqCst)
    }
}

impl MadarCore {
    /// Something says there is new work on the server. Recorded on the pull
    /// single-flight BEFORE the debounce, so a pull already in flight — whose
    /// request predates this news — cannot be handed back as if it covered it.
    pub(crate) fn announce_change(&self) {
        self.scheduler.pull_flight.announce();
    }

    /// Ask for a drain + incremental pull soon. Cheap and idempotent: nudges
    /// inside the debounce window collapse into one pull. A no-op without a
    /// tokio runtime or a session.
    pub(crate) fn nudge_sync(&self) {
        // Announce FIRST, even when there is no session or no runtime to act on
        // it: the news is real whatever we do about it, and a pull already on
        // the wire cannot contain it.
        self.announce_change();
        if self.current_session().is_none() {
            return;
        }
        if self.scheduler.manual.load(Ordering::SeqCst) {
            self.scheduler.nudges_wanted.fetch_add(1, Ordering::SeqCst);
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
        if self.scheduler.manual.load(Ordering::SeqCst) {
            self.scheduler.nudges_wanted.fetch_add(1, Ordering::SeqCst);
            return;
        }
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
        if self.scheduler.manual.load(Ordering::SeqCst) {
            self.scheduler.poll_wanted.store(true, Ordering::SeqCst);
            return;
        }
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
                // Skip the beat only while the stream is BOTH connected and
                // actually speaking. A connected-but-silent stream is exactly
                // the failure that hid the restarted-bus bug, so past the
                // grace we poll anyway — on the slow beat, so a quiet branch
                // costs one request a minute, not a busy loop.
                if core.realtime_live() && !core.realtime_gone_quiet() {
                    interval = POLL_MIN;
                    continue;
                }
                if core.realtime_live() {
                    interval = POLL_MAX;
                }
                core.scheduler.pulls_started.fetch_add(1, Ordering::Relaxed);
                let _ = core.drain_outbox().await;
                // A pull that brought changes keeps the quick beat (the branch is
                // busy); an empty one or a failure backs off toward POLL_MAX, so
                // an idle device with its stream down asks once a minute.
                interval = after_poll(interval, core.pull(false).await.ok());
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
            core.mark_realtime_activity();
            core.store.emit_changes(crate::changes::tables_for_event(&event.event_type));
            core.nudge_sync();
        }
        self.inner.on_event(event);
    }

    fn on_connection_changed(&self, connected: bool) {
        self.connected.store(connected, Ordering::Relaxed);
        if let Some(core) = self.core.upgrade() {
            core.mark_realtime_activity();
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
    fn a_connected_but_silent_stream_does_not_hold_the_poll_off() {
        assert!(poll_skips(true, 0), "a live, talking stream: no poll needed");
        assert!(
            poll_skips(true, REALTIME_SILENCE_GRACE.as_millis() as u64),
            "at the grace it is still trusted"
        );
        assert!(
            !poll_skips(true, REALTIME_SILENCE_GRACE.as_millis() as u64 + 1),
            "a stream that has gone quiet is checked for itself, not believed"
        );
        assert!(!poll_skips(false, 0), "a down stream always polls");
    }

    #[test]
    fn an_idle_fallback_poll_backs_off_and_a_busy_one_keeps_the_beat() {
        let mut d = POLL_MIN;
        for _ in 0..10 {
            d = after_poll(d, Some(0));
        }
        assert_eq!(d, POLL_MAX, "nothing new: once a minute");
        assert_eq!(after_poll(d, Some(3)), POLL_MIN, "changes: the quick beat");
        assert_eq!(after_poll(POLL_MIN, None), Duration::from_secs(10), "a failure backs off");
    }

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
