// Bills — the waiter's second tab: every open bill in the branch, MINE first.
//
// A waiter covers a colleague's table constantly, so the tab shows all of
// them and groups rather than filters. "Mine" is a display-name match: the
// ticket view carries the waiter's name and no `opened_by` id, and the
// grouping is honest about being that coarse. A bill whose kitchen round is
// ready leads its group; the rest sit longest-open first.
//
// A branch with no floor has no tables to tap, so this tab grows a "+ New
// bill" that asks only for a name and hands over to Sell.
import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/bill_screen.dart';
import 'package:feature_order/src/floor_list.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/sell_screen.dart';
import 'package:feature_order/src/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The open bills, grouped.
class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({this.canCharge, super.key});

  /// Handed to the Bill a row opens — see [BillScreen.canCharge]. The
  /// waiter's shell passes false; Queue › Bills is a different screen.
  final bool? canCharge;

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen>
    with RealtimeGatedPoll<BillsScreen> {
  Timer? _clock;

  OrderNotifier get _notifier => ref.read(orderProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _notifier.ensureInit().then((_) => _notifier.loadOpenTickets()),
      );
    });
    _clock = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _open(TicketView t) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BillScreen(ticketId: t.id, canCharge: widget.canCharge),
      ),
    );
  }

  /// "+ New bill": a name, then Sell as the round builder.
  Future<void> _newBill() async {
    final bridge = ref.read(bridgeProvider);
    final controller = TextEditingController();
    final name = await showMadarSheet<String>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Text(
              orderWord(bridge, 'bills.new_bill'),
              style: MadarType.h2.copyWith(
                color: sheetContext.madarColors.textPrimary,
              ),
            ),
            MadarField(
              controller: controller,
              placeholder: orderWord(bridge, 'sell.guest_name'),
              glyph: MadarGlyph.user,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) => Navigator.of(sheetContext).maybePop(v),
            ),
            MadarButton(
              label: bridge.tr(key: 'setup.continue'),
              onTap: () => Navigator.of(sheetContext).maybePop(controller.text),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    _notifier.startNewBill(name);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SellScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    ref.listen(ticketTickProvider, (_, _) {
      unawaited(_notifier.loadOpenTickets());
    });
    realtimeGatedPoll(
      interval: const Duration(seconds: 15),
      onPoll: () => unawaited(_notifier.loadOpenTickets()),
    );

    final layout = MadarLayout.of(context);
    final state = ref.watch(orderProvider);
    final me = state.displayName.trim();
    final live = state.openTickets.where(isLiveTicket).toList(growable: false)
      ..sort((a, b) {
        final ar = a.status == 'ready' ? 0 : 1;
        final br = b.status == 'ready' ? 0 : 1;
        if (ar != br) return ar - br;
        return a.openedAt.compareTo(b.openedAt);
      });
    final mine = live
        .where((t) => me.isNotEmpty && t.waiterName?.trim() == me)
        .toList(growable: false);
    final others = live.where((t) => !mine.contains(t)).toList(growable: false);
    final now = DateTime.now().toUtc();

    Widget group(String title, List<TicketView> list) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MadarSectionHeader(text: title),
        const SizedBox(height: Space.sm),
        MadarCard(
          flush: true,
          child: Column(
            children: [
              for (final (i, t) in list.indexed) ...[
                if (i > 0) const MadarHairline(light: true),
                _BillRow(
                  ticket: t,
                  tableLabel: state.floorLayout?.tables
                      .where((x) => x.id == t.tableId)
                      .firstOrNull
                      ?.label,
                  currency: state.currency,
                  now: now,
                  bridge: bridge,
                  onTap: () => unawaited(_open(t)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
      ],
    );

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                layout.gutter,
                Space.md,
                layout.gutter,
                Space.md,
              ),
              child: MadarHeader(
                title: orderWord(bridge, 'bills.title'),
                actions: [
                  if (!state.hasFloor)
                    MadarButton(
                      label: orderWord(bridge, 'bills.new_bill'),
                      glyph: MadarGlyph.plus,
                      size: MadarButtonSize.compact,
                      onTap: () => unawaited(_newBill()),
                    ),
                ],
              ),
            ),
            Expanded(
              child: live.isEmpty
                  ? EmptyState(
                      icon: 'doc.text',
                      title: bridge.tr(key: 'waiter.no_tickets'),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: Responsive.billMaxWidth,
                        ),
                        child: ListView(
                          padding: EdgeInsetsDirectional.symmetric(
                            horizontal: layout.gutter,
                          ),
                          children: [
                            if (mine.isNotEmpty)
                              group(orderWord(bridge, 'bills.mine'), mine),
                            if (others.isNotEmpty)
                              group(
                                mine.isEmpty
                                    ? orderWord(bridge, 'bills.title')
                                    : orderWord(bridge, 'bills.others'),
                                others,
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "▌T3   ✓ Ready · 42m · Sara        235.00 ›"
class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.ticket,
    required this.tableLabel,
    required this.currency,
    required this.now,
    required this.bridge,
    required this.onTap,
  });

  final TicketView ticket;
  final String? tableLabel;
  final String currency;
  final DateTime now;
  final MadarBridge bridge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final t = ticket;
    final ready = t.status == 'ready';
    final queued = t.queuedOffline || t.status == 'queued';
    final bar = ready
        ? colors.success
        : queued
        ? colors.warning
        : colors.accent;
    final opened = DateTime.tryParse(t.openedAt);
    final age = opened == null
        ? null
        : formatSeatedFor(now.difference(opened.toUtc()));
    final rounds = t.lines.isEmpty
        ? 0
        : t.lines.map((l) => l.roundNumber).reduce((a, b) => a > b ? a : b);
    final subtitle = [
      if (ready)
        orderWord(bridge, 'bill.ready')
      else if (queued)
        orderWord(bridge, 'bill.queued')
      else if (rounds > 0)
        '${bridge.tr(key: 'tables.round')} $rounds',
      ?age,
      if (t.waiterName?.trim().isNotEmpty ?? false) t.waiterName!,
    ].join(' · ');
    return MadarRow(
      bar: bar,
      title: tableLabel ?? t.customerName ?? t.ticketRef ?? '',
      subtitle: subtitle,
      value: t.subtotalMinor > 0
          ? MoneyText(t.subtotalMinor, currency: currency)
          : null,
      trailing: queued
          ? MadarGlyphIcon(
              MadarGlyph.half,
              size: IconSize.md,
              color: colors.warning,
            )
          : null,
      onTap: onTap,
    );
  }
}
