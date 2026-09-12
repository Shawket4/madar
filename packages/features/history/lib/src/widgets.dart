/// The small pieces both halves of the Orders screen share: what a row's
/// state is called, what an origin is called, and the state tag itself.
/// Tokens-only; every word arrives through [historyTr].
library;

import 'package:design_system/design_system.dart';
import 'package:feature_history/src/history_strings.dart';
import 'package:flutter/widgets.dart';
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

/// "#1042", or the word for a sale that has no number yet.
String saleNumber(MadarBridge bridge, OrderSummaryView o) =>
    o.orderNumber != null
    ? '#${o.orderNumber}'
    : historyTr(bridge, 'history.order');

/// "Sale #1042" for a title — or just "Sale" while the server has not
/// numbered it yet; the QUEUED tag under the title says the rest.
String saleTitle(MadarBridge bridge, OrderSummaryView o) {
  final sale = historyTr(bridge, 'history.sale');
  final n = o.orderNumber;
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

/// The uppercase state tag for a row or the sale header.
/// "Offline price" — this sale was rung against a catalogue that has since
/// moved.
///
/// NOT a [SaleState]: those are exclusive and describe what happened to the
/// sale, while this describes how it was PRICED and can sit on a perfectly
/// ordinary settled one. It can only happen offline — a live sale is priced by
/// the server and the till has no way to name a price of its own — so it
/// always means the same thing: this till was out of touch when something
/// changed, and somebody may want to look.
class PriceFlagTag extends StatelessWidget {
  const PriceFlagTag({required this.bridge, super.key});

  final MadarBridge bridge;

  @override
  Widget build(BuildContext context) => MadarTag(
    label: historyTr(bridge, 'history.price_flagged'),
    tone: MadarTone.warning,
    glyph: MadarGlyph.percent,
  );
}

class SaleStateTag extends StatelessWidget {
  const SaleStateTag({required this.state, required this.bridge, super.key});

  final SaleState state;
  final MadarBridge bridge;

  @override
  Widget build(BuildContext context) => MadarTag(
    label: state.label(bridge),
    tone: state.tone,
    glyph: state.glyph,
  );
}
