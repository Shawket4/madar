/// The item dialog (the web's `menu-item-dialog.tsx`, MENU-ITEMS-072..092,
/// 112, 115): name, description, category (with "+" for a new one), active,
/// the picture, the price or the sizes, the recipe per size (the embedded
/// recipe builder) and the add-ons offered. Create from the items page; edit
/// is the onboarding's (same dialog).
///
/// Save, in the web's order: the item (create / patch), its sizes
/// (replace-set), each returned size's recipe, the staged picture (create),
/// then the add-on attachments when the selection changed. A failure at any
/// step toasts the server's words and keeps the dialog open.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart'
    show
        AddonItem,
        ApiFilePart,
        GroupOut,
        Category,
        CreateMenuItemRequest,
        MenuItem,
        MenuItemFull,
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

import '../recipes/recipe_builder.dart';
import '../shared/category_dialog.dart';
import '../shared/menu_bilingual_field.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import '../studio/studio_providers.dart' show studioMenuItemProvider;
import 'items_data.dart';
import 'items_widgets.dart';

/// How often an upload's job is asked about, and for how long (`POLL_MS`,
/// `POLL_LIMIT_MS`).
const Duration assetPollEvery = Duration(seconds: 3);
const Duration assetPollLimit = Duration(seconds: 60);

/// The add-on picker's height cap (`max-h-52`).
const double _pickerHeight = 208;

Future<void> showMenuItemDialog(
  BuildContext context, {
  required String orgId,
  MenuItem? item,
  String? defaultCategoryId,
}) => showDashDialog<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (_) => MenuItemDialog(
    orgId: orgId,
    item: item,
    defaultCategoryId: defaultCategoryId,
  ),
);

/// Words to show under the uploader (its error is the thrown value's text).
class _Words implements Exception {
  const _Words(this.text);
  final String text;

  @override
  String toString() => text;
}

class _SizeRow {
  _SizeRow({required this.label, required this.price});

  final Key key = UniqueKey();
  String label;
  String price;
}

class MenuItemDialog extends ConsumerStatefulWidget {
  const MenuItemDialog({
    required this.orgId,
    this.item,
    this.defaultCategoryId,
    super.key,
  });

  final String orgId;

  /// Null = a new item.
  final MenuItem? item;

  /// The page's category filter, the new item's category.
  final String? defaultCategoryId;

  @override
  ConsumerState<MenuItemDialog> createState() => _MenuItemDialogState();
}

class _MenuItemDialogState extends ConsumerState<MenuItemDialog> {
  late String _name = widget.item?.name ?? '';
  late String _nameAr = arOf(widget.item?.nameTranslations);
  late String _desc = widget.item?.description ?? '';
  late String _descAr = arOf(widget.item?.descriptionTranslations);
  late String? _categoryId =
      widget.item?.categoryId ?? widget.defaultCategoryId;
  late bool _active = widget.item?.isActive ?? true;

  /// New item: one price box. Editing: filled when the full item lands.
  late final List<_SizeRow> _sizes = widget.item == null
      ? [_SizeRow(label: oneSize, price: '0')]
      : [];
  List<CleanRow> _recipeRows = const [];
  List<RecipeRowInit> _initialRecipe = const [];
  final Set<String> _allowed = {};
  String _seededAllowed = '';

  /// The person has changed the form: fresh reads stop re-seeding it.
  bool _touched = false;
  String _addonSearch = '';

  DashPickedFile? _pendingImage;
  String? _jobId;
  DateTime? _jobStarted;
  Timer? _poll;
  String? _jobError;

  String? _nameError;
  String? _categoryError;
  String? _sizesError;
  final Map<Key, String> _labelErrors = {};
  bool _busy = false;

  bool get _editing => widget.item != null;

  /// Set once [initState] is done (a cached item seeds before that).
  bool _ready = false;

  bool get _singlePrice => _sizes.length == 1 && _sizes.first.label == oneSize;

  /// A change the person made.
  void _edit(VoidCallback change) => setState(() {
    _touched = true;
    change();
  });

  /// The builder streams its rows on every change; they count as the
  /// person's once they differ from what the read seeded.
  void _rowsChanged(List<CleanRow> rows) {
    _recipeRows = rows;
    String sig(Iterable<(String, String?, double)> r) =>
        ([for (final x in r) '${x.$1}|${x.$2}|${x.$3}']..sort()).join(';');
    final seeded = sig([
      for (final r in _initialRecipe)
        if (r.quantityUsed > 0)
          (r.sizeLabel, r.orgIngredientId, r.quantityUsed),
    ]);
    final now = sig([
      for (final r in rows) (r.sizeLabel, r.orgIngredientId, r.quantityUsed),
    ]);
    if (now != seeded) _touched = true;
  }

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null) {
      // Each fresh read (the cached copy, then a background refresh of it)
      // re-seeds the form until the person edits it.
      ref.listenManual(studioMenuItemProvider(item.id), (prev, next) {
        final full = next.value;
        if (full == null || _touched || identical(full, prev?.value)) return;
        _seed(full);
        if (_ready) setState(() {});
      }, fireImmediately: true);
    }
    _ready = true;
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// The item's fields, its sizes (active ones of `all_sizes`, prices in
  /// pounds), the recipe rows and the offered add-ons, from a read.
  void _seed(MenuItemFull full) {
    _name = full.name;
    _nameAr = arOf(full.nameTranslations);
    _desc = full.description ?? '';
    _descAr = arOf(full.descriptionTranslations);
    _categoryId = full.categoryId;
    _active = full.isActive;
    _sizes
      ..clear()
      ..addAll([
        for (final s in full.allSizes ?? full.sizes)
          if (s.isActive)
            _SizeRow(label: s.label, price: egpText(s.priceOverride)),
      ]);
    _initialRecipe = [
      for (final r in full.recipes)
        RecipeRowInit(
          sizeLabel: r.sizeLabel,
          orgIngredientId: r.orgIngredientId,
          ingredientName: r.ingredientName,
          ingredientUnit: r.ingredientUnit,
          quantityUsed: r.quantityUsed,
        ),
    ];
    _allowed
      ..clear()
      ..addAll(full.allowedAddonIds);
    _seededAllowed = selectionKey(full.allowedAddonIds);
  }

  List<String> get _recipeSizes {
    final labels = [
      for (final s in _sizes)
        if (s.label.isNotEmpty) s.label,
    ];
    return {
      ...(labels.isEmpty ? const [oneSize] : labels),
      for (final r in _initialRecipe) r.sizeLabel,
    }.toList();
  }

  int? _priceForSize(String size) {
    for (final s in _sizes) {
      if (s.label == size) {
        final p = egpTextToPiastres(s.price);
        if (p != null) return p;
        break;
      }
    }
    final all = [for (final s in _sizes) ?egpTextToPiastres(s.price)];
    return all.isEmpty ? null : all.reduce((a, b) => a < b ? a : b);
  }

  /// The zod schema: every message at once; true when the form is valid.
  bool _validate() {
    final t = ref.read(tProvider);
    final req = t('common.requiredField');
    setState(() {
      _nameError = _name.isEmpty ? req : null;
      _categoryError = (_categoryId ?? '').isEmpty ? req : null;
      _labelErrors
        ..clear()
        ..addAll({
          for (final s in _sizes)
            if (s.label.isEmpty) s.key: req,
        });
      _sizesError = _sizes.isEmpty ? t('menu.needsOneSize') : null;
    });
    return _nameError == null &&
        _categoryError == null &&
        _labelErrors.isEmpty &&
        _sizesError == null;
  }

  Future<void> _save() async {
    if (_busy || !_validate()) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final addons = ref.read(addonItemsProvider(widget.orgId)).value ?? [];
    final groups =
        ref
            .read(
              modifierGroupsProvider((
                orgId: widget.orgId,
                includeInactive: false,
              )),
            )
            .value ??
        [];
    setState(() => _busy = true);
    final invalidate = ref.menuInvalidate;
    final nameTr = _nameAr.isEmpty ? null : <String, Object?>{'ar': _nameAr};
    final descTr = _descAr.isEmpty ? null : <String, Object?>{'ar': _descAr};
    final desc = _desc.isEmpty ? null : _desc;
    final prices = [for (final s in _sizes) egpTextToPiastres(s.price) ?? 0];
    try {
      final item = widget.item;
      final String itemId;
      if (item != null) {
        await api.menu.updateMenuItem(
          id: item.id,
          body: UpdateMenuItemRequest(
            name: _name,
            nameTranslations: nameTr,
            description: desc,
            descriptionTranslations: descTr,
            categoryId: _categoryId,
            isActive: _active,
            explicitNulls: const {'description'},
          ),
        );
        itemId = item.id;
      } else {
        final created = await api.menu.createMenuItem(
          body: CreateMenuItemRequest(
            orgId: widget.orgId,
            name: _name,
            nameTranslations: nameTr,
            description: desc,
            descriptionTranslations: descTr,
            categoryId: _categoryId!,
            basePrice: prices.reduce((a, b) => a < b ? a : b),
            explicitNulls: const {'description'},
          ),
        );
        itemId = created.id;
      }
      final studio = await api.menu.putSizes(
        id: itemId,
        body: PutSizesRequest(
          sizes: [
            for (final (i, s) in _sizes.indexed)
              SizeInput(
                label: s.label,
                price: prices[i],
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
      final image = _pendingImage;
      if (item == null && image != null) {
        await api.uploads.uploadMenuItemImage(
          menuItemId: itemId,
          body: UploadImageMultipart(image: _filePart(image)),
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
      mimeType: f.mimeType ?? _mimeOf(f.name),
    );
  }

  static String _mimeOf(String name) =>
      switch (name.split('.').last.toLowerCase()) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        _ => 'application/octet-stream',
      };

  /// Edit: uploads now; a "processing" answer is followed until it settles.
  Future<String?> _upload(DashPickedFile file) async {
    final t = ref.read(tProvider);
    final invalidate = ref.menuInvalidate;
    try {
      final res = await ref
          .read(apiProvider)
          .uploads
          .uploadMenuItemImage(
            menuItemId: widget.item!.id,
            body: UploadImageMultipart(image: _filePart(file)),
          );
      invalidate.catalog();
      if (!mounted) return res.imageUrl;
      if (res.status == 'processing' && res.assetJobId.isNotEmpty) {
        _follow(res.assetJobId);
        return null;
      }
      return res.imageUrl;
    } on Object catch (e) {
      throw _Words(errorMessage(e, t));
    }
  }

  void _follow(String jobId) {
    _poll?.cancel();
    setState(() {
      _jobId = jobId;
      _jobError = null;
      _jobStarted = ref.read(clockProvider)();
    });
    unawaited(_check(jobId));
  }

  Future<void> _check(String jobId) async {
    final t = ref.read(tProvider);
    final invalidate = ref.menuInvalidate;
    try {
      final job = await ref.read(apiProvider).assets.getJob(id: jobId);
      if (!mounted || _jobId != jobId) return;
      if (job.status == 'done' || job.status == 'failed') {
        setState(() {
          _jobId = null;
          if (job.status == 'failed') {
            _jobError = job.error ?? t('uploader.processingFailed');
          }
        });
        invalidate.catalog();
        return;
      }
    } on Object {
      if (!mounted || _jobId != jobId) return;
    }
    final elapsed = ref.read(clockProvider)().difference(_jobStarted!);
    if (elapsed < assetPollLimit) {
      _poll = Timer(assetPollEvery, () => _check(jobId));
    }
  }

  Future<void> _removeImage() async {
    final t = ref.read(tProvider);
    final invalidate = ref.menuInvalidate;
    try {
      await ref
          .read(apiProvider)
          .menu
          .updateMenuItem(
            id: widget.item!.id,
            body: const UpdateMenuItemRequest(explicitNulls: {'image_url'}),
          );
      invalidate.catalog();
    } on Object catch (e) {
      throw _Words(errorMessage(e, t));
    }
  }

  Future<void> _newCategory() async {
    final created = await showCategoryDialog(context, orgId: widget.orgId);
    if (created == null || !mounted) return;
    _edit(() {
      _categoryId = created.id;
      _categoryError = null;
    });
  }

  void _addSize() => _edit(() {
    if (_singlePrice) _sizes.first.label = '';
    _sizes.add(_SizeRow(label: '', price: '0'));
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final lang = t.lang;
    final categories =
        ref.watch(menuCategoriesProvider(widget.orgId)).value ??
        const <Category>[];
    final catalog =
        ref.watch(ingredientCatalogProvider(widget.orgId)).value ?? const [];
    final addons =
        ref.watch(addonItemsProvider(widget.orgId)).value ??
        const <AddonItem>[];
    final groups =
        ref
            .watch(
              modifierGroupsProvider((
                orgId: widget.orgId,
                includeInactive: false,
              )),
            )
            .value ??
        const <GroupOut>[];
    final full = _editing
        ? ref.watch(studioMenuItemProvider(widget.item!.id)).value
        : null;

    Widget section(String icon, String title, [String? hint]) => Wrap(
      spacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DashIcon(icon, size: IconSize.sm, color: c.accent),
        Text(title, style: DashType.bodyStrong.copyWith(color: c.textPrimary)),
        if (hint != null)
          Text(hint, style: DashType.small.copyWith(color: c.textSecondary)),
      ],
    );
    Widget divided(Widget child) => Container(
      padding: const EdgeInsets.only(top: Space.lg),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: child,
    );
    final priceLabel =
        '${t('common.price')} (${ref.watch(formatProvider).currencyLabel()})';

    final category = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: Space.sm,
      children: [
        Expanded(
          child: DashSelectField<String>(
            label: t('common.category'),
            placeholder: t('menu.selectCategory'),
            errorText: _categoryError,
            value: _categoryId,
            options: [
              for (final cat in categories)
                DashOption(
                  value: cat.id,
                  label: translatedName(cat.name, cat.nameTranslations, lang),
                ),
            ],
            onChanged: (v) => _edit(() {
              _categoryId = v;
              _categoryError = null;
            }),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            bottom: _categoryError == null ? 0 : Space.xl,
          ),
          child: DashIconButton(
            icon: 'plus',
            semanticLabel: t('menu.newCategory'),
            variant: DashButtonVariant.outline,
            onPressed: _newCategory,
          ),
        ),
      ],
    );

    final image = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        Text(
          t('menu.itemImage'),
          style: DashType.bodyMedium.copyWith(color: c.textPrimary),
        ),
        if (_editing)
          DashImageUploader(
            value:
                _nonEmpty(full?.imageUrl) ??
                _nonEmpty(widget.item!.imageUrl) ??
                menuImageUrl(full?.image ?? widget.item!.image, null),
            processing: _jobId != null,
            onPick: _pick,
            onUpload: _upload,
            onRemove:
                (full?.image ?? widget.item!.image) != null ||
                    _nonEmpty(full?.imageUrl ?? widget.item!.imageUrl) != null
                ? _removeImage
                : null,
            hint: t('menu.imageHint'),
          )
        else
          DashImageUploader(
            value: null,
            onPick: _pick,
            onUpload: (f) async {
              setState(() => _pendingImage = f);
              return null;
            },
            onRemove: _pendingImage == null
                ? null
                : () async => setState(() => _pendingImage = null),
            hint: t('menu.imageAfterSave'),
          ),
        if (_jobError != null)
          Text(_jobError!, style: DashType.small.copyWith(color: c.errorText)),
      ],
    );

    final sizes = _singlePrice
        ? Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(Radii.control),
              border: Border.all(color: c.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.sm,
              children: [
                MenuPriceField(
                  key: _sizes.first.key,
                  label: priceLabel,
                  value: _sizes.first.price,
                  onChanged: (v) => _edit(() => _sizes.first.price = v),
                  onSubmit: _save,
                ),
                const PriceTaxHint(),
                Text(
                  t('menu.addSizeHint'),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              for (final s in _sizes)
                Container(
                  key: s.key,
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    color: c.muted.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(Radii.control),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.md,
                    children: [
                      Expanded(
                        child: DashTextField(
                          label: t('menu.sizeLabel'),
                          placeholder: t('menu.sizeLabelPlaceholder'),
                          value: s.label,
                          errorText: _labelErrors[s.key],
                          onChanged: (v) => _edit(() {
                            s.label = v;
                            _labelErrors.remove(s.key);
                          }),
                          onSubmitted: (_) => _save(),
                        ),
                      ),
                      Expanded(
                        child: MenuPriceField(
                          label: priceLabel,
                          value: s.price,
                          onChanged: (v) => _edit(() => s.price = v),
                          onSubmit: _save,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xl),
                        child: DashIconButton(
                          icon: 'trash-2',
                          semanticLabel: t('menu.removeSize'),
                          color: c.errorText,
                          onPressed: _sizes.length <= 1
                              ? null
                              : () => _edit(() => _sizes.remove(s)),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_sizesError != null)
                Text(
                  _sizesError!,
                  style: DashType.small.copyWith(color: c.errorText),
                ),
            ],
          );

    return DashSurface(
      title: _editing ? t('menu.editItem') : t('menu.newItem'),
      description: t('menu.itemDesc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          MenuBilingualField(
            label: t('common.name'),
            en: _name,
            ar: _nameAr,
            enError: _nameError,
            onEnChanged: (v) => _edit(() => _name = v),
            onArChanged: (v) => _edit(() => _nameAr = v),
            onSubmit: _save,
          ),
          MenuBilingualField(
            label: t('common.description'),
            en: _desc,
            ar: _descAr,
            textarea: true,
            onEnChanged: (v) => _edit(() => _desc = v),
            onArChanged: (v) => _edit(() => _descAr = v),
          ),
          category,
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.sm,
              children: [
                DashSwitch(
                  value: _active,
                  semanticLabel: t('common.active'),
                  onChanged: (v) => _edit(() => _active = v),
                ),
                Text(
                  t('common.active'),
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
              ],
            ),
          ),
          image,
          divided(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: section(
                        'ruler',
                        _singlePrice ? t('menu.priceSection') : t('menu.sizes'),
                      ),
                    ),
                    DashButton(
                      label: t('menu.addSize'),
                      icon: 'plus',
                      variant: DashButtonVariant.outline,
                      size: DashButtonSize.compact,
                      onPressed: _addSize,
                    ),
                  ],
                ),
                sizes,
              ],
            ),
          ),
          divided(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                section('book-open', t('menu.recipe'), t('menu.recipeHint')),
                RecipeBuilder(
                  orgId: widget.orgId,
                  sizes: _recipeSizes,
                  initialRows: _initialRecipe,
                  catalog: catalog,
                  priceForSize: _priceForSize,
                  deferred: true,
                  onRowsChange: _rowsChanged,
                  allowCreateIngredient: false,
                ),
              ],
            ),
          ),
          divided(_addonsSection(t, addons, groups)),
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

  static String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;

  Widget _addonsSection(
    Translator t,
    List<AddonItem> addons,
    List<GroupOut> groups,
  ) {
    // A type's header: its shared group's name in the active language (the
    // web humanizes the raw type, English in Arabic too), else the type.
    String typeTitle(String type) {
      for (final g in groups) {
        if (g.legacyAddonType == type) {
          return translatedName(g.name, g.nameTranslations, t.lang);
        }
      }
      return humanizeAddonType(type);
    }

    final c = context.madarColors;
    final selected = [
      for (final a in addons)
        if (_allowed.contains(a.id)) a,
    ];
    final picker = addonPickerGroups(addons, _addonSearch);
    String name(AddonItem a) =>
        translatedName(a.name, a.nameTranslations, t.lang);
    void toggle(String id) => _edit(() {
      if (!_allowed.remove(id)) _allowed.add(id);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        Wrap(
          spacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DashIcon('cup-soda', size: IconSize.sm, color: c.accent),
            Text(
              t('menu.addons'),
              style: DashType.bodyStrong.copyWith(color: c.textPrimary),
            ),
            Text(
              t('menu.addonsHint'),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ],
        ),
        if (selected.isEmpty)
          Text(
            t('menu.addonsEmpty'),
            style: DashType.small.copyWith(color: c.textSecondary),
          )
        else
          Wrap(
            spacing: Space.xs + DashMetrics.hair,
            runSpacing: Space.xs + DashMetrics.hair,
            children: [
              for (final a in selected)
                Container(
                  key: ValueKey('addon-chip-${a.id}'),
                  padding: const EdgeInsetsDirectional.only(start: Space.md),
                  decoration: BoxDecoration(
                    color: c.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name(a),
                        style: DashType.smallMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      DashIconButton(
                        icon: 'x',
                        semanticLabel: t('common.remove'),
                        iconSize: IconSize.xs,
                        onPressed: () => toggle(a.id),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.hairline),
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: DashSearchInput(
                  value: _addonSearch,
                  placeholder: t('menu.searchAddons'),
                  onChanged: (v) => setState(() => _addonSearch = v),
                ),
              ),
              Container(height: DashMetrics.hair, color: c.hairline),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _pickerHeight),
                child: picker.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.lg),
                        child: Text(
                          t('menu.noAddonsMatch'),
                          textAlign: TextAlign.center,
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (type, items) in picker)
                              _PickerGroup(
                                key: ValueKey('addon-group-$type'),
                                title: typeTitle(type),
                                count: items.length,
                                allSelected: items.every(
                                  (a) => _allowed.contains(a.id),
                                ),
                                onToggleAll: () => _edit(() {
                                  final all = items.every(
                                    (a) => _allowed.contains(a.id),
                                  );
                                  for (final a in items) {
                                    all
                                        ? _allowed.remove(a.id)
                                        : _allowed.add(a.id);
                                  }
                                }),
                                children: [
                                  for (final a in items)
                                    DashCheckChip(
                                      key: ValueKey('addon-pick-${a.id}'),
                                      label: name(a),
                                      value: _allowed.contains(a.id),
                                      onChanged: (_) => toggle(a.id),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PickerGroup extends StatelessWidget {
  const _PickerGroup({
    required this.title,
    required this.count,
    required this.allSelected,
    required this.onToggleAll,
    required this.children,
    super.key,
  });

  final String title;
  final int count;
  final bool allSelected;
  final VoidCallback onToggleAll;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.translator;
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
                    text: title,
                    style: DashType.smallStrong.copyWith(color: c.textPrimary),
                    children: [
                      TextSpan(
                        text:
                            '  (${dashFigure(context.dashFormats.number(count))})',
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              DashButton(
                label: allSelected
                    ? t('common.deselectAll')
                    : t('common.selectAll'),
                variant: DashButtonVariant.link,
                size: DashButtonSize.compact,
                onPressed: onToggleAll,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.sm + DashMetrics.hair),
          child: Wrap(
            spacing: Space.xs + DashMetrics.hair,
            runSpacing: Space.xs + DashMetrics.hair,
            children: children,
          ),
        ),
      ],
    );
  }
}
