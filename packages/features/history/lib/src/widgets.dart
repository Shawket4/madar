/// The small pieces both halves of the Orders screen share: what a row's
/// state is called, what an origin is called, and the state tag itself.
/// Tokens-only; every word arrives through [historyTr].
library;

import 'package:design_system/design_system.dart';
import 'package:feature_history/src/history_strings.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// "dine-in" / "Online" / "Takeaway" for a summary's `orderType`. The wire
/// carries no takeaway value today; the label is ready for the day it does,
/// and anything unmapped shows as the server sent it rather than as a key.
String orderTypeLabel(MadarBridge bridge, String orderType) =>
    switch (orderType) {
      'dine_in' => historyTr(bridge, 'history.type.dine_in'),
      'delivery' => historyTr(bridge, 'history.type.online'),
      'takeaway' => historyTr(bridge, 'history.type.takeaway'),
      _ => orderType,
    };

/// The number a sale is read by, as the core words it: `36B-12` for a
/// device-numbered sale (`36B-12~AB12` when two devices shared a code), else
/// the server's number; null while it has none.
String? saleNumberText(OrderSummaryView o) => o.displayNumber.isNotEmpty
    ? o.displayNumber
    : o.orderNumber?.toString();

/// "#36B-12", or the word for a sale that has no number yet.
String saleNumber(MadarBridge bridge, OrderSummaryView o) =>
    switch (saleNumberText(o)) {
      final n? => '#$n',
      null => historyTr(bridge, 'history.order'),
    };

/// "Sale #36B-12" for a title — or just "Sale" while the sale has no number
/// yet; the QUEUED tag under the title says the rest.
String saleTitle(MadarBridge bridge, OrderSummaryView o) {
  final sale = historyTr(bridge, 'history.sale');
  final n = saleNumberText(o);
  return n == null ? sale : '$sale ${ltrIsland('#$n')}';
}

/// Wraps a figure so it reads left-to-right inside Arabic text: the bidi
/// algorithm otherwise floats a "#" or a "%" to the far side of its number.
/// (LRI … PDI — the isolate pair, invisible.)
String ltrIsland(String figure) => '\u2066$figure\u2069';

/// The one state a row may be in beyond "settled", or null. Voided beats
/// failed beats queued, which is the order the core resolves them in.
enum SaleState {
  voided,
  failed,
  queued;

  static SaleState? of(OrderSummaryView o) {
    if (o.status == 'voided') return SaleState.voided;
    if (o.status == 'failed') return SaleState.failed;
    if (o.queued) return SaleState.queued;
    return null;
  }

  String label(MadarBridge bridge) => switch (this) {
    SaleState.voided => historyTr(bridge, 'history.voided'),
    SaleState.failed => historyTr(bridge, 'history.failed'),
    SaleState.queued => historyTr(bridge, 'history.queued'),
  };

  /// The sentence under the tag on the sale itself.
  String hint(MadarBridge bridge) => switch (this) {
    SaleState.voided => historyTr(bridge, 'history.voided_hint'),
    SaleState.failed => historyTr(bridge, 'history.failed_hint'),
    SaleState.queued => historyTr(bridge, 'history.queued_hint'),
  };

  MadarTone get tone => switch (this) {
    SaleState.voided => MadarTone.danger,
    SaleState.failed => MadarTone.danger,
    SaleState.queued => MadarTone.warning,
  };

  MadarGlyph get glyph => switch (this) {
    SaleState.voided => MadarGlyph.xCircle,
    SaleState.failed => MadarGlyph.alertCircle,
    SaleState.queued => MadarGlyph.half,
  };
}
