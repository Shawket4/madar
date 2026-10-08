/// Mock implementations of dashboard_core's gateways, for tests and mock mode.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, ApiRequest, ApiResponse, ApiTransport;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/src/data/core_api.dart';
import 'package:dashboard_core/src/data/models.dart';
import 'package:dashboard_core/src/gateways/export.dart';
import 'package:dashboard_core/src/gateways/files.dart';
import 'package:dashboard_core/src/gateways/preferences.dart';
import 'package:dashboard_core/src/gateways/realtime.dart';
import 'package:dashboard_core/src/session/session.dart';

// ── Preferences ──────────────────────────────────────────────────────────

/// In-memory preferences.
class MemoryPreferences implements PreferencesGateway {
  MemoryPreferences([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  /// Every write, in order (`key`, value or null).
  final List<(String, String?)> writes = [];

  @override
  String? getString(String key) => values[key];

  @override
  Future<void> setString(String key, String? value) async {
    writes.add((key, value));
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

// ── Session ──────────────────────────────────────────────────────────────

/// A [SessionGateway] over the [MockServer]'s auth endpoints and personas.
///
/// Requests should go through [transport] (not the server directly): like
/// the core in real mode, it adds the bearer token and the `X-Org-Id` /
/// `X-Branch-Id` headers [applyScope] set, so the mock sees the scope the
/// way the backend does.
class MockSessionGateway implements SessionGateway {
  MockSessionGateway(this.server, {Persona? signedInAs})
    : _restoreAs = signedInAs;

  final MockServer server;
  Persona? _restoreAs;
  String? _token;

  /// The org and branch the next requests carry.
  String? orgId;
  String? branchId;

  /// Every [applyScope], in order.
  final List<({String? orgId, String? branchId})> scopeCalls = [];
  int signOutCount = 0;

  /// The transport the app should use (headers added).
  late final ApiTransport transport = ScopedTransport(server, headers: headers);

  bool get signedIn => _token != null;

  /// What the next request carries.
  Map<String, String> headers() => {
    if (_token != null) 'Authorization': 'Bearer $_token',
    'X-Org-Id': ?orgId,
    'X-Branch-Id': ?branchId,
  };

  CoreApi get _api => CoreApi(transport);

  @override
  Future<SessionInfo?> restore() async {
    final p = _restoreAs;
    if (p == null) return null;
    server.persona = p;
    _token = p.token;
    return _api.me(token: p.token);
  }

  @override
  Future<SessionInfo> signIn({
    required String email,
    required String password,
    String? orgId,
  }) async {
    final info = await _api.login(
      email: email,
      password: password,
      orgId: orgId,
    );
    _token = info.token;
    _restoreAs = Persona.byEmail(email);
    return info;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    _token = null;
    _restoreAs = null;
    orgId = null;
    branchId = null;
    server.platformOrgId = null;
  }

  @override
  Future<void> applyScope({
    required String? orgId,
    required String? branchId,
  }) async {
    this.orgId = orgId;
    this.branchId = branchId;
    scopeCalls.add((orgId: orgId, branchId: branchId));
    if (server.persona.isPlatform) server.platformOrgId = orgId;
  }
}

/// Adds [headers] to every request on [inner] (what the core does in real
/// mode).
class ScopedTransport implements ApiTransport {
  ScopedTransport(this.inner, {required this.headers});

  final ApiTransport inner;
  final Map<String, String> Function() headers;

  ApiRequest _with(ApiRequest r) => ApiRequest(
    method: r.method,
    path: r.path,
    query: r.query,
    body: r.body,
    files: r.files,
    headers: {...headers(), ...r.headers},
  );

  @override
  Future<ApiResponse> send(ApiRequest request) => inner.send(_with(request));

  @override
  Stream<String> stream(ApiRequest request) => inner.stream(_with(request));
}

// ── Files ────────────────────────────────────────────────────────────────

/// One saved or shared file.
class RecordedFile {
  const RecordedFile({
    required this.filename,
    required this.bytes,
    this.mimeType,
    this.text,
  });

  final String filename;
  final List<int> bytes;
  final String? mimeType;

  /// The share text, for a shared file.
  final String? text;

  String get asString => utf8.decode(bytes, allowMalformed: true);
}

/// Records what was saved and shared; answers picks from queues.
class RecordingFileGateway implements FileGateway {
  final List<RecordedFile> saved = [];
  final List<RecordedFile> shared = [];

  /// The next [pickFile] answers (null = cancelled); empty = cancelled.
  final List<PickedFile?> fileQueue = [];
  final List<PickedFile?> imageQueue = [];

  /// Make the next save cancel (returns null).
  bool cancelNextSave = false;

  @override
  Future<String?> saveBytes(
    List<int> bytes, {
    required String filename,
    String? mimeType,
  }) async {
    if (cancelNextSave) {
      cancelNextSave = false;
      return null;
    }
    saved.add(
      RecordedFile(filename: filename, bytes: bytes, mimeType: mimeType),
    );
    return '/mock/downloads/$filename';
  }

  @override
  Future<void> share(
    List<int> bytes, {
    required String filename,
    String? mimeType,
    String? text,
  }) async {
    shared.add(
      RecordedFile(
        filename: filename,
        bytes: bytes,
        mimeType: mimeType,
        text: text,
      ),
    );
  }

  @override
  Future<PickedFile?> pickFile({List<String>? extensions}) async =>
      fileQueue.isEmpty ? null : fileQueue.removeAt(0);

  @override
  Future<PickedFile?> pickImage() async =>
      imageQueue.isEmpty ? null : imageQueue.removeAt(0);
}

// ── Exports ──────────────────────────────────────────────────────────────

/// Records every workbook asked for; "writes" it as its JSON spec; answers
/// imports from [readQueue].
class RecordingExportGateway implements ExportGateway {
  final List<WorkbookSpec> built = [];
  final List<List<SheetData>> readQueue = [];

  /// Throw this from the next [buildXlsx] (an export failure).
  Object? failNext;

  @override
  Future<List<int>> buildXlsx(WorkbookSpec spec) async {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
    built.add(spec);
    return utf8.encode(json.encode(spec.toJson()));
  }

  @override
  Future<List<SheetData>> readXlsx(List<int> bytes) async =>
      readQueue.isEmpty ? const [] : readQueue.removeAt(0);
}

// ── Realtime ─────────────────────────────────────────────────────────────

/// One connection a [MockRealtimeGateway] handed out.
class MockRealtimeConnection {
  MockRealtimeConnection(this.branchId, this.topics, this.lastEventId);

  final String branchId;
  final String topics;
  final String? lastEventId;
  final StreamController<RealtimeFrame> _c = StreamController<RealtimeFrame>();

  bool get isOpen => !_c.isClosed;

  /// Whether the client is still listening.
  bool get hasListener => _c.hasListener;

  void emit(String event, {String data = '', String? id}) =>
      _c.add(RealtimeFrame(event: event, data: data, id: id));

  /// The server ends the stream.
  Future<void> close() => _c.close();

  /// The connection drops.
  void drop([Object error = 'connection lost']) => _c.addError(error);
}

/// A realtime gateway a test drives: every [connect] is recorded; the next
/// [refuse] connects fail.
class MockRealtimeGateway implements RealtimeGateway {
  final List<MockRealtimeConnection> connections = [];
  int _refuse = 0;

  /// The newest connection (null before the first).
  MockRealtimeConnection? get current =>
      connections.isEmpty ? null : connections.last;

  /// The next [times] connects are refused.
  void refuse([int times = 1]) => _refuse += times;

  @override
  Future<Stream<RealtimeFrame>> connect({
    required String branchId,
    required String topics,
    String? lastEventId,
  }) async {
    if (_refuse > 0) {
      _refuse--;
      throw const ApiException(status: 403, message: 'stream refused');
    }
    final c = MockRealtimeConnection(branchId, topics, lastEventId);
    connections.add(c);
    return c._c.stream;
  }
}
