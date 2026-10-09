/// The item editor (ADM-ONB-021/022; the web's `features/menu/menu-item-dialog.tsx`):
/// "New item" from the menu-items step, "Edit item" on one item from the
/// recipes step ("Add recipe"). Name and description in both languages, the
/// category (with "+" for a new one), Active, the image, the price or the
/// sizes, the recipe per size (the embedded recipe builder) and the add-ons
/// customers may pick.
///
/// Save, in the web's order: the item (`POST /menu-items` with its "from"
/// price, or `PATCH /menu-items/{id}`), its sizes (`PUT …/sizes`), each
/// size's recipe (`PUT /menu-item-sizes/{id}/recipe`), a new item's picked
/// image (`POST /uploads/menu-items/{id}`), and the add-on groups when the
/// picks changed (`PUT …/modifier-groups`); then it refreshes the catalog and
/// recipe reads, toasts "Changes saved" and closes. A failure toasts the
/// server's words and keeps everything typed.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart'
    show
        AddonItem,
        ApiFilePart,
        Category,
        CreateMenuItemRequest,
        GroupAttachInput,
        GroupOut,
        MenuItem,
        MenuItemFull,
        MenuItemRecipe,
        OrgIngredient,
        PutModifierGroupsRequest,
        PutRecipeRequest,
        PutSizesRequest,
        RecipeLineInput,
        SizeInput,
        UpdateMenuItemRequest,
        UploadImageMultipart;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/tax_rate.dart' show formatRate;
import '../onboarding_data.dart';
import '../org_identity_step.dart' show OnbImage, mimeOf;
import 'category_dialog.dart';
import 'menu_reads.dart';
import 'menu_text.dart';
import 'recipe_builder.dart';

/// Opens the editor on [item] (null = a new item).
Future<void> showMenuItemDialog(
  BuildContext context, {
  required String orgId,
  MenuItem? item,
}) => showDashDialog<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (_) => MenuItemDialog(orgId: orgId, item: item),
);

/// A selection of add-on ids as one comparable value, order-free.
String selectionKey(Iterable<String> ids) => (ids.toList()..sort()).join(',');

/// One size row as typed.
class SizeDraft {
  SizeDraft({required this.key, this.label = '', this.price = '0'});

  final int key;
  String label;

  /// Pounds as typed.
  String price;
}

/// The form's messages (zod's schema), keyed by field; empty = valid.
Map<String, String> validateMenuItem({
  required String name,
  required String categoryId,
  required List<SizeDraft> sizes,
  required Translator t,
}) => {
  if (name.isEmpty) 'name': t('common.requiredField'),
  if (categoryId.isEmpty) 'category_id': t('common.requiredField'),
  if (sizes.isEmpty) 'sizes': t('menu.needsOneSize'),
  for (final (i, s) in sizes.indexed) ...{
    if (s.label.isEmpty) 'sizes.$i.label': t('common.requiredField'),
    if (jsNumber(s.price).isNaN)
      'sizes.$i.price': t('onboarding.form.notANumber')
    else if (jsNumber(s.price) < 0)
      'sizes.$i.price': t('onboarding.form.priceMin'),
  },
};

/// The add-on groups an item offers for [allowed]: each add-on's type maps
/// to its reusable group (by legacy type, else name), the picks becoming that
/// attachment's `included_option_ids`, in first-picked order.
List<GroupAttachInput> addonAttachments(
  Iterable<String> allowed,
  List<AddonItem> addons,
  List<GroupOut> groups,
) {
  final typeOf = {for (final a in addons) a.id: a.addonType};
  final groupByType = {for (final g in groups) g.legacyAddonType ?? g.name: g};
  final byType = <String, List<String>>{};
  for (final id in allowed) {
    final ty = typeOf[id];
    if (ty == null) continue;
    (byType[ty] ??= []).add(id);
  }
  return [
    for (final (i, e) in byType.entries.indexed)
      if (groupByType[e.key] case final g?)
        GroupAttachInput(groupId: g.id, sort: i, includedOptionIds: e.value),
  ];
}

class MenuItemDialog extends ConsumerStatefulWidget {
  const MenuItemDialog({required this.orgId, this.item, super.key});

  final String orgId;

  /// Null = a new item.
  final MenuItem? item;

  @override
  ConsumerState<MenuItemDialog> createState() => _MenuItemDialogState();
}

class _MenuItemDialogState extends ConsumerState<MenuItemDialog> {
  var _seq = 0;
  late String _name = widget.item?.name ?? '';
  late String _nameAr = arOf(widget.item?.nameTranslations);
  late String _desc = widget.item?.description ?? '';
  late String _descAr = arOf(widget.item?.descriptionTranslations);
  late String _categoryId = widget.item?.categoryId ?? '';
  late bool _active = widget.item?.isActive ?? true;

  /// New item: one price box. Editing: replaced when the full item lands.
  late List<SizeDraft> _sizes = [
    if (widget.item == null) SizeDraft(key: _seq++, label: oneSize),
  ];
  List<CleanRow> _recipeRows = const [];
  Set<String> _allowed = {};
  String _seededAllowed = '';

  /// The full item the sizes and picks were last seeded from.
  MenuItemFull? _seededFrom;

  /// The sizes or the add-on picks were changed by hand: a refresh landing
  /// no longer re-seeds them.
  bool _touched = false;
  String _addonSearch = '';
  DashPickedFile? _pendingImage;
  String? _pendingPreview;
  bool _submitted = false;
  bool _busy = false;

  bool get _editing => widget.item != null;

  /// A hand edit of the sizes or the add-on picks.
  void _edit(VoidCallback change) => setState(() {
    _touched = true;
    change();
  });

  bool get _singlePrice => _sizes.length == 1 && _sizes.first.label == oneSize;

  /// Seeds the sizes and the add-on picks from the full item (edit): when it
  /// lands and again whenever a refresh brings a new answer, until they are
  /// edited (the web's effect on `liveItem`).
  void _seedFrom(MenuItemFull live) {
    if (_touched || identical(live, _seededFrom)) return;
    _seededFrom = live;
    // `all_sizes` includes the synthetic `one_size` row of a simple item.
    final rows = live.allSizes ?? live.sizes;
    _sizes = [
      for (final s in rows)
        if (s.isActive)
          SizeDraft(
            key: _seq++,
            label: s.label,
            price: egpText(s.priceOverride),
          ),
    ];
    _allowed = {...live.allowedAddonIds};
    _seededAllowed = selectionKey(live.allowedAddonIds);
  }

  /// The price of [size] in piastres: its own row, else the item's "from"
  /// price (the lowest size).
  int? _priceForSize(String size) {
    int? toP(String v) {
      final n = jsParseFloat(v);
      return n.isFinite ? jsRound(n * 100) : null;
    }

    for (final s in _sizes) {
      if (s.label == size) {
        final exact = toP(s.price);
        if (exact != null) return exact;
        break;
      }
    }
    final all = [for (final s in _sizes) ?toP(s.price)];
    return all.isEmpty ? null : all.reduce((a, b) => a < b ? a : b);
  }

  Future<void> _save() async {
    final t = ref.read(tProvider);
    setState(() => _submitted = true);
    if (validateMenuItem(
      name: _name,
      categoryId: _categoryId,
      sizes: _sizes,
      t: t,
    ).isNotEmpty) {
      return;
    }
    setState(() => _busy = true);
    final api = ref.read(apiProvider);
    final invalidate = ref.menuInvalidate;
    final addons = ref.read(addonItemsProvider(widget.orgId)).value ?? const [];
    final groups =
        ref.read(modifierGroupsProvider(widget.orgId)).value ?? const [];
    try {
      final nameTr = _nameAr.isEmpty ? null : <String, Object?>{'ar': _nameAr};
      final descTr = _descAr.isEmpty ? null : <String, Object?>{'ar': _descAr};
      final sizes = [
        for (final s in _sizes)
          (label: s.label, price: egpToPiastres(jsNumber(s.price))),
      ];
      final item = widget.item;
      final String itemId;
      if (item != null) {
        itemId = (await api.menu.updateMenuItem(
          id: item.id,
          body: UpdateMenuItemRequest(
            name: _name,
            nameTranslations: nameTr,
            description: _desc.isEmpty ? null : _desc,
            descriptionTranslations: descTr,
            categoryId: _categoryId,
            isActive: _active,
            explicitNulls: {if (_desc.isEmpty) 'description'},
          ),
        )).id;
      } else {
        // The API still wants one number on create: the "from" price.
        itemId = (await api.menu.createMenuItem(
          body: CreateMenuItemRequest(
            orgId: widget.orgId,
            name: _name,
            nameTranslations: nameTr,
            description: _desc.isEmpty ? null : _desc,
            descriptionTranslations: descTr,
            categoryId: _categoryId,
            basePrice: sizes
                .map((s) => s.price)
                .reduce((a, b) => a < b ? a : b),
            explicitNulls: {if (_desc.isEmpty) 'description'},
          ),
        )).id;
      }
      final studio = await api.menu.putSizes(
        id: itemId,
        body: PutSizesRequest(
          sizes: [
            for (final (i, s) in sizes.indexed)
              SizeInput(
                label: s.label,
                price: s.price,
                sort: i,
                isActive: true,
              ),
          ],
        ),
      );
      for (final size in studio.sizes) {
        await api.menu.putSizeRecipe(
          sizeId: size.id,
          body: PutRecipeRequest(
            lines: [
              for (final r in _recipeRows)
                if (r.sizeLabel == size.label && r.orgIngredientId != null)
                  RecipeLineInput(
                    ingredientId: r.orgIngredientId!,
                    quantity: r.quantityUsed,
                    unit: r.ingredientUnit,
                  ),
            ],
          ),
        );
      }
      final pending = _pendingImage;
      if (item == null && pending != null) {
        await api.uploads.uploadMenuItemImage(
          menuItemId: itemId,
          body: UploadImageMultipart(image: _filePart(pending)),
        );
      }
      if (selectionKey(_allowed) != _seededAllowed) {
        await api.menu.putModifierGroups(
          id: itemId,
          body: PutModifierGroupsRequest(
            groups: addonAttachments(_allowed, addons, groups),
          ),
        );
      }
      invalidate
        ..catalog()
        ..recipes();
      if (!mounted) return;
      DashToast.success(context, t('common.savedChanges'));
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  static ApiFilePart _filePart(DashPickedFile f) => ApiFilePart(
    field: 'image',
    filename: f.name,
    bytes: f.bytes,
    contentType: f.mimeType,
  );

  Future<DashPickedFile?> _pick() async {
    final f = await ref.read(fileGatewayProvider).pickImage();
    if (f == null) return null;
    return DashPickedFile(
      bytes: Uint8List.fromList(f.bytes),
      name: f.name,
      mimeType: f.mimeType ?? mimeOf(f.name),
    );
  }

  Future<void> _newCategory() async {
    final created = await showCategoryDialog(context, orgId: widget.orgId);
    if (created == null || !mounted) return;
    setState(() => _categoryId = created.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final lang = ref.watch(localeProvider);
    final item = widget.item;
    final live = item == null
        ? null
        : ref.watch(menuItemProvider(item.id)).value;
    if (live != null) _seedFrom(live);
    final categories =
        ref.watch(menuCategoriesProvider(widget.orgId)).value ??
        const <Category>[];
    final catalog =
        ref.watch(ingredientCatalogProvider(widget.orgId)).value ??
        const <OrgIngredient>[];
    final addons =
        ref.watch(addonItemsProvider(widget.orgId)).value ??
        const <AddonItem>[];
    ref.watch(modifierGroupsProvider(widget.orgId));
    final errors = _submitted
        ? validateMenuItem(
            name: _name,
            categoryId: _categoryId,
            sizes: _sizes,
            t: t,
          )
        : const <String, String>{};
    final twoUp = !DashBreakpoints.isPhone(context);

    final initialRecipe = [
      for (final r in live?.recipes ?? const <MenuItemRecipe>[])
        RecipeRowInit(
          sizeLabel: r.sizeLabel,
          orgIngredientId: r.orgIngredientId,
          ingredientName: r.ingredientName,
          ingredientUnit: r.ingredientUnit,
          quantityUsed: r.quantityUsed,
        ),
    ];
    final labels = [
      for (final s in _sizes)
        if (s.label.isNotEmpty) s.label,
    ];
    final recipeSizes = <String>{
      ...(labels.isEmpty ? const [oneSize] : labels),
      for (final r in initialRecipe) r.sizeLabel,
    }.toList();

    Widget section(String icon, String title, {String? hint}) => Container(
      padding: const EdgeInsets.only(top: Space.lg),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DashIcon(icon, color: c.accent),
          Text(
            title,
            style: DashType.bodyStrong.copyWith(color: c.textPrimary),
          ),
          if (hint != null)
            Text(hint, style: DashType.small.copyWith(color: c.textSecondary)),
        ],
      ),
    );

    final priceLabel = '${t('common.price')} (EGP)';
    final category = DashFormField<String>(
      label: t('common.category'),
      errorText: errors['category_id'],
      value: _categoryId,
      builder: (context, invalid) => Row(
        spacing: Space.sm,
        children: [
          Expanded(
            child: DashSelect<String>(
              key: const ValueKey('item-category'),
              options: [
                for (final cat in categories)
                  DashOption(
                    value: cat.id,
                    label: translatedName(cat.name, cat.nameTranslations, lang),
                  ),
              ],
              value: _categoryId.isEmpty ? null : _categoryId,
              invalid: invalid,
              placeholder: t('menu.selectCategory'),
              semanticLabel: t('common.category'),
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ),
          DashIconButton(
            icon: 'plus',
            semanticLabel: t('menu.newCategory'),
            variant: DashButtonVariant.outline,
            onPressed: _newCategory,
          ),
        ],
      ),
    );

    return DashSurface(
      title: _editing ? t('menu.editItem') : t('menu.newItem'),
      description: t('menu.itemDesc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DashBilingualField(
            label: t('common.name'),
            en: _name,
            ar: _nameAr,
            enError: errors['name'],
            onEnChanged: (v) => setState(() => _name = v),
            onArChanged: (v) => setState(() => _nameAr = v),
          ),
          DashBilingualField(
            label: t('common.description'),
            en: _desc,
            ar: _descAr,
            textarea: true,
            onEnChanged: (v) => setState(() => _desc = v),
            onArChanged: (v) => setState(() => _descAr = v),
          ),
          if (twoUp)
            Row(
              children: [
                Expanded(child: category),
                const Spacer(),
              ],
            )
          else
            category,
          Row(
            spacing: Space.sm,
            children: [
              DashSwitch(
                value: _active,
                semanticLabel: t('common.active'),
                onChanged: (v) => setState(() => _active = v),
              ),
              Text(
                t('common.active'),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
            ],
          ),
          // Image
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xs + DashMetrics.hair,
            children: [
              Text(
                t('menu.itemImage'),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              SizedBox(width: _imageWidth, child: _image(t, item, live)),
            ],
          ),
          // Price & sizes: the only place a price is entered.
          Container(
            padding: const EdgeInsets.only(top: Space.lg),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.hairline)),
            ),
            child: Row(
              spacing: Space.sm,
              children: [
                DashIcon('ruler', color: c.accent),
                Expanded(
                  child: Text(
                    _singlePrice ? t('menu.priceSection') : t('menu.sizes'),
                    style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                  ),
                ),
                DashButton(
                  key: const ValueKey('item-add-size'),
                  label: t('menu.addSize'),
                  icon: 'plus',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed: () => _edit(() {
                    // Leaving one-price mode: the sentinel label becomes a
                    // real one the customer sees.
                    if (_singlePrice) _sizes.first.label = '';
                    _sizes = [..._sizes, SizeDraft(key: _seq++)];
                  }),
                ),
              ],
            ),
          ),
          if (_singlePrice)
            _box(
              c,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.xs,
                children: [
                  DashTextField(
                    key: const ValueKey('item-price'),
                    label: priceLabel,
                    value: _sizes.first.price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textDirection: TextDirection.ltr,
                    errorText: errors['sizes.0.price'],
                    onChanged: (v) =>
                        _edit(() => _sizes.first.price = cleanDecimal(v)),
                  ),
                  _PriceTaxHint(orgId: widget.orgId),
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      t('menu.addSizeHint'),
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.sm,
              children: [
                for (final (i, s) in _sizes.indexed)
                  _box(
                    c,
                    Row(
                      key: ValueKey('item-size-${s.key}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.md,
                      children: [
                        Expanded(
                          child: DashTextField(
                            key: ValueKey('item-size-label-$i'),
                            label: t('menu.sizeLabel'),
                            placeholder: 'Large',
                            value: s.label,
                            errorText: errors['sizes.$i.label'],
                            onChanged: (v) => _edit(() => s.label = v),
                          ),
                        ),
                        Expanded(
                          child: DashTextField(
                            key: ValueKey('item-size-price-$i'),
                            label: priceLabel,
                            value: s.price,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textDirection: TextDirection.ltr,
                            errorText: errors['sizes.$i.price'],
                            onChanged: (v) =>
                                _edit(() => s.price = cleanDecimal(v)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xl),
                          child: DashIconButton(
                            icon: 'trash-2',
                            semanticLabel: t('menu.removeSize'),
                            color: c.errorText,
                            // The last size holds the item's price: it stays.
                            onPressed: _sizes.length <= 1
                                ? null
                                : () => _edit(() => _sizes.removeAt(i)),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (errors['sizes'] case final e?)
                  Text(e, style: DashType.small.copyWith(color: c.errorText)),
              ],
            ),
          section('book-open', t('menu.recipe'), hint: t('menu.recipeHint')),
          RecipeBuilder(
            orgId: widget.orgId,
            sizes: recipeSizes,
            initialRows: initialRecipe,
            catalog: catalog,
            priceForSize: _priceForSize,
            deferred: true,
            onRowsChange: (rows) => _recipeRows = rows,
            allowCreateIngredient: false,
          ),
          section('cup-soda', t('menu.addons'), hint: t('menu.addonsHint')),
          _AddonPicker(
            addons: addons,
            allowed: _allowed,
            search: _addonSearch,
            onSearch: (v) => setState(() => _addonSearch = v),
            onChanged: (next) => _edit(() => _allowed = next),
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

  static const double _imageWidth = 200;

  Widget _box(MadarColors c, Widget child) => Container(
    padding: const EdgeInsets.all(Space.md),
    decoration: BoxDecoration(
      color: c.muted.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(Radii.md),
      border: Border.all(color: c.hairline),
    ),
    child: child,
  );

  Widget _image(Translator t, MenuItem? item, MenuItemFull? live) {
    if (item == null) {
      // A new item: the picture waits for the item and uploads after Save.
      return DashImageUploader(
        key: const ValueKey('item-image'),
        value: _pendingPreview,
        square: false,
        hint: t('menu.imageAfterSave'),
        onPick: _pick,
        imageBuilder: (context, url) => OnbImage(url: url),
        onUpload: (file) async {
          final url =
              'data:${file.mimeType};base64,${base64Encode(file.bytes)}';
          setState(() {
            _pendingImage = file;
            _pendingPreview = url;
          });
          return url;
        },
        onRemove: _pendingPreview == null
            ? null
            : () async => setState(() {
                _pendingImage = null;
                _pendingPreview = null;
              }),
      );
    }
    // `||`: an empty string is a field left blank, not a picture.
    final current = (live?.imageUrl ?? '').isNotEmpty
        ? live!.imageUrl
        : item.imageUrl;
    final has =
        live?.image != null ||
        item.image != null ||
        (live?.imageUrl ?? '').isNotEmpty ||
        (item.imageUrl ?? '').isNotEmpty;
    final api = ref.read(apiProvider);
    final invalidate = ref.menuInvalidate;
    return DashImageUploader(
      key: const ValueKey('item-image'),
      value: current,
      square: false,
      hint: t('menu.imageHint'),
      onPick: _pick,
      imageBuilder: (context, url) => OnbImage(url: url),
      onUpload: (file) async {
        try {
          final res = await api.uploads.uploadMenuItemImage(
            menuItemId: item.id,
            body: UploadImageMultipart(image: _filePart(file)),
          );
          invalidate.catalog();
          return res.imageUrl;
        } on Object catch (e) {
          throw _UploadFailure(errorMessage(e, t));
        }
      },
      onRemove: has
          ? () async {
              await api.menu.updateMenuItem(
                id: item.id,
                body: const UpdateMenuItemRequest(explicitNulls: {'image_url'}),
              );
              invalidate.catalog();
            }
          : null,
    );
  }
}

class _UploadFailure implements Exception {
  const _UploadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Whether a price already contains the tax (`PriceTaxHint`): shown when
/// the org charges tax.
class _PriceTaxHint extends ConsumerWidget {
  const _PriceTaxHint({required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final org = ref.watch(onbOrgProvider(orgId)).value;
    if (org == null || !(org.taxRate > 0)) return const SizedBox.shrink();
    final rate = formatRate(org.taxRate);
    final words = org.taxInclusive
        ? t('menu.priceIncludesTax', args: {'rate': rate})
        : t('menu.priceExcludesTax', args: {'rate': rate});
    return Text(
      '$words · ${t('menu.priceTaxBranchNote')}',
      key: const ValueKey('price-tax-hint'),
      style: DashType.small.copyWith(color: context.madarColors.textSecondary),
    );
  }
}

/// The picked add-ons as removable chips, then a search and the add-ons
/// grouped by type, each group with Select all / Deselect all.
class _AddonPicker extends ConsumerWidget {
  const _AddonPicker({
    required this.addons,
    required this.allowed,
    required this.search,
    required this.onSearch,
    required this.onChanged,
  });

  final List<AddonItem> addons;
  final Set<String> allowed;
  final String search;
  final ValueChanged<String> onSearch;
  final ValueChanged<Set<String>> onChanged;

  /// The picker's scroll height (`max-h-52`).
  static const double _maxHeight = 208;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final q = search.trim().toLowerCase();
    final byType = <String, List<AddonItem>>{};
    for (final a in addons) {
      if (q.isNotEmpty && !a.name.toLowerCase().contains(q)) continue;
      (byType[a.addonType] ??= []).add(a);
    }
    final selected = [
      for (final a in addons)
        if (allowed.contains(a.id)) a,
    ];
    void toggle(String id) => onChanged(
      allowed.contains(id) ? ({...allowed}..remove(id)) : {...allowed, id},
    );
    final small = DashType.small.copyWith(color: c.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        if (selected.isNotEmpty)
          Wrap(
            spacing: Space.xs + DashMetrics.hair,
            runSpacing: Space.xs + DashMetrics.hair,
            children: [
              for (final a in selected)
                Container(
                  padding: const EdgeInsetsDirectional.only(
                    start: Space.sm + DashMetrics.hair,
                  ),
                  decoration: BoxDecoration(
                    color: c.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        a.name,
                        style: DashType.smallMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      DashIconButton(
                        icon: 'x',
                        iconSize: IconSize.xs,
                        semanticLabel: t('common.remove'),
                        tooltip: false,
                        onPressed: () => toggle(a.id),
                      ),
                    ],
                  ),
                ),
            ],
          )
        else
          Text(t('menu.addonsEmpty'), style: small),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: c.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: DashSearchInput(
                  value: search,
                  placeholder: t('menu.searchAddons'),
                  onChanged: onSearch,
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxHeight: _maxHeight),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.hairline)),
                ),
                child: byType.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.lg),
                        child: Text(
                          t('menu.noAddonsMatch'),
                          textAlign: TextAlign.center,
                          style: small,
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final MapEntry(key: type, value: items)
                              in byType.entries)
                            _AddonGroup(
                              type: type,
                              items: items,
                              allowed: allowed,
                              onToggle: toggle,
                              onAll: (on) => onChanged(
                                on
                                    ? {...allowed, for (final a in items) a.id}
                                    : ({...allowed}
                                        ..removeAll(items.map((a) => a.id))),
                              ),
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

class _AddonGroup extends ConsumerWidget {
  const _AddonGroup({
    required this.type,
    required this.items,
    required this.allowed,
    required this.onToggle,
    required this.onAll,
  });

  final String type;
  final List<AddonItem> items;
  final Set<String> allowed;
  final ValueChanged<String> onToggle;
  final ValueChanged<bool> onAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final all = items.every((a) => allowed.contains(a.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: c.muted.withValues(alpha: 0.3),
          padding: const EdgeInsetsDirectional.only(start: Space.md),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: humanizeAddonType(type),
                    children: [
                      TextSpan(
                        text: '  (${items.length})',
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                  style: DashType.smallMedium.copyWith(color: c.textPrimary),
                ),
              ),
              DashButton(
                label: all ? t('common.deselectAll') : t('common.selectAll'),
                variant: DashButtonVariant.link,
                size: DashButtonSize.compact,
                onPressed: () => onAll(!all),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.sm + DashMetrics.hair),
          child: Wrap(
            spacing: Space.xs + DashMetrics.hair,
            runSpacing: Space.xs + DashMetrics.hair,
            children: [
              for (final a in items)
                DashCheckChip(
                  label: a.name,
                  value: allowed.contains(a.id),
                  onChanged: (_) => onToggle(a.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
