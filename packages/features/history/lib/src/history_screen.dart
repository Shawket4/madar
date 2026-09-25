/// Orders — this till's sales, and every till's when online, with the
/// selected sale beside the table.
///
/// On the spec grid (docs/design/SPEC.md §15): the header carries the scope
/// line; the search box and the This till / All segments sit in the header's
/// `below` slot; the body is the one [OrdersTable] — the same table a past
/// till nests — with the type chips over it. Where the page is wide enough
/// (an iPad in landscape, a desktop) a selected sale opens in a 560 pane on
/// the trailing side; narrower, a row pushes the sale ([SaleScreen]). The two
/// are the same [SalePanel].
///
/// State lives in [historyProvider]. The screen is paramless beyond an
/// optional starting scope and bridges via `ref.bridge`.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/src/history_provider.dart';
import 'package:feature_history/src/history_strings.dart';
import 'package:feature_history/src/orders_table.dart';
import 'package:feature_history/src/sale_panel.dart';
import 'package:feature_history/src/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The sale pane beside the table (SPEC §3).
const double _detailWidth = 560;

/// The table keeps at least this much beside the pane; below it the sale is
/// pushed instead (an iPad in portrait).
const double _tableMinWidth = 440;

/// The segments beside the search on a tablet.
const double _segmentsWidth = 280;

/// The Orders screen — This till / All, search, and the sale beside it.
class OrderHistoryScreen extends ConsumerStatefulWidget {
  /// Creates the screen, opening on [initialScope].
  const OrderHistoryScreen({
    super.key,
    this.initialScope = OrdersScope.thisTill,
  });

  /// Which segment is selected on open. The Till's "Orders this till" row
  /// leaves it; the old Search entry opens on every till.
  final OrdersScope initialScope;

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

/// The old cross-till Search page, kept as a name so the shell still
/// compiles: it is the Orders screen opened on All.
class OrderSearchScreen extends StatelessWidget {
  /// Creates the Orders screen opened on every till.
  const OrderSearchScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const OrderHistoryScreen(initialScope: OrdersScope.all);
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  final TextEditingController _searchField = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialScope != OrdersScope.thisTill) {
      // The notifier builds on This till; flip it before the first frame's
      // load lands so the screen never flashes the wrong list.
      unawaited(
        Future.microtask(() {
          if (!mounted) return;
          ref.read(historyProvider.notifier).setScope(widget.initialScope);
        }),
      );
    }
  }

  @override
  void dispose() {
    _searchField.dispose();
    super.dispose();
  }

  /// A row tap where there is no room beside the table: select, then push
  /// the sale. The provider stays alive underneath, so the pushed screen
  /// reads the same selection and the table is where it was on the way back.
  void _push(BuildContext context, OrderSummaryView order) {
    ref.read(historyProvider.notifier).select(order);
    unawaited(MadarPages.push<void>(context, (_) => const SaleScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    final layout = context.madarLayout;
    final notifier = ref.read(historyProvider.notifier);
    final scope = ref.watch(historyProvider.select((s) => s.scope));
    String t(String key) => historyTr(bridge, key);

    final search = MadarField(
      controller: _searchField,
      placeholder: t('history.search_hint'),
      kind: MadarFieldKind.search,
      glyph: MadarGlyph.search,
      onChanged: notifier.setSearch,
    );
    final segments = MadarSegmented<OrdersScope>(
      items: [
        MadarSegmentItem(OrdersScope.thisTill, t('history.this_shift')),
        MadarSegmentItem(OrdersScope.all, t('order.all')),
      ],
      value: scope,
      onChanged: notifier.setScope,
    );

    return MadarPageScaffold(
      title: t('history.title'),
      subtitle: _scopeLine(ref, bridge),
      width: MadarContentWidth.full,
      below: layout.isTablet
          ? Row(
              spacing: Space.md,
              children: [
                Expanded(child: search),
                SizedBox(width: _segmentsWidth, child: segments),
              ],
            )
          : Column(spacing: Space.md, children: [search, segments]),
      // Pulled: the manual sync, then the scope re-read (This till from the
      // local rows; All searches the server again, as a person asked).
      body: MadarRefresh(
        nested: true,
        onRefresh: () => pullThenReread(ref, notifier.load),
        child: MadarPullable(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final roomBeside =
                    layout.isTablet &&
                    constraints.maxWidth - _detailWidth - Space.lg >=
                        _tableMinWidth;
                return _Body(
                  split: roomBeside,
                  onOpen: roomBeside
                      ? notifier.select
                      : (o) => _push(context, o),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// The header's second line: "This till · 42 sales · EGP 6,230.00", or
  /// "All · 318 found", or the honest "No till open".
  ///
  /// Without `till.cash_spot_check` the shift aggregate is gone and the line
  /// reads "This till · Blind count" (owner, 2026-09-19): the sales total and
  /// the order count are the same figures the rule hides everywhere else.
  String? _scopeLine(WidgetRef ref, MadarBridge bridge) {
    final scope = ref.watch(historyProvider.select((s) => s.scope));
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    String t(String key) => historyTr(bridge, key);
    switch (scope) {
      case OrdersScope.thisTill:
        final hasTill = ref.watch(shellProvider.select((s) => s.tillOpen));
        final stats = ref.watch(historyProvider.select((s) => s.stats));
        final loading = ref.watch(historyProvider.select((s) => s.loading));
        if (!hasTill && !loading) return t('history.no_shift');
        final parts = <String>[t('history.this_shift')];
        // The shift aggregate is the one till money figure on this screen:
        // without `till.cash_spot_check` there is no total and no count, and
        // the header says so in the Till section's own words rather than
        // going quiet. The list below keeps every sale's own total.
        if (stats == null && hasTill && !bridge.tillFiguresVisible()) {
          parts.add(bridge.tr(key: 'spot.blind_count_note'));
        }
        if (stats != null) {
          parts
            ..add(
              t(
                'history.sales_count',
              ).replaceAll('{count}', ltrIsland('${stats.orderCount}')),
            )
            ..add(
              bridge.formatMoney(
                minor: stats.salesMinor,
                currency: currency,
                signed: false,
              ),
            );
        }
        return parts.join(' · ');
      case OrdersScope.all:
        final total = ref.watch(historyProvider.select((s) => s.serverTotal));
        final parts = <String>[t('order.all')];
        if (total > 0) {
          parts.add(
            t('history.found_count').replaceAll('{count}', ltrIsland('$total')),
          );
        }
        return parts.join(' · ');
    }
  }
}

/// Chips, notice and table — and the sale pane beside them when [split] and
/// a sale is selected. Nothing selected, the table takes the whole width: an
/// empty pane saying "pick one" is a column of nothing.
class _Body extends ConsumerWidget {
  const _Body({required this.split, required this.onOpen});

  final bool split;
  final ValueChanged<OrderSummaryView> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(historyProvider.select((s) => s.selected));
    final master = _Master(onOpen: onOpen, split: split);
    if (!split || selected == null) return master;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Expanded(child: master),
        SizedBox(
          width: _detailWidth,
          child: MadarContentFrame(
            gutter: false,
            child: MadarCard(
              padding: EdgeInsetsDirectional.zero,
              child: SalePanel(
                order: selected,
                onClose: ref.read(historyProvider.notifier).clearSelection,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Master extends ConsumerWidget {
  const _Master({required this.onOpen, required this.split});

  final ValueChanged<OrderSummaryView> onOpen;
  final bool split;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final notifier = ref.read(historyProvider.notifier);
    final scope = ref.watch(historyProvider.select((s) => s.scope));
    final filter = ref.watch(historyProvider.select((s) => s.filter));
    final loading = ref.watch(historyProvider.select((s) => s.loading));
    final loadingMore = ref.watch(historyProvider.select((s) => s.loadingMore));
    final error = ref.watch(historyProvider.select((s) => s.error));
    final online = ref.watch(historyProvider.select((s) => s.online));
    final rowsEmpty = ref.watch(historyProvider.select((s) => s.rows.isEmpty));
    final filtered = ref.watch(historyProvider.select((s) => s.filtered));
    final visibleLimit = ref.watch(
      historyProvider.select((s) => s.visibleLimit),
    );
    final hasMore = ref.watch(historyProvider.select((s) => s.hasMore));
    final hasTill = ref.watch(shellProvider.select((s) => s.tillOpen));
    final selectedId = ref.watch(historyProvider.select((s) => s.selectedId));
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    String t(String key) => historyTr(bridge, key);

    Widget chip(OrdersFilter f, String label) => MadarChip(
      label: label,
      selected: filter == f,
      onTap: () => notifier.setFilter(f),
    );

    // The honest states first: a first load, a refusal, no network, no till.
    final visible = scope == OrdersScope.thisTill
        ? filtered.take(visibleLimit).toList()
        : filtered;
    final more = scope == OrdersScope.thisTill
        ? filtered.length > visible.length
        : hasMore;
    var empty = MadarEmptyContent(
      icon: rowsEmpty ? 'tray' : 'line.3.horizontal.decrease.circle',
      title: rowsEmpty ? t('history.empty') : t('history.no_match'),
      message: rowsEmpty ? t('history.empty_message') : null,
    );
    final MadarTableState<OrderSummaryView> state;
    if (loading && rowsEmpty) {
      state = const MadarTableState.loading();
    } else if (error != null && rowsEmpty) {
      state = MadarTableState.error(
        message: error.of(bridge),
        retryLabel: t('history.retry'),
        onRetry: notifier.load,
      );
    } else if (scope == OrdersScope.all && !online && rowsEmpty) {
      empty = MadarEmptyContent(
        icon: 'wifi.slash',
        title: t('history.offline_search'),
        actionLabel: t('history.retry'),
        onAction: notifier.load,
      );
      state = const MadarTableState.data([]);
    } else if (scope == OrdersScope.thisTill && !hasTill) {
      // No till is a place to be, not an error: say so and offer every
      // till, where yesterday's sale is.
      empty = MadarEmptyContent(
        icon: 'lock',
        title: t('history.no_shift'),
        actionLabel: t('order.all'),
        onAction: () => notifier.setScope(OrdersScope.all),
      );
      state = const MadarTableState.data([]);
    } else {
      state = MadarTableState.data(
        visible,
        hasMore: more,
        loadingMore: loadingMore,
        onLoadMore: notifier.showMore,
      );
    }

    // A notice above the rows when the list is stale or partial, in words.
    final Widget? notice = switch ((scope, online, error, rowsEmpty)) {
      (OrdersScope.all, false, _, false) => NoticeBanner(
        text: t('history.offline_cached'),
        icon: 'wifi.slash',
      ),
      (OrdersScope.all, true, final UiText message, false) => NoticeBanner(
        text: message.of(bridge),
        tone: ChipTone.danger,
        icon: 'exclamationmark.triangle',
        onTap: notifier.load,
      ),
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // The chips must not clip their tactile press.
          clipBehavior: Clip.none,
          child: Row(
            spacing: Space.sm,
            children: [
              chip(OrdersFilter.all, t('history.type.all')),
              chip(OrdersFilter.dineIn, t('history.type.dine_in')),
              chip(OrdersFilter.takeaway, t('history.type.takeaway')),
              chip(OrdersFilter.online, t('history.type.online')),
              chip(OrdersFilter.voided, t('history.voided')),
            ],
          ),
        ),
        ?notice,
        Flexible(
          child: OrdersTable(
            // A short or empty list still pulls to refresh.
            physics: MadarRefresh.physics,
            bridge: bridge,
            currency: currency,
            state: state,
            empty: empty,
            onTap: onOpen,
            selectedId: split ? selectedId : null,
            // Beside the pane the table narrows; it drops columns by
            // priority rather than turning into phone rows.
            collapse: context.madarLayout.isPhone ? null : false,
          ),
        ),
      ],
    );
  }
}
