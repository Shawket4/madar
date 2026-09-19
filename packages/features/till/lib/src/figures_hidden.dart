/// The one "figures hidden" panel — the whole Till section's answer when the
/// signed-in person does not hold `till.cash_spot_check`.
///
/// `till.cash_spot_check` is "may see this till's money figures" (owner,
/// 2026-09-19), not only "may open the live report": without it the Till tab
/// shows no shift or drawer aggregate at all. Every surface that would have
/// shown one shows THIS panel instead — there is only ever one of them.
///
/// Past orders keep their list, each sale's own total, its items, payments,
/// receipt and reprint (owner decision 3), so this panel never appears there.
/// That screen's ONE shift aggregate — the header's sales total and order
/// count — is a till money figure and is gated like the rest, but a one-line
/// header has no room for a card, so it drops the figures and says
/// `spot.blind_count_note` instead.
library;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "The drawer figures stay hidden until the till is closed." — with its
/// heading above it when the panel stands in for a named card.
class FiguresHiddenPanel extends ConsumerWidget {
  /// Creates the panel. [titleKey] is the heading the hidden card carried
  /// (null for a sheet, which has its own title).
  const FiguresHiddenPanel({super.key, this.titleKey, this.action});

  /// The i18n key of the heading, e.g. `till.cash_in_till`.
  final String? titleKey;

  /// An action under the words — Cash spot, where the screen offers it.
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    return MadarCard.column(
      children: [
        if (titleKey case final key?)
          Text(bridge.tr(key: key), style: MadarType.title),
        Text(
          bridge.tr(key: 'spot.blind'),
          style: MadarType.bodySm.copyWith(
            color: context.madarColors.textSecondary,
          ),
        ),
        ?action,
      ],
    );
  }
}
