/// "N actions need a manager" — the till-level indicator, its list, and the
/// ONE manager PIN that clears the whole batch (stream 11 part 2).
///
/// Everything here is a thin shell over `madar-core`'s `till_review`: the core
/// builds the list (refused outbox ops + the last pulled flags), decides what
/// each approver may clear, re-sends the refusals with the approval attached
/// and resolves the flags through the backend's bulk endpoint. This file only
/// renders it and collects the PIN.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The till's "needs a manager" list. Reads offline; refreshes the flags half
/// from the server whenever there is a connection.
class ManagerActionsNotifier extends Notifier<ManagerActionsView> {
  late MadarBridge _bridge;
  bool _disposed = false;

  @override
  ManagerActionsView build() {
    _bridge = ref.read(bridgeProvider);
    ref
      ..onDispose(() => _disposed = true)
      ..listen(shellProvider, (_, _) => unawaited(refresh()))
      ..listen(connectivityPulseProvider, (_, _) => unawaited(refresh()))
      ..listen(drawerTickProvider, (_, _) => unawaited(refresh()));
    unawaited(Future<void>.microtask(refresh));
    return _bridge.pendingManagerActions();
  }

  /// Re-read the list. Pulls this branch's flags first when online; the last
  /// pull stands otherwise, so the list is never empty just because the
  /// network is.
  Future<void> refresh() async {
    if (_bridge.currentSession()?.online ?? false) {
      try {
        await _bridge.refreshReviewFlags();
      } on Exception catch (_) {
        // Best-effort: the cached flags still show.
      }
    }
    if (_disposed) return;
    state = _bridge.pendingManagerActions();
  }

  /// One manager PIN for [ids] (empty = everything listed).
  Future<BatchAuthorizeView> authorize(String pin, List<String> ids) async {
    final res = await _bridge.authorizeManagerActions(
      approverPin: pin,
      ids: ids,
    );
    await refresh();
    return res;
  }
}

/// The till's "needs a manager" list.
final NotifierProvider<ManagerActionsNotifier, ManagerActionsView>
managerActionsProvider =
    NotifierProvider.autoDispose<ManagerActionsNotifier, ManagerActionsView>(
      ManagerActionsNotifier.new,
    );

/// "3 actions need a manager" on the Till home. Nothing shows when the list is
/// empty — this is a real problem or it is not there at all.
class ManagerActionsBanner extends ConsumerWidget {
  /// Creates the banner.
  const ManagerActionsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(managerActionsProvider);
    if (view.count == 0) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(
        MadarPages.push<void>(context, (_) => const ManagerActionsScreen()),
      ),
      child: NoticeBanner(text: view.headline),
    );
  }
}

/// The list: what each action was, when, who did it, and why it was flagged or
/// refused — with one button that asks a manager for their PIN once.
class ManagerActionsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ManagerActionsScreen({super.key});

  @override
  ConsumerState<ManagerActionsScreen> createState() =>
      _ManagerActionsScreenState();
}

class _ManagerActionsScreenState extends ConsumerState<ManagerActionsScreen> {
  /// Picked ids. Empty = everything listed, which is the common case.
  final Set<String> _picked = <String>{};

  Future<void> _authorize() async {
    final bridge = ref.read(bridgeProvider);
    final res = await askManagerBatch(
      context,
      reason: bridge.tr(key: 'review.enter_pin'),
      authorize: (pin) => ref
          .read(managerActionsProvider.notifier)
          .authorize(pin, _picked.toList()),
    );
    if (res == null || !mounted) return;
    setState(() {
      _picked.clear();
      _result = res;
    });
  }

  /// What the last PIN cleared, shown above the list until it is tried again.
  BatchAuthorizeView? _result;

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final view = ref.watch(managerActionsProvider);
    final colors = context.madarColors;

    return MadarPageScaffold(
      title: t('review.title'),
      width: MadarContentWidth.form,
      body: ListView(
        padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
        children: [
          if (_result != null) ...[
            NoticeBanner(
              text: _result!.summary,
              tone: _result!.left.isEmpty ? ChipTone.success : ChipTone.warning,
              icon: 'checkmark.circle',
            ),
            const SizedBox(height: Space.xl),
          ],
          if (view.blockedReason.isNotEmpty) ...[
            NoticeBanner(
              text: view.blockedReason,
              tone: ChipTone.info,
              icon: 'wifi.slash',
            ),
            const SizedBox(height: Space.xl),
          ],
          if (view.count == 0)
            EmptyState(icon: 'checkmark.circle', title: t('review.cleared'))
          else
            MadarCard.column(
              children: [
                for (final item in view.items)
                  MadarListRow.pick(
                    title: item.what,
                    glyph: item.kind == 'refused'
                        ? MadarGlyph.alertTriangle
                        : MadarGlyph.alertCircle,
                    selected: _picked.isEmpty || _picked.contains(item.id),
                    onTap: () => setState(() {
                      // The first tap narrows an "everything" list down to
                      // exactly what the person did NOT tap.
                      if (_picked.isEmpty) {
                        _picked
                          ..addAll(view.items.map((i) => i.id))
                          ..remove(item.id);
                      } else if (!_picked.remove(item.id)) {
                        _picked.add(item.id);
                      }
                    }),
                    meta: _meta(bridge, item),
                  ),
              ],
            ),
          if (view.count > 0) ...[
            const SizedBox(height: Space.md),
            for (final item in view.items)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: Space.xs),
                child: Text(
                  '${item.what} — ${item.why}',
                  style: MadarType.bodySm.copyWith(color: colors.textMuted),
                ),
              ),
            const SizedBox(height: Space.xl),
            MadarButton(
              label: t('review.title'),
              glyph: MadarGlyph.lock,
              enabled: view.canAuthorize,
              onTap: () => unawaited(_authorize()),
            ),
          ],
        ],
      ),
    );
  }

  /// Who did it and when, plus the money when the act moved any.
  String _meta(MadarBridge bridge, ManagerActionView item) {
    final when = MadarFormat.isolate(
      bridge.formatStamp(rfc3339: item.occurredAt),
    );
    return [
      if (item.personName.isNotEmpty) item.personName,
      when,
      MadarFormat.ltr(item.capability),
    ].join(' · ');
  }
}

/// The one-time manager PIN for a whole batch — the same sheet shape as a void
/// or مراجعة الخزنة, except the core answers with what it managed to clear
/// rather than one approval. The signed-in person does not change.
Future<BatchAuthorizeView?> askManagerBatch(
  BuildContext context, {
  required String reason,
  required Future<BatchAuthorizeView> Function(String pin) authorize,
}) {
  return showMadarSheet<BatchAuthorizeView>(
    context,
    size: SheetSize.hug,
    maxWidth: 420,
    builder: (_) => _BatchPinSheet(reason: reason, authorize: authorize),
  );
}

class _BatchPinSheet extends ConsumerStatefulWidget {
  const _BatchPinSheet({required this.reason, required this.authorize});

  final String reason;
  final Future<BatchAuthorizeView> Function(String pin) authorize;

  @override
  ConsumerState<_BatchPinSheet> createState() => _BatchPinSheetState();
}

class _BatchPinSheetState extends ConsumerState<_BatchPinSheet> {
  final TextEditingController _pin = TextEditingController();
  bool _busy = false;
  UiText? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy || _pin.text.trim().length < 4) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.authorize(_pin.text.trim());
      if (mounted) await Navigator.of(context).maybePop(res);
    } on MadarError catch (e) {
      MadarHaptics.warning();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is MadarError_Forbidden
              ? UiText.raw(e.action)
              : UiText.error(e);
          _pin.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(
            t('approval.title'),
            style: MadarType.h3.copyWith(color: colors.textPrimary),
          ),
          Text(
            widget.reason,
            style: MadarType.body.copyWith(color: colors.textSecondary),
          ),
          MadarField(
            controller: _pin,
            placeholder: t('approval.pin'),
            icon: 'lock',
            obscure: true,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _go(),
          ),
          if (_error != null)
            NoticeBanner(
              text: _error!.of(bridge),
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
          MadarButton(
            label: t('approval.approve'),
            onTap: _go,
            loading: _busy,
            icon: 'checkmark.circle',
          ),
        ],
      ),
    );
  }
}
