/// The board proper — banners, the ticket grid, the toast — without a
/// header, so it mounts under the kitchen device's top bar AND inside
/// Queue's Kitchen segment (routing mode `till`). One widget, one provider
/// family: the cook and the cashier cannot disagree about a line.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_kds/src/kds_provider.dart';
import 'package:feature_kds/src/kds_strings.dart';
import 'package:feature_kds/src/kds_ticket_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Adaptive grid: as many equal columns as fit at ≥ this each. 260 puts
/// four on an iPad landscape and one on a phone.
const double _gridMinCell = 260;

/// Safety-net poll under the realtime tick (natives: 60s), only while
/// realtime is down.
const Duration _safetyPollPeriod = Duration(seconds: 60);

/// Ages are re-painted on this beat even when nothing happens — a ticket
/// that crosses 5 or 10 minutes must change colour on its own.
const Duration _ageBeat = Duration(seconds: 20);

/// All-clear empty state: badge tile, glyph.
const double _emptyTile = 72;
const double _emptyIcon = 36;

/// The board body for one [stationId] (null = every station).
class KdsBoardBody extends ConsumerStatefulWidget {
  const KdsBoardBody({required this.stationId, super.key});

  final String? stationId;

  @override
  ConsumerState<KdsBoardBody> createState() => _KdsBoardBodyState();
}

class _KdsBoardBodyState extends ConsumerState<KdsBoardBody>
    with RealtimeGatedPoll<KdsBoardBody> {
  Timer? _ageTimer;

  KdsNotifier get _board => ref.read(kdsProvider(widget.stationId).notifier);

  /// Throwing away a refused kitchen action. The kitchen never accepted it
  /// and it will not be retried, so whatever it was meant to do does not
  /// happen — that is worth one question before the tap takes effect.
  Future<void> _confirmDiscardRefused() async {
    final bridge = ref.read(bridgeProvider);
    final ok = await showMadarConfirm(
      context,
      title: bridge.tr(key: 'kds.discard_refused_title'),
      body: bridge.tr(key: 'kds.discard_refused_body'),
      confirmLabel: bridge.trOr(KdsKeys.discard),
      cancelLabel: bridge.tr(key: 'common.cancel'),
    );
    if (!ok) return;
    await _board.discardRefused();
  }

  @override
  void initState() {
    super.initState();
    // Post-frame: notifier writes during initState land mid-build (crash).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_board.loadStations());
      unawaited(_board.load());
    });
    _ageTimer = Timer.periodic(_ageBeat, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(KdsBoardBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A station rebind updates this widget in place (the shell keys the
    // subtree by route TYPE only) — prime the new station's family member
    // instead of showing an empty board until the next tick/poll.
    if (oldWidget.stationId != widget.stationId) {
      unawaited(_board.loadStations());
      unawaited(_board.load());
    }
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    final layout = context.madarLayout;
    // Fallback poll ONLY while realtime is down (connected → ticks cover it;
    // the notifier itself listens to the ticks).
    realtimeGatedPoll(
      interval: _safetyPollPeriod,
      onPoll: () => unawaited(_board.load()),
    );
    final state = ref.watch(kdsProvider(widget.stationId));
    final connected = ref.watch(realtimeConnectedProvider);
    final now = DateTime.now();
    final refused = state.deadBumps.length;
    return Stack(
      children: [
        Column(
          children: [
            // Offline outranks "reconnecting": the socket is down BECAUSE
            // the network is, and saying so twice helps nobody.
            if (!state.online)
              _Banner(
                child: NoticeBanner(
                  text: bridge.trOr(KdsKeys.offlineBanner),
                  icon: 'wifi.slash',
                ),
              )
            else if (!connected)
              _Banner(
                child: NoticeBanner(
                  text: bridge.tr(key: 'kds.reconnecting'),
                  icon: 'wifi.slash',
                ),
              ),
            if (refused > 0)
              _Banner(
                child: NoticeBanner(
                  text: '$refused · ${bridge.trOr(KdsKeys.refused)}',
                  tone: ChipTone.danger,
                  icon: 'xmark.circle',
                  onTap: () => unawaited(_board.retryRefused()),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.sm,
                    children: [
                      BannerActionPill(label: bridge.trOr(KdsKeys.retry)),
                      TactileScale(
                        onTap: () => unawaited(_confirmDiscardRefused()),
                        child: BannerActionPill(
                          label: bridge.trOr(KdsKeys.discard),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: switch ((state.loaded, state.tickets.isEmpty)) {
                (false, _) => const SizedBox.shrink(),
                (true, true) => _AllClear(
                  title: bridge.tr(key: 'kds.all_clear'),
                ),
                (true, false) => _TicketGrid(
                  tickets: state.tickets,
                  gutter: layout.gutter,
                  singleColumn: layout.isPhone,
                  cardFor: (ticket) => KdsTicketCard(
                    key: ValueKey(ticket.id),
                    ticket: ticket,
                    ageMinutes: state.ageMinutes(ticket, now),
                    busyLineIds: state.busyLineIds,
                    bumpingAll: state.bumpingAllIds.contains(ticket.id),
                    onToggleLine: (line) => unawaited(_board.toggleLine(line)),
                    onBumpAll: () => unawaited(_board.bumpAll(ticket)),
                  ),
                ),
              },
            ),
          ],
        ),
        // Toasts float above the grid — a refused bump says so here.
        SafeArea(child: ToastHost(state.toast, onDismiss: _board.dismissToast)),
      ],
    );
  }
}

/// A banner's inset from the board edge — the page gutter on the sides, a
/// small step on top.
class _Banner extends StatelessWidget {
  const _Banner({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gutter = context.madarLayout.gutter;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: gutter,
        end: gutter,
        top: Space.md,
      ),
      child: child,
    );
  }
}

/// A success-tinted badge (not the muted shared EmptyState) — "no tickets"
/// is GOOD news on a kitchen board.
class _AllClear extends StatelessWidget {
  const _AllClear({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          Container(
            width: _emptyTile,
            height: _emptyTile,
            decoration: BoxDecoration(
              color: colors.successBg,
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Center(
              child: MadarGlyphIcon(
                MadarGlyph.checkCircle,
                size: _emptyIcon,
                color: colors.success,
              ),
            ),
          ),
          Text(
            title,
            style: MadarType.title.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// As many equal-width columns as fit at ≥260 each (one on a phone). Cards
/// are variable height, so the board is a lazy list of top-aligned rows —
/// each row as tall as its tallest card — which no fixed-extent GridView
/// reproduces.
class _TicketGrid extends StatelessWidget {
  const _TicketGrid({
    required this.tickets,
    required this.gutter,
    required this.singleColumn,
    required this.cardFor,
  });

  final List<KdsTicketView> tickets;
  final double gutter;
  final bool singleColumn;
  final Widget Function(KdsTicketView ticket) cardFor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - gutter * 2;
        final fit = singleColumn
            ? 1
            : ((available + Space.lg) / (_gridMinCell + Space.lg)).floor();
        final columns = fit < 1 ? 1 : fit;
        final rows = (tickets.length + columns - 1) ~/ columns;
        return ListView.separated(
          padding: EdgeInsetsDirectional.all(gutter),
          itemCount: rows,
          separatorBuilder: (_, _) => const SizedBox(height: Space.lg),
          itemBuilder: (context, row) {
            final start = row * columns;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.lg,
              children: [
                for (var i = start; i < start + columns; i++)
                  Expanded(
                    child: i < tickets.length
                        ? cardFor(tickets[i])
                        : const SizedBox.shrink(),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
