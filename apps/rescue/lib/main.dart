// Madar POS — database rescue build.
//
// This app exists for one job: copy the POS's local SQLite store off a device
// whose queued sales have not synced, on a tablet with no USB debugging.
//
// It ships with `applicationId = com.madar.pos` and the production signing key,
// so installing it UPDATES the POS in place and inherits its sandbox — which is
// the only way on Android to read another build's private files. It must be
// installed over the app, never after an uninstall: uninstalling deletes the
// very data this is here to rescue.
//
// It deliberately does NOT open the database. Opening it with any version of the
// core would run schema migrations against the only copy of those sales. It
// copies bytes and nothing else — including the -wal and -shm sidecars, because
// the store runs in WAL mode and recent writes live in the -wal file. A copy of
// madar.db alone can be missing the newest orders.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const DumpApp());

class DumpApp extends StatelessWidget {
  const DumpApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Madar Rescue',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
    home: const DumpScreen(),
  );
}

class DumpScreen extends StatefulWidget {
  const DumpScreen({super.key});

  @override
  State<DumpScreen> createState() => _DumpScreenState();
}

class _DumpScreenState extends State<DumpScreen> {
  final List<String> _log = [];
  bool _busy = false;
  bool _done = false;

  void _say(String line) => setState(() => _log.add(line));

  /// Where the POS keeps its store. Same package id, so the same directory.
  Future<Directory> _storeDir() async => getApplicationSupportDirectory();

  /// Candidate destinations, best first.
  ///
  /// A public folder is what an FTP server on the device can actually serve.
  /// On Android 11+ that write is refused unless the user grants "all files",
  /// so the app-specific external directory is kept as a fallback — it always
  /// works and is still outside the sandbox.
  Future<List<Directory>> _destinations() async {
    final out = <Directory>[];
    for (final p in ['/storage/emulated/0/MadarDump', '/sdcard/MadarDump']) {
      out.add(Directory(p));
    }
    final ext = await getExternalStorageDirectory();
    if (ext != null) out.add(Directory('${ext.path}/MadarDump'));
    return out;
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _done = false;
      _log.clear();
    });

    try {
      // Ask for storage access. Refusal is not fatal — the fallback destination
      // needs no permission at all.
      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
      }
      if (await Permission.manageExternalStorage.isDenied) {
        await Permission.manageExternalStorage.request();
      }

      final src = await _storeDir();
      _say('Store directory: ${src.path}');

      // madar.db plus its WAL sidecars. Copy all three or risk losing the most
      // recent orders, which are exactly the ones that never synced.
      final names = ['madar.db', 'madar.db-wal', 'madar.db-shm'];
      final present = <File>[];
      for (final n in names) {
        final f = File('${src.path}/$n');
        if (f.existsSync()) {
          present.add(f);
          _say('found $n  (${_size(f.lengthSync())})');
        } else {
          _say('missing $n  (may be normal)');
        }
      }
      if (present.isEmpty) {
        _say('');
        _say('NO DATABASE HERE — nothing to copy.');
        _say('Expected on a phone without the POS installed.');
        // List what IS there, so a wrong path is diagnosable rather than fatal.
        for (final e in src.listSync()) {
          _say('  • ${e.path.split('/').last}');
        }
        // Still prove where this Android version lets us write. That is the
        // whole point of a dry run on a different handset: on the real tablet a
        // refused destination is discovered too late.
        _say('');
        _say('Checking where a copy could be written:');
        for (final dest in await _destinations()) {
          try {
            dest.createSync(recursive: true);
            final probe = File('${dest.path}/.madar_write_test');
            probe.writeAsStringSync('ok');
            probe.deleteSync();
            _say('  WRITABLE  ${dest.path}');
          } catch (e) {
            _say('  refused   ${dest.path}');
          }
        }
        _say('');
        _say('Send this screen to Shawket.');
        setState(() => _busy = false);
        return;
      }

      Directory? wrote;
      for (final dest in await _destinations()) {
        try {
          dest.createSync(recursive: true);
          for (final f in present) {
            final name = f.path.split('/').last;
            f.copySync('${dest.path}/$name');
          }
          wrote = dest;
          break;
        } catch (e) {
          _say('could not write to ${dest.path} — $e');
        }
      }

      _say('');
      if (wrote == null) {
        _say('COULD NOT WRITE THE COPY ANYWHERE.');
        _say('Do not uninstall anything. Send this screen to Shawket.');
      } else {
        // Verify by size: a copy that silently truncated is worse than a failure.
        var ok = true;
        for (final f in present) {
          final name = f.path.split('/').last;
          final copy = File('${wrote.path}/$name');
          final a = f.lengthSync();
          final b = copy.existsSync() ? copy.lengthSync() : -1;
          _say(
            '$name: ${_size(a)} → ${_size(b)} ${a == b ? "OK" : "MISMATCH"}',
          );
          if (a != b) ok = false;
        }
        _say('');
        _say(ok ? 'COPIED TO:' : 'COPIED WITH PROBLEMS — TO:');
        _say(wrote.path);
        _say('');
        _say('Fetch all three files over FTP.');
        _say('Do NOT uninstall the app until they are on the MacBook.');
        setState(() => _done = ok);
      }
    } catch (e) {
      _say('FAILED: $e');
      _say('Do not uninstall anything.');
    } finally {
      setState(() => _busy = false);
    }
  }

  String _size(int b) {
    if (b < 0) return 'missing';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Madar — rescue the queued sales'),
        backgroundColor: _done ? Colors.green.shade100 : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This copies the POS database to shared storage so it can be '
              'fetched over FTP. It does not open or change the database.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              'Do not uninstall the app. Uninstalling deletes the sales.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _run,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_busy ? 'Copying…' : 'Copy database out'),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _log.isEmpty ? 'Ready.' : _log.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
