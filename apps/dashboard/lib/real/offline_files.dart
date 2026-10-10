/// Real mode's [OfflineBlobs]: one file per saved answer in a folder of the
/// app's support directory (inside the app's own sandbox on iOS, Android and
/// a sandboxed macOS build). dart:io writes on its own threads, never the UI
/// one; a file is written beside its name and renamed over it, so a crash
/// mid-write never leaves half an answer.
library;

import 'dart:io';

import 'package:dashboard_core/dashboard_core.dart' show OfflineBlobs;

class DirectoryBlobs implements OfflineBlobs {
  DirectoryBlobs(this.dir);

  final Directory dir;

  File _file(String name) => File('${dir.path}${Platform.pathSeparator}$name');

  @override
  Future<List<int>?> read(String name) async {
    try {
      return await _file(name).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String name, List<int> bytes) async {
    await dir.create(recursive: true);
    final part = _file('$name.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(_file(name).path);
  }

  @override
  Future<void> delete(String name) async {
    try {
      await _file(name).delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  @override
  Future<List<String>> names() async {
    if (!await dir.exists()) return const [];
    final out = <String>[];
    await for (final e in dir.list()) {
      if (e is File) out.add(e.uri.pathSegments.last);
    }
    return out;
  }

  @override
  Future<void> clear() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
