/// The Sync section — the outbox, told honestly. It answers three questions:
/// is anything waiting, is anything stuck, and can the server hear us. One
/// widget renders it everywhere it appears: the full Sync screen (from the
/// outbox pill), a section of Settings, and the waiter's Me tab.
///
/// A refused command is ACTIONABLE here. The old client acked every 409 as
/// success, which is how work vanished silently; this section shows the
/// server's own sentence under the row and offers the two honest answers —
/// retry (all, because the core's retry is all-or-nothing) or discard (with
/// a confirm, because a discarded row never reaches the server).
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_settings/src/sync_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Rows shown under WAITING before the section folds the rest into "N more"
/// — only in [SyncSection.compact] (Settings, Me); the Sync screen lists all.
const int _compactWaitingCap = 5;

/// Clock drift at which the chit times start to lie; the strip's banner
/// threshold, repeated here so Sync says the same thing.
const int _skewBannerMinutes = 5;

/// Localised label for an outbox op type. Every op the core enqueues has a
/// key; a wire name the till has never heard of is shown humanised rather
/// than raw, so the row still reads as words.
String outboxOpLabel(MadarBridge bridge, String op) {
  final key = switch (op) {
    'open_till' || 'open_shift' => 'sync.op_open_till',
    'close_till' || 'close_shift' => 'sync.op_close_till',
    'create_order' => 'sync.op_create_order',
    'void_order' => 'sync.op_void_order',
    'cash_movement' => 'sync.op_cash_movement',
    'open_ticket' => 'sync.op_open_ticket',
    'ticket_add_round' => 'sync.op_ticket_add_round',
    'void_ticket' => 'sync.op_void_ticket',
    'settle_open_ticket' => 'sync.op_settle_open_ticket',
    'award_loyalty_points' => 'sync.op_award_loyalty_points',
    'lan_mirror' => 'sync.op_lan_mirror',
    _ => null,
  };
  if (key == null) return op.replaceAll('_', ' ');
  return bridge.tr(key: key);
}

/// The outbox ops a waiter's work produces — what "rounds waiting to send"
/// counts on the Me tab. A teller's queue holds sales and drawer movements
/// too; those are not a waiter's to worry about.
const Set<String> waiterOutboxOps = {
  'open_ticket',
  'ticket_add_round',
  'void_ticket',
};

/// A figure — a count, a clock time — set LTR in mono so it stays an island
/// inside Arabic text.
class SyncFigure extends StatelessWidget {
  const SyncFigure(this.text, {this.style, this.color, super.key});

  final String text;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = style ?? MadarType.num;
    return Text(
      text,
      textDirection: TextDirection.ltr,
      style: base.copyWith(color: color ?? context.madarColors.textSecondary),
    );
  }
}

/// The section. Loads on mount and again on every connectivity pulse, so
/// offline → online flips the health row without a pull-to-refresh.
class SyncSection extends ConsumerStatefulWidget {
  const SyncSection({
    this.compact = false,
    this.onSeeAll,
    this.waiterOnly = false,
    super.key,
  });

  /// Cap the waiting list and fold the rest behind [onSeeAll].
  final bool compact;

  /// Opens the full Sync screen; the "N more" row's target.
  final VoidCallback? onSeeAll;

  /// Show only the ops a waiter produced ([waiterOutboxOps]). The Me tab
  /// passes this; a waiter's queue is rounds, not drawer movements.
  final bool waiterOnly;

  @override
  ConsumerState<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<SyncSection> {
  @override
  void initState() {
    super.initState();
    // Post-frame: notifier writes during initState land mid-build (crash).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(syncProvider.notifier).load());
    });
  }

  @override
  Widget build(BuildContext context) {
    // The device's reachability changed (OS event, resume, a failed
    // request): re-read so Online/Offline is the truth, not the last read.
    ref.listen(connectivityPulseProvider, (_, _) {
      unawaited(ref.read(syncProvider.notifier).load());
    });
    final bridge = ref.bridge;
    final state = ref.watch(syncProvider);
    final waiting = widget.waiterOnly
        ? state.waiting.where((i) => waiterOutboxOps.contains(i.opType))
        : state.waiting;
    final stuck = widget.waiterOnly
        ? state.stuck.where((i) => waiterOutboxOps.contains(i.opType))
        : state.stuck;
    final waitingRows = waiting.toList(growable: false);
    final stuckRows = stuck.toList(growable: false);
    final capped = widget.compact && waitingRows.length > _compactWaitingCap;
    final shown = capped
        ? waitingRows.sublist(0, _compactWaitingCap)
        : waitingRows;
    // A waiter's view hides a teller's stranded work: nothing they can do.
    final heldRows = widget.waiterOnly ? const <OutboxItemView>[] : state.held;
    final blocked = widget.waiterOnly ? 0 : state.blocked;
    final clear = waitingRows.isEmpty && stuckRows.isEmpty && blocked == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        _HealthCard(
          pendingCount: waitingRows.length,
          clear: clear,
          compact: widget.compact,
        ),
        if (stuckRows.isNotEmpty) ...[
          MadarSectionHeader(
            text:
                '${bridge.tr(key: 'sync.stuck')} · '
                '${bridge.tr(key: 'sync.needs_you')}',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.md,
              children: [
                SyncFigure('${stuckRows.length}'),
                MadarButton(
                  label: bridge.tr(key: 'sync.retry_all'),
                  variant: MadarButtonVariant.ghost,
                  size: MadarButtonSize.compact,
                  glyph: MadarGlyph.refresh,
                  onTap: () =>
                      unawaited(ref.read(syncProvider.notifier).retryAll()),
                ),
              ],
            ),
          ),
          MadarCard(
            flush: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, item) in stuckRows.indexed) ...[
                  if (index > 0) const MadarHairline.row(),
                  _StuckItem(item: item),
                ],
              ],
            ),
          ),
        ],
        if (blocked > 0) ...[
          MadarSectionHeader(
            text: bridge.tr(key: 'sync.blocked'),
            trailing: SyncFigure('$blocked'),
          ),
          if (heldRows.isNotEmpty)
            MadarCard(
              flush: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, item) in heldRows.indexed) ...[
                    if (index > 0) const MadarHairline.row(),
                    _WaitingItem(item: item),
                  ],
                ],
              ),
            ),
          const _BlockedCard(),
        ],
        if (waitingRows.isNotEmpty) ...[
          MadarSectionHeader(
            text: bridge.tr(key: 'sync.waiting'),
            trailing: SyncFigure('${waitingRows.length}'),
          ),
          MadarCard(
            flush: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, item) in shown.indexed) ...[
                  if (index > 0) const MadarHairline.row(),
                  _WaitingItem(item: item),
                ],
                if (capped) ...[
                  const MadarHairline.row(),
                  MadarListRow.nav(
                    title: bridge.tr(key: 'sync.more'),
                    valueText: MadarFormat.ltr(
                      '${waitingRows.length - _compactWaitingCap}',
                    ),
                    onTap: widget.onSeeAll,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Reachability + live updates + LAN on one row, the two banners that
/// change what the queue can do (auth parked, clock off), and the one
/// button: Sync now. When the queue is empty the row says so in one line —
/// no illustration.
class _HealthCard extends ConsumerWidget {
  const _HealthCard({
    required this.pendingCount,
    required this.clear,
    required this.compact,
  });

  final int pendingCount;
  final bool clear;

  /// Settings / Me render a compact strip; the full Sync screen has room for
  /// the rebuild action and what it does.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final status = ref.watch(syncProvider.select((s) => s.status));
    final pushing = ref.watch(syncProvider.select((s) => s.pushing));
    // The realtime flag flips on the SSE edge; the bridge answers whether
    // the subscription exists at all. Either alone lies for a moment.
    final live =
        ref.watch(realtimeConnectedProvider) && bridge.isRealtimeSubscribed();
    final online = status?.online ?? false;
    final authPaused = status?.authPaused ?? false;
    // The device's own skew against the SERVER, and the largest difference a
    // branch PEER's catch-up frame showed. Either one means a clock in this
    // branch is wrong, and the peer one used to be invisible: a skewed tablet
    // was simply dropped out of catch-up while every screen said it was fine.
    final peerSkew = bridge.lanActive()
        ? bridge.lanStatus().peerSkewMinutes.abs()
        : 0;
    final skew = bridge.clockSkewMinutes().abs() > peerSkew
        ? bridge.clockSkewMinutes().abs()
        : peerSkew;
    final lanPeers = bridge.lanActive() ? bridge.lanPeerCount() : 0;
    final String healthTitle;
    if (!online) {
      healthTitle = bridge.tr(key: 'chrome.offline');
    } else {
      healthTitle =
          '${bridge.tr(key: 'chrome.online')} · '
          '${bridge.tr(key: live ? 'sync.live_on' : 'sync.live_off')}';
    }
    return MadarCard(
      flush: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MadarRow(
            title: healthTitle,
            subtitle: clear ? bridge.tr(key: 'sync.empty') : null,
            leading: MadarGlyphIcon(
              online ? MadarGlyph.wifi : MadarGlyph.wifiOff,
              size: IconSize.xl,
              color: online ? colors.success : colors.warning,
            ),
            trailing: lanPeers > 0
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs,
                    children: [
                      SyncFigure('$lanPeers'),
                      Text(
                        bridge.tr(key: 'settings.lan_peers'),
                        style: MadarType.bodySm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  )
                : null,
          ),
          if (authPaused)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                Space.lg,
                0,
                Space.lg,
                Space.md,
              ),
              child: NoticeBanner(
                text: bridge.tr(key: 'chrome.auth_paused'),
                tone: ChipTone.danger,
                icon: 'lock',
                trailing: BannerActionPill(
                  label: bridge.tr(key: 'chrome.auth_paused_action'),
                ),
                onTap: () => ref.read(reauthRequestProvider.notifier).request(),
              ),
            ),
          // A repair is not a failure, but it is not nothing: a device that
          // keeps having to be rebuilt from the server is a device with a
          // problem, and healing in silence is what hid that.
          if ((status?.repairedTypes ?? const []).isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                Space.lg,
                0,
                Space.lg,
                Space.md,
              ),
              child: NoticeBanner(
                text:
                    '${bridge.tr(key: 'sync.repaired')} · '
                    '${status!.repairedTypes.length}',
                icon: 'shield',
              ),
            ),
          if (skew >= _skewBannerMinutes)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                Space.lg,
                0,
                Space.lg,
                Space.md,
              ),
              child: NoticeBanner(
                text: bridge.tr(key: 'chrome.clock_skew'),
                icon: 'clock',
                trailing: SyncFigure('$skew′', color: colors.warning),
              ),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.lg,
              0,
              Space.lg,
              Space.lg,
            ),
            child: MadarButton(
              label: bridge.tr(key: pushing ? 'sync.pushing' : 'sync.push'),
              glyph: MadarGlyph.refresh,
              // One teal button per surface: the queue's is this one. Where
              // the section sits inside Settings or Me it is still the one
              // action that changes something on the server.
              variant: pendingCount > 0
                  ? MadarButtonVariant.primary
                  : MadarButtonVariant.secondary,
              trailing: pendingCount > 0
                  ? SyncFigure(
                      '$pendingCount',
                      style: MadarType.numMd,
                      color: colors.textOnAccent,
                    )
                  : null,
              loading: pushing,
              onTap: () => unawaited(ref.read(syncProvider.notifier).syncNow()),
              // A long press downloads everything again, after a confirm that
              // says unsent sales stay. Not gated on a role: nobody signs in to
              // the POS with a manager role (managers only set the device up),
              // so a role gate left the long press dead for everyone.
              onLongPress: () => unawaited(confirmFullSync(context, ref)),
            ),
          ),
          // The same act, but FINDABLE. It was only ever a long press on Push
          // — a gesture nobody discovers and nothing announces, so the one
          // action that repairs a device that has drifted was effectively not
          // there. On the full Sync screen it is a plain button with a line
          // saying what it does; the long press stays for anyone used to it.
          if (!compact)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                Space.lg,
                0,
                Space.lg,
                Space.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.xs,
                children: [
                  MadarButton(
                    label: bridge.tr(key: 'sync.rebuild'),
                    glyph: MadarGlyph.undo,
                    variant: MadarButtonVariant.ghost,
                    enabled: !pushing,
                    onTap: () => unawaited(confirmFullSync(context, ref)),
                  ),
                  Text(
                    bridge.tr(key: 'sync.rebuild_hint'),
                    style: MadarType.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Ask before downloading everything again; runs it on yes.
Future<void> confirmFullSync(BuildContext context, WidgetRef ref) async {
  final bridge = ref.read(bridgeProvider);
  final notifier = ref.read(syncProvider.notifier);
  final yes = await showMadarConfirm(
    context,
    title: bridge.tr(key: 'sync.full_confirm_title'),
    body: bridge.tr(key: 'sync.full_confirm_body'),
    confirmLabel: bridge.tr(key: 'sync.push'),
    cancelLabel: bridge.tr(key: 'common.cancel'),
  );
  if (yes) await notifier.syncFull();
}

/// A queued or in-flight item: what it is, when, how many tries, as a bill
/// row with its state pill.
class _WaitingItem extends ConsumerWidget {
  const _WaitingItem({required this.item});

  final OutboxItemView item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final sending = item.status == 'inflight';
    final tries = item.attempts;
    return MadarListRow.bill(
      title: outboxOpLabel(bridge, item.opType),
      meta: [
        MadarFormat.isolate(bridge.formatStamp(rfc3339: item.eventAt)),
        // A first try is not news; a second one is.
        if (tries > 1)
          '${MadarFormat.ltr('$tries')} ${bridge.tr(key: 'sync.tries')}',
      ].join(' · '),
      status: sending
          ? MadarStatus(bridge.tr(key: 'sync.sending'), tone: MadarTone.accent)
          : MadarStatus(bridge.tr(key: 'sync.queued')),
      chevron: false,
    );
  }
}

/// A refused item: the op, its time, the server's sentence, and Discard.
/// Retry is at the section head (all-or-nothing on the bridge).
class _StuckItem extends ConsumerWidget {
  const _StuckItem({required this.item});

  final OutboxItemView item;

  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final bridge = ref.read(bridgeProvider);
    final ok = await showMadarConfirm(
      context,
      title: bridge.tr(key: 'sync.discard_title'),
      body: bridge.tr(key: 'sync.discard_body'),
      confirmLabel: bridge.tr(key: 'sync.discard'),
      cancelLabel: bridge.tr(key: 'common.cancel'),
    );
    if (!ok) return;
    await ref.read(syncProvider.notifier).discard(item.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final sentence = item.lastError?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MadarListRow.bill(
          title: outboxOpLabel(bridge, item.opType),
          meta: [
            MadarFormat.isolate(bridge.formatStamp(rfc3339: item.eventAt)),
            if (item.attempts > 1)
              '${MadarFormat.ltr('${item.attempts}')} ${bridge.tr(key: 'sync.tries')}',
          ].join(' · '),
          status: MadarStatus(
            bridge.tr(key: 'sync.stuck'),
            tone: MadarTone.danger,
          ),
          rail: MadarTone.danger,
          chevron: false,
          trailing: MadarButton(
            label: bridge.tr(key: 'sync.discard'),
            variant: MadarButtonVariant.danger,
            size: MadarButtonSize.compact,
            glyph: MadarGlyph.trash,
            onTap: () => unawaited(_confirmDiscard(context, ref)),
          ),
        ),
        // The server's own words — a dead item with no detail still gets a
        // sentence.
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.card,
            0,
            Space.card,
            Space.lg,
          ),
          child: Text(
            sentence.isEmpty ? bridge.tr(key: 'sync.refused') : sentence,
            style: MadarType.body.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// Work held behind a refused action — a sale, a void, drawer money, a
/// ticket, or the drawer's own CLOSE. What makes it held is the dependency,
/// which the rows above cannot show for themselves, so this card names the way
/// forward rather than leaving a queue that never drains. Behind a failed
/// shift opening, recovery needs an open drawer to move the work onto.
class _BlockedCard extends ConsumerWidget {
  const _BlockedCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final hasTill = ref.watch(syncProvider.select((s) => s.hasOpenTill));
    final recovering = ref.watch(syncProvider.select((s) => s.recovering));
    final recovered = ref.watch(syncProvider.select((s) => s.recovered));
    final blocksClose = ref.watch(
      syncProvider.select((s) => s.heldBlocksClose),
    );
    final behindOpen = ref.watch(syncProvider.select((s) => s.heldBehindOpen));
    return MadarCard.column(
      children: [
        Text(
          bridge.tr(
            key: behindOpen ? 'sync.blocked_open_hint' : 'sync.blocked_hint',
          ),
          style: MadarType.bodySm.copyWith(color: colors.textSecondary),
        ),
        if (blocksClose)
          Text(
            bridge.tr(key: 'sync.blocked_close_warning'),
            style: MadarType.bodySm.copyWith(color: colors.warning),
          ),
        // Only a failed shift OPENING has a recovery of its own; anything else
        // held is freed by retrying or discarding the refused row above, which
        // the hint says. Offering "Recover stranded sales" there would be a
        // button that cannot help.
        if (behindOpen) ...[
          MadarButton(
            label: bridge.tr(key: 'sync.recover'),
            variant: MadarButtonVariant.secondary,
            glyph: MadarGlyph.undo,
            enabled: hasTill,
            tooltip: hasTill ? null : bridge.tr(key: 'sync.recover_need_shift'),
            loading: recovering,
            onTap: () => unawaited(ref.read(syncProvider.notifier).recover()),
          ),
          if (!hasTill)
            Text(
              bridge.tr(key: 'sync.recover_need_shift'),
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
        ],
        if (recovered != null)
          Row(
            spacing: Space.xs,
            children: [
              SyncFigure('$recovered', color: colors.success),
              Text(
                bridge.tr(key: 'sync.recovered'),
                style: MadarType.bodySm.copyWith(color: colors.success),
              ),
            ],
          ),
      ],
    );
  }
}
