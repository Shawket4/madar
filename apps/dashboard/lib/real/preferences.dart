/// The device's preferences (the web's localStorage) as one JSON file in the
/// app's support folder: read whole at boot, so reads are synchronous; each
/// write rewrites the file, one after another. A preference is a convenience:
/// an unreadable file starts empty and a failed write is dropped quietly.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_core/dashboard_core.dart' show PreferencesGateway;

class FilePreferences implements PreferencesGateway {
  FilePreferences._(this.file, this._values);

  /// Opens (or starts) the store at [file].
  static Future<FilePreferences> open(File file) async {
    var values = <String, String>{};
    try {
      if (await file.exists()) {
        final v = jsonDecode(await file.readAsString());
        if (v is Map) {
          values = {
            for (final e in v.entries)
              if (e.value is String) '${e.key}': e.value as String,
          };
        }
      }
    } on Object {
      values = {};
    }
    return FilePreferences._(file, values);
  }

  final File file;
  final Map<String, String> _values;
  Future<void> _writing = Future<void>.value();

  @override
  String? getString(String key) => _values[key];

  @override
  Future<void> setString(String key, String? value) {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    final snapshot = jsonEncode(_values);
    return _writing = _writing.then((_) async {
      try {
        await file.parent.create(recursive: true);
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(snapshot, flush: true);
        await tmp.rename(file.path);
      } on Object {
        // Dropped: the next write carries every value again.
      }
    });
  }
}
