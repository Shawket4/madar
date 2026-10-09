/// Table geometry: local edits, undo, and autosave — the web's
/// `use-floor-geometry.ts` (SELL-FLR-048 – 054, -085, -087).
///
/// A gesture is saved [kAutosaveDebounce] after it settles, in one
/// `PUT /floor/layout` naming every changed table with the `updated_at` it
/// was first seen with (then the one each save returns), so two managers
/// arranging one room never silently overwrite each other. Undo and redo are
/// edits too: they are saved.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:flutter/foundation.dart';

import 'floor_util.dart';

/// The header's save indicator (`SaveState`).
enum FloorSaveState { idle, pending, saving, saved, conflict, error }

typedef GeoMap = Map<String, GeoItem>;

class FloorGeometry extends ChangeNotifier {
  FloorGeometry({
    required this.branchId,
    required this.save,
    required this.onSaved,
    required this.onFailed,
  });

  final String branchId;

  /// `PUT /floor/layout`.
  final Future<List<FloorTable>> Function(SaveLayoutRequest body) save;

  /// A save landed: the web's `invalidateFloor()`.
  final VoidCallback onSaved;

  /// A save failed; [conflict] for the 409 (someone else moved a table).
  final void Function(Object error, {required bool conflict}) onFailed;

  List<FloorTable> _tables = const [];
  GeoMap _geo = {};
  UndoHistory<GeoMap> _history = const UndoHistory();
  FloorSaveState _state = FloorSaveState.idle;

  /// The `updated_at` each table was FIRST seen with, then the one each save
  /// returned — never a refetch's (that would defeat the guard).
  final Map<String, DateTime> _tokens = {};

  /// Ids changed since the last successful save.
  final Set<String> _dirty = {};
  Timer? _timer;
  bool _disposed = false;

  FloorSaveState get saveState => _state;
  bool get canUndo => _history.past.isNotEmpty;
  bool get canRedo => _history.future.isNotEmpty;

  /// The branch's tables as last read (call on every build with the list);
  /// a table's token is taken when it is first seen in a NEW list.
  void syncTables(List<FloorTable> tables) {
    if (identical(tables, _tables)) return;
    _tables = tables;
    for (final t in tables) {
      _tokens.putIfAbsent(t.id, () => t.updatedAt);
    }
  }

  /// Live geometry: the local edit if there is one, else the row.
  GeoItem geoOf(FloorTable t) =>
      _geo[t.id] ??
      GeoItem(
        id: t.id,
        x: t.posX,
        y: t.posY,
        w: t.width,
        h: t.height,
        rot: t.rotation,
      );

  /// Records the state a gesture is about to change (one undo step).
  void beginGesture() {
    _history = pushHistory(_history, _geo);
    _notify();
  }

  /// Stages [updates]; call [beginGesture] first so undo groups them.
  void setGeo(List<GeoItem> updates) {
    if (updates.isEmpty) return;
    // A table's first local edit: the snapshots taken before it meant "the
    // row", which a save is about to change. Pin the row's geometry into
    // them, so undo puts the table back (the web's undo of a saved first
    // edit does nothing).
    for (final u in updates) {
      if (_geo.containsKey(u.id)) continue;
      final row = _tables.where((t) => t.id == u.id).firstOrNull;
      if (row == null) continue;
      final g = geoOf(row);
      GeoMap pin(GeoMap m) => m.containsKey(u.id) ? m : {...m, u.id: g};
      _history = UndoHistory(
        past: [for (final m in _history.past) pin(m)],
        future: [for (final m in _history.future) pin(m)],
      );
    }
    _geo = {..._geo, for (final u in updates) u.id: u};
    _dirty.addAll(updates.map((u) => u.id));
    _schedule();
  }

  void undo() => _step(applyUndo);
  void redo() => _step(applyRedo);

  void _step(
    ({GeoMap value, UndoHistory<GeoMap> history})? Function(
      UndoHistory<GeoMap>,
      GeoMap,
    )
    step,
  ) {
    final r = step(_history, _geo);
    if (r == null) return;
    // Everything the step touched in either direction is saved again.
    _dirty.addAll({...r.value.keys, ..._geo.keys});
    _history = r.history;
    _geo = r.value;
    _schedule();
  }

  /// The 409 toast's "Reload": drop every local edit and token.
  void reload() {
    _dirty.clear();
    _geo = {};
    // The refetch that follows brings the tokens back.
    _tokens.clear();
    _state = FloorSaveState.idle;
    _notify();
  }

  void _schedule() {
    _state = FloorSaveState.pending;
    _timer?.cancel();
    _timer = Timer(kAutosaveDebounce, () => unawaited(_save()));
    _notify();
  }

  /// Saves what is pending now.
  Future<void> flush() async {
    _timer?.cancel();
    await _save();
  }

  Future<void> _save() async {
    final ids = [..._dirty];
    // Cleared up front: an edit made while this request is in flight is
    // saved by the next pass.
    _dirty.clear();
    final payload = <TablePosition>[
      for (final id in ids)
        if (_geo[id] case final g?)
          if (_tables.where((t) => t.id == id).firstOrNull case final t?)
            TablePosition(
              id: id,
              // save_layout always writes section_id: keep the table where
              // it is.
              sectionId: t.sectionId,
              posX: g.x,
              posY: g.y,
              width: g.w,
              height: g.h,
              rotation: g.rot,
              expectedUpdatedAt: _tokens[id] ?? t.updatedAt,
              explicitNulls: const {'section_id'},
            ),
    ];
    if (payload.isEmpty) {
      // Nothing to send (an undo of a click that moved nothing): the web
      // stays on "Saving…" for good; say nothing instead.
      if (_state == FloorSaveState.pending) _state = FloorSaveState.idle;
      _notify();
      return;
    }
    _state = FloorSaveState.saving;
    _notify();
    try {
      final rows = await save(
        SaveLayoutRequest(branchId: branchId, tables: payload),
      );
      for (final r in rows) {
        _tokens[r.id] = r.updatedAt;
      }
      _state = FloorSaveState.saved;
      onSaved();
    } on Object catch (e) {
      // Nothing was written (the batch rolls back): keep the edits and retry
      // them with the next change.
      _dirty.addAll(ids);
      final conflict = e is ApiException && e.status == 409;
      _state = conflict ? FloorSaveState.conflict : FloorSaveState.error;
      if (!_disposed) onFailed(e, conflict: conflict);
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Leaving the page saves what is pending (the web drops it on an in-app
  /// navigation: a divergence).
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_dirty.isNotEmpty) unawaited(_save());
    super.dispose();
  }
}
