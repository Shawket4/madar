/// An in-memory [ApiTransport] that behaves like the Madar backend: routes by
/// `(method, path template)`, refuses in the backend's error envelope, and
/// records every call for tests.
library;

import 'dart:async';
import 'dart:convert';

import '../generated/mock_capabilities.dart';
import '../generated/operations.dart';
import '../transport.dart';
import 'mock_clock.dart';
import 'personas.dart';

typedef MockHandler = FutureOr<MockResponse> Function(MockRequest req);
typedef MockStreamHandler = Stream<String> Function(MockRequest req);

/// A refusal thrown from inside a handler (`req.requireCap`, `req.notFound`…);
/// the server answers it as [response].
class MockHttpError implements Exception {
  const MockHttpError(this.response);

  final MockResponse response;

  @override
  String toString() => 'MockHttpError(${response.status} ${response.text})';
}

/// What a handler answers.
class MockResponse {
  const MockResponse(
    this.status, {
    this.bodyBytes = const [],
    this.headers = const {},
  });

  /// A JSON answer. [body] may be JSON values or generated models (anything
  /// with `toJson()`), nested freely.
  factory MockResponse.json(int status, Object? body) => MockResponse(
    status,
    bodyBytes: utf8.encode(jsonEncode(body)),
    headers: const {'content-type': 'application/json'},
  );

  factory MockResponse.ok(Object? body) => MockResponse.json(200, body);

  factory MockResponse.created(Object? body) => MockResponse.json(201, body);

  /// No body (204 by default).
  factory MockResponse.empty([int status = 204]) => MockResponse(status);

  factory MockResponse.bytes(
    List<int> bytes, {
    int status = 200,
    String contentType = 'application/octet-stream',
  }) => MockResponse(
    status,
    bodyBytes: bytes,
    headers: {'content-type': contentType},
  );

  factory MockResponse.text(
    String text, {
    int status = 200,
    String contentType = 'text/plain; charset=utf-8',
  }) => MockResponse(
    status,
    bodyBytes: utf8.encode(text),
    headers: {'content-type': contentType},
  );

  /// The backend's error envelope (`errors.rs` `ErrorBody`):
  /// `{"error": …, "code"?: …, "till"?: …, "retry_after_seconds"?: …, "vars"?: …}`.
  factory MockResponse.error(
    int status,
    String error, {
    String? code,
    Object? vars,
    Object? till,
    int? retryAfterSeconds,
  }) => MockResponse.json(status, {
    'error': error,
    'code': ?code,
    'till': ?till,
    'retry_after_seconds': ?retryAfterSeconds,
    'vars': ?vars,
  });

  /// `AppError::Unauthorized` → 401 `Unauthorized: …`.
  factory MockResponse.unauthorized([String reason = 'Invalid credentials']) =>
      MockResponse.error(401, 'Unauthorized: $reason');

  /// `AppError::Forbidden` → 403 `Forbidden: …`.
  factory MockResponse.forbidden(String reason) =>
      MockResponse.error(403, 'Forbidden: $reason');

  /// The backend's capability refusal (`authz::require::denied`).
  factory MockResponse.denied(String capability) {
    final meta = mockCapabilities.where((c) => c.key == capability);
    final label = meta.isEmpty ? capability : meta.first.en;
    return MockResponse.forbidden(
      "You don't have permission to do this: $label ($capability)",
    );
  }

  /// `AppError::NotFound` → 404 `Not found: …`.
  factory MockResponse.notFound([String what = 'Resource not found']) =>
      MockResponse.error(404, 'Not found: $what');

  /// `AppError::BadRequest` → 400 `Bad request: …`.
  factory MockResponse.badRequest(String reason, {String? code}) => code == null
      ? MockResponse.error(400, 'Bad request: $reason')
      : MockResponse.error(400, reason, code: code);

  /// `AppError::Conflict` → 409 `Conflict: …`; a coded refusal keeps its words.
  factory MockResponse.conflict(String reason, {String? code}) => code == null
      ? MockResponse.error(409, 'Conflict: $reason')
      : MockResponse.error(409, reason, code: code);

  /// A coded 422 (`AppError::Coded`), the backend's validation refusal shape.
  factory MockResponse.unprocessable(
    String reason, {
    String? code,
    Object? vars,
  }) => MockResponse.error(422, reason, code: code, vars: vars);

  final int status;
  final List<int> bodyBytes;
  final Map<String, String> headers;

  bool get ok => status >= 200 && status < 300;

  String get text => utf8.decode(bodyBytes, allowMalformed: true);

  /// The decoded JSON body (null when empty).
  Object? get json => bodyBytes.isEmpty ? null : jsonDecode(text);

  ApiResponse toApiResponse() =>
      ApiResponse(status: status, headers: headers, bodyBytes: bodyBytes);
}

/// One request as a handler sees it: the wire JSON (the body went through
/// `jsonEncode`/`jsonDecode`, exactly as on the network), path params, query.
class MockRequest {
  MockRequest({
    required this.server,
    required this.method,
    required this.path,
    required this.template,
    required this.pathParams,
    required this.queryAll,
    required this.body,
    required this.files,
    required this.headers,
    required this.persona,
  });

  final MockServer server;
  final String method;
  final String path;

  /// The matched template (`/orders/{id}/void`).
  final String template;
  final Map<String, String> pathParams;
  final Map<String, List<String>> queryAll;
  final Object? body;
  final List<ApiFilePart> files;
  final Map<String, String> headers;
  final Persona persona;

  MockClock get clock => server.clock;

  DateTime get now => server.clock.now;

  /// A path parameter (throws if the template has none by that name).
  String param(String name) {
    final v = pathParams[name];
    if (v == null) throw ArgumentError('No path param {$name} in $template');
    return v;
  }

  /// First value of each query key.
  Map<String, String> get query => {
    for (final e in queryAll.entries)
      if (e.value.isNotEmpty) e.key: e.value.first,
  };

  String? q(String key) {
    final v = queryAll[key];
    return v == null || v.isEmpty ? null : v.first;
  }

  List<String> qAll(String key) => queryAll[key] ?? const [];

  int? qInt(String key) {
    final v = q(key);
    if (v == null) return null;
    return int.tryParse(v) ??
        (throw MockHttpError(
          MockResponse.badRequest(
            'Query deserialize error: invalid digit found in string',
          ),
        ));
  }

  bool? qBool(String key) {
    final v = q(key);
    if (v == null) return null;
    return v == 'true' || v == '1';
  }

  DateTime? qDateTime(String key) {
    final v = q(key);
    if (v == null) return null;
    return DateTime.tryParse(v)?.toUtc() ??
        (throw MockHttpError(
          MockResponse.badRequest(
            'Query deserialize error: input contains invalid characters',
          ),
        ));
  }

  /// The JSON body as an object (empty when there is none). Multipart form
  /// fields arrive here too.
  Map<String, Object?> get json {
    final b = body;
    if (b is Map<String, Object?>) return b;
    if (b is Map) return b.map((k, v) => MapEntry(k.toString(), v));
    return const {};
  }

  /// The body decoded with a generated model's `fromJson`; a body that does not
  /// fit answers 400 like actix's JSON extractor.
  T bodyAs<T>(T Function(Map<String, Object?> json) fromJson) {
    try {
      return fromJson(json);
    } on ApiException catch (e) {
      throw MockHttpError(
        MockResponse.badRequest('Json deserialize error: ${e.message}'),
      );
    }
  }

  ApiFilePart? file(String field) {
    for (final f in files) {
      if (f.field == field) return f;
    }
    return null;
  }

  /// The org this request acts in: the `X-Org-Id` header (honoured for a
  /// platform admin, as the backend does) or the persona's org.
  String? get orgId {
    final pinned = headers['X-Org-Id'] ?? headers['x-org-id'];
    if (persona.isPlatform) return pinned ?? server.platformOrgId;
    return persona.orgId;
  }

  /// The branch header (`X-Branch-Id`), when the client sent one.
  String? get branchHeader => headers['X-Branch-Id'] ?? headers['x-branch-id'];

  /// 403 in the backend's envelope unless the persona holds [capability]
  /// (at [branchId], when given and the persona is branch-scoped).
  void requireCap(String capability, {String? branchId}) {
    if (!persona.can(capability)) {
      throw MockHttpError(MockResponse.denied(capability));
    }
    if (branchId != null) requireBranch(branchId);
  }

  /// 403 unless the persona holds at least one of [capabilities].
  void requireAnyCap(List<String> capabilities, {String? branchId}) {
    if (!capabilities.any(persona.can)) {
      throw MockHttpError(MockResponse.denied(capabilities.first));
    }
    if (branchId != null) requireBranch(branchId);
  }

  /// 403 `Not assigned to this branch` for a branch-scoped persona elsewhere.
  void requireBranch(String branchId) {
    if (!persona.seesBranch(branchId)) {
      throw MockHttpError(
        MockResponse.forbidden('Not assigned to this branch'),
      );
    }
  }

  /// 403 `Access to this org is not allowed` unless [orgId] is the persona's
  /// org (a platform admin may act in any org), as `guards::require_same_org`.
  void requireSameOrg(String? orgId) {
    if (persona.isPlatform) return;
    if (orgId == null || orgId != persona.orgId) {
      throw MockHttpError(
        MockResponse.forbidden('Access to this org is not allowed'),
      );
    }
  }

  /// 403 `Super admin access required` unless the persona is a platform admin.
  void requirePlatform() {
    if (!persona.isPlatform) {
      throw MockHttpError(
        MockResponse.forbidden('Super admin access required'),
      );
    }
  }

  Never notFound([String what = 'Resource not found']) =>
      throw MockHttpError(MockResponse.notFound(what));

  Never badRequest(String reason, {String? code}) =>
      throw MockHttpError(MockResponse.badRequest(reason, code: code));

  Never conflict(String reason, {String? code}) =>
      throw MockHttpError(MockResponse.conflict(reason, code: code));

  Never unprocessable(String reason, {String? code, Object? vars}) =>
      throw MockHttpError(
        MockResponse.unprocessable(reason, code: code, vars: vars),
      );

  Never fail(MockResponse response) => throw MockHttpError(response);
}

/// One recorded call.
class MockCall {
  MockCall({
    required this.method,
    required this.path,
    required this.query,
    required this.body,
    required this.files,
    required this.headers,
    required this.persona,
    required this.at,
    this.template,
    this.operationId,
  });

  final String method;
  final String path;
  final Map<String, List<String>> query;
  final Object? body;
  final List<ApiFilePart> files;
  final Map<String, String> headers;
  final Persona persona;
  final DateTime at;

  /// The matched template, null when unmatched.
  final String? template;

  /// The spec operation the template belongs to, when it is one.
  final String? operationId;

  int? status;

  bool get stream => _stream;
  bool _stream = false;

  @override
  String toString() =>
      '$method $path${query.isEmpty ? '' : '?${Uri(queryParameters: query).query}'}'
      '${status == null ? '' : ' → $status'}';
}

/// Holds a route's answers until [release]: lets a test see a loading state.
class MockGate {
  final Completer<void> _open = Completer<void>();

  bool get released => _open.isCompleted;

  void release() {
    if (!_open.isCompleted) _open.complete();
  }

  Future<void> get future => _open.future;
}

class _Route {
  _Route(this.method, this.template, this.handler, this.stream)
    : segments = template
          .split('/')
          .where((s) => s.isNotEmpty)
          .map(_Segment.new)
          .toList();

  final String method;
  final String template;
  final MockHandler? handler;
  final MockStreamHandler? stream;
  final List<_Segment> segments;

  /// Literal segments win over parameters, left to right (`/orders/export`
  /// beats `/orders/{id}`).
  List<int> get score => [for (final s in segments) s.literal ? 1 : 0];

  Map<String, String>? match(List<String> parts) {
    if (parts.length != segments.length) return null;
    final params = <String, String>{};
    for (var i = 0; i < parts.length; i++) {
      if (!segments[i].match(parts[i], params)) return null;
    }
    return params;
  }
}

class _Segment {
  _Segment(this.raw) {
    final names = <String>[];
    final pattern = raw.replaceAllMapped(RegExp(r'\{([^}]+)\}|([^{]+)'), (m) {
      if (m.group(1) != null) {
        names.add(m.group(1)!);
        return '([^/]+?)';
      }
      return RegExp.escape(m.group(2)!);
    });
    this.names = names;
    regex = RegExp('^$pattern\$');
  }

  final String raw;
  late final List<String> names;
  late final RegExp regex;

  bool get literal => names.isEmpty;

  bool match(String part, Map<String, String> params) {
    if (literal) return part == raw;
    final m = regex.firstMatch(part);
    if (m == null) return false;
    for (var i = 0; i < names.length; i++) {
      params[names[i]] = Uri.decodeComponent(m.group(i + 1)!);
    }
    return true;
  }
}

int _compareScore(List<int> a, List<int> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

/// The mock backend. Register handlers with [on]/[onStream] (a later
/// registration of the same route replaces the earlier one, so an area can
/// override a core handler); unmatched routes answer 501 and are recorded in
/// [unmatched].
class MockServer implements ApiTransport {
  MockServer({
    this.persona = Persona.owner,
    MockClock? clock,
    this.latency = Duration.zero,
  }) : clock = clock ?? MockClock();

  final MockClock clock;

  /// Added before every answer (zero by default).
  Duration latency;

  /// Who is signed in. Sign-in (`POST /auth/login`) switches it.
  Persona persona;

  /// The org a platform admin has picked when no `X-Org-Id` is sent.
  String? platformOrgId;

  final List<MockCall> calls = [];
  final List<MockCall> unmatched = [];

  /// Handler crashes (not refusals): a test harness should fail on these.
  final List<Object> handlerErrors = [];

  final List<_Route> _routes = [];
  final Map<String, _Override> _overrides = {};
  final Map<String, StreamController<String>> _channels = {};

  static final Map<String, ApiOperation> _opsByRoute = {
    for (final op in apiOperations) '${op.method} ${op.path}': op,
  };

  /// Registers [handler] for `method template` (e.g. `GET`, `/orders/{id}`).
  void on(String method, String template, MockHandler handler) =>
      _add(_Route(method.toUpperCase(), template, handler, null));

  /// Registers a server-sent-events route: one string per `data:` frame.
  void onStream(String method, String template, MockStreamHandler handler) =>
      _add(_Route(method.toUpperCase(), template, null, handler));

  /// Registers [handler] for a spec operation by its operationId.
  void onOperation(String operationId, MockHandler handler) {
    final op = apiOperations.firstWhere(
      (o) => o.id == operationId,
      orElse: () => throw ArgumentError('Unknown operationId $operationId'),
    );
    on(op.method, op.path, handler);
  }

  void _add(_Route route) {
    _routes.removeWhere(
      (r) => r.method == route.method && r.template == route.template,
    );
    _routes.add(route);
  }

  /// Whether a handler is registered for exactly `method template`.
  bool handles(String method, String template) => _routes.any(
    (r) => r.method == method.toUpperCase() && r.template == template,
  );

  /// Every registered `METHOD template`.
  List<String> get routes => [
    for (final r in _routes) '${r.method} ${r.template}',
  ];

  /// The next [times] calls to `method template` answer [response] instead of
  /// the handler (null [times] = until [clearFailures]).
  void fail(
    String method,
    String template,
    MockResponse response, {
    int? times = 1,
  }) {
    _overrides['${method.toUpperCase()} $template'] = _Override(
      response: response,
      times: times,
    );
  }

  /// Holds every call to `method template` until the returned gate is released.
  MockGate hold(String method, String template) {
    final gate = MockGate();
    _overrides['${method.toUpperCase()} $template'] = _Override(gate: gate);
    return gate;
  }

  void clearFailures() => _overrides.clear();

  /// Pushes a data frame to every open stream on [channel] (see [channel]).
  void publish(String channel, String data) => _channels[channel]?.add(data);

  /// A broadcast stream for stream handlers: `onStream(..., (req) => server.channel('realtime'))`.
  Stream<String> channel(String name) =>
      (_channels[name] ??= StreamController<String>.broadcast()).stream;

  /// Closes every channel (end of a test).
  Future<void> close() async {
    for (final c in _channels.values) {
      await c.close();
    }
    _channels.clear();
  }

  /// The calls whose template is [template] (and [method], when given).
  List<MockCall> callsTo(String template, {String? method}) => [
    for (final c in calls)
      if (c.template == template &&
          (method == null || c.method == method.toUpperCase()))
        c,
  ];

  ({_Route route, Map<String, String> params})? _find(
    String method,
    String path,
  ) {
    final parts = path
        .split('?')
        .first
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    ({_Route route, Map<String, String> params})? best;
    for (final r in _routes) {
      if (r.method != method) continue;
      final params = r.match(parts);
      if (params == null) continue;
      if (best == null || _compareScore(r.score, best.route.score) > 0) {
        best = (route: r, params: params);
      }
    }
    return best;
  }

  MockCall _record(
    ApiRequest request,
    ({_Route route, Map<String, String> params})? hit,
  ) {
    final call = MockCall(
      method: request.method.toUpperCase(),
      path: request.path,
      query: request.query,
      body: _wire(request.body),
      files: request.files,
      headers: request.headers,
      persona: persona,
      at: clock.now,
      template: hit?.route.template,
      operationId: hit == null
          ? null
          : _opsByRoute['${hit.route.method} ${hit.route.template}']?.id,
    );
    calls.add(call);
    return call;
  }

  static Object? _wire(Object? body) =>
      body == null ? null : jsonDecode(jsonEncode(body));

  MockRequest _request(
    ApiRequest request,
    MockCall call,
    Map<String, String> params,
  ) => MockRequest(
    server: this,
    method: call.method,
    path: request.path,
    template: call.template!,
    pathParams: params,
    queryAll: request.query,
    body: call.body,
    files: request.files,
    headers: request.headers,
    persona: persona,
  );

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    final method = request.method.toUpperCase();
    final hit = _find(method, request.path);
    final call = _record(request, hit);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (hit == null || hit.route.handler == null) {
      call.status = 501;
      unmatched.add(call);
      throw ApiException(
        status: 501,
        code: 'MOCK_UNMATCHED',
        message: 'No mock handler for $method ${request.path}',
        details: {'method': method, 'path': request.path},
      );
    }
    final key = '$method ${hit.route.template}';
    final ov = _overrides[key];
    MockResponse response;
    final gate = ov?.gate;
    if (gate != null) await gate.future;
    final failure = ov?.response;
    if (ov != null && failure != null) {
      response = failure;
      final left = ov.times;
      if (left != null) {
        ov.times = left - 1;
        if (left - 1 <= 0) _overrides.remove(key);
      }
    } else {
      response = await _run(
        hit.route.handler!,
        _request(request, call, hit.params),
      );
    }
    call.status = response.status;
    if (!response.ok) throw toApiException(response);
    return response.toApiResponse();
  }

  Future<MockResponse> _run(MockHandler handler, MockRequest req) async {
    try {
      return await handler(req);
    } on MockHttpError catch (e) {
      return e.response;
    } on ApiException catch (e) {
      // A handler that decoded a bad body with a model's fromJson.
      if (e.code == 'decode') {
        return MockResponse.badRequest('Json deserialize error: ${e.message}');
      }
      rethrow;
    } catch (e, st) {
      handlerErrors.add(e);
      return MockResponse.error(
        500,
        'Internal error',
        code: 'MOCK_HANDLER_CRASH',
        vars: {
          'error': e.toString(),
          'stack': st.toString().split('\n').take(8).join('\n'),
        },
      );
    }
  }

  @override
  Stream<String> stream(ApiRequest request) {
    final method = request.method.toUpperCase();
    final hit = _find(method, request.path);
    final call = _record(request, hit);
    call._stream = true;
    if (hit == null || hit.route.stream == null) {
      call.status = 501;
      unmatched.add(call);
      return Stream<String>.error(
        ApiException(
          status: 501,
          code: 'MOCK_UNMATCHED',
          message: 'No mock stream handler for $method ${request.path}',
        ),
      );
    }
    call.status = 200;
    try {
      return hit.route.stream!(_request(request, call, hit.params));
    } on MockHttpError catch (e) {
      call.status = e.response.status;
      return Stream<String>.error(toApiException(e.response));
    }
  }

  /// The [ApiException] a non-2xx [response] becomes: the envelope's `error`
  /// as the message, its `code`, and the whole envelope as `details`.
  static ApiException toApiException(MockResponse response) {
    Object? json;
    try {
      json = response.json;
    } on FormatException {
      json = null;
    }
    if (json is Map && json['error'] is String) {
      return ApiException(
        status: response.status,
        code: json['code'] as String?,
        message: json['error']! as String,
        details: json,
      );
    }
    return ApiException(
      status: response.status,
      message: 'HTTP ${response.status}',
    );
  }
}

class _Override {
  _Override({this.response, this.times, this.gate});

  final MockResponse? response;
  int? times;
  final MockGate? gate;
}
