/// Studio section 3, How it's made (the web's `section-steps.tsx` and
/// `step-preview.tsx`): the ordered steps a barista follows. A step is a
/// library PRESET (named by the library, with its animation) or a line
/// someone TYPED. Each step may carry this drink's own note. Without
/// `recipes.edit` everything shows and nothing edits.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show RecipeStepPreset;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import 'studio_model.dart';
import 'studio_providers.dart';
import 'studio_widgets.dart';

class StudioStepsSection extends ConsumerWidget {
  const StudioStepsSection({
    required this.steps,
    required this.onChanged,
    this.readOnly = false,
    super.key,
  });

  final List<StepDraft> steps;
  final ValueChanged<List<StepDraft>> onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final ar = ref.watch(localeProvider).startsWith('ar');
    final q = ref.watch(stepPresetsProvider);
    final presets = q.value ?? const <RecipeStepPreset>[];
    final bySlug = {for (final p in presets) p.slug: p};
    final settled = q.hasValue || q.hasError;
    final wide = MediaQuery.sizeOf(context).width >= StudioMetrics.sm;

    void set(int i, StepDraft s) =>
        onChanged([for (final (j, x) in steps.indexed) j == i ? s : x]);

    Widget pair(Widget a, Widget b) => wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.sm,
            children: [Expanded(child: a), Expanded(child: b)],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [a, b],
          );

    Widget row(int i, StepDraft step) {
      final preset = step.isPreset ? bySlug[step.presetSlug] : null;
      final missing = step.isPreset && preset == null && settled;
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          if (step.isPreset) ...[
            MadarClippedText(
              preset == null
                  ? step.presetSlug ?? ''
                  : (ar && preset.nameAr.isNotEmpty
                        ? preset.nameAr
                        : preset.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            MadarClippedText(
              missing
                  ? t('menu.studio.steps.retired')
                  : (preset == null
                            ? null
                            : (ar && (preset.noteAr ?? '').isNotEmpty
                                  ? preset.noteAr
                                  : preset.note)) ??
                        t('menu.studio.steps.fromLibrary'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ] else
            pair(
              DashTextInput(
                value: step.title,
                enabled: !readOnly,
                placeholder: t('menu.studio.steps.titlePlaceholder'),
                semanticLabel: t('menu.studio.steps.titleEn'),
                onChanged: (v) => set(i, step.copyWith(title: v)),
              ),
              DashTextInput(
                value: step.titleAr,
                enabled: !readOnly,
                textDirection: TextDirection.rtl,
                placeholder: t('menu.studio.steps.titlePlaceholderAr'),
                semanticLabel: t('menu.studio.steps.titleAr'),
                onChanged: (v) => set(i, step.copyWith(titleAr: v)),
              ),
            ),
          pair(
            DashTextInput(
              value: step.note,
              enabled: !readOnly,
              maxLength: 280,
              placeholder: t('menu.studio.steps.notePlaceholder'),
              semanticLabel: t('menu.studio.steps.noteEn'),
              onChanged: (v) => set(i, step.copyWith(note: v)),
            ),
            DashTextInput(
              value: step.noteAr,
              enabled: !readOnly,
              maxLength: 280,
              textDirection: TextDirection.rtl,
              placeholder: t('menu.studio.steps.notePlaceholderAr'),
              semanticLabel: t('menu.studio.steps.noteAr'),
              onChanged: (v) => set(i, step.copyWith(noteAr: v)),
            ),
          ),
        ],
      );
      final actions = readOnly
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DashIconButton(
                  icon: 'arrow-up',
                  semanticLabel: t('menu.studio.steps.moveUp'),
                  onPressed: i == 0
                      ? null
                      : () => onChanged(moveStep(steps, i, i - 1)),
                ),
                DashIconButton(
                  icon: 'arrow-down',
                  semanticLabel: t('menu.studio.steps.moveDown'),
                  onPressed: i == steps.length - 1
                      ? null
                      : () => onChanged(moveStep(steps, i, i + 1)),
                ),
                DashIconButton(
                  icon: 'trash-2',
                  color: c.danger,
                  semanticLabel: t('common.remove'),
                  onPressed: () => onChanged([
                    for (final (j, x) in steps.indexed)
                      if (j != i) x,
                  ]),
                ),
              ],
            );
      return Container(
        key: ValueKey('studio-step-$i'),
        padding: const EdgeInsets.all(Space.sm + 2),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: DashIcon(
                    'grip-vertical',
                    size: IconSize.sm,
                    color: c.textMuted.withValues(alpha: 0.5),
                  ),
                ),
                SizedBox(
                  width: Space.lg + Space.xs,
                  child: Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      '${i + 1}',
                      textAlign: TextAlign.center,
                      style: DashType.monoStrong.copyWith(
                        color: c.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                StepPreview(
                  url: preset?.animationUrl,
                  size: StudioMetrics.stepFrame,
                  play: false,
                ),
                Expanded(child: content),
                if (wide && actions != null) actions,
              ],
            ),
            if (!wide && actions != null)
              Align(alignment: AlignmentDirectional.centerEnd, child: actions),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        if (steps.isEmpty)
          StudioDashedBox(
            child: Text(
              t('menu.studio.steps.empty'),
              textAlign: TextAlign.center,
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
          ),
        for (final (i, s) in steps.indexed) row(i, s),
        if (!readOnly)
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              DashButton(
                label: t('menu.studio.steps.addFromLibrary'),
                icon: 'plus',
                variant: DashButtonVariant.outline,
                size: DashButtonSize.compact,
                onPressed: () async {
                  final picked = await showStepPicker(context);
                  if (picked != null) onChanged([...steps, picked]);
                },
              ),
              DashButton(
                label: t('menu.studio.steps.addCustom'),
                icon: 'type',
                variant: DashButtonVariant.ghost,
                size: DashButtonSize.compact,
                onPressed: () =>
                    onChanged([...steps, const StepDraft.custom()]),
              ),
            ],
          ),
      ],
    );
  }
}

/// The library picker: resolves with the step to append (a preset, or an
/// empty written step), or null when closed.
Future<StepDraft?> showStepPicker(BuildContext context) =>
    showDashDialog<StepDraft>(
      context,
      width: DashMetrics.dialogWide + Space.xxl * 3,
      builder: (_) => const _StepPicker(),
    );

class _StepPicker extends ConsumerWidget {
  const _StepPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final ar = ref.watch(localeProvider).startsWith('ar');
    final q = ref.watch(stepPresetsProvider);
    final presets = q.value ?? const <RecipeStepPreset>[];
    final cols = MediaQuery.sizeOf(context).width >= StudioMetrics.sm ? 3 : 2;

    Widget grid(List<Widget> tiles) => LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - Space.md * (cols - 1)) / cols;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [for (final tile in tiles) SizedBox(width: w, child: tile)],
        );
      },
    );

    final Widget body;
    if (!q.hasValue && !q.hasError) {
      body = grid([
        for (var i = 0; i < 6; i++)
          const DashSkeleton(height: Space.xxl * 3.5, radius: Radii.control),
      ]);
    } else if (q.hasError && !q.hasValue) {
      body = DashErrorState(
        framed: false,
        message: errorMessage(q.error, t),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(stepPresetsProvider),
      );
    } else if (presets.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xxl),
        child: Text(
          t('menu.studio.steps.noPresets'),
          textAlign: TextAlign.center,
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
      );
    } else {
      body = grid([
        for (final p in presets)
          () {
            final name = ar && p.nameAr.isNotEmpty ? p.nameAr : p.name;
            final note = ar && (p.noteAr ?? '').isNotEmpty ? p.noteAr : p.note;
            return DashPressable(
              key: ValueKey('step-preset-${p.slug}'),
              onTap: () =>
                  Navigator.of(context).pop(StepDraft.preset(p.slug)),
              semanticLabel: name,
              excludeChildSemantics: true,
              pressScale: false,
              builder: (context, s) => Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: s.hovered ? c.hover : null,
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: Border.all(
                    color: s.hovered ? c.textPrimary : c.hairline,
                  ),
                ),
                child: Column(
                  spacing: Space.xs + 2,
                  children: [
                    StepPreview(
                      url: p.animationUrl,
                      size: StudioMetrics.stepTile,
                    ),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: DashType.bodyMedium.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    if (note != null && note.isNotEmpty)
                      MadarClippedText(
                        note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: DashType.small.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }(),
      ]);
    }

    return DashSurface(
      title: t('menu.studio.steps.pickTitle'),
      description: t('menu.studio.steps.pickDesc'),
      body: body,
      actions: [
        DashButton(
          label: t('menu.studio.steps.addCustom'),
          icon: 'pencil',
          variant: DashButtonVariant.ghost,
          onPressed: () =>
              Navigator.of(context).pop(const StepDraft.custom()),
        ),
        DashButton(
          label: t('common.close'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// One step's animation in a square: the library's Lottie file (a still first
/// frame unless [play], and never moving when motion is reduced), a sparkle
/// for a written step, an empty square while the file loads or fails.
class StepPreview extends ConsumerWidget {
  const StepPreview({
    required this.url,
    required this.size,
    this.play = true,
    super.key,
  });

  /// The animation's address from the API; null for a written step.
  final String? url;
  final double size;
  final bool play;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    final u = url;
    Widget inner;
    if (u == null) {
      inner = Center(
        child: DashIcon(
          'sparkles',
          size: IconSize.sm,
          color: c.textMuted.withValues(alpha: 0.6),
        ),
      );
    } else {
      final bytes = ref.watch(stepAnimationProvider(u)).value;
      final animate = play && !MediaQuery.disableAnimationsOf(context);
      inner = bytes == null
          ? const SizedBox.shrink()
          : Lottie.memory(
              bytes,
              width: size,
              height: size,
              animate: animate,
              errorBuilder: (context, e, s) => const SizedBox.shrink(),
            );
    }
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: inner,
      ),
    );
  }
}
