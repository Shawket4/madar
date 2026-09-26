part of 'done_card.dart';

/// The page's state mark: the card's settle mark and queued clock, at the
/// size a page gives them.
const double _pageMarkSize = 64;

/// Present Done as a PAGE of the screen's panel (the Sell screen's Fast
/// mode): it replaces the menu beside the cart, as Charge did, and "Back to
/// menu", New sale, Cleared or Not yet give the menu back. Dismissing it
/// means "not yet", as it does for the card.
///
/// With no [MadarPanelHost] above [context] this is [showDoneCard]: the
/// standard layout keeps the card.
Future<DoneCardResult> showDonePage(
  BuildContext context,
  ChargeOutcome outcome, {
  VoidCallback? onPrinterSettings,
}) async {
  final paged = MadarPanelHost.maybeOf(context)?.present<DoneCardResult>(
    context,
    builder: (pageContext) => DonePage(
      outcome: outcome,
      onPrinterSettings: onPrinterSettings,
      onDone: (r) => MadarSheet.close(pageContext, r),
    ),
  );
  if (paged == null) {
    return await showDoneCard(
      context,
      outcome,
      onPrinterSettings: onPrinterSettings,
    );
  }
  return await paged ?? DoneCardResult.notYet;
}

/// Done, as a page that fills the panel — the "Done" board's content with
/// room to breathe.
///
/// The top: the state mark, "Sale #1042" (or "Queued · #8f2a4c1e"), the
/// amount, the tender and the change ("· Will send when back online" while
/// queued), and "Printed" in green once the paper is out. Under it Add
/// points and Reprint. At the foot, where Charge's bar was: "T5 cleared?"
/// with Cleared / Not yet on a table's sale, "New sale" on a counter's.
///
/// The same view model as [DoneCard] ([_DoneSale]): the same print state,
/// queued re-check, auto-dismiss and calls. Only the drawing differs.
class DonePage extends ConsumerStatefulWidget {
  const DonePage({
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
  ConsumerState<DonePage> createState() => _DonePageState();
}

class _DonePageState extends ConsumerState<DonePage> with _DoneSale<DonePage> {
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

    // "Sale #1042", or "Queued · #8f2a4c1e" with the reference quieter.
    final headline = Text.rich(
      key: const ValueKey('done-headline'),
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
              _saleRef,
              textDirection: TextDirection.ltr,
              style: MadarType.moneyLg.copyWith(
                color: _queued ? colors.textSecondary : colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      style: MadarType.h2.copyWith(color: colors.textPrimary),
    );

    // The tender and the change; for a queued sale the honest sentence about
    // where it is, and any word the core had about points or staff drinks.
    final detail = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: o.methodLabel),
          if (o.isCash && o.changeMinor > 0) ...[
            TextSpan(text: ' · ${tr('charge.change_short')} '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: MoneyText(
                o.changeMinor,
                currency: o.currency,
                style: MadarType.numMd,
                color: colors.textPrimary,
              ),
            ),
          ],
          if (_queued) TextSpan(text: ' · ${tr('charge.will_send')}'),
          if (_receipt?.loyaltyNotice case final notice?)
            TextSpan(text: '\n$notice'),
          if (_staffNotice case final notice?) TextSpan(text: '\n$notice'),
        ],
      ),
      style: MadarType.body.copyWith(color: colors.textSecondary),
    );

    final status = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.lg,
      children: [
        // The card's marks: the settle mark strikes its check once; a sale
        // parked for the network gets the living amber clock.
        SizedBox.square(
          dimension: _pageMarkSize,
          child: _queued
              ? const QueuedMark(size: _pageMarkSize)
              : const SettleMark(size: _pageMarkSize),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.sm,
            children: [
              headline,
              MoneyText(
                o.amountMinor,
                currency: o.currency,
                style: MadarType.moneyDisplay,
                color: colors.textPrimary,
              ),
              detail,
            ],
          ),
        ),
        _PrintStatus(
          state: _print,
          hasReceipt: _receipt != null,
          tr: tr,
          bridge: bridge,
          onPrinterSettings: widget.onPrinterSettings,
        ),
      ],
    );

    final actions = <Widget>[
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
    final Widget foot;
    if (table != null) {
      // The answer the floor is waiting for. Not yet (or leaving the page)
      // keeps the table waiting for a bus: the default never lies about
      // the room.
      final label = o.tableLabel;
      foot = Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: Text.rich(
              label == null
                  ? TextSpan(text: bridge.tr(key: 'tables.clear_ask_generic'))
                  : TextSpan(
                      children: [
                        TextSpan(
                          text: label,
                          style: MadarType.numLg.copyWith(
                            fontWeight: MadarType.heaviest,
                          ),
                        ),
                        TextSpan(text: ' ${tr('charge.cleared_q')}'),
                      ],
                    ),
              style: MadarType.title.copyWith(color: colors.textPrimary),
            ),
          ),
          MadarButton(
            key: const ValueKey('done-cleared'),
            label: tr('charge.cleared'),
            glyph: MadarGlyph.check,
            loading: _clearing,
            onTap: () => unawaited(_clear(table)),
          ),
          MadarButton(
            key: const ValueKey('done-not-yet'),
            label: tr('charge.not_yet'),
            variant: MadarButtonVariant.ghost,
            onTap: () => _finish(DoneCardResult.notYet),
          ),
        ],
      );
    } else {
      foot = MadarButton(
        key: const ValueKey('done-new-sale'),
        label: tr('charge.new_sale'),
        glyph: MadarGlyph.plus,
        onTap: () => _finish(DoneCardResult.notYet),
      );
    }

    // A touch anywhere on the page holds it, as a touch on the card does.
    return Listener(
      key: const ValueKey('done-page'),
      onPointerDown: (_) => _holdOpen(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.all(Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.xl,
                children: [
                  status,
                  if (_clearError case final err?)
                    NoticeBanner(
                      text: err,
                      tone: ChipTone.danger,
                      icon: 'exclamationmark.circle',
                    ),
                  if (actions.isNotEmpty)
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: actions,
                    ),
                ],
              ),
            ),
          ),
          const MadarHairline(),
          Padding(
            padding: const EdgeInsetsDirectional.all(Space.xl),
            child: foot,
          ),
        ],
      ),
    );
  }
}
