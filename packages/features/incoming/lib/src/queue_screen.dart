/// The Queue — the teller's one inbox: bills to charge, online orders, and
/// (only where the branch routes fired rounds to the counter) the kitchen
/// board, as segments with their counts in the label.
///
/// The Kitchen segment is gated on [tillShowsKitchen]: in `kds` mode the
/// kitchen owns its own board, and a till bumping from here would clear a
/// line off a screen a cook is still working from. Unknown mode hides it
/// too — a device that has never reached the server does not get to guess.
///
/// Both feeds are live: the screen reloads on the shell's `ticket.*` and
/// `delivery.*` ticks, so a waiter's fire on another device and a new online
/// order reach the teller at once, and both segment counts stay right
/// whichever segment is showing. The shell mounts this as a tab body; pushed
/// on its own (the sticky new-order toast's *View*) it draws a back tile.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_incoming/src/bills_segment.dart';
import 'package:feature_incoming/src/incoming_provider.dart';
import 'package:feature_incoming/src/online_segment.dart';
import 'package:feature_incoming/src/queue_strings.dart';
import 'package:feature_kds/feature_kds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The segmented control's width beside the title on a tablet.
const double _segmentMaxWidth = 420;

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({
    this.initialSegment = QueueSegment.bills,
    this.onOpenBill,
    super.key,
  });

  /// Which segment opens first — the new-order toast's *View* lands on
  /// Online; the tab lands on Bills.
  final QueueSegment initialSegment;

  /// Opens the Bill for a row; the shell supplies its Bill screen. Null falls
  /// back to the shared details sheet with Charge under it.
  final OpenBill? onOpenBill;

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  @override
  void initState() {
    super.initState();
    // Provider writes are illegal while the tree is building — seed the
    // landing segment + kick the loads right after this first build.
    unawaited(
      Future<void>.microtask(() {
        if (!mounted) return;
        ref
            .read(incomingProvider.notifier)
            .enter(segment: widget.initialSegment);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Live ticks — listened HERE (not per-segment) so both counts stay live
    // whichever segment is showing.
    ref
      ..listen(deliveryTickProvider, (_, _) {
        unawaited(ref.read(incomingProvider.notifier).loadDeliveryOrders());
      })
      ..listen(ticketTickProvider, (_, _) {
        unawaited(ref.read(incomingProvider.notifier).loadOpenTickets());
      });
    final colors = context.madarColors;
    final bridge = ref.bridge;
    var segment =
        ref.watch(incomingProvider.select((s) => s.segment)) ??
        widget.initialSegment;
    final billsCount = ref.watch(
      incomingProvider.select((s) => s.settleableTickets.length),
    );
    final onlineCount = ref.watch(
      incomingProvider.select((s) => s.deliveryOrders.length),
    );
    // Null while the first read is in flight, and null forever on a device
    // that has never reached the server — both hide the segment.
    final showKitchen = tillShowsKitchen(ref.watch(kitchenRoutingModeProvider));
    // The mode can change under a teller who is standing on the segment.
    // Fall back rather than leave the control pointing at an item it no
    // longer has.
    if (segment == QueueSegment.kitchen && !showKitchen) {
      segment = QueueSegment.bills;
    }
    // Only counted when the segment exists: watching the board's family
    // member mounts it, and an unrouted till has no business holding a feed.
    final kitchenCount = showKitchen
        ? ref.watch(
            kdsProvider(null).select(
              (s) => s.tickets.where((t) => t.status == 'firing').length,
            ),
          )
        : 0;
    final toast = ref.watch(incomingProvider.select((s) => s.toast));
    final layout = context.madarLayout;
    final canPop = Navigator.of(context).canPop();

    final segmented = MadarSegmented<QueueSegment>(
      items: [
        MadarSegmentItem(
          QueueSegment.bills,
          bridge.trOr(QueueKeys.bills),
          count: billsCount,
          glyph: MadarGlyph.receipt,
        ),
        MadarSegmentItem(
          QueueSegment.online,
          bridge.trOr(QueueKeys.online),
          count: onlineCount,
          glyph: MadarGlyph.bike,
        ),
        if (showKitchen)
          MadarSegmentItem(
            QueueSegment.kitchen,
            bridge.trOr(QueueKeys.kitchen),
            count: kitchenCount,
            glyph: MadarGlyph.flame,
          ),
      ],
      value: segment,
      onChanged: ref.read(incomingProvider.notifier).setSegment,
    );

    final title = Text(
      bridge.trOr(QueueKeys.title),
      style: MadarType.h1.copyWith(color: colors.textPrimary),
    );

    final header = Padding(
      padding: EdgeInsetsDirectional.only(
        start: layout.gutter,
        end: layout.gutter,
        top: Space.lg,
        bottom: Space.xs,
      ),
      child: layout.isTablet
          ? Row(
              spacing: Space.lg,
              children: [
                if (canPop)
                  MadarGlyphTile(
                    glyph: MadarGlyph.chevronBack,
                    size: MadarButtonSize.regular,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                title,
                Flexible(
                  flex: 3,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _segmentMaxWidth,
                    ),
                    child: segmented,
                  ),
                ),
                // Accepting per channel rides in the header on a tablet
                // (the phone puts it at the foot of the Online segment).
                // Bounded, so a long channel name wraps instead of pushing
                // past the edge.
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: segment == QueueSegment.online
                        ? const AcceptingRow(compact: true)
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                Row(
                  spacing: Space.md,
                  children: [
                    if (canPop)
                      MadarGlyphTile(
                        glyph: MadarGlyph.chevronBack,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    title,
                  ],
                ),
                segmented,
              ],
            ),
    );

    // Scaffold: every screen root owns its own Scaffold in this app.
    // A tab body — the shell's top bar above it already paid the top inset.
    return MadarPageScaffold(
      safeTop: false,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                header,
                // Swapping widget types remounts the segment so its own
                // init (refresh) runs on (re)entry.
                Expanded(
                  child: switch (segment) {
                    QueueSegment.bills => BillsSegment(
                      onOpenBill: widget.onOpenBill,
                    ),
                    QueueSegment.online => const OnlineSegment(),
                    // The cook's own board, minus its header — one widget and
                    // one provider family, so the counter and the kitchen
                    // cannot disagree about a line. Falls back to Bills if the
                    // mode changed out from under a selected segment.
                    QueueSegment.kitchen => const KdsBoardBody(stationId: null),
                  },
                ),
              ],
            ),
          ),
          // Toasts float above everything on this screen.
          SafeArea(
            child: ToastHost(
              toast,
              onDismiss: ref.read(incomingProvider.notifier).dismissToast,
            ),
          ),
        ],
      ),
    );
  }
}
