import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

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

/// PIN length window: auto-submit at 6, reject below 4 (natives' maxPin /
/// submit guard).
const int _maxPin = 6;
const int _minPin = 4;

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
/// `MadarSheet(size = HUG, maxWidth = 440.dp)`).
///
/// Resolves to a [ReauthOutcome], or null when dismissed via scrim / drag /
/// back (natives: `showReauth = false`, sync stays paused).
Future<ReauthOutcome?> showReauthSheet(
  BuildContext context, {
  required MadarCore core,
  required void Function() onStateChanged,
}) {
  return showMadarSheet<ReauthOutcome>(
    context,
    size: SheetSize.hug,
    maxWidth: _sheetMaxWidth,
    builder: (_) => ReauthSheet(core: core, onStateChanged: onStateChanged),
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
class ReauthSheet extends StatefulWidget {
  /// Creates the re-auth sheet.
  const ReauthSheet({
    required this.core,
    required this.onStateChanged,
    super.key,
  });

  /// The core handle.
  final MadarCore core;

  /// Notifies the shell after the bridge sign-in (session/sync state moved).
  final void Function() onStateChanged;

  @override
  State<ReauthSheet> createState() => _ReauthSheetState();
}

class _ReauthSheetState extends State<ReauthSheet> {
  String _pin = '';
  bool _busy = false;
  String? _error;

  MadarBridge get _bridge => widget.core.bridge;

  String _t(String key) => _bridge.tr(key: key);

  /// Re-authenticate the SAME teller who owns the open shift (no handover) —
  /// mirrors the natives' `reauth(pin)`: `signInTeller(session.displayName,
  /// pin)`, clear the PIN + warning haptic on failure, pop on success.
  Future<void> _submit() async {
    if (_pin.length < _minPin) {
      MadarHaptics.warning();
      return;
    }
    final name = _bridge.currentSession()?.displayName ?? '';
    setState(() {
      _busy = true;
      _error = null;
    });
    String? failure;
    try {
      await _bridge.signIn(
        req: LoginRequest(
          mode: LoginMode.pin,
          name: name,
          pin: _pin,
          branchId: _bridge.deviceConfig().branchId,
        ),
      );
    } on MadarError catch (e) {
      failure = _bridge.humanMessage(e);
    } on Exception catch (_) {
      failure = _t('err.generic');
    }
    widget.onStateChanged();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure;
      if (failure != null) _pin = '';
    });
    if (failure != null) {
      MadarHaptics.warning();
      return;
    }
    await Navigator.of(context).maybePop(ReauthOutcome.resumed);
  }

  void _digit(String digit) {
    if (_busy || _pin.length >= _maxPin) return;
    setState(() {
      _error = null;
      _pin += digit;
    });
    if (_pin.length == _maxPin) unawaited(_submit());
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final tellerName = _bridge.currentSession()?.displayName ?? '';
    final error = _error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReauthHeader(
          title: _t('chrome.reauth_title'),
          body: _t('chrome.reauth_body'),
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
                  label: '${_t('chrome.reauth_as')} $tellerName',
                  tone: ChipTone.accent,
                  icon: 'person.crop.circle.badge.clock',
                ),
                const SizedBox(height: Space.xxl),
                PinPad(
                  pin: _pin,
                  onDigit: _digit,
                  onBackspace: _backspace,
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
                  label: _t('login.sign_in'),
                  onPressed: () => unawaited(_submit()),
                  loading: _busy,
                  height: _ctaHeight,
                  icon: 'arrow.right.circle',
                ),
                const SizedBox(height: Space.sm),
                // Escape hatch — close the shift and route a different
                // teller to login.
                _SwitchTellerLink(
                  label: _t('chrome.reauth_switch'),
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
