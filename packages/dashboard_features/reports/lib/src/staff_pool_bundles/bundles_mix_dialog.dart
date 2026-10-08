/// A combo's mix (REP-BUN-013…017, `features/reports/bundles/mix-dialog.tsx`):
/// per slot, what customers picked, at which size, how often, and what the
/// upgrades brought in.
library;

import 'package:dashboard_api/dashboard_api.dart' show MixPick, MixSlot;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'bundles_providers.dart';
import 'unit_support.dart';

/// The combo slot label of a single-size pick (`ONE_SIZE`).
const String _oneSize = 'one_size';

/// `sizeLabelText`: `one_size` reads "Standard"; any other label as stored.
String sizeLabelText(Translator t, String label) =>
    label == _oneSize ? t('combos.oneSize') : label;

class BundlesMixDialog extends ConsumerWidget {
  const BundlesMixDialog({required this.name, required this.query, super.key});

  /// `sm:max-w-xl`.
  static const double width = 576;

  /// The combo's name in the active language.
  final String name;
  final ComboMixQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final q = ref.watch(comboMixProvider(query));
    final Widget body;
    if (q.firstLoad) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          for (var i = 0; i < 4; i++) const DashSkeleton(height: Space.xxl),
        ],
      );
    } else if (q.hasError || q.value == null) {
      body = DashErrorState(
        framed: false,
        retryLabel: t('common.retry'),
        onRetry: () => ref.invalidate(comboMixProvider(query)),
      );
    } else if (q.value!.slots.isEmpty) {
      body = Text(
        t('reports.bundles.mixEmpty'),
        style: DashType.body.copyWith(color: context.madarColors.textSecondary),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg + Space.xs,
        children: [for (final s in q.value!.slots) _SlotSection(slot: s)],
      );
    }
    final surface = DashSurface(
      title: t('reports.bundles.mixTitle', args: {'name': name}),
      description: t('reports.bundles.mixHint'),
      body: body,
    );
    // At most 88% of the window's height, scrolling inside (REP-BUN-017).
    if (DashSurfaceScope.maybeOf(context) != DashSurfaceMode.dialog) {
      return surface;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: surface,
    );
  }
}

/// One slot: its name as a heading, then Pick / Times / Share / Extras.
class _SlotSection extends ConsumerWidget {
  const _SlotSection({required this.slot});

  final MixSlot slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final slotName = translatedName(slot.name, slot.nameTranslations, t.lang);
    final total = slot.picks.fold<int>(0, (n, p) => n + p.count);
    // Most-picked first (a stable sort keeps the server's order on a tie).
    final picks = [...slot.picks];
    mergeSortPicks(picks);
    final head = DashType.tableHeader.copyWith(color: c.textSecondary);
    final figure = DashType.mono.copyWith(color: c.textPrimary);

    Widget row(List<Widget> cells, {bool header = false}) => Container(
      padding: const EdgeInsets.symmetric(
        vertical: Space.xs + DashMetrics.hair,
      ),
      decoration: header
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: c.hairline)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.sm,
        children: [
          Expanded(flex: 5, child: cells[0]),
          for (final cell in cells.skip(1))
            Expanded(
              flex: 2,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: cell,
              ),
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: slotName,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          Semantics(
            header: true,
            child: Text(
              slotName,
              style: DashType.bodyStrong.copyWith(color: c.textPrimary),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row(header: true, [
                Text(t('reports.bundles.mixItem').toUpperCase(), style: head),
                Text(t('reports.bundles.mixCount').toUpperCase(), style: head),
                Text(t('reports.bundles.mixShare').toUpperCase(), style: head),
                Text(t('reports.bundles.mixExtra').toUpperCase(), style: head),
              ]),
              for (final p in picks)
                row([
                  _PickName(pick: p),
                  Text(dashFigure(f.fmtNumber(p.count)), style: figure),
                  Text(dashFigure(f.fmtShare(p.count, total)), style: figure),
                  Text(
                    dashFigure(
                      p.surchargeTotal > 0 ? f.fmtMoney(p.surchargeTotal) : '—',
                    ),
                    style: figure,
                  ),
                ]),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Burger · Large": the pick in the active language, its size muted.
class _PickName extends ConsumerWidget {
  const _PickName({required this.pick});

  final MixPick pick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final size = pick.sizeLabel;
    return Text.rich(
      TextSpan(
        text: translatedName(pick.name, pick.nameTranslations, t.lang),
        children: [
          if (size != null)
            TextSpan(
              text: ' · ${sizeLabelText(t, size)}',
              style: TextStyle(color: c.textSecondary),
            ),
        ],
      ),
      style: DashType.body.copyWith(color: c.textPrimary),
    );
  }
}

/// Sorts [picks] by count, most first, keeping the server's order on a tie
/// (`[...s.picks].sort((a, b) => b.count - a.count)` is stable).
void mergeSortPicks(List<MixPick> picks) {
  final indexed = [for (final (i, p) in picks.indexed) (i, p)]
    ..sort((a, b) {
      final d = b.$2.count.compareTo(a.$2.count);
      return d != 0 ? d : a.$1.compareTo(b.$1);
    });
  for (var i = 0; i < picks.length; i++) {
    picks[i] = indexed[i].$2;
  }
}
