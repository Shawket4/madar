/// The dashboard's ONE realtime connection (`use-branch-realtime.ts`).
///
/// It is opened once, by the shell, for the selected branch, subscribes to
/// every topic the dashboard reads, and turns events into invalidations: a
/// provider that reads `/floor/...` watches `realtimeEpochProvider('/floor/...')`
/// and refetches when an event makes that path stale. Events are nudges, never
/// state.
///
/// Resume: the last `id:` goes back as `Last-Event-ID`, so a blip replays the
/// gap; a `resync` frame invalidates everything. A dropped or refused stream
/// reconnects after 1 s, 2 s, 5 s, 10 s, then every 30 s; a stream that opens
/// resets the backoff.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart' show ApiRequest, ApiTransport;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One server-sent event (`SseFrame`).
class RealtimeFrame {
  const RealtimeFrame({required this.event, this.data = '', this.id});

  final String event;
  final String data;
  final String? id;

  @override
  String toString() => 'RealtimeFrame($event, id: $id)';
}

/// Opens the branch event stream (`GET /realtime/stream?branch_id&topics`,
/// `Accept: text/event-stream`, the session's auth and scope headers).
abstract interface class RealtimeGateway {
  /// Completes when the server accepted the stream (the web's `res.ok`) and
  /// fails when it refused or could not be reached. The returned stream yields
  /// frames until the server closes it (done) or the connection drops (error).
  Future<Stream<RealtimeFrame>> connect({
    required String branchId,
    required String topics,
    String? lastEventId,
  });
}

final realtimeGatewayProvider = Provider<RealtimeGateway>(
  (ref) =>
      throw StateError('realtimeGatewayProvider must be overridden at boot'),
);

/// Backoff between reconnects (`RETRY_MS`).
const List<Duration> realtimeRetryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 30),
];

/// Topics the dashboard consumes; the server intersects with permissions.
const String realtimeTopics = 'floor,tickets,bookings,delivery,tills';

/// Which data an event makes stale, as API path prefixes
/// (`invalidationsFor`). `resync` -> `/`: everything.
List<String> invalidationsFor(String event) {
  if (event == 'resync') return ['/'];
  if (event.startsWith('booking.')) return ['/bookings', '/floor'];
  if (event.startsWith('floor.') ||
      event.startsWith('table.') ||
      event.startsWith('transfer.')) {
    return ['/floor'];
  }
  if (event == 'ticket.table_changed') return ['/floor', '/open-tickets'];
  if (event.startsWith('ticket.')) return ['/open-tickets', '/floor'];
  if (event.startsWith('delivery.')) return ['/delivery-orders'];
  if (event.startsWith('kitchen.')) return ['/kitchen'];
  if (event.startsWith('till.')) return ['/tills', '/reports'];
  if (event == 'payment_methods.availability_changed') {
    return ['/payment-methods'];
  }
  if (event == 'branch.settings_changed') return ['/branches'];
  return [];
}

/// Whether data read from [path] is stale after an invalidation of [prefix]
/// (React Query's `queryKey[0].startsWith(prefix)`).
bool pathInvalidatedBy(String path, String prefix) => path.startsWith(prefix);

/// `parseSseFrames`: complete frames in [buffer] and the partial rest (a chunk
/// boundary lands mid-frame routinely). For a gateway reading raw text.
({List<RealtimeFrame> frames, String rest}) parseSseFrames(String buffer) {
  final normalized = buffer.replaceAll('\r\n', '\n');
  final blocks = normalized.split('\n\n');
  final rest = blocks.removeLast();
  final frames = <RealtimeFrame>[];
  for (final block in blocks) {
    final f = _parseBlock(block);
    if (f != null) frames.add(f);
  }
  return (frames: frames, rest: rest);
}

RealtimeFrame? _parseBlock(String block) {
  var event = 'message';
  String? id;
  final data = <String>[];
  var sawField = false;
  for (final raw in block.split('\n')) {
    if (raw.isEmpty || raw.startsWith(':')) continue;
    final colon = raw.indexOf(':');
    final field = colon == -1 ? raw : raw.substring(0, colon);
    var value = colon == -1 ? '' : raw.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    sawField = true;
    if (field == 'event') {
      event = value;
    } else if (field == 'data') {
      data.add(value);
    } else if (field == 'id') {
      id = value;
    }
  }
  if (!sawField) return null;
  return RealtimeFrame(event: event, data: data.join('\n'), id: id);
}

/// Where events go: raw listeners and invalidated path prefixes.
class RealtimeBus {
  final StreamController<RealtimeFrame> _events =
      StreamController<RealtimeFrame>.broadcast(sync: true);
  final StreamController<List<String>> _invalidations =
      StreamController<List<String>>.broadcast(sync: true);

  /// Every event (`onRealtimeEvent`; rarely needed: prefer the epochs).
  Stream<RealtimeFrame> get events => _events.stream;

  /// The path prefixes each event made stale.
  Stream<List<String>> get invalidations => _invalidations.stream;

  void dispatch(RealtimeFrame frame) {
    final targets = invalidationsFor(frame.event);
    if (targets.isNotEmpty) _invalidations.add(targets);
    _events.add(frame);
  }

  /// Invalidates [prefixes] as an event would (a page's own refresh).
  void invalidate(List<String> prefixes) => _invalidations.add(prefixes);

  Future<void> dispose() async {
    await _events.close();
    await _invalidations.close();
  }
}

/// One branch's connection loop (`useBranchRealtime`'s effect).
class BranchRealtime {
  BranchRealtime({
    required this.gateway,
    required this.branchId,
    required this.bus,
    this.topics = realtimeTopics,
  });

  final RealtimeGateway gateway;
  final String branchId;
  final RealtimeBus bus;
  final String topics;

  int _attempt = 0;
  bool _stopped = false;
  Timer? _timer;
  StreamSubscription<RealtimeFrame>? _sub;
  String? _lastId;

  /// The resume cursor (the last `id:` seen).
  String? get lastEventId => _lastId;

  /// How many reconnects are queued so far without a successful open.
  int get attempt => _attempt;

  bool get isStopped => _stopped;

  void start() => unawaited(_connect());

  Future<void> _connect() async {
    if (_stopped) return;
    try {
      final stream = await gateway.connect(
        branchId: branchId,
        topics: topics,
        lastEventId: _lastId,
      );
      if (_stopped) return;
      _attempt = 0;
      final done = Completer<void>();
      _sub = stream.listen(
        (frame) {
          if (frame.id != null) _lastId = frame.id;
          bus.dispatch(frame);
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future;
    } on Object {
      // Fall through to the retry; a stopped stream is not an error.
    }
    if (_stopped) return;
    final wait =
        realtimeRetryDelays[_attempt < realtimeRetryDelays.length
            ? _attempt
            : realtimeRetryDelays.length - 1];
    _attempt += 1;
    _timer = Timer(wait, () => unawaited(_connect()));
  }

  /// Closes the connection and stops reconnecting.
  void stop() {
    _stopped = true;
    _timer?.cancel();
    unawaited(_sub?.cancel());
  }
}

/// A [RealtimeGateway] over [ApiTransport.stream] (mock mode, and any
/// transport that streams the frames as JSON envelopes).
///
/// The transport yields one string per `data:` frame and so drops the SSE
/// `event:`/`id:` lines; this gateway reads them back from an envelope:
/// `{"event": "floor.table_updated", "id": "42", "data": {…}}` (the frame's
/// data is the envelope's `data`, re-encoded as JSON unless it is a string).
/// A string that is not an envelope arrives as event `message`.
///
/// The stream counts as accepted once it has stayed up for [acceptAfter] or
/// delivered a frame; a refusal before that fails [connect], which is what
/// lets the backoff grow for a stream the server keeps refusing.
class TransportRealtimeGateway implements RealtimeGateway {
  const TransportRealtimeGateway(
    this.transport, {
    this.acceptAfter = const Duration(milliseconds: 300),
  });

  final ApiTransport transport;
  final Duration acceptAfter;

  /// Decodes one data string.
  static RealtimeFrame decode(String raw) {
    try {
      final v = json.decode(raw);
      if (v is Map && v['event'] is String) {
        final data = v['data'];
        return RealtimeFrame(
          event: v['event']! as String,
          data: data == null ? '' : (data is String ? data : json.encode(data)),
          id: v['id']?.toString(),
        );
      }
    } on FormatException {
      // Not JSON: a bare data frame.
    }
    return RealtimeFrame(event: 'message', data: raw);
  }

  /// The envelope [decode] reads: what a mock publishes for one event.
  static String encode(String event, {Object? data, String? id}) =>
      json.encode({'event': event, 'id': ?id, 'data': ?data});

  @override
  Future<Stream<RealtimeFrame>> connect({
    required String branchId,
    required String topics,
    String? lastEventId,
  }) {
    final source = transport.stream(
      ApiRequest(
        method: 'GET',
        path: '/realtime/stream',
        query: {
          'branch_id': [branchId],
          'topics': [topics],
        },
        headers: {'Accept': 'text/event-stream', 'Last-Event-ID': ?lastEventId},
      ),
    );
    final accepted = Completer<Stream<RealtimeFrame>>();
    late final StreamController<RealtimeFrame> out;
    StreamSubscription<String>? sub;
    Timer? grace;
    void accept() {
      grace?.cancel();
      if (!accepted.isCompleted) accepted.complete(out.stream);
    }

    out = StreamController<RealtimeFrame>(
      onCancel: () async {
        grace?.cancel();
        await sub?.cancel();
      },
    );
    sub = source.listen(
      (raw) {
        accept();
        out.add(decode(raw));
      },
      onError: (Object e, StackTrace st) {
        grace?.cancel();
        if (!accepted.isCompleted) {
          accepted.completeError(e, st);
          unawaited(sub?.cancel());
        } else {
          out.addError(e, st);
        }
      },
      onDone: () {
        grace?.cancel();
        if (!accepted.isCompleted) {
          // Closed before anything: an open stream that ended at once.
          accepted.complete(out.stream);
        }
        unawaited(out.close());
      },
    );
    grace = Timer(acceptAfter, accept);
    return accepted.future;
  }
}
