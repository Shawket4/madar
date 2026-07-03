/// Open-shift — the continuation of login: login confirms WHO you are, this
/// confirms WHAT'S in the drawer. A name-first greeting, one isolated hero
/// count field (auto-focused), one loud primary. Wide screens split into the
/// same BrandPanel as login; narrow shows one calm centered column. A
/// pixel-and-behavior port of the Kotlin OpenShiftScreen.kt.
///
/// State lives in [openShiftProvider] (prefill, heartbeat, busy/error and the
/// connectivity chrome); the screen renders and forwards intents. Auth-flow
/// split-brand screen → keeps its own chrome (no MadarHeader).
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/brand_panel.dart';
import 'package:feature_shift/src/controls.dart';
import 'package:feature_shift/src/shift_providers.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Form column vertical inset (natives: 48.dp).
const double _formVPad = 48;

/// Narrow-layout logo mark size (natives: MadarMark(56.dp)).
const double _logoSize = 56;

/// Greeting name type (natives: 28.sp black, -0.5 tracking; Cairo tops out
/// at ExtraBold so w800 stands in for the natives' Black).
const double _greetingSize = 28;
const double _greetingTracking = -0.5;

/// Carryover hint inset (natives: 14.dp) and money size (natives: 20.sp).
const double _carryoverPad = 14;
const double _carryoverMoneySize = 20;

/// Opening-cash entry. Bridges through [bridgeProvider]; every call that can
/// move `app_route()`/session (open shift, sign out, shift adoption) hands
/// off to the shell inside [OpenShiftNotifier].
class OpenShiftScreen extends ConsumerStatefulWidget {
  /// Creates the open-shift screen.
  const OpenShiftScreen({super.key});

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
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    // Narrow slices: the heartbeat chrome repaints alone every 15s.
    final online = ref.watch(openShiftProvider.select((s) => s.online));
    final authPaused = ref.watch(
      openShiftProvider.select((s) => s.authPaused),
    );
    // Scaffold (not a bare ColoredBox): TextFields and text styling need a
    // Material ancestor — screens own their own Scaffold in this app.
    return Scaffold(
      backgroundColor: colors.bg,
      body: ResponsiveBuilder(
        builder: (context, info) {
          final form = SingleChildScrollView(
            child: _FormColumn(
              width: info.width,
              showLogo: !info.isWide,
              reason: _reason,
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
              // the order screen.
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
      ),
    );
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
    final bridge = ref.watch(bridgeProvider);
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
            ShiftCard(
              children: [
                ShiftSectionHeader(
                  text: t('shift.opening_cash'),
                  icon: 'banknote',
                ),
                AmountField(
                  amountMinor: openingMinor,
                  onAmountMinor: (v) =>
                      ref.read(openShiftProvider.notifier).setAmount(v),
                  currencyCode: currency,
                  autofocus: true,
                ),
                // Carried-over suggestion (previous declared closing).
                if (suggestedMinor > 0)
                  _CarryoverHint(
                    label: t('shift.suggested_from_close'),
                    suggestedMinor: suggestedMinor,
                    currency: currency,
                  ),
                // Discrepancy reason — only when the count deviates.
                if (needsReason)
                  ShiftTextField(
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
                text: error,
                tone: ChipTone.danger,
                icon: 'exclamationmark.circle',
              ),
              const SizedBox(height: Space.md),
            ] else
              const SizedBox(height: Space.xl),
            // ── Primary action ────────────────────────────────────────────
            ShiftButton(
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
            ShiftButton(
              label: t('shift.switch_teller'),
              variant: ShiftButtonVariant.ghost,
              onTap: () =>
                  unawaited(ref.read(openShiftProvider.notifier).signOut()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The carried-over opening-cash suggestion (previous declared closing) — a
/// tinted teal block carrying the prior figure as bold teal money, the twin of
/// CloseShift's ExpectedCashBlock (the figure this open count reconciles
/// against).
class _CarryoverHint extends StatelessWidget {
  const _CarryoverHint({
    required this.label,
    required this.suggestedMinor,
    required this.currency,
  });

  final String label;
  final int suggestedMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accentBg,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(_carryoverPad),
        child: Row(
          spacing: Space.sm,
          children: [
            MadarIcon(
              'clock.arrow.circlepath',
              tint: colors.accent,
              size: IconSize.sm,
            ),
            Expanded(
              child: Text(
                label,
                style: MadarType.label.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                ),
              ),
            ),
            MoneyText(
              suggestedMinor,
              currency: currency,
              style: MadarType.moneyLg.copyWith(fontSize: _carryoverMoneySize),
            ),
          ],
        ),
      ),
    );
  }
}
