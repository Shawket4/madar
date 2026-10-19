/// The Setup page's vocabulary (web `features/setup/checks.ts`): for each
/// readiness check the server sends (`GET /orgs/{id}/readiness`, MadarRust
/// `orgs/readiness.rs`), its glyph, the page that fixes it and its words
/// (`setup.checks.<key>` in this package's tables, the web's own). Nothing
/// here decides whether a check passes: that is the server's.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show CheckLevel, Readiness, ReadinessCheck, ReadinessProblem;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

/// A check's glyph and the page its button opens (`tablet` and an empty
/// `menu` start on the Setup page instead).
typedef CheckDef = ({String icon, String to});

const Map<String, CheckDef> checkDefs = {
  'branch': (icon: 'building-2', to: '/branches'),
  'menu': (icon: 'utensils-crossed', to: '/menu/items'),
  'payment': (icon: 'credit-card', to: '/settings/payment-methods'),
  'sign_in': (icon: 'key-round', to: '/access/users'),
  'tablet': (icon: 'tablet', to: '/devices'),
  'items_no_category': (icon: 'folder-tree', to: '/menu/items'),
  'items_zero_price': (icon: 'coins', to: '/menu/items'),
  'required_group_empty': (icon: 'list-checks', to: '/menu/groups'),
  'menu_lint': (icon: 'clipboard-check', to: '/menu/items'),
  'recipes': (icon: 'book-open', to: '/menu/items?tab=items&recipe=missing'),
  'ingredient_costs': (icon: 'scale', to: '/inventory/ingredients'),
  'team': (icon: 'users', to: '/access/users'),
  'receipt': (icon: 'receipt', to: '/settings/brand'),
};

/// The checks a branch is named in: their names are in the sentence.
const Set<String> perBranchChecks = {'payment', 'sign_in', 'tablet'};

/// Where one named problem is fixed: its own editor.
String problemRoute(ReadinessProblem p) => switch (p) {
  ReadinessProblem(:final itemId?) => '/menu/items/$itemId',
  ReadinessProblem(entityType: 'branch') => '/branches?edit=${p.entityId}',
  ReadinessProblem(entityType: 'ingredient') => '/inventory/ingredients',
  ReadinessProblem(:final groupId?) => '/menu/groups?edit=$groupId',
  _ => '/menu/groups',
};

/// The checks this build knows how to show; an unknown key from a newer
/// server is skipped.
List<ReadinessCheck> knownChecks(Readiness r) => [
  for (final c in r.checks)
    if (checkDefs.containsKey(c.key)) c,
];

List<ReadinessCheck> blockingChecks(Readiness r) => [
  for (final c in knownChecks(r))
    if (c.level == CheckLevel.blocking) c,
];

List<ReadinessCheck> adviceChecks(Readiness r) => [
  for (final c in knownChecks(r))
    if (c.level != CheckLevel.blocking) c,
];

/// The first blocking check still open: the one thing to do next.
ReadinessCheck? nextCheck(Readiness r) =>
    blockingChecks(r).where((c) => !c.ok).firstOrNull;

/// Blocking checks still open.
int leftToDo(Readiness r) => blockingChecks(r).where((c) => !c.ok).length;

/// Where the shop is: nothing for the till (no POS), setting up, ready but
/// no sale yet, or live.
enum SetupStage { none, setup, ready, live }

SetupStage stageOf(Readiness r) => r.checks.isEmpty
    ? SetupStage.none
    : !r.ready
    ? SetupStage.setup
    : r.live
    ? SetupStage.live
    : SetupStage.ready;

/// The home card shows until the shop is ready AND has sold; a new blocking
/// problem brings it back. Nothing is dismissed or stored.
bool showsHomeCard(Readiness r) =>
    const {SetupStage.setup, SetupStage.ready}.contains(stageOf(r));

/// `GET /orgs/{id}/readiness`, read fresh each time a page that shows it
/// opens (the owner fixes things on other pages and comes back, and the
/// answer must be the shop as it is now) and when the app comes back to the
/// front; a write that changes it bumps `/orgs/{id}/readiness`.
final readinessProvider = FutureProvider.autoDispose.family<Readiness, String>((
  ref,
  orgId,
) {
  // Short, not zero: the first listener would refetch what was just read.
  ref.webCache(staleTime: const Duration(seconds: 2));
  ref.watch(realtimeEpochProvider('/orgs/$orgId/readiness'));
  final resume = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(resume.dispose);
  return ref.watch(apiProvider).orgs.getReadiness(id: orgId);
});

/// [names] as one phrase: "Maadi, Zamalek and 2 more" (the web's
/// `Intl.ListFormat` conjunction, the extra ones counted by `setup.andMore`).
String joinNames(Translator t, List<String> names, int more) {
  final shown = names.take(3).toList();
  final comma = t.isRtl ? '، ' : ', ';
  final rest = names.length - shown.length + more;
  // `setup.andMore` brings its own "and" / "و".
  if (rest > 0) {
    return '${shown.join(comma)} ${t('setup.andMore', count: rest)}';
  }
  if (shown.length < 2) return shown.firstOrNull ?? '';
  final head = shown.sublist(0, shown.length - 1).join(comma);
  return t.isRtl ? '$head و${shown.last}' : '$head and ${shown.last}';
}

/// A check's title, its sentence for its state, and its button's words.
extension CheckCopy on Translator {
  String checkTitle(String key) => call('setup.checks.$key.title');
  String checkAction(String key) => call('setup.checks.$key.action');

  String checkLine(ReadinessCheck c) {
    final total = c.total ?? 0;
    // No branch at all: the per-branch checks have no one to name.
    if (!c.ok && perBranchChecks.contains(c.key) && c.problems.isEmpty) {
      return call('setup.checks.branch.todo');
    }
    if (c.ok) {
      return call(
        'setup.checks.${c.key}.ok',
        count: c.count,
        args: {'total': total},
      );
    }
    return call(
      'setup.checks.${c.key}.todo',
      count: c.count,
      args: {
        'total': total,
        'done': (total - c.count).clamp(0, total),
        'names': joinNames(this, [for (final p in c.problems) p.name], c.more),
      },
    );
  }
}
