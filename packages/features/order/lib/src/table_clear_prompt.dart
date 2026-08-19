// The post-checkout bussing question.
//
// A sale used to hand its table straight back to the room, which quietly
// asserted something the app cannot know: that the table is READY. It rarely
// is — the party's plates are still on it. So a checkout now leaves the table
// `dirty`, and this asks the one person who can actually see it.
//
// Design rules this surface follows:
//  - Ask ONCE, immediately, while the teller is still standing at the table.
//  - Both answers are real answers. "Not yet" is not a cancel — it leaves the
//    table visibly needing a bus, with a one-tap clear on the tables screen.
//  - Dismissing (backdrop / back) means "not yet", never "cleared". The safe
//    default is the one that does not lie about the room.
//  - The table is NAMED, so the question is answerable without looking up.

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Watch for a table left needing a bus by a checkout and ask about it.
///
/// Call from `build` on any surface a sale can complete from. The pending slot
/// is consumed by whoever asks first, so mounting this on several surfaces can
/// never double-prompt.
void listenForTableClear(BuildContext context, WidgetRef ref) {
  ref.listen<PendingTableClear?>(
    orderProvider.select((s) => s.pendingTableClear),
    (previous, next) {
      if (next == null) return;
      unawaited(showTableClearPrompt(context, ref, next));
    },
  );
}

/// The question itself. Resolves the pending slot either way — an unanswered
/// prompt would sit forever and re-fire on the next rebuild.
Future<void> showTableClearPrompt(
  BuildContext context,
  WidgetRef ref,
  PendingTableClear pending,
) async {
  final bridge = ref.read(bridgeProvider);
  final notifier = ref.read(orderProvider.notifier);
  final label = pending.label?.trim();

  final cleared = await showMadarSheet<bool>(
    context,
    size: SheetSize.hug,
    maxWidth: Responsive.sheetCompactMaxWidth,
    builder: (sheetContext) => _TableClearBody(
      title: label == null || label.isEmpty
          ? bridge.tr(key: 'tables.clear_ask_generic')
          : '${bridge.tr(key: 'tables.clear_ask')} $label',
      message: bridge.tr(key: 'tables.clear_ask_hint'),
      clearLabel: bridge.tr(key: 'tables.clear_now'),
      keepLabel: bridge.tr(key: 'tables.clear_later'),
      onAnswer: (clear) => Navigator.of(sheetContext).maybePop(clear),
    ),
  );

  // Dismissed without choosing → the table STAYS dirty. Never assume a bus.
  if (cleared ?? false) {
    await notifier.clearPendingTable();
  } else {
    notifier.dismissPendingTableClear();
  }
}

class _TableClearBody extends StatelessWidget {
  const _TableClearBody({
    required this.title,
    required this.message,
    required this.clearLabel,
    required this.keepLabel,
    required this.onAnswer,
  });

  final String title;
  final String message;
  final String clearLabel;
  final String keepLabel;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // The state's own glyph and colour — the same pair the canvas
              // uses for a table awaiting a bus, so the question and the
              // thing it is about look like each other.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.dangerBg,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                alignment: Alignment.center,
                child: MadarIcon(
                  'sparkles',
                  tint: colors.danger,
                  size: IconSize.lg,
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  title,
                  style: MadarType.h3.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            message,
            style: MadarType.body.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: Space.xl),
          ActionButton(
            label: clearLabel,
            icon: 'checkmark.circle',
            onTap: () {
              MadarHaptics.selection();
              onAnswer(true);
            },
          ),
          const SizedBox(height: Space.sm),
          ActionButton(
            label: keepLabel,
            icon: 'clock',
            variant: ActionVariant.outline,
            onTap: () {
              MadarHaptics.selection();
              onAnswer(false);
            },
          ),
        ],
      ),
    );
  }
}
