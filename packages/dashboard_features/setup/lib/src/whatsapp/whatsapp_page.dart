/// `/settings/whatsapp` WhatsApp, platform admins only (`features/whatsapp/whatsapp-page.tsx`, SET-WA rows).
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane. The connection card shows the
/// gateway's link state (not configured, unreachable, linked, a pairing QR,
/// not linked) and the pause card mutes sending. The status is polled every
/// 2.5 s while the app is in front, and again on coming back to it.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart'
    show PauseInput, WhatsappApi, WhatsappStatus;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/scope.dart' show SetupRefusalPane;
import 'whatsapp_providers.dart';

/// The web's fixed sizes.
abstract final class WhatsappMetrics {
  /// The glyph tile beside a card's title (`size-9`).
  static const double tile = Space.xxl + Space.xs;

  /// The pairing QR (`size-60`).
  static const double qr = Space.xxl * 7.5;

  /// The steps under the QR and the pause hint (`max-w-xs`).
  static const double narrow = Space.xxl * 10;
}

/// Warms the status read on intent (beyond the web: `route-prefetch.ts` has
/// no case for this path); [whatsappWarmProvider] asks only for a platform
/// admin, the one person the pane reads for.
void prefetchWhatsapp(DashPrefetcher warm, Scope _) =>
    warm(whatsappWarmProvider);

class WhatsappPage extends ConsumerStatefulWidget {
  const WhatsappPage({super.key});

  @override
  ConsumerState<WhatsappPage> createState() => _WhatsappPageState();
}

class _WhatsappPageState extends ConsumerState<WhatsappPage> {
  late final Timer _poll;
  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;
  bool _pairing = false;
  bool _unlinking = false;
  bool _pausing = false;

  /// The web asks the signed-in role (`super_admin`), not the grants.
  bool get _superAdmin => ref.read(currentSessionProvider)?.isPlatform ?? false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(kWhatsappPoll, (_) => _onPoll());
    _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
  }

  @override
  void dispose() {
    _poll.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  /// `refetchInterval`: only while the app shows (React Query pauses a
  /// hidden tab), and never on top of a read in flight.
  void _onPoll() {
    final life = WidgetsBinding.instance.lifecycleState;
    if (!mounted || !_superAdmin) return;
    if (life != null &&
        life != AppLifecycleState.resumed &&
        life != AppLifecycleState.inactive) {
      return;
    }
    if (ref.read(whatsappStatusProvider).isLoading) return;
    ref.invalidate(whatsappStatusProvider);
  }

  void _onHide() => _hiddenAt = ref.read(clockProvider)();

  /// `refetchOnWindowFocus`: back after the status went stale (30 s).
  void _onShow() {
    final at = _hiddenAt;
    _hiddenAt = null;
    if (at == null || !mounted || !_superAdmin) return;
    if (ref.read(clockProvider)().difference(at) < kQueryStaleTime) return;
    ref.invalidate(whatsappStatusProvider);
  }

  /// Runs a write whose answer replaces the cached status; a failure toasts
  /// the server's words. Returns the new status (null on failure).
  Future<WhatsappStatus?> _mutate(
    void Function(bool busy) busy,
    Future<WhatsappStatus> Function(WhatsappApi api) call,
  ) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).whatsapp;
    // Captured before the await: the page may close mid-save.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => busy(true));
    try {
      final s = await call(api);
      container.read(whatsappStatusProvider.notifier).write(s);
      return s;
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
      return null;
    } finally {
      if (mounted) setState(() => busy(false));
    }
  }

  Future<void> _pair() =>
      _mutate((b) => _pairing = b, (api) => api.whatsappPair());

  Future<void> _unlink() async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('whatsapp.unlinkTitle'),
      description: t('whatsapp.unlinkHint'),
      confirmLabel: t('whatsapp.unlink'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final s = await _mutate(
      (b) => _unlinking = b,
      (api) => api.whatsappLogout(),
    );
    if (s != null && mounted) {
      DashToast.success(context, t('whatsapp.unlinkedToast'));
    }
  }

  Future<void> _pause(bool paused) async {
    final t = ref.read(tProvider);
    final s = await _mutate(
      (b) => _pausing = b,
      (api) => api.whatsappPause(body: PauseInput(paused: paused)),
    );
    if (s != null && mounted) {
      DashToast.success(
        context,
        t(s.paused ? 'whatsapp.pausedToast' : 'whatsapp.resumedToast'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final title = t('whatsapp.title');
    final superAdmin =
        ref.watch(currentSessionProvider.select((s) => s?.isPlatform)) ?? false;
    if (!superAdmin) {
      return SetupRefusalPane(
        key: const ValueKey('whatsapp-forbidden'),
        title: title,
        stateTitle: t('whatsapp.forbidden'),
        icon: 'message-circle',
      );
    }
    final q = ref.watch(whatsappStatusProvider);
    final status = q.value;
    return DashPageScaffold(
      title: title,
      subtitle: t('whatsapp.subtitle'),
      width: DashPageWidth.reading,
      actions: [
        DashButton(
          key: const ValueKey('whatsapp-refresh'),
          label: t('common.refresh'),
          icon: 'refresh-cw',
          variant: DashButtonVariant.outline,
          // Follows every fetch, the background poll's too (SET-WA-017).
          loading: q.isLoading,
          onPressed: () => ref.invalidate(whatsappStatusProvider),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          DashCard(
            key: const ValueKey('whatsapp-connection'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.lg,
              children: [
                _CardHead(
                  icon: 'message-circle',
                  title: t('whatsapp.connection'),
                  hint: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${t('whatsapp.session')}: '),
                        TextSpan(
                          text: status?.session ?? '—',
                          style: DashType.mono.copyWith(
                            fontSize: DashType.small.fontSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: _StatusBadge(
                    status: q.awaitingFirst ? null : status,
                  ),
                ),
                _connectionBody(t, q),
              ],
            ),
          ),
          if (status?.configured ?? false)
            DashCard(
              key: const ValueKey('whatsapp-pause'),
              child: _CardHead(
                icon: 'pause-circle',
                title: t('whatsapp.pauseTitle'),
                hint: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: WhatsappMetrics.narrow,
                  ),
                  child: Text(t('whatsapp.pauseHint')),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.sm,
                  children: [
                    if (status!.paused)
                      DashStatusPill(
                        label: t('whatsapp.paused'),
                        tone: DashTone.warning,
                      ),
                    DashSwitch(
                      key: const ValueKey('whatsapp-pause-switch'),
                      value: status.paused,
                      semanticLabel: t('whatsapp.pauseTitle'),
                      enabled: !_pausing,
                      onChanged: _pause,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _connectionBody(Translator t, AsyncValue<WhatsappStatus> q) {
    final c = context.madarColors;
    final s = q.value;
    final busy = _pairing || _unlinking;
    if (q.awaitingFirst) {
      return const Padding(
        key: ValueKey('whatsapp-skeleton'),
        padding: EdgeInsets.symmetric(vertical: Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            DashSkeleton(height: Space.xxl + Space.lg, radius: Radii.control),
            DashSkeleton(height: Space.xxl + Space.sm, radius: Radii.control),
          ],
        ),
      );
    }
    // The web falls through to "Gateway not configured" here (divergence).
    if (q.failedFirst || s == null) {
      return DashErrorState(
        key: const ValueKey('whatsapp-error'),
        framed: false,
        title: t('common.loadFailed'),
        message: errorMessage(q.error, t),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(whatsappStatusProvider),
      );
    }
    if (!s.configured) {
      return _Notice(
        title: t('whatsapp.notConfigured'),
        body: t('whatsapp.notConfiguredHint'),
      );
    }
    if (!s.reachable) {
      return _Notice(
        title: t('whatsapp.unreachable'),
        body: t('whatsapp.unreachableHint'),
      );
    }
    if (s.loggedIn) {
      final fg = DashTone.success.foreground(c);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.lg,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: DashTone.success.wash(c),
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Row(
              spacing: Space.md,
              children: [
                DashIcon('check-circle-2', size: IconSize.lg, color: fg),
                Expanded(
                  child: Text(
                    t('whatsapp.linked'),
                    style: DashType.bodyMedium.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ),
          _OutlineDangerButton(
            key: const ValueKey('whatsapp-unlink'),
            label: t('whatsapp.unlink'),
            icon: 'power',
            loading: _unlinking,
            expand: MediaQuery.sizeOf(context).width < DashBreakpoints.sm,
            onPressed: busy ? null : _unlink,
          ),
        ],
      );
    }
    final qr = s.hasQr ? _qrBytes(s.qrImage) : null;
    if (qr != null) {
      final steps = [
        t('whatsapp.step1'),
        t('whatsapp.step2'),
        t('whatsapp.step3'),
      ];
      final style = DashType.small.copyWith(color: c.textMuted);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Column(
          spacing: Space.md,
          children: [
            Container(
              key: const ValueKey('whatsapp-qr'),
              width: WhatsappMetrics.qr,
              height: WhatsappMetrics.qr,
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                // The code sits on paper white in both themes.
                color: MadarColors.light.surface,
                borderRadius: BorderRadius.circular(Radii.xs),
                border: Border.all(color: c.hairline),
              ),
              child: Image.memory(
                qr,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
                semanticLabel: t('whatsapp.qrAlt'),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: WhatsappMetrics.narrow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.xs,
                children: [
                  for (final (i, step) in steps.indexed)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: Space.xl - Space.xs,
                          child: Text('${i + 1}.', style: style),
                        ),
                        Expanded(child: Text(step, style: style)),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      key: const ValueKey('whatsapp-not-linked'),
      padding: const EdgeInsets.symmetric(vertical: Space.xl),
      child: Column(
        spacing: Space.md,
        children: [
          Container(
            width: DashMetrics.badgeDisc,
            height: DashMetrics.badgeDisc,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
            child: DashIcon('qr-code', size: IconSize.xxl, color: c.textMuted),
          ),
          Text(
            t('whatsapp.notLinked'),
            textAlign: TextAlign.center,
            style: DashType.body.copyWith(color: c.textMuted),
          ),
          DashButton(
            key: const ValueKey('whatsapp-pair'),
            label: t('whatsapp.startPairing'),
            icon: 'smartphone',
            loading: _pairing,
            onPressed: busy ? null : _pair,
          ),
        ],
      ),
    );
  }
}

/// The QR's PNG bytes from its `data:` URL (null when it is not one).
Uint8List? _qrBytes(String? url) {
  if (url == null) return null;
  try {
    return UriData.parse(url).contentAsBytes();
  } on FormatException {
    return null;
  }
}

/// A card's head: the glyph tile, the title over a muted line, and
/// [trailing] at the end.
class _CardHead extends StatelessWidget {
  const _CardHead({
    required this.icon,
    required this.title,
    required this.hint,
    required this.trailing,
  });

  final String icon;
  final String title;
  final Widget hint;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Row(
      spacing: Space.md,
      children: [
        Container(
          width: WhatsappMetrics.tile,
          height: WhatsappMetrics.tile,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: DashIcon(icon, color: c.textMuted),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: DashType.sectionTitle),
              DefaultTextStyle.merge(
                style: DashType.small.copyWith(color: c.textMuted),
                child: hint,
              ),
            ],
          ),
        ),
        trailing,
      ],
    );
  }
}

/// The connection pill (the web's `StatusBadge`): no status yet → Checking.
class _StatusBadge extends ConsumerWidget {
  const _StatusBadge({required this.status});

  final WhatsappStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final s = status;
    final (key, tone, icon) = s == null
        ? ('whatsapp.checking', DashTone.neutral, null)
        : !s.configured || !s.reachable
        ? ('whatsapp.offline', DashTone.warning, null)
        : s.loggedIn
        ? ('whatsapp.connected', DashTone.success, null)
        : ('whatsapp.awaitingScan', DashTone.accent, 'qr-code');
    return DashStatusPill(
      key: const ValueKey('whatsapp-status'),
      label: t(key),
      tone: tone,
      icon: icon,
    );
  }
}

/// A warning line (the web's `Notice`).
class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      key: const ValueKey('whatsapp-notice'),
      width: double.infinity,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: DashTone.warning.wash(c),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: DashMetrics.hair),
            child: DashIcon(
              'alert-triangle',
              size: IconSize.lg,
              color: DashTone.warning.foreground(c),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DashType.bodyStrong),
                Text(body, style: DashType.body.copyWith(color: c.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An outline button with red words (the web's `variant="outline"
/// className="text-destructive"`).
// ponytail: local until the kit has `DashButtonVariant.outlineDanger` (kit
// candidate; sell keeps its own copy too).
class _OutlineDangerButton extends StatelessWidget {
  const _OutlineDangerButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
    this.expand = false,
    super.key,
  });

  final String label;
  final String icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final enabled = onPressed != null && !loading;
    final fg = c.errorText.withValues(alpha: enabled ? 1 : 0.6);
    final radius = BorderRadius.circular(Radii.sm);
    return DashPressable(
      onTap: enabled ? onPressed : null,
      enabled: enabled,
      semanticLabel: label,
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        height: DashMetrics.control,
        constraints: const BoxConstraints(minWidth: DashMetrics.target),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.md),
        foregroundDecoration: dashFocusRing(context, s, radius),
        decoration: BoxDecoration(
          color: s.highlighted ? c.danger.withValues(alpha: 0.1) : c.card,
          borderRadius: radius,
          border: Border.all(color: c.input),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: Space.sm,
          children: [
            if (loading)
              SizedBox.square(
                dimension: IconSize.sm,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            else
              DashIcon(icon, color: fg),
            Flexible(
              child: MadarClippedText(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyMedium.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
