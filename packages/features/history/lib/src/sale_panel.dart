/// The sale — the settled order opened from the Orders table.
///
/// [SalePanel] is the one body, in the pane beside the table on a wide page
/// and inside [SaleScreen] where it is pushed: a header (the sale, and when,
/// what, who and how it was paid), the lines as rows, the totals under them,
/// what was already given back, and the actions — Reprint, Preview, Add
/// points, and Void and Refund as buttons you can see. They used to live
/// behind a ⋯ tile that scrolled away with the header.
///
/// A REFUND IS NOT A VOID, and the two sheets say so: a void corrects a
/// mistake, the sale is removed as if it never happened; a refund returns
/// money already taken and the sale stands. When one does not apply the
/// button is disabled and the reason is written under it.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_history/src/approval_sheet.dart';
import 'package:feature_history/src/history_provider.dart';
import 'package:feature_history/src/history_strings.dart';
import 'package:feature_history/src/orders_table.dart';
import 'package:feature_history/src/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The void and refund sheets' width cap.
const double _sheetMaxWidth = 520;

/// "19:31 · Dine-in · Sara · Cash" — the facts under a sale's title.
String _saleMeta(MadarBridge bridge, OrderSummaryView o) => [
  MadarFormat.isolate(bridge.formatStamp(rfc3339: o.createdAt)),
  if (o.orderRef case final ref?) ltrIsland(ref),
  orderTypeLabel(bridge, o.orderType),
  ?o.tellerName,
  bridge.paymentMethodLabel(code: o.paymentLabel),
  ?o.customerName,
].join(' · ');

/// Why Void does not apply to [o], in words — or null when it does. The one
/// refusal the till cannot see ahead (a closed till) comes back from the
/// server and lands in the void sheet's banner.
String? _voidBlocked(MadarBridge bridge, OrderSummaryView o) =>
    switch (SaleState.of(o)) {
      SaleState.voided => historyTr(bridge, 'history.void_cannot_voided'),
      SaleState.queued => historyTr(bridge, 'history.void_cannot_queued'),
      SaleState.failed => historyTr(bridge, 'history.void_cannot_failed'),
      null => null,
    };

/// The sale, as a body: fills whatever the host gives it. [onClose] draws a
/// close tile in the pane's header; a pushed [SaleScreen] has its own back.
class SalePanel extends ConsumerWidget {
  /// Creates the panel for [order]; its detail comes from [historyProvider].
  const SalePanel({
    required this.order,
    this.onClose,
    this.header = true,
    super.key,
  });

  /// The selected row.
  final OrderSummaryView order;

  /// Closes the pane.
  final VoidCallback? onClose;

  /// Draw the panel's own header. Off inside [SaleScreen], whose page header
  /// already names the sale.
  final bool header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final detail = ref.watch(historyProvider.select((s) => s.detail));
    final receipt = ref.watch(historyProvider.select((s) => s.receipt));
    final refunds = ref.watch(historyProvider.select((s) => s.refunds));
    final loading = ref.watch(historyProvider.select((s) => s.detailLoading));
    final session = ref.watch(shellProvider.select((s) => s.session));
    final currency = session?.currencyCode ?? '';
    final o = order;
    final state = SaleState.of(o);
    String t(String key) => historyTr(bridge, key);

    Widget note(MadarStatus status, String text) => Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.card),
      child: Row(
        spacing: Space.md,
        children: [
          MadarStatusPill(status),
          Expanded(
            child: Text(
              text,
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.card,
              Space.md,
              Space.md,
              0,
            ),
            child: MadarHeader(
              title: saleTitle(bridge, o),
              subtitle: _saleMeta(bridge, o),
              actions: [
                if (onClose != null)
                  MadarHeaderAction(
                    glyph: MadarGlyph.close,
                    tooltip: t('common.close'),
                    onTap: onClose!,
                  ),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.only(
              top: Space.lg,
              bottom: Space.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                if (!header)
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: Space.card,
                    ),
                    child: Text(
                      _saleMeta(bridge, o),
                      style: MadarType.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                if (state != null)
                  note(orderStatus(bridge, o), state.hint(bridge)),
                // Always on the sale, even beside a state, because this is
                // the screen somebody opens to find out what happened to it.
                if (o.priceFlagged)
                  note(
                    MadarStatus(
                      t('history.price_flagged'),
                      tone: MadarTone.warning,
                      glyph: MadarGlyph.percent,
                    ),
                    t('history.price_flagged_hint'),
                  ),
                if (loading)
                  const Padding(
                    padding: EdgeInsetsDirectional.symmetric(
                      horizontal: Space.card,
                    ),
                    child: SkeletonList(count: 3),
                  )
                else if (detail != null && detail.lines.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const MadarHairline.row(),
                      for (final line in detail.lines) ...[
                        // A combo's items sit indented under it (C12); the
                        // combo's own row carries their total.
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: line.kind == 'combo_part' ? Space.xl : 0,
                          ),
                          child: MadarListRow.bill(
                            title: '${ltrIsland('${line.qty}×')} ${line.name}',
                            meta: _mods(line),
                            minor: line.lineTotalMinor,
                            currency: currency,
                            chevron: false,
                          ),
                        ),
                        const MadarHairline.row(),
                      ],
                    ],
                  ),
                Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: Space.card,
                  ),
                  child: _Totals(
                    order: o,
                    detail: detail,
                    receipt: receipt,
                    currency: currency,
                    bridge: bridge,
                  ),
                ),
                _SaleCustomer(key: ValueKey(o.id), order: o),
                // What has already gone back, before anything is offered
                // about giving more back.
                if (refunds != null && refunds.refundedMinor > 0)
                  _Refunded(refunds: refunds, currency: currency),
              ],
            ),
          ),
        ),
        const MadarHairline(),
        _Actions(order: o, receipt: receipt),
      ],
    );
  }

  static String? _mods(OrderDetailLineView line) {
    final mods = <String>[?line.sizeLabel, ...line.addons, ...line.optionals];
    return mods.isEmpty ? null : mods.join(' · ');
  }
}

/// Who the sale was for, and the way to say so after the fact: pick a
/// customer for a sale already rung, or take them off. Local and offline —
/// the core queues the change behind the sale and answers at once.
class _SaleCustomer extends ConsumerStatefulWidget {
  const _SaleCustomer({required this.order, super.key});

  final OrderSummaryView order;

  @override
  ConsumerState<_SaleCustomer> createState() => _SaleCustomerState();
}

class _SaleCustomerState extends ConsumerState<_SaleCustomer> {
  CustomerView? _read(MadarBridge bridge) {
    try {
      return bridge.orderCustomer(orderId: widget.order.id);
    } on MadarError {
      return null;
    }
  }

  void _set(CustomerView? customer) {
    final bridge = ref.read(bridgeProvider);
    final notifier = ref.read(historyProvider.notifier);
    try {
      bridge.attachCustomer(orderId: widget.order.id, customerId: customer?.id);
      if (customer != null) {
        notifier.showToast(
          bridge.tr(key: 'customers.attached'),
          tone: ChipTone.success,
        );
      }
    } on MadarError catch (e) {
      notifier.surfaceError(e);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    final customer = _read(bridge);
    final may = bridge.can(cap: Cap.customersAttach);
    if (customer == null && !may) return const SizedBox.shrink();
    final phone = customer?.phone ?? customer?.phoneHint;
    return MadarListRow.nav(
      title: bridge.tr(key: 'customers.attach'),
      valueText: customer == null
          ? bridge.tr(key: 'customers.search_hint')
          : customer.isMember
          ? '${customer.name} · ${bridge.tr(key: 'customers.member')}'
          : customer.name,
      meta: phone == null ? null : MadarFormat.ltr(phone),
      // Somebody is on the sale: the row opens their card. Nobody: it picks.
      onTap: customer != null
          ? () => unawaited(showCustomerCard(context, customer))
          : !may
          ? null
          : () => unawaited(
              showMadarSheet<void>(
                context,
                size: SheetSize.hug,
                maxWidth: Responsive.sheetCompactMaxWidth,
                builder: (_) => CustomerSheet(
                  title: bridge.tr(key: 'customers.history_title'),
                  onPicked: _set,
                ),
              ),
            ),
      trailing: may && customer != null
          ? MadarGlyphTile(
              glyph: MadarGlyph.close,
              semanticLabel: bridge.tr(key: 'customers.remove'),
              onTap: () => _set(null),
            )
          : null,
    );
  }
}

/// Subtotal · Discount · Service · Tax · Total · Tip. The detail view has
/// subtotal / discount / tax / total; the receipt projection adds the
/// service charge and the tip, so those lines appear only once it is in
/// hand and only when non-zero. Tax reads "VAT included" under an inclusive
/// policy and sits under the total because it added nothing.
class _Totals extends StatelessWidget {
  const _Totals({
    required this.order,
    required this.detail,
    required this.receipt,
    required this.currency,
    required this.bridge,
  });

  final OrderSummaryView order;
  final OrderDetailView? detail;
  final ReceiptView? receipt;
  final String currency;
  final MadarBridge bridge;

  @override
  Widget build(BuildContext context) {
    String t(String key) => historyTr(bridge, key);
    final subtotal = detail?.subtotalMinor ?? order.subtotalMinor;
    final discount = detail?.discountMinor ?? receipt?.discountMinor ?? 0;
    final tax = detail?.taxMinor ?? order.taxMinor;
    final service = receipt?.serviceChargeMinor ?? 0;
    final tip = receipt?.tipMinor ?? 0;
    // The sale's OWN tax: inclusive or not is read from its figures, and no
    // rate is printed — today's branch rate is not what an old sale paid.
    final inclusive = bridge.saleTaxInclusive(
      subtotalMinor: subtotal,
      discountMinor: discount,
      serviceMinor: service,
      deliveryMinor: receipt?.deliveryFeeMinor ?? 0,
      taxMinor: tax,
      totalMinor: order.totalMinor,
    );
    final voided = order.status == 'voided';
    MadarSummaryLine line(String label, int minor, {bool muted = false}) =>
        MadarSummaryLine(
          label: label,
          minor: minor,
          currency: currency,
          muted: muted,
        );
    final vatLabel = inclusive ? t('history.vat_included') : t('order.tax');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line(t('order.subtotal'), subtotal),
        if (discount > 0)
          MadarSummaryLine(
            label: t('order.discount'),
            minor: -discount,
            currency: currency,
            tone: MadarTone.success,
          ),
        if (service > 0) line(t('history.service'), service),
        if (!inclusive) line(vatLabel, tax),
        MadarSummaryLine(
          label: t('order.total'),
          minor: order.totalMinor,
          currency: currency,
          emphasis: true,
          strike: voided,
        ),
        if (inclusive) line(vatLabel, tax, muted: true),
        if (tip > 0) line(t('history.tip'), tip, muted: true),
      ],
    );
  }
}

/// What has already gone back on this sale: one ledger row per refund, and
/// what is LEFT — the server's arithmetic, not this screen's.
class _Refunded extends ConsumerWidget {
  const _Refunded({required this.refunds, required this.currency});

  final OrderRefundsView refunds;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => historyTr(bridge, key);
    final remaining = refunds.refundableRemainingMinor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.card,
            Space.md,
            Space.card,
            Space.md,
          ),
          child: MadarSectionHeader(text: t('history.refunded')),
        ),
        const MadarHairline.row(),
        for (final r in refunds.refunds) ...[
          MadarListRow.ledger(
            title: bridge.paymentMethodLabel(code: r.method),
            meta: [
              r.issuedByName,
              if (r.queued) t('history.refund_queued'),
            ].where((p) => p.isNotEmpty).join(' · '),
            minor: -r.amountMinor,
            currency: currency,
          ),
          const MadarHairline.row(),
        ],
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.card,
          ),
          child: remaining <= 0
              ? MadarSummaryLine(
                  label: t('history.refund_all'),
                  minor: refunds.refundedMinor,
                  currency: currency,
                  muted: true,
                )
              : MadarSummaryLine(
                  label: t('history.refund_left_label'),
                  minor: remaining,
                  currency: currency,
                ),
        ),
      ],
    );
  }
}

/// Reprint · Preview · Add points, then Void and Refund — visible, each
/// disabled with its reason written under it when it does not apply.
///
/// Reprint needs the receipt projection, which a queued sale does not have
/// yet (it is not on the server); a failed sale never will. Add points is
/// offered on a queued sale too — the award names it by the client key it
/// was rung under — and disappears on its own when the core's 24-hour
/// window closes.
class _Actions extends ConsumerWidget {
  const _Actions({required this.order, required this.receipt});

  final OrderSummaryView order;
  final ReceiptView? receipt;

  Future<void> _void(BuildContext context, WidgetRef ref) async {
    final voided = await showMadarSheet<bool>(
      context,
      size: SheetSize.hug,
      maxWidth: _sheetMaxWidth,
      builder: (_) => _VoidSheet(order: order),
    );
    if (voided ?? false) {
      await ref.read(historyProvider.notifier).reloadAfterVoid();
    }
  }

  Future<void> _refund(BuildContext context, WidgetRef ref) async {
    final refunded = await showMadarSheet<bool>(
      context,
      size: SheetSize.hug,
      maxWidth: _sheetMaxWidth,
      builder: (_) => _RefundSheet(order: order),
    );
    if ((refunded ?? false) && context.mounted) {
      await ref.read(historyProvider.notifier).reloadAfterVoid();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final o = order;
    final state = SaleState.of(o);
    final canReprint = state != SaleState.queued && state != SaleState.failed;
    // A queued sale CAN be previewed even though it cannot be reprinted: the
    // core kept the receipt it printed on the sale's own row, so a teller can
    // look at the receipt they have just handed over with no network at all.
    // Reprint stays out until the sale is real on the server.
    final canPreview = canReprint || state == SaleState.queued;
    final canAward =
        ref.watch(historyProvider.select((s) => s.loyaltyOffered)) &&
        state != SaleState.voided &&
        state != SaleState.failed &&
        bridge.loyaltyAwardWindowOpen(
          orderCreatedAt: o.createdAt,
          now: DateTime.now().toUtc().toIso8601String(),
        );
    String t(String key) => historyTr(bridge, key);
    final voidBlocked = _voidBlocked(bridge, o);
    // Refund shares Void's three states, and adds one: a sale already given
    // back in full has nothing left to refund.
    final refundBlocked =
        voidBlocked ??
        switch (ref.watch(historyProvider.select((s) => s.refunds))) {
          final r? when r.orderId == o.id && r.refundableRemainingMinor <= 0 =>
            t('history.refund_all'),
          _ => null,
        };
    final blocked = {?voidBlocked, ?refundBlocked}.join(' ');

    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          if (canPreview || canAward)
            Row(
              spacing: Space.sm,
              children: [
                if (canReprint)
                  Expanded(
                    child: _ReprintButton(order: o, receipt: receipt),
                  ),
                if (canPreview)
                  Expanded(
                    child: MadarButton(
                      label: t('history.preview_receipt'),
                      glyph: MadarGlyph.receipt,
                      variant: MadarButtonVariant.ghost,
                      size: MadarButtonSize.compact,
                      onTap: () =>
                          unawaited(_previewReceipt(context, ref, o, receipt)),
                    ),
                  ),
                if (canAward)
                  Expanded(
                    child: MadarButton(
                      label: t('loyalty.add_points'),
                      variant: MadarButtonVariant.ghost,
                      size: MadarButtonSize.compact,
                      glyph: MadarGlyph.star,
                      onTap: () => unawaited(
                        showMadarSheet<bool>(
                          context,
                          builder: (_) => LoyaltyAwardSheet(
                            // A queued sale has no server id yet — it is
                            // known by the client key it was rung under.
                            orderId: o.queued ? null : o.id,
                            orderKey: o.queued ? o.id : null,
                            orderCreatedAt: o.createdAt,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          Row(
            spacing: Space.sm,
            children: [
              Expanded(
                child: MadarButton(
                  label: t('history.refund_sale'),
                  glyph: MadarGlyph.receipt,
                  variant: MadarButtonVariant.secondary,
                  size: MadarButtonSize.compact,
                  enabled: refundBlocked == null,
                  onTap: () => unawaited(_refund(context, ref)),
                ),
              ),
              Expanded(
                child: MadarButton(
                  label: t('history.void_sale'),
                  glyph: MadarGlyph.trash,
                  variant: MadarButtonVariant.danger,
                  size: MadarButtonSize.compact,
                  enabled: voidBlocked == null,
                  onTap: () => unawaited(_void(context, ref)),
                ),
              ),
            ],
          ),
          if (blocked.isNotEmpty)
            Text(
              blocked,
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// The receipt projection is fetched with the sale's detail; if that fetch
/// lost (a first tap before it landed, or an order never seen online) ask
/// once more here and say so if the core cannot. Shared by the Reprint
/// button's long-press and the View glyph beside it, so there is exactly
/// one place this screen fetches a receipt for READING.
Future<ReceiptView?> _resolveReceipt(
  WidgetRef ref,
  OrderSummaryView order,
  ReceiptView? cached,
) async {
  if (cached != null) return cached;
  try {
    return await ref.read(bridgeProvider).orderReceiptView(orderId: order.id);
  } on MadarError catch (e) {
    ref.read(historyProvider.notifier).surfaceError(e);
    return null;
  }
}

Future<void> _previewReceipt(
  BuildContext context,
  WidgetRef ref,
  OrderSummaryView order,
  ReceiptView? cached,
) async {
  final view = await _resolveReceipt(ref, order, cached);
  if (view == null || !context.mounted) return;
  await showMadarSheet<void>(
    context,
    size: SheetSize.large,
    builder: (_) => ReceiptSheet(receipt: view),
  );
}

/// Reprint's SINGLE TAP: render the cached receipt in the core and stream it
/// to the configured printer — `kickDrawer: false`, a reprint never pops the
/// till again. LONG PRESS defers to the shared preview ([_previewReceipt]).
/// Local `_busy` because this button has no screen of its own to hold a
/// richer print-state machine, unlike the checkout session it mirrors.
class _ReprintButton extends ConsumerStatefulWidget {
  const _ReprintButton({required this.order, required this.receipt});

  final OrderSummaryView order;
  final ReceiptView? receipt;

  @override
  ConsumerState<_ReprintButton> createState() => _ReprintButtonState();
}

class _ReprintButtonState extends ConsumerState<_ReprintButton> {
  bool _busy = false;

  Future<void> _printNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final view = await _resolveReceipt(ref, widget.order, widget.receipt);
    if (view == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final outcome = await printReceiptView(
      ref.read(bridgeProvider),
      ref.read(printerServiceProvider),
      view,
      kickDrawer: false,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final bridge = ref.read(bridgeProvider);
    String t(String key) => historyTr(bridge, key);
    final feedback = switch (outcome) {
      PrintState.printed => (
        t('receipt.printed'),
        ChipTone.success,
        'checkmark.circle',
      ),
      PrintState.noPrinter => (
        t('receipt.no_printer'),
        ChipTone.warning,
        'exclamationmark.triangle',
      ),
      PrintState.failed => (
        t('receipt.print_failed'),
        ChipTone.danger,
        'exclamationmark.triangle',
      ),
      PrintState.idle || PrintState.printing => null,
    };
    if (feedback != null) {
      ref
          .read(historyProvider.notifier)
          .showToast(feedback.$1, tone: feedback.$2, icon: feedback.$3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    String t(String key) => historyTr(bridge, key);
    return GestureDetector(
      onLongPress: _busy
          ? null
          : () {
              MadarHaptics.impact();
              unawaited(
                _previewReceipt(context, ref, widget.order, widget.receipt),
              );
            },
      child: MadarButton(
        label: t('history.reprint'),
        variant: MadarButtonVariant.secondary,
        glyph: MadarGlyph.printer,
        loading: _busy,
        onTap: () => unawaited(_printNow()),
      ),
    );
  }
}

// ── The pushed sale screen ─────────────────────────────────────────────────

/// The sale pushed over the table where there is no room beside it (a phone,
/// an iPad in portrait). Reads the selection from [historyProvider].
class SaleScreen extends ConsumerWidget {
  /// Creates the sale screen.
  const SaleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final selected = ref.watch(historyProvider.select((s) => s.selected));
    if (selected == null) {
      return MadarPageScaffold(
        title: historyTr(bridge, 'history.title'),
        width: MadarContentWidth.form,
        body: EmptyState(
          icon: 'receipt',
          title: historyTr(bridge, 'history.select_prompt'),
        ),
      );
    }
    return MadarPageScaffold(
      title: saleTitle(bridge, selected),
      width: MadarContentWidth.form,
      body: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: Space.lg),
        child: MadarCard(
          padding: EdgeInsetsDirectional.zero,
          child: SalePanel(order: selected, header: false),
        ),
      ),
    );
  }
}

// ── The void sheet ──────────────────────────────────────────────────────────

/// The void form's state (reason / busy / error). No restock choice: a void
/// always puts the stock back (the core and the server both hold that rule).
class _VoidFormState {
  const _VoidFormState({this.reason, this.busy = false, this.error});

  /// Null until chosen — a void's reason is the teller's, never a default
  /// the report then attributes to them.
  final String? reason;
  final bool busy;
  final UiText? error;

  static const Object _unset = Object();

  _VoidFormState copyWith({
    String? reason,
    bool? busy,
    Object? error = _unset,
  }) {
    return _VoidFormState(
      reason: reason ?? this.reason,
      busy: busy ?? this.busy,
      error: error == _unset ? this.error : error as UiText?,
    );
  }
}

class _VoidFormNotifier extends Notifier<_VoidFormState> {
  bool _alive = true;

  @override
  _VoidFormState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    return const _VoidFormState();
  }

  void selectReason(String reason) =>
      state = state.copyWith(reason: reason, error: null);

  /// Void the sale — true on success (the sheet pops). A void moves the
  /// till stats, so the shell refreshes here; a refusal (the till is
  /// closed, the order is not this branch's) lands in [_VoidFormState.error]
  /// in the server's words — the till cannot pre-check them.
  Future<bool> confirm({
    required String orderId,
    required String note,
    required Future<ApprovalView?> Function(String reason) askManager,
  }) async {
    final reason = state.reason;
    if (reason == null) {
      state = state.copyWith(
        error: const UiText.key('history.reason_required'),
      );
      return false;
    }
    final bridge = ref.read(bridgeProvider);
    // Phase 5: the core decides (whose sale, how old, the person's limits).
    final decision = bridge.decideOrderAct(
      capKey: 'orders.void',
      orderId: orderId,
    );
    ApprovalView? approval;
    if (decision.outcome == 'deny') {
      state = state.copyWith(error: UiText.raw(decision.reason));
      return false;
    }
    if (decision.outcome == 'needs_approval') {
      approval = await askManager(decision.reason);
      if (approval == null) return false;
    }
    state = state.copyWith(busy: true, error: null);
    try {
      await bridge.voidOrderApproved(
        orderId: orderId,
        reason: reason,
        note: note.isEmpty ? null : note,
        restoreInventory: true,
        approval: approval,
      );
      ref.read(shellProvider.notifier).refresh();
      ref.read(drawerTickProvider.notifier).bump();
      return true;
    } on MadarError catch (e) {
      if (e is MadarError_Unauthenticated &&
          ref.read(shellProvider).session != null) {
        ref.read(reauthRequestProvider.notifier).request();
      }
      if (_alive) {
        state = state.copyWith(busy: false, error: UiText.error(e));
      }
      return false;
    }
  }
}

final NotifierProvider<_VoidFormNotifier, _VoidFormState> _voidFormProvider =
    NotifierProvider.autoDispose<_VoidFormNotifier, _VoidFormState>(
      _VoidFormNotifier.new,
    );

// ── The refund sheet ────────────────────────────────────────────────────────

/// How much goes back, by what route, and why. Pops `true` on success.
///
/// The amount defaults to the whole sale because most refunds are the whole
/// sale, and it is editable because the ones that are not are the ones worth
/// getting right. It is capped at the total: the server refuses a cumulative
/// refund above what was taken, and a till that let someone type more would be
/// queueing a failure the customer has already been promised.
///
/// No restock toggle, unlike a void. Returning money is not getting the food
/// back — the kitchen made it and it left the building. The items the money
/// is for are picked here; the server keeps their stock deducted and logs it
/// as waste (reason `refund`). Picking none is a money-only refund.
class _RefundSheet extends ConsumerStatefulWidget {
  const _RefundSheet({required this.order});

  final OrderSummaryView order;

  @override
  ConsumerState<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends ConsumerState<_RefundSheet> {
  static const List<(String, String)> _reasons = [
    ('customer', 'history.refund_reason_customer'),
    ('wrong_order', 'history.refund_reason_wrong'),
    ('quality', 'history.refund_reason_quality'),
    ('overcharged', 'history.refund_reason_overcharged'),
    ('other', 'history.refund_reason_other'),
  ];

  late int _amountMinor = widget.order.totalMinor;
  final TextEditingController _note = TextEditingController();

  /// Null until chosen: no silent "customer asked" on the books.
  String? _reason;

  /// How the money may go back (the core's plan), and the chosen code. The
  /// sale's own method is preselected only when the server accepts it — a
  /// split or an aggregator sale must be chosen, never sent as `mixed`.
  RefundMethodPlan? _plan;
  String? _method;
  bool _busy = false;
  UiText? _error;

  /// What the SERVER says is still refundable, once earlier refunds are
  /// counted. Null while it loads, or when nothing could be read — the
  /// endpoint checks again anyway, so the sale's total is a safe start.
  int? _remainingMinor;

  int get _cap => _remainingMinor ?? widget.order.totalMinor;

  /// The sale's lines (null while loading or when they cannot be read — the
  /// refund then goes without lines) and how many units of each are picked.
  List<RefundableLineView>? _lines;
  final Map<String, int> _picked = {};

  Future<void> _loadLines() async {
    try {
      final lines = await ref
          .read(bridgeProvider)
          .refundableLines(orderId: widget.order.id);
      if (mounted) setState(() => _lines = lines);
    } on MadarError catch (_) {
      // Offline and never opened: a money-only refund still works.
    }
  }

  void _pick(RefundableLineView line, int qty) {
    setState(() {
      if (qty <= 0) {
        _picked.remove(line.orderItemId);
      } else {
        _picked[line.orderItemId] = qty;
      }
      // The amount follows the picked items, within what is left.
      if (_picked.isNotEmpty) {
        var sum = 0;
        for (final l in _lines ?? const <RefundableLineView>[]) {
          sum += l.unitShareMinor * (_picked[l.orderItemId] ?? 0);
        }
        _amountMinor = sum > _cap ? _cap : sum;
      }
      _error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    try {
      _plan = ref
          .read(bridgeProvider)
          .refundMethodPlan(
            orderPaymentMethod: widget.order.paymentLabel,
            orderCreatedAt: widget.order.createdAt,
          );
      _method = _plan?.defaultCode;
    } on MadarError catch (_) {
      _plan = null;
    }
    // The panel usually has this already; asking again costs a cached read
    // and covers the sheet being opened from somewhere that did not.
    final prior = ref.read(historyProvider).refunds;
    if (prior != null && prior.orderId == widget.order.id) {
      _remainingMinor = prior.refundableRemainingMinor;
      _amountMinor = prior.refundableRemainingMinor;
    }
    unawaited(_loadLines());
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final bridge = ref.read(bridgeProvider);
    final minor = _amountMinor;
    if (minor <= 0) return;
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = const UiText.key('history.reason_required'));
      return;
    }
    final method = _method;
    if (method == null) {
      setState(() => _error = const UiText.key('history.refund_method_pick'));
      return;
    }
    // Against what is LEFT, not against the sale: a second refund on a sale
    // already half given back is over by half, and the server refuses it.
    if (minor > _cap) {
      setState(() => _error = const UiText.key('history.refund_over'));
      return;
    }
    final decision = bridge.decideOrderAct(
      capKey: 'refunds.create',
      orderId: widget.order.id,
      amountMinor: minor,
    );
    ApprovalView? approval;
    if (decision.outcome == 'deny') {
      setState(() => _error = UiText.raw(decision.reason));
      return;
    }
    if (decision.outcome == 'needs_approval') {
      approval = await askManager(
        context,
        ref,
        reason: decision.reason,
        capKey: 'refunds.create',
        orderId: widget.order.id,
        amountMinor: minor,
      );
      if (approval == null) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await bridge.refundOrderLinesApproved(
        approval: approval,
        lines: [
          for (final e in _picked.entries)
            RefundLinePick(orderItemId: e.key, qty: e.value),
        ],
        orderId: widget.order.id,
        amountMinor: minor,
        // A method the server accepts: back the way it came when it can,
        // otherwise the one the teller chose.
        method: method,
        reason: reason,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      ref.read(shellProvider.notifier).refresh();
      ref.read(drawerTickProvider.notifier).bump();
      if (mounted) Navigator.of(context).maybePop(true);
    } on MadarError catch (e) {
      if (e is MadarError_Unauthenticated &&
          ref.read(shellProvider).session != null) {
        ref.read(reauthRequestProvider.notifier).request();
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _error = UiText.error(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final o = widget.order;
    String t(String key) => historyTr(bridge, key);
    String money(int minor) =>
        bridge.formatMoney(minor: minor, currency: currency, signed: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.lg,
              children: [
                MadarHeader(
                  title: t('history.refund_sale'),
                  subtitle: [
                    saleTitle(bridge, o),
                    money(o.totalMinor),
                    // What is left, whenever it differs from the sale — the
                    // figure this sheet is bounded by.
                    if (_remainingMinor case final left?
                        when left != o.totalMinor && left <= 0)
                      t('history.refund_all'),
                    if (_remainingMinor case final left?
                        when left != o.totalMinor && left > 0)
                      t(
                        'history.refund_left',
                      ).replaceAll('{amount}', money(left)),
                  ].join(' · '),
                  actions: [
                    MadarHeaderAction(
                      glyph: MadarGlyph.close,
                      tooltip: t('common.close'),
                      onTap: () => Navigator.of(context).maybePop(false),
                    ),
                  ],
                ),
                Text(
                  t('history.refund_teach'),
                  style: MadarType.bodySm.copyWith(color: colors.textSecondary),
                ),
                if (_lines case final lines? when lines.isNotEmpty) ...[
                  MadarSectionHeader(text: t('history.refund_items')),
                  Text(
                    t('history.refund_items_hint'),
                    style: MadarType.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  for (final line in lines)
                    Row(
                      spacing: Space.sm,
                      children: [
                        Expanded(
                          child: Text(
                            [
                              line.name,
                              ?line.sizeLabel,
                              MadarFormat.ltr('×${line.soldQty}'),
                            ].join(' · '),
                            style: MadarType.body.copyWith(
                              color: line.refundableQty > 0
                                  ? colors.textPrimary
                                  : colors.textMuted,
                            ),
                          ),
                        ),
                        MadarStepper(
                          value: _picked[line.orderItemId] ?? 0,
                          max: line.refundableQty,
                          onChanged: _busy ? (_) {} : (v) => _pick(line, v),
                        ),
                      ],
                    ),
                ],
                MadarSectionHeader(text: t('history.refund_amount')),
                MadarAmountField(
                  amountMinor: _amountMinor,
                  onAmountMinor: (v) => setState(() {
                    _amountMinor = v;
                    _error = null;
                  }),
                  currencyCode: currency,
                ),
                // An old sale's refund still leaves TODAY's drawer; say so
                // before the money moves.
                if (_plan?.crossesTill ?? false)
                  NoticeBanner(
                    text: t('history.refund_other_shift'),
                    icon: 'exclamationmark.triangle',
                  ),
                MadarSectionHeader(text: t('history.refund_method')),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final option
                        in _plan?.options ?? const <PaymentMethodChoice>[])
                      MadarChip(
                        label: option.label,
                        selected: _method == option.code,
                        enabled: !_busy,
                        onTap: () => setState(() {
                          _method = option.code;
                          _error = null;
                        }),
                      ),
                  ],
                ),
                MadarSectionHeader(text: t('history.refund_reason')),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final (key, label) in _reasons)
                      MadarChip(
                        label: t(label),
                        selected: _reason == key,
                        enabled: !_busy,
                        onTap: () => setState(() {
                          _reason = key;
                          _error = null;
                        }),
                      ),
                  ],
                ),
                MadarField(
                  controller: _note,
                  placeholder: t('void.note'),
                  kind: MadarFieldKind.note,
                  glyph: MadarGlyph.note,
                  enabled: !_busy,
                ),
                if (_error case final error?)
                  NoticeBanner(
                    text: error.of(ref.bridge),
                    tone: ChipTone.danger,
                    icon: 'exclamationmark.triangle',
                  ),
                Row(
                  spacing: Space.md,
                  children: [
                    Expanded(
                      child: MadarButton(
                        label: t('void.cancel'),
                        variant: MadarButtonVariant.secondary,
                        enabled: !_busy,
                        onTap: () => Navigator.of(context).maybePop(false),
                      ),
                    ),
                    Expanded(
                      child: MadarButton(
                        label: t('history.refund_confirm'),
                        glyph: MadarGlyph.receipt,
                        loading: _busy,
                        onTap: () => unawaited(_confirm()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Reason chips, an optional note, one danger CTA. The stock goes back.
/// Pops `true` after a successful void.
class _VoidSheet extends ConsumerStatefulWidget {
  const _VoidSheet({required this.order});

  final OrderSummaryView order;

  @override
  ConsumerState<_VoidSheet> createState() => _VoidSheetState();
}

class _VoidSheetState extends ConsumerState<_VoidSheet> {
  final TextEditingController _note = TextEditingController();

  static const List<(String, String)> _reasons = [
    ('mistake', 'void.reason_mistake'),
    ('customer', 'void.reason_customer'),
    ('quality', 'void.reason_quality'),
    ('other', 'void.reason_other'),
  ];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final ok = await ref
        .read(_voidFormProvider.notifier)
        .confirm(
          orderId: widget.order.id,
          note: _note.text.trim(),
          askManager: (why) => askManager(
            context,
            ref,
            reason: why,
            capKey: 'orders.void',
            orderId: widget.order.id,
          ),
        );
    if (ok && mounted) await Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final form = ref.watch(_voidFormProvider);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final o = widget.order;
    String t(String key) => historyTr(bridge, key);
    String money(int minor) =>
        bridge.formatMoney(minor: minor, currency: currency, signed: false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.lg,
              children: [
                MadarHeader(
                  title: t('void.title'),
                  subtitle: '${saleTitle(bridge, o)} · ${money(o.totalMinor)}',
                  actions: [
                    MadarHeaderAction(
                      glyph: MadarGlyph.close,
                      tooltip: t('common.close'),
                      onTap: () => Navigator.of(context).maybePop(false),
                    ),
                  ],
                ),
                Text(
                  t('history.void_teach'),
                  style: MadarType.bodySm.copyWith(color: colors.textSecondary),
                ),
                MadarSectionHeader(text: t('void.reason')),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final (key, label) in _reasons)
                      MadarChip(
                        label: t(label),
                        selected: form.reason == key,
                        enabled: !form.busy,
                        onTap: () => ref
                            .read(_voidFormProvider.notifier)
                            .selectReason(key),
                      ),
                  ],
                ),
                MadarField(
                  controller: _note,
                  placeholder: t('void.note'),
                  kind: MadarFieldKind.note,
                  glyph: MadarGlyph.note,
                  enabled: !form.busy,
                ),
                Text(
                  t('history.void_stock'),
                  style: MadarType.bodySm.copyWith(color: colors.textSecondary),
                ),
                if (form.error case final error?)
                  NoticeBanner(
                    text: error.of(ref.bridge),
                    tone: ChipTone.danger,
                    icon: 'exclamationmark.triangle',
                  ),
                Row(
                  spacing: Space.md,
                  children: [
                    Expanded(
                      child: MadarButton(
                        label: t('void.cancel'),
                        variant: MadarButtonVariant.secondary,
                        enabled: !form.busy,
                        onTap: () => Navigator.of(context).maybePop(false),
                      ),
                    ),
                    Expanded(
                      child: MadarButton(
                        label: t('void.confirm'),
                        variant: MadarButtonVariant.danger,
                        glyph: MadarGlyph.trash,
                        loading: form.busy,
                        onTap: () => unawaited(_confirm()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
