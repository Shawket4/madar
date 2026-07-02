/// Kitchen Display — the full-screen board a `kitchen`-role device shows.
/// Live kitchen events arrive on the ONE session-level realtime subscription
/// the shell owns (the core picks the kitchen topic for a KDS device); the
/// shell surfaces them as [KitchenDisplayScreen.realtimeTick] bumps and this
/// screen reloads. Sound is the shell's job too (AlertCommand.ping) — the
/// board only draws. A pixel-and-behavior port of the Kotlin
/// KitchenDisplayScreen.kt.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native board metrics (KitchenDisplayScreen.kt) that fall between the 4-pt
// Space steps — kept verbatim so the Flutter board measures identically to
// the Kotlin/Swift natives.

/// Header row vertical inset (natives: 14.dp).
const double _headerVPad = 14;

/// Header station tone-tile side (natives: 34.dp).
const double _headerTile = 34;

/// Live-connection dot diameter (natives: 8.dp).
const double _connectionDot = 8;

/// Station title size (natives: 20.sp Black; Cairo tops out at ExtraBold so
/// w800 stands in for the natives' Black — the shift screens' convention).
const double _stationTitleSize = 20;

/// Adaptive grid minimum cell width (natives: GridCells.Adaptive(260.dp)).
const double _gridMinCell = 260;

/// Ticket-card age strip: fixed height (natives: 54.dp) so every card's
/// first item starts at the SAME y regardless of table label or waiter chip.
const double _cardHeaderHeight = 54;

/// Card title / age-clock sizes (natives: 19.sp / 18.sp Black).
const double _cardTitleSize = 19;
const double _ageSize = 18;

/// Ready-ticket border weight (natives: 2.dp vs the 1.dp resting hairline)
/// and border tint alpha (natives: success.copy(alpha = 0.6f)).
const double _readyBorder = 2;
const double _readyBorderAlpha = 0.6;

/// Line row: vertical inset (natives: 8.dp), check-toggle side (22.dp),
/// intra-column gap (2.dp), and type sizes (15/12/10.sp).
const double _lineVPad = 8;
const double _lineCheck = 22;
const double _lineGap = 2;
const double _lineSize = 15;
const double _lineMetaSize = 12;
const double _lineStationSize = 10;

/// All-clear empty state: badge tile (72.dp), glyph (36.dp), text (16.sp).
const double _emptyTile = 72;
const double _emptyIcon = 36;
const double _emptyTextSize = 16;

/// Age escalation thresholds (minutes) — fresh accent → amber → red.
const int _ageWarnMinutes = 5;
const int _ageDangerMinutes = 10;

/// Safety-net poll under the realtime tick (natives: 60s).
const Duration _safetyPollPeriod = Duration(seconds: 60);

/// Cairo at a native size/weight (colors applied per call site).
TextStyle _cairo(double size, FontWeight weight) =>
    MadarType.body.copyWith(fontSize: size, fontWeight: weight);

/// Minutes elapsed since an RFC3339 stamp, clamped at 0 (the natives'
/// `minutesSince` — a malformed stamp reads as fresh, never stale).
int _minutesSince(String rfc) {
  final then = DateTime.tryParse(rfc);
  if (then == null) return 0;
  final minutes = DateTime.now().toUtc().difference(then.toUtc()).inMinutes;
  return minutes < 0 ? 0 : minutes;
}

/// The kitchen board. Takes the shared screen contract ([core] +
/// [onStateChanged]) plus the board's route payload: the device's bound
/// [stationId] (null = the all-station expo board) and the shell-owned
/// [realtimeTick] that bumps on every `kitchen.*` realtime event.
class KitchenDisplayScreen extends StatefulWidget {
  const KitchenDisplayScreen({
    required this.core,
    required this.onStateChanged,
    this.stationId,
    this.realtimeTick,
    this.realtimeConnected,
    this.onOpenSettings,
    super.key,
  });

  final MadarCore core;

  /// Fired after any bridge call that can move `app_route()` / the session.
  /// The board's own calls (bump/recall) never do — kept for the shared
  /// screen contract and future settings-driven route moves.
  final void Function() onStateChanged;

  /// The device's bound kitchen station (route payload). Null shows every
  /// station's lines — the expo board.
  final String? stationId;

  /// Bumped by the shell on each `kitchen.*` realtime event → reload.
  final Listenable? realtimeTick;

  /// The shell's SSE connection state — drives the header dot and the
  /// reconnecting banner (the natives' `realtimeConnected`). Null reads as
  /// connected until the shell wires it.
  final ValueListenable<bool>? realtimeConnected;

  /// Opens the settings overlay (shell-owned). The header gear only renders
  /// when provided.
  final VoidCallback? onOpenSettings;

  @override
  State<KitchenDisplayScreen> createState() => _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends State<KitchenDisplayScreen> {
  MadarBridge get _bridge => widget.core.bridge;

  List<KdsTicketView> _tickets = const [];
  List<KdsStationView> _stations = const [];
  Timer? _safetyPoll;

  String _t(String key) => _bridge.tr(key: key);

  bool get _connected => widget.realtimeConnected?.value ?? true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStations());
    unawaited(_load());
    widget.realtimeTick?.addListener(_onTick);
    widget.realtimeConnected?.addListener(_onConnection);
    // Slow safety-net poll under the realtime tick — also re-renders the
    // age escalation at least once a minute (the natives' 60s loop).
    _safetyPoll = Timer.periodic(_safetyPollPeriod, (_) => unawaited(_load()));
  }

  @override
  void didUpdateWidget(KitchenDisplayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.realtimeTick != widget.realtimeTick) {
      oldWidget.realtimeTick?.removeListener(_onTick);
      widget.realtimeTick?.addListener(_onTick);
    }
    if (oldWidget.realtimeConnected != widget.realtimeConnected) {
      oldWidget.realtimeConnected?.removeListener(_onConnection);
      widget.realtimeConnected?.addListener(_onConnection);
    }
    // A station rebind updates this widget in place (the shell keys the
    // subtree by route TYPE only) — refetch instead of showing the old
    // station's tickets until the next tick/poll.
    if (oldWidget.stationId != widget.stationId) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    widget.realtimeTick?.removeListener(_onTick);
    widget.realtimeConnected?.removeListener(_onConnection);
    _safetyPoll?.cancel();
    super.dispose();
  }

  void _onTick() => unawaited(_load());

  void _onConnection() {
    if (mounted) setState(() {});
  }

  /// Fetch the board. A failed fetch keeps the last good board on screen
  /// (the natives' runCatching — a blip never blanks a busy kitchen).
  Future<void> _load() async {
    try {
      final tickets = await _bridge.kdsList(stationId: widget.stationId);
      if (!mounted) return;
      setState(() => _tickets = tickets);
    } on Object {
      // Keep the previous tickets.
    }
  }

  Future<void> _loadStations() async {
    List<KdsStationView> stations;
    try {
      stations = await _bridge.kdsListStations();
    } on Object {
      stations = const [];
    }
    if (!mounted) return;
    setState(() => _stations = stations);
  }

  /// Toggle one line's done marker: bump ⇄ recall (kdsBump / kdsUnbump),
  /// then reload. Failures are silent — the next tick reconciles.
  Future<void> _toggleLine(KdsLineView line) async {
    try {
      if (line.bumped) {
        await _bridge.kdsUnbump(itemId: line.id);
      } else {
        await _bridge.kdsBump(itemId: line.id);
      }
      await _load();
    } on Object {
      // The board reloads on the next tick / poll.
    }
  }

  String get _stationName {
    final id = widget.stationId;
    if (id != null) {
      for (final station in _stations) {
        if (station.id == id) return station.name;
      }
    }
    return _t('kds.title');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    // Scaffold (not a bare ColoredBox): text styling needs a Material
    // ancestor — every screen owns its own Scaffold in this app.
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _KitchenHeader(
              stationName: _stationName,
              ticketCount: _tickets.length,
              connected: _connected,
              onOpenSettings: widget.onOpenSettings,
            ),
            if (!_connected)
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.sm,
                ),
                child: NoticeBanner(
                  text: _t('kds.reconnecting'),
                  icon: 'wifi.slash',
                ),
              ),
            Expanded(
              child: _tickets.isEmpty
                  ? _KdsEmptyState(title: _t('kds.all_clear'))
                  : _TicketGrid(
                      tickets: _tickets,
                      onToggleLine: (line) => unawaited(_toggleLine(line)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────
/// Clean, confident board header: a leading teal tone-tile behind the station
/// glyph, the bold station name, a live-connection dot, and the outstanding-
/// ticket count. Mirrors the natives' `KitchenHeader`.
class _KitchenHeader extends StatelessWidget {
  const _KitchenHeader({
    required this.stationName,
    required this.ticketCount,
    required this.connected,
    required this.onOpenSettings,
  });

  final String stationName;
  final int ticketCount;
  final bool connected;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
              vertical: _headerVPad,
            ),
            child: Row(
              children: [
                Container(
                  width: _headerTile,
                  height: _headerTile,
                  decoration: BoxDecoration(
                    color: colors.accentBg,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Center(
                    child: MadarIcon(
                      'fork.knife',
                      tint: colors.accent,
                      size: IconSize.lg,
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Flexible(
                  child: Text(
                    stationName,
                    style: _cairo(
                      _stationTitleSize,
                      FontWeight.w800,
                    ).copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Space.sm),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: connected ? colors.success : colors.textMuted,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(
                    width: _connectionDot,
                    height: _connectionDot,
                  ),
                ),
                const Spacer(),
                if (ticketCount > 0) ...[
                  const SizedBox(width: Space.sm),
                  StatusChip(label: '$ticketCount', tone: ChipTone.accent),
                ],
                if (onOpenSettings case final openSettings?)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: Space.xs),
                    child: TactileScale(
                      onTap: openSettings,
                      child: MadarIcon(
                        'gearshape',
                        tint: colors.textSecondary,
                        size: IconSize.lg,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.border),
        ],
      ),
    );
  }
}

// ── All-clear empty state ───────────────────────────────────────────────────
/// A success-tinted badge (not the muted shared EmptyState) — "no tickets"
/// is GOOD news on a kitchen board. Mirrors the natives' `KdsEmptyState`.
class _KdsEmptyState extends StatelessWidget {
  const _KdsEmptyState({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _emptyTile,
            height: _emptyTile,
            decoration: BoxDecoration(
              color: colors.successBg,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: Center(
              child: MadarIcon(
                'checkmark.circle',
                tint: colors.success,
                size: _emptyIcon,
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          Text(
            title,
            style: _cairo(
              _emptyTextSize,
              FontWeight.w600,
            ).copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Ticket grid ─────────────────────────────────────────────────────────────
/// The natives' `GridCells.Adaptive(260.dp)`: as many equal-width columns as
/// fit at ≥260 each. Cards are variable height, so the board renders as a
/// lazy list of top-aligned rows (each row is as tall as its tallest card) —
/// Compose's exact line behavior, which no fixed-extent GridView reproduces.
class _TicketGrid extends StatelessWidget {
  const _TicketGrid({required this.tickets, required this.onToggleLine});

  final List<KdsTicketView> tickets;
  final void Function(KdsLineView line) onToggleLine;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - Space.lg * 2;
        final fit = ((available + Space.md) / (_gridMinCell + Space.md))
            .floor();
        final columns = fit < 1 ? 1 : fit;
        final rows = (tickets.length + columns - 1) ~/ columns;
        return ListView.separated(
          padding: const EdgeInsetsDirectional.all(Space.lg),
          itemCount: rows,
          separatorBuilder: (_, _) => const SizedBox(height: Space.md),
          itemBuilder: (context, row) {
            final start = row * columns;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = start; i < start + columns; i++) ...[
                  if (i > start) const SizedBox(width: Space.md),
                  Expanded(
                    child: i < tickets.length
                        ? _KdsTicketCard(
                            key: ValueKey(tickets[i].id),
                            ticket: tickets[i],
                            onToggleLine: onToggleLine,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

// ── Ticket card ─────────────────────────────────────────────────────────────
/// A raised card with an age-TINTED header strip so a cook reads urgency from
/// across the kitchen: fresh teal → amber (5m) → red (10m); a ready ticket
/// goes green and gets a heavier border. The header is a FIXED height, so
/// every card's item list starts at the SAME y.
class _KdsTicketCard extends StatelessWidget {
  const _KdsTicketCard({
    required this.ticket,
    required this.onToggleLine,
    super.key,
  });

  final KdsTicketView ticket;
  final void Function(KdsLineView line) onToggleLine;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ready = ticket.status == 'ready';
    final ageMinutes = _minutesSince(ticket.createdAt);
    final ageFg = switch (ageMinutes) {
      _ when ready => colors.success,
      >= _ageDangerMinutes => colors.danger,
      >= _ageWarnMinutes => colors.warning,
      _ => colors.accent,
    };
    final ageBg = switch (ageMinutes) {
      _ when ready => colors.successBg,
      >= _ageDangerMinutes => colors.dangerBg,
      >= _ageWarnMinutes => colors.warningBg,
      _ => colors.accentBg,
    };
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: ready
              ? ageFg.withValues(alpha: _readyBorderAlpha)
              : colors.borderLight,
          width: ready ? _readyBorder : 1,
        ),
        boxShadow: MadarElevation.card.shadows(colors, dark: dark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Age-tinted header strip — fixed height aligns every card's
          // first item.
          Container(
            height: _cardHeaderHeight,
            color: ageBg,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.md,
            ),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    ticket.tableLabel ??
                        ticket.kitchenRef ??
                        '#${ticket.roundNumber}',
                    style: _cairo(
                      _cardTitleSize,
                      FontWeight.w800,
                    ).copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (ticket.sourceType == 'open_ticket') ...[
                  const SizedBox(width: Space.sm),
                  MadarIcon('person.fill', tint: ageFg),
                ],
                const Spacer(),
                const SizedBox(width: Space.sm),
                Text(
                  '${ageMinutes}m',
                  style: MadarType.money.copyWith(
                    fontSize: _ageSize,
                    fontWeight: FontWeight.w800,
                    color: ageFg,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.md,
              vertical: Space.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in ticket.items)
                  _KdsLineRow(
                    key: ValueKey(line.id),
                    line: line,
                    onToggle: () => onToggleLine(line),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bumpable line ───────────────────────────────────────────────────────────
/// One tappable line: a check toggle, the qty × name (+ size), modifiers, and
/// an optional kitchen note (warning-tinted). Bumped lines mute + strike
/// through. The per-line station label (expo board) pins to the trailing edge.
class _KdsLineRow extends StatelessWidget {
  const _KdsLineRow({required this.line, required this.onToggle, super.key});

  final KdsLineView line;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final size = line.sizeLabel;
    final title = '${line.qty}× ${line.name}${size != null ? ' · $size' : ''}';
    final notes = line.notes;
    final stationName = line.stationName;
    return TactileScale(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: _lineVPad),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MadarIcon(
              line.bumped ? 'checkmark.circle.fill' : 'circle',
              tint: line.bumped ? colors.success : colors.textMuted,
              size: _lineCheck,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: _lineGap,
                children: [
                  Text(
                    title,
                    style: _cairo(_lineSize, FontWeight.w600).copyWith(
                      color: line.bumped
                          ? colors.textMuted
                          : colors.textPrimary,
                      decoration: line.bumped
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: colors.textMuted,
                    ),
                  ),
                  if (line.modifiers.isNotEmpty)
                    Text(
                      line.modifiers.join(', '),
                      style: _cairo(
                        _lineMetaSize,
                        FontWeight.w500,
                      ).copyWith(color: colors.textSecondary),
                    ),
                  if (notes != null && notes.trim().isNotEmpty)
                    Text(
                      notes,
                      style: _cairo(
                        _lineMetaSize,
                        FontWeight.w600,
                      ).copyWith(color: colors.warning),
                    ),
                ],
              ),
            ),
            // Per-line station label — the expo / all-station board's routing
            // hint (the natives render it on both hosts).
            if (stationName != null && stationName.trim().isNotEmpty) ...[
              const SizedBox(width: Space.sm),
              Text(
                stationName.toUpperCase(),
                style: _cairo(
                  _lineStationSize,
                  FontWeight.w700,
                ).copyWith(color: colors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
