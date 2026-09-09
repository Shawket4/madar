import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/loyalty_scan_capture.dart';
import 'package:feature_checkout/src/widgets.dart';
import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Add a finished sale's points to a customer's balance.
///
/// Presented from the receipt right after checkout, and from a past order in the
/// history for as long as that sale's window is open. Self-contained (it holds
/// its own state rather than the checkout session's) precisely so both callers
/// can use it — a sale in the history has no tender session to hang off.
///
/// **This sheet captures bytes; it decides nothing.** Camera frames and USB
/// keystrokes are platform I/O — Rust cannot reach CameraX/AVFoundation without
/// re-implementing them and shipping every frame across the bridge — so capture
/// lives here. What a captured string MEANS is `classifyLoyaltyInput`; whether
/// the sale is still claimable is `loyaltyAwardWindowOpen`; what it is worth is
/// the server's, from the order's own totals; and WHICH OF THE THREE OUTCOMES
/// happened — added, already collected, queued — is `LoyaltyAwardOutcome`,
/// phrased by the core. The only judgement left in Dart is the in-flight guard,
/// which is widget sequencing.
///
/// Three ways in, because one counter is not like another:
///  * **Camera** — where there is one. `mobile_scanner` covers Android, iOS and
///    macOS; the Windows tills this app also ships to have no plugin at all.
///  * **USB scanner** — a keyboard-wedge imager types the barcode. That is what
///    most counters have, and it needs nothing but a focused field.
///  * **Phone number** — for the customer whose battery is dead, which is the
///    commonest reason a card cannot be produced at all.
class LoyaltyAwardSheet extends ConsumerStatefulWidget {
  const LoyaltyAwardSheet({
    required this.orderCreatedAt,
    this.orderId,
    this.orderKey,
    this.customerId,
    super.key,
  });

  /// The sale's own timestamp (RFC3339) — what the window is measured from,
  /// here and on the server.
  final String orderCreatedAt;

  /// The server's order id. Present for a sale from the history.
  final String? orderId;

  /// The client-minted key. Present for a sale this till just rang, which may
  /// not have reached the server yet.
  final String? orderKey;

  /// The member whose card was scanned at the till for this sale.
  ///
  /// When it is known there is nothing to scan: the sheet awards straight away
  /// and closes. Scanning once, before payment, then again to collect for the
  /// same sale, was two screens for one customer at one counter.
  final String? customerId;

  @override
  ConsumerState<LoyaltyAwardSheet> createState() => _LoyaltyAwardSheetState();
}

class _LoyaltyAwardSheetState extends ConsumerState<LoyaltyAwardSheet> {
  bool _busy = false;
  String? _error;

  /// What the server said happened, already phrased by the core. Null until a
  /// press has been answered.
  LoyaltyAwardOutcome? _outcome;

  Future<void> _award({String? token, String? phone}) async {
    final bridge = ref.read(bridgeProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await bridge.loyaltyAward(
        orderId: widget.orderId,
        orderKey: widget.orderKey,
        orderCreatedAt: widget.orderCreatedAt,
        token: token,
        phone: phone,
        customerId: token == null && phone == null ? widget.customerId : null,
      );
      if (!mounted) return;
      setState(() => _outcome = outcome);
      MadarHaptics.success();
    } on MadarError catch (e) {
      if (!mounted) return;
      // The server's own sentence — "the 24-hour window for adding points to
      // this sale has closed", "That sale was voided" — reaches the teller as
      // written. Refocusing for another attempt is the capture widget's
      // business; it owns the fields and refocuses when `busy` falls.
      setState(() => _error = bridge.humanMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // The card was already scanned at the till, so there is nothing to ask.
    // The sheet opens straight into its result rather than presenting a scanner
    // to a teller who has just used one on the same customer.
    if (widget.customerId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_award());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);

    // Awarding to the card scanned at the till: no scanner, just the outcome.
    if (widget.customerId != null && _outcome == null && _error == null) {
      return Padding(
        padding: const EdgeInsetsDirectional.all(Space.xxl),
        child: Center(
          child: SizedBox.square(
            dimension: IconSize.xxl,
            child: CircularProgressIndicator(
              color: colors.accent,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    if (_outcome case final outcome?) {
      // One of three facts about the customer's card, and they are not
      // interchangeable: the points went on, the sale had already been
      // collected for (the call is idempotent per order, so the second press
      // changed nothing), or the press is waiting for a connection.
      final (String glyph, Color tint) = switch (outcome) {
        LoyaltyAwardOutcome(queued: true) => (
          'icloud.and.arrow.up',
          colors.warning,
        ),
        LoyaltyAwardOutcome(alreadyCollected: true) => (
          'checkmark.seal',
          colors.accent,
        ),
        LoyaltyAwardOutcome(pointsAwarded: 0) => (
          'exclamationmark.circle',
          colors.textSecondary,
        ),
        _ => ('checkmark.circle.fill', colors.success),
      };
      return Padding(
        padding: const EdgeInsetsDirectional.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Center(
              child: MadarIcon(glyph, tint: tint, size: IconSize.xxl),
            ),
            Text(
              outcome.headline,
              textAlign: TextAlign.center,
              style: MadarType.h3.copyWith(color: colors.textPrimary),
            ),
            Text(
              outcome.detail,
              textAlign: TextAlign.center,
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
            ActionButton(
              label: t('common.done'),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          Text(
            t('loyalty.add_points_title'),
            textAlign: TextAlign.center,
            style: MadarType.h3.copyWith(color: colors.textPrimary),
          ),
          LoyaltyScanCapture(busy: _busy, error: _error, onCaptured: _award),
        ],
      ),
    );
  }
}
