import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/charge_strings.dart';
import 'package:feature_checkout/src/charge_target.dart';
import 'package:feature_checkout/src/checkout_provider.dart';
import 'package:feature_checkout/src/done_card.dart';
import 'package:feature_checkout/src/loyalty_scan_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The modal's width on a tablet — the canvas draws it at 620.
const double _modalWidth = 620;

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

/// Round-number cash presets in minor units; the two smallest at or above
/// the due are offered beside Exact.
const List<int> _cashPresets = [5000, 10000, 20000, 50000, 100000];
const int _cashPresetCount = 2;

/// Below this width the method buttons stack two to a row.
const double _methodsSingleRowMin = 480;

/// Present Charge for [target] and, once money is taken, the Done card over
/// whatever the caller is standing on.
///
/// A centred 620 modal on a tablet; a full-height sheet on a phone. Resolves
/// with the [ChargeOutcome] — null when the teller closed it without
/// charging. The Done card is presented by default; pass
/// [presentDoneCard] false to handle the outcome yourself.
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
  final outcome = MadarLayout.of(context).isTablet
      ? await _showChargeModal(context, target)
      : await showMadarSheet<ChargeOutcome>(
          context,
          size: SheetSize.large,
          builder: (_) => ChargeSheet(target: target),
        );
  if (outcome != null && presentDoneCard && context.mounted) {
    unawaited(
      showDoneCard(
        context,
        outcome,
        onPrinterSettings: onPrinterSettings,
      ).then((result) => onDone?.call(outcome, result)),
    );
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
  return showGeneralDialog<ChargeOutcome>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: Opacities.scrim),
    transitionDuration: MotionSpec.standardDuration,
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: MotionSpec.springOut,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, _, _) {
      final maxHeight =
          MediaQuery.sizeOf(context).height * _modalHeightFraction;
      return SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _modalWidth,
              maxHeight: maxHeight,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(Radii.sheet),
                  boxShadow: MadarElevation.raised.shadows(colors, dark: dark),
                ),
                child: ChargeSheet(target: target),
              ),
            ),
          ),
        ),
      );
    },
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

  void _resolve(ChargeOutcome outcome, PrintState printState) {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.of(context).pop(outcome.withPrintState(printState));
  }

  @override
  Widget build(BuildContext context) {
    // The drawer pops once the money is taken AND the auto-print has said
    // what happened — the Done card carries that answer and has no session
    // left to ask.
    ref.listen(checkoutProvider.select((s) => (s.outcome, s.isPlacingOrder)), (
      _,
      next,
    ) {
      final (outcome, busy) = next;
      if (outcome != null && !busy) {
        _resolve(outcome, ref.read(checkoutProvider).printState);
      }
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
    final bridge = ref.watch(bridgeProvider);
    // The drawer renders nearly every session field — the one legitimate
    // whole-state watch; the leaf widgets receive plain data below.
    final s = ref.watch(checkoutProvider);
    final notifier = ref.read(checkoutProvider.notifier);
    final layout = MadarLayout.of(context);
    final pad = layout.pick(phone: Space.lg, tablet: Space.xl);
    String tr(String key) => chargeTr(bridge, key);

    final block = s.block;
    final reason = switch (block) {
      ChargeBlock.noShift => bridge.tr(key: 'waiter.need_shift'),
      _ => null,
    };

    return Padding(
      padding: EdgeInsetsDirectional.all(pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          _ChargeHeader(
            target: widget.target,
            tr: tr,
            bridge: bridge,
            onClose: () => Navigator.of(context).maybePop(),
          ),
          Flexible(
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.lg,
                children: [
                  _Hero(state: s, tr: tr, bridge: bridge),
                  if (s.takesTender)
                    _QuietRows(
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
                      onRemoveMember: notifier.clearLoyalty,
                      onToggleReward: notifier.toggleReward,
                      onOpenTip: notifier.openTip,
                      onCloseTip: notifier.closeTip,
                      onTip: notifier.setTip,
                      onTipMethod: notifier.setTipMethod,
                    ),
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
                      onAmount: notifier.setSplitAmount,
                    )
                  else if (s.takesTender && s.isCash)
                    _CashSection(
                      state: s,
                      tr: tr,
                      bridge: bridge,
                      layout: layout,
                      onTendered: notifier.setTendered,
                      onExact: () => unawaited(notifier.chargeExact()),
                    ),
                  if (s.error case final error?)
                    NoticeBanner(
                      text: error,
                      tone: ChipTone.danger,
                      icon: 'exclamationmark.circle',
                    ),
                ],
              ),
            ),
          ),
          MadarMoneyBar(
            label: tr('charge.title'),
            amountMinor: s.dueMinor + (s.splitMode ? 0 : s.tipMinor),
            currency: s.currency,
            enabled: block == ChargeBlock.none,
            loading: block == ChargeBlock.charging,
            reason: reason,
            onTap: () => unawaited(notifier.charge()),
          ),
          if (s.paymentMethods.length == 1 && s.effectiveMethod != null)
            // One method: no grid — the bar names it.
            Text(
              s.effectiveMethod!.name,
              textAlign: TextAlign.center,
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
        ],
      ),
    );
  }

  /// The discount picker: No discount + every active discount as chips.
  /// The cart's applies live in the core; a bill's is a pick the server
  /// applies at settle.
  Future<void> _pickDiscount(BuildContext context, CheckoutState s) async {
    final notifier = ref.read(checkoutProvider.notifier);
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
  });

  final ChargeTarget target;
  final String Function(String) tr;
  final MadarBridge bridge;
  final VoidCallback onClose;

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
              Text.rich(
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
                Text(
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
  const _Hero({required this.state, required this.tr, required this.bridge});

  final CheckoutState state;
  final String Function(String) tr;
  final MadarBridge bridge;

  String _pct(double rate) {
    // Rounded to a tenth first: 0.14 × 100 is 14.000000000000002 in a
    // double, and "14.0%" on a receipt looks like a rate nobody set.
    final pct = (rate * 1000).round() / 10;
    return pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = state;
    final sum = s.summary;
    final phone = context.isPhone;
    String money(int minor) => Money.format(minor);

    // The breakdown, as "Subtotal 175.00 · Service 21.00 · VAT incl. 24.07".
    // Only lines that exist: a zero rate draws nothing.
    final parts = <String>[];
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
        final rate = s.taxRate > 0 ? ' ${_pct(s.taxRate)}%' : '';
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
        color: colors.bg,
        borderRadius: BorderRadius.circular(_heroRadius),
      ),
      child: Column(
        spacing: Space.xs,
        children: [
          _Eyebrow(
            bridge.tr(key: s.heroIsSubtotal ? 'order.subtotal' : 'order.total'),
          ),
          MoneyText(
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
    required this.onToggleReward,
    required this.onOpenTip,
    required this.onCloseTip,
    required this.onTip,
    required this.onTipMethod,
  });

  final CheckoutState state;
  final String Function(String) tr;
  final MadarBridge bridge;
  final DiscountView? pickedDiscount;
  final VoidCallback onDiscount;
  final VoidCallback onMember;
  final VoidCallback onRemoveMember;
  final ValueChanged<int> onToggleReward;
  final VoidCallback onOpenTip;
  final VoidCallback onCloseTip;
  final ValueChanged<int> onTip;
  final ValueChanged<String> onTipMethod;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = state;
    final hasDiscounts = s.discounts.any((d) => d.isActive);
    final member = s.loyaltyMember;
    final rows = <Widget>[];

    // Discount — only when the branch has any. Order-level: that is all
    // the server has. On a bill it is applied at settle, with no preview.
    if (hasDiscounts) {
      final d = pickedDiscount;
      final value = d == null
          ? bridge.tr(key: 'order.no_discount')
          : s.isBill
          ? '${discountLabel(d)} · ${tr('charge.applied_at_charge')}'
          : discountLabel(d);
      rows.add(
        _QuietRow(
          label: bridge.tr(key: 'order.discount'),
          value: value,
          onTap: onDiscount,
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
              : '${member.name} · ${member.balance} ${member.balanceLabel}',
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
      final claimable = s.claimableLines;
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
        for (final i in claimable) {
          rows.add(
            _RewardLine(
              name: s.redeemableLines[i].name,
              costLabel: s.rewardForLine(i)!.costLabel,
              covered: s.redemptions[i] ?? 0,
              quantity: s.redeemableLines[i].qty,
              freeWord: tr('charge.free'),
              onTap: () => onToggleReward(i),
            ),
          );
        }
        rows.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
            child: Text(
              // What is left AFTER what is ticked — the number the customer
              // will ask about.
              '${s.balanceAfterRedemptions} ${member.balanceLabel} '
              '${bridge.tr(key: 'loyalty.left')}',
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
            child: Text(
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
  });

  final String name;
  final String costLabel;
  final int covered;
  final int quantity;
  final String freeWord;
  final VoidCallback onTap;

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
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.body.copyWith(color: colors.textPrimary),
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

/// The branch's methods, 56 high, in one row on a tablet and two to a row
/// on a phone; the chosen one fills with ink and carries a check. The
/// Split chip rides at the end, only where the bridge carries splits.
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
    final colors = context.madarColors;
    final s = state;
    final selected = s.splitMode ? null : s.effectiveMethodId;
    final buttons = [
      for (final m in s.paymentMethods)
        MadarButton(
          label: m.name,
          glyph: paymentGlyph(m.icon),
          variant: m.id == selected
              ? MadarButtonVariant.ink
              : MadarButtonVariant.secondary,
          trailing: m.id == selected
              ? const MadarGlyphIcon(MadarGlyph.check, color: Colors.white)
              : null,
          onTap: () => onSelect(m.id),
        ),
    ];
    final split = s.canSplit
        ? MadarChip(
            label: tr('order.split_payment'),
            glyph: MadarGlyph.split,
            selected: s.splitMode,
            onTap: onToggleSplit,
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _methodsSingleRowMin) {
          return Row(
            spacing: Space.sm + 2,
            children: [
              for (final b in buttons) Expanded(child: b),
              ?split,
            ],
          );
        }
        // Phone: two to a row, the split chip on its own line.
        final rows = <Widget>[];
        for (var i = 0; i < buttons.length; i += 2) {
          rows.add(
            Row(
              spacing: Space.sm + 2,
              children: [
                Expanded(child: buttons[i]),
                if (i + 1 < buttons.length)
                  Expanded(child: buttons[i + 1])
                else
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm + 2,
          children: [
            ...rows,
            if (split != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: DefaultTextStyle(
                  style: TextStyle(color: colors.textSecondary),
                  child: split,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Map a backend payment-icon token to a glyph — the natives' payGlyph.
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
  _ => MadarGlyph.banknote,
};

// ── Split ────────────────────────────────────────────────────────────────

/// Per-method amount entry + a live remaining indicator (must reach 0).
class _SplitAllocator extends StatelessWidget {
  const _SplitAllocator({
    required this.state,
    required this.remainingLabel,
    required this.onAmount,
  });

  final CheckoutState state;
  final String remainingLabel;
  final void Function(String id, int minor) onAmount;

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
                child: Text(
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
              MoneyText(
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
  });

  final CheckoutState state;
  final String Function(String) tr;
  final MadarBridge bridge;
  final MadarLayout layout;
  final ValueChanged<int> onTendered;
  final VoidCallback onExact;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = state;
    final due = s.dueCashMinor;
    final presets = _cashPresets
        .where((p) => p > due)
        .take(_cashPresetCount)
        .toList(growable: false);
    final typed = s.tenderedMinor > 0;
    final short = s.shortMinor > 0;

    final exact = MadarMoneyBar(
      label: bridge.tr(key: 'order.exact'),
      amountMinor: due,
      enabled: s.canChargeExact,
      loading: s.isPlacingOrder,
      onTap: onExact,
    );
    final tiles = [
      for (final p in presets)
        Expanded(
          flex: _presetFlex,
          child: _PresetTile(
            amountMinor: p,
            selected: s.tenderedMinor == p,
            onTap: () => onTendered(p),
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
            if (s.showsChange)
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
                      MoneyText(
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

/// A round-note preset: 64 high on the sunk grey, the figure centred in
/// mono. Ink once it is the amount in the field — never teal, so Exact
/// stays the one lit primary in the row.
class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.amountMinor,
    required this.selected,
    required this.onTap,
  });

  final int amountMinor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: onTap,
      child: Container(
        height: Metrics.moneyBarHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.chromeAlt : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Text(
          // A whole note: "200", never "200.00".
          '${amountMinor ~/ 100}',
          textDirection: TextDirection.ltr,
          style: MadarType.numLg.copyWith(
            fontSize: 18,
            color: selected ? Colors.white : colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ── Discount sheet ───────────────────────────────────────────────────────

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
    final bridge = ref.watch(bridgeProvider);
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
                    Navigator.of(context).pop(const _DiscountPick(null)),
              ),
              for (final d in discounts)
                MadarChip(
                  label: discountLabel(d),
                  selected: current == d.id,
                  onTap: () => Navigator.of(context).pop(_DiscountPick(d)),
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
