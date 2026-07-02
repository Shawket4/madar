import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_incoming/src/delivery_body.dart';
import 'package:feature_incoming/src/incoming_controller.dart';
import 'package:feature_incoming/src/tickets_settle_body.dart';
import 'package:feature_incoming/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (IncomingScreen.kt) kept verbatim.

/// Header title size (natives: 17.sp Black).
const double _headerTitleSize = 17;

/// Count-pill insets (natives: (xs+2)×1.dp).
const EdgeInsetsDirectional _countPillPad = EdgeInsetsDirectional.symmetric(
  horizontal: Space.xs + 2,
  vertical: 1,
);

/// Unified "Orders" surface (teller): delivery + waiter open-tickets in ONE
/// place, two tabs, fed by the shell's session-level SSE ticks. Replaces
/// the separate delivery and settle-tickets screens. Both tabs are live
/// (delivery → [deliveryTick], tickets → [ticketTick]) so a waiter firing
/// on another device reaches the teller instantly. Port of the Kotlin
/// IncomingScreen (IncomingScreen.kt + DeliveryScreen.kt + WaiterScreen.kt
/// TicketsSettleBody).
class IncomingScreen extends StatefulWidget {
  const IncomingScreen({
    required this.core,
    required this.onStateChanged,
    this.initialTab = 0,
    this.deliveryTick,
    this.ticketTick,
    this.onBack,
    super.key,
  });

  final MadarCore core;

  /// Fired after any bridge call that can move `app_route()` / the shift
  /// stats (a finalized delivery / settled ticket books a real sale).
  final void Function() onStateChanged;

  /// Which tab opens first (0 = delivery, 1 = tickets) — the natives'
  /// `incomingTab`, which realtime alerts steer to the pinged board.
  final int initialTab;

  /// Bumped by the shell on `delivery.*` realtime events.
  final Listenable? deliveryTick;

  /// Bumped by the shell on `ticket.*` realtime events.
  final Listenable? ticketTick;

  /// Back affordance — defaults to popping this route (the natives set
  /// `showIncoming = false`).
  final VoidCallback? onBack;

  @override
  State<IncomingScreen> createState() => _IncomingScreenState();
}

class _IncomingScreenState extends State<IncomingScreen> {
  late final IncomingController _model;
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    _model = IncomingController(
      core: widget.core,
      onStateChanged: widget.onStateChanged,
    );
    // Load both lists on entry so the tab badges are populated immediately
    // (each body also reloads itself + keys on its own live tick).
    unawaited(_model.loadDeliveryOrders());
    unawaited(_model.loadOpenTickets());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void _back() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final colors = context.madarColors;
        final deliveryCount = _model.deliveryOrders.length;
        final ticketCount = _model.settleableTickets.length;
        // Scaffold: every screen root owns its own Scaffold in this app.
        return Scaffold(
          backgroundColor: colors.bg,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    // Raised header surface: back + title, then the live
                    // segmented tab bar.
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
                            child: Row(
                              spacing: Space.md,
                              children: [
                                TactileScale(
                                  onTap: _back,
                                  child: MadarIcon(
                                    'chevron.backward',
                                    tint: colors.textPrimary,
                                    size: IconSize.xl,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _model.tr('incoming.title'),
                                    style: MadarType.h3.copyWith(
                                      fontSize: _headerTitleSize,
                                      fontWeight: FontWeight.w900,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Segmented tab bar (teal active fill) with live
                          // per-tab count badges.
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start: Space.lg,
                              end: Space.lg,
                              bottom: Space.md,
                            ),
                            child: Container(
                              padding: const EdgeInsetsDirectional.all(
                                Space.xs,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceAlt,
                                borderRadius: BorderRadius.circular(Radii.sm),
                              ),
                              child: Row(
                                spacing: Space.xs,
                                children: [
                                  Expanded(
                                    child: _IncomingTab(
                                      label: _model.tr('delivery.title'),
                                      count: deliveryCount,
                                      active: _tab == 0,
                                      onTap: () => setState(() => _tab = 0),
                                    ),
                                  ),
                                  Expanded(
                                    child: _IncomingTab(
                                      label: _model.tr('waiter.title'),
                                      count: ticketCount,
                                      active: _tab == 1,
                                      onTap: () => setState(() => _tab = 1),
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
                    // body's own init (initial load + live tick) runs on
                    // (re)entry, like the natives' `when(tab)`.
                    Expanded(
                      child: _tab == 0
                          ? DeliveryBody(
                              model: _model,
                              tick: widget.deliveryTick,
                            )
                          : TicketsSettleBody(
                              model: _model,
                              tick: widget.ticketTick,
                            ),
                    ),
                  ],
                ),
                // Toasts float above everything on this screen.
                ToastHost(_model.toast, onDismiss: _model.dismissToast),
              ],
            ),
          ),
        );
      },
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
