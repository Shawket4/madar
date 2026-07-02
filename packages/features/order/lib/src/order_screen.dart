import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_order/src/bundle_detail_sheet.dart';
import 'package:feature_order/src/cart_panel.dart';
import 'package:feature_order/src/catalog_column.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:feature_order/src/order_controller.dart';
import 'package:feature_order/src/waiter_sheets.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:feature_shift/feature_shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The order screen — the heart of the POS. Browse the branch-effective
/// catalog (offline-safe) and build a cart: tap an item to customize + add,
/// adjust quantities, see live totals. On wide layouts (≥760) the cart is a
/// column beside the grid; on narrow ones it's a bottom bar that opens a
/// drawer. In waiter mode the cart's terminal action FIRES a ticket (or
/// adds a round) instead of tendering. Mirror of the Kotlin OrderScreen.
class OrderScreen extends StatefulWidget {
  const OrderScreen({
    required this.core,
    required this.onStateChanged,
    this.ticketTick,
    this.onOpenSync,
    super.key,
  });

  final MadarCore core;

  /// Fired after any bridge call that can move `app_route()` / the session.
  final void Function() onStateChanged;

  /// Shell-owned realtime tick — bumps on every `ticket.*` SSE event so a
  /// waiter board reloads its open tickets instantly (the 15s heartbeat
  /// poll stays as a safety net). Null = poll only.
  final Listenable? ticketTick;

  /// Opens the sync center (outbox) — makes the top-bar sync status chip
  /// tappable like the natives' SyncChip. Null leaves the chip inert.
  final VoidCallback? onOpenSync;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late final OrderController _model;
  Timer? _heartbeat;

  /// Keeps the catalog's search/category state alive when the responsive
  /// layout flips the column between the wide Row and the narrow Column.
  final GlobalKey _catalogKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _model = OrderController(
      core: widget.core,
      onStateChanged: widget.onStateChanged,
    );
    unawaited(_model.init());
    _model.addListener(_maybeReauth);
    widget.ticketTick?.addListener(_onTicketTick);
    // Connectivity heartbeat — refresh online + sync chrome every 15s; a
    // waiter board also re-polls its open tickets (safety net under the
    // shell-owned realtime session).
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_model.refreshConnectivity());
      if (_model.isWaiter) unawaited(_model.loadOpenTickets());
    });
  }

  @override
  void didUpdateWidget(OrderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ticketTick, widget.ticketTick)) {
      oldWidget.ticketTick?.removeListener(_onTicketTick);
      widget.ticketTick?.addListener(_onTicketTick);
    }
  }

  @override
  void dispose() {
    widget.ticketTick?.removeListener(_onTicketTick);
    _heartbeat?.cancel();
    _model
      ..removeListener(_maybeReauth)
      ..dispose();
    super.dispose();
  }

  /// A bridge call 401'd with a live session (expired/missing bearer) —
  /// open the re-auth sheet once; the latch clears immediately so a second
  /// notify can't double-present it.
  bool _reauthShowing = false;
  void _maybeReauth() {
    if (!_model.needsReauth || _reauthShowing || !mounted) return;
    _model.needsReauth = false;
    _reauthShowing = true;
    unawaited(
      _handleAuthPaused().whenComplete(() => _reauthShowing = false),
    );
  }

  /// A ticket moved somewhere (fired / settled / voided on another device)
  /// — refresh the waiter's held-ticket strip immediately (the natives'
  /// `LaunchedEffect(model.ticketTick) { loadOpenTickets() }`).
  void _onTicketTick() {
    if (_model.isWaiter) unawaited(_model.loadOpenTickets());
  }

  // ── sheet launchers ────────────────────────────────────────────────────────
  /// Item customization (add mode, or edit mode seeded from [editLine]).
  Future<void> _openItemDetail(
    MenuItemView item, {
    CartLineView? editLine,
  }) async {
    final addons = await _model.loadItemAddons(item.id);
    if (!mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      builder: (_) => ItemDetailSheet(
        model: _model,
        item: item,
        addons: addons,
        editLine: editLine,
      ),
    );
  }

  /// Re-open the customization sheet for a configured cart line.
  Future<void> _editCartLine(CartLineView line) async {
    final item = _model.menuItemById(line.itemId);
    if (item == null) return;
    await _openItemDetail(item, editLine: line);
  }

  Future<void> _openBundleDetail(BundleView bundle) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => BundleDetailSheet(model: _model, bundle: bundle),
    );
  }

  /// Waiter firing a NEW ticket → collect dine-in details first; adding a
  /// round to the selected ticket fires straight away. Cashiers get the
  /// shared tender drawer; a placed order clears the cart in the core, so
  /// reload after the sheet closes either way.
  Future<void> _checkout() async {
    if (!_model.isWaiter) {
      await showMadarSheet<ReceiptView>(
        context,
        size: SheetSize.large,
        builder: (_) => TenderSheet(
          core: widget.core,
          onStateChanged: widget.onStateChanged,
        ),
      );
      await _model.loadCart();
      // A placed order moves the shift totals — refresh the top-bar pill.
      await _model.loadShiftStats();
      return;
    }
    if (_model.activeTicketId == null) {
      await showMadarSheet<void>(
        context,
        size: SheetSize.hug,
        maxWidth: Responsive.sheetCompactMaxWidth,
        builder: (_) => FireDetailsSheet(model: _model),
      );
    } else {
      await _model.fireOrAddRound();
    }
  }

  /// Close shift — pushed over the order surface like the natives' overlay;
  /// on success the shell's route machine takes over.
  Future<void> _closeShift() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloseShiftScreen(
          core: widget.core,
          onStateChanged: widget.onStateChanged,
        ),
      ),
    );
  }

  /// Sync parked on a 401 → the auth-paused banner opens the re-auth sheet:
  /// the SAME teller re-enters their PIN to un-park the outbox (natives:
  /// AuthPausedBanner → ReauthScreen). Resumed → refresh the sync chrome +
  /// success toast; the switch-teller escape routes into close-shift.
  Future<void> _handleAuthPaused() async {
    final outcome = await showReauthSheet(
      context,
      core: widget.core,
      onStateChanged: widget.onStateChanged,
    );
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case ReauthOutcome.resumed:
        await _model.refreshConnectivity();
        _model.showToast(
          _model.tr('chrome.sync_resumed'),
          tone: ChipTone.success,
          icon: 'checkmark.circle',
        );
      case ReauthOutcome.switchTeller:
        await _closeShift();
    }
  }

  /// Narrow layout: the cart lives in a bottom drawer.
  Future<void> _openCartSheet() async {
    await showMadarSheet<void>(
      context,
      builder: (_) => ListenableBuilder(
        listenable: _model,
        builder: (context, _) => _buildCartPanel(
          context,
          onClose: () => unawaited(Navigator.of(context).maybePop()),
        ),
      ),
    );
  }

  /// Hardware-keyboard shortcut (desktop): Ctrl/⌘+Enter checks out a
  /// non-empty cart.
  void _shortcutCheckout() {
    if (_model.cartLines.isEmpty) return;
    unawaited(_checkout());
  }

  // ── build ──────────────────────────────────────────────────────────────────
  Widget _buildCartPanel(BuildContext context, {VoidCallback? onClose}) {
    final isWaiter = _model.isWaiter;
    final checkoutLabel = !isWaiter
        ? _model.tr('order.checkout')
        : _model.activeTicketId != null
        ? _model.tr('waiter.add_round')
        : _model.tr('waiter.fire');
    return CartPanel(
      model: _model,
      checkoutLabel: checkoutLabel,
      checkoutIcon: isWaiter ? 'arrow.up.circle' : 'creditcard',
      checkoutEnabled: true,
      onCheckout: () {
        onClose?.call();
        unawaited(_checkout());
      },
      onEditLine: (line) => unawaited(_editCartLine(line)),
      onClose: onClose,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    // No screen-wide ListenableBuilder: each region (top bar + banners,
    // catalog, cart, toast host) listens on its own, so a controller notify
    // (heartbeat, cart mutation, toast) rebuilds only what reads it — and
    // search keystrokes stay inside CatalogColumn entirely.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _shortcutCheckout,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            _shortcutCheckout,
      },
      child: Focus(
        autofocus: true,
        // Scaffold: text fields, ink, and text styling need a Material
        // ancestor — every screen owns its own Scaffold in this app.
        child: Scaffold(
          backgroundColor: colors.bg,
          body: SafeArea(
            child: Stack(
              children: [
                ResponsiveBuilder(
                  builder: (context, info) => Column(
                    children: [
                      ListenableBuilder(
                        listenable: _model,
                        builder: (context, _) => Column(
                          children: [
                            _OrderTopBar(
                              model: _model,
                              wide: info.isWide,
                              onOpenSync: widget.onOpenSync,
                              onCloseShift: _model.isWaiter
                                  ? null
                                  : () => unawaited(_closeShift()),
                            ),
                            _ChromeBanners(
                              model: _model,
                              onAuthPausedTap: () =>
                                  unawaited(_handleAuthPaused()),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: info.isWide
                            ? Row(
                                children: [
                                  Expanded(child: _buildCatalog()),
                                  Container(
                                    width: 1,
                                    color: colors.border,
                                  ),
                                  SizedBox(
                                    width: kCartPanelWidth,
                                    child: ListenableBuilder(
                                      listenable: _model,
                                      builder: (context, _) =>
                                          _buildCartPanel(context),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  Expanded(child: _buildCatalog()),
                                  ListenableBuilder(
                                    listenable: _model,
                                    builder: (context, _) => CartBar(
                                      model: _model,
                                      onOpen: () => unawaited(_openCartSheet()),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                // Toasts float above everything on this screen.
                ListenableBuilder(
                  listenable: _model,
                  builder: (context, _) => ToastHost(
                    _model.toast,
                    onAction: _model.runToastAction,
                    onDismiss: _model.dismissToast,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCatalog() {
    // The catalog listens on the model here (menu, badges, styles); its
    // search text + selected category live INSIDE CatalogColumn so a
    // keystroke never reaches the cart panel or top bar.
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) => CatalogColumn(
        key: _catalogKey,
        model: _model,
        onItemTap: (item) => unawaited(_openItemDetail(item)),
        onBundleTap: (bundle) => unawaited(_openBundleDetail(bundle)),
      ),
    );
  }
}

// ── Top status bar ─────────────────────────────────────────────────────────────

class _OrderTopBar extends StatelessWidget {
  const _OrderTopBar({
    required this.model,
    required this.wide,
    this.onCloseShift,
    this.onOpenSync,
  });

  final OrderController model;
  final bool wide;

  /// Cashier-only: opens the close-shift overlay (null hides the action —
  /// waiters don't own the drawer). The full nav chrome lands in M6.
  final VoidCallback? onCloseShift;

  /// Opens the sync center from the status chip (null = chip is inert).
  final VoidCallback? onOpenSync;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final shift = model.shift;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
              vertical: Space.md,
            ),
            child: Row(
              children: [
                // Status — teller + live shift totals (wide) + sync state;
                // the shell owns the rest of the nav chrome.
                if (!model.isWaiter && wide && shift != null) ...[
                  StatusChip(
                    label: shift.tellerName,
                    tone: ChipTone.info,
                    icon: 'person.fill',
                  ),
                  if (shift.isOpen) ...[
                    const SizedBox(width: Space.sm),
                    _ShiftStatsPill(model: model),
                  ],
                ],
                const Spacer(),
                _SyncChip(model: model, onTap: onOpenSync),
                const SizedBox(width: Space.sm),
                _SyncDataButton(model: model),
                if (onCloseShift != null) ...[
                  const SizedBox(width: Space.sm),
                  TactileScale(
                    onTap: onCloseShift,
                    child: Tooltip(
                      message: model.tr('order.close_shift'),
                      child: Padding(
                        padding: const EdgeInsets.all(Space.xs),
                        child: MadarIcon(
                          'lock',
                          tint: colors.textSecondary,
                          size: IconSize.lg,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(height: 1, color: colors.border),
        ],
      ),
    );
  }
}

/// Live shift totals — "EGP X · N orders" (voided excluded, summed in the
/// core). Mirror of the natives' ShiftStatsPill.
class _ShiftStatsPill extends StatelessWidget {
  const _ShiftStatsPill({required this.model});

  final OrderController model;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: colors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Money.format(model.shiftSalesMinor, currency: model.currency),
            textDirection: TextDirection.ltr,
            style: MadarType.labelSm.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: Space.xs),
          Text(
            '·',
            style: MadarType.labelSm.copyWith(color: colors.textMuted),
          ),
          const SizedBox(width: Space.xs),
          Text(
            '${model.shiftOrderCount} ${model.tr('chrome.orders')}',
            style: MadarType.labelSm.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sync status chip — offline / stuck / syncing; hidden when idle + fully
/// synced. Tappable into the sync center when [onTap] is wired (natives'
/// SyncChip jumps straight to the outbox).
class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.model, this.onTap});

  final OrderController model;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = switch ((
      model.isOnline,
      model.syncFailed,
      model.pendingCount,
    )) {
      (false, _, final pending) => (
        pending > 0
            ? '${model.tr('chrome.offline')} · $pending ${model.tr('chrome.queued')}'
            : model.tr('chrome.offline'),
        ChipTone.warning,
        'exclamationmark.triangle',
      ),
      (true, final failed, _) when failed > 0 => (
        '${model.tr('chrome.needs_attention')} ($failed)',
        ChipTone.danger,
        'exclamationmark.triangle',
      ),
      (true, _, final pending) when pending > 0 => (
        '${model.tr('chrome.syncing')} ($pending)',
        ChipTone.warning,
        'arrow.triangle.2.circlepath',
      ),
      _ => null,
    };
    if (state == null) return const SizedBox.shrink();
    final (label, tone, icon) = state;
    final chip = StatusChip(label: label, tone: tone, icon: icon);
    final onTap = this.onTap;
    if (onTap == null) return chip;
    return TactileScale(
      onTap: () {
        MadarHaptics.impact();
        onTap();
      },
      child: chip,
    );
  }
}

/// Manual "sync server data" — re-pulls the catalog. Spins + disables while
/// running.
class _SyncDataButton extends StatelessWidget {
  const _SyncDataButton({required this.model});

  final OrderController model;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final box = Container(
      width: kSquareControl,
      height: kSquareControl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: colors.borderLight),
      ),
      child: model.isSyncingData
          ? SizedBox.square(
              dimension: IconSize.md,
              child: CircularProgressIndicator(
                color: colors.accent,
                strokeWidth: 2,
              ),
            )
          : MadarIcon('arrow.triangle.2.circlepath', tint: colors.textMuted),
    );
    if (model.isSyncingData) return box;
    return Semantics(
      button: true,
      label: model.tr('chrome.sync_data'),
      child: TactileScale(
        onTap: () {
          MadarHaptics.impact();
          unawaited(model.refreshServerData());
        },
        child: box,
      ),
    );
  }
}

// ── Connectivity / error chrome ────────────────────────────────────────────────

class _ChromeBanners extends StatelessWidget {
  const _ChromeBanners({required this.model, required this.onAuthPausedTap});

  final OrderController model;

  /// Sync parked on a 401 → open the re-auth sheet (the same teller
  /// re-enters their PIN to un-park the outbox).
  final VoidCallback onAuthPausedTap;

  @override
  Widget build(BuildContext context) {
    final error = model.error;
    final skew = model.clockSkewMinutes.abs();
    const pad = EdgeInsetsDirectional.symmetric(
      horizontal: Space.lg,
      vertical: Space.sm,
    );
    return Column(
      children: [
        if (!model.isOnline)
          Padding(
            padding: pad,
            child: NoticeBanner(
              text: model.tr('chrome.offline_banner'),
              icon: 'wifi.slash',
            ),
          ),
        if (model.syncAuthPaused)
          Padding(
            padding: pad,
            child: NoticeBanner(
              text: model.tr('chrome.auth_paused'),
              tone: ChipTone.danger,
              icon: 'lock',
              onTap: onAuthPausedTap,
              trailing: BannerActionPill(
                label: model.tr('chrome.auth_paused_action'),
              ),
            ),
          ),
        if (skew >= 5)
          Padding(
            padding: pad,
            child: NoticeBanner(
              text: '${model.tr('chrome.clock_skew')} (${skew}m)',
              icon: 'clock.badge.exclamationmark',
            ),
          ),
        if (error != null)
          Padding(
            padding: pad,
            child: NoticeBanner(
              text: error,
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
              onTap: model.clearError,
            ),
          ),
      ],
    );
  }
}
