/// Orders — this shift's sales, and every shift's when online, with the
/// selected sale beside the list.
///
/// One screen replaces the old History page and the cross-shift Search
/// page: a This shift / All segment, one search box, one chip row. On a
/// tablet the list takes the start half and the sale opens beside it as a
/// card (master-detail); on a phone the list is the screen and a row pushes
/// the sale ([SaleScreen]). The two paths are the same [SalePanel].
///
/// State lives in [historyProvider]. The screen is paramless beyond an
/// optional starting scope and bridges via `ref.watch(bridgeProvider)`.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/src/history_provider.dart';
import 'package:feature_history/src/history_strings.dart';
import 'package:feature_history/src/sale_panel.dart';
import 'package:feature_history/src/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The list column beside the sale on a tablet (canvas: 560 of 1194). It
/// gives way on a narrower tablet so the sale keeps a readable width.
const double _listColumnWidth = 560;
const double _listColumnMinWidth = 380;

/// Below this body width the sale is pushed over the list rather than
/// drawn beside it — an iPad in portrait behind its rail is about here.
const double _splitMinWidth = Responsive.wide;

/// The search box at the header's end on a tablet (canvas: 360).
const double _searchWidth = 360;

/// Row cells (canvas grid: 70 / 52 / 1fr / 64 / 80, 12 gaps).
const double _numberColWidth = 76;
const double _timeColWidth = 56;
const double _paymentColWidth = 60;
const double _amountColWidth = 124;

/// The selected row's start-edge bar.
const double _selectBarWidth = 4;

/// The Orders screen — This shift / All, search, and the sale beside it.
class OrderHistoryScreen extends ConsumerStatefulWidget {
  /// Creates the screen, opening on [initialScope].
  const OrderHistoryScreen({
    super.key,
    this.initialScope = OrdersScope.thisShift,
  });

  /// Which segment is selected on open. The Till's "Orders this shift" row
  /// leaves it; the old Search entry opens on every shift.
  final OrdersScope initialScope;

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

/// The old cross-shift Search page, kept as a name so the shell still
/// compiles: it is the Orders screen opened on All.
class OrderSearchScreen extends StatelessWidget {
  /// Creates the Orders screen opened on every shift.
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
    if (widget.initialScope != OrdersScope.thisShift) {
      // The notifier builds on This shift; flip it before the first frame's
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

  /// A row tap on a phone: select, then push the sale over the list. The
  /// provider stays alive underneath, so the pushed screen reads the same
  /// selection and the list is exactly where it was on the way back.
  void _openOnPhone(BuildContext context, OrderSummaryView order) {
    ref.read(historyProvider.notifier).select(order);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const SaleScreen(),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: MotionSpec.springOut),
              ),
          child: child,
        ),
        transitionDuration: MotionSpec.standardDuration,
        reverseTransitionDuration: MotionSpec.standardDuration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(bridgeProvider);
    final layout = context.madarLayout;
    final notifier = ref.read(historyProvider.notifier);
    String t(String key) => historyTr(bridge, key);

    final search = MadarField(
      controller: _searchField,
      placeholder: t('history.search_hint'),
      glyph: MadarGlyph.search,
      onChanged: notifier.setSearch,
    );

    return MadarPageScaffold(
      title: t('history.title'),
      subtitle: _scopeLine(ref, bridge),
      onBack: () => Navigator.maybePop(context),
      actions: [
        if (layout.isTablet) SizedBox(width: _searchWidth, child: search),
      ],
      below: layout.isPhone ? search : null,
      overlay: const _HistoryToastHost(),
      body: Padding(
        padding: EdgeInsetsDirectional.only(
          start: layout.gutter,
          end: layout.gutter,
          top: Space.lg,
          bottom: layout.gutter,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final split = constraints.maxWidth >= _splitMinWidth;
                  if (!split) {
                    return _ListColumn(onOpen: (o) => _openOnPhone(context, o));
                  }
                  final listWidth = (constraints.maxWidth * 0.52).clamp(
                    _listColumnMinWidth,
                    _listColumnWidth,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Space.lg,
                    children: [
                      SizedBox(
                        width: listWidth,
                        child: _ListColumn(onOpen: notifier.select),
                      ),
                      const Expanded(child: _SaleCard()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The header's second line: "this shift · 42 sales · EGP 6230.00", or
  /// "All · 318 found", or the honest "No shift open".
  String? _scopeLine(WidgetRef ref, MadarBridge bridge) {
    final scope = ref.watch(historyProvider.select((s) => s.scope));
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    String t(String key) => historyTr(bridge, key);
    switch (scope) {
      case OrdersScope.thisShift:
        final hasShift = ref.watch(historyProvider.select((s) => s.hasShift));
        final stats = ref.watch(historyProvider.select((s) => s.stats));
        final loading = ref.watch(historyProvider.select((s) => s.loading));
        if (!hasShift && !loading) return t('history.no_shift');
        final parts = <String>[t('history.this_shift')];
        if (stats != null) {
          parts
            ..add(
              t(
                'history.sales_count',
              ).replaceAll('{count}', ltrIsland('${stats.orderCount}')),
            )
            ..add(Money.format(stats.salesMinor, currency: currency));
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

/// The screen toast, driven by [HistoryState.toast].
class _HistoryToastHost extends ConsumerWidget {
  const _HistoryToastHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(historyProvider.select((s) => s.toast));
    return ToastHost(
      toast,
      onDismiss: (id) => ref.read(historyProvider.notifier).dismissToast(id),
    );
  }
}

/// The sale beside the list on a tablet: a card holding the panel, or the
/// prompt to pick one.
class _SaleCard extends ConsumerWidget {
  const _SaleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final selected = ref.watch(historyProvider.select((s) => s.selected));
    return MadarCard(
      padding: EdgeInsetsDirectional.zero,
      child: selected == null
          ? EmptyState(
              icon: 'receipt',
              title: historyTr(bridge, 'history.select_prompt'),
            )
          : SalePanel(order: selected),
    );
  }
}

// ── The list column: segment, chips, rows ────────────────────────────────

class _ListColumn extends ConsumerWidget {
  const _ListColumn({required this.onOpen});

  /// A row tap. Selects beside the list on a tablet; pushes on a phone.
  final void Function(OrderSummaryView) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final notifier = ref.read(historyProvider.notifier);
    final scope = ref.watch(historyProvider.select((s) => s.scope));
    final filter = ref.watch(historyProvider.select((s) => s.filter));
    String t(String key) => historyTr(bridge, key);

    Widget chip(OrdersFilter f, String label) => MadarChip(
      label: label,
      selected: filter == f,
      onTap: () => notifier.setFilter(f),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSegmented<OrdersScope>(
          items: [
            MadarSegmentItem(OrdersScope.thisShift, t('history.this_shift')),
            MadarSegmentItem(OrdersScope.all, t('order.all')),
          ],
          value: scope,
          onChanged: notifier.setScope,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // The chips must not clip their tactile press, and the last chip
          // must not kiss the column's edge when it scrolls.
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
        Expanded(child: _Rows(onOpen: onOpen)),
      ],
    );
  }
}

class _Rows extends ConsumerWidget {
  const _Rows({required this.onOpen});

  final void Function(OrderSummaryView) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final notifier = ref.read(historyProvider.notifier);
    final scope = ref.watch(historyProvider.select((s) => s.scope));
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
    final selectedId = ref.watch(historyProvider.select((s) => s.selectedId));
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final compact = context.isPhone;
    String t(String key) => historyTr(bridge, key);

    // The honest states first: a first load, a refusal, no network.
    if (loading && rowsEmpty) {
      return const Align(alignment: Alignment.topCenter, child: SkeletonList());
    }
    if (error != null && rowsEmpty) {
      return ErrorState(
        message: error,
        retryLabel: t('history.retry'),
        onRetry: notifier.load,
      );
    }
    if (scope == OrdersScope.all && !online && rowsEmpty) {
      return EmptyState(
        icon: 'wifi.slash',
        title: t('history.offline_search'),
        actionLabel: t('history.retry'),
        onAction: notifier.load,
      );
    }
    if (filtered.isEmpty) {
      return EmptyState(
        icon: rowsEmpty ? 'tray' : 'line.3.horizontal.decrease.circle',
        title: rowsEmpty ? t('history.empty') : t('history.no_match'),
      );
    }

    final visible = scope == OrdersScope.thisShift
        ? filtered.take(visibleLimit).toList()
        : filtered;
    final remaining = scope == OrdersScope.thisShift
        ? filtered.length - visible.length
        : (hasMore ? 1 : 0);

    // A notice above the rows when the list is stale or partial, in words.
    final Widget? notice = switch ((scope, online, error)) {
      (OrdersScope.all, false, _) => NoticeBanner(
        text: t('history.offline_cached'),
        icon: 'wifi.slash',
      ),
      (OrdersScope.all, true, final String message) => NoticeBanner(
        text: message,
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
        ?notice,
        Expanded(
          child: MadarCard(
            flush: true,
            // Lazy on purpose: "Show more" grows the list without bound.
            child: ListView.builder(
              padding: EdgeInsetsDirectional.zero,
              itemCount: visible.length + (remaining > 0 ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= visible.length) {
                  return _MoreRow(
                    label: scope == OrdersScope.thisShift
                        ? t('history.show_more').replaceAll(
                            '{count}',
                            '${remaining < kHistoryPageSize ? remaining : kHistoryPageSize}',
                          )
                        : t('search.load_more'),
                    loading: loadingMore,
                    onTap: notifier.showMore,
                  );
                }
                final o = visible[index];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (index > 0) const MadarHairline(light: true),
                    _SaleRow(
                      order: o,
                      bridge: bridge,
                      currency: currency,
                      selected: o.id == selectedId,
                      compact: compact,
                      showDate: scope == OrdersScope.all,
                      onTap: () => onOpen(o),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The last row of the card: one more page.
class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MadarHairline(light: true),
        Padding(
          padding: const EdgeInsetsDirectional.all(Space.md),
          child: MadarButton(
            label: label,
            variant: MadarButtonVariant.ghost,
            size: MadarButtonSize.compact,
            glyph: MadarGlyph.chevronDown,
            loading: loading,
            onTap: onTap,
          ),
        ),
      ],
    );
  }
}

/// One sale in the list. 64 tall; the number and the time are mono, the
/// origin and who bought it are words, the payment method is quiet and the
/// money sits at the end. The selected row carries a teal bar on its start
/// edge and the accent wash — the row's colour lives there and nowhere else.
///
/// [compact] is the phone's two-line arrangement: the five columns do not
/// fit in 358 points, and a wrapped money figure is a misread figure.
class _SaleRow extends StatelessWidget {
  const _SaleRow({
    required this.order,
    required this.bridge,
    required this.currency,
    required this.selected,
    required this.compact,
    required this.showDate,
    required this.onTap,
  });

  final OrderSummaryView order;
  final MadarBridge bridge;
  final String currency;
  final bool selected;
  final bool compact;

  /// Under All the day matters; under This shift it is today.
  final bool showDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final o = order;
    final state = SaleState.of(o);
    final voided = state == SaleState.voided;
    final time = bridge.formatTime(rfc3339: o.createdAt, style: TimeStyle.time);
    final date = showDate
        ? bridge.formatTime(rfc3339: o.createdAt, style: TimeStyle.dateShort)
        : null;

    // "T5 · dine-in" in the design; the table is not on the view, so the
    // origin leads and the ref (an online order's) or the customer follows.
    final meta = <String>[
      if (o.orderRef case final ref?) ltrIsland(ref),
      orderTypeLabel(bridge, o.orderType),
      ?o.customerName,
      ?date,
    ].join(' · ');

    final number = state == SaleState.queued
        ? MadarGlyphIcon(
            MadarGlyph.half,
            size: IconSize.xl,
            color: colors.warning,
          )
        : Text(
            saleNumber(bridge, o),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: MadarType.numLg.copyWith(
              fontWeight: FontWeight.w700,
              color: voided ? colors.textMuted : colors.textPrimary,
            ),
          );
    final timeText = Text(
      time,
      textDirection: TextDirection.ltr,
      style: MadarType.num.copyWith(
        fontWeight: FontWeight.w500,
        color: colors.textSecondary,
      ),
    );
    final metaText = Text(
      meta,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: MadarType.body.copyWith(
        color: voided ? colors.textMuted : colors.textPrimary,
      ),
    );
    final payment = Text(
      o.paymentLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: MadarType.bodySm.copyWith(color: colors.textSecondary),
    );
    final money = Text(
      Money.format(o.totalMinor, currency: currency),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.end,
      style: MadarType.money.copyWith(
        fontSize: 16,
        color: voided ? colors.textMuted : colors.textPrimary,
        decoration: voided ? TextDecoration.lineThrough : null,
      ),
    );
    final tag = state != null
        ? SaleStateTag(state: state, bridge: bridge)
        : o.priceFlagged
        // Only when there is no state to show: a voided or still-queued sale
        // has something more urgent to say, and two tags on one row is a row
        // nobody reads. The sale itself always shows it — see `_Flags`.
        ? PriceFlagTag(bridge: bridge)
        : null;

    final Widget content;
    if (compact) {
      content = Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Row(
                  spacing: Space.sm,
                  children: [
                    number,
                    timeText,
                    if (tag != null) Flexible(child: tag),
                  ],
                ),
                metaText,
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 2,
            children: [money, payment],
          ),
        ],
      );
    } else {
      content = Row(
        spacing: Space.md,
        children: [
          SizedBox(
            width: _numberColWidth,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: number,
            ),
          ),
          SizedBox(width: _timeColWidth, child: timeText),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [metaText, ?tag],
            ),
          ),
          SizedBox(width: _paymentColWidth, child: payment),
          SizedBox(width: _amountColWidth, child: money),
        ],
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          MadarHaptics.selection();
          onTap();
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration: MotionSpec.standardDuration,
                curve: MotionSpec.standardCurve,
                color: selected ? colors.accentBg : colors.surface,
              ),
            ),
            if (selected)
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width: _selectBarWidth,
                  child: ColoredBox(color: colors.accent),
                ),
              ),
            Container(
              constraints: const BoxConstraints(minHeight: Metrics.rowHeight),
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              alignment: AlignmentDirectional.centerStart,
              child: content,
            ),
          ],
        ),
      ),
    );
  }
}
