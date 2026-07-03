//! Realtime inversion: the core's `EventListener` + `RealtimePlayer` callbacks
//! become two Dart streams. Ordering within each stream is the core's own
//! (single FIFO); `sink.add` is a non-blocking enqueue, satisfying the core's
//! "return promptly" contract on the SSE supervisor task.
use madar_core::realtime::RealtimeEvent;

use crate::frb_generated::StreamSink;

/// Board-refresh signals: every realtime event plus SSE connect/drop edges.
pub enum RealtimeMessage {
    /// A domain event arrived (cloud SSE or LAN relay). `data` is raw JSON.
    Event { event_type: String, data: String },
    /// The SSE connection came up / went down (supervisor keeps reconnecting).
    ConnectionChanged { connected: bool },
}

/// Platform-primitive alert commands. The CORE decides when to alert and
/// builds localized text; the host only performs the primitive.
pub enum AlertCommand {
    /// Play the bundled "new work" ping sound.
    Ping,
    /// Post/replace a local OS notification (same `tag` replaces).
    Notify {
        title: String,
        body: String,
        tag: String,
    },
    /// Fire a confirmation haptic.
    Haptic,
}

pub(crate) struct SinkListener(pub(crate) StreamSink<RealtimeMessage>);

impl madar_core::realtime::EventListener for SinkListener {
    fn on_event(&self, event: RealtimeEvent) {
        let _ = self.0.add(RealtimeMessage::Event {
            event_type: event.event_type,
            data: event.data,
        });
    }

    fn on_connection_changed(&self, connected: bool) {
        let _ = self.0.add(RealtimeMessage::ConnectionChanged { connected });
    }
}

pub(crate) struct SinkPlayer(pub(crate) StreamSink<AlertCommand>);

impl madar_core::realtime::RealtimePlayer for SinkPlayer {
    fn play_ping(&self) {
        let _ = self.0.add(AlertCommand::Ping);
    }

    fn post_notification(&self, title: String, body: String, tag: String) {
        let _ = self.0.add(AlertCommand::Notify { title, body, tag });
    }

    fn haptic(&self) {
        let _ = self.0.add(AlertCommand::Haptic);
    }
}
