/// Sync center — a pixel-and-behavior port of the Kotlin SyncScreen.kt:
/// visibility into the durable outbox (queued / in-flight / failed rows
/// with the error), Retry (requeues every failed command), Sync now
/// (force-drains everything queued), and per-row discard of a dead
/// command. Full-screen over the order screen.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_settings/src/sync_provider.dart';
import 'package:flutter/material.dart'
    show CircularProgressIndicator, Scaffold, Theme;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (SyncScreen.kt) that fall between the 4-pt Space steps —
// kept verbatim so the Flutter chrome measures identically.

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

/// The outbox inspector. All state flows from [syncProvider]; the header's
/// back pops it via `Navigator.maybePop`.
class SyncScreen extends ConsumerStatefulWidget {
  /// Creates the sync center screen.
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(syncProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    // Pushed as its own route — re-derive direction from the locale
    // provider so the screen is RTL-correct wherever it's presented.
    final rtl = ref.watch(localeProvider.select((s) => s.rtl));
    final outbox = ref.watch(syncProvider.select((s) => s.outbox));
    final hasFailed = ref.watch(syncProvider.select((s) => s.hasFailed));
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: colors.bg,
        body: Column(
          children: [
            MadarHeader(
              title: bridge.tr(key: 'sync.title'),
              onBack: () => unawaited(Navigator.of(context).maybePop()),
              actions: [
                // Retry requeues only the FAILED (dead) rows, so it only
                // appears when there's something dead to resurrect.
                if (hasFailed) const _RetryAction(),
                // "Sync now" force-pushes every QUEUED command — the manual
                // escape hatch when the queue isn't draining on its own.
                if (outbox.isNotEmpty) const _SyncNowAction(),
              ],
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: outbox.isEmpty
                    ? const _EmptyState()
                    : _OutboxList(outbox: outbox),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Requeue-the-failed action — a quiet accent text button.
class _RetryAction extends ConsumerWidget {
  const _RetryAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    return Semantics(
      button: true,
      child: TactileScale(
        onTap: () => unawaited(ref.read(syncProvider.notifier).retry()),
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
              bridge.tr(key: 'sync.retry'),
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
}

/// Force-push-the-queue action — the teal pill CTA; spins + disables
/// while pushing.
class _SyncNowAction extends ConsumerWidget {
  const _SyncNowAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final pushing = ref.watch(syncProvider.select((s) => s.pushing));
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
          if (pushing)
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
            pushing
                ? bridge.tr(key: 'sync.pushing')
                : bridge.tr(key: 'sync.push'),
            style: MadarType.bodySm.copyWith(
              fontSize: _actionLabelSize,
              fontWeight: FontWeight.w800,
              color: colors.textOnAccent,
            ),
          ),
        ],
      ),
    );
    if (pushing) return pill;
    return Semantics(
      button: true,
      child: TactileScale(
        onTap: () => unawaited(ref.read(syncProvider.notifier).syncNow()),
        child: pill,
      ),
    );
  }
}

// ── empty state ──────────────────────────────────────────────────────────────
/// Nothing waiting to sync — a reassuring success mark.
class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
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
            bridge.tr(key: 'sync.empty'),
            style: MadarType.h3.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── outbox list ──────────────────────────────────────────────────────────────
/// One surface card; rows separated by hairlines (matches the natives'
/// grouped card — not per-row cards) — capped + centered on tablet.
class _OutboxList extends StatelessWidget {
  const _OutboxList({required this.outbox});

  final List<OutboxItemView> outbox;

  @override
  Widget build(BuildContext context) {
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
                for (final (index, item) in outbox.indexed) ...[
                  if (index > 0)
                    SizedBox(
                      height: 1,
                      child: ColoredBox(color: colors.borderLight),
                    ),
                  _OutboxRow(item: item),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One outbox row: leading tone-tinted op tile, op label + error (or
/// attempt count), status chip, and a discard for dead commands. Takes the
/// row's pure data; actions go through the notifier.
class _OutboxRow extends ConsumerWidget {
  const _OutboxRow({required this.item});

  final OutboxItemView item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
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
                    _opLabel(bridge, item.opType),
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
                      '${item.attempts} ${bridge.tr(key: 'sync.attempts')}',
                      style: MadarType.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            StatusChip(label: _statusLabel(bridge, item.status), tone: tone),
            if (dead)
              Semantics(
                button: true,
                child: TactileScale(
                  onTap: () => unawaited(
                    ref.read(syncProvider.notifier).discard(item.id),
                  ),
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
  String _opLabel(MadarBridge bridge, String op) => switch (op) {
    'open_shift' => bridge.tr(key: 'sync.op_open_shift'),
    'close_shift' => bridge.tr(key: 'sync.op_close_shift'),
    'create_order' => bridge.tr(key: 'sync.op_create_order'),
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

  String _statusLabel(MadarBridge bridge, String status) => switch (status) {
    'dead' => bridge.tr(key: 'sync.failed'),
    'inflight' => bridge.tr(key: 'sync.sending'),
    _ => bridge.tr(key: 'sync.queued'),
  };
}
