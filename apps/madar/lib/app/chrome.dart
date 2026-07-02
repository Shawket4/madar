import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/feature_history.dart';
import 'package:feature_incoming/feature_incoming.dart';
import 'package:feature_order/feature_order.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:feature_shift/feature_shift.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:madar/app/app_state.dart';
import 'package:madar/spike_screen.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Rail width — the natives' NavRailWidth (80dp).
const double _railWidth = 80;

/// The persistent chrome around the ORDER surface: the natives' leading
/// side rail (sections of icon+label tiles, system footer, More sheet),
/// plus the app-level alert toast + chime driven by the realtime stream.
/// Wide layouts only — narrow keeps the bare surface (the natives' phone
/// drawer is an M7 polish item; this POS ships landscape-first).
class MadarChrome extends StatefulWidget {
  const MadarChrome({required this.state, required this.child, super.key});

  final MadarAppState state;
  final Widget child;

  @override
  State<MadarChrome> createState() => _MadarChromeState();
}

class _MadarChromeState extends State<MadarChrome> {
  final _player = AudioPlayer();
  ToastData? _toast;
  Timer? _toastTimer;

  // Ticks already seen — the rail badge pulses only for unseen activity.
  int _seenDelivery = 0;
  int _seenTicket = 0;

  MadarAppState get _state => widget.state;
  MadarBridge get _bridge => _state.core.bridge;

  @override
  void initState() {
    super.initState();
    _state.alert.addListener(_onAlert);
  }

  @override
  void dispose() {
    _state.alert.removeListener(_onAlert);
    _toastTimer?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  /// Core-raised alert: localized text decided in Rust; the shell renders
  /// a toast + chime for notify, chime-only for ping, haptic-only for
  /// haptic (the natives' RealtimePlayer contract).
  void _onAlert() {
    // The notifier pairs each command with a sequence counter so identical
    // consecutive commands still fire — only the command matters here.
    final cmd = _state.alert.value?.$2;
    if (cmd == null || !mounted) return;
    switch (cmd) {
      case AlertCommand_Notify(:final title, :final body):
        _showToast(body.isEmpty ? title : '$title — $body');
        _chime();
        MadarHaptics.impact();
      case AlertCommand_Ping():
        _chime();
      case AlertCommand_Haptic():
        MadarHaptics.success();
    }
  }

  void _showToast(
    String text, {
    ChipTone tone = ChipTone.accent,
    String icon = 'bell',
  }) {
    setState(() {
      _toast = ToastData(
        id: DateTime.now().millisecondsSinceEpoch,
        text: text,
        tone: tone,
        icon: icon,
      );
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _toast = null);
    });
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

  List<_RailSection> _sections(BuildContext context) {
    final t = _state.tr;
    // A waiter's tickets live in the cart strip — the rail keeps only the
    // system footer for them, exactly like the natives.
    if (_state.session?.role == 'waiter') return const [];
    return [
      _RailSection(t('nav.section.orders'), [
        _RailDest(
          'bicycle',
          t('nav.incoming'),
          hasNew:
              _state.deliveryTick.value > _seenDelivery ||
              _state.ticketTick.value > _seenTicket,
          onTap: () {
            _seenDelivery = _state.deliveryTick.value;
            _seenTicket = _state.ticketTick.value;
            setState(() {});
            _push(
              () => IncomingScreen(
                core: _state.core,
                onStateChanged: _state.refreshRoute,
                deliveryTick: _state.deliveryTick,
                ticketTick: _state.ticketTick,
              ),
            );
          },
        ),
        _RailDest(
          'tray.full',
          t('drafts.title'),
          onTap: () => _push(
            () => DraftsScreen(
              core: _state.core,
              onStateChanged: _state.refreshRoute,
            ),
          ),
        ),
        _RailDest(
          'list.bullet.rectangle',
          t('nav.history'),
          onTap: () => _push(
            () => OrderHistoryScreen(
              core: _state.core,
              onStateChanged: _state.refreshRoute,
            ),
          ),
        ),
        _RailDest(
          'magnifyingglass',
          t('search.title'),
          onTap: () => _push(
            () => OrderSearchScreen(
              core: _state.core,
              onStateChanged: _state.refreshRoute,
            ),
          ),
        ),
      ]),
      _RailSection(t('nav.section.money'), [
        _RailDest(
          'banknote',
          t('cash.title'),
          onTap: () => _push(
            () => CashMovementsScreen(
              core: _state.core,
              onStateChanged: _state.refreshRoute,
            ),
          ),
        ),
        _RailDest(
          'clock.arrow.circlepath',
          t('shifts.title'),
          onTap: () => _push(
            () => ShiftHistoryScreen(
              core: _state.core,
              onStateChanged: _state.refreshRoute,
            ),
          ),
        ),
        _RailDest(
          'printer',
          t('shift.print_report'),
          onTap: () => unawaited(
            showMadarSheet<void>(
              context,
              builder: (_) => ShiftReportSheet(core: _state.core),
            ),
          ),
        ),
      ]),
    ];
  }

  _RailSection _footer(BuildContext context) {
    final t = _state.tr;
    return _RailSection(t('nav.section.system'), [
      _RailDest(
        'arrow.triangle.2.circlepath',
        t('sync.title'),
        onTap: () => _push(
          () => SyncScreen(
            core: _state.core,
            onStateChanged: _state.refreshRoute,
          ),
        ),
      ),
      _RailDest(
        'gearshape',
        t('settings.title'),
        onTap: () => _push(
          () => SettingsScreen(
            core: _state.core,
            onStateChanged: _state.refreshRoute,
            onLocaleChanged: _state.setLocale,
            onThemeChanged: (dark) => _state.setThemeMode(
              dark ? ThemeMode.dark : ThemeMode.light,
            ),
          ),
        ),
      ),
      _RailDest('ellipsis', t('chrome.more'), onTap: _openMore),
    ]);
  }

  /// The More sheet. On wide layouts it holds only the overflow rows; on
  /// narrow ones it doubles as the natives' phone drawer, carrying every
  /// rail section above them (the rail itself is hidden there).
  Future<void> _openMore({bool includeSections = false}) async {
    final t = _state.tr;
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
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
            for (final section in [
              ..._sections(sheetContext),
              _footer(sheetContext),
            ]) ...[
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
                if (d.label != t('chrome.more'))
                  row(d.glyph, d.label, onTap: d.onTap),
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
                  t('waiter.title'),
                  onTap: () => _push(
                    () => OpenTicketsScreen(
                      core: _state.core,
                      onStateChanged: _state.refreshRoute,
                    ),
                  ),
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
                  t('order.close_shift'),
                  tone: colors.danger,
                  onTap: () => _push(
                    () => CloseShiftScreen(
                      core: _state.core,
                      onStateChanged: _state.refreshRoute,
                    ),
                  ),
                ),
                row(
                  'rectangle.portrait.and.arrow.right',
                  t('home.sign_out'),
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
    ShiftView? shift;
    try {
      shift = await _bridge.currentShift();
    } on Exception catch (_) {}
    if (!mounted) return;
    if (shift?.isOpen ?? false) {
      _showToast(
        _state.tr('settings.sign_out_shift_open'),
        tone: ChipTone.danger,
        icon: 'lock',
      );
      return;
    }
    _bridge.unsubscribeRealtime();
    try {
      await _bridge.lanStop();
    } on Exception catch (_) {}
    try {
      await _bridge.logout(wipeOutbox: false);
    } on Exception catch (_) {}
    _state.refreshRoute();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, info) {
        final colors = context.madarColors;
        final rail = info.isWide
            ? ListenableBuilder(
                listenable: Listenable.merge([
                  _state.deliveryTick,
                  _state.ticketTick,
                ]),
                builder: (context, _) => _NavRail(
                  sections: _sections(context),
                  footer: _footer(context),
                ),
              )
            : null;
        return Stack(
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
            // Narrow layouts have no rail — the natives' phone drawer:
            // a floating nav button opening the full grouped More sheet.
            if (rail == null)
              PositionedDirectional(
                bottom: Space.lg,
                start: Space.lg,
                child: TactileScale(
                  onTap: () => unawaited(_openMore(includeSections: true)),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceRaised,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.border),
                    ),
                    child: MadarIcon(
                      'ellipsis',
                      tint: colors.textSecondary,
                      size: IconSize.xl,
                    ),
                  ),
                ),
              ),
            if (_toast != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: ToastHost(
                  _toast,
                  onDismiss: (_) {
                    if (mounted) setState(() => _toast = null);
                  },
                ),
              ),
          ],
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
  });

  final String glyph;
  final String label;
  final bool hasNew;
  final VoidCallback onTap;
}

class _RailSection {
  const _RailSection(this.title, this.items);

  final String title;
  final List<_RailDest> items;
}

/// The rail surface — lockup mark, scrolling task sections, pinned system
/// footer. Anatomy from the natives' NavRail (80dp, 36dp tiles, 8sp
/// captions, pulsing accent badge).
class _NavRail extends StatelessWidget {
  const _NavRail({required this.sections, required this.footer});

  final List<_RailSection> sections;
  final _RailSection footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Column(
          children: [
            const MadarSymbol(size: 40),
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
                    child: MadarIcon(
                      dest.glyph,
                      tint: dest.hasNew ? colors.accent : colors.textSecondary,
                      size: IconSize.lg,
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
