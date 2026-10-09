/// The two moments the builder asks something (the web's `dialogs.tsx`):
/// which of the four setups a new branch starts from, and, before a save,
/// whether what the change does is what the person meant.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'plan.dart';
import 'vocabulary.dart';

/// The four setups, the first thing an empty plan shows.
class SetupPicker extends ConsumerWidget {
  const SetupPicker({required this.onPick, super.key});

  final ValueChanged<Setup> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final twoColumns = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    Widget card(Setup s) {
      final (:title, :body) = setupLabel(t, s);
      final common = s == Setup.tillPrinter || s == Setup.tillScreen;
      return DashPressable(
        key: ValueKey('bb-setup-${s.name}'),
        onTap: () => onPick(s),
        semanticLabel: title,
        builder: (context, st) => Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            color: st.hovered ? c.hover : c.card,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: st.hovered ? c.accent.withValues(alpha: 0.6) : c.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accentBg,
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                child: MadarIcon(setupIcon[s], size: 20, tint: c.accent),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.xs,
                  children: [
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: DashType.bodyStrong.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        if (common)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.sm,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: c.muted,
                              borderRadius: BorderRadius.circular(Radii.pill),
                            ),
                            child: Text(
                              t('builder.mostCommon'),
                              style: DashType.smallMedium.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      body,
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cards = [for (final s in Setup.values) card(s)];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: Column(
            spacing: Space.lg,
            children: [
              Column(
                spacing: Space.xs,
                children: [
                  Text(
                    t('builder.pickTitle'),
                    textAlign: TextAlign.center,
                    style: DashType.sectionTitle.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    t('builder.pickBody'),
                    textAlign: TextAlign.center,
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
              if (twoColumns)
                for (var i = 0; i < cards.length; i += 2)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Space.md,
                      children: [
                        Expanded(child: cards[i]),
                        Expanded(child: cards[i + 1]),
                      ],
                    ),
                  )
              else
                ...cards,
            ],
          ),
        ),
      ),
    );
  }
}

/// What the save will do, in plain words, before it does it.
class ReviewDialog extends ConsumerWidget {
  const ReviewDialog({
    required this.before,
    required this.after,
    required this.firstSave,
    required this.routingNow,
    required this.openItems,
    required this.saving,
    required this.onConfirm,
    super.key,
  });

  /// The plan as the branch has it now: saved, or assembled from its
  /// stations.
  final BuilderPlan before;
  final BuilderPlan after;
  final bool firstSave;
  final String routingNow;
  final Map<String, int> openItems;
  final ValueListenable<bool> saving;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final diff = diffPlans(before, after);
    final routingNext = routingModeFor(after);
    final busy = [
      for (final r in diff.removed)
        if (r.kind == PieceKind.section && (openItems[r.id] ?? 0) > 0) r,
    ];
    String names(List<PieceRef> refs, BuilderPlan plan) => [
      for (final r in refs)
        pieceName(plan, r).isEmpty ? t('builder.unnamed') : pieceName(plan, r),
    ].join(', ');
    final rows = [
      if (diff.added.isNotEmpty)
        (t('builder.review.added'), names(diff.added, after), false),
      if (diff.changed.isNotEmpty)
        (t('builder.review.changed'), names(diff.changed, after), false),
      if (diff.removed.isNotEmpty)
        (t('builder.review.removed'), names(diff.removed, before), true),
    ];
    final routingChanges = routingNext != routingNow;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    Widget row(String label, Widget value) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.md,
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: DashType.body.copyWith(color: c.textSecondary)),
        ),
        Expanded(child: value),
      ],
    );

    return ValueListenableBuilder<bool>(
      valueListenable: saving,
      builder: (context, isSaving, _) => DashSurface(
        title: t('builder.review.title'),
        description: firstSave
            ? t('builder.review.firstBody')
            : t('builder.review.body'),
        actions: [
          DashButton(
            key: const ValueKey('bb-review-cancel'),
            label: t('common.cancel'),
            variant: DashButtonVariant.outline,
            onPressed: isSaving ? null : () => Navigator.of(context).pop(),
          ),
          DashButton(
            key: const ValueKey('bb-review-save'),
            label: t('builder.save'),
            loading: isSaving,
            onPressed: isSaving || busy.isNotEmpty ? null : onConfirm,
          ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            for (final (label, value, danger) in rows)
              row(
                label,
                Text(
                  value,
                  style: DashType.body.copyWith(
                    color: danger ? c.danger : c.textPrimary,
                  ),
                ),
              ),
            if (routingChanges)
              row(
                t('builder.review.kitchen'),
                Wrap(
                  spacing: Space.xs + 2,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      routingText(t, routingNow),
                      style: DashType.body.copyWith(
                        color: c.textSecondary,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Transform.flip(
                      flipX: rtl,
                      child: MadarIcon(
                        'arrow-right',
                        size: 14,
                        tint: c.textSecondary,
                      ),
                    ),
                    Text(
                      routingText(t, routingNext),
                      style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
              ),
            if (rows.isEmpty && !routingChanges)
              Text(
                t('builder.review.onlyMoved'),
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
            if (busy.isNotEmpty)
              Semantics(
                liveRegion: true,
                child: Container(
                  key: const ValueKey('bb-review-busy'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.dangerBg,
                    borderRadius: BorderRadius.circular(Radii.xs),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.sm,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: MadarIcon('triangle-alert', size: 16, tint: c.danger),
                      ),
                      Expanded(
                        child: Text(
                          t(
                            'builder.review.busy',
                            args: {'names': names(busy, before)},
                          ),
                          style: DashType.body.copyWith(color: c.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
