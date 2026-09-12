/// Queue › Online — the branch's live online orders as cards, one primary
/// button per card and always the next step:
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

/// Safety-net poll period under the SSE tick, only while realtime is down.
const Duration _pollPeriod = Duration(seconds: 60);

class OnlineSegment extends ConsumerStatefulWidget {
  const OnlineSegment({super.key});

  @override
  ConsumerState<OnlineSegment> createState() => _OnlineSegmentState();
}

class _OnlineSegmentState extends ConsumerState<OnlineSegment>
    with RealtimeGatedPoll<OnlineSegment> {
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
  Future<void> _charge(DeliveryOrderView o) async {
    final outcome = await showCharge(context, ChargeTarget.online(o));
    if (outcome == null || !mounted) return;
    await ref.read(incomingProvider.notifier).loadDeliveryOrders();
    ref.read(shellProvider.notifier).refresh();
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

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(bridgeProvider);
    // Backstop poll ONLY while realtime is down; connected relies on ticks.
    realtimeGatedPoll(interval: _pollPeriod, onPoll: _reload);
    final orders = ref.watch(incomingProvider.select((s) => s.deliveryOrders));
    final loading = ref.watch(
      incomingProvider.select((s) => s.isLoadingDelivery),
    );
    final stale = ref.watch(incomingProvider.select((s) => s.onlineStale));
    final error = ref.watch(incomingProvider.select((s) => s.error));
    final layout = context.madarLayout;
    final gutter = layout.gutter;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= kTwoColumnMinWidth ? 2 : 1;
        final banners = <Widget>[
          if (stale)
            NoticeBanner(
              text: bridge.trOr(QueueKeys.offlineNotice),
              icon: 'wifi.slash',
            ),
          if (error != null)
            NoticeBanner(
              text: error,
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
        ];
        Widget body;
        if (loading && orders.isEmpty && !stale) {
          body = const Align(
            alignment: Alignment.topCenter,
            child: SkeletonList(count: 3),
          );
        } else if (orders.isEmpty) {
          body = QuietEmpty(bridge.trOr(QueueKeys.emptyOnline));
        } else {
          body = _CardColumns(
            columns: columns,
            orders: orders,
            onView: _view,
            onCharge: _charge,
            onDecline: _decline,
            onCancel: _cancel,
          );
        }
        return ListView(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: gutter,
            vertical: Space.lg,
          ),
          children: [
            for (final b in banners)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: Space.md),
                child: b,
              ),
            body,
            const SizedBox(height: Space.md),
            // Accepting per channel stays at the foot of the segment on a
            // phone; the tablet header carries it too, via the screen.
            if (layout.isPhone) const AcceptingRow(),
            const SizedBox(height: Space.xxl),
          ],
        );
      },
    );
  }
}

/// Cards laid in one or two columns of variable height — dealt left/right
/// in order so the newest sit at the top of both. Its own widget so queue
/// churn (SSE ticks) rebuilds the cards, never the banners above.
class _CardColumns extends ConsumerWidget {
  const _CardColumns({
    required this.columns,
    required this.orders,
    required this.onView,
    required this.onCharge,
    required this.onDecline,
    required this.onCancel,
  });

  final int columns;
  final List<DeliveryOrderView> orders;
  final Future<void> Function(DeliveryOrderView o) onView;
  final Future<void> Function(DeliveryOrderView o) onCharge;
  final Future<void> Function(DeliveryOrderView o) onDecline;
  final Future<void> Function(DeliveryOrderView o) onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // New orders first (they want a hand), then by arrival.
    final sorted = [...orders]
      ..sort((a, b) {
        final ra = a.status == 'received' ? 0 : 1;
        final rb = b.status == 'received' ? 0 : 1;
        if (ra != rb) return ra - rb;
        return a.createdAt.compareTo(b.createdAt);
      });
    Widget card(DeliveryOrderView o) => _OnlineCard(
      key: ValueKey(o.id),
      order: o,
      onView: () => unawaited(onView(o)),
      onCharge: () => unawaited(onCharge(o)),
      onDecline: () => unawaited(onDecline(o)),
      onCancel: () => unawaited(onCancel(o)),
    );
    if (columns == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [for (final o in sorted) card(o)],
      );
    }
    final cols = List.generate(columns, (_) => <Widget>[]);
    for (final (i, o) in sorted.indexed) {
      cols[i % columns].add(card(o));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.lg,
      children: [
        for (final c in cols)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.lg,
              children: c,
            ),
          ),
      ],
    );
  }
}

/// One online order. The header names the state (tag), channel and ref;
/// the body the customer and what they owe; the foot the one next step.
/// A NEW card also lists the lines and the ready-in chips, because accept
/// is the moment the teller reads the order.
class _OnlineCard extends ConsumerStatefulWidget {
  const _OnlineCard({
    required this.order,
    required this.onView,
    required this.onCharge,
    required this.onDecline,
    required this.onCancel,
    super.key,
  });

  final DeliveryOrderView order;
  final VoidCallback onView;
  final VoidCallback onCharge;
  final VoidCallback onDecline;
  final VoidCallback onCancel;

  @override
  ConsumerState<_OnlineCard> createState() => _OnlineCardState();
}

class _OnlineCardState extends ConsumerState<_OnlineCard> {
  /// The chosen ready-in chip; null = the branch's base (preselected).
  final _readyIn = ValueNotifier<int?>(null);

  @override
  void dispose() {
    _readyIn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final o = widget.order;
    final busy = ref.watch(
      incomingProvider.select((s) => s.busyOrderIds.contains(o.id)),
    );
    final notice = ref.watch(incomingProvider.select((s) => s.notices[o.id]));
    final prepChoices = ref.watch(
      incomingProvider.select((s) => s.prepChoices),
    );
    final isNew = o.status == 'received';
    final tone = deliveryTone(o.status);
    final address = o.address;
    final notes = o.deliveryNotes;
    final hint = o.paymentHint;
    // The code and the figure are one word: never split across a wrap.
    final feeLabel =
        '${bridge.tr(key: 'receipt.delivery_fee')} '
        '${Money.format(o.deliveryFeeMinor, currency: currency).replaceAll(' ', '\u00A0')}';
    return MadarCard.column(
      onTap: isNew ? null : widget.onView,
      children: [
        // State · channel · ref · arrived-at.
        Row(
          spacing: Space.sm,
          children: [
            MadarTag(
              label: bridge.tr(key: 'delivery.status.${o.status}'),
              tone: tone,
              glyph: switch (o.status) {
                'received' => MadarGlyph.full,
                'preparing' => MadarGlyph.quarter,
                'ready' => MadarGlyph.check,
                'out_for_delivery' => MadarGlyph.bike,
                _ => MadarGlyph.half,
              },
            ),
            Flexible(
              child: Text(
                bridge.tr(key: 'delivery.${o.channel}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.bodySm.copyWith(color: colors.textSecondary),
              ),
            ),
            if (o.orderRef case final ref?)
              FigureText(
                ref,
                style: MadarType.numLg,
                color: colors.textPrimary,
              ),
            const Spacer(),
            FigureText(
              clockLabel(bridge, o.createdAt),
              style: MadarType.num,
              color: colors.textMuted,
            ),
          ],
        ),
        // Who.
        Row(
          spacing: Space.md,
          children: [
            Flexible(
              child: Text(
                o.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.h3.copyWith(color: colors.textPrimary),
              ),
            ),
            FigureText(
              o.customerPhone,
              style: MadarType.numMd,
              color: colors.textSecondary,
            ),
          ],
        ),
        if (isNew && address != null && address.isNotEmpty)
          Text(
            address,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MadarType.body.copyWith(
              fontWeight: FontWeight.w400,
              color: colors.textSecondary,
            ),
          ),
        if (isNew && notes != null && notes.isNotEmpty)
          Text(
            '“$notes”',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MadarType.body.copyWith(
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w400,
              color: colors.textSecondary,
            ),
          ),
        // What. A NEW card lists the lines; the rest only count them.
        if (isNew)
          _LinesBlock(order: o, currency: currency)
        else
          Row(
            spacing: Space.sm,
            children: [
              Expanded(
                child: Text(
                  [
                    '${o.itemCount} ${bridge.tr(key: 'delivery.items')}',
                    if (o.deliveryFeeMinor > 0) feeLabel,
                    if (hint != null && hint.isNotEmpty) hint,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(color: colors.textSecondary),
                ),
              ),
              MoneyText(
                o.totalMinor,
                currency: currency,
                style: MadarType.moneyMd,
                color: colors.textPrimary,
              ),
            ],
          ),
        if (notice != null)
          CardNotice(
            text: notice,
            onDismiss: () =>
                ref.read(incomingProvider.notifier).clearNotice(o.id),
          ),
        // READY IN — only while the base is known; a chip whose minutes we
        // cannot name is not offered, and Accept then just accepts.
        if (isNew && prepChoices != null) ...[
          MadarSectionHeader(
            text: bridge.trOr(QueueKeys.readyIn),
            trailing: bridge.trMaybe(QueueKeys.minutes) == null
                ? null
                : Text(
                    bridge.trMaybe(QueueKeys.minutes)!,
                    style: MadarType.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
          ),
          ValueListenableBuilder<int?>(
            valueListenable: _readyIn,
            builder: (_, chosen, _) => Row(
              spacing: Space.sm,
              children: [
                for (final m in prepChoices)
                  Expanded(
                    child: MadarChip.tile(
                      label: '$m',
                      selected: (chosen ?? prepChoices.first) == m,
                      onTap: () => _readyIn.value = m,
                    ),
                  ),
              ],
            ),
          ),
        ],
        _Actions(
          order: o,
          busy: busy,
          onPrimary: () {
            switch (o.status) {
              case 'received':
                unawaited(
                  ref
                      .read(incomingProvider.notifier)
                      .acceptDelivery(
                        o,
                        readyInMinutes: _readyIn.value ?? prepChoices?.first,
                      ),
                );
              case 'out_for_delivery':
                widget.onCharge();
              default:
                unawaited(
                  ref.read(incomingProvider.notifier).advanceDelivery(o),
                );
            }
          },
          onView: widget.onView,
          onDecline: widget.onDecline,
          onCancel: widget.onCancel,
        ),
      ],
    );
  }
}

/// The priced lines on a NEW order, then fee · payment hint · total.
class _LinesBlock extends ConsumerWidget {
  const _LinesBlock({required this.order, required this.currency});

  final DeliveryOrderView order;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final o = order;
    final hint = o.paymentHint;
    // The code and the figure are one word: never split across a wrap.
    final feeLabel =
        '${bridge.tr(key: 'receipt.delivery_fee')} '
        '${Money.format(o.deliveryFeeMinor, currency: currency).replaceAll(' ', '\u00A0')}';
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Column(
        children: [
          for (final line in o.lines)
            SizedBox(
              height: kLineRowHeight,
              child: Row(
                spacing: Space.sm,
                children: [
                  FigureText(
                    '${line.qty}×',
                    style: MadarType.num,
                    color: colors.textSecondary,
                  ),
                  Expanded(
                    child: Text(
                      [
                        line.name,
                        if (line.sizeLabel case final s? when s.isNotEmpty) s,
                        ...line.modifiers,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.body.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  MoneyText(
                    line.lineTotalMinor,
                    currency: currency,
                    style: MadarType.num,
                    color: colors.textPrimary,
                  ),
                ],
              ),
            ),
          Container(
            constraints: const BoxConstraints(minHeight: kLineRowHeight),
            padding: const EdgeInsetsDirectional.symmetric(vertical: Space.xs),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.borderLight)),
            ),
            child: Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: Text(
                    [
                      if (o.deliveryFeeMinor > 0) feeLabel,
                      if (o.discountMinor > 0)
                        '−${Money.format(o.discountMinor, currency: currency)}',
                      if (hint != null && hint.isNotEmpty) hint,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                MoneyText(
                  o.totalMinor,
                  currency: currency,
                  style: MadarType.moneyMd,
                  color: colors.textPrimary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The card's foot: one primary (the next step), a quiet View, and ⋯ with
/// Cancel. A NEW card has Decline in place of View and no ⋯ — declining IS
/// its cancel.
class _Actions extends ConsumerWidget {
  const _Actions({
    required this.order,
    required this.busy,
    required this.onPrimary,
    required this.onView,
    required this.onDecline,
    required this.onCancel,
  });

  final DeliveryOrderView order;
  final bool busy;
  final VoidCallback onPrimary;
  final VoidCallback onView;
  final VoidCallback onDecline;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final o = order;
    final next = nextDeliveryStatus(o.status);
    final primaryLabel = switch (o.status) {
      'received' => bridge.trOr(QueueKeys.accept),
      'out_for_delivery' => bridge.trOr(QueueKeys.chargeOnline),
      'ready' when o.channel == 'pickup' => bridge.trOr(QueueKeys.pickedUp),
      _ => bridge.tr(key: 'delivery.action.$next'),
    };
    final isNew = o.status == 'received';
    return Row(
      spacing: Space.sm,
      children: [
        if (isNew)
          MadarButton(
            label: bridge.trOr(QueueKeys.decline),
            variant: MadarButtonVariant.ghost,
            size: MadarButtonSize.compact,
            enabled: !busy,
            onTap: onDecline,
          )
        else
          MadarButton(
            label: bridge.trOr(QueueKeys.view),
            variant: MadarButtonVariant.secondary,
            size: MadarButtonSize.compact,
            onTap: onView,
          ),
        Expanded(
          child: MadarButton(
            label: primaryLabel,
            size: isNew ? MadarButtonSize.regular : MadarButtonSize.compact,
            glyph: o.status == 'out_for_delivery'
                ? MadarGlyph.banknote
                : MadarGlyph.chevronForward,
            loading: busy,
            onTap: onPrimary,
          ),
        ),
        if (!isNew) _More(onView: onView, onCancel: onCancel),
      ],
    );
  }
}

/// The ⋯ — View, and Cancel (with the restock toggle in its sheet).
class _More extends ConsumerWidget {
  const _More({required this.onView, required this.onCancel});

  final VoidCallback onView;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
            side: BorderSide(color: colors.borderLight),
          ),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: onView,
          leadingIcon: MadarGlyphIcon(
            MadarGlyph.list,
            color: colors.textSecondary,
          ),
          child: Text(
            bridge.tr(key: 'order.view_order'),
            style: MadarType.body.copyWith(color: colors.textPrimary),
          ),
        ),
        MenuItemButton(
          onPressed: onCancel,
          leadingIcon: MadarGlyphIcon(MadarGlyph.xCircle, color: colors.danger),
          child: Text(
            bridge.tr(key: 'delivery.cancel'),
            style: MadarType.body.copyWith(color: colors.danger),
          ),
        ),
      ],
      builder: (context, menu, _) => MadarGlyphTile(
        glyph: MadarGlyph.more,
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
      ),
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
    final bridge = ref.watch(bridgeProvider);
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
    final bridge = ref.watch(bridgeProvider);
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
    final bridge = ref.watch(bridgeProvider);
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
              text: error,
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
          MadarField(
            controller: _reason,
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
    final bridge = ref.watch(bridgeProvider);
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
              text: error,
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
          MadarField(
            controller: _reason,
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
              ValueListenableBuilder<bool>(
                valueListenable: _restock,
                builder: (_, restock, _) => Switch(
                  value: restock,
                  activeTrackColor: colors.accent,
                  onChanged: (value) => _restock.value = value,
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
