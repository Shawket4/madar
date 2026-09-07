import 'dart:async';
import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/loyalty_scan_capture.dart';
import 'package:flutter/material.dart';
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
/// the sale is still claimable is `loyaltyAwardWindowOpen`; and what it is worth
/// is the server's, from the order's own totals. The only judgement left in Dart
/// is the in-flight guard, which is widget sequencing.
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

  @override
  ConsumerState<LoyaltyAwardSheet> createState() => _LoyaltyAwardSheetState();
}

class _LoyaltyAwardSheetState extends ConsumerState<LoyaltyAwardSheet> {
  bool _busy = false;
  String? _error;
  LoyaltyMemberView? _awarded;
  bool _queued = false;

  Future<void> _award({String? token, String? phone}) async {
    final bridge = ref.read(bridgeProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final member = await bridge.loyaltyAward(
        orderId: widget.orderId,
        orderKey: widget.orderKey,
        orderCreatedAt: widget.orderCreatedAt,
        token: token,
        phone: phone,
      );
      if (!mounted) return;
      setState(() {
        // A null member means the till was offline and the press was queued.
        // Saying so is the honest answer; inventing a balance is not.
        _awarded = member;
        _queued = member == null;
      });
      MadarHaptics.success();
    } on MadarError catch (e) {
      if (!mounted) return;
      // Refocusing for another attempt is the capture widget's business — it
      // owns the fields and refocuses when `busy` falls.
      setState(() => _error = bridge.humanMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Done — either credited, or safely queued.
    if (_awarded != null || _queued) {
      final m = _awarded;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              _queued ? 'Points queued' : 'Points added',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _queued
                  ? 'This till is offline. The points go on as soon as it reconnects.'
                  : '${m!.name} — ${m.balance} ${m.balanceLabel} · ${m.progressLabel}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Add points to this sale',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          LoyaltyScanCapture(
            busy: _busy,
            error: _error,
            onCaptured: _award,
          ),
        ],
      ),
    );
  }
}
