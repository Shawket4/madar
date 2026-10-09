/// `/discounts`: the discounts list, its export and the discount dialog
/// (inventory OFFR-DSC rows; web `features/discounts/discounts-page.tsx`);
/// `?edit=<id>|new` opens the dialog. The web gates nothing on this page
/// (OFFR-DSC-003): New, Export, Edit, Delete and the status toggle show to
/// whoever reaches it, and the server refuses.
///
/// - The list is the whole of `GET /discounts` in the server's order (by
///   name), ten a page in the client; a search or any change of the rows (a
///   save, a delete, a toggle, a `resync`) puts it back on page 1
///   (OFFR-ALL-015).
/// - Four counts over the whole list; Export writes every discount, whatever
///   the search shows.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show Discount, UpdateDiscountRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/offers_cache.dart';
import '../shared/offers_format.dart' show translatedName;
import 'discount_dialog.dart';
import 'discounts_data.dart';

class DiscountsPage extends ConsumerStatefulWidget {
  const DiscountsPage({this.edit, super.key});

  /// The `edit` search param: a discount id, `new`, or null.
  final String? edit;

  /// Discounts a page (the shared table's client paging).
  static const int pageSize = 10;

  @override
  ConsumerState<DiscountsPage> createState() => _DiscountsPageState();
}

class _DiscountsPageState extends ConsumerState<DiscountsPage> {
  String _query = '';
  int _page = 0;
  String? _rowsSeen;

  /// Discounts whose status toggle is on its way.
  final Set<String> _toggling = {};
  bool _exporting = false;

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

  /// Opens (or closes) the dialog `?edit` names (`dlgOpen = edit === "new"
  /// || !!editing`): `new` for anyone, an id once the list holds it.
  void _syncDialog(String orgId, String? edit, List<Discount>? discounts) {
    if (edit != _closedFor) _closedFor = null;
    final open = _dialogFor;
    if (open != null) {
      final stillListed =
          open == 'new' ||
          discounts == null ||
          discounts.any((d) => d.id == open);
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
    final Discount? discount;
    if (edit == 'new') {
      discount = null;
    } else {
      discount = discounts?.firstWhereOrNull((d) => d.id == edit);
      if (discount == null) return;
    }
    _dialogFor = edit;
    _dialogOpen?.dispose();
    final signal = _dialogOpen = ValueNotifier(true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDiscountDialog(
        context,
        orgId: orgId,
        discount: discount,
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

  String _name(Discount d) =>
      translatedName(d.name, d.nameTranslations, ref.read(localeProvider));

  // ── Actions ──────────────────────────────────────────────────────────────

  /// OFFR-DSC-013: flips `is_active` at once; no confirm, no success toast.
  Future<void> _toggle(Discount d) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).discounts;
    final bus = ref.read(realtimeBusProvider);
    setState(() => _toggling.add(d.id));
    try {
      await api.updateDiscount(
        id: d.id,
        body: UpdateDiscountRequest(isActive: !d.isActive),
      );
      bus.invalidate(const [OffersPaths.discounts]);
    } on Object catch (e) {
      _toast(DashToastKind.error, discountErrorText(e, t));
    } finally {
      if (mounted) setState(() => _toggling.remove(d.id));
    }
  }

  /// OFFR-DSC-016/017: confirm, delete, refresh, toast.
  Future<void> _remove(Discount d) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('common.confirmDelete', args: {'name': _name(d)}),
      description: t('discounts.deleteConsequence'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).discounts.deleteDiscount(id: d.id);
      invalidateDiscounts(ref);
      _toast(DashToastKind.success, t('discounts.deletedToast'));
    } on Object catch (e) {
      _toast(DashToastKind.error, discountErrorText(e, t));
    }
  }

  /// OFFR-DSC-007/040: every discount, in list order, whatever the search.
  Future<void> _export(List<Discount> discounts) async {
    final t = ref.read(tProvider);
    String type(Discount d) => d.dtype == DiscountType.percentage
        ? t('discounts.percentage')
        : t('discounts.fixed');
    setState(() => _exporting = true);
    final toast = DashToast.loading(context, t('excel.generating'));
    ExportOutcome outcome;
    try {
      final brand = await ref.read(publicBrandProvider.future);
      // `useExportLogo`: the shop's own on the branding tier; blank = Madar's.
      final url = brand?.logoUrl?.trim() ?? '';
      final logo = brand != null && brand.customBranding && url.isNotEmpty
          ? url
          : null;
      outcome = await ref
          .read(exporterProvider)
          .exportToExcel(
            ExcelConfig(
              filename: 'Madar-Discounts',
              logoUrl: logo,
              sheets: [
                ExcelSheet<Discount>(
                  name: t('discounts.title'),
                  title: t('discounts.title'),
                  rows: discounts,
                  columns: [
                    ExcelColumn<Discount>(
                      header: t('discounts.discountName'),
                      accessor: _name,
                      type: ExcelColumnType.text,
                      width: 28,
                    ),
                    ExcelColumn<Discount>(
                      header: t('common.type'),
                      accessor: type,
                      type: ExcelColumnType.text,
                      width: 16,
                    ),
                    ExcelColumn<Discount>(
                      header: t('discounts.value'),
                      accessor: discountExportValue,
                      type: ExcelColumnType.number,
                      width: 14,
                    ),
                    ExcelColumn<Discount>(
                      header: t('common.status'),
                      accessor: (d) => d.isActive
                          ? t('common.active')
                          : t('common.inactive'),
                      type: ExcelColumnType.text,
                      width: 12,
                    ),
                  ],
                ),
              ],
            ),
          );
    } on Object catch (e) {
      outcome = ExportFailed(e);
    }
    toast.update(
      outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
      outcome.message(t),
    );
    if (mounted) setState(() => _exporting = false);
  }

  // ── The table ────────────────────────────────────────────────────────────

  List<DashColumn<Discount>> _columns(Translator t, DashFormat f) => [
    DashColumn<Discount>(
      id: 'name',
      label: t('discounts.discountName'),
      // The search reads the raw English name (OFFR-DSC-041).
      text: (d) => d.name,
      cell: (context, d) => _DiscountName(discount: d, name: _name(d)),
      phone: DashPhoneRole.title,
      hideable: false,
      flex: 3,
      minWidth: 220,
    ),
    DashColumn<Discount>(
      id: 'dtype',
      label: t('common.type'),
      text: (d) => d.dtype,
      cell: (context, d) => _OutlineBadge(
        d.dtype == DiscountType.percentage
            ? t('discounts.percentage')
            : t('discounts.fixed'),
      ),
      hideable: false,
      flex: 2,
      minWidth: 140,
    ),
    DashColumn<Discount>(
      id: 'value',
      label: t('discounts.value'),
      text: (d) => '${d.value}',
      cell: (context, d) => MadarClippedText(
        discountValueLabel(d, f),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DashType.monoMedium.copyWith(
          color: context.madarColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      numeric: true,
      flex: 2,
      minWidth: 120,
    ),
    DashColumn<Discount>(
      id: 'status',
      label: t('common.status'),
      text: (d) => t(d.isActive ? 'common.active' : 'common.inactive'),
      cell: (context, d) => _StatusToggle(
        active: d.isActive,
        pending: _toggling.contains(d.id),
        label: t(d.isActive ? 'common.active' : 'common.inactive'),
        semanticLabel: t(
          d.isActive ? 'discounts.deactivate' : 'discounts.activate',
        ),
        onTap: () => _toggle(d),
      ),
      hideable: false,
      searchable: false,
      flex: 2,
      minWidth: 120,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final orgId = ref.watch(orgIdProvider);
    if (orgId == null) {
      return DashPageScaffold(
        title: t('discounts.title'),
        body: DashEmptyState(icon: 'tag', title: t('discounts.pickOrg')),
      );
    }

    final q = ref.watch(discountsProvider(orgId));
    final discounts = q.value ?? const <Discount>[];
    final firstLoad = q.isLoading && !q.hasValue && !q.hasError;
    final loading = q.isLoading && !q.hasValue;
    // A failed refetch replaces the rows it had (OFFR-ALL-012).
    final error = q.hasError && !q.isLoading ? q.error : null;

    // Any change of the rows puts the table back on page 1.
    final seen = jsonEncode([for (final d in discounts) d.toJson()]);
    if (_rowsSeen != null && seen != _rowsSeen) _page = 0;
    _rowsSeen = seen;
    final matching = [
      for (final d in discounts)
        if (discountMatches(d, _query)) d,
    ];
    final pages = math.max(
      1,
      (matching.length / DiscountsPage.pageSize).ceil(),
    );
    final page = math.min(_page, pages - 1);
    final shown = matching
        .skip(page * DiscountsPage.pageSize)
        .take(DiscountsPage.pageSize)
        .toList();

    _syncDialog(orgId, widget.edit, q.hasValue ? discounts : null);

    final phone = DashBreakpoints.isPhone(context);
    final stats = _StatGrid(
      loading: firstLoad,
      cards: [
        (t('common.total'), discounts.length),
        (t('common.active'), discounts.where((d) => d.isActive).length),
        (
          t('discounts.percentage'),
          discounts.where((d) => d.dtype == DiscountType.percentage).length,
        ),
        (
          t('discounts.fixed'),
          discounts.where((d) => d.dtype == DiscountType.fixed).length,
        ),
      ],
    );

    final search = CallbackShortcuts(
      // `type="search"`: Esc empties it.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
          _query = '';
          _page = 0;
        }),
      },
      child: DashSearchInput(
        value: _query,
        width: phone ? double.infinity : DashMetrics.searchWidth,
        placeholder: t('common.search'),
        onChanged: (v) => setState(() {
          _query = v;
          _page = 0;
        }),
      ),
    );

    final table = DashDataTable<Discount>(
      columns: _columns(t, f),
      rows: shown,
      rowKey: (d) => d.id,
      loading: loading,
      errorMessage: error == null ? null : discountErrorText(error, t),
      onRetry: () => ref.invalidate(discountsProvider(orgId)),
      onRowTap: (d) => _setEdit(d.id),
      rowSemanticLabel: _name,
      toolbar: search,
      rowActions: (context, d) => Row(
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
      ),
      rowActionsWidth: DashMetrics.target * 2 + Space.lg,
      pageSize: DiscountsPage.pageSize,
      pageIndex: page,
      pageCount: pages,
      onPageChanged: (p) => setState(() => _page = p),
      // A search that matches nothing reads the same (OFFR-DSC-009).
      empty: DashEmptyState(
        icon: 'tag',
        title: t('discounts.empty'),
        description: t('discounts.emptyHint'),
      ),
    );

    return DashPageScaffold(
      title: t('discounts.title'),
      subtitle: t('discounts.subtitle'),
      actions: [
        DashExportButton(
          onExport: () => _export(discounts),
          loading: _exporting,
          enabled: discounts.isNotEmpty,
        ),
        DashButton(
          label: t('discounts.new'),
          icon: 'plus',
          onPressed: () => _setEdit('new'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xl,
        children: [stats, table],
      ),
    );
  }
}

/// The four counts: two a row, four from 1024 (`grid-cols-2 lg:grid-cols-4`).
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.loading, required this.cards});

  final bool loading;
  final List<(String, int)> cards;

  @override
  Widget build(BuildContext context) {
    final cols = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg ? 4 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        for (final row in cards.slices(cols))
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                for (final (label, value) in row)
                  Expanded(
                    child: DashStatCard(
                      label: label,
                      value: value,
                      loading: loading,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The name cell: a 32 tile with the type's glyph, then the name (Arabic
/// when the UI is Arabic and one exists).
class _DiscountName extends StatelessWidget {
  const _DiscountName({required this.discount, required this.name});

  final Discount discount;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final phone = DashBreakpoints.isPhone(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        ExcludeSemantics(
          child: Container(
            width: Space.xxl,
            height: Space.xxl,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.muted,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: MadarIcon(
              discount.dtype == DiscountType.percentage
                  ? 'percent'
                  : 'banknote',
              size: IconSize.xs,
              tint: c.textSecondary,
            ),
          ),
        ),
        Flexible(
          child: MadarClippedText(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (phone ? DashType.sectionTitle : DashType.bodyStrong)
                .copyWith(color: c.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// The Status cell: the pill IS the button (OFFR-DSC-013); a tap flips the
/// discount and never opens the row; disabled while its request runs.
class _StatusToggle extends StatelessWidget {
  const _StatusToggle({
    required this.active,
    required this.pending,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final bool active;
  final bool pending;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DashPressable(
    onTap: pending ? null : onTap,
    enabled: !pending,
    semanticLabel: semanticLabel,
    excludeChildSemantics: true,
    pressScale: false,
    builder: (context, s) => ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: DashMetrics.target,
        minWidth: DashMetrics.target,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1,
        child: Opacity(
          opacity: pending ? 0.5 : 1,
          child: DashStatusPill(
            label: label,
            tone: active ? DashTone.success : DashTone.neutral,
          ),
        ),
      ),
    ),
  );
}

/// An outline badge (`<Badge variant="outline">`): a hairline, no fill.
class _OutlineBadge extends StatelessWidget {
  const _OutlineBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.hairline),
      ),
      child: Text(
        label,
        style: DashType.smallMedium.copyWith(color: c.textPrimary),
      ),
    );
  }
}
