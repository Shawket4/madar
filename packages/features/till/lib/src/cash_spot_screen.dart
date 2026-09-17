/// Cash spot — the full live till report (the old X report), on screen with
/// Print (owner design 2026-09-16 item 5, corrected 2026-09-17). Nothing is
/// counted here; counting happens only at close.
///
/// With `till.cash_spot_check` it opens straight away. Without it the button
/// is still there: someone holding the grant types their PIN
/// ([askCashSpotPin]) and that unlocks this one look; the signed-in person
/// does not change. The core records every look and its print.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/feature_history.dart' show askCashSpotPin;
import 'package:feature_till/src/till_report_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Take the one-time PIN when the person may not look on their own.
/// Returns false when dismissed, with the approval when one was taken.
Future<(bool, ApprovalView?)> _unlock(
  BuildContext context,
  WidgetRef ref,
) async {
  final bridge = ref.read(bridgeProvider);
  if (bridge.cashSpotAccess().outcome == 'allow') return (true, null);
  final approval = await askCashSpotPin(
    context,
    reason: bridge.tr(key: 'spot.needs_pin'),
  );
  return (approval != null, approval);
}

/// Open Cash spot: unlock when needed, read the live report (the core records
/// the look), and show it with Print (the core records the print).
Future<void> openCashSpot(BuildContext context, WidgetRef ref) async {
  final bridge = ref.read(bridgeProvider);
  final (ok, approval) = await _unlock(context, ref);
  if (!ok || !context.mounted) return;
  final CashSpotView view;
  try {
    view = await bridge.cashSpotView(approval: approval);
  } on MadarError catch (_) {
    // Refused or not on this device yet: nothing opens, nothing is recorded.
    return;
  }
  if (!context.mounted) return;
  await showMadarSheet<void>(
    context,
    size: SheetSize.large,
    builder: (_) => TillReportSheet(
      report: view.report,
      titleKey: 'spot.title',
      onPrinted: () => unawaited(
        bridge.recordCashSpotPrint(viewId: view.viewId).then((_) {}),
      ),
    ),
  );
  ref.read(drawerTickProvider.notifier).bump();
}

/// The one-time PIN for the close screen's expected figures, when needed.
/// Returns the figures, or null when dismissed or refused.
Future<CloseTillPreviewView?> unlockCloseFigures(
  BuildContext context,
  WidgetRef ref,
) async {
  final bridge = ref.read(bridgeProvider);
  final (ok, approval) = await _unlock(context, ref);
  if (!ok) return null;
  try {
    return await bridge.closeFigures(approval: approval);
  } on MadarError catch (_) {
    return null;
  }
}
