/// Small shared pieces the Queue's two segments reuse — the status → tone
/// maps, the LTR figure, the clock label, the one-line card notice, and the
/// board's own metrics that fall between the kit's tokens.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// A card's inner list block (the priced lines on a NEW order) — the paper
/// wash with 36px rows, per the canvas.
const double kLineRowHeight = 36;

/// Two columns of cards on a tablet once the body is this wide — the
/// container test, not the device one: a tablet with a sheet open or a
/// split view can still be one column.
const double kTwoColumnMinWidth = Responsive.wide;

/// A Queue segment lays its list beside a detail pane once its content is
/// this wide (a landscape iPad's page area is 1106).
const double kQueueSplitMinWidth = 900;

/// The Queue's detail pane: 440 where there is room, narrowing with the
/// content (40% of it, never under 360) so the list keeps its columns. SPEC
/// §3 names 560 for Orders; the Queue's list carries an action column, so its
/// pane is narrower on purpose (see the deviation note there).
double queuePaneWidth(double contentWidth) =>
    (contentWidth * 0.4).clamp(360.0, 440.0);

/// Online status → tone. New is teal (it wants a hand), cooking is amber,
/// done is green, the terminal states are red; `confirmed` and `out` are
/// neutral ink — steps, not alarms.
MadarTone deliveryTone(String status) => switch (status) {
  'received' => MadarTone.accent,
  'preparing' => MadarTone.warning,
  'ready' || 'delivered' => MadarTone.success,
  'cancelled' || 'rejected' => MadarTone.danger,
  _ => MadarTone.neutral,
};

/// Bill status → tone for the row's state bar. Ready lights green; a
/// queued (offline-fired) bill is amber because the server has not seen it.
MadarTone ticketTone(String status) => switch (status) {
  'ready' => MadarTone.success,
  'queued' => MadarTone.warning,
  _ => MadarTone.accent,
};

/// One forward lifecycle step the STATUS endpoint accepts. `delivered` is
/// NOT a settable target — it is reached only by charging (finalizing) the
/// order into a real sale — so `out_for_delivery` returns null and the card
/// offers Charge instead of another step.
String? nextDeliveryStatus(String status) => switch (status) {
  'received' => 'confirmed',
  'confirmed' => 'preparing',
  'preparing' => 'ready',
  'ready' => 'out_for_delivery',
  _ => null,
};

/// The status an online order's step button asks the server for — the
/// TARGET, named from the status the teller is looking at, never "the next
/// one" worked out when the call lands. A double tap, a retry or a slow
/// answer asks for the same place again and the order lands there once (the
/// server answers a step to where the order already is with the order).
///
/// Null when the order's next act is Charge instead: the last delivery step,
/// and a PICKUP order once it is accepted. The customer collects a pickup at
/// the counter, with no courier to send it out with, so it walks no steps:
/// Charge finalises it from wherever it is (the server finalises any order
/// still on the line). Accept stays: it is the shop's yes, with its ready-in
/// time, not a step.
String? onlineStepTarget(DeliveryOrderView o) =>
    o.channel == 'pickup' && o.status != 'received'
    ? null
    : nextDeliveryStatus(o.status);

/// The order's next act is Charge (finalise), not a step.
bool onlineChargesNext(DeliveryOrderView o) =>
    !o.isTerminal && onlineStepTarget(o) == null;

/// A figure — an order ref, a phone number, a time — set LTR in Plex Mono
/// whichever script surrounds it. Figures never mirror.
class FigureText extends StatelessWidget {
  const FigureText(
    this.text, {
    this.style,
    this.color,
    this.maxLines = 1,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? MadarType.num;
    return MadarClippedText(
      text,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: color == null ? base : base.copyWith(color: color),
    );
  }
}

/// The clock time an order arrived or a bill opened, in the BRANCH's zone
/// through the core's one formatter. A relative age ("42m") would need a
/// unit word the core has no key for yet; the clock needs none.
String clockLabel(MadarBridge bridge, String rfc3339) {
  try {
    return bridge.formatTime(rfc3339: rfc3339, style: TimeStyle.time);
  } on Object {
    return '';
  }
}

/// A one-line notice pinned inside a card — the server's sentence when the
/// order changed under the teller — with a dismiss. Warning wash; never a
/// dialog.
class CardNotice extends StatelessWidget {
  const CardNotice({required this.text, required this.onDismiss, super.key});

  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      padding: const EdgeInsetsDirectional.only(
        start: Space.md,
        top: Space.sm,
        bottom: Space.sm,
        end: Space.xs,
      ),
      decoration: BoxDecoration(
        color: colors.warningBg,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        spacing: Space.sm,
        children: [
          MadarGlyphIcon(
            MadarGlyph.alertCircle,
            size: IconSize.sm,
            color: colors.warning,
          ),
          Expanded(
            child: MadarClippedText(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MadarType.bodySm.copyWith(color: colors.textPrimary),
            ),
          ),
          MadarGlyphTile(
            glyph: MadarGlyph.close,
            background: Colors.transparent,
            tint: colors.textSecondary,
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// A segment's empty line: one sentence, no illustration. The segment
/// keeps its zero count in the label above; this only says so in words.
class QuietEmpty extends StatelessWidget {
  const QuietEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: Space.xxl * 2),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: MadarType.body.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}
