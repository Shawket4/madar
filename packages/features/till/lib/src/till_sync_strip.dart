/// The one line that says how the sync started by opening a till is going:
/// "Syncing…", "Up to date", or why the data may be stale with a Retry.
///
/// Opening a till drains the outbox and pulls what changed (the core does
/// it, in the background). The teller sells straight away — so this line
/// never disables anything; it only tells.
///
/// The core owns the state (`syncOnTillOpenStatus`); the strip re-reads it
/// when the core says it moved (the `sync.status` tick), and never polls.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// How long after a finished sync the sell header keeps saying so.
const Duration tillSyncHeaderLinger = Duration(minutes: 1);

/// The strip's state: the core's last word, and a retry in flight.
@immutable
class TillSyncState {
  /// Creates the strip state.
  const TillSyncState({this.view, this.retrying = false});

  /// The core's view; null until first read (or when it could not be read).
  final TillOpenSyncView? view;

  /// A manual Retry is running.
  final bool retrying;
}

/// Reads the sync-on-open status from the core and retries on request.
class TillSyncNotifier extends Notifier<TillSyncState> {
  bool _disposed = false;
  late MadarBridge _bridge;

  @override
  TillSyncState build() {
    _bridge = ref.read(bridgeProvider);
    ref
      ..onDispose(() => _disposed = true)
      ..listen(syncTickProvider, (_, _) => unawaited(read()))
      // Opening or closing a till moves the route; the sync it started is
      // then the one to show.
      ..listen(shellProvider, (_, _) => unawaited(read()))
      ..listen(connectivityPulseProvider, (_, _) => unawaited(read()));
    unawaited(Future<void>.microtask(read));
    return const TillSyncState();
  }

  /// Re-read the core's status.
  Future<void> read() async {
    TillOpenSyncView? view;
    try {
      view = await Future<TillOpenSyncView>.sync(
        () => _bridge.syncOnTillOpenStatus(),
      );
    } on Exception catch (_) {
      return;
    }
    if (_disposed) return;
    state = TillSyncState(view: view, retrying: state.retrying);
  }

  /// Retry an incremental sync (the stale line's action).
  Future<void> retry() async {
    if (state.retrying) return;
    state = TillSyncState(view: state.view, retrying: true);
    try {
      await _bridge.syncNow();
    } on Exception catch (_) {
      // The status the core reports next says what went wrong.
    }
    if (_disposed) return;
    state = TillSyncState(view: state.view);
    await read();
  }
}

/// The sync-on-open strip's state, shared by every strip on screen.
final NotifierProvider<TillSyncNotifier, TillSyncState> tillSyncProvider =
    NotifierProvider.autoDispose<TillSyncNotifier, TillSyncState>(
      TillSyncNotifier.new,
    );

/// Whether the sell header should still show the strip at [now]: while
/// running or stale, and for [tillSyncHeaderLinger] after it finished.
bool tillSyncShowsInHeader(TillOpenSyncView? view, DateTime now) {
  if (view == null || view.tillId == null) return false;
  if (view.state != 'done') return true;
  final finished = DateTime.tryParse(view.finishedAt ?? '');
  if (finished == null) return false;
  return now.difference(finished) < tillSyncHeaderLinger;
}

/// The one-line sync strip. [headerOnly] hides it once the sync after
/// opening has been done for a minute (the sell header); the Open till
/// screen shows it whenever the core has something to say.
class TillSyncStrip extends ConsumerWidget {
  /// Creates the strip.
  const TillSyncStrip({super.key, this.headerOnly = false, this.now});

  /// Hide once finished for [tillSyncHeaderLinger].
  final bool headerOnly;

  /// The clock, for tests; null reads the wall clock.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final view = ref.watch(tillSyncProvider.select((s) => s.view));
    final retrying = ref.watch(tillSyncProvider.select((s) => s.retrying));
    if (view == null) return const SizedBox.shrink();
    if (headerOnly &&
        !tillSyncShowsInHeader(view, (now ?? DateTime.now).call())) {
      return const SizedBox.shrink();
    }

    final running = view.state == 'running' || retrying;
    final stale = !running && view.state == 'stale';
    final String text;
    final MadarTone tone;
    if (running) {
      text = t('sync.running');
      tone = MadarTone.accent;
    } else if (stale) {
      final at = view.finishedAt ?? view.startedAt;
      text = switch (view.staleReason) {
        'offline' => t('sync.stale_offline').replaceAll(
          '{time}',
          at == null ? '—' : MadarFormat.isolate(bridge.formatStamp(rfc3339: at)),
        ),
        'checksum_mismatch' => t('sync.stale_checksum'),
        _ => t('sync.stale_error'),
      };
      tone = MadarTone.warning;
    } else {
      text = t('sync.done');
      tone = MadarTone.success;
    }
    final pending = view.pendingOutbox;

    return Semantics(
      liveRegion: true,
      label: text,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Space.xxl + Space.lg),
        child: Row(
          spacing: Space.sm,
          children: [
            if (running)
              MadarSpinner(size: IconSize.sm, color: tone.color(colors))
            else
              MadarGlyphIcon(
                MadarStatus.glyphFor(tone),
                size: IconSize.sm,
                color: tone.color(colors),
              ),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.bodySm.copyWith(color: colors.textSecondary),
              ),
            ),
            if (pending > 0)
              Text(
                t('sync.pending_count').replaceAll(
                  '{count}',
                  MadarFormat.ltr('$pending'),
                ),
                maxLines: 1,
                style: MadarType.bodySm.copyWith(color: colors.textMuted),
              ),
            if (stale)
              MadarButton(
                label: t('sync.retry'),
                variant: MadarButtonVariant.ghost,
                size: MadarButtonSize.compact,
                onTap: () =>
                    unawaited(ref.read(tillSyncProvider.notifier).retry()),
              ),
          ],
        ),
      ),
    );
  }
}
