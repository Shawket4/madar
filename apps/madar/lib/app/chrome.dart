import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/feature_history.dart';
import 'package:feature_incoming/feature_incoming.dart';
import 'package:feature_order/feature_order.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:feature_shift/feature_shift.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:madar/app/notifications.dart';
import 'package:madar/spike_screen.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Rail width — the natives' NavRailWidth (80dp).
const double _railWidth = 80;

/// Chrome-owned rendered state: the transient toast and the tick values
/// already acknowledged by the teller (the rail badge pulses only for
/// unseen incoming activity).
class ChromeState {
  const ChromeState({this.toast, this.seenDelivery = 0, this.seenTicket = 0});

  final ToastData? toast;
  final int seenDelivery;
  final int seenTicket;

  static const Object _keep = Object();

  ChromeState copyWith({
    Object? toast = _keep,
    int? seenDelivery,
    int? seenTicket,
  }) {
    return ChromeState(
      toast: identical(toast, _keep) ? this.toast : toast as ToastData?,
      seenDelivery: seenDelivery ?? this.seenDelivery,
      seenTicket: seenTicket ?? this.seenTicket,
    );
  }
}

class ChromeNotifier extends Notifier<ChromeState> {
  Timer? _toastTimer;

  @override
  ChromeState build() {
    ref.onDispose(() => _toastTimer?.cancel());
    return const ChromeState();
  }

  /// Show a transient toast — auto-dismisses after 2.6s (the natives'
  /// toast lifetime).
  void showToast(
    String text, {
    ChipTone tone = ChipTone.accent,
    String icon = 'bell',
    String? actionLabel,
    bool sticky = false,
  }) {
    state = state.copyWith(
      toast: ToastData(
        id: DateTime.now().millisecondsSinceEpoch,
        text: text,
        tone: tone,
        icon: icon,
        actionLabel: actionLabel,
        sticky: sticky,
      ),
    );
    _toastTimer?.cancel();
    if (sticky) return;
    _toastTimer = Timer(const Duration(milliseconds: 2600), dismissToast);
  }

  void dismissToast() {
    _toastTimer?.cancel();
    if (state.toast != null) state = state.copyWith(toast: null);
  }

  /// Stamp the current tick values as seen — clears the rail badge.
  void markIncomingSeen() {
    state = state.copyWith(
      seenDelivery: ref.read(deliveryTickProvider),
      seenTicket: ref.read(ticketTickProvider),
    );
    // Viewing Incoming acknowledges the alert — the sticky toast goes too.
    dismissToast();
  }
}

final chromeProvider = NotifierProvider<ChromeNotifier, ChromeState>(
  ChromeNotifier.new,
);

/// The persistent chrome around the ORDER surface: the natives' leading
/// side rail (sections of icon+label tiles, system footer, More sheet),
/// plus the app-level alert toast + chime driven by the realtime stream.
/// Wide layouts only — narrow keeps the bare surface (the natives' phone
/// drawer is an M7 polish item; this POS ships landscape-first).
///
/// No blanket SafeArea here: the rail pads itself with the status-bar
/// inset (its surface paints to y=0) and the order surface owns its own
/// top inset.
class MadarChrome extends ConsumerStatefulWidget {
  const MadarChrome({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<MadarChrome> createState() => _MadarChromeState();
}

class _MadarChromeState extends ConsumerState<MadarChrome> {
  // Prefix cleared: AssetSource prepends 'assets/' by default, which broke
  // the design_system package path (silent chime). The bundled key is
  // 'packages/design_system/assets/sounds/new_order.wav' verbatim.
  final _player = AudioPlayer()..audioCache = AudioCache(prefix: '');
  NotificationService? _notifications;

  @override
  void initState() {
    super.initState();
    // OS notifications for the realtime channel (the natives' RealtimePlayer
    // OS-notification tier). Async init — the in-app toast + chime work
    // immediately; a notification that arrives before init just skips.
    unawaited(
      NotificationService.initialize().then((s) {
        if (mounted) _notifications = s;
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  String _t(String key) => ref.read(bridgeProvider).tr(key: key);

  /// Core-raised alert: localized text decided in Rust; the shell renders
  /// an in-app toast + chime + haptic AND posts an OS notification for
  /// notify (so it surfaces when the app is backgrounded, like the natives'
  /// RealtimePlayer); chime-only for ping, haptic-only for haptic.
  void _onAlert(AlertCommand cmd) {
    switch (cmd) {
      case AlertCommand_Notify(:final title, :final body, :final tag):
        // Sticky: a new order deserves attention until the teller actually
        // looks — it clears on markIncomingSeen (Incoming opened), not on a
        // timer. The View action jumps straight there.
        ref
            .read(chromeProvider.notifier)
            .showToast(
              body.isEmpty ? title : '$title — $body',
              actionLabel: ref.read(bridgeProvider).tr(key: 'chrome.view'),
              sticky: true,
            );
        _chime();
        MadarHaptics.impact();
        unawaited(_notifications?.post(title: title, body: body, tag: tag));
      case AlertCommand_Ping():
        _chime();
      case AlertCommand_Haptic():
        MadarHaptics.success();
    }
  }

  void _chime() {
    unawaited(
      _player.play(
        AssetSource('packages/design_system/assets/sounds/new_order.wav'),
      ),
    );
  }

  void _push(Widget Function() build) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => build()),
      ),
    );
  }

  List<_RailSection> _sections({
    required String? role,
    required bool incomingHasNew,
    int incomingRing = 0,
  }) {
    // A waiter's tickets live in the cart strip — the rail keeps only the
    // system footer for them, exactly like the natives.
    if (role == 'waiter') return const [];
    return [
      _RailSection(_t('nav.section.orders'), [
        _RailDest(
          'bicycle',
          _t('nav.incoming'),
          hasNew: incomingHasNew,
          ring: incomingRing,
          onTap: () {
            ref.read(chromeProvider.notifier).markIncomingSeen();
            _push(() => const IncomingScreen());
          },
        ),
        _RailDest(
          'tray.full',
          _t('drafts.title'),
          onTap: () => _push(() => const DraftsScreen()),
        ),
        _RailDest(
          'list.bullet.rectangle',
          _t('nav.history'),
          onTap: () => _push(() => const OrderHistoryScreen()),
        ),
        _RailDest(
          'magnifyingglass',
          _t('search.title'),
          onTap: () => _push(() => const OrderSearchScreen()),
        ),
      ]),
      _RailSection(_t('nav.section.money'), [
        _RailDest(
          'banknote',
          _t('cash.title'),
          onTap: () => _push(() => const CashMovementsScreen()),
        ),
        _RailDest(
          'clock.arrow.circlepath',
          _t('shifts.title'),
          onTap: () => _push(() => const ShiftHistoryScreen()),
        ),
        _RailDest(
          'printer',
          _t('shift.print_report'),
          onTap: () => unawaited(
            showMadarSheet<void>(
              context,
              builder: (_) => const ShiftReportSheet(),
            ),
          ),
        ),
      ]),
    ];
  }

  _RailSection _footer() {
    return _RailSection(_t('nav.section.system'), [
      _RailDest(
        'arrow.triangle.2.circlepath',
        _t('sync.title'),
        onTap: () => _push(() => const SyncScreen()),
      ),
      _RailDest(
        'gearshape',
        _t('settings.title'),
        onTap: () => _push(() => const SettingsScreen()),
      ),
      _RailDest('ellipsis', _t('chrome.more'), onTap: _openMore),
    ]);
  }

  /// The wide layouts' More sheet — only the overflow rows (the rail
  /// carries the sections there).
  Future<void> _openMore() async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) =>
          _moreContent(sheetContext, includeSections: false),
    );
  }

  /// The narrow layouts' nav drawer — the natives' phone drawer: every
  /// rail section plus the overflow rows, sliding from the start edge.
  Future<void> _openMoreDrawer() async {
    await showMadarDrawer<void>(
      context,
      builder: (drawerContext) =>
          _moreContent(drawerContext, includeSections: true),
    );
  }

  /// The shared More menu body. [presContext] is the presenting route's
  /// context (sheet or drawer) — rows pop it before navigating.
  Widget _moreContent(
    BuildContext presContext, {
    required bool includeSections,
  }) {
    // A snapshot for the surface's lifetime — the rows only carry
    // glyph/label/onTap, so badge state is irrelevant here.
    final sections = includeSections
        ? [
            ..._sections(
              role: ref.read(shellProvider).session?.role,
              incomingHasNew: false,
            ),
            _footer(),
          ]
        : const <_RailSection>[];
    final moreLabel = _t('chrome.more');
    return Builder(
      builder: (sheetContext) {
        final colors = sheetContext.madarColors;
        Widget row(
          String glyph,
          String label, {
          required VoidCallback onTap,
          Color? tone,
        }) {
          return TactileScale(
            onTap: () {
              unawaited(Navigator.of(sheetContext).maybePop());
              onTap();
            },
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: Row(
                children: [
                  MadarIcon(
                    glyph,
                    tint: tone ?? colors.textSecondary,
                    size: IconSize.xl,
                  ),
                  const SizedBox(width: Space.md),
                  Text(
                    label,
                    style: MadarType.title.copyWith(
                      color: tone ?? colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final sectionRows = <Widget>[
          if (includeSections)
            for (final section in sections) ...[
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: Space.lg,
                  top: Space.md,
                  bottom: Space.xs,
                ),
                child: Text(
                  section.title.toUpperCase(),
                  style: MadarType.labelSm.copyWith(
                    letterSpacing: MadarType.tracking,
                    color: colors.textMuted,
                  ),
                ),
              ),
              for (final d in section.items)
                if (d.label != moreLabel) row(d.glyph, d.label, onTap: d.onTap),
            ],
          if (includeSections) Divider(height: 1, color: colors.borderLight),
        ];
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...sectionRows,
                row(
                  'fork.knife',
                  _t('waiter.title'),
                  onTap: () => _push(() => const OpenTicketsScreen()),
                ),
                // Dev harnesses — debug builds only, so the hardcoded
                // labels never reach a teller.
                if (kDebugMode) ...[
                  row(
                    'biotech',
                    'Core spike (dev)',
                    onTap: () => _push(SpikeScreen.new),
                  ),
                  row(
                    'paintpalette',
                    'Design gallery (dev)',
                    onTap: () => _push(GalleryScreen.new),
                  ),
                ],
                Divider(height: 1, color: colors.borderLight),
                row(
                  'lock',
                  _t('order.close_shift'),
                  tone: colors.danger,
                  onTap: () => _push(() => const CloseShiftScreen()),
                ),
                row(
                  'rectangle.portrait.and.arrow.right',
                  _t('home.sign_out'),
                  tone: colors.danger,
                  onTap: () => unawaited(_signOut()),
                ),
                const SizedBox(height: Space.sm),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _signOut() async {
    // You can't sign out mid-shift — the natives guard BOTH exits
    // (OrderScreen.kt's More drawer and SettingsScreen), mirroring the
    // Flutter settings screen's own guard.
    final bridge = ref.read(bridgeProvider);
    ShiftView? shift;
    try {
      shift = await bridge.currentShift();
    } on Exception catch (_) {}
    if (!mounted) return;
    if (shift?.isOpen ?? false) {
      ref
          .read(chromeProvider.notifier)
          .showToast(
            _t('settings.sign_out_shift_open'),
            tone: ChipTone.danger,
            icon: 'lock',
          );
      return;
    }
    bridge.unsubscribeRealtime();
    try {
      await bridge.lanStop();
    } on Exception catch (_) {}
    try {
      await bridge.logout(wipeOutbox: false);
    } on Exception catch (_) {}
    ref.read(shellProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..listen(alertProvider, (_, next) {
        // The notifier pairs each command with a sequence counter so
        // identical consecutive commands still fire — only the command
        // matters here.
        final cmd = next?.$2;
        if (cmd != null) _onAlert(cmd);
      })
      // A screen's leading toggle (the order top bar on narrow layouts)
      // asked for the nav drawer — the shell owns and presents it.
      ..listen(navDrawerRequestProvider, (_, _) {
        unawaited(_openMoreDrawer());
      });
    final role = ref.watch(shellProvider.select((s) => s.session?.role));
    final deliveryTick = ref.watch(deliveryTickProvider);
    final ticketTick = ref.watch(ticketTickProvider);
    final seenDelivery = ref.watch(
      chromeProvider.select((s) => s.seenDelivery),
    );
    final seenTicket = ref.watch(chromeProvider.select((s) => s.seenTicket));
    final toast = ref.watch(chromeProvider.select((s) => s.toast));
    // Locale switches must re-resolve every rail string.
    ref.watch(localeProvider);
    final incomingHasNew =
        deliveryTick > seenDelivery || ticketTick > seenTicket;

    return ResponsiveBuilder(
      builder: (context, info) {
        final colors = context.madarColors;
        final rail = info.isWide
            ? _NavRail(
                sections: _sections(
                  role: role,
                  incomingHasNew: incomingHasNew,
                  // Every realtime order/ticket event bumps the sum, ringing
                  // the Incoming tile even while its badge is already lit.
                  incomingRing: deliveryTick + ticketTick,
                ),
                footer: _footer(),
              )
            : null;
        return Material(
          color: colors.bg,
          child: Stack(
            children: [
              Row(
                children: [
                  if (rail != null) ...[
                    SizedBox(width: _railWidth, child: rail),
                    Container(width: 1, color: colors.border),
                  ],
                  Expanded(child: widget.child),
                ],
              ),
              if (toast != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ToastHost(
                    toast,
                    onDismiss: (_) =>
                        ref.read(chromeProvider.notifier).dismissToast(),
                    // Only the sticky new-order alert carries an action —
                    // it jumps to Incoming (marking seen clears the toast).
                    onAction: () {
                      ref.read(chromeProvider.notifier).markIncomingSeen();
                      _push(() => const IncomingScreen());
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RailDest {
  const _RailDest(
    this.glyph,
    this.label, {
    required this.onTap,
    this.hasNew = false,
    this.ring = 0,
  });

  final String glyph;
  final String label;
  final bool hasNew;

  /// Monotonic counter; each increase rings the tile's glyph via [BellShake].
  final int ring;

  final VoidCallback onTap;
}

class _RailSection {
  const _RailSection(this.title, this.items);

  final String title;
  final List<_RailDest> items;
}

/// The rail surface — lockup mark, scrolling task sections, pinned system
/// footer. Anatomy from the natives' NavRail (80dp, 36dp tiles, 8sp
/// captions, pulsing accent badge). The chrome has no blanket SafeArea —
/// the rail owns its own top inset so its surface paints to y=0.
class _NavRail extends StatelessWidget {
  const _NavRail({required this.sections, required this.footer});

  final List<_RailSection> sections;
  final _RailSection footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: EdgeInsets.only(top: topInset + Space.sm, bottom: Space.sm),
        child: Column(
          children: [
            // The full brand lockup, alive: the recreated symbol (satellite
            // riding the ring, planet breathing) above the typed wordmark.
            const AnimatedBrandMark(symbolSize: 44, wordmarkWidth: 52),
            const SizedBox(height: Space.sm),
            _divider(colors),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Column(
                  children: [
                    for (final (i, section) in sections.indexed) ...[
                      _caption(
                        colors,
                        section.title,
                        top: i == 0 ? 0 : Space.sm,
                      ),
                      for (final d in section.items) _RailTile(dest: d),
                    ],
                  ],
                ),
              ),
            ),
            _divider(colors),
            _caption(colors, footer.title, top: 0),
            for (final d in footer.items) _RailTile(dest: d),
          ],
        ),
      ),
    );
  }

  Widget _divider(MadarColors colors) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Space.md,
      vertical: Space.xs,
    ),
    child: Container(height: 1, color: colors.borderLight),
  );

  Widget _caption(MadarColors colors, String title, {required double top}) =>
      Padding(
        padding: EdgeInsets.only(top: top, bottom: 2, left: 2, right: 2),
        child: Text(
          title.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: MadarType.labelSm.copyWith(
            fontSize: 8,
            letterSpacing: MadarType.tracking,
            color: colors.textMuted,
          ),
        ),
      );
}

class _RailTile extends StatelessWidget {
  const _RailTile({required this.dest});

  final _RailDest dest;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: dest.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: dest.hasNew ? colors.accentBg : colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: BellShake(
                      trigger: dest.ring,
                      child: MadarIcon(
                        dest.glyph,
                        tint: dest.hasNew
                            ? colors.accent
                            : colors.textSecondary,
                        size: IconSize.lg,
                      ),
                    ),
                  ),
                  if (dest.hasNew)
                    PositionedDirectional(
                      top: 3,
                      end: 3,
                      child: _PulsingDot(color: colors.accent),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                dest.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: MadarType.labelSm.copyWith(
                  fontSize: 9,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The natives' rail badge: an accent dot whose opacity breathes 1 ↔ 0.25.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
      lowerBound: 0.25,
    );
    unawaited(_pulse.repeat(reverse: true));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _pulse,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
