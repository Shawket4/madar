import 'dart:async';
import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/checkout_provider.dart';
import 'package:feature_checkout/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (TenderScreen.kt) that fall between the 4-pt Space steps —
// kept verbatim so the Flutter chrome measures identically.

/// Sticky-header title size (natives: 19.sp Black).
const double _headerTitleSize = 19;

/// Sticky-header live total size (natives: 20.sp Black).
const double _headerTotalSize = 20;

/// Summary sub-row text size (natives: 13.sp).
const double _rowSize = 13;

/// Grand-total block amount size (natives: 20.sp Black).
const double _grandTotalSize = 20;

/// Amount-due hero amount size (natives: 18.sp Black).
const double _dueAmountSize = 18;

/// Split-toggle pill insets (natives: 8×4.dp) and label size (11.sp).
const EdgeInsetsDirectional _splitTogglePad = EdgeInsetsDirectional.symmetric(
  horizontal: 8,
  vertical: 4,
);
const double _pillLabelSize = 11;

/// Split-allocator method dot (natives: 9.dp) and name cap (96.dp).
const double _splitDot = 9;
const double _splitNameMax = 96;

/// Tone-banner vertical inset (natives: 10.dp).
const double _bannerVPad = 10;

/// Change-banner amount size (natives: 15.sp Black).
const double _changeAmountSize = 15;

/// Pay chip insets (natives: 12×13.dp).
const EdgeInsetsDirectional _payChipPad = EdgeInsetsDirectional.symmetric(
  horizontal: 12,
  vertical: 13,
);

/// Discount chip insets (natives: 14×10.dp) and icon/label gap (5.dp).
const EdgeInsetsDirectional _discountChipPad = EdgeInsetsDirectional.symmetric(
  horizontal: 14,
  vertical: 10,
);
const double _chipGap = 5;

/// Quick-cash pill insets (natives: 14×7.dp).
const EdgeInsetsDirectional _quickCashPad = EdgeInsetsDirectional.symmetric(
  horizontal: 14,
  vertical: 7,
);

/// Tip-method pill insets (natives: 11×6.dp).
const EdgeInsetsDirectional _tipPillPad = EdgeInsetsDirectional.symmetric(
  horizontal: 11,
  vertical: 6,
);

/// Small active-check glyph inside chips (natives: 10.dp).
const double _chipCheck = 10;

/// Tip-card heart glyph (natives: 13.dp).
const double _tipHeart = 13;

/// Round-number cash presets in minor units (natives: 50/100/200/500 major).
const List<int> _cashPresets = [5000, 10000, 20000, 50000];

/// How many presets show at or above the amount due (natives: take(3)).
const int _cashPresetCount = 3;

/// The ONE real checkout drawer — payment method (or split allocator), cash
/// with live change, tip, optional discount + customer fields, then a
/// terminal button. Both the main cashier checkout (via TenderSheet) and the
/// ticket-settle / delivery-finalize flows drive THIS component. All shared
/// state (summary, methods, tender picks, errors) lives in [checkoutProvider];
/// the presenting sheet starts the session first (`startCart()` /
/// `startSettle(summary)` in its `initState`). Constructor params are pure
/// CONFIG: chrome strings, feature flags, the terminal callback. Money +
/// order assembly stay in the core / callback; this view only collects the
/// tender and reports it back via [CheckoutResult]. Port of TenderScreen.kt's
/// CheckoutDrawer.
class CheckoutDrawer extends ConsumerStatefulWidget {
  const CheckoutDrawer({
    required this.title,
    required this.terminalLabel,
    required this.terminalIcon,
    required this.onClose,
    required this.onTerminal,
    this.placing = false,
    this.showDiscountPicker = false,
    this.showCustomerFields = false,
    this.headerContent,
    super.key,
  });

  final String title;
  final String terminalLabel;
  final String terminalIcon;
  final VoidCallback onClose;
  final ValueChanged<CheckoutResult> onTerminal;

  /// Extra in-flight flag from the CALLER's op (e.g. a settle running on the
  /// floor/shift provider) — OR'd with the session's own `isPlacingOrder`.
  final bool placing;

  /// Cart-only discount chips (a ticket's discount is frozen at fire time).
  final bool showDiscountPicker;

  /// Cart-only customer/notes capture (a ticket carries its covering).
  final bool showCustomerFields;

  /// Optional extra header rows under the title (e.g. a settle line-item
  /// review) so the drawer stays self-contained.
  final Widget? headerContent;

  @override
  ConsumerState<CheckoutDrawer> createState() => _CheckoutDrawerState();
}

class _CheckoutDrawerState extends ConsumerState<CheckoutDrawer> {
  // Widget-local ephemera only — every rendered value flows from
  // [checkoutProvider].
  final _customer = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _customer.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Cash-first default (the natives' LaunchedEffect pick), resolved lazily
  /// so the async method load never races the first frame.
  String? _effectiveSelected(CheckoutState s) {
    final picked = s.selectedMethodId;
    if (picked != null && s.paymentMethods.any((m) => m.id == picked)) {
      return picked;
    }
    final cash = s.paymentMethods.where((m) => m.isCash).firstOrNull;
    return (cash ?? s.paymentMethods.firstOrNull)?.id;
  }

  void _fireTerminal(
    CheckoutState s, {
    required String? selected,
    required bool isCash,
    required List<CheckoutSplit> splitLegs,
    required String? splitPrimary,
  }) {
    final primary = s.splitMode ? splitPrimary : selected;
    if (primary == null) return;
    String? blank(String v) => v.trim().isEmpty ? null : v.trim();
    widget.onTerminal(
      CheckoutResult(
        primaryMethodId: primary,
        tenderedMinor: s.tenderedMinor,
        tipMinor: s.tipMinor,
        tipPaymentMethodId: s.tipMethodId,
        customerName: blank(_customer.text),
        notes: blank(_notes.text),
        splits: s.splitMode ? splitLegs : const [],
        isCash: isCash,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    // The drawer renders nearly every session field — the one legitimate
    // whole-state watch; the leaf chips receive plain data below.
    final s = ref.watch(checkoutProvider);
    final notifier = ref.read(checkoutProvider.notifier);
    String tr(String key) => bridge.tr(key: key);

    final methods = s.paymentMethods;
    final selected = _effectiveSelected(s);
    final method = methods.where((m) => m.id == selected).firstOrNull;
    final isCash = method?.isCash ?? false;
    final total = s.summary.totalMinor;

    // A tip paid by cash comes out of the same drawer → due with the
    // bill. The tip can ride a DIFFERENT method than the order (e.g.
    // card order + cash tip), so gate on the TIP method's isCash
    // (tipMethod ?? selected), not the order's.
    final tipMethodView = methods
        .where((m) => m.id == (s.tipMethodId ?? selected))
        .firstOrNull;
    final tipMethodIsCash = s.tipMinor > 0 && (tipMethodView?.isCash ?? isCash);
    final tipCash = tipMethodIsCash ? s.tipMinor : 0;
    final dueCash = total + tipCash;
    final change = math.max(s.tenderedMinor - dueCash, 0);
    final short = math.max(dueCash - s.tenderedMinor, 0);

    final splitAllocated = s.splitAmounts.values.fold(0, (a, b) => a + b);
    final splitRemaining = total - splitAllocated;
    final positiveLegs = s.splitAmounts.entries
        .where((e) => e.value > 0)
        .toList(growable: false);
    final splitLegs = positiveLegs
        .map(
          (e) => CheckoutSplit(paymentMethodId: e.key, amountMinor: e.value),
        )
        .toList(growable: false);
    String? splitPrimary;
    var largest = 0;
    for (final e in positiveLegs) {
      if (e.value > largest) {
        largest = e.value;
        splitPrimary = e.key;
      }
    }
    final placing = widget.placing || s.isPlacingOrder;
    final canPlace = switch (placing) {
      true => false,
      false when s.splitMode => splitAllocated == total && splitLegs.isNotEmpty,
      false => selected != null && (!isCash || s.tenderedMinor >= dueCash),
    };

    final error = s.error;
    return Column(
      children: [
        // Sticky header — title + live order total + close. Lives
        // outside the scroll so it pins like the natives' sheet header.
        _TenderHeader(
          title: widget.title,
          totalMinor: total,
          currency: s.currency,
          onClose: widget.onClose,
        ),
        const Hairline(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.xl,
              vertical: Space.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.lg,
              children: [
                // Caller-supplied header block (e.g. the settle
                // line-item review) — sits above the summary so the
                // teller sees WHAT they're charging first.
                ?widget.headerContent,
                // Order summary card — subtotal/discount/tax light
                // above, the grand total in a tinted teal block.
                _SummaryCard(
                  summary: s.summary,
                  currency: s.currency,
                  totalLabel: tr('order.total'),
                  subtotalLabel: tr('order.subtotal'),
                  discountLabel: tr('order.discount'),
                  taxLabel: tr('order.tax'),
                ),
                // Payment — brand-colored method chips, or a split
                // allocator.
                _PaymentSection(
                  methods: methods,
                  currency: s.currency,
                  sectionLabel: tr('order.payment_method'),
                  splitToggleLabel: tr('order.split_payment'),
                  splitRemainingLabel: tr('order.split_remaining'),
                  splitMode: s.splitMode,
                  onToggleSplit: notifier.toggleSplit,
                  selected: selected,
                  onSelect: notifier.selectMethod,
                  splitAmounts: s.splitAmounts,
                  splitRemaining: splitRemaining,
                  onSplitAmount: notifier.setSplitAmount,
                ),
                // Cash tendered (cash, non-split) — hero amount-due
                // block, quick chips, and a live change banner.
                if (isCash && !s.splitMode)
                  _CashSection(
                    currency: s.currency,
                    sectionLabel: tr('order.cash_received'),
                    totalLabel: tr('order.total'),
                    exactLabel: tr('order.exact'),
                    changeDueLabel: tr('order.change_due'),
                    shortByLabel: tr('order.short_by'),
                    dueCash: dueCash,
                    tendered: s.tenderedMinor,
                    change: change,
                    short: short,
                    onTendered: notifier.setTendered,
                  ),
                // Tip card — optional, with which method pays the tip.
                _TipCard(
                  methods: methods,
                  currency: s.currency,
                  tipLabel: tr('order.tip'),
                  tip: s.tipMinor,
                  selected: selected,
                  tipMethod: s.tipMethodId,
                  onTip: notifier.setTip,
                  onTipMethod: notifier.setTipMethod,
                ),
                // Discount (cart only — a ticket's is frozen at fire).
                if (widget.showDiscountPicker)
                  _DiscountSection(
                    discounts: s.discounts,
                    cartDiscountId: s.cartDiscountId,
                    sectionLabel: tr('order.discount'),
                    noDiscountLabel: tr('order.no_discount'),
                    onPick: (id) => unawaited(notifier.setDiscount(id)),
                  ),
                // Customer + notes (cart only).
                if (widget.showCustomerFields)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Space.sm,
                    children: [
                      SectionLabel(tr('order.customer')),
                      CheckoutTextField(
                        controller: _customer,
                        placeholder: tr('order.customer_hint'),
                        icon: 'person',
                      ),
                      CheckoutTextField(
                        controller: _notes,
                        placeholder: tr('order.notes_hint'),
                        icon: 'text.bubble',
                      ),
                    ],
                  ),
                if (error != null)
                  NoticeBanner(
                    text: error,
                    tone: ChipTone.danger,
                    icon: 'exclamationmark.circle',
                  ),
              ],
            ),
          ),
        ),
        // Sticky footer — the terminal action (Place Order / Settle).
        ColoredBox(
          color: colors.surface,
          child: Column(
            children: [
              const Hairline(),
              Padding(
                padding: const EdgeInsetsDirectional.all(Space.lg),
                child: ActionButton(
                  label: widget.terminalLabel,
                  icon: widget.terminalIcon,
                  loading: placing,
                  enabled: canPlace,
                  onTap: () => _fireTerminal(
                    s,
                    selected: selected,
                    isCash: isCash,
                    splitLegs: splitLegs,
                    splitPrimary: splitPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sticky sheet header — bold title + the live order total in hero teal + a
/// close affordance. Mirrors the natives' TenderHeader.
class _TenderHeader extends StatelessWidget {
  const _TenderHeader({
    required this.title,
    required this.totalMinor,
    required this.currency,
    required this.onClose,
  });

  final String title;
  final int totalMinor;
  final String currency;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: Space.xl,
        end: Space.xl,
        top: Space.sm,
        bottom: Space.md,
      ),
      child: Row(
        spacing: Space.sm,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.h3.copyWith(
                fontSize: _headerTitleSize,
                fontWeight: FontWeight.w900,
                color: colors.textPrimary,
              ),
            ),
          ),
          MoneyText(
            totalMinor,
            currency: currency,
            style: MadarType.money.copyWith(
              fontSize: _headerTotalSize,
              fontWeight: FontWeight.w900,
            ),
          ),
          TactileScale(
            onTap: onClose,
            child: Container(
              width: Metrics.closeButton,
              height: Metrics.closeButton,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: MadarIcon(
                'xmark',
                tint: colors.textMuted,
                size: IconSize.sm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Order totals card — subtotal/discount/tax in light muted rows, then the
/// grand total in a tinted teal block (bold teal figure). Matches the Order
/// screen's CartFooter total block.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.currency,
    required this.totalLabel,
    required this.subtotalLabel,
    required this.discountLabel,
    required this.taxLabel,
  });

  final CheckoutSummary summary;
  final String currency;
  final String totalLabel;
  final String subtotalLabel;
  final String discountLabel;
  final String taxLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.borderLight),
        boxShadow: MadarElevation.card.shadows(colors, dark: dark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xs,
        children: [
          _SummaryRow(
            label: subtotalLabel,
            value: Money.format(summary.subtotalMinor, currency: currency),
          ),
          if (summary.discountMinor > 0)
            _SummaryRow(
              label: discountLabel,
              value:
                  '−${Money.format(summary.discountMinor, currency: currency)}',
              valueColor: colors.success,
            ),
          if (summary.taxMinor > 0)
            _SummaryRow(
              label: taxLabel,
              value: Money.format(summary.taxMinor, currency: currency),
            ),
          // Grand-total block — tinted teal, the hero figure.
          Padding(
            padding: const EdgeInsetsDirectional.only(top: Space.xs),
            child: Container(
              padding: const EdgeInsetsDirectional.all(Space.md),
              decoration: BoxDecoration(
                color: colors.accentBg,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      totalLabel,
                      style: MadarType.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                      ),
                    ),
                  ),
                  MoneyText(
                    summary.totalMinor,
                    currency: currency,
                    style: MadarType.money.copyWith(
                      fontSize: _grandTotalSize,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: MadarType.bodySm.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: MadarType.bodySm.copyWith(
            fontSize: _rowSize,
            fontWeight: FontWeight.w600,
            color: valueColor ?? colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Payment — the section label + split toggle, then either a brand-color
/// method grid or the split allocator.
class _PaymentSection extends StatelessWidget {
  const _PaymentSection({
    required this.methods,
    required this.currency,
    required this.sectionLabel,
    required this.splitToggleLabel,
    required this.splitRemainingLabel,
    required this.splitMode,
    required this.onToggleSplit,
    required this.selected,
    required this.onSelect,
    required this.splitAmounts,
    required this.splitRemaining,
    required this.onSplitAmount,
  });

  final List<PaymentMethodView> methods;
  final String currency;
  final String sectionLabel;
  final String splitToggleLabel;
  final String splitRemainingLabel;
  final bool splitMode;
  final VoidCallback onToggleSplit;
  final String? selected;
  final ValueChanged<String> onSelect;
  final Map<String, int> splitAmounts;
  final int splitRemaining;
  final void Function(String id, int minor) onSplitAmount;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionLabel(sectionLabel),
            ),
            if (methods.length > 1)
              TactileScale(
                onTap: () {
                  MadarHaptics.selection();
                  onToggleSplit();
                },
                child: Container(
                  padding: _splitTogglePad,
                  decoration: BoxDecoration(
                    color: splitMode ? colors.accentBg : colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs,
                    children: [
                      MadarIcon(
                        splitMode
                            ? 'checkmark.circle.fill'
                            : 'rectangle.split.2x1',
                        tint: splitMode ? colors.accent : colors.textMuted,
                      ),
                      Text(
                        splitToggleLabel,
                        style: MadarType.labelSm.copyWith(
                          fontSize: _pillLabelSize,
                          color: splitMode ? colors.accent : colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (splitMode)
          _SplitAllocator(
            methods: methods,
            currency: currency,
            remainingLabel: splitRemainingLabel,
            splitAmounts: splitAmounts,
            splitRemaining: splitRemaining,
            onSplitAmount: onSplitAmount,
          )
        else
          _MethodGrid(methods: methods, selected: selected, onSelect: onSelect),
      ],
    );
  }
}

/// Two-column grid of payment-method chips — the SHARED method selector used
/// by both the checkout and the settle sheet.
class _MethodGrid extends StatelessWidget {
  const _MethodGrid({
    required this.methods,
    required this.selected,
    required this.onSelect,
  });

  final List<PaymentMethodView> methods;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < methods.length; i += 2) {
      final pair = methods.sublist(i, math.min(i + 2, methods.length));
      rows.add(
        Row(
          spacing: Space.sm,
          children: [
            for (final m in pair)
              Expanded(
                child: _PayChip(
                  method: m,
                  active: m.id == selected,
                  onTap: () => onSelect(m.id),
                ),
              ),
            if (pair.length == 1) const Expanded(child: SizedBox.shrink()),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: rows,
    );
  }
}

/// Payment method tile — a per-method icon (in the method's brand color) +
/// label + check when active; fills with the brand color when selected.
class _PayChip extends StatelessWidget {
  const _PayChip({
    required this.method,
    required this.active,
    required this.onTap,
  });

  final PaymentMethodView method;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final brand = hexColor(method.color);
    return TactileScale(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        padding: _payChipPad,
        decoration: BoxDecoration(
          color: active ? brand : colors.surface,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: active ? null : Border.all(color: colors.border),
        ),
        child: Row(
          spacing: Space.sm,
          children: [
            MadarIcon(
              payGlyph(method.icon),
              tint: active ? colors.textOnAccent : brand,
            ),
            Expanded(
              child: Text(
                method.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: active ? colors.textOnAccent : colors.textPrimary,
                ),
              ),
            ),
            if (active)
              MadarIcon(
                'checkmark',
                tint: colors.textOnAccent,
                size: IconSize.sm,
              ),
          ],
        ),
      ),
    );
  }
}

/// Per-method amount entry + a live remaining indicator (must reach 0).
class _SplitAllocator extends StatelessWidget {
  const _SplitAllocator({
    required this.methods,
    required this.currency,
    required this.remainingLabel,
    required this.splitAmounts,
    required this.splitRemaining,
    required this.onSplitAmount,
  });

  final List<PaymentMethodView> methods;
  final String currency;
  final String remainingLabel;
  final Map<String, int> splitAmounts;
  final int splitRemaining;
  final void Function(String id, int minor) onSplitAmount;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final settled = splitRemaining == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        for (final m in methods)
          Row(
            spacing: Space.sm,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: hexColor(m.color),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: _splitDot),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _splitNameMax),
                child: Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: AmountField(
                  amountMinor: splitAmounts[m.id] ?? 0,
                  onAmountMinor: (minor) => onSplitAmount(m.id, minor),
                  currencyCode: currency,
                ),
              ),
            ],
          ),
        Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.md,
            vertical: _bannerVPad,
          ),
          decoration: BoxDecoration(
            color: settled ? colors.successBg : colors.warningBg,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  remainingLabel,
                  style: MadarType.label.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              MoneyText(
                splitRemaining,
                currency: currency,
                style: MadarType.money.copyWith(fontSize: _rowSize),
                color: settled ? colors.success : colors.danger,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cash tendered — a tinted teal "Amount Due" hero block, the cash field,
/// round presets, and a live change banner.
class _CashSection extends StatelessWidget {
  const _CashSection({
    required this.currency,
    required this.sectionLabel,
    required this.totalLabel,
    required this.exactLabel,
    required this.changeDueLabel,
    required this.shortByLabel,
    required this.dueCash,
    required this.tendered,
    required this.change,
    required this.short,
    required this.onTendered,
  });

  final String currency;
  final String sectionLabel;
  final String totalLabel;
  final String exactLabel;
  final String changeDueLabel;
  final String shortByLabel;
  final int dueCash;
  final int tendered;
  final int change;
  final int short;
  final ValueChanged<int> onTendered;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        SectionLabel(sectionLabel),
        // Amount-due hero block — tinted teal, the figure the cash tendered
        // must reach (mirrors the grand-total block in weight + treatment).
        Container(
          padding: const EdgeInsetsDirectional.all(Space.md),
          decoration: BoxDecoration(
            color: colors.accentBg,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  totalLabel,
                  style: MadarType.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.accent,
                  ),
                ),
              ),
              MoneyText(
                dueCash,
                currency: currency,
                style: MadarType.money.copyWith(
                  fontSize: _dueAmountSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        AmountField(
          amountMinor: tendered,
          onAmountMinor: onTendered,
          currencyCode: currency,
        ),
        // Round-number cash presets at or above the amount due.
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            _QuickCash(
              label: exactLabel,
              active: tendered == dueCash,
              onTap: () => onTendered(dueCash),
            ),
            for (final preset
                in _cashPresets
                    .where((p) => p >= dueCash)
                    .take(_cashPresetCount))
              _QuickCash(
                label: Money.format(preset, currency: currency),
                active: tendered == preset,
                onTap: () => onTendered(preset),
              ),
          ],
        ),
        if (tendered > 0)
          _ChangeBanner(
            currency: currency,
            changeDueLabel: changeDueLabel,
            shortByLabel: shortByLabel,
            change: change,
            short: short,
          ),
      ],
    );
  }
}

/// A quick-tender amount chip (Exact / round-number presets) filling cash.
class _QuickCash extends StatelessWidget {
  const _QuickCash({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        padding: _quickCashPad,
        decoration: BoxDecoration(
          color: active ? colors.accent : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: active ? null : Border.all(color: colors.border),
        ),
        child: Text(
          label,
          textDirection: TextDirection.ltr,
          style: MadarType.label.copyWith(
            fontWeight: FontWeight.w700,
            color: active ? colors.textOnAccent : colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Green "Change due" / red "Short by" banner under the cash field — a
/// leading tone icon + the hero change figure.
class _ChangeBanner extends StatelessWidget {
  const _ChangeBanner({
    required this.currency,
    required this.changeDueLabel,
    required this.shortByLabel,
    required this.change,
    required this.short,
  });

  final String currency;
  final String changeDueLabel;
  final String shortByLabel;
  final int change;
  final int short;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final ok = short <= 0;
    final fg = ok ? colors.success : colors.danger;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.md,
        vertical: _bannerVPad,
      ),
      decoration: BoxDecoration(
        color: ok ? colors.successBg : colors.dangerBg,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        spacing: Space.sm,
        children: [
          MadarIcon(
            ok ? 'checkmark.circle.fill' : 'exclamationmark.triangle.fill',
            tint: fg,
            size: IconSize.lg,
          ),
          Expanded(
            child: Text(
              ok ? changeDueLabel : shortByLabel,
              style: MadarType.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
          MoneyText(
            ok ? change : short,
            currency: currency,
            style: MadarType.money.copyWith(
              fontSize: _changeAmountSize,
              fontWeight: FontWeight.w900,
            ),
            color: fg,
          ),
        ],
      ),
    );
  }
}

/// Tip card — optional, with which method pays the tip.
class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.methods,
    required this.currency,
    required this.tipLabel,
    required this.tip,
    required this.selected,
    required this.tipMethod,
    required this.onTip,
    required this.onTipMethod,
  });

  final List<PaymentMethodView> methods;
  final String currency;
  final String tipLabel;
  final int tip;
  final String? selected;
  final String? tipMethod;
  final ValueChanged<int> onTip;
  final ValueChanged<String> onTipMethod;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.borderLight),
        boxShadow: MadarElevation.card.shadows(colors, dark: dark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          Row(
            spacing: Space.xs + 2,
            children: [
              MadarIcon(
                'heart.circle',
                tint: colors.textMuted,
                size: _tipHeart,
              ),
              Expanded(child: SectionLabel(tipLabel)),
              if (tip > 0)
                StatusChip(
                  label: Money.format(tip, currency: currency),
                  tone: ChipTone.success,
                  icon: 'plus',
                ),
            ],
          ),
          if (methods.length > 1)
            Wrap(
              spacing: Space.xs + 2,
              runSpacing: Space.xs + 2,
              children: [
                for (final m in methods)
                  _TipMethodPill(
                    method: m,
                    active: (tipMethod ?? selected) == m.id,
                    onTap: () => onTipMethod(m.id),
                  ),
              ],
            ),
          AmountField(
            amountMinor: tip,
            onAmountMinor: onTip,
            currencyCode: currency,
          ),
        ],
      ),
    );
  }
}

/// Which-method-pays-the-tip pill — brand-filled when active.
class _TipMethodPill extends StatelessWidget {
  const _TipMethodPill({
    required this.method,
    required this.active,
    required this.onTap,
  });

  final PaymentMethodView method;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        padding: _tipPillPad,
        decoration: BoxDecoration(
          color: active ? hexColor(method.color) : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: active ? null : Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            if (active)
              MadarIcon(
                'checkmark',
                tint: colors.textOnAccent,
                size: _chipCheck,
              ),
            Text(
              method.name,
              style: MadarType.labelSm.copyWith(
                fontSize: _pillLabelSize,
                color: active ? colors.textOnAccent : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Discount — wrapping pill chips (No discount + each active discount).
class _DiscountSection extends StatelessWidget {
  const _DiscountSection({
    required this.discounts,
    required this.cartDiscountId,
    required this.sectionLabel,
    required this.noDiscountLabel,
    required this.onPick,
  });

  final List<DiscountView> discounts;
  final String? cartDiscountId;
  final String sectionLabel;
  final String noDiscountLabel;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final active = discounts.where((d) => d.isActive).toList(growable: false);
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        SectionLabel(sectionLabel),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            _DiscountChip(
              label: noDiscountLabel,
              active: cartDiscountId == null,
              onTap: () => onPick(null),
            ),
            for (final d in active)
              _DiscountChip(
                label: _discountLabel(d),
                active: cartDiscountId == d.id,
                onTap: () => onPick(d.id),
              ),
          ],
        ),
      ],
    );
  }
}

String _discountLabel(DiscountView d) =>
    d.dtype == 'percentage' ? '${d.name} ${d.value}%' : d.name;

/// Discount chip — a content-width pill with a leading check when active,
/// laid out in a Wrap (NOT a full-width stacked row).
class _DiscountChip extends StatelessWidget {
  const _DiscountChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        padding: _discountChipPad,
        decoration: BoxDecoration(
          color: active ? colors.accent : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: active ? null : Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: _chipGap,
          children: [
            if (active)
              MadarIcon(
                'checkmark',
                tint: colors.textOnAccent,
                size: _chipCheck,
              ),
            Text(
              label,
              style: MadarType.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: active ? colors.textOnAccent : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
