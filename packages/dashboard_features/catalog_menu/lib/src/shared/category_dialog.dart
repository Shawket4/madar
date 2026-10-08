/// The category dialog (the web's `features/menu/category-dialog.tsx`,
/// MENU-ITEMS-068..071), opened from the Categories tab, the item dialog's
/// "+" and the studio's "+": create or edit a menu category.
///
/// Owner after scaffolding: the `items` unit (its rows); the studio only
/// calls [showCategoryDialog].
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Category, CreateCategoryRequest, UpdateCategoryRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'menu_queries.dart';
import 'menu_text.dart';

/// Opens the dialog: create when [category] is null, else edit. Resolves with
/// the saved category (the created one is what the item dialog and the studio
/// select), or null when cancelled.
Future<Category?> showCategoryDialog(
  BuildContext context, {
  required String orgId,
  Category? category,
}) => showDashDialog<Category>(
  context,
  builder: (_) => CategoryDialog(orgId: orgId, category: category),
);

class CategoryDialog extends ConsumerStatefulWidget {
  const CategoryDialog({required this.orgId, this.category, super.key});

  final String orgId;

  /// Null = a new category.
  final Category? category;

  @override
  ConsumerState<CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<CategoryDialog> {
  late String _name = widget.category?.name ?? '';
  late String _nameAr = arOf(widget.category?.nameTranslations);
  late bool _active = widget.category?.isActive ?? true;
  String? _nameError;
  bool _busy = false;

  Future<void> _save() async {
    final t = ref.read(tProvider);
    // zod `min(1)`: the raw text, not trimmed.
    if (_name.isEmpty) {
      setState(() => _nameError = t('common.requiredField'));
      return;
    }
    setState(() {
      _nameError = null;
      _busy = true;
    });
    final api = ref.read(apiProvider);
    final translations = _nameAr.isEmpty
        ? null
        : <String, Object?>{'ar': _nameAr};
    try {
      final c = widget.category;
      final Category saved;
      if (c == null) {
        // A new category is always created active (the switch is not sent).
        saved = await api.menu.createCategory(
          body: CreateCategoryRequest(
            orgId: widget.orgId,
            name: _name,
            nameTranslations: translations,
          ),
        );
      } else {
        saved = await api.menu.updateCategory(
          id: c.id,
          body: UpdateCategoryRequest(
            name: _name,
            nameTranslations: translations,
            isActive: _active,
          ),
        );
      }
      if (!mounted) return;
      DashToast.success(context, t('common.savedChanges'));
      ref.menuInvalidate.catalog();
      Navigator.of(context).pop(saved);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return DashSurface(
      title: widget.category == null
          ? t('menu.newCategory')
          : t('menu.editCategory'),
      description: t('menu.categoryDesc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DashBilingualField(
            label: t('common.name'),
            en: _name,
            ar: _nameAr,
            enError: _nameError,
            onEnChanged: (v) => setState(() => _name = v),
            onArChanged: (v) => setState(() => _nameAr = v),
          ),
          DashSwitchField(
            label: t('common.active'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(label: t('common.save'), loading: _busy, onPressed: _save),
      ],
    );
  }
}
