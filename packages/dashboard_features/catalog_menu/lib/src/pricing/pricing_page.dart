/// `/menu/pricing`: the pricing and availability matrix (MENU-PRC rows).
/// Web: `features/menu/pricing/pricing-availability-page.tsx`.
///
/// Every priceable target (an item's sizes, an add-on) × every scope of the
/// ONE branch in the top bar (In-store and the four delivery channels). Edits
/// are staged per cell and written together from the floating save bar.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        AddonItem,
        Branch,
        BranchAddonOverride,
        ChannelAddonOverride,
        MenuItemWithCosts,
        PaginatedAddonItems,
        PaginatedMenuItems,
        SizeOut,
        StudioAggregate;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../items/items_providers.dart';
import '../items/items_widgets.dart' show MenuImageTile;
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import '../shared/unsaved_bar.dart';
import '../studio/studio_providers.dart';
import 'pricing_model.dart';
import 'pricing_providers.dart';
import 'pricing_widgets.dart';

class PricingAvailabilityPage extends ConsumerStatefulWidget {
  const PricingAvailabilityPage({super.key});

  @override
  ConsumerState<PricingAvailabilityPage> createState() => _PricingPageState();
}

/// An expanded item's name and size targets, kept after it collapses or its
/// page goes so Save still writes its cells (`registerTargets`).
typedef _ItemEntry = ({String name, List<PricingTarget> targets});

class _PricingPageState extends ConsumerState<PricingAvailabilityPage>
    with DashRememberedState {
  String _tab = 'items';
  int _itemsPage = 0;
  String _itemsSearch = '';
  int _addonsPage = 0;
  String _addonsSearch = '';

  // ── memory: the tab, searches and pages come back with the page
  // (`DashRememberedState`); staged cells are not filters. ──

  @override
  String get memoryKey => 'menu.pricing';

  @override
  Map<String, Object?> get rememberedValues => {
    'tab': _tab,
    'itemsPage': _itemsPage,
    'itemsSearch': _itemsSearch,
    'addonsPage': _addonsPage,
    'addonsSearch': _addonsSearch,
  };

  @override
  void restoreRemembered(DashMemo m) {
    _tab = m.string('tab') == 'addons' ? 'addons' : 'items';
    _itemsPage = m.getOr('itemsPage', 0);
    _itemsSearch = m.getOr('itemsSearch', '');
    _addonsPage = m.getOr('addonsPage', 0);
    _addonsSearch = m.getOr('addonsSearch', '');
  }

  /// Staged cells by `cellKey` (`useDirtyCells`).
  final Map<String, DraftCell> _drafts = {};

  /// Cells staged by "Remove override" and not edited since: Save deletes
  /// their rows.
  final Set<String> _cleared = {};

  /// Items expanded on the page shown.
  final Set<String> _open = {};
  final Map<String, _ItemEntry> _items = {};

  /// Every add-on shown so far, so a cell staged on another page is saved
  /// too (MENU-PRC-028).
  final Map<String, AddonItem> _addons = {};
  bool _saving = false;

  /// The last lists that arrived, shown while the next page or search loads
  /// (`placeholderData: keepPreviousData`).
  PaginatedMenuItems? _lastItems;
  PaginatedAddonItems? _lastAddons;

  String _name(String name, Object? tr) =>
      translatedName(name, tr, ref.read(localeProvider));

  DraftCell _draftFor(PricingCol col, PricingTarget t) =>
      _drafts[pricingCellKey(col, t.targetId)] ?? pristineDraft(t.resolve(col));

  void _set(PricingCol col, PricingTarget t, {String? price, bool? available}) {
    final key = pricingCellKey(col, t.targetId);
    final r = t.resolve(col);
    final cur = _drafts[key] ?? pristineDraft(r);
    final next = (
      price: price ?? cur.price,
      available: available ?? cur.available,
    );
    setState(() {
      _cleared.remove(key);
      // Dropped once it matches the server again: the count stays honest.
      if (isDirtyCell(next, r)) {
        _drafts[key] = next;
      } else {
        _drafts.remove(key);
      }
    });
  }

  /// "Remove override": a blank price, marked for deletion.
  void _clear(PricingCol col, PricingTarget t) {
    final key = pricingCellKey(col, t.targetId);
    setState(() {
      _drafts[key] = clearedDraft(t.resolve(col));
      _cleared.add(key);
    });
  }

  void _discard() => setState(() {
    _drafts.clear();
    _cleared.clear();
  });

  bool _anyDirty(Iterable<PricingTarget> targets) => targets.any(
    (t) => pricingCols.any(
      (c) => _drafts.containsKey(pricingCellKey(c, t.targetId)),
    ),
  );

  // ── reads ───────────────────────────────────────────────────────────────

  CatalogQuery _itemsKey(String org) => pricingCatalogKey(
    org,
    _itemsSearch.isEmpty ? null : _itemsSearch,
    _itemsPage + 1,
  );

  PricingPageKey _addonsKey(String org) => pricingAddonKey(
    org,
    _addonsSearch.isEmpty ? null : _addonsSearch,
    _addonsPage + 1,
  );

  /// The add-on override reads, by add-on id ([watch] in build, read in
  /// Save).
  ({
    Map<String, BranchAddonOverride> branch,
    Map<String, Map<String, ChannelAddonOverride>> channels,
  })
  _addonOverrides(String branchId, {bool watch = true}) {
    List<T> get<T>(FutureProvider<List<T>> p) =>
        (watch ? ref.watch(p) : ref.read(p)).value ?? <T>[];
    final b = get(branchAddonOverridesProvider(branchId));
    return (
      branch: {for (final o in b) o.addonItemId: o},
      channels: {
        for (final ch in pricingChannels)
          ch: {
            for (final o in get(
              channelAddonOverridesProvider((branchId: branchId, channel: ch)),
            ))
              o.addonItemId: o,
          },
      },
    );
  }

  // ── save ────────────────────────────────────────────────────────────────

  Future<void> _save(String branchId) async {
    final t = ref.read(tProvider);
    final ovr = _addonOverrides(branchId, watch: false);
    final pending = [
      for (final e in _items.values)
        ...collectPending(e.targets, e.name, _drafts, cleared: _cleared),
      for (final a in _addons.values)
        ...collectPending(
          [addonTarget(a, ovr.branch, ovr.channels)],
          _name(a.name, a.nameTranslations),
          _drafts,
          cleared: _cleared,
        ),
    ];
    // A staged cell a refresh made match the server again is no change: it
    // goes (the web keeps counting it and Save does nothing).
    final live = {for (final p in pending) p.key};
    if (live.length != _drafts.length) {
      setState(() {
        _drafts.removeWhere((k, _) => !live.contains(k));
        _cleared.retainWhere(_drafts.containsKey);
      });
    }
    if (pending.isEmpty) return;
    final bad = firstInvalidLabel(pending);
    if (bad != null) {
      DashToast.error(
        context,
        t('menu.pricing.invalidPriceFor', args: {'name': bad}),
      );
      return;
    }
    setState(() => _saving = true);
    final api = ref.read(apiProvider).menu;
    // Taken before the writes: the refresh and the toast happen even if the
    // page closes meanwhile (the shell's navigator outlives it).
    final invalidate = ref.menuInvalidate;
    final toasts = Navigator.of(context).context;
    final results = await Future.wait([
      for (final cell in pending)
        () async {
          final plan = planCell(cell, branchId);
          if (plan == null) return (cell: cell, error: null);
          try {
            if (plan.put) {
              await api.putPriceOverride(body: plan.body);
            } else {
              await api.deletePriceOverride(body: plan.body);
            }
            return (cell: cell, error: null);
          } on Object catch (e) {
            return (cell: cell, error: e);
          }
        }(),
    ]);
    invalidate.pricingOverrides();
    final failed = [
      for (final r in results)
        if (r.error != null) r,
    ];
    if (mounted) {
      setState(() {
        _saving = false;
        // Only what was written and not edited since goes: a cell typed
        // while the save ran stays staged (the web drops it).
        for (final r in results) {
          final k = r.cell.key;
          if (r.error == null &&
              _drafts[k] == r.cell.draft &&
              _cleared.contains(k) == r.cell.cleared) {
            _drafts.remove(k);
            _cleared.remove(k);
          }
        }
      });
    }
    if (!toasts.mounted) return;
    if (failed.isEmpty) {
      DashToast.success(
        toasts,
        t('menu.pricing.savedN', count: pending.length),
      );
    } else {
      DashToast.error(
        toasts,
        t(
          'menu.pricing.savedPartial',
          args: {'ok': pending.length - failed.length, 'failed': failed.length},
        ),
        description: errorMessage(failed.first.error, t),
      );
    }
  }

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final scope = ref.watch(currentScopeProvider);
    final org = scope.orgId;
    final branchId = scope.branchId;
    // Another branch is another override set: staged edits go.
    ref.listen(
      currentScopeProvider.select((s) => s.branchId),
      (_, _) => _discard(),
    );

    if (org == null) {
      return DashPageScaffold(
        title: t('menu.pricing.title'),
        subtitle: t('menu.pricing.matrixSubtitle'),
        body: DashEmptyState(icon: 'store', title: t('menu.pricing.pickOrg')),
      );
    }

    final branches = ref.watch(branchesProvider);
    final branchesLoading = branches.awaitingFirst;
    final branch = branches.value?.where((b) => b.id == branchId).firstOrNull;
    final phone = DashBreakpoints.isPhone(context);

    Widget body;
    Widget? toolbar;
    if (branchesLoading) {
      body = const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          DashSkeleton(width: PricingMetrics.barSkeleton, height: Space.xxl),
          DashSkeleton(height: PricingMetrics.skeleton, radius: Radii.xxl),
        ],
      );
    } else if (branchId == null) {
      body = DashEmptyState(
        icon: 'store',
        title: t('menu.pricing.pickBranchTitle'),
        description: t('menu.pricing.pickBranchHint'),
      );
    } else {
      // Both tabs' reads fire on mount, whichever tab shows (as the web's).
      ref.watch(menuCatalogProvider(_itemsKey(org)));
      ref.watch(pricingAddonCatalogProvider(_addonsKey(org)));
      _addonOverrides(branchId);
      body = _tab == 'items'
          ? _itemsTab(t, org, branchId, phone)
          : _addonsTab(t, org, branchId, phone);
      toolbar = _toolbar(t, branch, phone);
    }

    final count = _drafts.length;
    return MenuUnsavedBarHost(
      bar: count == 0 || branchId == null
          ? null
          : MenuUnsavedBar(
              countText: t('menu.pricing.unsavedN', count: count),
              discardLabel: t('menu.pricing.discard'),
              saveLabel: t('common.save'),
              saving: _saving,
              onDiscard: _discard,
              onSave: () => _save(branchId),
            ),
      child: DashPageScaffold(
        title: t('menu.pricing.title'),
        subtitle: t('menu.pricing.matrixSubtitle'),
        filters: toolbar,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            // Keeps the last row clear of the floating bar (`h-16`).
            if (count > 0) const SizedBox(height: Space.xxl * 2),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(Translator t, Branch? branch, bool phone) {
    final c = context.madarColors;
    final items = _tab == 'items';
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.md,
      runSpacing: Space.md,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            DashSegmentedControl<String>(
              value: _tab,
              onChanged: (v) => setState(() {
                _tab = v;
                _open.clear();
              }),
              options: [
                DashOption(value: 'items', label: t('menu.pricing.menuItems')),
                DashOption(
                  value: 'addons',
                  label: t('menu.pricing.addonItems'),
                ),
              ],
            ),
            DashSearchInput(
              value: items ? _itemsSearch : _addonsSearch,
              placeholder: t('common.search'),
              debounce: DashSearchInput.listDelay,
              width: phone ? null : Space.xxl * 8,
              // A new search starts at page 1 (MENU-PRC-030).
              onChanged: (q) => setState(() {
                if (items) {
                  _itemsSearch = q;
                  _itemsPage = 0;
                } else {
                  _addonsSearch = q;
                  _addonsPage = 0;
                }
              }),
            ),
            if (branch != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs + DashMetrics.hair,
                children: [
                  DashIcon('store', size: IconSize.xs, color: c.textSecondary),
                  Text(
                    branch.name,
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
          ],
        ),
        const PricingLegend(),
      ],
    );
  }

  Widget _pager(
    int page,
    int count,
    ValueChanged<int> onChanged,
    ValueChanged<int> onIntent,
  ) => count > 1
      ? Padding(
          padding: const EdgeInsets.only(top: Space.lg),
          child: DashPagination(
            pageIndex: page,
            pageCount: count,
            onChanged: onChanged,
            onIntent: onIntent,
          ),
        )
      : const SizedBox.shrink();

  // ── items tab ───────────────────────────────────────────────────────────

  Widget _itemsTab(Translator t, String org, String branchId, bool phone) {
    final key = _itemsKey(org);
    final q = ref.watch(menuCatalogProvider(key));
    if (q.value case final v?) _lastItems = v;
    // The web's `isError`: a failed read replaces the rows shown, but never
    // while Riverpod is still retrying.
    if (q.hasError && !q.retrying) {
      return DashErrorState(
        title: t('menu.pricing.loadError'),
        message: errorMessage(q.error, t),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(menuCatalogProvider(key)),
      );
    }
    // The last page stays up while the next loads, but never an empty one.
    final data = q.value ?? _lastItems;
    if (data == null || (!q.hasValue && data.data.isEmpty)) {
      return const DashSkeleton(
        height: PricingMetrics.skeleton,
        radius: Radii.xxl,
      );
    }
    final list = data.data;
    // A row that left the page closes, as the web unmounts it.
    _open.retainWhere((id) => list.any((m) => m.id == id));
    final Widget content;
    if (list.isEmpty) {
      content = DashEmptyState(
        icon: 'utensils-crossed',
        title: t('menu.pricing.noItems'),
      );
    } else {
      final rows = [for (final m in list) _itemState(m, branchId)];
      content = phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [for (final r in rows) _itemCard(t, r)],
            )
          : PricingMatrix(
              rows: (w, sticky) => [
                _head(t, w, sticky, t('menu.pricing.itemColumn')),
                for (final r in rows) ..._itemRows(t, r, w, sticky),
              ],
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        content,
        _pager(
          _itemsPage,
          data.totalPages,
          (p) => setState(() => _itemsPage = p),
          (p) => ref.warm(
            menuCatalogProvider(pricingCatalogKey(org, key.search, p + 1)),
          ),
        ),
      ],
    );
  }

  /// One item's view: open or not, its studio read and its targets.
  _ItemView _itemState(MenuItemWithCosts m, String branchId) {
    final name = _name(m.name, m.nameTranslations);
    final open = _open.contains(m.id);
    AsyncValue<StudioAggregate>? studio;
    List<(SizeOut, PricingTarget)>? sizes;
    if (open) {
      final q = ref.watch(menuStudioProvider(m.id));
      studio = q;
      if (q.value case final s?) {
        sizes = sizeTargets(s, branchId);
        _items[m.id] = (name: name, targets: [for (final e in sizes) e.$2]);
      }
    }
    return (
      item: m,
      name: name,
      open: open,
      studio: studio,
      sizes: sizes,
      dirty: _anyDirty(_items[m.id]?.targets ?? const []),
    );
  }

  /// Opening an item reads its studio: warmed on intent (closing reads
  /// nothing).
  VoidCallback? _studioWarmer(_ItemView r) =>
      r.open ? null : () => ref.warm(menuStudioProvider(r.item.id));

  void _toggle(String id) => setState(() {
    if (!_open.remove(id)) _open.add(id);
  });

  Widget _head(Translator t, MatrixWidths w, StickyRow sticky, String first) {
    final c = context.madarColors;
    final style = DashType.smallMedium.copyWith(color: c.textSecondary);
    return sticky(
      MatrixCell(
        width: w.first,
        topBorder: false,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        child: Text(first, style: style),
      ),
      [
        MatrixCell(
          width: w.catalog,
          topBorder: false,
          color: c.muted.withValues(alpha: 0.4),
          child: Text.rich(
            TextSpan(
              text: t('menu.pricing.col_catalog'),
              children: [
                TextSpan(
                  text: ' (${t('menu.pricing.readonly')})',
                  style: style.copyWith(fontWeight: FontWeight.w400),
                ),
              ],
            ),
            style: style.copyWith(color: c.textMuted),
          ),
        ),
        for (final col in pricingCols)
          MatrixCell(
            width: w.cell,
            topBorder: false,
            startBorder: true,
            color: c.muted.withValues(alpha: 0.4),
            child: Text(t(pricingColKey(col)), style: style),
          ),
      ],
      background: c.muted.withValues(alpha: 0.4),
    );
  }

  List<Widget> _itemRows(
    Translator t,
    _ItemView r,
    MatrixWidths w,
    StickyRow sticky,
  ) {
    final rest = matrixTotal(w) - w.first;
    final head = sticky(
      MatrixCell(
        width: w.first,
        padding: EdgeInsets.zero,
        child: PricingItemHead(
          item: r.item,
          name: r.name,
          open: r.open,
          dirty: r.dirty,
          onToggle: () => _toggle(r.item.id),
          onIntent: _studioWarmer(r),
        ),
      ),
      [MatrixCell(width: rest, child: const SizedBox.shrink())],
    );
    if (!r.open) return [head];
    final total = matrixTotal(w);
    Widget message(Widget child) => MatrixCell(
      width: total,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(Space.md),
      child: child,
    );
    final studio = r.studio!;
    final sizes = r.sizes;
    final muted = DashType.body.copyWith(
      color: context.madarColors.textSecondary,
    );
    if (studio.hasError && !studio.retrying) {
      return [head, message(Text(t('menu.pricing.loadError'), style: muted))];
    }
    if (sizes == null) {
      return [head, message(const DashSkeleton(height: Space.xxl + Space.xs))];
    }
    if (sizes.isEmpty) {
      return [head, message(Text(t('menu.pricing.noSizes'), style: muted))];
    }
    final c = context.madarColors;
    return [
      head,
      for (final (size, target) in sizes)
        sticky(
          MatrixCell(
            width: w.first,
            color: c.muted.withValues(alpha: 0.4),
            padding: const EdgeInsetsDirectional.only(
              start: Space.md + Space.xxl + Space.md,
              end: Space.md,
            ),
            child: PricingSizePill(
              label: sizeLabelText(size.label, t('recipes.oneSize')),
              active: size.isActive,
            ),
          ),
          // A size row is faintly tinted (`bg-muted/10`).
          _targetCells(w, target, tint: c.muted.withValues(alpha: 0.1)),
        ),
    ];
  }

  /// The catalog cell and the five editable cells of one target, on the
  /// row's [tint].
  List<Widget> _targetCells(
    MatrixWidths w,
    PricingTarget target, {
    Color? tint,
  }) {
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    return [
      MatrixCell(
        width: w.catalog,
        color: tint,
        child: Text(
          fmt.fmtMoney(target.catalogPrice),
          style: DashType.monoMedium.copyWith(
            fontSize: 14,
            color: c.textPrimary,
          ),
        ),
      ),
      for (final col in pricingCols)
        () {
          final r = target.resolve(col);
          final d = _draftFor(col, target);
          return MatrixCell(
            width: w.cell,
            startBorder: true,
            alignment: AlignmentDirectional.topStart,
            color: isDirtyCell(d, r) ? c.hover : tint,
            child: _control(col, target, r, d, touch: false),
          );
        }(),
    ];
  }

  Widget _control(
    PricingCol col,
    PricingTarget target,
    ResolvedCell r,
    DraftCell d, {
    required bool touch,
  }) => PricingControl(
    key: ValueKey(pricingCellKey(col, target.targetId)),
    resolved: r,
    draft: d,
    touch: touch,
    currencyLabel: ref.watch(formatProvider).currencyLabel(),
    onChange: ({price, available}) =>
        _set(col, target, price: price, available: available),
    onClear: () => _clear(col, target),
  );

  Widget _itemCard(Translator t, _ItemView r) {
    final c = context.madarColors;
    Widget body;
    final studio = r.studio;
    final sizes = r.sizes;
    final muted = DashType.body.copyWith(color: c.textSecondary);
    Widget note(String text) => _topLine(
      Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Center(child: Text(text, style: muted)),
      ),
    );
    if (!r.open || studio == null) {
      body = const SizedBox.shrink();
    } else if (studio.hasError && !studio.retrying) {
      body = note(t('menu.pricing.loadError'));
    } else if (sizes == null) {
      body = _topLine(
        const Padding(
          padding: EdgeInsets.all(Space.md),
          child: DashSkeleton(height: Space.xxl * 3),
        ),
      );
    } else if (sizes.isEmpty) {
      body = note(t('menu.pricing.noSizes'));
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (size, target) in sizes)
            _topLine(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: c.muted.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.xs + DashMetrics.hair,
                    ),
                    alignment: AlignmentDirectional.centerStart,
                    child: PricingSizePill(
                      label: sizeLabelText(size.label, t('recipes.oneSize')),
                      active: size.isActive,
                    ),
                  ),
                  _scopeList(t, target),
                ],
              ),
            ),
        ],
      );
    }
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PricingItemHead(
            item: r.item,
            name: r.name,
            open: r.open,
            dirty: r.dirty,
            onToggle: () => _toggle(r.item.id),
            onIntent: _studioWarmer(r),
          ),
          body,
        ],
      ),
    );
  }

  Widget _card(Widget child) {
    final c = context.madarColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.hairline),
      ),
      child: child,
    );
  }

  Widget _topLine(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.madarColors.hairline)),
    ),
    child: child,
  );

  /// `TargetScopeList`: the catalog line, then one row per scope.
  Widget _scopeList(Translator t, PricingTarget target) {
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _topLine(
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: '${t('menu.pricing.col_catalog')} ',
                      children: [
                        TextSpan(
                          text: '(${t('menu.pricing.readonly')})',
                          style: TextStyle(color: c.textMuted),
                        ),
                      ],
                    ),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ),
                Text(
                  fmt.fmtMoney(target.catalogPrice),
                  style: DashType.monoMedium.copyWith(
                    fontSize: 14,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final col in pricingCols)
          () {
            final r = target.resolve(col);
            final d = _draftFor(col, target);
            return _topLine(
              Container(
                color: isDirtyCell(d, r) ? c.hover : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.md,
                  children: [
                    SizedBox(
                      width: PricingMetrics.scopeLabel,
                      child: Padding(
                        padding: const EdgeInsets.only(top: Space.md),
                        child: Text(
                          t(pricingColKey(col)),
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: _control(col, target, r, d, touch: true)),
                  ],
                ),
              ),
            );
          }(),
      ],
    );
  }

  // ── add-ons tab ─────────────────────────────────────────────────────────

  Widget _addonsTab(Translator t, String org, String branchId, bool phone) {
    final key = _addonsKey(org);
    final q = ref.watch(pricingAddonCatalogProvider(key));
    if (q.value case final v?) _lastAddons = v;
    final data = q.value ?? _lastAddons;
    final reads = [
      ref.watch(branchAddonOverridesProvider(branchId)),
      for (final ch in pricingChannels)
        ref.watch(
          channelAddonOverridesProvider((branchId: branchId, channel: ch)),
        ),
    ];
    final ovr = _addonOverrides(branchId);
    // The channel reads gate the tab too (the web shows their cells as
    // inherited while they load or after they fail: MENU-PRC-032).
    final all = <AsyncValue<Object?>>[q, ...reads];
    // The add-on and branch reads replace the rows on a failure (the web's
    // `isError`); a channel read gates only until its first answer.
    final failed = [
      for (final (i, r) in all.indexed)
        if (i < 2 ? r.hasError && !r.retrying : r.failedFirst) r,
    ];
    if (failed.isNotEmpty) {
      return DashErrorState(
        title: t('menu.pricing.loadError'),
        message: errorMessage(failed.first.error, t),
        retryLabel: t('common.retry'),
        retrying: all.any((r) => r.isLoading),
        onRetry: () {
          ref.invalidate(pricingAddonCatalogProvider(key));
          ref.invalidate(branchAddonOverridesProvider(branchId));
          for (final ch in pricingChannels) {
            ref.invalidate(
              channelAddonOverridesProvider((branchId: branchId, channel: ch)),
            );
          }
        },
      );
    }
    if (data == null ||
        reads.any((r) => !r.hasValue) ||
        (!q.hasValue && data.data.isEmpty)) {
      return const DashSkeleton(
        height: PricingMetrics.skeleton,
        radius: Radii.xl,
      );
    }
    final list = data.data;
    for (final a in list) {
      _addons[a.id] = a;
    }
    final Widget content;
    if (list.isEmpty) {
      content = DashEmptyState(icon: 'tag', title: t('menu.pricing.noAddons'));
    } else {
      final rows = [
        for (final a in list)
          (
            name: _name(a.name, a.nameTranslations),
            target: addonTarget(a, ovr.branch, ovr.channels),
          ),
      ];
      final c = context.madarColors;
      Widget head(String name, PricingTarget target) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm + DashMetrics.hair,
        ),
        child: Row(
          spacing: Space.sm + DashMetrics.hair,
          children: [
            const MenuImageTile(
              url: null,
              icon: 'tag',
              size: PricingMetrics.tile,
            ),
            Expanded(
              child: MadarClippedText(
                name,
                maxLines: 1,
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
            ),
            if (_anyDirty([target])) const PricingDirtyDot(),
          ],
        ),
      );
      content = phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                for (final r in rows)
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        head(r.name, r.target),
                        _scopeList(t, r.target),
                      ],
                    ),
                  ),
              ],
            )
          : PricingMatrix(
              rows: (w, sticky) => [
                _head(t, w, sticky, t('menu.pricing.addonColumn')),
                for (final r in rows)
                  sticky(
                    MatrixCell(
                      width: w.first,
                      padding: EdgeInsets.zero,
                      child: head(r.name, r.target),
                    ),
                    _targetCells(w, r.target),
                  ),
              ],
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        content,
        _pager(
          _addonsPage,
          data.totalPages,
          (p) => setState(() => _addonsPage = p),
          (p) => ref.warm(
            pricingAddonCatalogProvider(
              pricingAddonKey(org, key.search, p + 1),
            ),
          ),
        ),
      ],
    );
  }
}

typedef _ItemView = ({
  MenuItemWithCosts item,
  String name,
  bool open,
  AsyncValue<StudioAggregate>? studio,
  List<(SizeOut, PricingTarget)>? sizes,
  bool dirty,
});
