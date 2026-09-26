import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/charge_strings.dart';
import 'package:feature_checkout/src/charge_target.dart';
import 'package:feature_checkout/src/loyalty_award_sheet.dart';
import 'package:feature_checkout/src/receipt_printing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

part 'done_page.dart';
part 'done_sale.dart';

/// The card's distance from the top of the window (the canvas: 76 — it
/// clears the top bar); its width cap is the top card's 600.
const double _cardTopTablet = 76;
const double _cardTopPhone = 60;

/// The state glyph at the card's start.
const double _markSize = 40;

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
/// A route in the kit's surface stack ([showMadarTopCard]), not a floating
/// overlay: a sheet it opens ("Add points") lands ABOVE it. It does not dim
/// the grid: a tap outside the card means "not yet" — the table keeps waiting
/// for a bus — and still lands on what was tapped, so a product tile starts
/// the next sale in one tap. Resolves once the card is gone.
Future<DoneCardResult> showDoneCard(
  BuildContext context,
  ChargeOutcome outcome, {
  VoidCallback? onPrinterSettings,
}) async {
  final layout = MadarLayout.of(context);
  final result = await showMadarTopCard<DoneCardResult>(
    context,
    barrierResult: DoneCardResult.notYet,
    padding: EdgeInsetsDirectional.only(
      top: layout.pick(phone: _cardTopPhone, tablet: _cardTopTablet),
      start: layout.gutter,
      end: layout.gutter,
    ),
    builder: (cardContext) => DoneCard(
      outcome: outcome,
      onPrinterSettings: onPrinterSettings,
      onDone: (r) => MadarSheet.close(cardContext, r),
    ),
  );
  return result ?? DoneCardResult.notYet;
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

class _DoneCardState extends ConsumerState<DoneCard> with _DoneSale<DoneCard> {
  @override
  ChargeOutcome get _outcome => widget.outcome;

  @override
  void _finish(DoneCardResult result) => widget.onDone(result);

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final o = widget.outcome;
    String tr(String key) => chargeTr(bridge, key);
    final phone = context.isPhone;

    // The headline: what happened, and the figure that names it.
    final ref_ = _saleRef;
    final headline = TextSpan(
      children: [
        TextSpan(
          text: _queued
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
              color: _queued ? colors.textSecondary : colors.textPrimary,
            ),
          ),
        ),
        if (!_queued) ...[
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
        if (_queued) ...[
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
            child: MoneyText(
              o.changeMinor,
              currency: o.currency,
              style: MadarType.money,
              color: colors.textSecondary,
            ),
          ),
        ],
        if (_queued) TextSpan(text: ' · ${tr('charge.will_send')}'),
        // The server recorded this sale's rewards without taking points (the
        // card was spent elsewhere first). The sale stands; the teller hears it.
        if (_receipt?.loyaltyNotice case final notice?)
          TextSpan(text: '\n$notice'),
        // A sale that carried staff drinks: how many are left today (or that
        // it went over) — or, plainly, that this server could not price them.
        if (_staffNotice case final notice?) TextSpan(text: '\n$notice'),
      ],
    );

    final printStatus = _PrintStatus(
      state: _print,
      hasReceipt: _receipt != null,
      tr: tr,
      bridge: bridge,
      onPrinterSettings: widget.onPrinterSettings,
    );

    final actions = <Widget>[
      // Only where a programme runs — and the sale must name itself.
      if (_offersPoints)
        MadarButton(
          label: bridge.tr(key: 'loyalty.add_points'),
          glyph: MadarGlyph.star,
          size: MadarButtonSize.compact,
          variant: MadarButtonVariant.secondary,
          onTap: () => unawaited(_addPoints()),
        ),
      if (_receipt != null)
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
    if (table != null) {
      // Secondary, beside Reprint: the answer the floor is waiting for. The
      // primary is the next sale; leaving without it means "not yet", which
      // never lies about the room.
      actions.add(
        MadarButton(
          label: o.tableLabel == null
              ? tr('charge.cleared')
              : '${o.tableLabel} · ${tr('charge.cleared')}',
          glyph: MadarGlyph.check,
          size: MadarButtonSize.compact,
          variant: MadarButtonVariant.secondary,
          loading: _clearing,
          onTap: () => unawaited(_clear(table)),
        ),
      );
    }
    final newSale = MadarButton(
      label: tr('charge.new_sale'),
      glyph: MadarGlyph.plus,
      size: MadarButtonSize.compact,
      onTap: () => widget.onDone(DoneCardResult.notYet),
    );

    return Listener(
      onPointerDown: (_) => _holdOpen(),
      child: Container(
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
          // Hugs its content: the card used to stretch to the window.
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                // The settle mark draws closed and strikes its check once; a
                // sale parked for the network gets the living amber clock.
                SizedBox.square(
                  dimension: _markSize,
                  child: _queued
                      ? const QueuedMark(size: _markSize)
                      : const SettleMark(size: _markSize),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.xs,
                    children: [
                      Text.rich(
                        headline,
                        style: MadarType.h3.copyWith(color: colors.textPrimary),
                      ),
                      Text.rich(
                        detail,
                        style: MadarType.bodySm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      printStatus,
                    ],
                  ),
                ),
              ],
            ),
            if (_clearError case final err?)
              NoticeBanner(
                text: err,
                tone: ChipTone.danger,
                icon: 'exclamationmark.circle',
              ),
            if (phone)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.sm,
                children: [
                  if (actions.isNotEmpty)
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: actions,
                    ),
                  newSale,
                ],
              )
            else
              Row(
                spacing: Space.sm,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: actions,
                    ),
                  ),
                  newSale,
                ],
              ),
          ],
        ),
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
