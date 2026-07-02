/// Open-shift — the continuation of login: login confirms WHO you are, this
/// confirms WHAT'S in the drawer. A name-first greeting, one isolated hero
/// count field (auto-focused), one loud primary. Wide screens split into the
/// same BrandPanel as login; narrow shows one calm centered column. A
/// pixel-and-behavior port of the Kotlin OpenShiftScreen.kt.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/brand_panel.dart';
import 'package:feature_shift/src/controls.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:rust_bridge/rust_bridge.dart';

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

/// Connectivity heartbeat period (natives: 15s).
const Duration _heartbeatPeriod = Duration(seconds: 15);

/// Opening-cash entry. Takes the shared screen contract: [core] for every
/// bridge call and [onStateChanged] after any call that can move
/// `app_route()`/session (open shift, sign out, shift adoption).
class OpenShiftScreen extends StatefulWidget {
  const OpenShiftScreen({
    required this.core,
    required this.onStateChanged,
    super.key,
  });

  final MadarCore core;
  final void Function() onStateChanged;

  @override
  State<OpenShiftScreen> createState() => _OpenShiftScreenState();
}

class _OpenShiftScreenState extends State<OpenShiftScreen> {
  MadarBridge get _bridge => widget.core.bridge;

  int _openingMinor = 0;
  int _suggestedMinor = 0;
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _online = true;
  bool _authPaused = false;
  Timer? _heartbeat;

  String _t(String key) => _bridge.tr(key: key);

  /// The count deviates from the carried-over closing → a reason is required.
  bool get _needsReason =>
      _suggestedMinor > 0 && _openingMinor != _suggestedMinor;

  @override
  void initState() {
    super.initState();
    // Prime the prefill on entry. reconcileShift FIRST — it adopts an
    // already-open shift (opened earlier or on another device) so a teller who
    // lands here never opens a SECOND shift on top of a live one.
    unawaited(_prime());
    // Connectivity heartbeat: a teller who landed here offline re-adopts their
    // active shift the moment the network returns.
    unawaited(_refreshConnectivity());
    _heartbeat = Timer.periodic(
      _heartbeatPeriod,
      (_) => unawaited(_refreshConnectivity()),
    );
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _prime() async {
    await _reconcileShift();
    if (!mounted) return;
    await _loadPrefill();
  }

  /// Reconcile the device's shift with the server when online (existing shift
  /// on login, dashboard force-close); use the local cache offline. Never let
  /// a transient refresh error nuke a good local shift — fall back to the
  /// cache. Adopting an open shift moves `app_route()` → hand off to the shell.
  Future<void> _reconcileShift() async {
    ShiftView? shift;
    if (_bridge.currentSession()?.online ?? false) {
      try {
        shift = await _bridge.refreshShift();
      } on Exception catch (_) {
        shift = await _currentShiftOrNull();
      }
    } else {
      shift = await _currentShiftOrNull();
    }
    if (!mounted) return;
    if (shift?.isOpen ?? false) widget.onStateChanged();
  }

  Future<ShiftView?> _currentShiftOrNull() async {
    try {
      return await _bridge.currentShift();
    } on Exception catch (_) {
      return null;
    }
  }

  /// Prime the open-shift screen: show the locally-cached carried-over
  /// suggestion instantly, then refresh it from the server (last synced
  /// declared closing) when online. Seed the count once while still untouched.
  Future<void> _loadPrefill() async {
    var suggested = await _readSuggested();
    if (!mounted) return;
    _applySuggested(suggested);
    if (_bridge.currentSession()?.online ?? false) {
      try {
        await _bridge.refreshShift();
      } on Exception catch (_) {}
      suggested = await _readSuggested();
      if (!mounted) return;
      _applySuggested(suggested);
    }
  }

  Future<int> _readSuggested() async {
    try {
      return await _bridge.suggestedOpeningCashMinor();
    } on Exception catch (_) {
      return 0;
    }
  }

  void _applySuggested(int suggested) {
    setState(() {
      _suggestedMinor = suggested;
      if (_openingMinor == 0 && suggested > 0) _openingMinor = suggested;
    });
  }

  /// Connectivity heartbeat — ping (updates online + drains), then re-read the
  /// sync chrome. On an offline→online transition, re-adopt the server's
  /// authoritative shift (the core drained the backlog during the ping).
  Future<void> _refreshConnectivity() async {
    if (_bridge.currentSession() == null) return;
    final wasOnline = _online;
    try {
      await _bridge.refreshConnectivity();
    } on Exception catch (_) {}
    SyncStatusView? status;
    try {
      status = await _bridge.syncStatus();
    } on Exception catch (_) {}
    if (!mounted) return;
    if (status != null) {
      setState(() {
        _online = status!.online;
        _authPaused = status.authPaused;
      });
    }
    if (!wasOnline && _online) await _reconcileShift();
  }

  Future<void> _submit() async {
    if (_needsReason && _reason.text.trim().isEmpty) {
      // Guidance next to the action that triggers it — the natives' flagError.
      setState(() => _error = _t('shift.opening_reason_required'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _bridge.openShift(
        openingCashMinor: _openingMinor,
        openingReason: _needsReason ? _reason.text : null,
      );
      if (mounted) setState(() => _busy = false);
      widget.onStateChanged();
    } on MadarError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _bridge.humanMessage(e);
      });
    } on Exception catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _t('err.generic');
      });
    }
  }

  /// The recessive exit — the natives' signOut: realtime + LAN teardown, then
  /// the best-effort core logout. The shell re-reads `app_route()` after.
  Future<void> _signOut() async {
    _bridge.unsubscribeRealtime();
    try {
      await _bridge.lanStop();
    } on Exception catch (_) {}
    try {
      await _bridge.logout(wipeOutbox: false);
    } on Exception catch (_) {}
    widget.onStateChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
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
              bridge: _bridge,
              openingMinor: _openingMinor,
              suggestedMinor: _suggestedMinor,
              needsReason: _needsReason,
              reason: _reason,
              busy: _busy,
              error: _error,
              onAmountMinor: (v) => setState(() => _openingMinor = v),
              onSubmit: () => unawaited(_submit()),
              onSignOut: () => unawaited(_signOut()),
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
                          tr: _t,
                          arabic: _bridge.locale().startsWith('ar'),
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
                      if (!_online)
                        NoticeBanner(
                          text: _t('chrome.offline_banner'),
                          icon: 'wifi.slash',
                        ),
                      if (_authPaused)
                        NoticeBanner(
                          text: _t('chrome.auth_paused'),
                          tone: ChipTone.danger,
                          icon: 'lock',
                          trailing: BannerActionPill(
                            label: _t('chrome.auth_paused_action'),
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

class _FormColumn extends StatelessWidget {
  const _FormColumn({
    required this.width,
    required this.showLogo,
    required this.bridge,
    required this.openingMinor,
    required this.suggestedMinor,
    required this.needsReason,
    required this.reason,
    required this.busy,
    required this.error,
    required this.onAmountMinor,
    required this.onSubmit,
    required this.onSignOut,
  });

  final double width;
  final bool showLogo;
  final MadarBridge bridge;
  final int openingMinor;
  final int suggestedMinor;
  final bool needsReason;
  final TextEditingController reason;
  final bool busy;
  final String? error;
  final ValueChanged<int> onAmountMinor;
  final VoidCallback onSubmit;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    String t(String key) => bridge.tr(key: key);
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
                  onAmountMinor: onAmountMinor,
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
                text: error!,
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
              onTap: onSubmit,
            ),
            const SizedBox(height: Space.sm),
            // ── Recessive exit ────────────────────────────────────────────
            ShiftButton(
              label: t('shift.switch_teller'),
              variant: ShiftButtonVariant.ghost,
              onTap: onSignOut,
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
