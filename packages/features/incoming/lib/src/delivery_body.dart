import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_incoming/src/details_sheets.dart';
import 'package:feature_incoming/src/incoming_controller.dart';
import 'package:feature_incoming/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Delivery queue — the "Delivery" tab of the unified Orders surface. The
// teller works the branch's live delivery orders: advance the lifecycle,
// bump prep time, cancel (with restock), and finalize into a real sale on
// the open shift. All logic in the core; this only renders + collects.
// SSE is primary (the shell bumps [DeliveryBody.tick] on delivery events);
// a slow 60s poll is just a safety net. Port of DeliveryScreen.kt.

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

/// The delivery board body. The unified [tick] Listenable (shell-owned SSE
/// counter) triggers reloads; a 60s poll backstops it.
class DeliveryBody extends StatefulWidget {
  const DeliveryBody({required this.model, this.tick, super.key});

  final IncomingController model;

  /// Bumped by the shell on `delivery.*` realtime events.
  final Listenable? tick;

  @override
  State<DeliveryBody> createState() => _DeliveryBodyState();
}

class _DeliveryBodyState extends State<DeliveryBody> {
  Timer? _poll;

  IncomingController get _model => widget.model;

  @override
  void initState() {
    super.initState();
    unawaited(_model.loadDeliveryOrders());
    widget.tick?.addListener(_reload);
    _poll = Timer.periodic(
      _pollPeriod,
      (_) => unawaited(_model.loadDeliveryOrders()),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    widget.tick?.removeListener(_reload);
    super.dispose();
  }

  void _reload() => unawaited(_model.loadDeliveryOrders());

  // ── sheet launchers ────────────────────────────────────────────────────────
  /// Order-details overlay — the SHARED details layout (customer/address/
  /// channel + lines + money breakdown), the same surface the Open-tickets
  /// tab routes through. Finalize CTA pinned when the order is live.
  Future<void> _viewOrder(DeliveryOrderView o) async {
    final finalize = await showMadarSheet<bool>(
      context,
      size: SheetSize.large,
      maxWidth: Responsive.listMaxWidth,
      builder: (sheetContext) => DeliveryDetailsSheet(
        order: o,
        currency: _model.currency,
        tr: _model.tr,
        footer: o.isTerminal
            ? null
            : IncomingButton(
                label: _model.tr('delivery.finalize'),
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
      builder: (_) => _DeliveryFinalizeSheet(model: _model, order: o),
    );
  }

  /// Cancel stays a branded HUG sheet — one sheet idiom across the app.
  Future<void> _cancel(DeliveryOrderView o) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => _CancelSheet(model: _model, order: o),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final model = _model;
        final settings = model.deliverySettings;
        final error = model.error;
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
                          activeOnly: model.deliveryActiveOnly,
                          activeLabel: model.tr('delivery.active'),
                          allLabel: model.tr('delivery.all'),
                          onChange: (active) {
                            model.deliveryActiveOnly = active;
                            unawaited(model.loadDeliveryOrders());
                          },
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
                            model.tr('delivery.accepting'),
                            style: MadarType.labelSm.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                          _AcceptingChip(
                            model: model,
                            label: model.tr('delivery.in_mall'),
                            channel: 'in_mall',
                            mode: settings.inMallOverride,
                            enabled: settings.inMallEnabled,
                          ),
                          _AcceptingChip(
                            model: model,
                            label: model.tr('delivery.outside'),
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
            Expanded(child: _buildList(model, colors)),
          ],
        );
      },
    );
  }

  Widget _buildList(IncomingController model, MadarColors colors) {
    if (model.isLoadingDelivery && model.deliveryOrders.isEmpty) {
      return const Align(
        alignment: Alignment.topCenter,
        child: SkeletonList(),
      );
    }
    if (model.deliveryOrders.isEmpty) {
      // The natives' bespoke empty column (bicycle glyph + quiet line).
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.md,
          children: [
            MadarIcon('bicycle', tint: colors.textMuted, size: _emptyIcon),
            Text(
              model.tr('delivery.empty'),
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
      itemCount: model.deliveryOrders.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, index) {
        final o = model.deliveryOrders[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kBoardCardMaxWidth),
            child: _DeliveryOrderCard(
              model: model,
              order: o,
              onView: () => unawaited(_viewOrder(o)),
              onAdvance: () => unawaited(model.advanceDelivery(o)),
              onPrep: () => unawaited(model.addDeliveryPrep(o)),
              onFinalize: () => unawaited(_finalize(o)),
              onCancel: () => unawaited(_cancel(o)),
              onReject: () => unawaited(model.rejectDelivery(o)),
            ),
          ),
        );
      },
    );
  }
}

/// Per-channel accepting override chip — dashboard-disabled channels can't
/// be opened, shown muted. Tap cycles auto → open → closed.
class _AcceptingChip extends StatelessWidget {
  const _AcceptingChip({
    required this.model,
    required this.label,
    required this.channel,
    required this.mode,
    required this.enabled,
  });

  final IncomingController model;
  final String label;
  final String channel;
  final String mode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tone = !enabled
        ? ChipTone.neutral
        : switch (mode) {
            'closed' => ChipTone.danger,
            'open' => ChipTone.success,
            _ => ChipTone.accent,
          };
    final chip = StatusChip(
      label: '$label: ${model.tr('delivery.mode_$mode')}',
      tone: tone,
    );
    if (!enabled) {
      return Opacity(opacity: _disabledChipAlpha, child: chip);
    }
    return TactileScale(
      onTap: () {
        if (model.isBusy) return;
        MadarHaptics.selection();
        unawaited(model.cycleAccepting(channel, mode));
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
class _DeliveryOrderCard extends StatelessWidget {
  const _DeliveryOrderCard({
    required this.model,
    required this.order,
    required this.onView,
    required this.onAdvance,
    required this.onPrep,
    required this.onFinalize,
    required this.onCancel,
    required this.onReject,
  });

  final IncomingController model;
  final DeliveryOrderView order;
  final VoidCallback onView;
  final VoidCallback onAdvance;
  final VoidCallback onPrep;
  final VoidCallback onFinalize;
  final VoidCallback onCancel;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
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
                      model.tr('delivery.status.${o.status}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.body.copyWith(
                        fontSize: _statusLabelSize,
                        fontWeight: FontWeight.w900,
                        color: statusFg,
                      ),
                    ),
                  ),
                  StatusChip(label: model.tr('delivery.${o.channel}')),
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
                          currency: model.currency,
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
                        '${o.itemCount} ${model.tr('delivery.items')}',
                        style: MadarType.labelSm.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      if (o.deliveryFeeMinor > 0)
                        Flexible(
                          child: Text(
                            '· ${model.tr('receipt.delivery_fee')} '
                            '${Money.format(o.deliveryFeeMinor, currency: model.currency)}',
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
                          label: model.tr('order.view_order'),
                          icon: 'list.bullet',
                          variant: IncomingButtonVariant.outline,
                          expand: false,
                          onTap: onView,
                        ),
                        if (next != null)
                          Flexible(
                            child: IncomingButton(
                              label: model.tr('delivery.action.$next'),
                              icon: 'arrow.right.circle',
                              expand: false,
                              onTap: onAdvance,
                            ),
                          ),
                        const Spacer(),
                        _OverflowMenu(
                          model: model,
                          order: o,
                          onView: onView,
                          onPrep: onPrep,
                          onFinalize: onFinalize,
                          onCancel: onCancel,
                          onReject: onReject,
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
class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.model,
    required this.order,
    required this.onView,
    required this.onPrep,
    required this.onFinalize,
    required this.onCancel,
    required this.onReject,
  });

  final IncomingController model;
  final DeliveryOrderView order;
  final VoidCallback onView;
  final VoidCallback onPrep;
  final VoidCallback onFinalize;
  final VoidCallback onCancel;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
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
        item('list.bullet', model.tr('order.view_order'), onView),
        item('clock', model.tr('delivery.add_prep'), onPrep),
        item('checkmark.seal', model.tr('delivery.finalize'), onFinalize),
        // Reject is the terminal "refuse incoming work" action — only a
        // just-received order can be rejected (before any prep).
        if (order.status == 'received')
          item(
            'hand.raised',
            model.tr('delivery.reject'),
            onReject,
            danger: true,
          ),
        item(
          'xmark.circle',
          model.tr('delivery.cancel'),
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
/// [IncomingController.finalizeDelivery].
///
/// The backend finalize only needs the chosen payment method, so the
/// drawer's tip/split/cash-tendered extras are a cashier aid only and are
/// intentionally ignored here. Discount + customer capture are hidden (a
/// delivery order carries its own), matching settle.
class _DeliveryFinalizeSheet extends StatefulWidget {
  const _DeliveryFinalizeSheet({required this.model, required this.order});

  final IncomingController model;
  final DeliveryOrderView order;

  @override
  State<_DeliveryFinalizeSheet> createState() => _DeliveryFinalizeSheetState();
}

class _DeliveryFinalizeSheetState extends State<_DeliveryFinalizeSheet> {
  late final CheckoutController _checkout;

  @override
  void initState() {
    super.initState();
    _checkout = CheckoutController(
      core: widget.model.core,
      onStateChanged: widget.model.onStateChanged,
    );
    unawaited(_checkout.init());
  }

  @override
  void dispose() {
    _checkout.dispose();
    super.dispose();
  }

  Future<void> _finalize(CheckoutResult result) async {
    _checkout.error = null;
    final ok = await widget.model.finalizeDelivery(
      widget.order,
      result.primaryMethodId,
    );
    if (!mounted) return;
    if (ok) {
      await Navigator.of(context).maybePop();
    } else {
      // Surface the failure INSIDE the drawer (the natives' model.error) —
      // the board's own banner sits behind the modal scrim. The model's
      // pending notify rebuilds the ListenableBuilder above.
      _checkout.error = widget.model.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final o = widget.order;
    final label = model.tr('delivery.finalize');
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => CheckoutDrawer(
        controller: _checkout,
        // totalMinor includes the delivery fee → cash/change math correct.
        summary: CheckoutSummary(
          subtotalMinor: o.subtotalMinor,
          discountMinor: o.discountMinor,
          totalMinor: o.totalMinor,
        ),
        title: label,
        terminalLabel: label,
        terminalIcon: 'checkmark.seal',
        placing: model.isBusy,
        onClose: () => unawaited(Navigator.of(context).maybePop()),
        headerContent: _FinalizeHeader(model: model, order: o),
        onTerminal: (result) => unawaited(_finalize(result)),
      ),
    );
  }
}

/// Compact order review atop the finalize drawer — the teller sees WHO +
/// WHAT they're charging (customer, address, priced lines) before
/// tendering. The drawer's own summary card renders the money breakdown.
class _FinalizeHeader extends StatelessWidget {
  const _FinalizeHeader({required this.model, required this.order});

  final IncomingController model;
  final DeliveryOrderView order;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
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
                  o.orderRef ?? model.tr('delivery.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
              ),
              StatusChip(label: model.tr('delivery.${o.channel}')),
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
                  currency: model.currency,
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
class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.model, required this.order});

  final IncomingController model;
  final DeliveryOrderView order;

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final _reason = TextEditingController();
  bool _restock = true;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final reason = _reason.text.trim();
    final ok = await widget.model.cancelDelivery(
      widget.order,
      reason: reason.isEmpty ? null : reason,
      restoreInventory: _restock,
    );
    if (!mounted || !ok) return;
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final model = widget.model;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => Padding(
        padding: const EdgeInsetsDirectional.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Text(
              model.tr('delivery.cancel'),
              style: MadarType.h2.copyWith(color: colors.textPrimary),
            ),
            Text(
              widget.order.customerName,
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
            // A failed cancel surfaces INSIDE the sheet — the board's own
            // banner sits behind the modal scrim (the natives' model.error).
            if (model.error case final error?)
              NoticeBanner(
                text: error,
                tone: ChipTone.danger,
                icon: 'exclamationmark.circle',
              ),
            IncomingTextField(
              controller: _reason,
              placeholder: model.tr('delivery.cancel_reason'),
              icon: 'text.bubble',
            ),
            Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: Text(
                    model.tr('delivery.restore_inventory'),
                    style: MadarType.body.copyWith(color: colors.textPrimary),
                  ),
                ),
                Switch(
                  value: _restock,
                  activeTrackColor: colors.accent,
                  onChanged: (value) => setState(() => _restock = value),
                ),
              ],
            ),
            IncomingButton(
              label: model.tr('delivery.cancel'),
              icon: 'xmark.circle',
              variant: IncomingButtonVariant.danger,
              loading: model.isBusy,
              onTap: () => unawaited(_confirm()),
            ),
          ],
        ),
      ),
    );
  }
}

/// One forward lifecycle step from a wire status (received → confirmed →
/// preparing → ready → out_for_delivery → delivered); null when terminal.
String? _nextStatus(String status) => switch (status) {
  'received' => 'confirmed',
  'confirmed' => 'preparing',
  'preparing' => 'ready',
  'ready' => 'out_for_delivery',
  'out_for_delivery' => 'delivered',
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
