import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/charge_strings.dart';
import 'package:feature_checkout/src/charge_target.dart';
import 'package:feature_checkout/src/loyalty_award_sheet.dart';
import 'package:feature_checkout/src/receipt_printing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The card's width on a tablet and its distance from the top of the window
/// (the canvas: 600 / 76 — it clears the top bar).
const double _cardWidth = 600;
const double _cardTopTablet = 76;
const double _cardTopPhone = 60;

/// The state glyph at the card's start.
const double _markSize = 28;

/// How the Done card was put away.
enum DoneCardResult {
  /// "Cleared" — the table is free again.
  cleared,

  /// "Not yet", or a tap anywhere behind the card. The table keeps waiting
  /// for a bus. On a card with no table this is the only answer.
  notYet,
}

/// Slide the Done card down over whatever the teller is standing on.
///
/// Not a screen and not a dialog: nothing behind it is blocked. The next tap
/// on the host goes THROUGH to the host — the next tile tap IS the new sale
/// — and dismisses the card on its way, which for a bill means "not yet".
/// Resolves once the card is gone.
Future<DoneCardResult> showDoneCard(
  BuildContext context,
  ChargeOutcome outcome, {
  VoidCallback? onPrinterSettings,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final done = Completer<DoneCardResult>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _DoneCardOverlay(
      outcome: outcome,
      onPrinterSettings: onPrinterSettings,
      onGone: (result) {
        entry.remove();
        if (!done.isCompleted) done.complete(result);
      },
    ),
  );
  overlay.insert(entry);
  return done.future;
}

/// The overlay: positions the card, plays it in and out, and watches for the
/// pointer-down that dismisses it — anywhere but on the card itself.
class _DoneCardOverlay extends StatefulWidget {
  const _DoneCardOverlay({
    required this.outcome,
    required this.onGone,
    this.onPrinterSettings,
  });

  final ChargeOutcome outcome;
  final ValueChanged<DoneCardResult> onGone;
  final VoidCallback? onPrinterSettings;

  @override
  State<_DoneCardOverlay> createState() => _DoneCardOverlayState();
}

class _DoneCardOverlayState extends State<_DoneCardOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: MotionSpec.standardDuration,
  );
  final GlobalKey _cardKey = GlobalKey();
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _anim.forward();
    // A global route, not a barrier: a barrier would eat the tap that is
    // meant to start the next sale. This only WATCHES pointers; the card's
    // own box is excluded, and everything else still gets its tap.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _anim.dispose();
    super.dispose();
  }

  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent || _leaving) return;
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final local = box.globalToLocal(event.position);
      if (box.paintBounds.contains(local)) return;
    }
    unawaited(_dismiss(DoneCardResult.notYet));
  }

  Future<void> _dismiss(DoneCardResult result) async {
    if (_leaving) return;
    _leaving = true;
    await _anim.reverse();
    if (mounted) widget.onGone(result);
  }

  @override
  Widget build(BuildContext context) {
    final layout = MadarLayout.of(context);
    final slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: MotionSpec.springOut));
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            top: layout.pick(phone: _cardTopPhone, tablet: _cardTopTablet),
            start: layout.gutter,
            end: layout.gutter,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _cardWidth),
            child: SlideTransition(
              position: slide,
              child: FadeTransition(
                opacity: _anim,
                child: Material(
                  type: MaterialType.transparency,
                  child: KeyedSubtree(
                    key: _cardKey,
                    child: DoneCard(
                      outcome: widget.outcome,
                      onPrinterSettings: widget.onPrinterSettings,
                      onDone: (r) => unawaited(_dismiss(r)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Done card — two variants of one card.
///
/// The happy sale: "Sale #1042 · EGP 196.00 / Cash · change 4.00 / Printed".
/// The queued one: "Queued · #local-8f2a / …will send when back online".
/// Add points and Reprint on both; on a bill, "T5 cleared?" with Cleared /
/// Not yet. Self-contained: the Charge session is gone by the time this is
/// up, so it prints, awards and clears with its own calls.
class DoneCard extends ConsumerStatefulWidget {
  const DoneCard({
    required this.outcome,
    required this.onDone,
    this.onPrinterSettings,
    super.key,
  });

  final ChargeOutcome outcome;
  final ValueChanged<DoneCardResult> onDone;

  /// Where "Not printed — no printer" goes when tapped. Null hides the
  /// chevron; the words stay.
  final VoidCallback? onPrinterSettings;

  @override
  ConsumerState<DoneCard> createState() => _DoneCardState();
}

class _DoneCardState extends ConsumerState<DoneCard> {
  late PrintState _print = widget.outcome.printState;
  bool _clearing = false;
  String? _clearError;

  Future<void> _reprint() async {
    final receipt = widget.outcome.receipt;
    if (receipt == null || _print == PrintState.printing) return;
    setState(() => _print = PrintState.printing);
    final result = await printReceiptView(
      ref.read(bridgeProvider),
      ref.read(printerServiceProvider),
      receipt,
      kickDrawer: false,
    );
    if (mounted) setState(() => _print = result);
  }

  /// The plates are gone. Optimistic locally and queued for the server, so
  /// it works offline like everything else on the floor.
  Future<void> _clear(String tableId) async {
    if (_clearing) return;
    setState(() {
      _clearing = true;
      _clearError = null;
    });
    final bridge = ref.read(bridgeProvider);
    try {
      await bridge.clearTable(tableId: tableId);
      if (!mounted) return;
      MadarHaptics.success();
      widget.onDone(DoneCardResult.cleared);
    } on MadarError catch (e) {
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _clearError = bridge.humanMessage(e);
      });
    }
  }

  Future<void> _addPoints() async {
    final o = widget.outcome;
    await showMadarSheet<bool>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => LoyaltyAwardSheet(
        orderId: o.orderId,
        // A just-rung cart sale is known by its client key — the server id
        // may not exist yet.
        orderKey: o.orderId == null ? o.orderKey : null,
        orderCreatedAt: o.createdAt,
        // If a card was scanned to pay, it is the same customer collecting —
        // no second scan.
        customerId: o.loyaltyCustomerId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final o = widget.outcome;
    String tr(String key) => chargeTr(bridge, key);
    final phone = context.isPhone;

    // The headline: what happened, and the figure that names it.
    final ref_ = o.queued
        ? '#${o.orderKey?.substring(0, o.orderKey!.length.clamp(0, 8)) ?? ''}'
        : o.orderNumber != null
        ? '#${o.orderNumber}'
        : (o.receipt?.orderRef ?? '');
    final headline = TextSpan(
      children: [
        TextSpan(
          text: o.queued
              ? '${bridge.tr(key: 'sync.queued')} · '
              : '${tr('charge.sale')} ',
        ),
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Text(
            ref_,
            textDirection: TextDirection.ltr,
            style: MadarType.numLg.copyWith(
              color: o.queued ? colors.textSecondary : colors.textPrimary,
            ),
          ),
        ),
        if (!o.queued) ...[
          const TextSpan(text: ' · '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: MoneyText(
              o.amountMinor,
              currency: o.currency,
              style: MadarType.moneyMd.copyWith(fontSize: 18),
              color: colors.textPrimary,
            ),
          ),
        ],
      ],
    );
    // The line under it: method, change, and for a queued sale the honest
    // sentence about where it is.
    final detail = TextSpan(
      children: [
        if (o.queued) ...[
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: MoneyText(
              o.amountMinor,
              currency: o.currency,
              style: MadarType.money,
              color: colors.textPrimary,
            ),
          ),
          const TextSpan(text: ' '),
        ],
        TextSpan(text: o.methodLabel),
        if (o.isCash && o.changeMinor > 0) ...[
          TextSpan(text: ' · ${tr('charge.change_short')} '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Text(
              Money.format(o.changeMinor),
              textDirection: TextDirection.ltr,
              style: MadarType.numMd.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
        if (o.queued) TextSpan(text: ' · ${tr('charge.will_send')}'),
      ],
    );

    final printStatus = _PrintStatus(
      state: _print,
      hasReceipt: o.receipt != null,
      tr: tr,
      bridge: bridge,
      onPrinterSettings: widget.onPrinterSettings,
    );

    final actions = <Widget>[
      if (o.canAwardPoints)
        MadarButton(
          label: bridge.tr(key: 'loyalty.add_points'),
          glyph: MadarGlyph.star,
          size: MadarButtonSize.compact,
          variant: MadarButtonVariant.secondary,
          onTap: () => unawaited(_addPoints()),
        ),
      if (o.receipt != null)
        MadarButton(
          label: tr('charge.reprint'),
          glyph: MadarGlyph.printer,
          size: MadarButtonSize.compact,
          variant: MadarButtonVariant.secondary,
          loading: _print == PrintState.printing,
          onTap: () => unawaited(_reprint()),
        ),
    ];

    final table = o.tableId;
    final clearGroup = table == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm + 2,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    if (o.tableLabel != null)
                      TextSpan(
                        text: '${o.tableLabel} ',
                        style: MadarType.numLg.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    TextSpan(text: tr('charge.cleared_q')),
                  ],
                ),
                style: MadarType.title.copyWith(color: colors.textPrimary),
              ),
              MadarButton(
                label: tr('charge.cleared'),
                size: MadarButtonSize.compact,
                loading: _clearing,
                onTap: () => unawaited(_clear(table)),
              ),
              MadarButton(
                label: tr('charge.not_yet'),
                size: MadarButtonSize.compact,
                variant: MadarButtonVariant.ghost,
                onTap: () => widget.onDone(DoneCardResult.notYet),
              ),
            ],
          );

    return Container(
      padding: const EdgeInsetsDirectional.all(Space.card),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: colors.border),
        boxShadow: MadarElevation.raised.shadows(
          colors,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md + 2,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md + 2,
            children: [
              MadarGlyphIcon(
                o.queued ? MadarGlyph.half : MadarGlyph.checkCircle,
                size: _markSize,
                // The same half disc, in the same teal, as the outbox pill.
                color: colors.accent,
                filled: !o.queued,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text.rich(
                      headline,
                      style: MadarType.h3.copyWith(color: colors.textPrimary),
                    ),
                    Text.rich(
                      detail,
                      style: MadarType.body.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    if (phone) printStatus,
                  ],
                ),
              ),
              if (!phone) printStatus,
            ],
          ),
          if (_clearError case final err?)
            NoticeBanner(
              text: err,
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
          if (actions.isNotEmpty || clearGroup != null)
            if (phone)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.sm + 2,
                children: [
                  if (actions.isNotEmpty)
                    Row(
                      spacing: Space.sm + 2,
                      children: [for (final a in actions) Expanded(child: a)],
                    ),
                  if (clearGroup != null)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: clearGroup,
                    ),
                ],
              )
            else
              Row(
                spacing: Space.sm + 2,
                children: [...actions, const Spacer(), ?clearGroup],
              ),
        ],
      ),
    );
  }
}

/// "Printed" in green, "Not printed — no printer" in amber (a link when
/// there is somewhere to go), the printer's refusal in red. Nothing while
/// idle with no receipt — a queued bill has no paper yet, and says nothing
/// rather than something false.
class _PrintStatus extends StatelessWidget {
  const _PrintStatus({
    required this.state,
    required this.hasReceipt,
    required this.tr,
    required this.bridge,
    this.onPrinterSettings,
  });

  final PrintState state;
  final bool hasReceipt;
  final String Function(String) tr;
  final MadarBridge bridge;
  final VoidCallback? onPrinterSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final (String? text, Color tint, MadarGlyph glyph) = switch (state) {
      PrintState.printed => (
        tr('charge.printed'),
        colors.success,
        MadarGlyph.printer,
      ),
      PrintState.noPrinter => (
        tr('charge.not_printed'),
        colors.warning,
        MadarGlyph.printer,
      ),
      PrintState.failed => (
        bridge.tr(key: 'receipt.print_failed'),
        colors.danger,
        MadarGlyph.alertTriangle,
      ),
      PrintState.printing => (
        bridge.tr(key: 'receipt.printing'),
        colors.textSecondary,
        MadarGlyph.printer,
      ),
      PrintState.idle => (null, colors.textSecondary, MadarGlyph.printer),
    };
    if (text == null || !hasReceipt) return const SizedBox.shrink();
    final link = state == PrintState.noPrinter && onPrinterSettings != null;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + 2,
      children: [
        MadarGlyphIcon(glyph, size: IconSize.md, color: tint),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MadarType.bodySm.copyWith(
              fontWeight: FontWeight.w700,
              color: tint,
            ),
          ),
        ),
        if (link)
          MadarGlyphIcon(
            MadarGlyph.chevronForward,
            size: IconSize.sm,
            color: tint,
          ),
      ],
    );
    final go = onPrinterSettings;
    if (!link || go == null) return row;
    return TactileScale(onTap: go, child: row);
  }
}
