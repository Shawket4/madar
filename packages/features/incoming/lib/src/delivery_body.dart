import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_incoming/src/details_sheets.dart';
import 'package:feature_incoming/src/incoming_provider.dart';
import 'package:feature_incoming/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Delivery queue — the "Delivery" tab of the unified Orders surface. The
// teller works the branch's live delivery orders: advance the lifecycle,
// bump prep time, cancel (with restock), and finalize into a real sale on
// the open shift. All logic in the core; this only renders + collects.
// SSE is primary (the screen reloads on [deliveryTickProvider]); a slow
// 60s poll is just a safety net. Port of DeliveryScreen.kt.

// Native metrics (DeliveryScreen.kt) kept verbatim.

/// Safety-net poll period under the SSE tick (natives: 60_000 ms).
const Duration _pollPeriod = Duration(seconds: 60);

/// Status label size in the tinted strip (natives: 14.sp Black).
const double _statusLabelSize = 14;

/// Order-ref money size in the strip (natives: 13.sp Bold).
const double _stripRefSize = 13;

/// Customer name size (natives: 16.sp Bold).
const double _customerNameSize = 16;

/// Card money hero size (natives: 17.sp Black).
const double _cardMoneySize = 17;

/// Segmented-toggle inner inset / gap (natives: 2.dp).
const double _segPad = 2;

/// Segmented-toggle segment vertical inset (natives: 6.dp).
const double _segVPad = 6;

/// Empty-state glyph size (natives: 40.dp).
const double _emptyIcon = 40;

/// Dashboard-disabled accepting chip alpha (natives: 0.5f).
const double _disabledChipAlpha = 0.5;

/// The delivery board body. The screen-level [deliveryTickProvider] listen
/// (shell-owned SSE counter) triggers reloads; a 60s poll backstops it.
class DeliveryBody extends ConsumerStatefulWidget {
  const DeliveryBody({super.key});

  @override
  ConsumerState<DeliveryBody> createState() => _DeliveryBodyState();
}

class _DeliveryBodyState extends ConsumerState<DeliveryBody>
    with RealtimeGatedPoll<DeliveryBody> {
  @override
  void initState() {
    super.initState();
    // (Re)entering the tab refreshes the queue — deferred a microtask
    // because provider writes are illegal while the tree is building.
    unawaited(
      Future<void>.microtask(() {
        if (mounted) _reload();
      }),
    );
    // The 60s backstop now runs ONLY while realtime is disconnected (wired in
    // build via RealtimeGatedPoll) — a connected board relies on the
    // `delivery.*`/`order.*` ticks.
  }

  void _reload() =>
      unawaited(ref.read(incomingProvider.notifier).loadDeliveryOrders());

  // ── sheet launchers ────────────────────────────────────────────────────────
  /// Order-details overlay — the SHARED details layout (customer/address/
  /// channel + lines + money breakdown), the same surface the Open-tickets
  /// tab routes through. Finalize CTA pinned when the order is live.
  Future<void> _viewOrder(DeliveryOrderView o) async {
    final bridge = ref.read(bridgeProvider);
    final finalize = await showMadarSheet<bool>(
      context,
      size: SheetSize.large,
      maxWidth: Responsive.listMaxWidth,
      builder: (sheetContext) => DeliveryDetailsSheet(
        order: o,
        footer: o.isTerminal
            ? null
            : IncomingButton(
                label: bridge.tr(key: 'delivery.finalize'),
                icon: 'checkmark.seal',
                onTap: () =>
                    unawaited(Navigator.of(sheetContext).maybePop(true)),
              ),
      ),
    );
    if (!mounted || finalize != true) return;
    await _finalize(o);
  }

  /// Finalize routes through the ONE shared CheckoutDrawer (same as the
  /// cashier checkout and the ticket settle) — no mirrored payment picker.
  Future<void> _finalize(DeliveryOrderView o) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => _DeliveryFinalizeSheet(order: o),
    );
  }

  /// Cancel stays a branded HUG sheet — one sheet idiom across the app.
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
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final notifier = ref.read(incomingProvider.notifier);
    // Backstop poll ONLY while realtime is down; connected relies on ticks.
    realtimeGatedPoll(interval: _pollPeriod, onPoll: _reload);
    final activeOnly = ref.watch(
      incomingProvider.select((s) => s.deliveryActiveOnly),
    );
    final settings = ref.watch(
      incomingProvider.select((s) => s.deliverySettings),
    );
    final error = ref.watch(incomingProvider.select((s) => s.error));
    return Column(
      children: [
        // Active/All filter toolbar (the unified header owns back+title).
        ColoredBox(
          color: colors.surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.sm,
                ),
                child: Row(
                  children: [
                    const Spacer(),
                    _SegToggle(
                      activeOnly: activeOnly,
                      activeLabel: bridge.tr(key: 'delivery.active'),
                      allLabel: bridge.tr(key: 'delivery.all'),
                      onChange: (active) =>
                          notifier.setDeliveryActiveOnly(activeOnly: active),
                    ),
                  ],
                ),
              ),
              const IncomingHairline(),
            ],
          ),
        ),
        // Accepting chips (in-mall / outside: auto → open → closed).
        if (settings != null)
          ColoredBox(
            color: colors.surface,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.sm,
                  ),
                  child: Row(
                    spacing: Space.sm,
                    children: [
                      Text(
                        bridge.tr(key: 'delivery.accepting'),
                        style: MadarType.labelSm.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      _AcceptingChip(
                        label: bridge.tr(key: 'delivery.in_mall'),
                        channel: 'in_mall',
                        mode: settings.inMallOverride,
                        enabled: settings.inMallEnabled,
                      ),
                      _AcceptingChip(
                        label: bridge.tr(key: 'delivery.outside'),
                        channel: 'outside',
                        mode: settings.outsideOverride,
                        enabled: settings.outsideEnabled,
                      ),
                    ],
                  ),
                ),
                const IncomingHairline(),
              ],
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsetsDirectional.all(Space.lg),
            child: NoticeBanner(
              text: error,
              icon: 'exclamationmark.circle',
            ),
          ),
        Expanded(child: _buildList(colors)),
      ],
    );
  }

  Widget _buildList(MadarColors colors) {
    final bridge = ref.watch(bridgeProvider);
    final notifier = ref.read(incomingProvider.notifier);
    final orders = ref.watch(
      incomingProvider.select((s) => s.deliveryOrders),
    );
    final loading = ref.watch(
      incomingProvider.select((s) => s.isLoadingDelivery),
    );
    if (loading && orders.isEmpty) {
      return const Align(
        alignment: Alignment.topCenter,
        child: SkeletonList(),
      );
    }
    if (orders.isEmpty) {
      // The natives' bespoke empty column (bicycle glyph + quiet line).
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.md,
          children: [
            MadarIcon('bicycle', tint: colors.textMuted, size: _emptyIcon),
            Text(
              bridge.tr(key: 'delivery.empty'),
              style: MadarType.body.copyWith(
                fontWeight: FontWeight.w400,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, index) {
        final o = orders[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kBoardCardMaxWidth),
            child: _DeliveryOrderCard(
              order: o,
              onView: () => unawaited(_viewOrder(o)),
              onAdvance: () => unawaited(notifier.advanceDelivery(o)),
              onPrep: () => unawaited(notifier.addDeliveryPrep(o)),
              onFinalize: () => unawaited(_finalize(o)),
              onCancel: () => unawaited(_cancel(o)),
            ),
          ),
        );
      },
    );
  }
}

/// Per-channel accepting override chip — dashboard-disabled channels can't
/// be opened, shown muted. Tap cycles auto → open → closed.
class _AcceptingChip extends ConsumerWidget {
  const _AcceptingChip({
    required this.label,
    required this.channel,
    required this.mode,
    required this.enabled,
  });

  final String label;
  final String channel;
  final String mode;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final tone = !enabled
        ? ChipTone.neutral
        : switch (mode) {
            'closed' => ChipTone.danger,
            'open' => ChipTone.success,
            _ => ChipTone.accent,
          };
    final chip = StatusChip(
      label: '$label: ${bridge.tr(key: 'delivery.mode_$mode')}',
      tone: tone,
    );
    if (!enabled) {
      return Opacity(opacity: _disabledChipAlpha, child: chip);
    }
    return TactileScale(
      onTap: () {
        if (ref.read(incomingProvider).isBusy) return;
        MadarHaptics.selection();
        unawaited(
          ref.read(incomingProvider.notifier).cycleAccepting(channel, mode),
        );
      },
      child: chip,
    );
  }
}

/// Active/All segmented toggle (teal active fill on a surface-alt track).
class _SegToggle extends StatelessWidget {
  const _SegToggle({
    required this.activeOnly,
    required this.activeLabel,
    required this.allLabel,
    required this.onChange,
  });

  final bool activeOnly;
  final String activeLabel;
  final String allLabel;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    Widget seg(String label, {required bool on, required bool value}) {
      return TactileScale(
        onTap: () {
          MadarHaptics.selection();
          onChange(value);
        },
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.md,
            vertical: _segVPad,
          ),
          decoration: BoxDecoration(
            color: on ? colors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm - _segPad),
          ),
          child: Text(
            label,
            style: MadarType.label.copyWith(
              color: on ? colors.textOnAccent : colors.textSecondary,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsetsDirectional.all(_segPad),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: _segPad,
        children: [
          seg(activeLabel, on: activeOnly, value: true),
          seg(allLabel, on: !activeOnly, value: false),
        ],
      ),
    );
  }
}

/// One delivery order card — a status-tinted header strip (the lifecycle
/// reads from across the room), the customer + money hero, address/notes,
/// then the action row (View / advance / ⋯ menu) while the order is live.
/// Hot path: watches only the bridge handle + the currency slice.
class _DeliveryOrderCard extends ConsumerWidget {
  const _DeliveryOrderCard({
    required this.order,
    required this.onView,
    required this.onAdvance,
    required this.onPrep,
    required this.onFinalize,
    required this.onCancel,
  });

  final DeliveryOrderView order;
  final VoidCallback onView;
  final VoidCallback onAdvance;
  final VoidCallback onPrep;
  final VoidCallback onFinalize;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final o = order;
    final (statusFg, statusBg) = _statusTint(o.status, colors);
    final next = _nextStatus(o.status);
    final address = o.address;
    final deliveryNotes = o.deliveryNotes;
    return GestureDetector(
      // Tap the card to review the full order (lines + money + context).
      onTap: onView,
      behavior: HitTestBehavior.opaque,
      child: IncomingCard(
        clip: true,
        padding: EdgeInsetsDirectional.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status-tinted header strip — fixed height so every card's
            // body starts at the same y. Status + channel chips lead; the
            // order ref pins to the trailing edge.
            Container(
              height: kDeliveryStripHeight,
              color: statusBg,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Space.md,
              ),
              child: Row(
                spacing: Space.sm,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: statusFg,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: kStatusDot),
                  ),
                  Flexible(
                    child: Text(
                      bridge.tr(key: 'delivery.status.${o.status}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.body.copyWith(
                        fontSize: _statusLabelSize,
                        fontWeight: FontWeight.w900,
                        color: statusFg,
                      ),
                    ),
                  ),
                  StatusChip(label: bridge.tr(key: 'delivery.${o.channel}')),
                  const Spacer(),
                  if (o.orderRef case final ref?)
                    Text(
                      ref,
                      textDirection: TextDirection.ltr,
                      style: MadarType.money.copyWith(
                        fontSize: _stripRefSize,
                        color: statusFg,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.sm,
                children: [
                  // Customer header — leading tone-tile + name/phone, money
                  // as the hero in a tinted teal block on the trailing edge.
                  Row(
                    spacing: Space.sm,
                    children: [
                      Container(
                        width: kPersonTile,
                        height: kPersonTile,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.accentBg,
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        child: MadarIcon(
                          'person.fill',
                          tint: colors.accent,
                          size: IconSize.lg,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: Space.xs / 2,
                          children: [
                            Text(
                              o.customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MadarType.body.copyWith(
                                fontSize: _customerNameSize,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            Text(
                              o.customerPhone,
                              style: MadarType.label.copyWith(
                                fontWeight: FontWeight.w500,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: Space.md,
                          vertical: kMoneyPillVPad,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accentBg,
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        child: MoneyText(
                          o.totalMinor,
                          currency: currency,
                          style: MadarType.money.copyWith(
                            fontSize: _cardMoneySize,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (address != null && address.isNotEmpty)
                    Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.textSecondary,
                      ),
                    ),
                  // Customer delivery instructions — warning-tinted inset
                  // so the dispatcher can't miss them.
                  if (deliveryNotes != null && deliveryNotes.isNotEmpty)
                    DeliveryNoteInset(note: deliveryNotes),
                  Row(
                    spacing: Space.sm,
                    children: [
                      Text(
                        '${o.itemCount} ${bridge.tr(key: 'delivery.items')}',
                        style: MadarType.labelSm.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      if (o.deliveryFeeMinor > 0)
                        Flexible(
                          child: Text(
                            '· ${bridge.tr(key: 'receipt.delivery_fee')} '
                            '${Money.format(o.deliveryFeeMinor, currency: currency)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MadarType.labelSm.copyWith(
                              fontWeight: FontWeight.w500,
                              color: colors.textMuted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (!o.isTerminal)
                    Row(
                      spacing: Space.sm,
                      children: [
                        // Visible "View order" — the same OUTLINE affordance
                        // the open-tickets card exposes.
                        IncomingButton(
                          label: bridge.tr(key: 'order.view_order'),
                          icon: 'list.bullet',
                          variant: IncomingButtonVariant.outline,
                          expand: false,
                          onTap: onView,
                        ),
                        if (next != null)
                          Flexible(
                            child: IncomingButton(
                              label: bridge.tr(key: 'delivery.action.$next'),
                              icon: 'arrow.right.circle',
                              expand: false,
                              onTap: onAdvance,
                            ),
                          )
                        else
                          // Out for delivery is the last advance step — the
                          // primary action becomes Settle (finalize into a
                          // real sale, then show the receipt).
                          Flexible(
                            child: IncomingButton(
                              label: bridge.tr(key: 'delivery.finalize'),
                              icon: 'checkmark.seal',
                              expand: false,
                              onTap: onFinalize,
                            ),
                          ),
                        const Spacer(),
                        _OverflowMenu(
                          order: o,
                          onView: onView,
                          onPrep: onPrep,
                          onFinalize: onFinalize,
                          onCancel: onCancel,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ⋯ menu — view / +5 min prep / finalize / reject (received only) /
/// cancel. Mirrors the natives' DropdownMenu on the 34-dp ellipsis box.
class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({
    required this.order,
    required this.onView,
    required this.onPrep,
    required this.onFinalize,
    required this.onCancel,
  });

  final DeliveryOrderView order;
  final VoidCallback onView;
  final VoidCallback onPrep;
  final VoidCallback onFinalize;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    MenuItemButton item(
      String icon,
      String label,
      VoidCallback onTap, {
      bool danger = false,
    }) {
      final fg = danger ? colors.danger : colors.textPrimary;
      return MenuItemButton(
        onPressed: onTap,
        leadingIcon: MadarIcon(
          icon,
          tint: danger ? colors.danger : colors.textSecondary,
        ),
        child: Text(
          label,
          style: MadarType.body.copyWith(color: fg),
        ),
      );
    }

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.sm),
            side: BorderSide(color: colors.borderLight),
          ),
        ),
      ),
      menuChildren: [
        item('list.bullet', bridge.tr(key: 'order.view_order'), onView),
        item('clock', bridge.tr(key: 'delivery.add_prep'), onPrep),
        item(
          'checkmark.seal',
          bridge.tr(key: 'delivery.finalize'),
          onFinalize,
        ),
        // ONE terminal action: Cancel — the sheet carries the restock
        // toggle (restock = the old "reject", waste = food already made).
        item(
          'xmark.circle',
          bridge.tr(key: 'delivery.cancel'),
          onCancel,
          danger: true,
        ),
      ],
      builder: (context, menu, _) => TactileScale(
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Container(
          width: kMenuButton,
          height: kMenuButton,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: colors.borderLight),
          ),
          child: MadarIcon(
            'ellipsis',
            tint: colors.textSecondary,
            size: IconSize.lg,
          ),
        ),
      ),
    );
  }
}

/// Finalize a delivery order through the SHARED [CheckoutDrawer] — the SAME
/// payment/cash/tip flow as the cashier checkout and the ticket settle. The
/// order's review rides in as the drawer's header, the delivery total drives
/// the summary (so cash/change math includes the delivery fee), and the
/// terminal action finalizes into a real sale via
/// [IncomingNotifier.finalizeDelivery].
///
/// The backend finalize only needs the chosen payment method, so the
/// drawer's tip/split/cash-tendered extras are a cashier aid only and are
/// intentionally ignored here. Discount + customer capture are hidden (a
/// delivery order carries its own), matching settle.
class _DeliveryFinalizeSheet extends ConsumerStatefulWidget {
  const _DeliveryFinalizeSheet({required this.order});

  final DeliveryOrderView order;

  @override
  ConsumerState<_DeliveryFinalizeSheet> createState() =>
      _DeliveryFinalizeSheetState();
}

class _DeliveryFinalizeSheetState
    extends ConsumerState<_DeliveryFinalizeSheet> {
  @override
  void initState() {
    super.initState();
    // Fresh settle session over the delivery money — deferred a microtask
    // because provider writes are illegal while the tree is building.
    // totalMinor includes the delivery fee → cash/change math correct.
    unawaited(
      Future<void>.microtask(() {
        if (!mounted) return;
        final o = widget.order;
        unawaited(
          ref
              .read(checkoutProvider.notifier)
              .startSettle(
                CheckoutSummary(
                  subtotalMinor: o.subtotalMinor,
                  discountMinor: o.discountMinor,
                  totalMinor: o.totalMinor,
                ),
              ),
        );
      }),
    );
  }

  Future<void> _finalize(CheckoutResult result) async {
    final checkout = ref.read(checkoutProvider.notifier)..setError(null);
    final bridge = ref.read(bridgeProvider);
    // Captured before any await — this sheet unmounts when the drawer pops,
    // so the receipt is presented on the PARENT navigator, not our context.
    final navigator = Navigator.of(context);
    final res = await ref
        .read(incomingProvider.notifier)
        .finalizeDelivery(widget.order, result.primaryMethodId);
    if (!mounted) return;
    if (res == null) {
      // Surface the failure INSIDE the drawer (the natives' model.error) —
      // the board's own banner sits behind the modal scrim.
      checkout.setError(ref.read(incomingProvider).error);
      return;
    }
    // The sale is booked — swap the drawer for the receipt of the real
    // order the finalize created (best-effort: fetch the receipt view;
    // if it's not resolvable, the success toast already fired).
    ReceiptView? receipt;
    try {
      receipt = await bridge.orderReceiptView(orderId: res.orderId);
    } on Object {
      receipt = null;
    }
    await navigator.maybePop();
    if (receipt != null) {
      await navigator.push(
        MadarSheetRoute<void>(
          builder: (_) => ReceiptSheet(receipt: receipt!, celebrate: true),
          size: SheetSize.large,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(bridgeProvider);
    final placing = ref.watch(incomingProvider.select((s) => s.isBusy));
    final o = widget.order;
    final label = bridge.tr(key: 'delivery.finalize');
    return CheckoutDrawer(
      title: label,
      terminalLabel: label,
      terminalIcon: 'checkmark.seal',
      placing: placing,
      onClose: () => unawaited(Navigator.of(context).maybePop()),
      headerContent: _FinalizeHeader(order: o),
      onTerminal: (result) => unawaited(_finalize(result)),
    );
  }
}

/// Compact order review atop the finalize drawer — the teller sees WHO +
/// WHAT they're charging (customer, address, priced lines) before
/// tendering. The drawer's own summary card renders the money breakdown.
class _FinalizeHeader extends ConsumerWidget {
  const _FinalizeHeader({required this.order});

  final DeliveryOrderView order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final o = order;
    final address = o.address;
    return IncomingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          Row(
            spacing: Space.sm,
            children: [
              MadarIcon('bicycle', tint: colors.accent, size: IconSize.lg),
              Flexible(
                child: Text(
                  o.orderRef ?? bridge.tr(key: 'delivery.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
              ),
              StatusChip(label: bridge.tr(key: 'delivery.${o.channel}')),
            ],
          ),
          Text(
            o.customerName,
            style: MadarType.bodySm.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
          if (address != null && address.isNotEmpty)
            Text(
              address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MadarType.label.copyWith(
                fontWeight: FontWeight.w400,
                color: colors.textMuted,
              ),
            ),
          for (final line in o.lines)
            Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: Text(
                    '${line.qty}× ${line.name}',
                    style: MadarType.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                MoneyText(
                  line.lineTotalMinor,
                  currency: currency,
                  style: MadarType.money.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  color: colors.textPrimary,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Cancel sheet — optional reason, the restock switch, and a danger
/// confirm. `restore_inventory = false` means the food was made and is
/// wasted (the frozen plan is deducted + logged as waste in the core).
class _CancelSheet extends ConsumerStatefulWidget {
  const _CancelSheet({required this.order});

  final DeliveryOrderView order;

  @override
  ConsumerState<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends ConsumerState<_CancelSheet> {
  final _reason = TextEditingController();

  /// Restock toggle — widget-local ephemera driven through a
  /// [ValueListenableBuilder] (no setState).
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
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(
            bridge.tr(key: 'delivery.cancel'),
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
          Text(
            widget.order.customerName,
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
          // A failed cancel surfaces INSIDE the sheet — the board's own
          // banner sits behind the modal scrim (the natives' model.error).
          if (error case final error?)
            NoticeBanner(
              text: error,
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
          IncomingTextField(
            controller: _reason,
            placeholder: bridge.tr(key: 'delivery.cancel_reason'),
            icon: 'text.bubble',
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
          IncomingButton(
            label: bridge.tr(key: 'delivery.cancel'),
            icon: 'xmark.circle',
            variant: IncomingButtonVariant.danger,
            loading: busy,
            onTap: () => unawaited(_confirm()),
          ),
        ],
      ),
    );
  }
}

/// One forward lifecycle step the STATUS endpoint accepts (received →
/// confirmed → preparing → ready → out_for_delivery). `delivered` is NOT a
/// settable advance target on the backend — it's reached only by finalizing
/// (settling) the order into a real sale — so `out_for_delivery` returns
/// null here and the card offers Settle instead of another advance.
String? _nextStatus(String status) => switch (status) {
  'received' => 'confirmed',
  'confirmed' => 'preparing',
  'preparing' => 'ready',
  'ready' => 'out_for_delivery',
  _ => null,
};

/// Status → (foreground, tinted-background) pair for the card's header
/// strip. Mirrors the Kitchen ticket's age-tint pattern so the lifecycle
/// reads at a glance.
(Color, Color) _statusTint(String status, MadarColors colors) =>
    switch (status) {
      'received' => (colors.navy, colors.navyBg),
      'confirmed' || 'out_for_delivery' => (colors.accent, colors.accentBg),
      'preparing' => (colors.warning, colors.warningBg),
      'ready' || 'delivered' => (colors.success, colors.successBg),
      'cancelled' || 'rejected' => (colors.danger, colors.dangerBg),
      _ => (colors.textSecondary, colors.surfaceAlt),
    };
