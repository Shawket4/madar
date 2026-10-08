/// The step panel (ADM-ONB-010..023; web `step-panel.tsx`): the step's title
/// and description, its body, and — on every step but the finale — Back and
/// Continue. Most steps create through the real editor of what they set up
/// (the branch, payment method, ingredient, category, add-on, menu item and
/// user dialogs); closing the editor asks the checklist again, so the counts
/// and the mirror follow.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Category, MenuItem, OnboardingStep;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../branches/branch_dialog.dart';
import '../users/user_dialog.dart';
import 'onboarding_config.dart';
import 'onboarding_data.dart';
import 'org_identity_step.dart';

class OnbStepPanel extends ConsumerWidget {
  const OnbStepPanel({
    required this.orgId,
    required this.active,
    required this.byKey,
    required this.canComplete,
    required this.isFirst,
    required this.finishing,
    required this.onPrev,
    required this.onNext,
    required this.onFinish,
    super.key,
  });

  final String orgId;
  final OnbStep active;
  final Map<String, OnboardingStep> byKey;
  final bool canComplete;
  final bool isFirst;
  final bool finishing;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onFinish;

  /// The panel's least height (`min-h-[28rem]`, less its padding).
  static const double minHeight = 448 - Space.xl * 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final finale = active == OnbStep.goLive;
    final desc = t(active.descKey, defaultValue: '');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      // A short step still puts Back / Continue at the panel's foot.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  t(active.titleKey),
                  style: DashType.paneTitle.copyWith(
                    color: c.textPrimary,
                    fontSize: DashType.paneTitle.fontSize! + 2,
                  ),
                ),
              ),
              if (desc.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    desc,
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                ),
              const SizedBox(height: Space.xl),
              KeyedSubtree(
                key: ValueKey('onb-body-${active.key}'),
                child: _StepBody(
                  orgId: orgId,
                  active: active,
                  byKey: byKey,
                  canComplete: canComplete,
                  finishing: finishing,
                  onNext: onNext,
                  onFinish: onFinish,
                ),
              ),
            ],
          ),
          if (!finale)
            Container(
              margin: const EdgeInsets.only(top: Space.xxl),
              padding: const EdgeInsets.only(top: Space.lg + DashMetrics.hair),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  DashButton(
                    label: t('onboarding.back'),
                    icon: _arrowBack(context),
                    variant: DashButtonVariant.ghost,
                    onPressed: isFirst ? null : onPrev,
                  ),
                  DashButton(
                    label: t('onboarding.continue'),
                    trailingIcon: DashIcon.arrowForward(context),
                    variant: DashButtonVariant.outline,
                    onPressed: onNext,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// An arrow toward the start of the line.
String _arrowBack(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? 'arrow-right'
    : 'arrow-left';

class _StepBody extends ConsumerWidget {
  const _StepBody({
    required this.orgId,
    required this.active,
    required this.byKey,
    required this.canComplete,
    required this.finishing,
    required this.onNext,
    required this.onFinish,
  });

  final String orgId;
  final OnbStep active;
  final Map<String, OnboardingStep> byKey;
  final bool canComplete;
  final bool finishing;
  final VoidCallback onNext;
  final VoidCallback onFinish;

  int _count(String key) => byKey[key]?.count ?? 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget add(Future<Object?> Function(BuildContext context) open) =>
        OnbAddViaDialog(
          orgId: orgId,
          step: active,
          count: _count(active.key),
          open: open,
        );
    return switch (active) {
      OnbStep.orgProfile => OnbOrgIdentityStep(orgId: orgId, onNext: onNext),
      OnbStep.branch => add((context) => showBranchDialog(context)),
      OnbStep.paymentMethods => add(
        (context) => _openPage(context, '/settings/payment-methods'),
      ),
      OnbStep.ingredients => add(
        (context) => _openPage(context, '/inventory/ingredients'),
      ),
      OnbStep.categories => add((context) => _openPage(context, '/menu/items')),
      OnbStep.menuItems => _MenuItemsBody(
        orgId: orgId,
        count: _count('menu_items'),
      ),
      OnbStep.addons => add((context) => _openPage(context, '/menu/items')),
      OnbStep.recipes => _RecipesBody(orgId: orgId),
      OnbStep.team => add((context) => showUserDialog(context)),
      OnbStep.goLive => _GoLiveBody(
        canComplete: canComplete,
        finishing: finishing,
        onFinish: onFinish,
      ),
    };
  }
}

/// The success banner ("3 categories created.") or the dashed empty line.
class _CountLine extends StatelessWidget {
  const _CountLine({required this.added, required this.empty});

  final String? added;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final added = this.added;
    if (added != null) {
      final fg = DashTone.success.foreground(c);
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          color: c.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.success.withValues(alpha: 0.3)),
        ),
        child: Row(
          spacing: Space.sm,
          children: [
            DashIcon('check', size: IconSize.sm, color: fg),
            Expanded(
              child: Text(
                added,
                style: DashType.bodyMedium.copyWith(color: fg),
              ),
            ),
          ],
        ),
      );
    }
    return OnbDashedNote(text: empty);
  }
}

/// A quiet dashed box with a centred sentence (the web's empty lines).
class OnbDashedNote extends StatelessWidget {
  const OnbDashedNote({required this.text, this.warning = false, super.key});

  final String text;

  /// The amber "add a category first" variant.
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final edge = warning ? c.warning.withValues(alpha: 0.4) : c.input;
    return CustomPaint(
      foregroundPainter: OnbDashedBorder(color: edge, radius: Radii.md),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: warning ? Space.md : Space.xl,
        ),
        decoration: BoxDecoration(
          color: warning
              ? c.warning.withValues(alpha: 0.1)
              : c.muted.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Text(
          text,
          textAlign: warning ? TextAlign.start : TextAlign.center,
          style: DashType.body.copyWith(
            color: warning ? DashTone.warning.foreground(c) : c.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The generic "create through the real editor" body: the count line, then
/// "Add …" (filled) or "Add another …" (outline). Closing the editor asks the
/// checklist again — a create likely happened.
class OnbAddViaDialog extends ConsumerWidget {
  const OnbAddViaDialog({
    required this.orgId,
    required this.step,
    required this.count,
    required this.open,
    super.key,
  });

  final String orgId;
  final OnbStep step;
  final int count;
  final Future<Object?> Function(BuildContext context) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final k = 'onboarding.steps.${step.key}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg + DashMetrics.hair * 2,
      children: [
        _CountLine(
          added: count > 0
              ? t('$k.added', args: {'count': count}, count: count)
              : null,
          empty: t('$k.empty'),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DashButton(
            label: count > 0 ? t('$k.addAnother') : t('$k.cta'),
            icon: 'plus',
            variant: count > 0
                ? DashButtonVariant.outline
                : DashButtonVariant.primary,
            onPressed: () async {
              await open(context);
              refreshOnboarding(ref, orgId);
            },
          ),
        ),
      ],
    );
  }
}

/// Menu items: the item editor needs a category, so with none the button
/// waits behind an amber "add a category first".
class _MenuItemsBody extends ConsumerWidget {
  const _MenuItemsBody({required this.orgId, required this.count});

  final String orgId;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final categories =
        ref.watch(onbCategoriesProvider(orgId)).value ?? const <Category>[];
    const k = 'onboarding.steps.menu_items';
    final Widget line = categories.isEmpty
        ? OnbDashedNote(text: t('$k.needCategory'), warning: true)
        : _CountLine(
            added: count > 0
                ? t('$k.added', args: {'count': count}, count: count)
                : null,
            empty: t('$k.empty'),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg + DashMetrics.hair * 2,
      children: [
        line,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DashButton(
            label: count > 0 ? t('$k.addAnother') : t('$k.cta'),
            icon: 'plus',
            variant: count > 0
                ? DashButtonVariant.outline
                : DashButtonVariant.primary,
            onPressed: categories.isEmpty
                ? null
                : () async {
                    await _openPage(context, '/menu/items');
                    refreshOnboarding(ref, orgId);
                  },
          ),
        ),
      ],
    );
  }
}

/// Recipes: the first eight items, each opening the item editor (which
/// carries the recipe builder) on that item.
class _RecipesBody extends ConsumerWidget {
  const _RecipesBody({required this.orgId});

  final String orgId;

  static const int _shown = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final lang = ref.watch(localeProvider);
    final items =
        ref.watch(onbMenuItemsProvider(orgId)).value ?? const <MenuItem>[];
    const k = 'onboarding.steps.recipes';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg + DashMetrics.hair * 2,
      children: [
        Text(
          t('$k.intro'),
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
        if (items.isEmpty)
          OnbDashedNote(text: t('$k.noItems'))
        else
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: c.hairline),
            ),
            child: Column(
              children: [
                for (final (i, item) in items.take(_shown).indexed)
                  Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: Space.lg,
                      vertical: DashMetrics.hair,
                    ),
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : Border(top: BorderSide(color: c.hairline)),
                    ),
                    child: Row(
                      spacing: Space.md,
                      children: [
                        Expanded(
                          child: MadarClippedText(
                            translatedName(
                              item.name,
                              item.nameTranslations,
                              lang,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashType.body.copyWith(color: c.textPrimary),
                          ),
                        ),
                        DashButton(
                          label: t('$k.addFor'),
                          variant: DashButtonVariant.outline,
                          size: DashButtonSize.compact,
                          onPressed: () async {
                            await _openPage(context, '/menu/items');
                            refreshOnboarding(ref, orgId);
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The finale: the rocket, "Ready to open your café", and "Open my café"
/// (only once every required step is done; a spinner while it opens).
class _GoLiveBody extends ConsumerWidget {
  const _GoLiveBody({
    required this.canComplete,
    required this.finishing,
    required this.onFinish,
  });

  final bool canComplete;
  final bool finishing;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    const k = 'onboarding.steps.go_live';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xl,
        vertical: Space.xxl + Space.lg,
      ),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.lg + DashMetrics.hair * 2,
        children: [
          Container(
            width: Space.xxl * 2,
            height: Space.xxl * 2,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: canComplete ? c.brand.withValues(alpha: 0.1) : c.muted,
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: DashIcon(
              'rocket',
              size: Space.xxl,
              color: canComplete ? c.brand : c.textSecondary,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs + DashMetrics.hair,
            children: [
              Text(
                t('$k.heading'),
                textAlign: TextAlign.center,
                style: DashType.paneTitle.copyWith(color: c.textPrimary),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: DashMetrics.prose),
                child: Text(
                  canComplete ? t('$k.ready') : t('$k.notReady'),
                  textAlign: TextAlign.center,
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
          DashButton(
            label: t('$k.cta'),
            icon: 'rocket',
            loading: finishing,
            onPressed: !canComplete || finishing ? null : onFinish,
          ),
        ],
      ),
    );
  }
}

/// A dashed rounded frame (the web's `border-dashed`).
class OnbDashedBorder extends CustomPainter {
  OnbDashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.5),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(OnbDashedBorder old) =>
      old.color != color || old.radius != radius;
}

// ponytail: the web opens each editor inline (onboarding dialogs not ported
// yet); this opens the page that owns it and refreshes the checklist on return.
Future<Object?> _openPage(BuildContext context, String path) =>
    context.push<Object?>(path);
