import 'dart:convert';
import 'dart:io';

/// madar-shared's vectors as the web pins them (`src/lib/<name>_vectors.json`),
/// copied by `tool/sync_web_vectors.py` into `packages/dashboard_core/test/vectors/`.
/// [name] is the file's stem, e.g. `day_bounds`. Works from any package's tests:
/// it looks for `dashboard_core/test/vectors/` from the current folder upwards.
Object? sharedVectors(String name) {
  for (var dir = Directory.current.absolute; ; dir = dir.parent) {
    for (final base in ['${dir.path}/dashboard_core', '${dir.path}/packages/dashboard_core']) {
      final f = File('$base/test/vectors/${name}_vectors.json');
      if (f.existsSync()) return json.decode(f.readAsStringSync());
    }
    if (dir.parent.path == dir.path) {
      throw StateError('${name}_vectors.json not found: run tool/sync_web_vectors.py');
    }
  }
}
