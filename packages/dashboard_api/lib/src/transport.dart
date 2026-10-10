/// The one seam every API call goes through. Real mode forwards to the Rust
/// core over the dashboard bridge (token, org/branch headers, refresh and the
/// EN/AR refusal text live there); tests and mock mode use `MockServer`.
library;

/// A request, with path parameters already substituted into [path].
class ApiRequest {
  const ApiRequest({
    required this.method,
    required this.path,
    this.query = const {},
    this.body,
    this.files = const [],
    this.headers = const {},
  });

  /// `GET`, `POST`, `PUT`, `PATCH` or `DELETE`.
  final String method;

  /// e.g. `/orders/3f0c…/void`, always starting with `/`.
  final String path;

  /// Repeated keys allowed (`status=open&status=paid`).
  final Map<String, List<String>> query;

  /// A JSON-encodable value (Map/List/String/num/bool) or null.
  final Object? body;

  /// Multipart file parts; when non-empty the request is multipart and the
  /// JSON [body] (a Map) is sent as plain form fields.
  final List<ApiFilePart> files;

  final Map<String, String> headers;
}

/// One file in a multipart request.
class ApiFilePart {
  const ApiFilePart({
    required this.field,
    required this.filename,
    required this.bytes,
    this.contentType,
  });

  final String field;
  final String filename;
  final List<int> bytes;
  final String? contentType;
}

class ApiResponse {
  const ApiResponse({
    required this.status,
    this.headers = const {},
    this.bodyBytes = const [],
  });

  final int status;
  final Map<String, String> headers;
  final List<int> bodyBytes;

  bool get ok => status >= 200 && status < 300;
}

/// A refused or failed call. [message] is already human and in the active
/// language (the core words it in real mode; the mock words it in tests).
class ApiException implements Exception {
  const ApiException({
    required this.status,
    required this.message,
    this.code,
    this.details,
  });

  final int status;
  final String? code;
  final String message;
  final Object? details;

  @override
  String toString() =>
      'ApiException($status${code == null ? '' : ' $code'}): $message';
}

abstract interface class ApiTransport {
  /// Sends [request]. Throws [ApiException] for a non-2xx answer or when the
  /// server cannot be reached; returns the raw response otherwise.
  Future<ApiResponse> send(ApiRequest request);

  /// Server-sent events: one item per `data:` frame, until the server closes.
  Stream<String> stream(ApiRequest request);
}
