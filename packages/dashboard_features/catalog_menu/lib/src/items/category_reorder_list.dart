/// Category ordering (the web's `category-reorder-list.tsx`, MENU-ITEMS-066
/// and 067): drag a row by its handle, or Move up / Move down. Optimistic:
/// the list reorders at once and `PUT /categories/order` saves the whole
/// order; a failed save rolls back to the server's order with its words.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Category, ReorderCategoriesRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import 'items_widgets.dart';

/// The reorder list's tile (`size-9`).
const double _tile = 36;

class CategoryReorderList extends ConsumerStatefulWidget {
  const CategoryReorderList({
    required this.orgId,
    required this.categories,
    required this.loading,
    super.key,
  });

  final String orgId;
  final List<Category> categories;
  final bool loading;

  @override
  ConsumerState<CategoryReorderList> createState() =>
      _CategoryReorderListState();
}

class _CategoryReorderListState extends ConsumerState<CategoryReorderList> {
  late List<Category> _order = widget.categories;
  bool _saving = false;

  @override
  void didUpdateWidget(CategoryReorderList old) {
    super.didUpdateWidget(old);
    // Follow the server list, but not over our own save in flight.
    if (!_saving && !identical(old.categories, widget.categories)) {
      _order = widget.categories;
    }
  }

  Future<void> _commit(List<Category> next) async {
    final t = ref.read(tProvider);
    final invalidate = ref.menuInvalidate;
    setState(() {
      _order = next;
      _saving = true;
    });
    try {
      await ref
          .read(apiProvider)
          .menu
          .reorderCategories(
            body: ReorderCategoriesRequest(
              orgId: widget.orgId,
              orderedIds: [for (final c in next) c.id],
            ),
          );
      _saving = false;
      invalidate.catalog();
      if (!mounted) return;
      DashToast.success(context, t('common.savedChanges'));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _order = widget.categories;
      });
      DashToast.error(context, errorMessage(e, t));
    }
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _order.length) return;
    final next = [..._order];
    next.insert(to, next.removeAt(from));
    _commit(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    if (widget.loading) return const SizedBox.shrink();
    if (_order.isEmpty) {
      return DashEmptyState(icon: 'tag', title: t('menu.noCategories'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Text(
          t('menu.categoriesReorderHint'),
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, _, _) => Material(
            type: MaterialType.transparency,
            child: Opacity(opacity: 0.7, child: child),
          ),
          onReorderItem: (from, to) {
            if (to != from) _move(from, to);
          },
          children: [
            for (final (i, cat) in _order.indexed)
              Padding(
                key: ValueKey(cat.id),
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: _Row(
                  index: i,
                  count: _order.length,
                  category: cat,
                  name: translatedName(cat.name, cat.nameTranslations, t.lang),
                  onUp: () => _move(i, i - 1),
                  onDown: () => _move(i, i + 1),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.index,
    required this.count,
    required this.category,
    required this.name,
    required this.onUp,
    required this.onDown,
  });

  final int index;
  final int count;
  final Category category;
  final String name;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.translator;
    return Container(
      padding: const EdgeInsets.all(Space.sm + DashMetrics.hair),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        spacing: Space.md,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              container: true,
              button: true,
              label: t('menu.categoriesDragToReorder', args: {'name': name}),
              child: SizedBox.square(
                dimension: DashMetrics.target,
                child: Center(
                  child: DashIcon(
                    'grip-vertical',
                    size: IconSize.sm,
                    color: c.textMuted,
                  ),
                ),
              ),
            ),
          ),
          MenuImageTile(
            url: menuImageUrl(category.image, category.imageUrl),
            icon: 'tag',
            size: _tile,
          ),
          Expanded(
            child: MadarClippedText(
              name,
              maxLines: 1,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
          ),
          DashIconButton(
            icon: 'arrow-up',
            semanticLabel: t('menu.studio.steps.moveUp'),
            onPressed: index == 0 ? null : onUp,
          ),
          DashIconButton(
            icon: 'arrow-down',
            semanticLabel: t('menu.studio.steps.moveDown'),
            onPressed: index == count - 1 ? null : onDown,
          ),
        ],
      ),
    );
  }
}
