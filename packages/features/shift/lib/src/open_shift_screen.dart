/// Open-shift — the continuation of login: login confirms WHO you are, this
/// confirms WHAT'S in the drawer. A name-first greeting, one isolated hero
/// count field (auto-focused), one loud primary. Wide screens split into the
/// same BrandPanel as login; narrow shows one calm centered column. A
/// pixel-and-behavior port of the Kotlin OpenShiftScreen.kt.
///
/// State lives in [openShiftProvider] (prefill, heartbeat, busy/error and the
/// connectivity chrome); the screen renders and forwards intents. Auth-flow
/// split-brand screen → keeps its own chrome (no MadarHeader). As the Till
/// tab's no-shift home (`embedded`) the shell already carries the
/// connectivity chrome, so the pinned banners stay off and the tab can hang
/// something under the card (a manager's drawers).
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/brand_panel.dart';
import 'package:feature_shift/src/shift_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Form column vertical inset (natives: 48.dp).
const double _formVPad = 48;

/// Narrow-layout logo mark size (natives: MadarMark(56.dp)).
const double _logoSize = 56;

/// Greeting name type (natives: 28.sp black, -0.5 tracking; Plex Sans Arabic
/// tops out at Bold, so `MadarType.heaviest` stands in for the natives'
/// Black).
const double _greetingSize = 28;
const double _greetingTracking = -0.5;

/// Opening-cash entry. Bridges through [bridgeProvider]; every call that can
/// move `app_route()`/session (open shift, sign out, shift adoption) hands
/// off to the shell inside [OpenShiftNotifier].
class OpenShiftScreen extends ConsumerStatefulWidget {
  /// Creates the open-shift screen.
  const OpenShiftScreen({super.key, this.embedded = false, this.below});

  /// Rendered inside the Till tab: the shell owns the offline / auth-paused
  /// banners, so this screen paints none of its own.
  final bool embedded;

  /// A block under the form column (the manager's drawers on the Till tab).
  final Widget? below;

  @override
  ConsumerState<OpenShiftScreen> createState() => _OpenShiftScreenState();
}

class _OpenShiftScreenState extends ConsumerState<OpenShiftScreen> {
  /// Discrepancy-reason text — widget-local ephemera; visible state flows
  /// from [openShiftProvider].
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    // Narrow slices: the heartbeat chrome repaints alone every 15s.
    final online = ref.watch(openShiftProvider.select((s) => s.online));
    final authPaused = ref.watch(openShiftProvider.select((s) => s.authPaused));
    // The page shell, so the banners pinned at top: 0 below sit under the
    // status bar rather than behind the clock. `embedded` means the tab
    // shell is above us and has already paid that inset.
    final page = ResponsiveBuilder(
      builder: (context, info) {
        final form = SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FormColumn(
                width: info.width,
                showLogo: !info.isWide,
                reason: _reason,
              ),
              if (widget.below case final below?)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.formWidth(info.width),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: Space.xxl,
                      end: Space.xxl,
                      bottom: _formVPad,
                    ),
                    child: below,
                  ),
                ),
            ],
          ),
        );
        return Stack(
          children: [
            if (info.isWide)
              Row(
                children: [
                  Expanded(
                    child: SizedBox.expand(
                      child: BrandPanel(
                        tr: t,
                        arabic: bridge.locale().startsWith('ar'),
                      ),
                    ),
                  ),
                  Expanded(child: Center(child: form)),
                ],
              )
            else
              Center(child: form),
            // Top-pinned chrome so a teller WAITING here still sees +
            // recovers connectivity / a genuine session expiry — not only on
            // the order screen. Off when the shell above carries it.
            if (!widget.embedded)
              PositionedDirectional(
                top: 0,
                start: 0,
                end: 0,
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.sm,
                  ),
                  child: Column(
                    spacing: Space.sm,
                    children: [
                      if (!online)
                        NoticeBanner(
                          text: t('chrome.offline_banner'),
                          icon: 'wifi.slash',
                        ),
                      if (authPaused)
                        NoticeBanner(
                          text: t('chrome.auth_paused'),
                          tone: ChipTone.danger,
                          icon: 'lock',
                          trailing: BannerActionPill(
                            label: t('chrome.auth_paused_action'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
    // Embedded, the Till tab's page shell is the page and its header: the
    // form on the grid's form width, and none of the sign-in's branding —
    // the teller is already in, and "Welcome back" under a header that says
    // Till is two screens talking at once.
    if (widget.embedded) {
      return SingleChildScrollView(
        padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.xl,
          children: [
            _OpeningForm(reason: _reason),
            ?widget.below,
          ],
        ),
      );
    }
    return MadarPageScaffold(body: page);
  }
}

class _FormColumn extends ConsumerWidget {
  const _FormColumn({
    required this.width,
    required this.showLogo,
    required this.reason,
  });

  final double width;
  final bool showLogo;
  final TextEditingController reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    // Narrow slices — the count keystrokes must not repaint the chrome
    // banners above, and the heartbeat must not repaint this form.
    final openingMinor = ref.watch(
      openShiftProvider.select((s) => s.openingMinor),
    );
    final suggestedMinor = ref.watch(
      openShiftProvider.select((s) => s.suggestedMinor),
    );
    final needsReason = ref.watch(
      openShiftProvider.select((s) => s.needsReason),
    );
    final busy = ref.watch(openShiftProvider.select((s) => s.busy));
    final error = ref.watch(openShiftProvider.select((s) => s.error));
    final session = bridge.currentSession();
    final currency = session?.currencyCode ?? '';
    final branchName = bridge.deviceConfig().branchName ?? '';

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: Responsive.formWidth(width)),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.xxl,
          vertical: _formVPad,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showLogo) ...[
              const Center(child: MadarSymbol(size: _logoSize)),
              const SizedBox(height: Space.xl),
            ],
            // ── Greeting (the teller's name IS the hero) ──────────────────
            Text(
              t('shift.welcome'),
              textAlign: TextAlign.center,
              style: MadarType.title.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              session?.displayName ?? t('shift.open_title'),
              textAlign: TextAlign.center,
              style: MadarType.h1.copyWith(
                fontSize: _greetingSize,
                letterSpacing: _greetingTracking,
                color: colors.textPrimary,
              ),
            ),
            if (branchName.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Center(
                child: StatusChip(
                  label: branchName,
                  tone: ChipTone.info,
                  icon: 'building.2',
                ),
              ),
            ],
            const SizedBox(height: Space.xxl),
            // ── Hero count field (the one thing the teller must do) ───────
            MadarCard.column(
              children: [
                MadarSectionHeader(
                  text: t('shift.opening_cash'),
                  icon: 'banknote',
                ),
                // Keyed on the suggestion: the carry-over lands a beat after
                // the field mounts, and the kit's field only syncs a value
                // it has already seen once (its `late _lastEmitted` is first
                // read inside didUpdateWidget, against the NEW widget). A
                // fresh mount takes the prefill as its initial text.
                MadarAmountField(
                  key: ValueKey(suggestedMinor),
                  amountMinor: openingMinor,
                  onAmountMinor: (v) =>
                      ref.read(openShiftProvider.notifier).setAmount(v),
                  currencyCode: currency,
                  autofocus: true,
                ),
                // Carried-over suggestion (previous declared closing).
                if (suggestedMinor > 0)
                  MadarSummaryLine(
                    label: t('shift.suggested_from_close'),
                    minor: suggestedMinor,
                    currency: currency,
                    tone: MadarTone.accent,
                  ),
                // Discrepancy reason — only when the count deviates.
                if (needsReason)
                  MadarField(
                    controller: reason,
                    placeholder: t('shift.opening_reason_label'),
                    icon: 'exclamationmark.bubble',
                  ),
                Text(
                  needsReason
                      ? t('shift.opening_reason_hint')
                      : t('shift.opening_hint'),
                  textAlign: TextAlign.center,
                  style: MadarType.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
            // ── Error (next to the action that triggers it) ────────────────
            if (error != null) ...[
              const SizedBox(height: Space.xl),
              NoticeBanner(
                text: error.of(ref.bridge),
                tone: ChipTone.danger,
                icon: 'exclamationmark.circle',
              ),
              const SizedBox(height: Space.md),
            ] else
              const SizedBox(height: Space.xl),
            // ── Primary action ────────────────────────────────────────────
            MadarButton(
              label: t('shift.open_button'),
              icon: 'lock.open',
              loading: busy,
              onTap: () => unawaited(
                ref
                    .read(openShiftProvider.notifier)
                    .submit(reason: reason.text),
              ),
            ),
            const SizedBox(height: Space.sm),
            // ── Recessive exit ────────────────────────────────────────────
            MadarButton(
              label: t('shift.switch_teller'),
              variant: MadarButtonVariant.ghost,
              onTap: () =>
                  unawaited(ref.read(openShiftProvider.notifier).signOut()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The opening count on the Till tab: the amount (prefilled from the last
/// close), the reason when it differs, the error beside the action, Open
/// shift, and the way out for the wrong teller.
class _OpeningForm extends ConsumerWidget {
  const _OpeningForm({required this.reason});

  final TextEditingController reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final openingMinor = ref.watch(
      openShiftProvider.select((s) => s.openingMinor),
    );
    final suggestedMinor = ref.watch(
      openShiftProvider.select((s) => s.suggestedMinor),
    );
    final needsReason = ref.watch(
      openShiftProvider.select((s) => s.needsReason),
    );
    final busy = ref.watch(openShiftProvider.select((s) => s.busy));
    final error = ref.watch(openShiftProvider.select((s) => s.error));
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final notifier = ref.read(openShiftProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(text: t('shift.opening_cash')),
        MadarCard.column(
          children: [
            // Keyed on the suggestion: the carry-over lands a beat after the
            // field mounts, and a fresh mount takes it as its initial text.
            MadarAmountField(
              key: ValueKey(suggestedMinor),
              amountMinor: openingMinor,
              onAmountMinor: notifier.setAmount,
              currencyCode: currency,
              autofocus: true,
            ),
            if (suggestedMinor > 0)
              MadarSummaryLine(
                label: t('shift.suggested_from_close'),
                minor: suggestedMinor,
                currency: currency,
                tone: MadarTone.accent,
              ),
            if (needsReason)
              MadarField(
                controller: reason,
                placeholder: t('shift.opening_reason_label'),
                glyph: MadarGlyph.alertCircle,
              ),
            Text(
              needsReason
                  ? t('shift.opening_reason_hint')
                  : t('shift.opening_hint'),
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
            if (error != null)
              NoticeBanner(
                text: error.of(bridge),
                tone: ChipTone.danger,
                icon: 'exclamationmark.circle',
              ),
            MadarButton(
              label: t('shift.open_button'),
              glyph: MadarGlyph.lock,
              loading: busy,
              onTap: () => unawaited(notifier.submit(reason: reason.text)),
            ),
            MadarButton(
              label: t('shift.switch_teller'),
              variant: MadarButtonVariant.ghost,
              onTap: () => unawaited(notifier.signOut()),
            ),
          ],
        ),
      ],
    );
  }
}
