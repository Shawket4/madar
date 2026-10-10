/// Files in and out: saving and sharing what the dashboard produces (exports,
/// QR codes), picking what a person brings (an import sheet, an image).
/// The web's `src/lib/download.ts` (`downloadBlob`, `downloadUrl`) map onto
/// [FileGateway.saveBytes] and [saveDataUri].
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file the person picked.
class PickedFile {
  const PickedFile({required this.name, required this.bytes, this.mimeType});

  final String name;
  final List<int> bytes;
  final String? mimeType;
}

abstract interface class FileGateway {
  /// Saves [bytes] as [filename] where the person keeps files (a save dialog
  /// or Downloads on desktop, the share sheet's "save" on a phone). Returns
  /// where it went, or null when the person cancelled.
  Future<String?> saveBytes(
    List<int> bytes, {
    required String filename,
    String? mimeType,
  });

  /// Opens the system share sheet with the file.
  Future<void> share(
    List<int> bytes, {
    required String filename,
    String? mimeType,
    String? text,
  });

  /// Asks for one file; null when cancelled. [extensions] without dots.
  Future<PickedFile?> pickFile({List<String>? extensions});

  /// Asks for one image (photos / files); null when cancelled.
  Future<PickedFile?> pickImage();
}

final fileGatewayProvider = Provider<FileGateway>(
  (ref) => throw StateError('fileGatewayProvider must be overridden at boot'),
);

/// MIME types the dashboard writes.
abstract final class MimeTypes {
  static const String xlsx =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const String csv = 'text/csv;charset=utf-8';
  static const String png = 'image/png';
  static const String svg = 'image/svg+xml';
  static const String pdf = 'application/pdf';
}

/// `downloadUrl(href, filename)` for a `data:` URI (a QR code's PNG/SVG):
/// decodes it and saves the bytes. Throws [FormatException] for anything that
/// is not a data URI.
Future<String?> saveDataUri(FileGateway files, String href, String filename) {
  final uri = Uri.parse(href);
  final data = uri.data;
  if (data == null) {
    throw FormatException('not a data: URI', href);
  }
  return files.saveBytes(
    data.contentAsBytes(),
    filename: filename,
    mimeType: data.mimeType,
  );
}

/// `downloadBlob(blob, filename)` for text (a CSV): UTF-8 bytes, saved.
Future<String?> saveText(
  FileGateway files,
  String text,
  String filename, {
  String mimeType = MimeTypes.csv,
}) =>
    files.saveBytes(utf8.encode(text), filename: filename, mimeType: mimeType);
