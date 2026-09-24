/// Queue › Online — the branch's live online orders as a table (rows beside
/// the order's pane on a wide iPad, like Bills), one next step per row:
/// `NEW → Accept · ACCEPTED → Start preparing · PREPARING → Mark ready ·
/// READY → Out for delivery / Picked up · OUT → Charge`.
///
/// Accept is one act with the ready-in time: the branch's base is the
/// preselected chip, so a new order is accepted in one tap on the card.
/// Decline needs a reason. A card whose status changed under the teller
/// (409) flips to its new state with a one-line notice, no dialog. Offline,
/// the segment shows the last list and says so; every action here is an
/// online call and answers in words where you tap it.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_incoming/src/details_sheets.dart';
import 'package:feature_incoming/src/incoming_provider.dart';
import 'package:feature_incoming/src/queue_strings.dart';
import 'package:feature_incoming/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

class OnlineSegment extends ConsumerStatefulWidget {
  const OnlineSegment({super.key});

  @override
  ConsumerState<OnlineSegment> createState() => _OnlineSegmentState();
}

class _OnlineSegmentState extends ConsumerState<OnlineSegment> {
  @override
  void initState() {
    super.initState();
    // (Re)entering the segment refreshes the board — deferred a microtask
    // because provider writes are illegal while the tree is building.
    unawaited(
      Future<void>.microtask(() {
        if (mounted) _reload();
      }),
    );
  }

  void _reload() =>
      unawaited(ref.read(incomingProvider.notifier).loadDeliveryOrders());

  // ── sheet launchers ────────────────────────────────────────────────────────

  /// The shared details layout (customer / address / channel + lines +
  /// money), with Charge pinned under it when the order is at its last step.
  Future<void> _view(DeliveryOrderView o) async {
    final bridge = ref.read(bridgeProvider);
    final charge = await showMadarSheet<bool>(
      context,
      size: SheetSize.large,
      maxWidth: Responsive.listMaxWidth,
      builder: (sheetContext) => DeliveryDetailsSheet(
        order: o,
        footer: o.status == 'out_for_delivery'
            ? MadarMoneyBar(
                label: bridge.trOr(QueueKeys.chargeOnline),
                amountMinor: o.totalMinor,
                currency: bridge.currentSession()?.currencyCode ?? '',
                onTap: () => Navigator.of(sheetContext).maybePop(true),
              )
            : null,
      ),
    );
    if (!mounted || charge != true) return;
    await _charge(o);
  }

  /// Charge = the ONE tender drawer; method-only for an online order (all
  /// `deliveryFinalize` takes). The drawer books the sale and prints; the
  /// board re-reads so the card leaves, and the shell learns of the sale.
  /// One drawer at a time: a double tap on Charge opened two over one order.
  bool _charging = false;

  Future<void> _charge(DeliveryOrderView o) async {
    if (_charging) return;
    _charging = true;
    try {
      ref.read(incomingProvider.notifier).clearError();
      final outcome = await showCharge(context, ChargeTarget.online(o));
      if (outcome == null || !mounted) return;
      await ref.read(incomingProvider.notifier).loadDeliveryOrders();
      ref.read(shellProvider.notifier).refresh();
    } finally {
      if (mounted) _charging = false;
    }
  }

  Future<void> _decline(DeliveryOrderView o) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => _DeclineSheet(order: o),
    );
  }

  Future<void> _cancel(DeliveryOrderView o) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => _CancelSheet(order: o),
    );
  }

  /// The order shown in the pane beside the list (wide layouts only).
  String? _selectedId;

  /// The row's one next step. Accept from a row takes the branch's base
  /// ready-in time; the pane offers the other choices.
  void _primary(DeliveryOrderView o, {int? readyIn}) {
    final notifier = ref.read(incomingProvider.notifier);
    switch (o.status) {
      case 'received':
        final prep = ref.read(incomingProvider).prepChoices;
        unawaited(
          notifier.acceptDelivery(o, readyInMinutes: readyIn ?? prep?.first),
        );
      case 'out_for_delivery':
        unawaited(_charge(o));
      default:
        unawaited(notifier.advanceDelivery(o));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    final orders = ref.watch(incomingProvider.select((s) => s.deliveryOrders));
    final loading = ref.watch(
      incomingProvider.select((s) => s.isLoadingDelivery),
    );
    final stale = ref.watch(incomingProvider.select((s) => s.onlineStale));
    final error = ref.watch(incomingProvider.select((s) => s.error));
    final busyIds = ref.watch(incomingProvider.select((s) => s.busyOrderIds));
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final layout = context.madarLayout;
    String t(String key) => bridge.tr(key: key);

    // New orders first (they want a hand), then by arrival.
    final sorted = [...orders]
      ..sort((a, b) {
        final ra = a.status == 'received' ? 0 : 1;
        final rb = b.status == 'received' ? 0 : 1;
        if (ra != rb) return ra - rb;
        return a.createdAt.compareTo(b.createdAt);
      });

    final MadarTableState<DeliveryOrderView> tableState;
    if (loading && orders.isEmpty && !stale) {
      tableState = const MadarTableState.loading(rows: 4);
    } else if (error != null && orders.isEmpty && !stale) {
      tableState = MadarTableState.error(
        message: error.of(bridge),
        retryLabel: t('history.retry'),
        onRetry: _reload,
      );
    } else {
      tableState = MadarTableState.data(sorted);
    }

    Widget primaryFor(DeliveryOrderView o) => MadarButton(
      label: onlinePrimaryLabel(bridge, o),
      size: MadarButtonSize.compact,
      variant: o.status == 'received'
          ? MadarButtonVariant.primary
          : MadarButtonVariant.secondary,
      loading: busyIds.contains(o.id),
      onTap: () => _primary(o),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final inner = constraints.maxWidth - 2 * layout.gutter;
        final split = !layout.isPhone && inner >= kQueueSplitMinWidth;
        final paneWidth = queuePaneWidth(inner);
        final selected = split
            ? sorted.where((o) => o.id == _selectedId).firstOrNull ??
                  sorted.firstOrNull
            : null;

        final table = MadarDataTable<DeliveryOrderView>(
          state: tableState,
          // A short or empty list still pulls to refresh.
          physics: MadarRefresh.physics,
          rowKey: (o) => o.id,
          empty: MadarEmptyContent(
            title: bridge.trOr(QueueKeys.emptyOnline),
            message: t('queue.empty_online_hint'),
          ),
          columns: [
            MadarColumn(
              id: 'customer',
              label: t('order.customer'),
              text: (o) => o.customerName,
              emphasis: true,
              flex: 2,
              phone: MadarPhoneRole.title,
            ),
            MadarColumn(
              id: 'channel',
              label: t('queue.col_channel'),
              text: (o) => [
                t('delivery.${o.channel}'),
                if (o.paymentHint case final h? when h.isNotEmpty) h,
                ?onlineReadyLabel(bridge, o),
              ].join(' · '),
              flex: 3,
            ),
            MadarColumn.status(
              id: 'status',
              label: t('queue.col_status'),
              status: (o) => MadarStatus(
                t('delivery.status.${o.status}'),
                tone: deliveryTone(o.status),
              ),
              width: 150,
            ),
            MadarColumn(
              id: 'time',
              label: t('queue.col_time'),
              text: (o) => clockLabel(bridge, o.createdAt),
              mono: true,
              muted: true,
              width: 72,
              priority: 1,
            ),
            MadarColumn.money(
              id: 'total',
              label: t('order.total'),
              minor: (o) => o.totalMinor,
              currency: currency,
              width: 132,
            ),
            MadarColumn(
              id: 'next',
              label: '',
              cell: (context, o) => primaryFor(o),
              width: 136,
              align: MadarColumnAlign.end,
              phone: MadarPhoneRole.hidden,
            ),
          ],
          rail: (o) => deliveryTone(o.status),
          selected: split ? (o) => o.id == selected?.id : null,
          onTap: (o) =>
              split ? setState(() => _selectedId = o.id) : unawaited(_view(o)),
          chevron: false,
          trailing: layout.isPhone ? (context, o) => primaryFor(o) : null,
        );

        final list = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            if (stale)
              NoticeBanner(
                text: bridge.trOr(QueueKeys.offlineNotice),
                icon: 'wifi.slash',
              ),
            if (error != null && (orders.isNotEmpty || stale))
              NoticeBanner(
                text: error.of(bridge),
                tone: ChipTone.danger,
                icon: 'exclamationmark.circle',
              ),
            Flexible(child: table),
            // Accepting per channel stays at the foot of the segment on a
            // phone; the tablet header carries it, via the screen.
            if (layout.isPhone) const AcceptingRow(),
          ],
        );

        return Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            layout.gutter,
            Space.lg,
            layout.gutter,
            Space.lg,
          ),
          child: !split
              ? list
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.lg,
                  children: [
                    Expanded(child: list),
                    SizedBox(
                      width: paneWidth,
                      child: selected == null
                          ? const SizedBox.shrink()
                          : MadarCard(
                              flush: true,
                              child: DeliveryDetailsSheet(
                                key: ValueKey('pane-${selected.id}'),
                                order: selected,
                                footer: _OnlinePaneFooter(
                                  key: ValueKey('foot-${selected.id}'),
                                  order: selected,
                                  onPrimary: (readyIn) =>
                                      _primary(selected, readyIn: readyIn),
                                  onDecline: () =>
                                      unawaited(_decline(selected)),
                                  onCancel: () => unawaited(_cancel(selected)),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// What the kitchen said, or what the shop promised — never both, and
/// nothing at all before the order is accepted (the core drops the promise
/// the moment the kitchen calls the order ready).
String? onlineReadyLabel(MadarBridge bridge, DeliveryOrderView o) {
  final stamp = o.readyAt ?? o.promisedReadyAt;
  if (stamp == null) return null;
  final word = bridge.trOr(
    o.readyAt == null ? QueueKeys.readyBy : QueueKeys.readyAt,
  );
  return '$word ${clockLabel(bridge, stamp)}';
}

/// The primary's word for an order's next step.
String onlinePrimaryLabel(MadarBridge bridge, DeliveryOrderView o) =>
    switch (o.status) {
      'received' => bridge.trOr(QueueKeys.accept),
      'out_for_delivery' => bridge.trOr(QueueKeys.chargeOnline),
      'ready' when o.channel == 'pickup' => bridge.trOr(QueueKeys.pickedUp),
      _ => bridge.tr(key: 'delivery.action.${nextDeliveryStatus(o.status)}'),
    };

/// Under the order in the pane: a NEW order's ready-in choice with Accept and
/// Decline; later, the next step (Charge with its figure at the last one,
/// the same bar Bills uses) and Cancel.
class _OnlinePaneFooter extends ConsumerStatefulWidget {
  const _OnlinePaneFooter({
    required this.order,
    required this.onPrimary,
    required this.onDecline,
    required this.onCancel,
    super.key,
  });

  final DeliveryOrderView order;
  final ValueChanged<int?> onPrimary;
  final VoidCallback onDecline;
  final VoidCallback onCancel;

  @override
  ConsumerState<_OnlinePaneFooter> createState() => _OnlinePaneFooterState();
}

class _OnlinePaneFooterState extends ConsumerState<_OnlinePaneFooter> {
  int? _readyIn;

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    final o = widget.order;
    final busy = ref.watch(
      incomingProvider.select((s) => s.busyOrderIds.contains(o.id)),
    );
    final notice = ref.watch(incomingProvider.select((s) => s.notices[o.id]));
    final prep = ref.watch(incomingProvider.select((s) => s.prepChoices));
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final isNew = o.status == 'received';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        if (notice != null)
          CardNotice(
            text: notice.of(bridge),
            onDismiss: () =>
                ref.read(incomingProvider.notifier).clearNotice(o.id),
          ),
        if (isNew && prep != null) ...[
          MadarSectionHeader(text: bridge.trOr(QueueKeys.readyIn)),
          Row(
            spacing: Space.sm,
            children: [
              for (final m in prep)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: MadarChip.tile(
                      label: bridge
                          .tr(key: 'queue.prep_minutes')
                          .replaceAll('{count}', '$m'),
                      selected: (_readyIn ?? prep.first) == m,
                      onTap: () => setState(() => _readyIn = m),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (o.status == 'out_for_delivery')
          MadarMoneyBar(
            label: bridge.trOr(QueueKeys.chargeOnline),
            amountMinor: o.totalMinor,
            currency: currency,
            loading: busy,
            onTap: () => widget.onPrimary(null),
          )
        else
          MadarButton(
            label: onlinePrimaryLabel(bridge, o),
            loading: busy,
            onTap: () => widget.onPrimary(_readyIn),
          ),
        MadarButton(
          label: isNew
              ? bridge.trOr(QueueKeys.decline)
              : bridge.tr(key: 'delivery.cancel'),
          variant: MadarButtonVariant.ghost,
          enabled: !busy,
          onTap: isNew ? widget.onDecline : widget.onCancel,
        ),
      ],
    );
  }
}

/// Accepting per channel: auto / open / closed, a tap cycles. Only the
/// channels the dashboard enabled are shown — a disabled one cannot be
/// opened from the till, so it is not a control. `pickup` / `umbrella` are
/// on the wire but not in the view, so they cannot appear yet.
class AcceptingRow extends ConsumerWidget {
  const AcceptingRow({this.compact = false, super.key});

  /// The tablet header's version: no leading label, chips only.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final settings = ref.watch(
      incomingProvider.select((s) => s.deliverySettings),
    );
    if (settings == null) return const SizedBox.shrink();
    final channels = <(String, String, String)>[
      if (settings.inMallEnabled)
        (
          'in_mall',
          bridge.tr(key: 'delivery.in_mall'),
          settings.inMallOverride,
        ),
      if (settings.outsideEnabled)
        (
          'outside',
          bridge.tr(key: 'delivery.outside'),
          settings.outsideOverride,
        ),
    ];
    if (channels.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!compact)
          Text(
            bridge.tr(key: 'delivery.accepting'),
            style: MadarType.label.copyWith(color: colors.textSecondary),
          ),
        for (final (channel, label, mode) in channels)
          _AcceptingChip(channel: channel, label: label, mode: mode),
      ],
    );
  }
}

class _AcceptingChip extends ConsumerWidget {
  const _AcceptingChip({
    required this.channel,
    required this.label,
    required this.mode,
  });

  final String channel;
  final String label;
  final String mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final tone = switch (mode) {
      'closed' => MadarTone.danger,
      'open' => MadarTone.success,
      _ => MadarTone.accent,
    };
    return TactileScale(
      onTap: () {
        if (ref.read(incomingProvider).isBusy) return;
        MadarHaptics.selection();
        unawaited(
          ref.read(incomingProvider.notifier).cycleAccepting(channel, mode),
        );
      },
      child: Container(
        height: Metrics.chipHeight,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.sm,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: tone.color(colors),
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 10),
            ),
            Text(
              '$label · ${bridge.tr(key: 'delivery.mode_$mode')}',
              style: MadarType.body.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Decline a NEW order. The reason is required here — the wire would take
/// none, but a refusal with no why is what the owner asks about the next
/// morning. Stock goes back: nothing was made.
class _DeclineSheet extends ConsumerStatefulWidget {
  const _DeclineSheet({required this.order});

  final DeliveryOrderView order;

  @override
  ConsumerState<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends ConsumerState<_DeclineSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) return;
    final ok = await ref
        .read(incomingProvider.notifier)
        .declineDelivery(widget.order, reason: reason);
    if (!mounted || !ok) return;
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final error = ref.watch(incomingProvider.select((s) => s.error));
    final busy = ref.watch(incomingProvider.select((s) => s.isBusy));
    final o = widget.order;
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.card),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Text(
            bridge.trOr(QueueKeys.decline),
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
          Row(
            spacing: Space.sm,
            children: [
              Flexible(
                child: Text(
                  o.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.body.copyWith(color: colors.textSecondary),
                ),
              ),
              if (o.orderRef case final ref?)
                FigureText(ref, color: colors.textSecondary),
            ],
          ),
          // A failed decline surfaces INSIDE the sheet — the board's banner
          // sits behind the modal scrim.
          if (error case final error?)
            NoticeBanner(
              text: error.of(ref.bridge),
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
          MadarField(
            controller: _reason,
            kind: MadarFieldKind.note,
            placeholder: bridge.trOr(QueueKeys.declineReason),
            glyph: MadarGlyph.note,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => unawaited(_confirm()),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _reason,
            builder: (_, v, _) => MadarButton(
              label: bridge.trOr(QueueKeys.decline),
              glyph: MadarGlyph.xCircle,
              variant: MadarButtonVariant.danger,
              enabled: v.text.trim().isNotEmpty,
              loading: busy,
              onTap: () => unawaited(_confirm()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cancel a live order later in its life: optional reason, the restock
/// switch, a danger confirm. Restock off = the food was made and is wasted
/// (the frozen plan is deducted + logged as waste in the core).
class _CancelSheet extends ConsumerStatefulWidget {
  const _CancelSheet({required this.order});

  final DeliveryOrderView order;

  @override
  ConsumerState<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends ConsumerState<_CancelSheet> {
  final _reason = TextEditingController();
  final _restock = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _reason.dispose();
    _restock.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final reason = _reason.text.trim();
    final ok = await ref
        .read(incomingProvider.notifier)
        .cancelDelivery(
          widget.order,
          reason: reason.isEmpty ? null : reason,
          restoreInventory: _restock.value,
        );
    if (!mounted || !ok) return;
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final error = ref.watch(incomingProvider.select((s) => s.error));
    final busy = ref.watch(incomingProvider.select((s) => s.isBusy));
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.card),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Text(
            bridge.tr(key: 'delivery.cancel'),
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
          Text(
            widget.order.customerName,
            style: MadarType.body.copyWith(color: colors.textSecondary),
          ),
          if (error case final error?)
            NoticeBanner(
              text: error.of(ref.bridge),
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
          MadarField(
            controller: _reason,
            kind: MadarFieldKind.note,
            placeholder: bridge.tr(key: 'delivery.cancel_reason'),
            glyph: MadarGlyph.note,
          ),
          Row(
            spacing: Space.sm,
            children: [
              Expanded(
                child: Text(
                  bridge.tr(key: 'delivery.restore_inventory'),
                  style: MadarType.body.copyWith(color: colors.textPrimary),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _restock,
                  builder: (_, restock, _) => MadarSegmented<bool>(
                    items: [
                      MadarSegmentItem(false, bridge.tr(key: 'toggle.off')),
                      MadarSegmentItem(true, bridge.tr(key: 'toggle.on')),
                    ],
                    value: restock,
                    onChanged: (value) => _restock.value = value,
                  ),
                ),
              ),
            ],
          ),
          MadarButton(
            label: bridge.tr(key: 'delivery.cancel'),
            glyph: MadarGlyph.xCircle,
            variant: MadarButtonVariant.danger,
            loading: busy,
            onTap: () => unawaited(_confirm()),
          ),
        ],
      ),
    );
  }
}
