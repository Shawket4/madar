import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/providers.dart';
import 'package:feature_auth/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Native metrics (ReauthScreen.kt literals) kept verbatim.

/// Sheet card width cap (natives: `maxWidth = 440.dp`).
const double _sheetMaxWidth = 440;

/// Header icon tile side (natives: 44.dp).
const double _headerTileSize = 44;

/// Header title size (natives: 20.sp over Type.h2).
const double _headerTitleSize = 20;

/// Header body size (natives: 12.sp over Type.bodySm).
const double _headerBodySize = 12;

/// Close-glyph squircle side / glyph size (natives: 32.dp / 14.dp).
const double _closeSize = 32;
const double _closeGlyph = 14;

/// Sign-in CTA height (natives pass 52.dp, below Metrics.buttonHeight).
const double _ctaHeight = 52;

/// Switch-teller link size (natives: 13.sp SemiBold).
const double _switchLinkSize = 13;

/// How the re-auth sheet was resolved.
enum ReauthOutcome {
  /// The same teller re-entered a valid PIN — the outbox is un-parked and the
  /// backlog drained. The presenter should refresh pending counts and show
  /// the `chrome.sync_resumed` success toast (natives: `reauth(pin)` →
  /// `refreshPending` + toast).
  resumed,

  /// The teller chose the escape hatch — the presenter must open the
  /// close-shift flow so a different teller can sign in (natives:
  /// `reauthSwitchTeller()` → `showCloseShift = true`).
  switchTeller,
}

/// Presents [ReauthSheet] in the shared Madar sheet (natives:
/// `MadarSheet(size = HUG, maxWidth = 440.dp)`). Reads its providers
/// internally — resets the PIN buffer before presenting so the sheet never
/// inherits a previous entry.
///
/// Resolves to a [ReauthOutcome], or null when dismissed via scrim / drag /
/// back (natives: `showReauth = false`, sync stays paused).
Future<ReauthOutcome?> showReauthSheet(BuildContext context) {
  ProviderScope.containerOf(
    context,
    listen: false,
  ).read(authProvider.notifier).resetEntry();
  return showMadarSheet<ReauthOutcome>(
    context,
    size: SheetSize.hug,
    maxWidth: _sheetMaxWidth,
    builder: (_) => const ReauthSheet(),
  );
}

/// Re-auth prompt shown when the bearer token expired mid-shift
/// (`syncStatus().authPaused` — the outbox parked on a 401 while it still
/// holds orders). The teller who owns the OPEN shift re-enters their PIN to
/// resume syncing — same teller, no handover; `signIn` un-parks the queue
/// and drains the backlog WITHOUT wiping the outbox. The escape hatch pops
/// [ReauthOutcome.switchTeller] so the presenter can close the shift and
/// route to login for a new teller. Port of the natives' ReauthScreen.kt /
/// ReauthView.swift, presented via [showReauthSheet].
class ReauthSheet extends ConsumerWidget {
  /// Creates the re-auth sheet.
  const ReauthSheet({super.key});

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final resumed = await ref.read(authProvider.notifier).reauthenticate();
    if (!resumed || !context.mounted) return;
    await Navigator.of(context).maybePop(ReauthOutcome.resumed);
  }

  void _digit(BuildContext context, WidgetRef ref, String digit) {
    if (ref.read(authProvider.notifier).pushDigit(digit)) {
      unawaited(_submit(context, ref));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Every rejected submit (short PIN, bridge failure) bumps the fail
    // counter — warning haptic once per failure (natives' `reauth(pin)`).
    ref.listen(authProvider.select((s) => s.failCount), (previous, next) {
      if (previous != null && next > previous) MadarHaptics.warning();
    });
    final pin = ref.watch(authProvider.select((s) => s.pin));
    final busy = ref.watch(authProvider.select((s) => s.busy));
    final error = ref.watch(authProvider.select((s) => s.error));

    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final tellerName = bridge.currentSession()?.displayName ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReauthHeader(
          title: t('chrome.reauth_title'),
          body: t('chrome.reauth_body'),
          onClose: () => unawaited(Navigator.of(context).maybePop()),
        ),
        // Deliberate rhythm mirrors the Login PIN pad (not a flat stack):
        // the identity pill sits up top, then xxl of air above the pad (and
        // xl below) so it reads as the hero, sm before the CTA, and a clear
        // gap down to the quiet escape hatch.
        ColoredBox(
          color: colors.surfaceAlt,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
              vertical: Space.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Locked to the current teller — no name field, just the
                // shared tinted-teal identity pill (same StatusChip the
                // Login branch pill uses).
                StatusChip(
                  label: '${t('chrome.reauth_as')} $tellerName',
                  tone: ChipTone.accent,
                  icon: 'person.crop.circle.badge.clock',
                ),
                const SizedBox(height: Space.xxl),
                PinPad(
                  pin: pin,
                  onDigit: (digit) => _digit(context, ref, digit),
                  onBackspace: ref.read(authProvider.notifier).popDigit,
                ),
                if (error != null) ...[
                  const SizedBox(height: Space.sm),
                  NoticeBanner(
                    text: error,
                    tone: ChipTone.danger,
                    icon: 'exclamationmark.circle',
                  ),
                ],
                const SizedBox(height: Space.xl),
                // The sign-in CTA carries the weight — bold teal fill, the
                // brightest thing on the sheet (mirrors the Login pad).
                MadarButton(
                  label: t('login.sign_in'),
                  onPressed: () => unawaited(_submit(context, ref)),
                  loading: busy,
                  height: _ctaHeight,
                  icon: 'arrow.right.circle',
                ),
                const SizedBox(height: Space.sm),
                // Escape hatch — close the shift and route a different
                // teller to login.
                _SwitchTellerLink(
                  label: t('chrome.reauth_switch'),
                  onTap: () => unawaited(
                    Navigator.of(
                      context,
                    ).maybePop(ReauthOutcome.switchTeller),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The sheet header — a leading accent-tinted icon tile (the signature
/// tone-tile pattern), the hero title + supporting body, and a trailing
/// close affordance over a 1px divider.
class _ReauthHeader extends StatelessWidget {
  const _ReauthHeader({
    required this.title,
    required this.body,
    required this.onClose,
  });

  final String title;
  final String body;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
              vertical: Space.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Container(
                  width: _headerTileSize,
                  height: _headerTileSize,
                  decoration: BoxDecoration(
                    color: colors.accentBg,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  alignment: Alignment.center,
                  child: MadarIcon(
                    'lock.circle',
                    tint: colors.accent,
                    size: IconSize.lg,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.xs / 2,
                    children: [
                      Text(
                        title,
                        style: MadarType.h2.copyWith(
                          fontSize: _headerTitleSize,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.bodySm.copyWith(
                          fontSize: _headerBodySize,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _CloseButton(onTap: onClose),
              ],
            ),
          ),
          SizedBox(height: 1, child: ColoredBox(color: colors.border)),
        ],
      ),
    );
  }
}

/// The header's close glyph — a bordered surface-alt squircle (matches the
/// order screen's bar-button idiom), with press feedback.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: onTap,
      child: Container(
        width: _closeSize,
        height: _closeSize,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: colors.border),
        ),
        alignment: Alignment.center,
        child: MadarIcon('xmark', tint: colors.textMuted, size: _closeGlyph),
      ),
    );
  }
}

/// The quiet muted escape-hatch link beneath the CTA, with press feedback.
class _SwitchTellerLink extends StatelessWidget {
  const _SwitchTellerLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: Space.xs),
        child: Text(
          label,
          style: MadarType.body.copyWith(
            fontSize: _switchLinkSize,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
          ),
        ),
      ),
    );
  }
}
