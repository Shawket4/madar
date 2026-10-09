/// The plan being edited: a local draft over the saved plan, with undo (the
/// web's `use-plan-draft.ts`).
///
/// Nothing is autosaved: edits collect in the draft and Save reviews them
/// first. The saved plan keeps flowing in (realtime `branch.plan_changed`
/// refetches it): a draft with no changes follows it; a draft with changes
/// keeps them and says someone else saved ([overtaken]).
library;

import 'package:flutter/foundation.dart';

import 'plan.dart';

class PlanDraft extends ChangeNotifier {
  BuilderPlan? _draft;
  ({BuilderPlan plan, int version})? _base;
  UndoHistory<BuilderPlan> _history = const UndoHistory();

  /// The latest saved plan the server gave.
  BuilderPlan? _saved;
  int? _savedVersion;

  /// What the canvas shows: the draft, or the saved plan when nothing changed.
  BuilderPlan? get plan => _draft;

  /// The version the draft was started from; what a save must match.
  int? get baseVersion => _base?.version;

  bool get dirty {
    final d = _draft, b = _base;
    return d != null && b != null && !samePlan(d, b.plan);
  }

  /// Someone saved a newer plan while this draft had changes.
  bool get overtaken =>
      dirty && _savedVersion != null && _savedVersion != _base!.version;

  bool get canUndo => _history.past.isNotEmpty;
  bool get canRedo => _history.future.isNotEmpty;

  /// A saved plan arrived (or the same one, again): a clean draft follows
  /// it; a version change drops the undo steps (redoing one would write the
  /// older plan back). Silent: called while the page builds.
  void receive(BuilderPlan saved, int version) {
    _saved = saved;
    _savedVersion = version;
    _follow();
  }

  void _follow() {
    final saved = _saved, version = _savedVersion;
    if (saved == null || version == null || dirty) return;
    if (_base != null && _base!.version != version) {
      _history = const UndoHistory();
    }
    _base = (plan: saved, version: version);
    _draft = saved;
  }

  void _set(BuilderPlan next) {
    _draft = next;
    _follow();
    notifyListeners();
  }

  /// One edit, one undo step.
  void change(BuilderPlan Function(BuilderPlan plan) edit) {
    final current = _draft;
    if (current == null) return;
    final next = edit(current);
    if (identical(next, current)) return;
    _history = pushHistory(_history, current);
    _set(next);
  }

  /// A continuous gesture (a drag) starts: one undo step for all of it.
  void beginGesture() {
    final current = _draft;
    if (current != null) _history = pushHistory(_history, current);
  }

  /// An update during a gesture, without undo steps.
  void live(BuilderPlan Function(BuilderPlan plan) edit) {
    final current = _draft;
    if (current != null) _set(edit(current));
  }

  void undo() => _step(applyUndo);
  void redo() => _step(applyRedo);

  void _step(
    ({BuilderPlan value, UndoHistory<BuilderPlan> history})? Function(
      UndoHistory<BuilderPlan>,
      BuilderPlan,
    )
    fn,
  ) {
    final current = _draft;
    if (current == null) return;
    final r = fn(_history, current);
    if (r == null) return;
    _history = r.history;
    _set(r.value);
  }

  /// Drops the draft and follows the saved plan again.
  void discard() {
    _history = const UndoHistory();
    final saved = _saved, version = _savedVersion;
    if (saved != null && version != null) {
      _base = (plan: saved, version: version);
      _draft = saved;
    }
    notifyListeners();
  }

  /// Replaces the draft wholesale (a setup picked, a version loaded), as
  /// one undo step.
  void replace(BuilderPlan plan) => change((_) => plan);

  /// After a save: the saved plan is the new base.
  void adopt(BuilderPlan plan, int version) {
    _history = const UndoHistory();
    _base = (plan: plan, version: version);
    _draft = plan;
    _saved = plan;
    _savedVersion = version;
    notifyListeners();
  }
}
