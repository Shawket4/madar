/// What the generated API classes share: query encoding, body decoding and the
/// mapping of decode failures to [ApiException]s carrying the HTTP status.
library;

import 'dart:convert';

import 'codec.dart';
import 'transport.dart';

/// One query value as the backend reads it (`date-time` in UTC ISO-8601).
String queryValue(Object value) => switch (value) {
  DateTime() => encDateTime(value),
  _ => value.toString(),
};

/// A path segment, percent-encoded.
String pathSegment(Object value) => Uri.encodeComponent(queryValue(value));

/// The JSON body of [response], or null when it is empty.
Object? responseJson(ApiResponse response, String operation) {
  if (response.bodyBytes.isEmpty) return null;
  try {
    return jsonDecode(utf8.decode(response.bodyBytes));
  } on FormatException catch (e) {
    throw ApiException(
      status: response.status,
      code: 'decode',
      message:
          'The server answered $operation with something that is not JSON.',
      details: {'operation': operation, 'error': e.message},
    );
  }
}

/// Decodes [response] with [decode]; any decode failure becomes an
/// [ApiException] with code `decode` and the response's status.
T decodeResponse<T>(
  ApiResponse response,
  String operation,
  T Function(Object? json) decode,
) {
  final json = responseJson(response, operation);
  try {
    return decode(json);
  } on ApiException catch (e) {
    if (e.code != 'decode') rethrow;
    throw ApiException(
      status: response.status,
      code: 'decode',
      message: e.message,
      details: {
        'operation': operation,
        if (e.details is Map) ...(e.details! as Map).cast<String, Object?>(),
      },
    );
  } on TypeError catch (e) {
    throw ApiException(
      status: response.status,
      code: 'decode',
      message: 'Unexpected server data for $operation.',
      details: {'operation': operation, 'error': e.toString()},
    );
  }
}

/// The text body of [response] (UTF-8).
String responseText(ApiResponse response) =>
    utf8.decode(response.bodyBytes, allowMalformed: true);
