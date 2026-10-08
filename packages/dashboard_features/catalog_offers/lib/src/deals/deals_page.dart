/// `/menu/deals` Deals (inventory OFFR-DEA-001..050; web
/// `features/deals/deals-page.tsx`): mix and match ("any 2 bites for 90")
/// and buy X get Y ("buy 2 coffees, get a cookie"), each its own small rule
/// over the cart.
///
/// - The route's gate is `menu.items.read` (the shell's Restricted "Deals"
///   without it). `menu.deals.edit` adds New deal, the row's Edit and Delete,
///   and Save in the dialog; without it a row opens the dialog read-only.
/// - The list is the whole of `GET /deals`, by `sort` then name, ten a page
///   in the client; any change of the rows (a save, a delete, a `resync`)
///   puts it back on page 1 (OFFR-ALL-015).
/// - `?edit=new` (with the right) or `?edit=<id>` (once the list holds it)
///   opens the dialog; closing it removes `edit` (OFFR-DEA-022, 023).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' show DealRule;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/menu_options.dart';
import '../shared/offers_cache.dart';
import '../shared/offers_format.dart';
import 'deal_dialog.dart';
import 'deals_data.dart';
import 'deals_format.dart';

class DealsPage extends ConsumerStatefulWidget {
  const DealsPage({this.edit, super.key});

  /// The `edit` search param: a deal id, `new`, or null.
  final String? edit;

  /// Deals a page (the shared table's client paging).
  static const int pageSize = 10;

  @override
  ConsumerState<DealsPage> createState() => _DealsPageState();
}

class _DealsPageState extends ConsumerState<DealsPage> {
  int _page = 0;
  String? _rowsSeen;

  /// The dialog `?edit` opened is up, and for which value.
  String? _dialogFor;
  ValueNotifier<bool>? _dialogOpen;

  /// The `?edit` value whose dialog just closed: not opened again while the
  /// URL still carries it (its removal is on its way).
  String? _closedFor;

  @override
  void dispose() {
    _dialogOpen?.dispose();
    super.dispose();
  }

  // ── The URL ──────────────────────────────────────────────────────────────

  /// `usePageSearch().update`: [edit] set (or removed, when null) on the
  /// current location, in place.
  void _setEdit(String? edit) {
    final current = GoRouterState.of(context).uri;
    final q = Map<String, String>.of(current.queryParameters);
    if (edit == null) {
      q.remove('edit');
    } else {
      q['edit'] = edit;
    }
    GoRouter.of(context).go(
      Uri(path: current.path, queryParameters: q.isEmpty ? null : q).toString(),
    );
  }

  /// Opens (or closes) the dialog `?edit` names (`dialogOpen = edit === "new"
  /// ? canEdit : !!editing`).
  void _syncDialog(String? edit, List<DealRule>? deals, bool canEdit) {
    if (edit != _closedFor) _closedFor = null;
    final open = _dialogFor;
    if (open != null) {
      final stillListed =
          open == 'new' || deals == null || deals.any((d) => d.id == open);
      if (edit != open || !stillListed) {
        final signal = _dialogOpen;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (signal != null && identical(signal, _dialogOpen)) {
            signal.value = false;
          }
        });
      }
      return;
    }
    if (edit == null || edit == _closedFor) return;
    final DealRule? deal;
    if (edit == 'new') {
      if (!canEdit) return;
      deal = null;
    } else {
      deal = deals?.firstWhereOrNull((d) => d.id == edit);
      if (deal == null) return;
    }
    _dialogFor = edit;
    _dialogOpen?.dispose();
    final signal = _dialogOpen = ValueNotifier(true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDealDialog(
        context,
        deal: deal,
        canEdit: canEdit,
        toast: _toast,
        open: signal,
      );
      if (!mounted) return;
      _dialogFor = null;
      _closedFor = edit;
      if (GoRouterState.of(context).uri.queryParameters['edit'] != null) {
        _setEdit(null);
      }
    });
  }

  void _toast(DashToastKind kind, String message) {
    if (!mounted) return;
    DashToast.show(context, message, kind: kind);
  }

  // ── Delete ───────────────────────────────────────────────────────────────

  Future<void> _remove(DealRule d) async {
    final t = ref.read(tProvider);
    final name = translatedName(
      d.name,
      d.nameTranslations,
      ref.read(localeProvider),
    );
    final ok = await showDashConfirm(
      context,
      title: t('deals.deleteTitle', args: {'name': name}),
      description: t('deals.deleteBody'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).menu.deleteDeal(id: d.id);
      _toast(DashToastKind.success, t('deals.deleted'));
      ref.read(realtimeBusProvider).invalidate(combosInvalidationPrefixes);
    } on Object catch (e) {
      _toast(DashToastKind.error, dealErrorText(e, t));
    }
  }

  // ── The table ────────────────────────────────────────────────────────────

  List<DashColumn<DealRule>> _columns(
    Translator t,
    DashFormat f,
    MenuOptions menu,
  ) {
    String rule(DealRule d) => dealRuleText(
      t,
      f,
      kind: d.kind,
      qty: d.qty,
      price: d.price,
      getQty: d.getQty,
      getPercent: d.getPercent,
    );
    String pool(DealRule d) {
      final counts = poolText(t, d.pool, menu);
      return d.rewardPool.isEmpty
          ? counts
          : '$counts → ${poolText(t, d.rewardPool, menu)}';
    }

    String when(DealRule d) {
      final w = d.windows;
      if (w.isEmpty) return t('combos.windows.always');
      if (w.length == 1) {
        return windowSummary(t, w.single, branchName: menu.branchName);
      }
      return t('deals.windowsCount', count: w.length);
    }

    Widget muted(BuildContext context, String text, {int maxLines = 2}) =>
        MadarClippedText(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: DashType.body.copyWith(
            color: context.madarColors.textSecondary,
          ),
        );

    return [
      DashColumn<DealRule>(
        id: 'name',
        label: t('deals.col.name'),
        text: (d) => d.name,
        cell: (context, d) => _DealName(deal: d),
        phone: DashPhoneRole.title,
        hideable: false,
        flex: 3,
        minWidth: 200,
      ),
      DashColumn<DealRule>(
        id: 'rule',
        label: t('deals.col.rule'),
        text: rule,
        cell: (context, d) => MadarClippedText(
          rule(d),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DashType.body.copyWith(color: context.madarColors.textPrimary),
        ),
        flex: 3,
        minWidth: 180,
      ),
      DashColumn<DealRule>(
        id: 'pool',
        label: t('deals.col.pool'),
        text: pool,
        cell: (context, d) => muted(context, pool(d)),
        flex: 3,
        minWidth: 180,
      ),
      DashColumn<DealRule>(
        id: 'when',
        label: t('deals.col.when'),
        text: when,
        cell: (context, d) => muted(context, when(d)),
        flex: 3,
        minWidth: 180,
      ),
      DashColumn<DealRule>(
        id: 'status',
        label: t('combos.col.status'),
        text: (d) => t(d.isActive ? 'common.active' : 'common.inactive'),
        cell: (context, d) => _DealStatus(deal: d),
        flex: 3,
        minWidth: 170,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final canEdit = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuDealsEdit)),
    );
    final q = ref.watch(dealsProvider);
    final menu = ref.watch(menuOptionsProvider);

    final deals = sortedDeals(q.value ?? const []);
    final loading = q.isLoading && !q.hasValue;
    // A failed refetch replaces the rows it had (OFFR-ALL-012).
    final error = q.hasError && !q.isLoading ? q.error : null;

    // Any change of the rows puts the table back on page 1.
    final seen = jsonEncode([for (final d in deals) d.toJson()]);
    if (_rowsSeen != null && seen != _rowsSeen) _page = 0;
    _rowsSeen = seen;
    final pages = math.max(1, (deals.length / DealsPage.pageSize).ceil());
    final page = math.min(_page, pages - 1);
    final shown = deals
        .skip(page * DealsPage.pageSize)
        .take(DealsPage.pageSize)
        .toList();

    _syncDialog(widget.edit, q.hasValue ? deals : null, canEdit);

    Widget newDeal() => DashButton(
      label: t('deals.new'),
      icon: 'plus',
      onPressed: () => _setEdit('new'),
    );

    return DashPageScaffold(
      title: t('deals.title'),
      subtitle: t('deals.subtitle'),
      actions: [if (canEdit) newDeal()],
      body: DashDataTable<DealRule>(
        columns: _columns(t, f, menu),
        rows: shown,
        rowKey: (d) => d.id,
        loading: loading,
        errorMessage: error == null ? null : errorMessage(error, t),
        onRetry: () => ref.invalidate(dealsProvider),
        onRowTap: (d) => _setEdit(d.id),
        rowSemanticLabel: (d) => d.name,
        rowActions: canEdit
            ? (context, d) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DashIconButton(
                    icon: 'pencil',
                    semanticLabel: t('common.edit'),
                    onPressed: () => _setEdit(d.id),
                  ),
                  DashIconButton(
                    icon: 'trash-2',
                    semanticLabel: t('common.delete'),
                    color: context.madarColors.danger,
                    onPressed: () => _remove(d),
                  ),
                ],
              )
            : null,
        rowActionsWidth: DashMetrics.target * 2 + Space.lg,
        pageSize: DealsPage.pageSize,
        pageIndex: page,
        pageCount: pages,
        onPageChanged: (p) => setState(() => _page = p),
        empty: DashEmptyState(
          icon: 'badge-percent',
          title: t('deals.empty'),
          description: t('deals.emptyHint'),
          action: canEdit ? newDeal() : null,
        ),
      ),
    );
  }
}

/// The "Deal" cell: the English name, and the Arabic one right to left
/// under it when there is one (neither is translated: both are shown).
class _DealName extends StatelessWidget {
  const _DealName({required this.deal});

  final DealRule deal;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final ar = arabicOf(deal.nameTranslations);
    final phone = DashBreakpoints.isPhone(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MadarClippedText(
          deal.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (phone ? DashType.sectionTitle : DashType.bodyStrong).copyWith(
            color: c.textPrimary,
          ),
        ),
        if (ar != null)
          MadarClippedText(
            ar,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.rtl,
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}

/// "Active" / "Inactive", and how many branches are set apart from it.
class _DealStatus extends ConsumerWidget {
  const _DealStatus({required this.deal});

  final DealRule deal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final exceptions = deal.branchOverrides.length;
    return Wrap(
      spacing: Space.xs + DashMetrics.hair,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DashStatusPill(
          label: t(deal.isActive ? 'common.active' : 'common.inactive'),
          tone: deal.isActive ? DashTone.success : DashTone.neutral,
        ),
        if (exceptions > 0)
          DashStatusPill(
            label: t('deals.branchExceptions', count: exceptions),
            tone: DashTone.info,
            small: true,
          ),
      ],
    );
  }
}
