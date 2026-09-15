import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Open the reconfigure sheet (Settings → Device, and the login screen).
Future<void> showReconfigureSheet(BuildContext context) =>
    showMadarSheet<void>(context, builder: (_) => const ReconfigurePanel());

/// Reconfigure = a fresh install, gated by the core.
///
/// Renders `reconfigureReadiness()` as it is: every blocker's localized label
/// with its live count, "Push now" (`reconfigurePushNow`), and "Reconfigure"
/// enabled only when the core says `allowed`. The panel decides nothing: it
/// re-reads the local readiness on a short timer (no network) and, once the
/// wipe succeeds, asks the app for a brand-new provider container.
class ReconfigurePanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const ReconfigurePanel({super.key});

  @override
  ConsumerState<ReconfigurePanel> createState() => _ReconfigurePanelState();
}

class _ReconfigurePanelState extends ConsumerState<ReconfigurePanel> {
  late ReconfigureReadinessView _ready;
  Timer? _tick;
  bool _pushing = false;
  bool _wiping = false;
  UiText? _error;

  @override
  void initState() {
    super.initState();
    _ready = ref.read(bridgeProvider).reconfigureReadiness();
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => _reread());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _reread() {
    if (!mounted || _wiping) return;
    setState(() => _ready = ref.read(bridgeProvider).reconfigureReadiness());
  }

  Future<void> _push() async {
    setState(() {
      _pushing = true;
      _error = null;
    });
    final ready = await ref.read(bridgeProvider).reconfigurePushNow();
    if (!mounted) return;
    setState(() {
      _pushing = false;
      _ready = ready;
    });
  }

  Future<void> _reconfigure() async {
    final bridge = ref.read(bridgeProvider);
    final ok = await showMadarConfirm(
      context,
      title: bridge.tr(key: 'reconfigure.confirm_title'),
      body: bridge.tr(key: 'reconfigure.confirm_body'),
      confirmLabel: bridge.tr(key: 'reconfigure.confirm'),
      cancelLabel: bridge.tr(key: 'common.cancel'),
    );
    if (!ok || !mounted) return;
    setState(() {
      _wiping = true;
      _error = null;
    });
    try {
      await bridge.startReconfigure();
    } on MadarError catch (e) {
      if (!mounted) return;
      setState(() {
        _wiping = false;
        _error = UiText.error(e);
        _ready = bridge.reconfigureReadiness();
      });
      return;
    }
    // The device is a first launch now: every provider and screen above is
    // derived from the wiped state, so the app starts a fresh container (and
    // with it the device-setup route).
    final reset = ref.read(deviceResetProvider.notifier);
    if (mounted) MadarSheet.close<void>(context);
    reset.reset();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final colors = context.madarColors;
    final ready = _ready;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.madarLayout.gutter,
        Space.lg,
        context.madarLayout.gutter,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MadarHeader(
            title: t('reconfigure.title'),
            actions: [
              MadarHeaderAction(
                glyph: MadarGlyph.close,
                tooltip: t('common.close'),
                onTap: () => MadarSheet.close<void>(context),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            t('reconfigure.body'),
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.lg),
          if (ready.allowed)
            NoticeBanner(
              key: const ValueKey('reconfigure-ready'),
              text: t('reconfigure.ready'),
              tone: ChipTone.success,
              icon: 'checkmark.circle',
            )
          else ...[
            MadarSectionHeader(text: t('reconfigure.blocked_header')),
            for (final b in ready.blockers)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: NoticeBanner(
                  key: ValueKey('blocker-${b.kind}-${b.tillId ?? ''}'),
                  text: b.label,
                  tone: b.kind == 'dead' ? ChipTone.danger : ChipTone.warning,
                  icon: b.kind == 'till_open'
                      ? 'lock'
                      : 'exclamationmark.circle',
                ),
              ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Space.sm),
            NoticeBanner(
              text: _error!.of(bridge),
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
          ],
          const SizedBox(height: Space.lg),
          MadarButton(
            key: const ValueKey('reconfigure-push'),
            label: t(_pushing ? 'reconfigure.pushing' : 'reconfigure.push_now'),
            glyph: MadarGlyph.refresh,
            variant: MadarButtonVariant.secondary,
            loading: _pushing,
            enabled: !_pushing && !_wiping,
            onTap: () => unawaited(_push()),
          ),
          const SizedBox(height: Space.sm),
          MadarButton(
            key: const ValueKey('reconfigure-confirm'),
            label: t('reconfigure.confirm'),
            variant: MadarButtonVariant.danger,
            loading: _wiping,
            enabled: ready.allowed && !_pushing && !_wiping,
            onTap: () => unawaited(_reconfigure()),
          ),
        ],
      ),
    );
  }
}
