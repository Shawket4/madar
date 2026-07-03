import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_order/src/bundle_detail_sheet.dart';
import 'package:feature_order/src/cart_panel.dart';
import 'package:feature_order/src/catalog_column.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/waiter_sheets.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:feature_shift/feature_shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The order screen — the heart of the POS. Browse the branch-effective
/// catalog (offline-safe) and build a cart: tap an item to customize + add,
/// adjust quantities, see live totals. On wide layouts (≥760) the cart is a
/// column beside the grid; on narrow ones it's a bottom bar that opens a
/// drawer. In waiter mode the cart's terminal action FIRES a ticket (or
/// adds a round) instead of tendering. Mirror of the Kotlin OrderScreen.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key});

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  Timer? _heartbeat;

  /// Keeps the catalog's search/category state alive when the responsive
  /// layout flips the column between the wide Row and the narrow Column.
  final GlobalKey _catalogKey = GlobalKey();

  /// A re-auth request is being presented — the once-per-bump guard so a
  /// second bump can't double-present the sheet.
  bool _reauthShowing = false;

  OrderNotifier get _notifier => ref.read(orderProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Post-frame: notifier writes during initState land mid-build (crash).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_notifier.init());
    });
    // Connectivity heartbeat — refresh online + sync chrome every 15s; a
    // waiter board also re-polls its open tickets (safety net under the
    // shell-owned realtime session).
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_notifier.refreshConnectivity());
      if (ref.read(orderProvider).isWaiter) {
        unawaited(_notifier.loadOpenTickets());
      }
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }

  /// A bridge call 401'd with a live session (expired/missing bearer) —
  /// open the re-auth sheet once per [reauthRequestProvider] bump; the
  /// guard clears when the flow completes so a later bump re-presents.
  void _onReauthRequest() {
    if (_reauthShowing || !mounted) return;
    _reauthShowing = true;
    unawaited(
      _handleAuthPaused().whenComplete(() => _reauthShowing = false),
    );
  }

  // ── sheet launchers ────────────────────────────────────────────────────────
  /// Item customization (add mode, or edit mode seeded from [editLine]).
  Future<void> _openItemDetail(
    MenuItemView item, {
    CartLineView? editLine,
  }) async {
    final addons = await _notifier.loadItemAddons(item.id);
    if (!mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      builder: (_) => ItemDetailSheet(
        item: item,
        addons: addons,
        editLine: editLine,
      ),
    );
  }

  /// Re-open the customization sheet for a configured cart line.
  Future<void> _editCartLine(CartLineView line) async {
    final item = ref.read(orderProvider).menuItemById(line.itemId);
    if (item == null) return;
    await _openItemDetail(item, editLine: line);
  }

  Future<void> _openBundleDetail(BundleView bundle) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => BundleDetailSheet(bundle: bundle),
    );
  }

  /// Waiter firing a NEW ticket → collect dine-in details first; adding a
  /// round to the selected ticket fires straight away. Cashiers get the
  /// shared tender drawer; a placed order clears the cart in the core, so
  /// reload after the sheet closes either way.
  Future<void> _checkout() async {
    final state = ref.read(orderProvider);
    if (!state.isWaiter) {
      await showMadarSheet<ReceiptView>(
        context,
        size: SheetSize.large,
        builder: (_) => const TenderSheet(),
      );
      await _notifier.loadCart();
      // A placed order moves the shift totals — refresh the top-bar pill.
      await _notifier.loadShiftStats();
      return;
    }
    if (state.activeTicketId == null) {
      await showMadarSheet<void>(
        context,
        size: SheetSize.hug,
        maxWidth: Responsive.sheetCompactMaxWidth,
        builder: (_) => const FireDetailsSheet(),
      );
    } else {
      await _notifier.fireOrAddRound();
    }
  }

  /// Close shift — pushed over the order surface like the natives' overlay;
  /// on success the shell's route machine takes over.
  Future<void> _closeShift() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CloseShiftScreen()),
    );
  }

  /// The sync center (outbox) — opened from the top-bar sync status chip
  /// like the natives' SyncChip.
  Future<void> _openSync() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SyncScreen()),
    );
  }

  /// Sync parked on a 401 → the auth-paused banner opens the re-auth sheet:
  /// the SAME teller re-enters their PIN to un-park the outbox (natives:
  /// AuthPausedBanner → ReauthScreen). Resumed → refresh the sync chrome +
  /// success toast; the switch-teller escape routes into close-shift.
  Future<void> _handleAuthPaused() async {
    final outcome = await showReauthSheet(context);
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case ReauthOutcome.resumed:
        await _notifier.refreshConnectivity();
        _notifier.showToast(
          ref.read(bridgeProvider).tr(key: 'chrome.sync_resumed'),
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
      builder: (sheetContext) => CartPanel(
        onCheckout: () {
          unawaited(Navigator.of(sheetContext).maybePop());
          unawaited(_checkout());
        },
        onEditLine: (line) => unawaited(_editCartLine(line)),
        onClose: () => unawaited(Navigator.of(sheetContext).maybePop()),
      ),
    );
  }

  /// Hardware-keyboard shortcut (desktop): Ctrl/⌘+Enter checks out a
  /// non-empty cart.
  void _shortcutCheckout() {
    if (ref.read(orderProvider).cartLines.isEmpty) return;
    unawaited(_checkout());
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    ref
      // A ticket moved somewhere (fired / settled / voided on another
      // device) — refresh the waiter's held-ticket strip immediately (the
      // natives' `LaunchedEffect(model.ticketTick) { loadOpenTickets() }`).
      ..listen(ticketTickProvider, (_, _) {
        if (ref.read(orderProvider).isWaiter) {
          unawaited(_notifier.loadOpenTickets());
        }
      })
      // A layer caught a 401 with a live session — present the re-auth
      // sheet once per bump.
      ..listen(reauthRequestProvider, (_, _) => _onReauthRequest())
      // Locale switched (Settings) — re-resolve the catalog so item / addon
      // names flip to the new language's translations. The core resolves
      // from the `*_translations` jsonb at read time, so a fresh
      // loadCatalog() is all it takes.
      ..listen(localeProvider.select((s) => s.locale), (_, _) {
        unawaited(_notifier.loadCatalog());
      });

    final isWaiter = ref.watch(orderProvider.select((s) => s.isWaiter));
    // Each region below watches its own narrow slice, so a notify
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
          body: Stack(
            children: [
              ResponsiveBuilder(
                builder: (context, info) => Column(
                  children: [
                    // Edge-to-edge: the top bar's surface paints to y=0 and
                    // owns the status-bar inset — no SafeArea above it.
                    _OrderTopBar(
                      wide: info.isWide,
                      onOpenSync: () => unawaited(_openSync()),
                      onCloseShift: isWaiter
                          ? null
                          : () => unawaited(_closeShift()),
                    ),
                    Expanded(
                      child: SafeArea(
                        top: false,
                        child: Column(
                          children: [
                            _ChromeBanners(
                              onAuthPausedTap: () =>
                                  unawaited(_handleAuthPaused()),
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
                                          child: CartPanel(
                                            onCheckout: () =>
                                                unawaited(_checkout()),
                                            onEditLine: (line) => unawaited(
                                              _editCartLine(line),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        Expanded(child: _buildCatalog()),
                                        CartBar(
                                          onOpen: () =>
                                              unawaited(_openCartSheet()),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Toasts float above everything on this screen.
              const SafeArea(child: _OrderToastHost()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCatalog() {
    // The catalog watches its own provider slices (menu, badges, styles);
    // its search text + selected category live INSIDE CatalogColumn so a
    // keystroke never reaches the cart panel or top bar.
    return CatalogColumn(
      key: _catalogKey,
      onItemTap: (item) => unawaited(_openItemDetail(item)),
      onBundleTap: (bundle) => unawaited(_openBundleDetail(bundle)),
    );
  }
}

/// Toast presenter scoped to its own watch, so a toast never rebuilds the
/// grid or cart.
class _OrderToastHost extends ConsumerWidget {
  const _OrderToastHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(orderProvider.select((s) => s.toast));
    final notifier = ref.read(orderProvider.notifier);
    return ToastHost(
      toast,
      onAction: notifier.runToastAction,
      onDismiss: notifier.dismissToast,
    );
  }
}

// ── Top status bar ─────────────────────────────────────────────────────────────

/// The order surface's own chrome bar (the root POS surface keeps its bar;
/// pushed routes use MadarHeader). Paints its surface all the way to y=0 —
/// the natives' status-bar-tinted bar — with the top inset INSIDE.
class _OrderTopBar extends ConsumerWidget {
  const _OrderTopBar({
    required this.wide,
    required this.onOpenSync,
    this.onCloseShift,
  });

  final bool wide;

  /// Opens the sync center from the status chip.
  final VoidCallback onOpenSync;

  /// Cashier-only: opens the close-shift overlay (null hides the action —
  /// waiters don't own the drawer).
  final VoidCallback? onCloseShift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final isWaiter = ref.watch(orderProvider.select((s) => s.isWaiter));
    final shift = ref.watch(orderProvider.select((s) => s.shift));
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              top: topInset + Space.md,
              bottom: Space.md,
              start: Space.lg,
              end: Space.lg,
            ),
            child: Row(
              children: [
                // Status — teller + live shift totals (wide) + sync state;
                // the shell owns the rest of the nav chrome.
                if (!isWaiter && wide && shift != null) ...[
                  StatusChip(
                    label: shift.tellerName,
                    tone: ChipTone.info,
                    icon: 'person.fill',
                  ),
                  if (shift.isOpen) ...[
                    const SizedBox(width: Space.sm),
                    const _ShiftStatsPill(),
                  ],
                ],
                const Spacer(),
                _SyncChip(onTap: onOpenSync),
                const SizedBox(width: Space.sm),
                const _SyncDataButton(),
                if (onCloseShift != null) ...[
                  const SizedBox(width: Space.sm),
                  TactileScale(
                    onTap: onCloseShift,
                    child: Tooltip(
                      message: bridge.tr(key: 'order.close_shift'),
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
class _ShiftStatsPill extends ConsumerWidget {
  const _ShiftStatsPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final (salesMinor, orderCount, currency) = ref.watch(
      orderProvider.select(
        (s) => (s.shiftSalesMinor, s.shiftOrderCount, s.currency),
      ),
    );
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
            Money.format(salesMinor, currency: currency),
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
            '$orderCount ${bridge.tr(key: 'chrome.orders')}',
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
/// synced. Tapping it jumps straight to the sync center (the natives'
/// SyncChip → outbox).
class _SyncChip extends ConsumerWidget {
  const _SyncChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final (isOnline, syncFailed, pendingCount) = ref.watch(
      orderProvider.select((s) => (s.isOnline, s.syncFailed, s.pendingCount)),
    );
    final state = switch ((isOnline, syncFailed, pendingCount)) {
      (false, _, final pending) => (
        pending > 0
            ? '${bridge.tr(key: 'chrome.offline')} · $pending '
                  '${bridge.tr(key: 'chrome.queued')}'
            : bridge.tr(key: 'chrome.offline'),
        ChipTone.warning,
        'exclamationmark.triangle',
      ),
      (true, final failed, _) when failed > 0 => (
        '${bridge.tr(key: 'chrome.needs_attention')} ($failed)',
        ChipTone.danger,
        'exclamationmark.triangle',
      ),
      (true, _, final pending) when pending > 0 => (
        '${bridge.tr(key: 'chrome.syncing')} ($pending)',
        ChipTone.warning,
        'arrow.triangle.2.circlepath',
      ),
      _ => null,
    };
    if (state == null) return const SizedBox.shrink();
    final (label, tone, icon) = state;
    return TactileScale(
      onTap: () {
        MadarHaptics.impact();
        onTap();
      },
      child: StatusChip(label: label, tone: tone, icon: icon),
    );
  }
}

/// Manual "sync server data" — re-pulls the catalog. Spins + disables while
/// running.
class _SyncDataButton extends ConsumerWidget {
  const _SyncDataButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final isSyncing = ref.watch(orderProvider.select((s) => s.isSyncingData));
    final box = Container(
      width: kSquareControl,
      height: kSquareControl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: colors.borderLight),
      ),
      child: isSyncing
          ? SizedBox.square(
              dimension: IconSize.md,
              child: CircularProgressIndicator(
                color: colors.accent,
                strokeWidth: 2,
              ),
            )
          : MadarIcon('arrow.triangle.2.circlepath', tint: colors.textMuted),
    );
    if (isSyncing) return box;
    return Semantics(
      button: true,
      label: bridge.tr(key: 'chrome.sync_data'),
      child: TactileScale(
        onTap: () {
          MadarHaptics.impact();
          unawaited(ref.read(orderProvider.notifier).refreshServerData());
        },
        child: box,
      ),
    );
  }
}

// ── Connectivity / error chrome ────────────────────────────────────────────────

class _ChromeBanners extends ConsumerWidget {
  const _ChromeBanners({required this.onAuthPausedTap});

  /// Sync parked on a 401 → open the re-auth sheet (the same teller
  /// re-enters their PIN to un-park the outbox).
  final VoidCallback onAuthPausedTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final (isOnline, authPaused, skewMinutes, error) = ref.watch(
      orderProvider.select(
        (s) => (s.isOnline, s.syncAuthPaused, s.clockSkewMinutes, s.error),
      ),
    );
    final skew = skewMinutes.abs();
    const pad = EdgeInsetsDirectional.symmetric(
      horizontal: Space.lg,
      vertical: Space.sm,
    );
    return Column(
      children: [
        if (!isOnline)
          Padding(
            padding: pad,
            child: NoticeBanner(
              text: bridge.tr(key: 'chrome.offline_banner'),
              icon: 'wifi.slash',
            ),
          ),
        if (authPaused)
          Padding(
            padding: pad,
            child: NoticeBanner(
              text: bridge.tr(key: 'chrome.auth_paused'),
              tone: ChipTone.danger,
              icon: 'lock',
              onTap: onAuthPausedTap,
              trailing: BannerActionPill(
                label: bridge.tr(key: 'chrome.auth_paused_action'),
              ),
            ),
          ),
        if (skew >= 5)
          Padding(
            padding: pad,
            child: NoticeBanner(
              text: '${bridge.tr(key: 'chrome.clock_skew')} (${skew}m)',
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
              onTap: ref.read(orderProvider.notifier).clearError,
            ),
          ),
      ],
    );
  }
}
