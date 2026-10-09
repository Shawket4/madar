/// The exclude-items control on the Orders page's Items Sold
/// (`components/app/exclude-items-control.tsx`, SELL-ORD-013 … SELL-ORD-015).
/// The delivery block is dashboard_core's `DeliveryChannels`.
library;

import 'package:dashboard_api/dashboard_api.dart' show MenuItem;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'order_lines.dart';
import 'orders_providers.dart';

// ── the exclude control ──────────────────────────────────────────────────

/// A funnel on the Items Sold tile: a searchable list of the org's menu
/// where a tap leaves an item out of the count (and puts it back), kept per
/// org on this device. The menu loads only once the list opens.
class OrdersExcludeItemsControl extends ConsumerWidget {
  const OrdersExcludeItemsControl({required this.orgId, super.key});

  final String? orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final excluded = ref.watch(excludedItemsProvider(orgId));
    final any = excluded.isNotEmpty;
    return DashPopover(
      width: Space.xxl * 8,
      align: DashPopoverAlign.end,
      anchor: (context, ctl) => DashPressable(
        key: const ValueKey('orders-exclude-trigger'),
        onTap: ctl.toggle,
        onIntent: orgId == null
            ? null
            : () => ref.warm(ordersMenuItemsProvider(orgId!)),
        pressScale: false,
        tooltip: t('analytics.excludeItems'),
        semanticLabel: t('analytics.excludeItems'),
        excludeChildSemantics: true,
        builder: (context, s) => SizedBox.square(
          dimension: DashMetrics.target,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DashIcon(
                  'list-filter',
                  size: IconSize.xs,
                  color: any ? c.info : c.textSecondary,
                ),
                if (any)
                  PositionedDirectional(
                    end: -Space.sm,
                    top: -Space.sm,
                    child: Container(
                      key: const ValueKey('orders-exclude-count'),
                      width: Space.md + DashMetrics.hair,
                      height: Space.md + DashMetrics.hair,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.info,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${excluded.length}',
                        style: DashType.smallStrong.copyWith(
                          fontSize: 9,
                          height: 1,
                          color: c.textOnAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      content: (context, ctl) => _ExcludeList(orgId: orgId),
    );
  }
}

class _ExcludeList extends ConsumerStatefulWidget {
  const _ExcludeList({required this.orgId});

  final String? orgId;

  @override
  ConsumerState<_ExcludeList> createState() => _ExcludeListState();
}

class _ExcludeListState extends ConsumerState<_ExcludeList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final org = widget.orgId;
    final excluded = ref.watch(excludedItemsProvider(org));
    final notifier = ref.read(excludedItemsProvider(org).notifier);
    final AsyncValue<List<MenuItem>> menu = org == null
        ? const AsyncData(<MenuItem>[])
        : ref.watch(ordersMenuItemsProvider(org));
    final options = [
      for (final m in menu.value ?? const <MenuItem>[])
        (m.id, translatedName(m.name, m.nameTranslations, lang)),
    ];
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final o in options)
        if (q.isEmpty || o.$2.toLowerCase().contains(q)) o,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.4),
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          child: Text(
            t('analytics.excludeScopeNote'),
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: DashSearchInput(
            key: const ValueKey('orders-exclude-search'),
            value: _query,
            placeholder: t('common.search'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Flexible(
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Text(
                    menu.awaitingFirst ? t('common.loading') : t('common.noResults'),
                    textAlign: TextAlign.center,
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: Space.xs,
                      ),
                      child: Text(
                        t('analytics.excludedFromCount'),
                        style: DashType.smallMedium.copyWith(color: c.textSecondary),
                      ),
                    ),
                    for (final (id, label) in shown)
                      DashPressable(
                        key: ValueKey('orders-exclude-$id'),
                        onTap: () => notifier.toggle(id),
                        pressScale: false,
                        selected: excluded.contains(id),
                        semanticLabel: label,
                        excludeChildSemantics: true,
                        builder: (context, s) => Container(
                          constraints: const BoxConstraints(minHeight: DashMetrics.target),
                          padding: const EdgeInsets.symmetric(horizontal: Space.md),
                          color: s.highlighted ? c.hover : null,
                          child: Row(
                            spacing: Space.sm,
                            children: [
                              Opacity(
                                opacity: excluded.contains(id) ? 1 : 0,
                                child: DashIcon('check', size: IconSize.sm, color: c.textPrimary),
                              ),
                              Expanded(
                                child: MadarClippedText(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DashType.body.copyWith(color: c.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (excluded.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(Space.xs),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.hairline))),
            child: DashButton(
              key: const ValueKey('orders-exclude-clear'),
              label: t('common.clear'),
              variant: DashButtonVariant.ghost,
              size: DashButtonSize.compact,
              expand: true,
              onPressed: () => notifier.set(const []),
            ),
          ),
      ],
    );
  }
}
