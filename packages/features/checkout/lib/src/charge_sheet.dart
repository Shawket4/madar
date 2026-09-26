import 'dart:async';
import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/charge_strings.dart';
import 'package:feature_checkout/src/charge_target.dart';
import 'package:feature_checkout/src/checkout_provider.dart';
import 'package:feature_checkout/src/customer_card.dart';
import 'package:feature_checkout/src/customer_sheet.dart';
import 'package:feature_checkout/src/discount_sheet.dart';
import 'package:feature_checkout/src/done_card.dart';
import 'package:feature_checkout/src/loyalty_scan_sheet.dart';
import 'package:feature_checkout/src/loyalty_words.dart';
import 'package:feature_checkout/src/manager_approval_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The modal's width on a tablet: two columns — how they pay on the start
/// side, what is owed, handed over and given back on the end side.
const double _modalWidth = 880;

/// The end column of the tablet modal: the figures and the one Charge.
const double _readoutWidth = 340;

/// The tablet modal's height cap — a two-column body needs a bounded height,
/// and the figures sit at the foot of the end column where the thumb is.
const double _modalMaxHeight = 700;

/// How much of the window the modal may take before its middle scrolls.
const double _modalHeightFraction = 0.92;

/// The hero figure — 44 on a tablet, 34 on a phone (the canvas's 44 does
/// not fit "EGP 1,234.00" beside a 16px gutter).
const double _heroTablet = 44;
const double _heroPhone = 34;

/// The hero block's corner and inset (the canvas: 14 / 16).
const double _heroRadius = 14;
const double _heroPad = 16;

/// A quiet row (Discount, Member) and the tip link (the canvas: 52 / 40).
const double _quietRow = 52;
const double _linkRow = 40;

/// A reward line under the member row.
const double _rewardRow = 44;

/// The Exact button takes 1.6× a preset's width (the canvas's flex).
const int _exactFlex = 16;
const int _presetFlex = 10;

/// A method tile's width band inside the [Wrap] — wide enough that "Cash"
/// doesn't read as a stray chip, capped so one very long or Arabic name
/// wraps its OWN text with an ellipsis rather than stretching the tile (and
/// the row) past what should just flow to a second line.
const double _methodTileMinWidth = 132;
const double _methodTileMaxWidth = 208;

/// Present Charge for [target] and, once money is taken, the Done card over
/// whatever the caller is standing on.
///
/// A centred 620 modal on a tablet; a full-height sheet on a phone. Resolves
/// with the [ChargeOutcome] — null when the teller closed it without
/// charging. The Done card is presented by default; pass
/// [presentDoneCard] false to handle the outcome yourself. Under a panel
/// host (the Sell screen's Fast mode) Charge is a page of the panel, and so
/// is Done ([showDonePage]): the same view model, drawn as a page.
///
/// ```dart
/// await showCharge(context, ChargeTarget.bill(ticket, tableLabel: 'T5'));
/// ```
Future<ChargeOutcome?> showCharge(
  BuildContext context,
  ChargeTarget target, {
  bool presentDoneCard = true,
  VoidCallback? onPrinterSettings,
  DoneCardCallback? onDone,
}) async {
  // Hold the session for the whole presentation, not just while the sheet is
  // mounted: a sheet put away while the charge is landing (a scrim tap that
  // slipped past the lock, a drag) must still hand its outcome to the Done
  // flow — the money is taken either way.
  final container = ProviderScope.containerOf(context, listen: false);
  final hold = container.listen(checkoutProvider, (_, _) {});
  ChargeOutcome? outcome;
  try {
    // A tablet's centred modal, unless the screen hosts its sheets in a
    // panel (the Sell screen's Fast mode): then Charge replaces the menu
    // beside the cart, as the sheet it is everywhere else.
    outcome =
        MadarLayout.of(context).isTablet &&
            MadarPanelHost.maybeOf(context) == null
        ? await _showChargeModal(context, target)
        : await showMadarSheet<ChargeOutcome>(
            context,
            size: SheetSize.large,
            builder: (_) => ChargeSheet(target: target),
          );
    outcome ??= await container
        .read(checkoutProvider.notifier)
        .settledOutcome();
  } finally {
    hold.close();
  }
  final landed = outcome;
  if (landed != null && presentDoneCard && context.mounted) {
    // Where Charge was a page of the panel, Done is one too; everywhere else
    // it is the card.
    final done = MadarPanelHost.maybeOf(context) == null
        ? showDoneCard(context, landed, onPrinterSettings: onPrinterSettings)
        : showDonePage(context, landed, onPrinterSettings: onPrinterSettings);
    unawaited(done.then((result) => onDone?.call(landed, result)));
  }
  return outcome;
}

/// Called with what the Done card decided, once it is gone.
typedef DoneCardCallback =
    void Function(ChargeOutcome outcome, DoneCardResult result);

/// The tablet presentation: a scrim and a centred card that hugs its
/// content up to [_modalHeightFraction] of the window.
Future<ChargeOutcome?> _showChargeModal(
  BuildContext context,
  ChargeTarget target,
) {
  final colors = context.madarColors;
  final dark = Theme.of(context).brightness == Brightness.dark;
  // The shared dialog presenter owns the dim (scrim.dart): claimed on push,
  // handed on the moment the modal starts to leave — so a sheet raised from
  // inside it never dims twice, and the Done card that follows it never
  // lands on an undimmed flash or on the modal's fading barrier.
  return showMadarDialogSurface<ChargeOutcome>(
    context,
    // A Builder, so the read of the keyboard inset is a widget dependency
    // and the card re-lays when the keyboard comes and goes — the route's
    // page builder alone runs once.
    pageBuilder: (context) => Builder(
      builder: (context) {
        final window = MediaQuery.sizeOf(context);
        // The keyboard the amount field raises takes the bottom of the window;
        // the card shrinks to what is left above it, and the Charge bar at
        // its foot stays in reach — on a 10.2" iPad in landscape the keys
        // would otherwise cover it.
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final maxHeight = math.min(
          (window.height - keyboard) * _modalHeightFraction,
          _modalMaxHeight,
        );
        return MadarKeyboardInset(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(_modalWidth, window.width - Space.xl * 2),
                  maxHeight: maxHeight,
                  minHeight: maxHeight,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(Radii.sheet),
                      boxShadow: MadarElevation.raised.shadows(
                        colors,
                        dark: dark,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.sheet),
                      child: ChargeSheet(target: target),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// THE tender drawer — one for a counter cart, a table's bill and an online
/// order. Cash is preselected; Exact is the loudest thing and charges
/// directly; the bar at the foot stays dimmed until a tender is picked or
/// typed. Discount, member and tip live here, quietly, and only where the
/// bridge call behind the caller can carry them.
///
/// Owns its [checkoutProvider] session (autoDispose): starts it on mount,
/// pops with the [ChargeOutcome] the moment the charge has landed and the
/// Taking the customer off a sale: no points earned, no reward applied.
/// Reversible only by scanning them again, which needs the card or the phone
/// back in hand — so it asks first.
Future<void> _confirmRemoveMember(
  BuildContext context,
  MadarBridge bridge,
  VoidCallback clear,
) async {
  final ok = await showMadarConfirm(
    context,
    title: bridge.tr(key: 'loyalty.remove_title'),
    body: bridge.tr(key: 'loyalty.remove_body'),
    confirmLabel: bridge.tr(key: 'loyalty.remove'),
    cancelLabel: bridge.tr(key: 'common.cancel'),
  );
  if (ok) clear();
}

/// auto-print has answered.
class ChargeSheet extends ConsumerStatefulWidget {
  const ChargeSheet({required this.target, super.key});

  final ChargeTarget target;

  @override
  ConsumerState<ChargeSheet> createState() => _ChargeSheetState();
}

class _ChargeSheetState extends ConsumerState<ChargeSheet> {
  bool _popped = false;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Bring the foot of the sheet into view — the change figure lives there,
  /// and a member's reward rows can push it under the bar.
  void _revealFoot() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (end <= 0) return;
      _scroll.animateTo(
        end,
        duration: MotionSpec.standardDuration,
        curve: MotionSpec.standardCurve,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    // Post-frame: notifier writes during initState land mid-build (crash).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(checkoutProvider.notifier).start(widget.target));
    });
  }

  void _resolve(ChargeOutcome outcome) {
    if (_popped || !mounted) return;
    // A landed outcome still counts as "charging" (nothing else may close the
    // sheet), so the PopScope would refuse this close too. Mark it resolved,
    // rebuild so the scope lets go, then close after that frame.
    setState(() => _popped = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MadarSheet.close(context, outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    // The drawer pops the moment the money is taken. The receipt prints in
    // the background; the outcome carries that job to the Done card, so a
    // slow printer never holds the sale open.
    ref.listen(checkoutProvider.select((s) => s.outcome), (_, outcome) {
      if (outcome != null) _resolve(outcome);
    });
    // Anything that changes what is owed or handed over moves the figure
    // the teller reads next to the foot of the sheet; follow it there.
    ref.listen(
      checkoutProvider.select(
        (s) => (s.tenderedMinor, s.tipOpen, s.splitMode, s.loyaltyMember?.id),
      ),
      (_, _) => _revealFoot(),
    );
    final colors = context.madarColors;
    final bridge = ref.bridge;
    // The drawer renders nearly every session field — the one legitimate
    // whole-state watch; the leaf widgets receive plain data below.
    final s = ref.watch(checkoutProvider);
    final notifier = ref.read(checkoutProvider.notifier);
    final layout = MadarLayout.of(context);
    final pad = layout.pick(phone: Space.lg, tablet: Space.xl);
    String tr(String key) => chargeTr(bridge, key);

    final block = s.block;
    // Every dimmed state says why — a grey bar with no words was the audit's
    // "Charge dim, no reason".
    final reason = switch (block) {
      ChargeBlock.noTill => bridge.tr(key: 'waiter.need_shift'),
      ChargeBlock.noMethods => tr('charge.no_methods'),
      ChargeBlock.needTender when s.splitMode => tr('charge.reason_split'),
      ChargeBlock.needTender when s.isCash => tr('charge.reason_cash'),
      ChargeBlock.needTender => tr('charge.reason_method'),
      _ => null,
    };
    // Money is moving: nothing may close the drawer until it has landed — not
    // the close tile, not system back, not the tablet's scrim.
    final paying = block == ChargeBlock.charging;

    // An online order takes no tender, but it still has a person: its quiet
    // rows are the customer row alone.
    final quiet = s.takesTender || bridge.can(cap: Cap.customersAttach)
        ? _QuietRows(
            state: s,
            tr: tr,
            bridge: bridge,
            pickedDiscount: notifier.pickedDiscount,
            onDiscount: () => unawaited(_pickDiscount(context, s)),
            onMember: () => unawaited(
              showMadarSheet<void>(
                context,
                size: SheetSize.hug,
                maxWidth: Responsive.sheetCompactMaxWidth,
                builder: (_) => const LoyaltyScanSheet(),
              ),
            ),
            onRemoveMember: () => unawaited(
              _confirmRemoveMember(context, bridge, notifier.clearLoyalty),
            ),
            onCustomer: () => unawaited(
              showMadarSheet<void>(
                context,
                size: SheetSize.hug,
                maxWidth: Responsive.sheetCompactMaxWidth,
                // An online order already names a phone: search starts there.
                builder: (_) => CustomerSheet(
                  initialQuery: switch (s.target) {
                    OnlineChargeTarget(:final order) => order.customerPhone,
                    _ => null,
                  },
                ),
              ),
            ),
            // The customer and the member are one person: taking them off a
            // sale with a member on it asks first, as the member's row does.
            onRemoveCustomer: s.loyaltyMember == null
                ? notifier.clearCustomer
                : () => unawaited(
                    _confirmRemoveMember(
                      context,
                      bridge,
                      notifier.clearLoyalty,
                    ),
                  ),
            onUseLoyalty: () => unawaited(notifier.useCustomerLoyalty()),
            onToggleReward: notifier.toggleReward,
            onOpenTip: notifier.openTip,
            onCloseTip: notifier.closeTip,
            onTip: notifier.setTip,
            onTipMethod: notifier.setTipMethod,
            onWaiveService: (waive) => notifier.setWaiveService(waive: waive),
          )
        : null;
    final wide = layout.isTablet;
    final tender = <Widget>[
      if (s.paymentMethods.length >= 2)
        _MethodsRow(
          state: s,
          tr: tr,
          onSelect: notifier.selectMethod,
          onToggleSplit: notifier.toggleSplit,
        ),
      if (s.splitMode)
        _SplitAllocator(
          state: s,
          remainingLabel: bridge.tr(key: 'order.split_remaining'),
          restLabel: tr('charge.rest_here'),
          onAmount: notifier.setSplitAmount,
          onRest: notifier.fillSplitRest,
        )
      else if (s.takesTender && s.isCash)
        _CashSection(
          state: s,
          tr: tr,
          bridge: bridge,
          layout: layout,
          showChange: !wide,
          onTendered: notifier.setTendered,
          onExact: () => unawaited(notifier.chargeExact()),
        ),
    ];
    final error = s.error == null
        ? null
        : NoticeBanner(
            text: s.error!.of(bridge),
            tone: ChipTone.danger,
            icon: 'exclamationmark.circle',
          );
    final bar = MadarMoneyBar(
      label: tr('charge.title'),
      amountMinor: s.chargeTotalMinor,
      currency: s.currency,
      enabled: block == ChargeBlock.none,
      loading: paying || block == ChargeBlock.loading,
      reason: reason,
      onTap: () => unawaited(_chargeGated(context, notifier)),
    );
    final oneMethod = s.paymentMethods.length == 1 && s.effectiveMethod != null
        // One method: no grid — the bar names it.
        ? Text(
            s.effectiveMethod!.name,
            textAlign: TextAlign.center,
            style: MadarType.bodySm.copyWith(color: colors.textMuted),
          )
        : null;
    final header = _ChargeHeader(
      target: widget.target,
      tr: tr,
      bridge: bridge,
      closing: !paying,
      onClose: () => Navigator.of(context).maybePop(),
    );

    final Widget body;
    if (wide) {
      // iPad / desktop: two columns. Start — how they pay: the methods, the
      // cash notes and the amount, then discount · member · tip. End — the
      // figures a teller reads aloud (total, received, change) over the one
      // Charge, which never scrolls away.
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(pad, pad, pad, Space.lg),
            child: header,
          ),
          const MadarHairline(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsetsDirectional.all(pad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Space.xl,
                      children: [...tender, ?quiet],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                SizedBox(
                  width: _readoutWidth,
                  child: ColoredBox(
                    color: colors.bg,
                    child: Padding(
                      padding: EdgeInsetsDirectional.all(pad),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: Space.lg,
                        children: [
                          // The figures scroll if they must (the card
                          // shrunk above a keyboard on a small iPad); the
                          // bar never does.
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: Space.lg,
                                children: [
                                  _Hero(
                                    state: s,
                                    tr: tr,
                                    bridge: bridge,
                                    flat: true,
                                  ),
                                  if (!s.splitMode && s.takesTender && s.isCash)
                                    _Readout(state: s, bridge: bridge),
                                ],
                              ),
                            ),
                          ),
                          ?error,
                          bar,
                          ?oneMethod,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      body = Padding(
        padding: EdgeInsetsDirectional.all(pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            header,
            Flexible(
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.lg,
                  children: [
                    _Hero(state: s, tr: tr, bridge: bridge),
                    ?quiet,
                    ...tender,
                    ?error,
                  ],
                ),
              ),
            ),
            bar,
            ?oneMethod,
          ],
        ),
      );
    }

    return PopScope<Object?>(canPop: !paying || _popped, child: body);
  }

  /// Charge — but a DISCOUNT ON THIS BILL is a discount, and it answers to the
  /// same three capabilities and the same per-person caps a counter sale does.
  /// Over the cap, a manager types their PIN here, before anything is queued;
  /// refused outright, the drawer stays open and the bar says why.
  ///
  /// The core asks again when it builds the settle, and the server asks a third
  /// time at replay — this is the prompt, not the lock.
  Future<void> _chargeGated(
    BuildContext context,
    CheckoutNotifier notifier,
  ) async {
    final decision = notifier.billDiscountDecision();
    if (decision != null && decision.outcome == 'deny') {
      notifier.showDiscountRefusal(decision.reason);
      return;
    }
    if (decision != null && decision.outcome == 'needs_approval') {
      final approval = await askManagerWith(
        context,
        reason: decision.reason,
        approve: notifier.approveBillDiscount,
      );
      if (approval == null || !mounted) return;
      notifier.setBillDiscountApproval(approval);
    }
    await notifier.charge();
  }

  /// The discount picker: No discount + every active discount as chips.
  /// The cart's applies live in the core; a bill's is a pick the server
  /// applies at settle.
  Future<void> _pickDiscount(BuildContext context, CheckoutState s) async {
    final notifier = ref.read(checkoutProvider.notifier);
    if (!s.isBill) {
      // The cart's: preset, amount or percent, each capped per person.
      final changed = await showCartDiscountSheet(
        context,
        ref,
        presets: s.discounts,
        currency: s.currency,
        tableId: s.cartTableId,
      );
      if (changed) await notifier.reloadCartDiscount();
      return;
    }
    final picked = await showMadarSheet<_DiscountPick>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => _DiscountSheet(
        discounts: s.discounts.where((d) => d.isActive).toList(),
        current: notifier.pickedDiscount?.id,
      ),
    );
    if (picked == null) return;
    if (s.isBill) {
      notifier.setBillDiscount(picked.discount);
    } else {
      await notifier.setDiscount(picked.discount?.id);
    }
  }
}

// ── Header ───────────────────────────────────────────────────────────────

/// "Charge · T5" with the bill's ref beside it; "Charge · Takeaway" for a
/// cart; "Charge · #D-118" with the customer under it for an online order.
class _ChargeHeader extends StatelessWidget {
  const _ChargeHeader({
    required this.target,
    required this.tr,
    required this.bridge,
    required this.onClose,
    this.closing = true,
  });

  final ChargeTarget target;
  final String Function(String) tr;
  final MadarBridge bridge;
  final VoidCallback onClose;

  /// False while a charge is in flight — the close tile is disabled.
  final bool closing;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final (String? ref, String? word, String? sub) = switch (target) {
      CartChargeTarget(:final label) => (
        null,
        label ?? tr('charge.takeaway'),
        null,
      ),
      BillChargeTarget(:final ticket, :final tableLabel) => (
        tableLabel ?? ticket.ticketRef,
        null,
        tableLabel != null && ticket.ticketRef != null
            ? '${tr('charge.bill')} ${ticket.ticketRef}'
            : ticket.customerName,
      ),
      OnlineChargeTarget(:final order) => (
        order.orderRef ??
            '#${order.id.substring(0, order.id.length.clamp(0, 6))}',
        null,
        [
          order.customerName,
          order.customerPhone,
          bridge.tr(key: 'delivery.${order.channel}'),
        ].where((p) => p.isNotEmpty).join(' · '),
      ),
    };
    final title = MadarType.h2.copyWith(color: colors.textPrimary);
    return Row(
      spacing: Space.md,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              MadarClippedText.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${tr('charge.title')} · '),
                    if (ref != null)
                      // The ref is a figure: mono, and an LTR island in both
                      // scripts.
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: Text(
                          ref,
                          textDirection: TextDirection.ltr,
                          style: MadarType.moneyLg.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    if (word != null) TextSpan(text: word),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: title,
              ),
              if (sub != null && sub.isNotEmpty)
                MadarClippedText(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
        ),
        MadarGlyphTile(
          glyph: MadarGlyph.close,
          semanticLabel: bridge.tr(key: 'common.cancel'),
          enabled: closing,
          onTap: onClose,
        ),
      ],
    );
  }
}

// ── Hero ─────────────────────────────────────────────────────────────────

/// TOTAL (or SUBTOTAL, on a bill) as the hero figure, with the one-line
/// breakdown under it worded per the tax policy.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.state,
    required this.tr,
    required this.bridge,
    this.flat = false,
  });

  final CheckoutState state;
  final String Function(String) tr;
  final MadarBridge bridge;

  /// On the tablet's figures column, which is already the sunk ground: a
  /// surface card instead of a second grey box.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = state;
    final sum = s.summary;
    final phone = context.isPhone;
    // An LTR island, so "Subtotal 175.00" reads the right way round in Arabic.
    String money(int minor) => MadarFormat.ltr(Money.format(minor));

    // The breakdown, as "Subtotal 175.00 · Service 21.00 · VAT incl. 24.07".
    // Only lines that exist: a zero rate draws nothing.
    final parts = <String>[];
    // A counter sale's staff drinks, stated before the subtotal they already
    // left: the pool's comp as a discount, and what those lines still pay.
    // The core's figures (local, synchronous); nothing here adds money up.
    if (s.target case CartChargeTarget(:final tableId)) {
      CartStaffSummary? staff;
      try {
        staff = bridge.cartStaffSummary(tableId: tableId);
      } on Object {
        staff = null;
      }
      if (staff != null) {
        parts.add(
          '${bridge.tr(key: 'staff_pool.badge')} −${money(staff.compMinor)}',
        );
        if (staff.chargedMinor > 0) {
          parts.add(
            '${bridge.tr(key: 'staff_pool.line_extras')} '
            '${money(staff.chargedMinor)}',
          );
        }
      }
    }
    if (!s.heroIsSubtotal) {
      parts.add(
        '${bridge.tr(key: 'order.subtotal')} ${money(sum.subtotalMinor)}',
      );
      if (sum.discountMinor > 0) {
        parts.add(
          '${bridge.tr(key: 'order.discount')} −${money(sum.discountMinor)}',
        );
      }
      if (sum.serviceChargeMinor > 0) {
        parts.add(
          '${bridge.tr(key: 'order.service_charge')} '
          '${money(sum.serviceChargeMinor)}',
        );
      }
      if (sum.deliveryFeeMinor > 0) {
        parts.add(
          '${bridge.tr(key: 'receipt.delivery_fee')} '
          '${money(sum.deliveryFeeMinor)}',
        );
      }
      if (sum.taxMinor > 0) {
        final rate = s.taxRate > 0 ? ' ${Money.ratePercent(s.taxRate)}%' : '';
        parts.add(
          s.taxInclusive
              ? '${tr('charge.vat_included')}$rate ${money(sum.taxMinor)}'
              : '${bridge.tr(key: 'order.tax')}$rate +${money(sum.taxMinor)}',
        );
      }
    } else if (s.serviceChargeRate > 0 || !s.taxInclusive) {
      // A bill's hero is its subtotal; when the server will add on top of
      // it, say so rather than let the figure pass for a total.
      parts.add(tr('charge.subtotal_hint'));
    }

    return Container(
      padding: const EdgeInsetsDirectional.all(_heroPad),
      decoration: BoxDecoration(
        color: flat ? colors.surface : colors.bg,
        borderRadius: BorderRadius.circular(_heroRadius),
        border: flat ? Border.all(color: colors.borderLight) : null,
      ),
      child: Column(
        spacing: Space.xs,
        children: [
          _Eyebrow(bridge.tr(key: s.heroLabelKey)),
          // The figures roll as they change — the natives' numericText.
          AnimatedMoneyText(
            s.dueMinor,
            currency: s.currency,
            style: MadarType.moneyDisplay.copyWith(
              fontSize: phone ? _heroPhone : _heroTablet,
              letterSpacing: -1,
              height: 1,
            ),
            color: colors.textPrimary,
          ),
          if (parts.isNotEmpty)
            Text(
              parts.join(' · '),
              textAlign: TextAlign.center,
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// A section header's word without its row: the same uppercase label, but
/// shrink-wrapped, so it can sit centred over the hero or at the end of the
/// change column where a row would have no width to fill.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    style: MadarType.label.copyWith(
      color: context.madarColors.textSecondary,
      letterSpacing: MadarType.tracking,
    ),
  );
}

// ── Quiet rows: discount · member · tip ───────────────────────────────────

class _QuietRows extends StatelessWidget {
  const _QuietRows({
    required this.state,
    required this.tr,
    required this.bridge,
    required this.pickedDiscount,
    required this.onDiscount,
    required this.onMember,
    required this.onRemoveMember,
    required this.onCustomer,
    required this.onRemoveCustomer,
    required this.onUseLoyalty,
    required this.onToggleReward,
    required this.onOpenTip,
    required this.onCloseTip,
    required this.onTip,
    required this.onTipMethod,
    required this.onWaiveService,
  });

  final CheckoutState state;
  final String Function(String) tr;
  final MadarBridge bridge;
  final DiscountView? pickedDiscount;
  final VoidCallback onDiscount;
  final VoidCallback onMember;
  final VoidCallback onRemoveMember;
  final VoidCallback onCustomer;
  final VoidCallback onRemoveCustomer;
  final VoidCallback onUseLoyalty;
  final ValueChanged<int> onToggleReward;
  final VoidCallback onOpenTip;
  final VoidCallback onCloseTip;
  final ValueChanged<int> onTip;
  final ValueChanged<String> onTipMethod;
  final ValueChanged<bool> onWaiveService;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = state;
    // Presets, or a discount this person may type by hand.
    final hasDiscounts =
        s.discounts.any((d) => d.isActive) ||
        (!s.isBill &&
            [
              Cap.ordersDiscountManualAmount,
              Cap.ordersDiscountManualPercent,
            ].any((c) => bridge.can(cap: c) || bridge.canAskManager(cap: c)));
    final member = s.loyaltyMember;
    final rows = <Widget>[];

    // Discount — only when the branch has any. Order-level: that is all
    // the server has. On a bill too it is priced at once by the core, so the
    // row states what it takes off, the same figure the settle books.
    if (hasDiscounts) {
      final d = pickedDiscount;
      final off = s.summary.discountMinor;
      final cart = s.isBill || s.cartDiscount == null
          ? null
          : cartDiscountLabel(
              bridge,
              s.cartDiscount!,
              s.discounts,
              discountLabel,
            );
      final value = cart != null
          ? off > 0
                ? '$cart · −${MadarFormat.ltr(Money.format(off))}'
                : cart
          : d == null
          ? bridge.tr(key: 'order.no_discount')
          : s.isBill && off > 0
          ? '${discountLabel(d)} · −${MadarFormat.ltr(Money.format(off))}'
          : discountLabel(d);
      rows.add(
        _QuietRow(
          label: bridge.tr(key: 'order.discount'),
          value: value,
          onTap: onDiscount,
        ),
      );
    }

    // Service charge — a table's bill only, and only for someone whose
    // effective permissions include `orders:waive_service` (the core reads
    // them; the role's name is never consulted). Shown while there is a
    // charge to remove, or once it has been removed so it can be put back.
    final serviceOnBill = s.summary.serviceChargeMinor > 0 || s.waiveService;
    if (s.isBill && s.canWaiveService && serviceOnBill) {
      rows.add(
        _QuietRow(
          label: s.waiveService
              ? bridge.tr(key: 'checkout.service_removed_hint')
              : bridge.tr(key: 'order.service_charge'),
          value: s.waiveService
              ? bridge.tr(key: 'checkout.keep_service')
              : bridge.tr(key: 'checkout.remove_service'),
          onTap: () => onWaiveService(!s.waiveService),
        ),
      );
    }

    // Customer — every target, for someone who may attach one. Works
    // offline: a bill or an online order gets them as an op queued behind
    // the charge.
    if (bridge.can(cap: Cap.customersAttach)) {
      final customer = s.customer;
      rows.add(
        _QuietRow(
          label: bridge.tr(key: 'customers.attach'),
          value: customer == null
              ? bridge.tr(key: 'customers.search_hint')
              : customer.isMember
              ? '${customer.name} · ${bridge.tr(key: 'customers.member')}'
              : customer.name,
          // Nobody yet: pick one. Somebody: their card.
          onTap: customer == null
              ? onCustomer
              : () => unawaited(showCustomerCard(context, customer)),
          trailing: customer == null
              ? null
              : MadarGlyphTile(
                  glyph: MadarGlyph.close,
                  semanticLabel: bridge.tr(key: 'customers.remove'),
                  onTap: onRemoveCustomer,
                ),
        ),
      );
    }

    // An online order is finalized with a method and nothing else.
    if (!s.takesTender) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    }

    // The customer picked is a member: their rewards are one tap away, with
    // no card to scan a second time.
    if (s.loyaltyOffered &&
        member == null &&
        s.customer?.loyaltyCustomerId != null) {
      rows.add(
        _LinkRow(
          label: bridge.tr(key: 'customers.use_loyalty'),
          onTap: onUseLoyalty,
        ),
      );
    }

    // Member — attach from here; the member card is the rows under it.
    // Only where a programme actually runs: in a shop with none, every scan
    // answers "no member", which reads as a broken till. The row names the
    // programme when the shop gave it a name.
    if (s.loyaltyOffered) {
      rows.add(
        _QuietRow(
          label: s.loyaltyProgramme?.programName.trim().isNotEmpty ?? false
              ? s.loyaltyProgramme!.programName
              : tr('charge.member'),
          value: member == null
              ? bridge.tr(key: 'loyalty.scan_card')
              : '${member.name} · ${member.balance} '
                    '${loyaltyUnit((k) => bridge.tr(key: k), member.mode)}',
          onTap: member == null ? onMember : null,
          trailing: member == null
              ? null
              : MadarGlyphTile(
                  glyph: MadarGlyph.close,
                  semanticLabel: bridge.tr(key: 'loyalty.remove'),
                  onTap: onRemoveMember,
                ),
        ),
      );
    }
    if (s.loyaltyOffered && member != null) {
      final board = s.rewardBoard;
      final claimable = [
        for (final l in board?.lines ?? const <RewardLineState>[])
          if (l.claimable || l.blockedReason != null) l,
      ];
      if (claimable.isEmpty) {
        rows.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
            child: Text(
              bridge.tr(key: 'loyalty.nothing_claimable'),
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
          ),
        );
      } else {
        for (final l in claimable) {
          rows.add(
            _RewardLine(
              name: s.rewardLines[l.line].name,
              costLabel: l.costLabel,
              covered: l.units,
              quantity: s.rewardLines[l.line].qty,
              freeWord: tr('charge.free'),
              // The core's reason a row cannot take another: the shop's cap,
              // the balance. Said under the row, never guessed.
              reason: l.canAdd || l.units > 0 ? null : l.blockedReason,
              onTap: l.claimable ? () => onToggleReward(l.line) : null,
            ),
          );
        }
        final adjusted = board?.adjustedReason;
        rows.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
            child: Text(
              // What is left AFTER what is ticked — the number the customer
              // will ask about — and why a tap did not all go through.
              '${board?.balanceAfter ?? member.balance} '
              '${loyaltyUnit((k) => bridge.tr(key: k), member.mode)} '
              '${bridge.tr(key: 'loyalty.left')}'
              '${adjusted == null ? '' : ' · $adjusted'}',
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
          ),
        );
      }
    }

    // Tip — a quiet link until asked for (there is no tips flag to hide it
    // behind), then an amount row and, with several methods, which one
    // pays it.
    if (!s.tipOpen) {
      rows.add(_LinkRow(label: tr('charge.add_tip'), onTap: onOpenTip));
    } else {
      rows.add(
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              Row(
                spacing: Space.md,
                children: [
                  Text(
                    bridge.tr(key: 'order.tip'),
                    style: MadarType.title.copyWith(color: colors.textPrimary),
                  ),
                  Expanded(
                    child: MadarAmountField(
                      amountMinor: s.tipMinor,
                      onAmountMinor: onTip,
                      currencyCode: s.currency,
                      autofocus: true,
                    ),
                  ),
                  MadarGlyphTile(
                    glyph: MadarGlyph.close,
                    semanticLabel: tr('charge.remove_tip'),
                    size: MadarButtonSize.regular,
                    onTap: onCloseTip,
                  ),
                ],
              ),
              if (s.paymentMethods.length > 1)
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final m in s.paymentMethods)
                      MadarChip(
                        label: m.name,
                        glyph: paymentGlyph(m.icon),
                        selected:
                            (s.tipMethodId ?? s.effectiveMethodId) == m.id,
                        onTap: () => onTipMethod(m.id),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1) const MadarHairline.row(),
        ],
      ],
    );
  }
}

/// A 52 row: label at the start, the current value muted, a chevron when it
/// goes somewhere (or a supplied trailing control).
class _QuietRow extends StatelessWidget {
  const _QuietRow({
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final row = SizedBox(
      height: _quietRow,
      child: Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: Text(
              label,
              style: MadarType.title.copyWith(color: colors.textPrimary),
            ),
          ),
          Flexible(
            child: MadarClippedText(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.body.copyWith(color: colors.textSecondary),
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            MadarGlyphIcon(
              MadarGlyph.chevronForward,
              size: IconSize.xl,
              color: colors.textMuted,
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    return TactileScale(onTap: onTap, child: row);
  }
}

/// A link-weight row: teal words and a chevron. "Add tip ›".
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: onTap,
      child: SizedBox(
        height: _linkRow,
        child: Row(
          spacing: Space.xs,
          children: [
            Text(
              label,
              style: MadarType.body.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.accent,
              ),
            ),
            MadarGlyphIcon(
              MadarGlyph.chevronForward,
              size: IconSize.md,
              color: colors.accent,
            ),
          ],
        ),
      ),
    );
  }
}

/// One line a reward could cover, and how many of its units are. Tapping
/// ticks one more unit; past the quantity it clears.
class _RewardLine extends StatelessWidget {
  const _RewardLine({
    required this.name,
    required this.costLabel,
    required this.covered,
    required this.quantity,
    required this.freeWord,
    required this.onTap,
    this.reason,
  });

  final String name;
  final String costLabel;
  final int covered;
  final int quantity;
  final String freeWord;
  final VoidCallback? onTap;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final on = covered > 0;
    return TactileScale(
      onTap: onTap,
      child: SizedBox(
        height: _rewardRow,
        child: Row(
          spacing: Space.md,
          children: [
            MadarGlyphIcon(
              on ? MadarGlyph.squareCheck : MadarGlyph.square,
              size: IconSize.xl,
              color: on ? colors.accent : colors.textMuted,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MadarClippedText(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.body.copyWith(
                      color: onTap == null
                          ? colors.textMuted
                          : colors.textPrimary,
                    ),
                  ),
                  if (reason case final why?)
                    MadarClippedText(
                      why,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.bodySm.copyWith(color: colors.textMuted),
                    ),
                ],
              ),
            ),
            if (on)
              // "2/3 free" reads correctly whether one unit is covered or all
              // of them; "free" alone would lie on a partly covered line.
              Text.rich(
                TextSpan(
                  children: [
                    if (quantity > 1)
                      TextSpan(
                        text: '$covered/$quantity ',
                        style: MadarType.numMd.copyWith(color: colors.success),
                      ),
                    TextSpan(text: freeWord),
                  ],
                ),
                textDirection: TextDirection.ltr,
                style: MadarType.bodySm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.success,
                ),
              ),
            Text(
              costLabel,
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Methods ──────────────────────────────────────────────────────────────

/// The branch's methods as self-sizing tiles in a [Wrap] — never a fixed
/// row of equal-width buttons. That was the old shape (one `Expanded` row
/// on a tablet, two per row on a phone), and it divided the row by COUNT: a
/// shop with five or six methods, or one Arabic name that reads wider than
/// its English counterpart, squeezed every tile under a legible width at
/// once. A [Wrap] hands each tile only the width its name needs and drops
/// the rest to a new line instead of shrinking all of them; a horizontal
/// scroll was the other option and was rejected — a method that only
/// appears after a swipe a teller doesn't know to try is worse than one
/// that's merely a row down (the sheet already scrolls vertically). The
/// Split chip rides in the same [Wrap], at the end, only where the bridge
/// carries splits.
class _MethodsRow extends StatelessWidget {
  const _MethodsRow({
    required this.state,
    required this.tr,
    required this.onSelect,
    required this.onToggleSplit,
  });

  final CheckoutState state;
  final String Function(String) tr;
  final ValueChanged<String> onSelect;
  final VoidCallback onToggleSplit;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final selected = s.splitMode ? null : s.effectiveMethodId;
    return Wrap(
      spacing: Space.sm + 2,
      runSpacing: Space.sm + 2,
      children: [
        // In a split the allocator below names every method with its own
        // amount; the tiles above it were the same list twice.
        if (!s.splitMode)
          for (final m in s.paymentMethods)
            _MethodTile(
              method: m,
              tr: tr,
              selected: m.id == selected,
              onTap: () => onSelect(m.id),
            ),
        if (s.canSplit)
          SizedBox(
            width: double.infinity,
            child: MadarSegmented<bool>(
              items: [
                MadarSegmentItem(false, tr('toggle.single_payment')),
                MadarSegmentItem(
                  true,
                  tr('order.split_payment'),
                  glyph: MadarGlyph.split,
                ),
              ],
              value: s.splitMode,
              onChanged: (_) => onToggleSplit(),
            ),
          ),
      ],
    );
  }
}

/// One payment method. The org's own colour and icon are SUPPORT for its
/// NAME, never a replacement for it — a custom method with a generic icon
/// used to be identifiable only by that icon, indistinguishable from any
/// other custom method that happened to share it. The muted line under the
/// name flags what the method actually IS — cash, a card, a wallet, or the
/// shop's own — so a branded name like "InstaPay" still reads as a wallet
/// at a glance, not only by its colour (which a washed-out brand colour, or
/// a colourblind teller, can't be relied on alone to carry).
class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.tr,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethodView method;
  final String Function(String) tr;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final brand = hexColor(method.color);
    final glyph = paymentGlyph(method.icon);
    final fg = selected ? colors.textOnAccent : colors.textPrimary;
    final kind = _kindLabel(method, tr);
    // Skip the caption when the org just named the method after its own
    // kind — "Cash" over a caption reading "Cash" repeats itself. It earns
    // its place only when it tells the teller something the name doesn't.
    final showKind = kind.toLowerCase() != method.name.trim().toLowerCase();

    return Semantics(
      button: true,
      selected: selected,
      child: TactileScale(
        onTap: onTap,
        child: Container(
          height: Metrics.buttonHeight,
          constraints: const BoxConstraints(
            minWidth: _methodTileMinWidth,
            maxWidth: _methodTileMaxWidth,
          ),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.md),
          decoration: BoxDecoration(
            color: selected ? brand : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (selected ? colors.textOnAccent : brand).withValues(
                    alpha: Opacities.subtle,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Space.xs),
                  child: MadarGlyphIcon(
                    glyph,
                    size: IconSize.md,
                    color: selected ? colors.textOnAccent : brand,
                  ),
                ),
              ),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MadarClippedText(
                      method.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.buttonSm.copyWith(color: fg),
                    ),
                    if (showKind)
                      MadarClippedText(
                        kind,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.labelSm.copyWith(
                          color: selected
                              ? colors.textOnAccent.withValues(alpha: 0.8)
                              : colors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                MadarGlyphIcon(
                  MadarGlyph.check,
                  size: IconSize.md,
                  color: colors.textOnAccent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cash vs card vs wallet vs the shop's own — the four ways a teller reads
/// a method at a glance. `isCash` is authoritative for cash (it also gates
/// the cash-tender section below, so the caption must never disagree with
/// it); everything else follows the same icon family [paymentGlyph]
/// resolves, so the caption never contradicts the glyph beside it. A token
/// [paymentGlyph] doesn't recognise — an org's own, invented for a method
/// it defined itself — falls to "the shop's own" rather than guessing Cash
/// or Card.
String _kindLabel(PaymentMethodView m, String Function(String) tr) {
  if (m.isCash) return tr('charge.kind_cash');
  return switch (m.icon.toLowerCase()) {
    'credit_card' ||
    'card' ||
    'creditcard' ||
    'visa' ||
    'mastercard' ||
    'debit' => tr('charge.kind_card'),
    'wallet' ||
    'ewallet' ||
    'e_wallet' ||
    'qr_code' ||
    'qr' ||
    'smartphone' ||
    'phone' ||
    'mobile' ||
    'vodafone' ||
    'instapay' => tr('charge.kind_wallet'),
    _ => tr('charge.kind_custom'),
  };
}

/// Map a backend payment-icon token to a glyph — the natives' payGlyph.
/// Unknown tokens (an org's own custom method) fall to [MadarGlyph.tag], not
/// [MadarGlyph.banknote] — the old default made every custom method LOOK
/// like cash, which is the exact confusion this screen exists to fix.
MadarGlyph paymentGlyph(String icon) => switch (icon.toLowerCase()) {
  'money' || 'cash' || 'banknote' => MadarGlyph.banknote,
  'credit_card' ||
  'card' ||
  'creditcard' ||
  'visa' ||
  'mastercard' ||
  'debit' => MadarGlyph.card,
  'wallet' || 'ewallet' || 'e_wallet' => MadarGlyph.wallet,
  'qr_code' || 'qr' => MadarGlyph.scan,
  'smartphone' ||
  'phone' ||
  'mobile' ||
  'vodafone' ||
  'instapay' => MadarGlyph.phone,
  'delivery' => MadarGlyph.bike,
  'gift_card' => MadarGlyph.star,
  'link' => MadarGlyph.globe,
  _ => MadarGlyph.tag,
};

// ── Split ────────────────────────────────────────────────────────────────

/// Per-method amount entry + a live remaining indicator (must reach 0).
class _SplitAllocator extends StatelessWidget {
  const _SplitAllocator({
    required this.state,
    required this.remainingLabel,
    required this.restLabel,
    required this.onAmount,
    required this.onRest,
  });

  final CheckoutState state;
  final String remainingLabel;

  /// "Rest here" — the compact action that puts what is left on one method.
  final String restLabel;
  final void Function(String id, int minor) onAmount;
  final ValueChanged<String> onRest;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = state;
    final settled = s.splitRemaining == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        for (final m in s.paymentMethods)
          Row(
            spacing: Space.md,
            children: [
              SizedBox(
                width: 96,
                child: MadarClippedText(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
              ),
              Expanded(
                child: MadarAmountField(
                  amountMinor: s.splitAmounts[m.id] ?? 0,
                  onAmountMinor: (minor) => onAmount(m.id, minor),
                  currencyCode: s.currency,
                ),
              ),
              MadarButton(
                label: restLabel,
                variant: MadarButtonVariant.secondary,
                size: MadarButtonSize.compact,
                enabled: s.splitRemaining > 0,
                onTap: () => onRest(m.id),
              ),
            ],
          ),
        Container(
          height: Metrics.chipHeight,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
          decoration: BoxDecoration(
            color: settled ? colors.successBg : colors.warningBg,
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  remainingLabel,
                  style: MadarType.label.copyWith(
                    color: settled ? colors.success : colors.warning,
                  ),
                ),
              ),
              AnimatedMoneyText(
                s.splitRemaining,
                currency: s.currency,
                style: MadarType.money,
                color: settled ? colors.success : colors.warning,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Cash ─────────────────────────────────────────────────────────────────

/// The tablet's big figures under the total: what the customer handed over
/// and what goes back (or what is still short), read across the counter.
class _Readout extends StatelessWidget {
  const _Readout({required this.state, required this.bridge});

  final CheckoutState state;
  final MadarBridge bridge;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = state;
    final typed = s.tenderedMinor > 0;
    final short = typed && s.shortMinor > 0;
    Widget line(String label, Widget figure) => Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: _Eyebrow(label)),
        figure,
      ],
    );
    return MadarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          line(
            bridge.tr(key: 'order.cash_received'),
            typed
                ? AnimatedMoneyText(
                    s.tenderedMinor,
                    currency: s.currency,
                    style: MadarType.moneyMd,
                    color: colors.textPrimary,
                  )
                : Text(
                    '—',
                    style: MadarType.moneyMd.copyWith(color: colors.textMuted),
                  ),
          ),
          const MadarHairline(light: true),
          line(
            bridge.tr(key: short ? 'order.short_by' : 'order.change'),
            typed
                ? AnimatedMoneyText(
                    short ? s.shortMinor : s.changeMinor,
                    currency: s.currency,
                    style: MadarType.moneyDisplay,
                    color: short ? colors.danger : colors.success,
                  )
                : Text(
                    '—',
                    style: MadarType.moneyDisplay.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// CASH RECEIVED: Exact (the lit primary — it charges directly), the two
/// round notes at or above the due, the typed amount, and the change.
class _CashSection extends StatelessWidget {
  const _CashSection({
    required this.state,
    required this.tr,
    required this.bridge,
    required this.layout,
    required this.onTendered,
    required this.onExact,
    this.showChange = true,
  });

  final CheckoutState state;
  final String Function(String) tr;
  final MadarBridge bridge;
  final MadarLayout layout;

  /// Off on the tablet, whose figures column carries the change in large.
  final bool showChange;
  final ValueChanged<int> onTendered;
  final VoidCallback onExact;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = state;
    final due = s.dueCashMinor;
    // The round notes that cover the due — the one equal to it included —
    // scaled by the currency's own minor digits. The core picks them.
    final presets = bridge.cashQuickTenders(
      dueMinor: due,
      currency: s.currency,
    );
    final typed = s.tenderedMinor > 0;
    final short = s.shortMinor > 0;

    // One selected style for the whole row: the amount in the field is the
    // filled tile, every other tile is secondary — Exact included, until the
    // amount in hand IS the due.
    final exact = _PresetTile(
      word: bridge.tr(key: 'order.exact'),
      label: MadarFormat.ltr(Money.format(due)),
      selected: typed && s.tenderedMinor == due,
      enabled: s.canChargeExact,
      loading: s.isPlacingOrder,
      onTap: onExact,
    );
    final tiles = [
      for (final p in presets)
        Expanded(
          flex: _presetFlex,
          child: _PresetTile(
            label: p.label,
            selected: typed && s.tenderedMinor == p.amountMinor,
            onTap: () => onTendered(p.amountMinor),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm + 2,
      children: [
        MadarSectionHeader(text: bridge.tr(key: 'order.cash_received')),
        // Exact beside the notes on a tablet; on a phone the bar's word
        // would be squeezed out by its own figure, so Exact takes the row
        // and the notes sit under it.
        if (layout.isTablet)
          Row(
            spacing: Space.sm + 2,
            children: [
              Expanded(flex: _exactFlex, child: exact),
              ...tiles,
            ],
          )
        else ...[
          exact,
          if (tiles.isNotEmpty) Row(spacing: Space.sm + 2, children: tiles),
        ],
        Row(
          spacing: Space.lg,
          children: [
            Expanded(
              child: MadarAmountField(
                amountMinor: s.tenderedMinor,
                onAmountMinor: onTendered,
                currencyCode: s.currency,
              ),
            ),
            if (s.showsChange && showChange)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  spacing: 2,
                  children: [
                    _Eyebrow(
                      bridge.tr(
                        key: short && typed ? 'order.short_by' : 'order.change',
                      ),
                    ),
                    if (!typed)
                      Text(
                        '—',
                        style: MadarType.moneyLg.copyWith(
                          color: colors.textMuted,
                        ),
                      )
                    else
                      AnimatedMoneyText(
                        short ? s.shortMinor : s.changeMinor,
                        style: MadarType.moneyLg,
                        color: short ? colors.danger : colors.textPrimary,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A quick tender: 64 high on the sunk grey, the figure centred in mono,
/// with Exact's word at the start. Filled ink once it is the amount in the
/// field; every other tile stays secondary, so one style says "selected".
class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.word,
    this.enabled = true,
    this.loading = false,
  });

  /// The note as the core words it: "200", never "200.00".
  final String label;
  final String? word;
  final bool selected;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final ink = selected ? Colors.white : colors.textPrimary;
    final figure = MadarClippedText(
      label,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: MadarType.numLg.copyWith(fontSize: 18, color: ink),
    );
    final w = word;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: TactileScale(
          onTap: enabled && !loading ? onTap : null,
          child: Container(
            height: Metrics.moneyBarHeight,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.chromeAlt : colors.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: loading
                ? MadarSpinner(color: ink)
                : w == null
                ? figure
                : Row(
                    spacing: Space.sm,
                    children: [
                      Text(w, style: MadarType.title.copyWith(color: ink)),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: figure,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Discount sheet ───────────────────────────────────────────────────────

/// The cart's discount, picked from the cart itself — before Charge.
///
/// The same sheet Charge opens, over the same core calls: the core prices the
/// discount live, so the cart's figures move the moment it is applied. Returns
/// whether anything was picked (the caller re-reads its cart).
Future<bool> showCartDiscountPicker(
  BuildContext context,
  WidgetRef ref, {
  String? tableId,
}) async {
  final bridge = ref.read(bridgeProvider);
  final List<DiscountView> discounts;
  try {
    discounts = await bridge.listDiscounts();
  } on Object {
    return false;
  }
  if (!context.mounted) return false;
  return await showCartDiscountSheet(
    context,
    ref,
    presets: discounts,
    currency: bridge.currentSession()?.currencyCode ?? '',
    tableId: tableId,
  );
}

/// What the discount sheet pops with. A null [discount] is "No discount";
/// the sheet dismissing pops nothing.
@immutable
class _DiscountPick {
  const _DiscountPick(this.discount);

  final DiscountView? discount;
}

class _DiscountSheet extends ConsumerWidget {
  const _DiscountSheet({required this.discounts, required this.current});

  final List<DiscountView> discounts;
  final String? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final colors = context.madarColors;
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Text(
            bridge.tr(key: 'order.discount'),
            style: MadarType.h3.copyWith(color: colors.textPrimary),
          ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              MadarChip(
                label: bridge.tr(key: 'order.no_discount'),
                selected: current == null,
                onTap: () =>
                    MadarSheet.close(context, const _DiscountPick(null)),
              ),
              for (final d in discounts)
                MadarChip(
                  label: discountLabel(d),
                  selected: current == d.id,
                  onTap: () => MadarSheet.close(context, _DiscountPick(d)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `value` is a FRACTION for a percentage discount (0.125 = 12.5%), the same
/// convention as the tax rate — so the chip multiplies it back up, and drops a
/// trailing `.0` so the common case still reads "10%" and not "10.0%".
String discountLabel(DiscountView d) {
  if (d.dtype != 'percentage') return d.name;
  // Rounded to a tenth first — see `_pct`.
  final pct = (d.value * 1000).round() / 10;
  final text = pct == pct.roundToDouble()
      ? pct.toStringAsFixed(0)
      : pct.toStringAsFixed(1);
  return '${d.name} $text%';
}
