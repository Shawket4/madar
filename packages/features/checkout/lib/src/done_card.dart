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

/// The card's distance from the top of the window (the canvas: 76 — it
/// clears the top bar); its width cap is the top card's 600.
const double _cardTopTablet = 76;
const double _cardTopPhone = 60;

/// The state disc at the card's start (the canvas: 28) — half full while
/// the sale waits for the network, whole once it is in.
const double _discSize = 28;

/// Between the card's two rows, and between row 1's disc, words and print
/// state (the canvas: 14).
const double _rowGap = Space.md + 2;

/// Between row 2's buttons (the canvas: 10).
const double _buttonGap = Space.sm + 2;

/// Between the title and the body (the canvas: 2).
const double _lineGap = 2;

/// The print state at the end of row 1 never takes more than this from the
/// words beside it; a longer one ellipsises.
const double _printMaxWidth = 200;

/// How the Done card was put away.
enum DoneCardResult {
  /// "Cleared" — the table is free again.
  cleared,

  /// "Not yet", or a tap anywhere behind the card. The table keeps waiting
  /// for a bus. On a card with no table this is the only answer.
  notYet,
}

/// Slide the Done card down over whatever the teller is standing on — or,
/// in the Sell screen's Fast mode, over the menu panel on the end edge.
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
    // Fast mode: the Sell screen hosts its sheets in the menu panel on the
    // END edge, and the card lands over that panel — the right in English,
    // the left in Arabic — not over the cart. Everywhere else (the standard
    // layout, the floor, a bill) it keeps its place, centred at the top.
    over: MadarPanelHost.maybeOf(context)?.navigatorKey,
    builder: (cardContext) => DoneCard(
      outcome: outcome,
      onPrinterSettings: onPrinterSettings,
      onDone: (r) => MadarSheet.close(cardContext, r),
    ),
  );
  return result ?? DoneCardResult.notYet;
}

/// The Done card — two variants of one card (the canvas: Done.dc.html).
///
/// Row 1: the state disc, "Sale #1042" or "Queued · #36B-12", the body
/// "EGP 196.00 Cash · change 4.00" (+ "· will send when back online" while
/// queued), and at the end "Printed" once the paper is out. Row 2: Add
/// points and Reprint; on a table's sale "T5 cleared?" with Cleared / Not
/// yet at the end (a counter sale gets a quiet "New sale" there instead).
/// Self-contained: the Charge session is gone by the time this is up, so it
/// prints, awards and clears with its own calls.
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

  // A card kept open for a table's "cleared?" answer can outlive the
  // outbox drain — without this it would say "Queued" forever even after
  // the sale synced. Local state so a sync tick can flip it live.
  late bool _queued = widget.outcome.queued;
  late ReceiptView? _receipt = widget.outcome.receipt;

  /// The pool line the core worded when the sale was rung ("3 left today").
  /// The synced record does not carry it, so it is kept across the re-read —
  /// unless the server turned out not to support staff drinks, which the
  /// re-read says instead.
  late String? _staffNotice = widget.outcome.receipt?.staffNotice;
  bool _syncChecking = false;
  ProviderSubscription<int>? _syncSub;

  /// The card steps aside by itself once nothing is left to answer — the
  /// next customer is already at the counter. A touch on the card holds it.
  Timer? _autoDismiss;

  static const Duration _dismissAfter = Duration(seconds: 6);

  void _holdOpen() {
    _autoDismiss?.cancel();
    _autoDismiss = null;
  }

  void _armDismiss() {
    _holdOpen();
    // A table still waiting for "cleared?", or paper that did not come out,
    // is a question for the teller: those cards wait.
    final o = widget.outcome;
    if (o.tableId != null) return;
    if (_print == PrintState.failed || _print == PrintState.noPrinter) return;
    _autoDismiss = Timer(_dismissAfter, () {
      if (mounted) widget.onDone(DoneCardResult.notYet);
    });
  }

  @override
  void dispose() {
    _syncSub?.close();
    _holdOpen();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _armDismiss();
    // The auto-print is still running in the background: say "Printing…"
    // until it answers. It always answers — a timeout is a state too.
    final job = widget.outcome.printJob;
    if (job != null) {
      unawaited(
        job.then((result) {
          if (mounted && _print == PrintState.printing) {
            setState(() => _print = result);
            if (_autoDismiss != null) _armDismiss();
          }
        }),
      );
    }
    // The core bumps this on every sync event; a queued sale re-checks its
    // own record on each one rather than polling on a timer.
    if (_queued) {
      _syncSub = ref.listenManual(syncTickProvider, (_, _) {
        unawaited(_checkSynced());
      });
    }
  }

  /// Re-read this sale's record — a LOCAL lookup by client key or server id
  /// (`order_full_for` resolves either), so this only reaches the network in
  /// the rare case the row is not local yet. Flips the card out of "Queued"
  /// the moment the outbox has actually acked it.
  Future<void> _checkSynced() async {
    final key = widget.outcome.orderKey;
    if (!mounted || !_queued || _syncChecking || key == null) return;
    _syncChecking = true;
    try {
      final r = await ref.read(bridgeProvider).orderReceiptView(orderId: key);
      if (!mounted || r.queuedOffline) return;
      setState(() {
        _queued = false;
        _receipt = r;
        _staffNotice = r.staffNotice ?? _staffNotice;
      });
      _syncSub?.close();
      _syncSub = null;
      if (_autoDismiss != null) _armDismiss();
    } on Object catch (_) {
      // Best-effort, as printReceiptView: the row may not have landed
      // locally yet, or the bridge threw — the next sync tick tries again.
    } finally {
      _syncChecking = false;
    }
  }

  Future<void> _reprint() async {
    final receipt = _receipt;
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
    final bridge = ref.bridge;
    final o = widget.outcome;
    String tr(String key) => chargeTr(bridge, key);
    final phone = context.isPhone;

    // The title: what happened, and the reference that names it.
    // The device number reads the same queued or synced (`36B-12`); the
    // older fallbacks stay for a sale rung without one.
    final display = _receipt?.displayNumber ?? '';
    final ref_ = display.isNotEmpty
        ? '#$display'
        : _queued
        ? '#${o.orderKey?.substring(0, o.orderKey!.length.clamp(0, 8)) ?? ''}'
        : o.orderNumber != null
        ? '#${o.orderNumber}'
        : (_receipt?.orderRef ?? '');
    final title = Text.rich(
      key: const ValueKey('done-title'),
      TextSpan(
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
        ],
      ),
      style: MadarType.h3.copyWith(color: colors.textPrimary),
    );
    // The body: the total, how it was paid, the change — and for a queued
    // sale the honest sentence about where it is.
    final body = Text.rich(
      key: const ValueKey('done-body'),
      TextSpan(
        children: [
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
          TextSpan(text: ' ${o.methodLabel}'),
          if (o.isCash && o.changeMinor > 0) ...[
            TextSpan(text: ' · ${tr('charge.change_short')} '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: MoneyText(
                o.changeMinor,
                style: MadarType.numMd,
                color: colors.textSecondary,
              ),
            ),
          ],
          if (_queued) TextSpan(text: ' · ${tr('charge.will_send')}'),
          // The server recorded this sale's rewards without taking points
          // (the card was spent elsewhere first). The sale stands; the
          // teller hears it.
          if (_receipt?.loyaltyNotice case final notice?)
            TextSpan(text: '\n$notice'),
          // A sale that carried staff drinks: how many are left today (or
          // that it went over) — or, plainly, that this server could not
          // price them.
          if (_staffNotice case final notice?) TextSpan(text: '\n$notice'),
        ],
      ),
      style: MadarType.body.copyWith(color: colors.textSecondary),
    );

    // Nothing while idle, and nothing with no receipt — a queued bill has
    // no paper yet, and says nothing rather than something false.
    final printStatus = _receipt != null && _print != PrintState.idle
        ? _PrintStatus(
            state: _print,
            tr: tr,
            bridge: bridge,
            onPrinterSettings: widget.onPrinterSettings,
          )
        : null;

    final actions = <Widget>[
      // Only where a programme runs — and the sale must name itself.
      // Read off the OUTCOME: the Charge session may already be gone, and a
      // fresh one knows nothing about the programme.
      if (o.canAwardPoints && o.loyaltyOffered)
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

    // The end of row 2. On a table's sale: the question the floor is
    // waiting for — "T5 cleared?" — with Cleared as the one primary and Not
    // yet beside it; leaving without an answer means not yet, which never
    // lies about the room. A counter sale asks nothing: a quiet way on.
    final table = o.tableId;
    final label = o.tableLabel;
    final answer = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: _buttonGap,
      runSpacing: Space.sm,
      children: table == null
          ? [
              MadarButton(
                label: tr('charge.new_sale'),
                size: MadarButtonSize.compact,
                variant: MadarButtonVariant.ghost,
                onTap: () => widget.onDone(DoneCardResult.notYet),
              ),
            ]
          : [
              Text.rich(
                key: const ValueKey('done-cleared-q'),
                TextSpan(
                  children: [
                    if (label != null) ...[
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: Text(
                          label,
                          textDirection: TextDirection.ltr,
                          style: MadarType.numLg.copyWith(
                            fontWeight: MadarType.heaviest,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const TextSpan(text: ' '),
                    ],
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
    final buttons = Wrap(
      spacing: _buttonGap,
      runSpacing: Space.sm,
      children: actions,
    );

    return Listener(
      onPointerDown: (_) => _holdOpen(),
      child: Container(
        padding: const EdgeInsetsDirectional.all(Space.card),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: colors.border),
          boxShadow: MadarElevation.floating.shadows(
            colors,
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
        ),
        child: Column(
          // Hugs its content: the card used to stretch to the window.
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: _rowGap,
          children: [
            Row(
              spacing: _rowGap,
              children: [
                MadarGlyphIcon(
                  _queued ? MadarGlyph.half : MadarGlyph.full,
                  size: _discSize,
                  color: colors.brand,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: _lineGap,
                    children: [
                      title,
                      body,
                      // A phone has no room beside the words: the print
                      // state goes under them.
                      if (phone && printStatus != null) printStatus,
                    ],
                  ),
                ),
                if (!phone && printStatus != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _printMaxWidth),
                    child: printStatus,
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
                children: [if (actions.isNotEmpty) buttons, answer],
              )
            else
              Row(
                spacing: _buttonGap,
                children: [
                  Expanded(child: buttons),
                  answer,
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// "Printed" in green with the printer glyph, "Not printed — no printer"
/// in amber (a link when there is somewhere to go), the printer's refusal
/// in red, "Printing…" while the paper is on its way.
class _PrintStatus extends StatelessWidget {
  const _PrintStatus({
    required this.state,
    required this.tr,
    required this.bridge,
    this.onPrinterSettings,
  });

  final PrintState state;
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
    if (text == null) return const SizedBox.shrink();
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
