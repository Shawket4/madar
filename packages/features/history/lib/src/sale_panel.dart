/// The sale — the settled order opened from the Orders list.
///
/// [SalePanel] is the one body: header (number, time, origin, teller, how
/// it was paid), the lines, the money ending in the total, then Reprint and
/// Add points. On a tablet it fills the card beside the list; on a phone
/// [SaleScreen] pushes it full-screen with the same content.
///
/// A REFUND IS NOT A VOID, and this is where the till says so. A void
/// corrects a mistake — the sale is removed as if it never happened. A
/// refund returns money already taken and the sale stands. Both are drawn
/// now — the core grew `refundOrder`, so the sentence explaining the refund
/// this screen could not do has been replaced by the refund itself.
/// Void lives in the ⋯ sheet, which explains what it does, says when it
/// cannot apply, and names the refund it is not — so a teller does not
/// reach for the wrong correction.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_history/src/history_provider.dart';
import 'package:feature_history/src/history_strings.dart';
import 'package:feature_history/src/widgets.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// A line's height and its quantity column (canvas: 40 / 32).
const double _lineHeight = 40;
const double _qtyColWidth = 32;

/// A totals row (canvas: 30).
const double _totalsRowHeight = 30;

/// The ⋯ and void sheets' width cap.
const double _sheetMaxWidth = 520;

/// Restock switch track (44×26) and thumb (20) — tokens-only stand-in for
/// the material Switch, as on the old void overlay.
const double _switchTrackWidth = 44;
const double _switchTrackHeight = 26;
const double _switchThumb = 20;

/// The sale, as a body: fills whatever the host gives it.
class SalePanel extends ConsumerWidget {
  /// Creates the panel for [order]; its detail comes from [historyProvider].
  const SalePanel({required this.order, super.key});

  /// The selected row.
  final OrderSummaryView order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final detail = ref.watch(historyProvider.select((s) => s.detail));
    final receipt = ref.watch(historyProvider.select((s) => s.receipt));
    final loading = ref.watch(historyProvider.select((s) => s.detailLoading));
    final session = ref.watch(shellProvider.select((s) => s.session));
    final currency = session?.currencyCode ?? '';
    final o = order;
    final state = SaleState.of(o);
    final phone = context.isPhone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(Space.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                // The phone's header carries the number; here it is the card's
                // own title beside ⋯.
                if (!phone) _PanelTitle(order: o, bridge: bridge),
                _MetaLine(order: o, bridge: bridge, forPhone: phone),
                if (state != null)
                  Row(
                    spacing: Space.md,
                    children: [
                      SaleStateTag(state: state, bridge: bridge),
                      Expanded(
                        child: Text(
                          state.hint(bridge),
                          style: MadarType.bodySm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (loading)
                  const SkeletonList(count: 3)
                else if (detail != null && detail.lines.isNotEmpty)
                  Column(
                    children: [
                      for (final line in detail.lines)
                        _LineRow(line: line, currency: currency),
                    ],
                  ),
                const MadarHairline(),
                _Totals(
                  order: o,
                  detail: detail,
                  receipt: receipt,
                  session: session,
                  currency: currency,
                  bridge: bridge,
                ),
              ],
            ),
          ),
        ),
        _Actions(order: o, receipt: receipt),
      ],
    );
  }
}

/// "Sale #1042" with ⋯ at the end.
class _PanelTitle extends ConsumerWidget {
  const _PanelTitle({required this.order, required this.bridge});

  final OrderSummaryView order;
  final MadarBridge bridge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    return Row(
      spacing: Space.md,
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${historyTr(bridge, 'history.sale')} '),
                if (order.orderNumber case final n?)
                  TextSpan(
                    text: ltrIsland('#$n'),
                    style: MadarType.moneyLg.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
        ),
        MoreTile(order: order),
      ],
    );
  }
}

/// The ⋯ tile: opens the sheet that holds Void and says what it is not.
class MoreTile extends ConsumerWidget {
  /// Creates the ⋯ tile for [order].
  const MoreTile({required this.order, super.key});

  /// The sale the sheet is about.
  final OrderSummaryView order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    return MadarGlyphTile(
      glyph: MadarGlyph.more,
      semanticLabel: historyTr(bridge, 'history.more'),
      onTap: () => unawaited(_openMore(context, ref, order)),
    );
  }

  Future<void> _openMore(
    BuildContext context,
    WidgetRef ref,
    OrderSummaryView order,
  ) async {
    final choice = await showMadarSheet<_MoreChoice>(
      context,
      size: SheetSize.hug,
      maxWidth: _sheetMaxWidth,
      builder: (_) => _MoreSheet(order: order),
    );
    if (choice == null || !context.mounted) return;
    if (choice == _MoreChoice.refundSale) {
      final refunded = await showMadarSheet<bool>(
        context,
        size: SheetSize.hug,
        maxWidth: _sheetMaxWidth,
        builder: (_) => _RefundSheet(order: order),
      );
      if ((refunded ?? false) && context.mounted) {
        await ref.read(historyProvider.notifier).reloadAfterVoid();
      }
      return;
    }
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
}

/// What has already gone back on this sale.
///
/// Drawn before the actions, not after: a teller about to give money back
/// needs to know what was given back already, and the number that matters is
/// what is LEFT, which is the server's arithmetic rather than this screen's.
class _RefundedBlock extends StatelessWidget {
  const _RefundedBlock({
    required this.refunds,
    required this.currency,
    required this.t,
  });

  final OrderRefundsView refunds;
  final String currency;
  final String Function(String) t;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final remaining = refunds.refundableRemainingMinor;
    return Container(
      padding: const EdgeInsetsDirectional.all(Space.md),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          Row(
            spacing: Space.sm,
            children: [
              Expanded(
                child: Text(
                  t('history.refunded'),
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
              ),
              Text(
                '− ${Money.format(refunds.refundedMinor, currency: currency)}',
                style: MadarType.money.copyWith(color: colors.danger),
              ),
            ],
          ),
          for (final r in refunds.refunds)
            Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: Text(
                    [
                      r.issuedByName,
                      r.method,
                      if (r.queued) t('history.refund_queued'),
                    ].where((p) => p.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.bodySm.copyWith(
                      color: r.queued ? colors.warning : colors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  Money.format(r.amountMinor, currency: currency),
                  style: MadarType.num.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          Text(
            remaining <= 0
                ? t('history.refund_all')
                : t('history.refund_left').replaceAll(
                    '{amount}',
                    Money.format(remaining, currency: currency),
                  ),
            style: MadarType.bodySm.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// "19:31 · dine-in · Sara · Cash · Omar". On the phone the number is in
/// the header, so the time leads here as well.
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.order,
    required this.bridge,
    required this.forPhone,
  });

  final OrderSummaryView order;
  final MadarBridge bridge;
  final bool forPhone;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final o = order;
    final parts = <String>[
      ltrIsland(
        bridge.formatTime(rfc3339: o.createdAt, style: TimeStyle.dateTime),
      ),
      if (o.orderRef case final ref?) ltrIsland(ref),
      orderTypeLabel(bridge, o.orderType),
      ?o.tellerName,
      o.paymentLabel,
      ?o.customerName,
    ];
    return Text(
      parts.join(' · '),
      style: (forPhone ? MadarType.body : MadarType.bodySm).copyWith(
        color: colors.textSecondary,
      ),
    );
  }
}

/// One line: "2×" mono in its column, the name, its choices under it, the
/// line total at the end.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.currency});

  final OrderDetailLineView line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final mods = <String>[?line.sizeLabel, ...line.addons, ...line.optionals];
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _lineHeight),
      child: Row(
        spacing: Space.md,
        children: [
          SizedBox(
            width: _qtyColWidth,
            child: Text(
              '${line.qty}×',
              textDirection: TextDirection.ltr,
              style: MadarType.numMd.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
                if (mods.isNotEmpty)
                  Text(
                    mods.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          MoneyText(
            line.lineTotalMinor,
            currency: currency,
            style: MadarType.money.copyWith(fontSize: 16),
            color: colors.textPrimary,
          ),
        ],
      ),
    );
  }
}

/// Subtotal · Discount · Service · Total · VAT · Tip. The detail view has
/// subtotal / discount / tax / total; the receipt projection adds the
/// service charge and the tip, so those rows appear only once it is in
/// hand and only when non-zero. Tax reads "VAT included" under an
/// inclusive policy — the same words Charge uses — and sits under the total
/// because it added nothing; otherwise it is a line above the total.
class _Totals extends StatelessWidget {
  const _Totals({
    required this.order,
    required this.detail,
    required this.receipt,
    required this.session,
    required this.currency,
    required this.bridge,
  });

  final OrderSummaryView order;
  final OrderDetailView? detail;
  final ReceiptView? receipt;
  final SessionSnapshot? session;
  final String currency;
  final MadarBridge bridge;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    String t(String key) => historyTr(bridge, key);
    final subtotal = detail?.subtotalMinor ?? order.subtotalMinor;
    final discount = detail?.discountMinor ?? receipt?.discountMinor ?? 0;
    final tax = detail?.taxMinor ?? order.taxMinor;
    final service = receipt?.serviceChargeMinor ?? 0;
    final tip = receipt?.tipMinor ?? 0;
    final inclusive = session?.taxInclusive ?? false;
    final rate = session?.taxRate ?? 0;
    final pct = rate > 0 ? ' ${ltrIsland('${(rate * 100).round()}%')}' : '';
    final voided = order.status == 'voided';

    Widget row(
      String label,
      int minor, {
      bool muted = false,
      bool negative = false,
      bool hero = false,
    }) {
      final fg = muted ? colors.textMuted : colors.textPrimary;
      return SizedBox(
        height: hero ? _lineHeight : _totalsRowHeight,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: (hero ? MadarType.h3 : MadarType.body).copyWith(
                  color: fg,
                ),
              ),
            ),
            Text(
              '${negative ? '− ' : ''}${Money.format(minor, currency: currency)}',
              textDirection: TextDirection.ltr,
              style: (hero ? MadarType.moneyLg : MadarType.money).copyWith(
                color: negative
                    ? colors.success
                    : hero && voided
                    ? colors.textMuted
                    : fg,
                decoration: hero && voided ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      );
    }

    final vatLabel = inclusive
        ? '${t('history.vat_included')}$pct'
        : '${t('order.tax')}$pct';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(t('order.subtotal'), subtotal),
        if (discount > 0) row(t('order.discount'), discount, negative: true),
        if (service > 0) row(t('history.service'), service),
        if (!inclusive) row(vatLabel, tax),
        row(t('order.total'), order.totalMinor, hero: true),
        if (inclusive) row(vatLabel, tax, muted: true),
        if (tip > 0) row(t('history.tip'), tip, muted: true),
      ],
    );
  }
}

/// Reprint · Add points, then the two sentences that keep a void from
/// being used as a refund.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final o = order;
    final state = SaleState.of(o);
    final canReprint = state != SaleState.queued && state != SaleState.failed;
    final refunds = ref.watch(historyProvider.select((s) => s.refunds));
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final canAward =
        ref.watch(historyProvider.select((s) => s.loyaltyOffered)) &&
        state != SaleState.voided &&
        state != SaleState.failed &&
        bridge.loyaltyAwardWindowOpen(
          orderCreatedAt: o.createdAt,
          now: DateTime.now().toUtc().toIso8601String(),
        );
    String t(String key) => historyTr(bridge, key);

    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: Space.card,
        end: Space.card,
        bottom: Space.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          if (canReprint || canAward)
            Row(
              spacing: Space.sm,
              children: [
                if (canReprint)
                  Expanded(
                    child: MadarButton(
                      label: t('history.reprint'),
                      variant: MadarButtonVariant.secondary,
                      glyph: MadarGlyph.printer,
                      onTap: () => unawaited(_reprint(context, ref)),
                    ),
                  ),
                if (canAward)
                  Expanded(
                    child: MadarButton(
                      label: t('loyalty.add_points'),
                      variant: MadarButtonVariant.secondary,
                      glyph: MadarGlyph.star,
                      onTap: () => unawaited(
                        showMadarSheet<bool>(
                          context,
                          builder: (_) => LoyaltyAwardSheet(
                            // A queued sale has no server id yet — it is known
                            // by the client key it was rung under.
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
          // What has already gone back on this sale, before anything is
          // offered about giving more back.
          if (refunds != null && refunds.refundedMinor > 0)
            _RefundedBlock(refunds: refunds, currency: currency, t: t),
          if (state != SaleState.voided)
            Container(
              padding: const EdgeInsetsDirectional.all(Space.md),
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.sm,
                children: [
                  MadarGlyphIcon(
                    MadarGlyph.alertCircle,
                    size: IconSize.md,
                    color: colors.textSecondary,
                  ),
                  Expanded(
                    child: Text(
                      '${t('history.void_teach')} ${t('history.refund_teach')}',
                      style: MadarType.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The receipt projection is fetched with the detail; if that fetch lost
  /// (a first tap before it landed, or an order never seen online) ask once
  /// more here and say so if the core cannot.
  Future<void> _reprint(BuildContext context, WidgetRef ref) async {
    var view = receipt;
    if (view == null) {
      try {
        view = await ref
            .read(bridgeProvider)
            .orderReceiptView(orderId: order.id);
      } on MadarError catch (e) {
        ref.read(historyProvider.notifier).surfaceError(e);
        return;
      }
    }
    if (!context.mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => ReceiptSheet(receipt: view!),
    );
  }
}

// ── The phone's sale screen ────────────────────────────────────────────────

/// The sale pushed over the list on a phone. Reads the selection from
/// [historyProvider]; pops itself if the selection is gone (the shift
/// reloaded without it).
class SaleScreen extends ConsumerWidget {
  /// Creates the phone's sale screen.
  const SaleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final selected = ref.watch(historyProvider.select((s) => s.selected));
    if (selected == null) {
      return Scaffold(
        backgroundColor: colors.bg,
        body: EmptyState(
          icon: 'receipt',
          title: historyTr(bridge, 'history.select_prompt'),
        ),
      );
    }
    final layout = context.madarLayout;
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: layout.gutter,
                end: layout.gutter,
                top: Space.lg,
              ),
              child: MadarHeader(
                title: saleTitle(bridge, selected),
                onBack: () => Navigator.maybePop(context),
                actions: [MoreTile(order: selected)],
              ),
            ),
            Expanded(child: SalePanel(order: selected)),
          ],
        ),
      ),
    );
  }
}

// ── The ⋯ sheet ─────────────────────────────────────────────────────────────

enum _MoreChoice { voidSale, refundSale }

/// What ⋯ offers: Void, with what it does under it and why it may not
/// apply; and the sentence about the refund it is not. The sale's paid time
/// sits above so the teller sees how old the sale is before correcting it.
class _MoreSheet extends ConsumerWidget {
  const _MoreSheet({required this.order});

  final OrderSummaryView order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final o = order;
    final state = SaleState.of(o);
    String t(String key) => historyTr(bridge, key);

    // Why Void does not apply, in words — or null when it does. The one
    // refusal the till cannot see ahead (a closed shift) comes back from
    // the server and lands in the void sheet's banner.
    final blocked = switch (state) {
      SaleState.voided => t('history.void_cannot_voided'),
      SaleState.queued => t('history.void_cannot_queued'),
      SaleState.failed => t('history.void_cannot_failed'),
      null => null,
    };
    // And the one Void does not share: a sale already given back in full has
    // nothing left to refund. The server refuses it; saying so here saves the
    // teller typing an amount in front of a customer first.
    final refundBlocked =
        blocked ??
        switch (ref.watch(historyProvider.select((s) => s.refunds))) {
          final r? when r.orderId == o.id && r.refundableRemainingMinor <= 0 =>
            t('history.refund_all'),
          _ => null,
        };

    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Row(
            spacing: Space.md,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.xs,
                  children: [
                    Text(
                      saleTitle(bridge, o),
                      style: MadarType.h2.copyWith(color: colors.textPrimary),
                    ),
                    Text(
                      '${t('history.paid_at').replaceAll('{time}', ltrIsland(bridge.formatTime(rfc3339: o.createdAt, style: TimeStyle.dateTime)))}'
                      ' · ${Money.format(o.totalMinor, currency: currency)}',
                      style: MadarType.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              MadarGlyphTile(
                glyph: MadarGlyph.close,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          MadarCard(
            flush: true,
            child: Opacity(
              opacity: blocked == null ? 1 : Opacities.disabled,
              child: MadarRow(
                title: t('history.void_sale'),
                subtitle: blocked ?? t('history.void_teach'),
                glyph: MadarGlyph.trash,
                onTap: blocked == null
                    ? () => Navigator.of(context).maybePop(_MoreChoice.voidSale)
                    : null,
                chevron: blocked == null,
                titleStyle: MadarType.title.copyWith(
                  color: blocked == null ? colors.danger : colors.textPrimary,
                ),
              ),
            ),
          ),
          // A REFUND IS NOT A VOID, and this is where a teller learns the
          // difference: the two sit side by side with what each one does to
          // the books written under it. Refund is blocked by the same three
          // states as void — you cannot give money back on a sale the server
          // has never seen, nor on one already undone.
          MadarCard(
            flush: true,
            child: Opacity(
              opacity: refundBlocked == null ? 1 : Opacities.disabled,
              child: MadarRow(
                title: t('history.refund_sale'),
                subtitle: refundBlocked ?? t('history.refund_teach'),
                glyph: MadarGlyph.receipt,
                onTap: refundBlocked == null
                    ? () =>
                          Navigator.of(context).maybePop(_MoreChoice.refundSale)
                    : null,
                chevron: refundBlocked == null,
                titleStyle: MadarType.title.copyWith(color: colors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── The void sheet ──────────────────────────────────────────────────────────

/// The void form's state (reason / restock / busy / error).
class _VoidFormState {
  const _VoidFormState({
    this.reason = 'mistake',
    this.restock = true,
    this.busy = false,
    this.error,
  });

  final String reason;
  final bool restock;
  final bool busy;
  final String? error;

  static const Object _unset = Object();

  _VoidFormState copyWith({
    String? reason,
    bool? restock,
    bool? busy,
    Object? error = _unset,
  }) {
    return _VoidFormState(
      reason: reason ?? this.reason,
      restock: restock ?? this.restock,
      busy: busy ?? this.busy,
      error: error == _unset ? this.error : error as String?,
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

  void selectReason(String reason) => state = state.copyWith(reason: reason);

  void toggleRestock({required bool on}) => state = state.copyWith(restock: on);

  /// Void the sale — true on success (the sheet pops). A void moves the
  /// shift stats, so the shell refreshes here; a refusal (the shift is
  /// closed, the order is not this branch's) lands in [_VoidFormState.error]
  /// in the server's words — the till cannot pre-check them.
  Future<bool> confirm({required String orderId, required String note}) async {
    final bridge = ref.read(bridgeProvider);
    state = state.copyWith(busy: true, error: null);
    try {
      await bridge.voidOrder(
        orderId: orderId,
        reason: state.reason,
        note: note.isEmpty ? null : note,
        restoreInventory: state.restock,
      );
      ref.read(shellProvider.notifier).refresh();
      return true;
    } on MadarError catch (e) {
      if (e is MadarError_Unauthenticated &&
          ref.read(shellProvider).session != null) {
        ref.read(reauthRequestProvider.notifier).request();
      }
      if (_alive) {
        state = state.copyWith(busy: false, error: bridge.humanMessage(e));
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
/// back — the kitchen made it and it left the building.
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
  String _reason = 'customer';
  bool _busy = false;
  String? _error;

  /// What the SERVER says is still refundable, once earlier refunds are
  /// counted. Null while it loads, or when nothing could be read — the
  /// endpoint checks again anyway, so the sale's total is a safe start.
  int? _remainingMinor;

  int get _cap => _remainingMinor ?? widget.order.totalMinor;

  @override
  void initState() {
    super.initState();
    // The panel usually has this already; asking again costs a cached read
    // and covers the sheet being opened from somewhere that did not.
    final prior = ref.read(historyProvider).refunds;
    if (prior != null && prior.orderId == widget.order.id) {
      _remainingMinor = prior.refundableRemainingMinor;
      _amountMinor = prior.refundableRemainingMinor;
    }
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
    // Against what is LEFT, not against the sale: a second refund on a sale
    // already half given back is over by half, and the server refuses it.
    if (minor > _cap) {
      setState(() => _error = historyTr(bridge, 'history.refund_over'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await bridge.refundOrder(
        orderId: widget.order.id,
        amountMinor: minor,
        // Back the way it came. A card sale refunded in cash would leave the
        // drawer short against a card takings line that never moved, and the
        // till has no list of methods on this screen to offer instead.
        method: widget.order.paymentLabel,
        reason: _reason,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      ref.read(shellProvider.notifier).refresh();
      if (mounted) Navigator.of(context).maybePop(true);
    } on MadarError catch (e) {
      if (e is MadarError_Unauthenticated &&
          ref.read(shellProvider).session != null) {
        ref.read(reauthRequestProvider.notifier).request();
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _error = bridge.humanMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final o = widget.order;
    String t(String key) => historyTr(bridge, key);

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
                Row(
                  spacing: Space.md,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.xs,
                        children: [
                          Text(
                            t('history.refund_sale'),
                            style: MadarType.h2.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            [
                              saleTitle(bridge, o),
                              Money.format(o.totalMinor, currency: currency),
                              // What is left, whenever it differs from the
                              // sale — the figure this sheet is bounded by.
                              if (_remainingMinor case final left?
                                  when left != o.totalMinor && left <= 0)
                                t('history.refund_all'),
                              if (_remainingMinor case final left?
                                  when left != o.totalMinor && left > 0)
                                t('history.refund_left').replaceAll(
                                  '{amount}',
                                  Money.format(left, currency: currency),
                                ),
                            ].join(' · '),
                            style: MadarType.bodySm.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    MadarGlyphTile(
                      glyph: MadarGlyph.close,
                      onTap: () => Navigator.of(context).maybePop(false),
                    ),
                  ],
                ),
                Text(
                  t('history.refund_teach'),
                  style: MadarType.bodySm.copyWith(color: colors.textSecondary),
                ),
                MadarSectionHeader(text: t('history.refund_amount')),
                MadarAmountField(
                  amountMinor: _amountMinor,
                  onAmountMinor: (v) => setState(() {
                    _amountMinor = v;
                    _error = null;
                  }),
                  currencyCode: currency,
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
                        onTap: () => setState(() => _reason = key),
                      ),
                  ],
                ),
                MadarField(
                  controller: _note,
                  placeholder: t('void.note'),
                  glyph: MadarGlyph.note,
                  enabled: !_busy,
                ),
                if (_error case final error?)
                  NoticeBanner(
                    text: error,
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

/// Reason chips, an optional note, the restock toggle, one danger CTA.
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
        .confirm(orderId: widget.order.id, note: _note.text.trim());
    if (ok && mounted) await Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final form = ref.watch(_voidFormProvider);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final o = widget.order;
    String t(String key) => historyTr(bridge, key);
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
                Row(
                  spacing: Space.md,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.xs,
                        children: [
                          Text(
                            t('void.title'),
                            style: MadarType.h2.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            '${saleTitle(bridge, o)}'
                            ' · ${Money.format(o.totalMinor, currency: currency)}',
                            style: MadarType.bodySm.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    MadarGlyphTile(
                      glyph: MadarGlyph.close,
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
                  glyph: MadarGlyph.note,
                  enabled: !form.busy,
                ),
                Row(
                  spacing: Space.sm,
                  children: [
                    Expanded(
                      child: Text(
                        t('void.restock'),
                        style: MadarType.title.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    _RestockSwitch(
                      value: form.restock,
                      onChanged: (v) => ref
                          .read(_voidFormProvider.notifier)
                          .toggleRestock(on: v),
                    ),
                  ],
                ),
                if (form.error case final error?)
                  NoticeBanner(
                    text: error,
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

/// A tokens-only toggle: accent track when on, sunk grey when off, an
/// animated thumb.
class _RestockSwitch extends StatelessWidget {
  const _RestockSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Semantics(
      toggled: value,
      child: TactileScale(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: MotionSpec.standardDuration,
          curve: MotionSpec.standardCurve,
          width: _switchTrackWidth,
          height: _switchTrackHeight,
          padding: const EdgeInsetsDirectional.all(
            (_switchTrackHeight - _switchThumb) / 2,
          ),
          decoration: BoxDecoration(
            color: value ? colors.accent : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: AnimatedAlign(
            duration: MotionSpec.standardDuration,
            curve: MotionSpec.standardCurve,
            alignment: value
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: value ? colors.textOnAccent : colors.textMuted,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: _switchThumb),
            ),
          ),
        ),
      ),
    );
  }
}
