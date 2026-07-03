import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_incoming/src/delivery_body.dart';
import 'package:feature_incoming/src/incoming_provider.dart';
import 'package:feature_incoming/src/tickets_settle_body.dart';
import 'package:feature_incoming/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Native metrics (IncomingScreen.kt) kept verbatim.

/// Count-pill insets (natives: (xs+2)×1.dp).
const EdgeInsetsDirectional _countPillPad = EdgeInsetsDirectional.symmetric(
  horizontal: Space.xs + 2,
  vertical: 1,
);

/// Unified "Orders" surface (teller): delivery + waiter open-tickets in ONE
/// place, two tabs, fed by the shell's session-level SSE ticks. Replaces
/// the separate delivery and settle-tickets screens. Both tabs are live
/// (delivery → [deliveryTickProvider], tickets → [ticketTickProvider]) so a
/// waiter firing on another device reaches the teller instantly. Port of
/// the Kotlin IncomingScreen (IncomingScreen.kt + DeliveryScreen.kt +
/// WaiterScreen.kt TicketsSettleBody).
class IncomingScreen extends ConsumerStatefulWidget {
  const IncomingScreen({super.key, this.initialTab = 0});

  /// Which tab opens first (0 = delivery, 1 = tickets) — the natives'
  /// `incomingTab`, which realtime alerts steer to the pinged board.
  final int initialTab;

  @override
  ConsumerState<IncomingScreen> createState() => _IncomingScreenState();
}

class _IncomingScreenState extends ConsumerState<IncomingScreen> {
  @override
  void initState() {
    super.initState();
    // Provider writes are illegal while the tree is building — seed the
    // landing tab + kick both loads (so the tab badges populate) right
    // after this first build.
    unawaited(
      Future<void>.microtask(() {
        if (!mounted) return;
        ref.read(incomingProvider.notifier).enter(tab: widget.initialTab);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Live ticks — the shell bumps these on `delivery.*` / `ticket.*`
    // realtime events. Listened HERE (not per-body) so both tab badges
    // stay live whichever tab is showing.
    ref
      ..listen(deliveryTickProvider, (_, _) {
        unawaited(ref.read(incomingProvider.notifier).loadDeliveryOrders());
      })
      ..listen(ticketTickProvider, (_, _) {
        unawaited(ref.read(incomingProvider.notifier).loadOpenTickets());
      });
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final tab =
        ref.watch(incomingProvider.select((s) => s.tab)) ?? widget.initialTab;
    final deliveryCount = ref.watch(
      incomingProvider.select((s) => s.deliveryOrders.length),
    );
    final ticketCount = ref.watch(
      incomingProvider.select((s) => s.settleableTickets.length),
    );
    final toast = ref.watch(incomingProvider.select((s) => s.toast));
    // Scaffold: every screen root owns its own Scaffold in this app.
    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              // THE shared header (paints under the status bar); the live
              // segmented tab bar rides directly beneath it.
              MadarHeader(
                title: bridge.tr(key: 'incoming.title'),
                onBack: () => Navigator.maybePop(context),
              ),
              // Segmented tab bar (teal active fill) with live per-tab
              // count badges.
              ColoredBox(
                color: colors.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: Space.lg,
                        vertical: Space.md,
                      ),
                      child: Container(
                        padding: const EdgeInsetsDirectional.all(Space.xs),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        child: Row(
                          spacing: Space.xs,
                          children: [
                            Expanded(
                              child: _IncomingTab(
                                label: bridge.tr(key: 'delivery.title'),
                                count: deliveryCount,
                                active: tab == 0,
                                onTap: () => ref
                                    .read(incomingProvider.notifier)
                                    .setTab(0),
                              ),
                            ),
                            Expanded(
                              child: _IncomingTab(
                                label: bridge.tr(key: 'waiter.title'),
                                count: ticketCount,
                                active: tab == 1,
                                onTap: () => ref
                                    .read(incomingProvider.notifier)
                                    .setTab(1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const IncomingHairline(),
                  ],
                ),
              ),
              // Body — swapping widget types remounts the tab so each
              // body's own init (refresh) runs on (re)entry, like the
              // natives' `when(tab)`.
              Expanded(
                child: SafeArea(
                  top: false,
                  child: tab == 0
                      ? const DeliveryBody()
                      : const TicketsSettleBody(),
                ),
              ),
            ],
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

/// One segment of the Incoming tab bar — label + an optional count pill,
/// teal fill when active. Mirrors the held-orders tab idiom (active =
/// on-accent count pill, idle = surface).
class _IncomingTab extends StatelessWidget {
  const _IncomingTab({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = active ? colors.textOnAccent : colors.textSecondary;
    return TactileScale(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: active ? colors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.sm,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.title.copyWith(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            if (count > 0)
              Container(
                padding: _countPillPad,
                decoration: BoxDecoration(
                  color: active
                      ? colors.textOnAccent.withValues(
                          alpha: Opacities.border,
                        )
                      : colors.surface,
                  // CircleShape over a wider-than-tall box = stadium pill.
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  '$count',
                  style: MadarType.labelSm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
