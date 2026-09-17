import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The first step of a till close (queue rule 8): when held orders or a
/// counter cart are still on this device, say which (names, who started
/// them, totals, all from the core) before anything is counted. Returns true
/// to go on closing (nothing held, or "Close anyway"), false to go back.
///
/// Self-contained on purpose: the close sequence calls it once, at the top.
Future<bool> confirmHeldOrdersBeforeClose(
  BuildContext context,
  WidgetRef ref,
) async {
  final bridge = ref.read(bridgeProvider);
  final ClosePreflightView preflight;
  try {
    preflight = bridge.closePreflight();
  } on Object catch (_) {
    return true;
  }
  if (preflight.heldCount == 0) return true;
  final go = await showMadarSheet<bool>(
    context,
    size: SheetSize.hug,
    maxWidth: Responsive.sheetCompactMaxWidth,
    builder: (sheetContext) => HeldOrdersCloseWarning(
      preflight: preflight,
      onBack: () => Navigator.of(sheetContext).maybePop(false),
      onContinue: () => Navigator.of(sheetContext).maybePop(true),
    ),
  );
  return go ?? false;
}

/// The warning itself: title, what happens to them, one row per order.
class HeldOrdersCloseWarning extends ConsumerWidget {
  const HeldOrdersCloseWarning({
    required this.preflight,
    required this.onBack,
    required this.onContinue,
    super.key,
  });

  final ClosePreflightView preflight;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final colors = context.madarColors;
    final currency = bridge.currentSession()?.currencyCode ?? '';
    String money(int minor) =>
        bridge.formatMoney(minor: minor, currency: currency, signed: false);
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(
            preflight.title,
            style: MadarType.h3.copyWith(color: colors.textPrimary),
          ),
          Text(
            preflight.body,
            style: MadarType.body.copyWith(color: colors.textSecondary),
          ),
          for (final h in preflight.held)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.body.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      if (h.startedByName case final name?)
                        Text(
                          bridge
                              .tr(key: 'drafts.started_by')
                              .replaceAll('{name}', name),
                          style: MadarType.bodySm.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  money(h.totalMinor),
                  style: MadarType.body.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          const MadarHairline(),
          Row(
            children: [
              Expanded(
                child: Text(
                  bridge.tr(key: 'till.z_held_left_open'),
                  style: MadarType.bodySm.copyWith(color: colors.textMuted),
                ),
              ),
              Text(
                money(preflight.heldTotalMinor),
                style: MadarType.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          MadarButton(
            label: bridge.tr(key: 'till.held_open_back'),
            onTap: onBack,
          ),
          MadarButton(
            label: bridge.tr(key: 'till.held_open_continue'),
            variant: MadarButtonVariant.secondary,
            onTap: onContinue,
          ),
        ],
      ),
    );
  }
}
