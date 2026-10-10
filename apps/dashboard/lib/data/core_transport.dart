/// Real mode's API transport (docs/fdash/SPEC.md §3.1): every generated API
/// call goes to the Rust core over the dashboard bridge (`api_request` /
/// `api_stream`). The core sends it on its own client (the token, the
/// identity and org/branch headers, the refresh) and words a refusal in the
/// active language; this file only converts between the seam's types and the
/// bridge's, in pure functions the tests drive without the native library.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show RealtimeFrame, RealtimeGateway;
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart' as rb;

/// The web's own sentence for a coded refusal (its `errors.codes.<CODE>`,
/// filled with the refusal's `vars`) when the host has one; null keeps the
/// core's words.
typedef RefusalWords = String? Function(String code, Map<String, Object?> vars);

/// The bridge calls the transport makes: the generated `MadarBridge` in real
/// mode ([BridgeCoreApi]), a fake in tests.
abstract interface class CoreApi {
  /// Throws [rb.ApiFailure] for a non-2xx answer or no answer.
  Future<rb.ApiReply> apiRequest(rb.ApiCall call);

  /// `opened`, then the frames; a failure as a last item.
  Stream<rb.ApiStreamItem> apiStream(rb.ApiCall call, String streamId);

  void apiStreamCancel(String streamId);
}

/// [CoreApi] over the dashboard bridge.
class BridgeCoreApi implements CoreApi {
  const BridgeCoreApi(this.bridge);

  final rb.MadarBridge bridge;

  @override
  Future<rb.ApiReply> apiRequest(rb.ApiCall call) =>
      bridge.apiRequest(call: call);

  @override
  Stream<rb.ApiStreamItem> apiStream(rb.ApiCall call, String streamId) =>
      bridge.apiStream(call: call, streamId: streamId);

  @override
  void apiStreamCancel(String streamId) =>
      bridge.apiStreamCancel(streamId: streamId);
}

/// [ApiTransport] over the core.
class CoreTransport implements ApiTransport {
  CoreTransport(this.core, {this.refusalWords});

  /// The transport over the app's bridge handle.
  factory CoreTransport.bridge(
    rb.MadarBridge bridge, {
    RefusalWords? refusalWords,
  }) => CoreTransport(BridgeCoreApi(bridge), refusalWords: refusalWords);

  final CoreApi core;

  /// See [RefusalWords].
  final RefusalWords? refusalWords;

  static int _streams = 0;

  /// A name for one open stream, unique in this process.
  static String _nextStreamId() =>
      'fdash-${++_streams}-${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    final call = coreCallOf(request);
    final rb.ApiReply reply;
    try {
      reply = await core.apiRequest(call);
    } on rb.ApiFailure catch (f) {
      throw apiExceptionOf(f, refusalWords: refusalWords);
    }
    return apiResponseOf(reply);
  }

  /// The `data:` of every frame that carries any.
  @override
  Stream<String> stream(ApiRequest request) =>
      events(request).where((f) => f.data.isNotEmpty).map((f) => f.data);

  /// Every frame of [request]'s event stream as the web's parser yields it
  /// (its `event:` name included, which the web's invalidations key on). A
  /// refusal or a dropped connection is an [ApiException] error, then the
  /// stream ends. Cancelling the subscription stops the core's stream.
  /// [onOpen] runs once the server accepted it.
  Stream<RealtimeFrame> events(ApiRequest request, {void Function()? onOpen}) {
    final call = coreCallOf(request);
    final id = _nextStreamId();
    StreamSubscription<rb.ApiStreamItem>? sub;
    late final StreamController<RealtimeFrame> out;
    out = StreamController<RealtimeFrame>(
      onListen: () {
        sub = core
            .apiStream(call, id)
            .listen(
              (item) {
                final failure = item.failure;
                if (item.opened) {
                  onOpen?.call();
                } else if (failure != null) {
                  out.addError(
                    apiExceptionOf(failure, refusalWords: refusalWords),
                  );
                } else {
                  out.add(frameOf(item));
                }
              },
              onError: out.addError,
              onDone: out.close,
            );
      },
      onCancel: () {
        core.apiStreamCancel(id);
        return sub?.cancel();
      },
    );
    return out.stream;
  }

  /// [events], once the server accepted the stream: completes with the
  /// frames that follow, or fails with the [ApiException] it was refused
  /// with (the web's `res.ok` check before reading the body).
  Future<Stream<RealtimeFrame>> open(ApiRequest request) {
    final opened = Completer<Stream<RealtimeFrame>>();
    final relay = StreamController<RealtimeFrame>();
    late final StreamSubscription<RealtimeFrame> sub;
    sub =
        events(
          request,
          onOpen: () {
            if (!opened.isCompleted) opened.complete(relay.stream);
          },
        ).listen(
          relay.add,
          onError: (Object e, StackTrace st) {
            if (opened.isCompleted) {
              relay.addError(e, st);
            } else {
              opened.completeError(e, st);
              unawaited(sub.cancel());
              unawaited(relay.close());
            }
          },
          onDone: () {
            if (!opened.isCompleted) {
              opened.completeError(
                StateError('the stream ended before it opened'),
              );
            }
            unawaited(relay.close());
          },
        );
    relay.onCancel = () => sub.cancel();
    return opened.future;
  }
}

/// [RealtimeGateway] over the core: the branch event stream the web opens
/// (`GET /realtime/stream?branch_id&topics`, `Last-Event-ID` to resume).
class CoreRealtimeGateway implements RealtimeGateway {
  const CoreRealtimeGateway(this.transport);

  final CoreTransport transport;

  @override
  Future<Stream<RealtimeFrame>> connect({
    required String branchId,
    required String topics,
    String? lastEventId,
  }) => transport.open(
    realtimeRequest(
      branchId: branchId,
      topics: topics,
      lastEventId: lastEventId,
    ),
  );
}

// ── pure mapping ─────────────────────────────────────────────────────────

/// The branch event stream's request (`use-branch-realtime.ts`).
ApiRequest realtimeRequest({
  required String branchId,
  required String topics,
  String? lastEventId,
}) => ApiRequest(
  method: 'GET',
  path: '/realtime/stream',
  query: {
    'branch_id': [branchId],
    'topics': [topics],
  },
  headers: {'Last-Event-ID': ?lastEventId},
);

/// The bridge's call for [request]: query pairs in order (a key repeats per
/// value), the headers, and a JSON body, or, with files, a multipart body
/// whose fields are the body map's entries.
rb.ApiCall coreCallOf(ApiRequest request) {
  final query = [
    for (final e in request.query.entries)
      for (final v in e.value) rb.ApiPair(key: e.key, value: v),
  ];
  final headers = [
    for (final e in request.headers.entries)
      rb.ApiPair(key: e.key, value: e.value),
  ];
  final multipart = request.files.isNotEmpty;
  return rb.ApiCall(
    method: request.method.toUpperCase(),
    path: request.path,
    query: query,
    headers: headers,
    jsonBody: multipart || request.body == null
        ? null
        : jsonEncode(request.body, toEncodable: _encodable),
    formFields: multipart ? formFieldsOf(request.body) : const [],
    files: [
      for (final f in request.files)
        rb.ApiFile(
          field: f.field,
          filename: f.filename,
          contentType: f.contentType,
          bytes: f.bytes is Uint8List
              ? f.bytes as Uint8List
              : Uint8List.fromList(f.bytes),
        ),
    ],
  );
}

/// A multipart body's text fields, the way the web's generated client
/// appends them: nulls are left out, a list is one field per element, an
/// object is its JSON, anything else its text.
List<rb.ApiPair> formFieldsOf(Object? body) {
  if (body == null) return const [];
  if (body is! Map) {
    throw ArgumentError.value(body, 'body', 'a multipart body must be a Map');
  }
  String text(Object v) => switch (v) {
    final String s => s,
    final Map<Object?, Object?> m => jsonEncode(m, toEncodable: _encodable),
    final DateTime d => d.toUtc().toIso8601String(),
    _ => v.toString(),
  };
  final out = <rb.ApiPair>[];
  for (final MapEntry(:key, :value) in body.entries) {
    final values = value is List ? value : [value];
    for (final v in values) {
      if (v != null) out.add(rb.ApiPair(key: '$key', value: text(v as Object)));
    }
  }
  return out;
}

Object? _encodable(Object? v) =>
    v is DateTime ? v.toUtc().toIso8601String() : v;

/// The seam's response for a 2xx reply.
ApiResponse apiResponseOf(rb.ApiReply reply) => ApiResponse(
  status: reply.status,
  headers: foldHeaders(reply.headers),
  bodyBytes: reply.body,
);

/// Header pairs as one map: names in lower case, a repeated name's values
/// joined with `, ` (HTTP's own folding).
Map<String, String> foldHeaders(List<rb.ApiPair> headers) {
  final out = <String, String>{};
  for (final h in headers) {
    final name = h.key.toLowerCase();
    final had = out[name];
    out[name] = had == null ? h.value : '$had, ${h.value}';
  }
  return out;
}

/// The seam's exception for a failure. [ApiException.status] is 0 whenever
/// the Madar server did not answer: no network, a portal's 401, and a 403 a
/// firewall sent in its place (never read as "no permission"). The message
/// is the core's, unless [refusalWords] has the web's sentence for the
/// backend's code. [ApiException.details] is the backend's envelope
/// (`error`, `code`, `vars`) when it sent one.
ApiException apiExceptionOf(
  rb.ApiFailure failure, {
  RefusalWords? refusalWords,
}) {
  final reached = switch (failure.kind) {
    rb.ApiFailureKind.offline || rb.ApiFailureKind.blockedUpstream => false,
    _ => failure.status != 0,
  };
  final envelope = envelopeOf(failure.body);
  final code = failure.code;
  var message = failure.message;
  if (reached && code != null && refusalWords != null) {
    final vars = envelope?['vars'];
    final said = refusalWords(
      code,
      vars is Map ? vars.cast<String, Object?>() : const {},
    );
    if (said != null && said.trim().isNotEmpty) message = said;
  }
  return ApiException(
    status: reached ? failure.status : 0,
    code: code,
    message: message,
    details: envelope,
  );
}

/// The backend's `{error, code, vars}` envelope in [body], when it is one.
Map<String, Object?>? envelopeOf(String? body) {
  if (body == null || body.isEmpty) return null;
  try {
    final v = jsonDecode(body);
    return v is Map ? v.cast<String, Object?>() : null;
  } on FormatException {
    return null;
  }
}

/// One stream item as a frame.
RealtimeFrame frameOf(rb.ApiStreamItem item) =>
    RealtimeFrame(event: item.event, data: item.data, id: item.id);
