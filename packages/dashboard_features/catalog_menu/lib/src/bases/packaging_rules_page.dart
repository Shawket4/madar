/// `/menu/packaging`: packaging rules and "Apply rules" (MENU-PKG-001..008).
/// The rule dialog is `rule_dialog.dart`.
/// Web: `features/menu/recipe/packaging-rules-page.tsx`.
///
/// - Reads: the rules, the menu categories and the first 500 menu items (for
///   the rows' match words and the dialog's pickers), only with an org.
/// - "Apply rules" needs `menu.packaging_rules.apply`; "New rule" and the row
///   actions need `menu.items.edit` (MENU-PKG-006).
/// - Apply shows its counts in an alert under the header until the next
///   apply and refreshes the catalog; rule writes refresh only the rules.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ApplyPackagingRulesResult, PackagingRuleOut;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import 'bases_providers.dart';
import 'bases_widgets.dart';
import 'rule_dialog.dart';

class PackagingRulesPage extends ConsumerStatefulWidget {
  const PackagingRulesPage({super.key});

  @override
  ConsumerState<PackagingRulesPage> createState() => _PackagingRulesPageState();
}

class _PackagingRulesPageState extends ConsumerState<PackagingRulesPage> {
  bool _applying = false;
  ApplyPackagingRulesResult? _result;

  /// MENU-PKG-007.
  Future<void> _apply() async {
    final t = ref.read(tProvider);
    final invalidate = ref.menuInvalidate;
    setState(() => _applying = true);
    try {
      final r = await ref.read(apiProvider).menu.applyRules();
      if (!mounted) return;
      setState(() => _result = r);
      invalidate.catalog();
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// MENU-PKG-008: confirm (not destructive-styled), delete, refresh the
  /// rules; no success toast.
  Future<void> _delete(PackagingRuleOut r) async {
    final t = ref.read(tProvider);
    final invalidate = ref.menuInvalidate;
    final ok = await showDashConfirm(
      context,
      title: t('modeling.packaging.deleteTitle', args: {'name': r.name}),
      description: t('modeling.packaging.deleteDesc'),
      confirmLabel: t('common.delete'),
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).menu.deleteRule(id: r.id);
      invalidate.paths(const [MenuPaths.packagingRules]);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    final canEdit = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuItemsEdit)),
    );
    final canApply = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuPackagingRulesApply)),
    );

    final categoryOptions = ruleCategoryOptions(ref, orgId, t);
    final itemOptions = ruleItemOptions(ref, orgId);
    String? labelOf(List<DashOption<String>> opts, String? id) => id == null
        ? null
        : (opts.where((o) => o.value == id).firstOrNull?.label ?? '—');

    void openDialog(PackagingRuleOut? rule) =>
        showRuleDialog(context, orgId: orgId, rule: rule);

    final empty = DashEmptyState(
      icon: 'package',
      title: t('modeling.packaging.empty'),
      description: t('modeling.packaging.emptyHint'),
    );
    Widget list;
    if (orgId == null) {
      list = empty;
    } else {
      final provider = packagingRulesProvider(orgId);
      final rules = ref.watch(provider);
      if (rules.hasError) {
        list = DashErrorState(
          title: t('modeling.packaging.loadError'),
          message: errorMessage(rules.error, t),
          retrying: rules.isLoading,
          onRetry: () => ref.invalidate(provider),
        );
      } else if (!rules.hasValue) {
        list = const ModelingSkeleton();
      } else if (rules.requireValue.isEmpty) {
        list = empty;
      } else {
        list = ModelingList(
          children: [
            for (final r in rules.requireValue)
              ModelingRow(
                key: ValueKey(r.id),
                name: r.name,
                active: r.isActive,
                inactiveLabel: t('common.inactive'),
                truncateSubtitle: true,
                subtitle: _ruleLine(
                  t,
                  r,
                  [
                    labelOf(itemOptions, r.matchItemId),
                    labelOf(categoryOptions, r.matchCategoryId),
                    r.matchSizeLabel,
                  ],
                ),
                editLabel: t('common.edit'),
                deleteLabel: t('common.delete'),
                onEdit: canEdit ? () => openDialog(r) : null,
                onDelete: canEdit ? () => _delete(r) : null,
              ),
          ],
        );
      }
    }

    final result = _result;
    return DashPageScaffold(
      title: t('modeling.packaging.title'),
      subtitle: t('modeling.packaging.subtitle'),
      width: DashPageWidth.reading,
      actions: [
        if (canApply)
          DashButton(
            label: t('modeling.packaging.apply'),
            icon: 'play',
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            loading: _applying,
            onPressed: _apply,
          ),
        if (canEdit)
          DashButton(
            label: t('modeling.packaging.new'),
            icon: 'plus',
            size: DashButtonSize.compact,
            onPressed: () => openDialog(null),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          if (result != null)
            ModelingAlert(
              title: t('modeling.packaging.appliedTitle'),
              description: t(
                'modeling.packaging.appliedBody',
                args: {
                  'seen': result.sizesSeen,
                  'withRule': result.sizesWithRule,
                  'changed': result.sizesChanged,
                  'manual': result.sizesWithManualPackaging,
                },
              ),
            ),
          list,
        ],
      ),
    );
  }
}

/// A rule's sub-line (MENU-PKG-004): the set matches joined " · " (or
/// "Every size"), " → ", then "ingredient quantity" joined ", " (or "—").
/// The arrow points along the reading direction: "←" in Arabic (divergence
/// MENU-PKG-004).
String _ruleLine(Translator t, PackagingRuleOut r, List<String?> matches) {
  final set = [
    for (final m in matches)
      if (m != null && m.isNotEmpty) m,
  ];
  final lines = [
    for (final l in r.lines)
      '${l.ingredientName} ${jsNumberText(jsNumber(l.quantity))}',
  ].join(', ');
  return '${set.isEmpty ? t('modeling.packaging.matchAll') : set.join(' · ')}'
      '${t.isRtl ? ' ← ' : ' → '}'
      '${lines.isEmpty ? '—' : lines}';
}
