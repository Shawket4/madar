/// Sync center — a pixel-and-behavior port of the Kotlin SyncScreen.kt:
/// visibility into the durable outbox (queued / in-flight / failed rows
/// with the error), Retry (requeues every failed command), Sync now
/// (force-drains everything queued), and per-row discard of a dead
/// command. Full-screen over the order screen.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart'
    show CircularProgressIndicator, Scaffold, Theme;
import 'package:flutter/widgets.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (SyncScreen.kt) that fall between the 4-pt Space steps —
// kept verbatim so the Flutter chrome measures identically.

/// Header back chevron (natives: 17.dp), vertical inset (14.dp), title
/// size (20.sp Black; Cairo tops out at ExtraBold so w800 stands in).
const double _headerIconSize = 17;
const double _headerVPad = 14;
const double _headerTitleSize = 20;

/// Header tone tile behind the sync glyph (natives: 34.dp, Radii.sm).
const double _headerTileSize = 34;

/// Sync-now pill vertical inset (natives: 7.dp), spinner (14.dp / 2.dp),
/// icon↔label gap (6.dp), action label size (13.sp).
const double _pillVPad = 7;
const double _pillSpinnerSize = 14;
const double _pillSpinnerStroke = 2;
const double _actionGap = 6;
const double _actionLabelSize = 13;

/// Outbox card cap (natives: widthIn(max = 560.dp)) and row metrics:
/// min height 68.dp, leading op tile 40.dp, text gap 3.dp.
const double _cardMaxWidth = 560;
const double _rowMinHeight = 68;
const double _opTileSize = 40;
const double _rowTextGap = 3;

/// Empty-state tile (natives: 72.dp, Radii.lg) and glyph (36.dp).
const double _emptyTileSize = 72;
const double _emptyIconSize = 36;

/// The outbox inspector. Takes the shared screen contract: [core] for
/// every bridge call and [onStateChanged] after a manual drain (the sync
/// chip counts on the order chrome move). The header's back pops it via
/// `Navigator.maybePop`.
class SyncScreen extends StatefulWidget {
  /// Creates the sync center screen.
  const SyncScreen({
    required this.core,
    required this.onStateChanged,
    super.key,
  });

  /// The core handle every bridge call goes through.
  final MadarCore core;

  /// Invoked after a drain/retry/discard so the shell's sync chrome
  /// (chip counts) re-reads.
  final void Function() onStateChanged;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  MadarBridge get _bridge => widget.core.bridge;

  List<OutboxItemView> _outbox = const [];
  bool _pushing = false;

  String _t(String key) => _bridge.tr(key: key);

  bool get _hasFailed => _outbox.any((item) => item.status == 'dead');

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Swallow bridge failures on best-effort calls (the natives'
  /// `runCatching`) — the inspector must render offline.
  Future<T?> _quiet<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Exception {
      return null;
    }
  }

  Future<void> _load() async {
    final outbox = await _quiet(_bridge.listOutbox) ?? const <OutboxItemView>[];
    if (mounted) setState(() => _outbox = outbox);
  }

  /// Requeue every FAILED (dead) command and try to send now.
  Future<void> _retry() async {
    await _quiet(_bridge.retryOutbox);
    await _load();
    widget.onStateChanged();
  }

  /// Manual PUSH of the durable outbox — force-drains every QUEUED (not
  /// just failed) command. Pings first so a queue parked offline re-probes
  /// connectivity + the auth-park, then drains (the natives' `syncNow`).
  /// Concurrent taps ignored.
  Future<void> _syncNow() async {
    if (_pushing) return;
    setState(() => _pushing = true);
    try {
      await _quiet(_bridge.refreshConnectivity);
      await _quiet(_bridge.syncNow);
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
    await _load();
    widget.onStateChanged();
  }

  /// Discard a single DEAD command (the teller gives up on it).
  Future<void> _discard(String id) async {
    await _quiet(() => _bridge.discardOutboxItem(id: id));
    await _load();
    widget.onStateChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    // Pushed as its own route — re-derive direction from the core so the
    // screen is RTL-correct wherever it's presented.
    return Directionality(
      textDirection: _bridge.isRtl() ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: colors.bg,
        body: Column(
          children: [
            _header(context),
            Expanded(
              child: _outbox.isEmpty ? _emptyState(context) : _list(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── header ─────────────────────────────────────────────────────────────────
  // Clean bold title with the back affordance, plus the two queue actions
  // (Retry the failed rows, force-push everything queued).
  Widget _header(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: colors.surface,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
              vertical: _headerVPad,
            ),
            child: Row(
              spacing: Space.sm,
              children: [
                Semantics(
                  button: true,
                  child: TactileScale(
                    onTap: () => unawaited(Navigator.of(context).maybePop()),
                    child: MadarIcon(
                      'chevron.backward',
                      tint: colors.textPrimary,
                      size: _headerIconSize,
                    ),
                  ),
                ),
                // Leading teal tone-tile behind the sync glyph — matches
                // the confident Kitchen/Order header.
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.accentBg,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: SizedBox.square(
                    dimension: _headerTileSize,
                    child: Center(
                      child: MadarIcon(
                        'arrow.triangle.2.circlepath',
                        tint: colors.accent,
                        size: IconSize.lg,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _t('sync.title'),
                    style: MadarType.h2.copyWith(
                      fontSize: _headerTitleSize,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                // Retry requeues only the FAILED (dead) rows, so it only
                // appears when there's something dead to resurrect.
                if (_hasFailed) _retryButton(context),
                // "Sync now" force-pushes every QUEUED command — the manual
                // escape hatch when the queue isn't draining on its own.
                if (_outbox.isNotEmpty) ...[
                  const SizedBox(width: Space.sm),
                  _syncNowButton(context),
                ],
              ],
            ),
          ),
        ),
        SizedBox(height: 1, child: ColoredBox(color: colors.border)),
      ],
    );
  }

  /// Requeue-the-failed action — a quiet accent text button.
  Widget _retryButton(BuildContext context) {
    final colors = context.madarColors;
    return Semantics(
      button: true,
      child: TactileScale(
        onTap: () => unawaited(_retry()),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: _actionGap,
          children: [
            MadarIcon(
              'arrow.clockwise',
              tint: colors.accent,
              size: IconSize.sm,
            ),
            Text(
              _t('sync.retry'),
              style: MadarType.bodySm.copyWith(
                fontSize: _actionLabelSize,
                fontWeight: FontWeight.w600,
                color: colors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Force-push-the-queue action — the teal pill CTA; spins + disables
  /// while pushing.
  Widget _syncNowButton(BuildContext context) {
    final colors = context.madarColors;
    final pill = Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.md,
        vertical: _pillVPad,
      ),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: _actionGap,
        children: [
          if (_pushing)
            SizedBox.square(
              dimension: _pillSpinnerSize,
              child: CircularProgressIndicator(
                color: colors.textOnAccent,
                strokeWidth: _pillSpinnerStroke,
              ),
            )
          else
            MadarIcon(
              'icloud.and.arrow.up',
              tint: colors.textOnAccent,
              size: IconSize.sm,
            ),
          Text(
            _pushing ? _t('sync.pushing') : _t('sync.push'),
            style: MadarType.bodySm.copyWith(
              fontSize: _actionLabelSize,
              fontWeight: FontWeight.w800,
              color: colors.textOnAccent,
            ),
          ),
        ],
      ),
    );
    if (_pushing) return pill;
    return Semantics(
      button: true,
      child: TactileScale(onTap: () => unawaited(_syncNow()), child: pill),
    );
  }

  // ── empty state ────────────────────────────────────────────────────────────
  // Nothing waiting to sync — a reassuring success mark.
  Widget _emptyState(BuildContext context) {
    final colors = context.madarColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.successBg,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: SizedBox.square(
              dimension: _emptyTileSize,
              child: Center(
                child: MadarIcon(
                  'checkmark.circle',
                  tint: colors.success,
                  size: _emptyIconSize,
                ),
              ),
            ),
          ),
          Text(
            _t('sync.empty'),
            style: MadarType.h3.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── outbox list ────────────────────────────────────────────────────────────
  // One surface card; rows separated by hairlines (matches the natives'
  // grouped card — not per-row cards) — capped + centered on tablet.
  Widget _list(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _cardMaxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: colors.borderLight),
              boxShadow: MadarElevation.card.shadows(colors, dark: dark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, item) in _outbox.indexed) ...[
                  if (index > 0)
                    SizedBox(
                      height: 1,
                      child: ColoredBox(color: colors.borderLight),
                    ),
                  _row(context, item),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One outbox row: leading tone-tinted op tile, op label + error (or
  /// attempt count), status chip, and a discard for dead commands.
  Widget _row(BuildContext context, OutboxItemView item) {
    final colors = context.madarColors;
    final dead = item.status == 'dead';
    // Outbox tones map to the shared ChipTone scale: failed → danger,
    // everything else (queued / in-flight) → info. The tile tint reuses the
    // same roles, so the leading icon and the status chip read as one tone.
    final tone = dead ? ChipTone.danger : ChipTone.info;
    final (Color tileBg, Color tileFg) = dead
        ? (colors.dangerBg, colors.danger)
        : (colors.navyBg, colors.navy);
    final error = item.lastError ?? '';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _rowMinHeight),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: Space.lg,
          end: Space.md,
          top: Space.md,
          bottom: Space.md,
        ),
        child: Row(
          spacing: Space.md,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: SizedBox.square(
                dimension: _opTileSize,
                child: Center(
                  child: MadarIcon(
                    _opGlyph(item.opType, item.status),
                    tint: tileFg,
                    size: IconSize.lg,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: _rowTextGap,
                children: [
                  Text(
                    _opLabel(item.opType),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.title.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (error.isNotEmpty)
                    Text(
                      error,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.textMuted,
                      ),
                    )
                  else if (item.attempts > 0)
                    Text(
                      '${item.attempts} ${_t('sync.attempts')}',
                      style: MadarType.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            StatusChip(label: _statusLabel(item.status), tone: tone),
            if (dead)
              Semantics(
                button: true,
                child: TactileScale(
                  onTap: () => unawaited(_discard(item.id)),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(Space.xs),
                    child: MadarIcon('trash', tint: colors.danger),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Localized op-type label (`open_shift` / `close_shift` /
  /// `create_order`); unknown ops show their raw wire name.
  String _opLabel(String op) => switch (op) {
    'open_shift' => _t('sync.op_open_shift'),
    'close_shift' => _t('sync.op_close_shift'),
    'create_order' => _t('sync.op_create_order'),
    _ => op,
  };

  /// Op glyph — dead → warning mark, else per op_type (the natives'
  /// `opGlyph`).
  String _opGlyph(String op, String status) {
    if (status == 'dead') return 'exclamationmark.circle';
    return switch (op) {
      'open_shift' => 'play.circle',
      'close_shift' => 'lock',
      'create_order' => 'doc.text',
      _ => 'arrow.clockwise',
    };
  }

  String _statusLabel(String status) => switch (status) {
    'dead' => _t('sync.failed'),
    'inflight' => _t('sync.sending'),
    _ => _t('sync.queued'),
  };
}
