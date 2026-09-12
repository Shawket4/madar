/// Kitchen Display — the full-screen board a `kitchen`-role device shows.
/// A board, not a shell: one ink top bar (station · branch · live dot ·
/// open count · outbox pill · settings) over [KdsBoardBody]. Live kitchen
/// events arrive on the ONE session-level realtime subscription the shell
/// owns; the shell bumps `kitchenTickProvider` and the notifier reloads.
/// Sound is the shell's job too (AlertCommand.ping) — the board only draws.
library;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_kds/src/kds_board_body.dart';
import 'package:feature_kds/src/kds_provider.dart';
import 'package:feature_kds/src/kds_strings.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Live-connection dot diameter.
const double _liveDot = 8;

/// The kitchen board. Takes only the board's route payload: the device's
/// bound [stationId] (null = every station, the expo board).
class KitchenDisplayScreen extends ConsumerWidget {
  const KitchenDisplayScreen({super.key, this.stationId});

  /// The device's bound kitchen station (route payload). Null shows every
  /// station's lines — the expo board.
  final String? stationId;

  void _openSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  void _openSync(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SyncScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final board = kdsProvider(stationId);
    final stationName =
        ref.watch(board.select((s) => s.stationName(stationId))) ??
        bridge.tr(key: 'kds.title');
    final openCount = ref.watch(board.select((s) => s.openCount));
    final outboxState = ref.watch(board.select((s) => s.outboxState));
    final outboxCount = ref.watch(board.select((s) => s.outboxCount));
    final connected = ref.watch(realtimeConnectedProvider);
    final branch = _branchName(bridge);
    final pillWord = switch (outboxState) {
      OutboxState.synced => bridge.trOr(KdsKeys.pillSynced),
      OutboxState.queued => bridge.trOr(KdsKeys.pillQueued),
      OutboxState.offline => bridge.trOr(KdsKeys.pillOffline),
      OutboxState.stuck => bridge.trOr(KdsKeys.pillStuck),
    };
    // Scaffold (not a bare ColoredBox): text styling needs a Material
    // ancestor — every screen owns its own Scaffold in this app. The top bar
    // paints under the status bar itself; the board keeps the side insets.
    // The KDS draws its own MadarTopBar, which pays its own inset.
    return MadarPageScaffold(
      safeTop: false,
      body: Column(
        children: [
          MadarTopBar(
            title: stationName,
            subtitle: branch,
            actions: [
              _LiveDot(connected: connected, label: bridge.trOr(KdsKeys.live)),
              _OpenCount(count: openCount, word: bridge.trMaybe(KdsKeys.open)),
              MadarGlyphTile(
                glyph: MadarGlyph.settings,
                tint: colors.onChrome,
                background: colors.chromeRaised,
                semanticLabel: bridge.tr(key: 'settings.title'),
                onTap: () => _openSettings(context),
              ),
            ],
            pill: MadarOutboxPill(
              state: outboxState,
              label: pillWord,
              count: outboxCount,
              onTap: () => _openSync(context),
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: KdsBoardBody(stationId: stationId),
            ),
          ),
        ],
      ),
    );
  }

  /// The device's branch, for the top bar's second word. A board that is
  /// not bound yet has none, and the bar just shows the station.
  String? _branchName(MadarBridge bridge) {
    try {
      final name = bridge.deviceConfig().branchName?.trim();
      return (name == null || name.isEmpty) ? null : name;
    } on Object {
      return null;
    }
  }
}

/// The live-updates dot: green while the realtime feed is up, muted while
/// the board is on its safety-net poll.
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.connected, required this.label});

  final bool connected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Semantics(
      label: label,
      value: connected ? 'on' : 'off',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: connected ? colors.success : colors.onChromeMuted,
          shape: BoxShape.circle,
        ),
        child: const SizedBox.square(dimension: _liveDot),
      ),
    );
  }
}

/// "4 open" in the bar: a mono LTR figure and, once the key lands, the
/// word. Hidden at zero — the all-clear state says it better.
class _OpenCount extends StatelessWidget {
  const _OpenCount({required this.count, required this.word});

  final int count;
  final String? word;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final colors = context.madarColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        Text(
          '$count',
          textDirection: TextDirection.ltr,
          style: MadarType.numMd.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.onChrome,
          ),
        ),
        if (word != null)
          Text(
            word!,
            style: MadarType.bodySm.copyWith(color: colors.onChromeMuted),
          ),
      ],
    );
  }
}
