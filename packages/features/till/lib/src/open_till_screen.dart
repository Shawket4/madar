/// Open-till — the continuation of login: login confirms WHO you are, this
/// confirms WHAT'S in the drawer. A name-first greeting, one isolated hero
/// count field (auto-focused), one loud primary. Wide screens split into the
/// same BrandPanel as login; narrow shows one calm centered column. A
/// pixel-and-behavior port of the Kotlin OpenTillScreen.kt.
///
/// State lives in [openTillProvider] (prefill, heartbeat, busy/error and the
/// connectivity chrome); the screen renders and forwards intents. Auth-flow
/// split-brand screen → keeps its own chrome (no MadarHeader). As the Till
/// tab's no-till home (`embedded`) the shell already carries the
/// connectivity chrome, so the pinned banners stay off and the tab can hang
/// something under the card (a manager's drawers).
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_till/src/brand_panel.dart';
import 'package:feature_till/src/till_notices.dart';
import 'package:feature_till/src/till_providers.dart';
import 'package:feature_till/src/till_sync_strip.dart';
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
/// move `app_route()`/session (open till, sign out, till adoption) hands
/// off to the shell inside [OpenTillNotifier].
class OpenTillScreen extends ConsumerStatefulWidget {
  /// Creates the open-till screen.
  const OpenTillScreen({super.key, this.embedded = false, this.below});

  /// Rendered inside the Till tab: the shell owns the offline / auth-paused
  /// banners, so this screen paints none of its own.
  final bool embedded;

  /// A block under the form column (the manager's drawers on the Till tab).
  final Widget? below;

  @override
  ConsumerState<OpenTillScreen> createState() => _OpenTillScreenState();
}

class _OpenTillScreenState extends ConsumerState<OpenTillScreen> {
  /// Discrepancy-reason text — widget-local ephemera; visible state flows
  /// from [openTillProvider].
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
    final online = ref.watch(openTillProvider.select((s) => s.online));
    final authPaused = ref.watch(openTillProvider.select((s) => s.authPaused));
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
      // The core's ONE answer on the lock: why the device is walled here and
      // what to do next. A refusal it cannot satisfy (no permission) drops
      // the counting form — a field nobody may submit is a dead end.
      final lock = ref.watch(shellProvider.select((s) => s.lock));
      return SingleChildScrollView(
        // The Till tab pulls to refresh, with no drawer open too.
        physics: MadarRefresh.physics,
        padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.xl,
          children: [
            if (lock.locked) TillLockNotice(lock: lock),
            const _OpenNotices(),
            if (lock.canOpen || !lock.locked)
              _OpeningForm(reason: _reason)
            else
              const _SwitchPersonOnly(),
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
      openTillProvider.select((s) => s.openingMinor),
    );
    final suggestedMinor = ref.watch(
      openTillProvider.select((s) => s.suggestedMinor),
    );
    final needsReason = ref.watch(
      openTillProvider.select((s) => s.needsReason),
    );
    final busy = ref.watch(openTillProvider.select((s) => s.busy));
    final error = ref.watch(openTillProvider.select((s) => s.error));
    final blocked = ref.watch(
      openTillProvider.select((s) => s.elsewhere != null),
    );
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
              t('till.welcome'),
              textAlign: TextAlign.center,
              style: MadarType.title.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              session?.displayName ?? t('till.open_title'),
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
            if (ref.watch(shellProvider.select((s) => s.lock)) case final lock
                when lock.locked) ...[
              TillLockNotice(lock: lock),
              const SizedBox(height: Space.lg),
            ],
            const _OpenNotices(),
            // ── Hero count field (the one thing the teller must do) ───────
            MadarCard.column(
              children: [
                MadarSectionHeader(
                  text: t('till.opening_cash'),
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
                      ref.read(openTillProvider.notifier).setAmount(v),
                  currencyCode: currency,
                  autofocus: true,
                ),
                // Carried-over suggestion (previous declared closing).
                if (suggestedMinor > 0)
                  MadarSummaryLine(
                    label: t('till.suggested_from_close'),
                    minor: suggestedMinor,
                    currency: currency,
                    tone: MadarTone.accent,
                  ),
                // Discrepancy reason — only when the count deviates.
                if (needsReason)
                  MadarField(
                    controller: reason,
                    placeholder: t('till.opening_reason_label'),
                    kind: MadarFieldKind.note,
                    icon: 'exclamationmark.bubble',
                  ),
                Text(
                  needsReason
                      ? t('till.opening_reason_hint')
                      : t('till.opening_hint'),
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
              label: t('till.open_button'),
              icon: 'lock.open',
              loading: busy,
              enabled: !blocked,
              onTap: () => unawaited(
                ref.read(openTillProvider.notifier).submit(reason: reason.text),
              ),
            ),
            const SizedBox(height: Space.sm),
            // ── Recessive exit ────────────────────────────────────────────
            MadarButton(
              label: t('till.switch_teller'),
              variant: MadarButtonVariant.ghost,
              onTap: () =>
                  unawaited(ref.read(openTillProvider.notifier).signOut()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The opening count on the Till tab: the amount (prefilled from the last
/// close), the reason when it differs, the error beside the action, Open
/// till, and the way out for the wrong teller.
class _OpeningForm extends ConsumerWidget {
  const _OpeningForm({required this.reason});

  final TextEditingController reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final openingMinor = ref.watch(
      openTillProvider.select((s) => s.openingMinor),
    );
    final suggestedMinor = ref.watch(
      openTillProvider.select((s) => s.suggestedMinor),
    );
    final needsReason = ref.watch(
      openTillProvider.select((s) => s.needsReason),
    );
    final busy = ref.watch(openTillProvider.select((s) => s.busy));
    final error = ref.watch(openTillProvider.select((s) => s.error));
    final blocked = ref.watch(
      openTillProvider.select((s) => s.elsewhere != null),
    );
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final notifier = ref.read(openTillProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(text: t('till.opening_cash')),
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
                label: t('till.suggested_from_close'),
                minor: suggestedMinor,
                currency: currency,
                tone: MadarTone.accent,
              ),
            if (needsReason)
              MadarField(
                controller: reason,
                placeholder: t('till.opening_reason_label'),
                kind: MadarFieldKind.note,
                glyph: MadarGlyph.alertCircle,
              ),
            Text(
              needsReason
                  ? t('till.opening_reason_hint')
                  : t('till.opening_hint'),
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
            if (error != null)
              NoticeBanner(
                text: error.of(bridge),
                tone: ChipTone.danger,
                icon: 'exclamationmark.circle',
              ),
            MadarButton(
              label: t('till.open_button'),
              glyph: MadarGlyph.lock,
              loading: busy,
              enabled: !blocked,
              onTap: () => unawaited(notifier.submit(reason: reason.text)),
            ),
            MadarButton(
              label: t('till.switch_teller'),
              variant: MadarButtonVariant.ghost,
              onTap: () => unawaited(notifier.signOut()),
            ),
          ],
        ),
      ],
    );
  }
}

/// What stands around opening: the till still open on another device (it
/// blocks, and a manager may force-close it), the bills left open at the
/// branch, and how the sync is going. Nothing here but the first blocks.
class _OpenNotices extends ConsumerWidget {
  const _OpenNotices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elsewhere = ref.watch(openTillProvider.select((s) => s.elsewhere));
    final notice = ref.watch(openTillProvider.select((s) => s.notice));
    final isManager = ref.watch(openTillProvider.select((s) => s.isManager));
    final forceClosing = ref.watch(
      openTillProvider.select((s) => s.forceClosing),
    );
    final notifier = ref.read(openTillProvider.notifier);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          if (elsewhere != null)
            TillElsewherePanel(
              elsewhere: elsewhere,
              canForceClose: isManager,
              forceClosing: forceClosing,
              onForceClose: (reason) =>
                  unawaited(notifier.forceCloseElsewhere(reason)),
            ),
          if (notice != null && notice.openBillsCount > 0)
            OpenBillsNoticeBanner(notice: notice),
          const TillSyncStrip(),
        ],
      ),
    );
  }
}

/// When the person may not open a till at all, the only way forward is to
/// let the right person in. Never a dead end, never a bare error.
class _SwitchPersonOnly extends ConsumerWidget {
  const _SwitchPersonOnly();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    return MadarCard.column(
      children: [
        MadarButton(
          label: bridge.tr(key: 'till.switch_teller'),
          glyph: MadarGlyph.signOut,
          onTap: () => unawaited(ref.read(openTillProvider.notifier).signOut()),
        ),
      ],
    );
  }
}
