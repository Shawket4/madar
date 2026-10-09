/// The answers kept for a relaunch with no network: the body of every
/// successful GET the dashboard read, as the server sent it, with when.
///
/// - One person's answers at a time: [OfflineStore.claim] wipes anyone
///   else's first, a write for another person is dropped, and signing out
///   wipes it all ([OfflineStore.wipe]).
/// - Bounded: past [OfflineStore.maxBytes] the least recently used answers
///   go.
/// - Written in order, off the UI thread (the bytes are already the JSON the
///   server sent; nothing is encoded on the way in).
library;

import 'dart:async';
import 'dart:convert';

/// Where the bytes live: a folder in the app's support directory (the app's
/// `DirectoryBlobs`) or memory ([MemoryBlobs]: tests and mock mode).
abstract interface class OfflineBlobs {
  /// The bytes saved under [name], or null.
  Future<List<int>?> read(String name);

  Future<void> write(String name, List<int> bytes);

  Future<void> delete(String name);

  /// Every name saved.
  Future<List<String>> names();

  /// Deletes everything.
  Future<void> clear();
}

/// [OfflineBlobs] in memory.
class MemoryBlobs implements OfflineBlobs {
  final Map<String, List<int>> files = {};

  @override
  Future<List<int>?> read(String name) async => files[name];

  @override
  Future<void> write(String name, List<int> bytes) async =>
      files[name] = List.unmodifiable(bytes);

  @override
  Future<void> delete(String name) async => files.remove(name);

  @override
  Future<List<String>> names() async => files.keys.toList();

  @override
  Future<void> clear() async => files.clear();
}

/// One saved answer: the JSON body as the server sent it, and when.
class SavedAnswer {
  const SavedAnswer(this.body, this.savedAt);

  final List<int> body;
  final DateTime savedAt;
}

class _Entry {
  _Entry(this.name, this.size, this.savedAt, this.used);

  final String name;
  final int size;
  final DateTime savedAt;
  DateTime used;

  Map<String, Object?> toJson() => {
    'f': name,
    'n': size,
    't': savedAt.millisecondsSinceEpoch,
    'u': used.millisecondsSinceEpoch,
  };

  static _Entry fromJson(Map<String, Object?> j) => _Entry(
    j['f']! as String,
    (j['n']! as num).toInt(),
    DateTime.fromMillisecondsSinceEpoch((j['t']! as num).toInt(), isUtc: true),
    DateTime.fromMillisecondsSinceEpoch((j['u']! as num).toInt(), isUtc: true),
  );
}

/// The saved answers, by key (see `offlineKey`).
class OfflineStore {
  OfflineStore._(this._blobs, this.maxBytes, this._clock);

  /// Opens the store over [blobs]. An index that cannot be read starts it
  /// empty (and clears what was there); a saved file the index does not name
  /// is deleted.
  static Future<OfflineStore> open(
    OfflineBlobs blobs, {
    int maxBytes = defaultMaxBytes,
    DateTime Function() clock = DateTime.now,
  }) async {
    final s = OfflineStore._(blobs, maxBytes, clock);
    await s._load();
    return s;
  }

  /// 64 MB: weeks of every page a busy owner opens.
  static const int defaultMaxBytes = 64 * 1024 * 1024;

  static const String indexName = 'index.json';

  final OfflineBlobs _blobs;

  /// Past this, the least recently used answers go (down to 90 % of it).
  final int maxBytes;
  final DateTime Function() _clock;

  final Map<String, _Entry> _entries = {};
  String? _owner;
  int _next = 0;
  int _bytes = 0;
  bool _dirty = false;
  int _pending = 0;
  Future<void> _queue = Future<void>.value();

  /// The person the saved answers belong to (null when it is empty).
  String? get owner => _owner;

  /// The saved bytes, every answer together.
  int get bytes => _bytes;

  /// How many answers are saved.
  int get length => _entries.length;

  /// When the answer under [key] was saved, or null.
  DateTime? savedAt(String key) => _entries[key]?.savedAt;

  /// Every saved key starting with [prefix].
  List<String> keysWithPrefix(String prefix) => [
    for (final k in _entries.keys)
      if (k.startsWith(prefix)) k,
  ];

  /// Makes [userId] the owner; another person's answers are wiped first.
  Future<void> claim(String userId) => _serial(() async {
    if (_owner == userId) return;
    if (_owner != null || _entries.isNotEmpty) await _wipeNow();
    _owner = userId;
    _dirty = true;
  });

  /// The answer saved under [key], or null.
  Future<SavedAnswer?> read(String key) async {
    final e = _entries[key];
    if (e == null) return null;
    final body = await _blobs.read(e.name);
    if (body == null) return null;
    // Flushed with the next write: the order only steers eviction.
    e.used = _clock();
    _dirty = true;
    return SavedAnswer(body, e.savedAt);
  }

  /// Saves [body] under [key] for [user]; dropped when [user] is not the
  /// owner (a late answer for someone who has signed out) or when the body
  /// alone is past [maxBytes].
  Future<void> write(
    String user,
    String key,
    List<int> body,
    DateTime savedAt,
  ) => _serial(() async {
    if (_owner != user || body.length > maxBytes) return;
    final old = _entries[key];
    final name = old?.name ?? 'a${_next++}.json';
    await _blobs.write(name, body);
    if (old != null) _bytes -= old.size;
    _entries[key] = _Entry(name, body.length, savedAt.toUtc(), _clock());
    _bytes += body.length;
    _dirty = true;
    await _evict(keep: key);
  });

  /// Forgets everything, the owner too.
  Future<void> wipe() => _serial(_wipeNow);

  Future<void> _wipeNow() async {
    _entries.clear();
    _bytes = 0;
    _owner = null;
    _next = 0;
    _dirty = false;
    await _blobs.clear();
  }

  Future<void> _evict({required String keep}) async {
    if (_bytes <= maxBytes) return;
    final target = maxBytes * 9 ~/ 10;
    final oldest = _entries.entries.where((e) => e.key != keep).toList()
      ..sort((a, b) => a.value.used.compareTo(b.value.used));
    for (final e in oldest) {
      if (_bytes <= target) break;
      _entries.remove(e.key);
      _bytes -= e.value.size;
      await _blobs.delete(e.value.name);
    }
  }

  /// Runs [op] after every earlier one; the last of a burst saves the index.
  Future<void> _serial(Future<void> Function() op) {
    _pending++;
    final done = _queue.then((_) async {
      try {
        await op();
      } finally {
        _pending--;
        if (_pending == 0 && _dirty) {
          _dirty = false;
          await _saveIndex();
        }
      }
    });
    _queue = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  Future<void> _saveIndex() => _blobs.write(
    indexName,
    utf8.encode(
      jsonEncode({
        'v': 1,
        'owner': _owner,
        'next': _next,
        'entries': {for (final e in _entries.entries) e.key: e.value.toJson()},
      }),
    ),
  );

  Future<void> _load() async {
    try {
      final raw = await _blobs.read(indexName);
      if (raw != null) {
        final j = jsonDecode(utf8.decode(raw)) as Map<String, Object?>;
        if (j['v'] != 1) throw const FormatException('index version');
        _owner = j['owner'] as String?;
        _next = (j['next']! as num).toInt();
        for (final e in (j['entries']! as Map<String, Object?>).entries) {
          final entry = _Entry.fromJson(e.value! as Map<String, Object?>);
          _entries[e.key] = entry;
          _bytes += entry.size;
        }
      }
      final named = {for (final e in _entries.values) e.name, indexName};
      for (final n in await _blobs.names()) {
        if (!named.contains(n)) await _blobs.delete(n);
      }
    } on Object {
      // Unreadable: start empty rather than serve a guess.
      _entries.clear();
      _bytes = 0;
      _owner = null;
      _next = 0;
      await _blobs.clear();
    }
  }
}
