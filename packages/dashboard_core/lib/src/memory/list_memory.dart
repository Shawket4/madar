/// What a list page was showing — its filters, search, sort, tab, page and
/// scroll — kept while the person goes somewhere else and comes back (the
/// owner's rule: a filter carries through navigation, everywhere).
///
/// One store, [DashListMemory], for the signed-in session, and three ways in:
///
/// - **Kit widgets remember themselves.** Every page is built under a
///   [PageStorage] bucket that belongs to its location
///   ([DashListMemory.bucketFor], set by the shell's `DashRouteHost`), so the
///   page scroll ([DashPageScaffold]) and a [DashDataTable]'s sort, search,
///   page and hidden columns come back with no code in the page.
/// - **A page's own filters** (a select, chips, a tab, a server page) use
///   [DashRememberedState]: the page names its values and how to restore
///   them; they are saved on every `setState`.
/// - **Filters held in the URL** (`/tills?status=…`) are named on the route
///   ([DashRoute.rememberQuery]); the router puts them back when the page is
///   opened bare from another page.
///
/// Scope rules: the store belongs to one org — another org (or signing out)
/// forgets everything. A value that only means something in one branch (a
/// teller, a station, a table) is restored only in the branch it was picked
/// in ([DashMemo.sameBranch]). A remembered id that is no longer offered (a
/// deleted category) is dropped by the page once its options load
/// ([dashStale]).
///
/// Nothing here is persisted: a relaunch starts clean, as the web's does.
library;

import 'package:dashboard_core/src/scope/scope.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The org and branch the dashboard is looking at.
typedef DashMemoryScope = ({String? org, String? branch});

/// A list's remembered values, as handed to
/// [DashRememberedState.restoreRemembered].
@immutable
class DashMemo {
  const DashMemo(this.values, {this.sameBranch = true});

  /// Nothing remembered: every filter at its default.
  static const DashMemo empty = DashMemo({});

  final Map<String, Object?> values;

  /// Whether the branch in scope is the one these values were picked in. A
  /// page restores its branch-bound values (a teller, a station) only when
  /// true.
  final bool sameBranch;

  /// Nothing set: no value, or every value null or empty.
  bool get isEmpty => values.values.every(
    (v) => v == null || v == '' || (v is Iterable && v.isEmpty),
  );

  /// [key] when it is a [T], else null.
  T? get<T>(String key) {
    final v = values[key];
    return v is T ? v : null;
  }

  /// [key] when it is a [T], else [fallback].
  T getOr<T>(String key, T fallback) => get<T>(key) ?? fallback;

  /// A string value; an empty string reads as null.
  String? string(String key) {
    final v = get<String>(key);
    return v == null || v.isEmpty ? null : v;
  }

  /// An enum stored by its name; an unknown name reads as [fallback].
  E enumOr<E extends Enum>(String key, List<E> all, E fallback) {
    final name = get<String>(key);
    for (final e in all) {
      if (e.name == name) return e;
    }
    return fallback;
  }

  /// A nullable enum stored by its name.
  E? enumOrNull<E extends Enum>(String key, List<E> all) {
    final name = get<String>(key);
    for (final e in all) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// A set stored as a list.
  Set<T> setOf<T>(String key) => {...?get<List<Object?>>(key)?.whereType<T>()};
}

/// Whether [value] is a remembered choice its options no longer offer:
/// set, the options loaded ([known] non-null), and not among them. The
/// page drops it (back to "All").
bool dashStale<T>(T? value, Iterable<T>? known) =>
    value != null && known != null && !known.contains(value);

class _Remembered {
  _Remembered(this.values, this.branch);
  final Map<String, Object?> values;
  final String? branch;
}

/// The session's remembered lists ([dashListMemoryProvider]).
class DashListMemory {
  DashListMemory(this._scope);

  final DashMemoryScope Function() _scope;

  String? _org;
  bool _known = false;
  final Map<String, _Remembered> _lists = {};
  final Map<String, _Remembered> _queries = {};
  final Map<String, PageStorageBucket> _buckets = {};
  final Map<String, String> _origins = {};

  /// Everything kept belongs to the org in scope; another org (or none)
  /// starts clean.
  DashMemoryScope _current() {
    final s = _scope();
    if (!_known || s.org != _org) {
      clear();
      _org = s.org;
      _known = true;
    }
    return s;
  }

  /// Forgets every list.
  void clear() {
    _lists.clear();
    _queries.clear();
    _buckets.clear();
    _origins.clear();
  }

  // ── a page's own values ───────────────────────────────────────────────

  /// What [key] was showing ([DashMemo.empty] when nothing is kept).
  DashMemo recall(String key) {
    final s = _current();
    final r = _lists[key];
    if (r == null) return DashMemo.empty;
    return DashMemo(r.values, sameBranch: r.branch == s.branch);
  }

  /// Keeps [values] for [key], under the branch in scope.
  void remember(String key, Map<String, Object?> values) {
    final s = _current();
    _lists[key] = _Remembered(Map.unmodifiable(values), s.branch);
  }

  /// Forgets [key].
  void forget(String key) {
    _current();
    _lists.remove(key);
  }

  // ── filters held in the URL ───────────────────────────────────────────

  /// The query [path] was last shown with (only its remembered keys), and
  /// whether the branch is still the one it was picked in.
  ({Map<String, String> query, bool sameBranch})? recallQuery(String path) {
    final s = _current();
    final r = _queries[path];
    if (r == null) return null;
    return (
      query: r.values.cast<String, String>(),
      sameBranch: r.branch == s.branch,
    );
  }

  void rememberQuery(String path, Map<String, String> query) {
    final s = _current();
    _queries[path] = _Remembered(Map.unmodifiable(query), s.branch);
  }

  // ── kit widgets (scroll, tables) ──────────────────────────────────────

  /// The [PageStorageBucket] the page at [path] keeps its widgets' state in.
  PageStorageBucket bucketFor(String path) {
    _current();
    return _buckets.putIfAbsent(path, PageStorageBucket.new);
  }

  // ── where a detail page goes back to ──────────────────────────────────

  /// Opening the detail page [detailPath] from [from] (path and query): its
  /// Back returns there. Opened from another detail page, it returns where
  /// that one would (never a loop between two details).
  void openedFrom(String detailPath, Uri from) {
    _current();
    final fromPath = from.path;
    if (fromPath == detailPath) return;
    _origins[detailPath] = _origins[fromPath] ?? from.toString();
  }

  /// Where [detailPath]'s Back goes: the page it was opened from, else
  /// [fallback].
  String backTarget(String detailPath, String fallback) {
    _current();
    return _origins[detailPath] ?? fallback;
  }
}

/// The session's list memory. Not auto-disposed: it outlives every page.
final dashListMemoryProvider = Provider<DashListMemory>(
  (ref) => DashListMemory(
    () => (
      org: ref.read(orgIdProvider),
      branch: ref.read(scopeProvider.select((s) => s.branchId)),
    ),
  ),
);

/// A list page whose filters (search, selects, chips, tab, page, sort) come
/// back when the person returns to it — from an editor, a report, another
/// page. The page names them ([rememberedValues]) and restores them
/// ([restoreRemembered]); every `setState` saves them.
///
/// [restoreRemembered] is also how the page resets: it gets
/// [DashMemo.empty] when the org changes (every filter back to its default)
/// and its own values with `sameBranch: false` when the branch changes
/// (only branch-bound values reset).
mixin DashRememberedState<W extends ConsumerStatefulWidget>
    on ConsumerState<W> {
  /// The list's name in the memory (`menu.items`).
  String get memoryKey;

  /// The values to keep (strings, numbers, bools, enum names, lists).
  Map<String, Object?> get rememberedValues;

  /// Sets the page's fields from [memo] (called from `initState`, before the
  /// first build, and inside `setState` on a scope change).
  void restoreRemembered(DashMemo memo);

  late final DashListMemory _memory;

  @override
  void initState() {
    super.initState();
    _memory = ref.read(dashListMemoryProvider);
    restoreRemembered(_memory.recall(memoryKey));
    ref
      ..listenManual(orgIdProvider, (prev, next) {
        if (prev == next || !mounted) return;
        setState(() => restoreRemembered(DashMemo.empty));
      })
      ..listenManual(scopeProvider.select((s) => s.branchId), (prev, next) {
        if (prev == next || !mounted) return;
        setState(
          () =>
              restoreRemembered(DashMemo(rememberedValues, sameBranch: false)),
        );
      });
  }

  /// Saves the values now (after a field changed outside `setState`, e.g. a
  /// stale filter dropped while building).
  void rememberNow() => _memory.remember(memoryKey, rememberedValues);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    rememberNow();
  }
}

/// Opening a detail page, and its way back.
extension DashDetailNavigation on WidgetRef {
  /// Records where [location] (a detail page) is opened from, then the
  /// caller navigates: its Back ([dashBackTarget]) returns here, filters and
  /// all.
  void dashOpenedFrom(BuildContext context, String location) {
    final from = GoRouter.maybeOf(
      context,
    )?.routerDelegate.currentConfiguration.uri;
    if (from == null) return;
    read(dashListMemoryProvider).openedFrom(Uri.parse(location).path, from);
  }

  /// Where the detail page at [path] goes back to (the page it was opened
  /// from, else [fallback]).
  String dashBackTarget(String path, String fallback) =>
      read(dashListMemoryProvider).backTarget(path, fallback);
}
