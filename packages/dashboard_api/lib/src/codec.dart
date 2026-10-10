/// JSON decode/encode helpers the generated models call. Every failure is an
/// [ApiException] with code `decode`, a human message naming the field, and
/// the offending value in `details`.
library;

import 'dart:convert';

import 'transport.dart';

/// Throws the decode error for [path] (e.g. `Order.total`).
Never decodeError(String path, String expected, Object? value) {
  final shown = value is String
      ? '"${value.length > 60 ? '${value.substring(0, 60)}…' : value}"'
      : value.runtimeType.toString();
  throw ApiException(
    status: 0,
    code: 'decode',
    message: 'Unexpected server data at $path: expected $expected, got $shown.',
    details: {'path': path, 'expected': expected, 'value': value},
  );
}

String decString(Object? v, String path) =>
    v is String ? v : decodeError(path, 'a string', v);

String? decStringN(Object? v, String path) =>
    v == null ? null : decString(v, path);

int decInt(Object? v, String path) {
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt();
  return decodeError(path, 'an integer', v);
}

int? decIntN(Object? v, String path) => v == null ? null : decInt(v, path);

double decDouble(Object? v, String path) {
  if (v is num) return v.toDouble();
  return decodeError(path, 'a number', v);
}

double? decDoubleN(Object? v, String path) =>
    v == null ? null : decDouble(v, path);

bool decBool(Object? v, String path) =>
    v is bool ? v : decodeError(path, 'true or false', v);

bool? decBoolN(Object? v, String path) => v == null ? null : decBool(v, path);

/// `date-time` strings, always returned in UTC.
DateTime decDateTime(Object? v, String path) {
  if (v is DateTime) return v.toUtc();
  if (v is String) {
    final parsed = DateTime.tryParse(v);
    if (parsed != null) return parsed.toUtc();
  }
  return decodeError(path, 'a date-time', v);
}

DateTime? decDateTimeN(Object? v, String path) =>
    v == null ? null : decDateTime(v, path);

/// `binary`: a byte list, or base64 text.
List<int> decBytes(Object? v, String path) {
  if (v is List<int>) return v;
  if (v is List && v.every((e) => e is int)) return v.cast<int>();
  if (v is String) {
    try {
      return base64Decode(v);
    } on FormatException {
      return decodeError(path, 'base64 bytes', v);
    }
  }
  return decodeError(path, 'bytes', v);
}

List<int>? decBytesN(Object? v, String path) =>
    v == null ? null : decBytes(v, path);

/// A multipart file field: an [ApiFilePart] or `{filename, bytes, content_type}`.
ApiFilePart decFile(Object? v, String path, String field) {
  if (v is ApiFilePart) return filePartAs(v, field);
  if (v is Map) {
    return ApiFilePart(
      field: field,
      filename: decString(v['filename'], '$path.filename'),
      bytes: decBytes(v['bytes'], '$path.bytes'),
      contentType: decStringN(v['content_type'], '$path.content_type'),
    );
  }
  return decodeError(path, 'a file', v);
}

ApiFilePart? decFileN(Object? v, String path, String field) =>
    v == null ? null : decFile(v, path, field);

/// [part] sent as multipart field [field].
ApiFilePart filePartAs(ApiFilePart part, String field) => part.field == field
    ? part
    : ApiFilePart(
        field: field,
        filename: part.filename,
        bytes: part.bytes,
        contentType: part.contentType,
      );

/// A free-form JSON object.
Map<String, Object?> decJsonMap(Object? v, String path) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.map((k, e) => MapEntry(k.toString(), e));
  return decodeError(path, 'an object', v);
}

Map<String, Object?>? decJsonMapN(Object? v, String path) =>
    v == null ? null : decJsonMap(v, path);

T decObject<T>(
  Object? v,
  String path,
  T Function(Map<String, Object?> json) fromJson,
) => fromJson(decJsonMap(v, path));

T? decObjectN<T>(
  Object? v,
  String path,
  T Function(Map<String, Object?> json) fromJson,
) => v == null ? null : decObject(v, path, fromJson);

T decEnum<T>(Object? v, String path, T Function(String value) fromJson) =>
    fromJson(decString(v, path));

T? decEnumN<T>(Object? v, String path, T Function(String value) fromJson) =>
    v == null ? null : decEnum(v, path, fromJson);

/// A required list; a missing one reads as empty (serde often skips empty
/// lists even when the schema marks them required).
List<T> decList<T>(Object? v, String path, T Function(Object? e) item) {
  if (v == null) return List<T>.empty();
  if (v is List) return List<T>.unmodifiable(v.map(item));
  return decodeError(path, 'a list', v);
}

List<T>? decListN<T>(Object? v, String path, T Function(Object? e) item) =>
    v == null ? null : decList(v, path, item);

/// A required map; a missing one reads as empty.
Map<String, T> decMap<T>(Object? v, String path, T Function(Object? e) item) {
  if (v == null) return Map<String, T>.unmodifiable(const <String, Never>{});
  if (v is Map) {
    return Map<String, T>.unmodifiable(
      v.map((k, e) => MapEntry(k.toString(), item(e))),
    );
  }
  return decodeError(path, 'an object', v);
}

Map<String, T>? decMapN<T>(
  Object? v,
  String path,
  T Function(Object? e) item,
) => v == null ? null : decMap(v, path, item);

String encDateTime(DateTime v) => v.toUtc().toIso8601String();

String? encDateTimeN(DateTime? v) => v?.toUtc().toIso8601String();
