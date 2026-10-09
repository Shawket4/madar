/// `/menu/combos`: the combos list (inventory OFFR-CMB rows; web
/// `features/combos/combos-page.tsx`). Every combo (a menu item of kind
/// `combo`) with what an owner checks at a glance: price, slots, whether it
/// is a fixed bundle, whether it can be sold now, and its default margin with
/// a warning chip when the server has something to say.
///
/// - Gate: `menu.items.read` shows the list (`OffersPageGate`, the
///   account-specific Restricted body); `menu.combos.edit` adds New combo and
///   the row's Edit and Delete; any of `org.settings.read`,
///   `menu.combos.edit` shows the "Channels and margin" link.
/// - The list is the server's (`GET /combos`), 25 a page; search (300 ms
///   debounce), category and status go to the server and return to page 1.
/// - Search, filters and page live only in this page's state: coming back
///   from the editor starts afresh (OFFR-CMB-034).
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart' show Category, ComboSummary;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/offers_cache.dart';
import '../shared/offers_format.dart';
import '../shared/offers_page_gate.dart';
import 'combos_providers.dart';

/// The web's fixed sizes on this page.
abstract final class CombosMetrics {
  /// The search box from 640 wide (`sm:w-60`).
  static const double search = Space.xl * 10;

  /// The Category select's floor (`min-w-40`).
  static const double categorySelect = Space.xxl * 5;

  /// The Status select's floor (`min-w-32`).
  static const double statusSelect = Space.xxl * 4;

  /// The combo's thumbnail tile (`size-10`).
  static const double thumb = Space.xxl + Space.sm;
}

class CombosPage extends ConsumerWidget {
  const CombosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return OffersPageGate(
      title: t('combos.title'),
      caps: const [Cap.menuItemsRead],
      who: t('combos.noAccess'),
      child: const _CombosList(),
    );
  }
}

class _CombosList extends ConsumerStatefulWidget {
  const _CombosList();

  @override
  ConsumerState<_CombosList> createState() => _CombosListState();
}

class _CombosListState extends ConsumerState<_CombosList> {
  /// The debounced search (trimmed; empty = none).
  String _q = '';
  String? _category;
  bool? _active;

  /// 0-based.
  int _page = 0;

  bool get _filtered => _q.isNotEmpty || _category != null || _active != null;

  CombosQuery get _key => (
    q: _q.isEmpty ? null : _q,
    categoryId: _category,
    isActive: _active,
    page: _page + 1,
  );

  /// Any change of the search, the category or the status returns to page 1.
  void _filter(void Function() change) => setState(() {
    change();
    _page = 0;
  });

  void _open(String id) => context.go('/menu/combos/$id');

  Future<void> _remove(ComboSummary c) async {
    final t = ref.read(tProvider);
    final name = translatedName(
      c.name,
      c.nameTranslations,
      ref.read(localeProvider),
    );
    final ok = await showDashConfirm(
      context,
      title: t('combos.deleteTitle', args: {'name': name}),
      description: t('combos.deleteBody'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    try {
      // A combo is a menu item: it is deleted through the item endpoint.
      await api.menu.deleteMenuItem(id: c.id);
      if (mounted) DashToast.success(context, t('combos.deleted'));
      bus.invalidate(combosInvalidationPrefixes);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final lang = ref.watch(localeProvider);
    final orgId = ref.watch(orgIdProvider);
    final canEdit = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuCombosEdit)),
    );
    final canSettings = ref.watch(
      authzProvider.select(
        (a) => a.canAny(const [Cap.orgSettingsRead, Cap.menuCombosEdit]),
      ),
    );

    // Asked only with an org in scope (the page itself needs the right).
    final key = _key;
    final list = orgId == null ? null : ref.watch(combosListProvider(key));
    final cats = orgId == null
        ? const <Category>[]
        : ref.watch(comboCategoriesProvider(orgId)).value ?? const [];
    final names = {
      for (final c in cats)
        c.id: translatedName(c.name, c.nameTranslations, lang),
    };
    String categoryName(String? id) => id == null ? '—' : (names[id] ?? '—');

    final page = list?.value;
    // A skeleton only while there is nothing to show; a failure (kept while
    // its Retry runs) replaces the rows it had (OFFR-ALL-012).
    final error = list?.error;
    final loading =
        list != null && list.isLoading && !list.hasValue && error == null;

    // A delete that empties the last page steps back to the new last page.
    if (page != null &&
        !list!.isLoading &&
        error == null &&
        page.data.isEmpty &&
        page.total > 0 &&
        _page > 0) {
      final last = math.max(0, page.totalPages - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _page > last) setState(() => _page = last);
      });
    }

    Widget newCombo() => DashButton(
      label: t('combos.new'),
      icon: 'plus',
      onPressed: () => _open('new'),
    );

    return DashPageScaffold(
      title: t('combos.title'),
      subtitle: t('combos.subtitle'),
      actions: [
        if (canSettings)
          DashButton(
            label: t('combos.channelsLink'),
            trailingIcon: DashIcon.arrowForward(context),
            variant: DashButtonVariant.ghost,
            size: DashButtonSize.compact,
            onPressed: () => context.go('/settings/combos'),
          ),
        if (canEdit) newCombo(),
      ],
      filters: _Filters(
        q: _q,
        onSearch: (v) => _filter(() => _q = v),
        categories: [
          for (final c in cats)
            DashOption(value: c.id, label: names[c.id] ?? c.name),
        ],
        category: _category,
        onCategory: (v) => _filter(() => _category = v),
        active: _active,
        onActive: (v) => _filter(() => _active = v),
      ),
      body: DashDataTable<ComboSummary>(
        columns: _columns(t, f, categoryName),
        rows: error == null ? page?.data ?? const [] : const [],
        rowKey: (c) => c.id,
        loading: loading,
        errorMessage: error == null ? null : errorMessage(error, t),
        onRetry: () => ref.invalidate(combosListProvider(key)),
        onRowTap: (c) => _open(c.id),
        rowSemanticLabel: (c) => c.name,
        rowActions: (context, c) => canEdit
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DashIconButton(
                    icon: 'pencil',
                    semanticLabel: t('common.edit'),
                    onPressed: () => _open(c.id),
                  ),
                  DashIconButton(
                    icon: 'trash-2',
                    semanticLabel: t('common.delete'),
                    color: context.madarColors.danger,
                    onPressed: () => _remove(c),
                  ),
                ],
              )
            : const SizedBox.shrink(),
        rowActionsWidth: DashMetrics.target * 2 + Space.lg,
        pageSize: combosPerPage,
        pageIndex: _page,
        pageCount: page?.totalPages ?? 0,
        onPageChanged: (p) => setState(() => _page = p),
        empty: DashEmptyState(
          icon: 'utensils-crossed',
          title: t(_filtered ? 'combos.emptyFiltered' : 'combos.empty'),
          description: _filtered ? null : t('combos.emptyHint'),
          action: canEdit && !_filtered ? newCombo() : null,
        ),
      ),
    );
  }

  List<DashColumn<ComboSummary>> _columns(
    Translator t,
    DashFormat f,
    String Function(String? id) categoryName,
  ) => [
    DashColumn<ComboSummary>(
      id: 'name',
      label: t('combos.col.name'),
      text: (c) => c.name,
      cell: (context, c) => ComboNameCell(combo: c),
      phone: DashPhoneRole.title,
      hideable: false,
      flex: 5,
      minWidth: 240,
    ),
    DashColumn<ComboSummary>(
      id: 'category',
      label: t('combos.col.category'),
      text: (c) => categoryName(c.categoryId),
      cell: (context, c) => MadarClippedText(
        categoryName(c.categoryId),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DashType.body.copyWith(
          color: context.madarColors.textSecondary,
        ),
      ),
      flex: 2,
      minWidth: 140,
    ),
    DashColumn<ComboSummary>(
      id: 'price',
      label: t('combos.col.price'),
      numeric: true,
      text: (c) => f.fmtMoney(c.price),
      cell: (context, c) => Text(
        dashFigure(f.fmtMoney(c.price)),
        maxLines: 1,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      flex: 2,
      minWidth: 130,
    ),
    DashColumn<ComboSummary>(
      id: 'slots',
      label: t('combos.col.slots'),
      numeric: true,
      text: (c) => '${c.slotCount}',
      flex: 1,
      minWidth: 80,
    ),
    DashColumn<ComboSummary>(
      id: 'margin',
      label: t('combos.col.margin'),
      numeric: true,
      text: (c) => fmtRate(f, c.marginDefault),
      cell: (context, c) => Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.xs + DashMetrics.hair,
        runSpacing: Space.xs,
        children: [
          if (c.warningCount > 0)
            DashStatusPill(
              label: t('combos.warningCount', count: c.warningCount),
              tone: DashTone.warning,
              icon: 'alert-triangle',
              small: true,
            ),
          Text(dashFigure(fmtRate(f, c.marginDefault))),
        ],
      ),
      flex: 3,
      minWidth: 180,
    ),
    DashColumn<ComboSummary>(
      id: 'status',
      label: t('combos.col.status'),
      text: (c) => _statusWord(t, c).$1,
      cell: (context, c) {
        final (label, tone) = _statusWord(t, c);
        return DashStatusPill(label: label, tone: tone);
      },
      flex: 2,
      minWidth: 170,
    ),
  ];
}

/// Inactive; else on sale now or not (outside its windows, nothing to sell).
(String, DashTone) _statusWord(Translator t, ComboSummary c) {
  if (!c.isActive) return (t('common.inactive'), DashTone.neutral);
  return c.availableNow
      ? (t('combos.availableNow'), DashTone.success)
      : (t('combos.notNow'), DashTone.accent);
}

/// The row under the header: search, Category, Status (the web's `below`).
class _Filters extends ConsumerWidget {
  const _Filters({
    required this.q,
    required this.onSearch,
    required this.categories,
    required this.category,
    required this.onCategory,
    required this.active,
    required this.onActive,
  });

  final String q;
  final ValueChanged<String> onSearch;
  final List<DashOption<String>> categories;
  final String? category;
  final ValueChanged<String?> onCategory;
  final bool? active;
  final ValueChanged<bool?> onActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final search = DashSearchInput(
      value: q,
      onChanged: onSearch,
      placeholder: t('combos.searchPlaceholder'),
      debounce: DashSearchInput.listDelay,
    );
    final selects = [
      DashFilterSelect<String>(
        label: t('combos.col.category'),
        allLabel: t('combos.allCategories'),
        options: categories,
        value: category,
        onChanged: onCategory,
        minWidth: CombosMetrics.categorySelect,
      ),
      DashFilterSelect<bool>(
        label: t('combos.col.status'),
        allLabel: t('combos.allStatuses'),
        options: [
          DashOption(value: true, label: t('common.active')),
          DashOption(value: false, label: t('common.inactive')),
        ],
        value: active,
        onChanged: onActive,
        minWidth: CombosMetrics.statusSelect,
      ),
    ];
    // Full width under 640 (`w-full sm:w-60`), the selects wrapping after.
    final narrow = MediaQuery.sizeOf(context).width < DashBreakpoints.sm;
    return Semantics(
      container: true,
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.sm,
              children: [
                search,
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: selects,
                ),
              ],
            )
          : Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: CombosMetrics.search, child: search),
                ...selects,
              ],
            ),
    );
  }
}

/// The "Combo" cell (and the phone card's title): the thumbnail, the English
/// name (never translated) with "Fixed" for a fixed bundle, and the Arabic
/// name right to left under it when there is one.
class ComboNameCell extends ConsumerWidget {
  const ComboNameCell({required this.combo, super.key});

  final ComboSummary combo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final ar = arabicOf(combo.nameTranslations);
    return Row(
      spacing: Space.md,
      children: [
        ComboThumb(url: combo.imageUrl),
        Flexible(
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  spacing: Space.xs + DashMetrics.hair,
                  children: [
                    Flexible(
                      child: MadarClippedText(
                        combo.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashType.bodyStrong.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    if (combo.isFixed) DashBadge(t('combos.fixed')),
                  ],
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
            ),
          ),
        ),
      ],
    );
  }
}

/// The 40 tile: the combo's image, or a muted fork-and-knife.
class ComboThumb extends StatelessWidget {
  const ComboThumb({required this.url, super.key});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final glyph = Center(
      child: DashIcon(
        'utensils-crossed',
        size: IconSize.sm,
        color: c.textSecondary,
      ),
    );
    return Container(
      width: CombosMetrics.thumb,
      height: CombosMetrics.thumb,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: url == null || url!.isEmpty
          ? glyph
          : Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => glyph,
            ),
    );
  }
}
