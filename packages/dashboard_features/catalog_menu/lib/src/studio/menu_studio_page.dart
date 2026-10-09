/// `/menu/items/:itemId`: the Menu Studio, ONE scrollable editor for a menu
/// item with a single dirty store and ONE batched save (MENU-STUDIO rows).
/// Web: `features/menu/studio/menu-studio-page.tsx`.
///
/// Save runs in order and stops at the first failing step, whose section the
/// toast names; earlier steps stay saved (each re-baselines its section) and
/// a retry re-runs only what is still dirty:
/// validate → item (+ image) → sizes → each new / changed size's recipe →
/// steps → modifiers → options → refresh + one toast.
///
/// Branch and channel pricing live on `/menu/pricing` (the header links
/// there). "Make it a meal", the base picker, unlinking and a cost fix apply
/// at once, outside the batched save. No realtime (MENU-AREA-009).
library;

import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart'
    show ApiFilePart, OrgIngredient, StudioAggregate, UploadImageMultipart;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/grid_model.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import '../shared/unsaved_bar.dart';
import 'studio_grid.dart';
import 'studio_item_section.dart';
import 'studio_meal.dart';
import 'studio_model.dart';
import 'studio_modifiers.dart';
import 'studio_options.dart';
import 'studio_preview.dart';
import 'studio_providers.dart';
import 'studio_steps.dart';
import 'studio_widgets.dart';

class MenuStudioPage extends ConsumerStatefulWidget {
  const MenuStudioPage({required this.itemId, this.tab, super.key});

  final String itemId;

  /// `?tab=` (old deep links): the section to scroll to once loaded.
  final String? tab;

  @override
  ConsumerState<MenuStudioPage> createState() => _MenuStudioPageState();
}

class _MenuStudioPageState extends ConsumerState<MenuStudioPage> {
  // ── the single dirty store ──────────────────────────────────────────────
  ItemDraft _item = const ItemDraft();
  DashPickedFile? _pendingImage;
  Uint8List? _pendingBytes;
  bool _imageRemoved = false;
  int _imageEpoch = 0;
  List<SizeBlock> _blocks = const [];
  List<AttachDraft> _attached = const [];
  List<OptionRow> _rows = const [];
  List<StepDraft> _steps = const [];
  Pristine _pristine = const Pristine();
  bool _saving = false;

  /// The item the drafts were seeded from (null until the first seed).
  String? _seededFor;
  bool _scrolled = false;
  ProviderSubscription<AsyncValue<StudioAggregate>>? _sub;

  final Map<String, GlobalKey> _sections = {
    for (final s in const ['item', 'sizes', 'steps', 'modifiers', 'options'])
      s: GlobalKey(debugLabel: 'studio-section-$s'),
  };

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(MenuStudioPage old) {
    super.didUpdateWidget(old);
    if (old.itemId != widget.itemId) {
      _scrolled = false;
      _subscribe();
    }
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  void _subscribe() {
    _sub?.close();
    _sub = ref.listenManual<AsyncValue<StudioAggregate>>(
      menuStudioProvider(widget.itemId),
      (prev, next) {
        final s = next.value;
        // A refetch in flight keeps the same aggregate: nothing new to seed.
        if (s == null || identical(prev?.value, s) || !mounted) return;
        setState(() => _seed(s, force: _seededFor != s.id));
        _scrollToTab(s.id);
      },
      fireImmediately: true,
    );
  }

  // ── dirty flags (signature against pristine, per section) ───────────────

  bool get _loaded => _seededFor != null;
  bool get _itemFieldsDirty => _loaded && _item.sig != _pristine.item;
  bool get _imageDirty => _pendingImage != null || _imageRemoved;
  bool get _itemDirty => _loaded && (_itemFieldsDirty || _imageDirty);
  bool get _sizesDirty => _loaded && sizesSig(_blocks) != _pristine.sizes;
  Set<String> get _recipeDirtyKeys =>
      _loaded ? changedSizeKeys(_blocks, _pristine.recipes) : const {};
  bool get _sizesSectionDirty => _sizesDirty || _recipeDirtyKeys.isNotEmpty;
  bool get _stepsDirty => _loaded && stepsSig(_steps) != _pristine.steps;
  bool get _modifiersDirty =>
      _loaded && modifiersSig(_attached) != _pristine.modifiers;
  bool get _optionsDirty => _loaded && optionsSig(_rows) != _pristine.options;

  int get _dirtyCount => [
    _itemDirty,
    _sizesSectionDirty,
    _stepsDirty,
    _modifiersDirty,
    _optionsDirty,
  ].where((d) => d).length;

  /// Seeds the drafts from the aggregate. A background refetch never
  /// clobbers a section with unsaved edits; [force] (a new item, Discard)
  /// re-seeds everything.
  void _seed(StudioAggregate s, {required bool force}) {
    final keepItem = !force && _itemFieldsDirty;
    final keepImage = !force && _imageDirty;
    final keepSizes = !force && _sizesSectionDirty;
    final keepSteps = !force && _stepsDirty;
    final keepModifiers = !force && _modifiersDirty;
    final keepOptions = !force && _optionsDirty;

    final item = toItemDraft(s);
    final blocks = toSizeBlocks(s);
    final steps = toStepDrafts(s);
    final attached = toAttachDrafts(s);
    final rows = toOptionRows(s);

    if (!keepItem) _item = item;
    if (!keepImage) {
      if (_imageDirty) _imageEpoch++;
      _pendingImage = null;
      _pendingBytes = null;
      _imageRemoved = false;
    }
    if (!keepSizes) _blocks = blocks;
    if (!keepSteps) _steps = steps;
    if (!keepModifiers) _attached = attached;
    if (!keepOptions) _rows = rows;
    _pristine = _pristine.copyWith(
      item: keepItem ? null : item.sig,
      sizes: keepSizes ? null : sizesSig(blocks),
      recipes: keepSizes
          ? null
          : {for (final b in blocks) b.key: ownRecipeSig(b.lines)},
      steps: keepSteps ? null : stepsSig(steps),
      modifiers: keepModifiers ? null : modifiersSig(attached),
      options: keepOptions ? null : optionsSig(rows),
    );
    _seededFor = s.id;
  }

  /// Old `?tab=` deep links scroll to their section once per item.
  void _scrollToTab(String itemId) {
    if (_scrolled) return;
    _scrolled = true;
    final section = tabToSection[widget.tab];
    if (section == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _sections[section]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, duration: Duration.zero);
      }
    });
  }

  // ── actions ─────────────────────────────────────────────────────────────

  /// Back (and the pricing link) keep the current search params.
  Uri _keepingQuery(String path) {
    final q = GoRouterState.of(context).uri.queryParameters;
    return Uri(path: path, queryParameters: q.isEmpty ? null : q);
  }

  void _goBack() => context.go(_keepingQuery('/menu/items').toString());

  Future<void> _duplicate() async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('menu.studio.duplicateTitle'),
      description: t('menu.studio.duplicateDesc'),
      confirmLabel: t('menu.grid.duplicate'),
    );
    if (!ok || !mounted) return;
    try {
      final created = await ref
          .read(apiProvider)
          .menu
          .duplicateItem(id: widget.itemId);
      if (!mounted) return;
      DashToast.success(context, t('menu.studio.duplicated'));
      context.go('/menu/items/${created.id}');
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    }
  }

  void _discard() {
    final s = ref.read(menuStudioProvider(widget.itemId)).value;
    if (s != null) setState(() => _seed(s, force: true));
  }

  Future<void> _save() async {
    final s = ref.read(menuStudioProvider(widget.itemId)).value;
    if (s == null || _saving) return;
    final t = ref.read(tProvider);
    final item = _item;
    final blocks = _blocks;
    final steps = _steps;
    final attached = _attached;
    final rows = _rows;

    final problem = validateStudio(
      item: item,
      blocks: blocks,
      steps: steps,
      rows: rows,
    );
    if (problem != null) {
      DashToast.error(context, t(problem.key, args: problem.args));
      return;
    }

    final itemFieldsDirty = _itemFieldsDirty;
    final itemDirty = _itemDirty;
    final imageRemoved = _imageRemoved;
    final pending = _pendingImage;
    final sizesDirty = _sizesDirty;
    final recipeDirty = _recipeDirtyKeys;
    final stepsDirty = _stepsDirty;
    final modifiersDirty = _modifiersDirty;
    final optionsDirty = _optionsDirty;
    final canEditSteps = ref.read(authzProvider).can(Cap.recipesEdit);
    final sourceItemId = s.recipeSourceItemId;
    final api = ref.read(apiProvider);
    // Captured before the first await: the web's refresh runs even when the
    // page is left mid-save.
    final invalidate = ref.menuInvalidate;
    final id = widget.itemId;

    // The rest of the save runs on after the page closes (as the web's does);
    // only what the page shows waits for it to be there.
    void update(VoidCallback fn) {
      if (mounted) setState(fn);
    }

    void fail(String section, Object e) {
      if (!mounted) return;
      DashToast.error(
        context,
        t(
          'menu.studio.saveFailedIn',
          args: {'section': section, 'error': errorMessage(e, t)},
        ),
      );
    }

    setState(() => _saving = true);
    try {
      // 1 · Item details (+ the staged image upload or removal).
      if (itemDirty) {
        try {
          if (itemFieldsDirty || imageRemoved) {
            await api.menu.updateMenuItem(
              id: id,
              body: itemPayload(item, imageRemoved: imageRemoved),
            );
          }
          if (pending != null) {
            await api.uploads.uploadMenuItemImage(
              menuItemId: id,
              body: UploadImageMultipart(
                image: ApiFilePart(
                  field: 'image',
                  filename: pending.name,
                  bytes: pending.bytes,
                  contentType: pending.mimeType,
                ),
              ),
            );
          }
        } on Object catch (e) {
          fail(t('menu.studio.basics.title'), e);
          return;
        }
        update(() {
          _pristine = _pristine.copyWith(item: item.sig);
          if (_imageDirty) _imageEpoch++;
          _pendingImage = null;
          _pendingBytes = null;
          _imageRemoved = false;
        });
      }

      // 2 · Sizes, whenever sizes OR a recipe changed: the aggregate it
      // answers is the only source of a new size's id.
      if (sizesDirty || recipeDirty.isNotEmpty) {
        final StudioAggregate agg;
        try {
          agg = await api.menu.putSizes(id: id, body: sizesPayload(blocks));
        } on Object catch (e) {
          fail(t('menu.studio.sections.sizesTitle'), e);
          return;
        }
        final idByLabel = {for (final z in agg.sizes) z.label: z.id};
        update(() {
          _pristine = _pristine.copyWith(sizes: sizesSig(blocks));
          // New columns adopt their ids, so a retry treats them as saved.
          _blocks = [
            for (final b in _blocks)
              b.id != null ? b : b.copyWith(id: idByLabel[b.label.trim()]),
          ];
        });

        // 3 · Recipes: each new or changed size's own lines.
        for (final b in blocks) {
          if (b.id != null && !recipeDirty.contains(b.key)) continue;
          final sizeId = idByLabel[b.label.trim()];
          if (sizeId == null) continue;
          // A linked copy's recipe belongs to its source (the server 409s).
          if (sourceItemId != null) continue;
          try {
            await api.menu.putSizeRecipe(
              sizeId: sizeId,
              body: recipePayload(b.lines),
            );
          } on Object catch (e) {
            fail(
              t(
                'menu.studio.sectionRecipeFor',
                args: {'label': b.label.trim()},
              ),
              e,
            );
            return;
          }
          update(
            () => _pristine = _pristine.copyWith(
              recipes: {..._pristine.recipes, b.key: ownRecipeSig(b.lines)},
            ),
          );
        }
      }

      // 4 · Steps (part of the recipe: recipes.edit).
      if (stepsDirty && canEditSteps) {
        try {
          await api.recipes.putRecipeSteps(
            menuItemId: id,
            body: stepsPayload(steps),
          );
        } on Object catch (e) {
          fail(t('menu.studio.sectionSteps'), e);
          return;
        }
        update(() => _pristine = _pristine.copyWith(steps: stepsSig(steps)));
      }

      // 5 · Modifier attachments.
      if (modifiersDirty) {
        try {
          await api.menu.putModifierGroups(
            id: id,
            body: modifiersPayload(attached),
          );
        } on Object catch (e) {
          fail(t('menu.studio.tabs.modifiers'), e);
          return;
        }
        update(
          () => _pristine = _pristine.copyWith(
            modifiers: modifiersSig(attached),
          ),
        );
      }

      // 6 · Item-only options.
      if (optionsDirty) {
        try {
          await api.menu.putItemOptions(id: id, body: optionsPayload(rows));
        } on Object catch (e) {
          fail(t('menu.studio.tabs.options'), e);
          return;
        }
        update(
          () => _pristine = _pristine.copyWith(options: optionsSig(rows)),
        );
      }

      // 7 · Refresh + one toast; the refetch re-baselines every section.
      invalidate
        ..studio(id)
        ..catalog();
      if (mounted) DashToast.success(context, t('common.savedChanges'));
    } finally {
      update(() => _saving = false);
    }
  }

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final q = ref.watch(menuStudioProvider(widget.itemId));
    final studio = q.value;

    if (studio == null && !q.hasError) {
      return DashPageScaffold(
        title: '',
        subtitleWidget: const DashSkeleton(
          key: ValueKey('studio-title-skeleton'),
          width: StudioMetrics.titleSkeleton,
          height: Space.xl + Space.xs,
        ),
        width: DashPageWidth.reading,
        onBack: _goBack,
        body: const StudioLoadingSkeleton(),
      );
    }
    if (studio == null) {
      return DashPageScaffold(
        title: t('menu.studio.itemTitle'),
        width: DashPageWidth.reading,
        onBack: _goBack,
        body: DashErrorState(
          title: t('menu.studio.loadError'),
          message: errorMessage(q.error, t),
          retryLabel: t('common.retry'),
          retrying: q.isLoading,
          onRetry: () => ref.invalidate(menuStudioProvider(widget.itemId)),
        ),
      );
    }

    final lang = ref.watch(localeProvider);
    final orgId = ref.watch(orgIdProvider);
    final authz = ref.watch(authzProvider);
    final canPreview = authz.can(Cap.menuItemsRead);
    final canEditSteps = authz.can(Cap.recipesEdit);
    final catalog = orgId == null
        ? const <OrgIngredient>[]
        : ref.watch(ingredientCatalogProvider(orgId)).value ??
              const <OrgIngredient>[];
    final name = translatedName(studio.name, studio.nameTranslations, lang);
    final serverImage = studioImageUrl(studio);
    final hasRemovable =
        _pendingImage != null || (serverImage != null && !_imageRemoved);

    final dirtyCount = _dirtyCount;
    final sections = <Widget>[
      StudioSection(
        key: _sections['item'],
        first: true,
        title: t('menu.studio.basics.title'),
        description: t('menu.studio.basics.desc'),
        dirty: _itemDirty,
        child: StudioItemSection(
          orgId: orgId,
          item: _item,
          onChanged: (v) => setState(() => _item = v),
          imageUrl: _imageRemoved ? null : serverImage,
          processing: !_imageRemoved && studioImageProcessing(studio),
          pendingBytes: _pendingBytes,
          uploaderKey: ValueKey('studio-image-$_imageEpoch'),
          onPickImage: (f) => setState(() {
            _pendingImage = f;
            _pendingBytes = f.bytes;
            _imageRemoved = false;
          }),
          onRemoveImage: hasRemovable
              ? () => setState(() {
                  if (_pendingImage != null) {
                    _pendingImage = null;
                    _pendingBytes = null;
                  } else {
                    _imageRemoved = true;
                  }
                  _imageEpoch++;
                })
              : null,
        ),
      ),
      StudioSection(
        key: _sections['sizes'],
        title: t('menu.studio.sections.sizesTitle'),
        description: t('menu.studio.sections.sizesDesc'),
        dirty: _sizesSectionDirty,
        child: StudioSizesSection(
          itemId: widget.itemId,
          orgId: orgId,
          studio: studio,
          blocks: _blocks,
          recipeDirtyKeys: _recipeDirtyKeys,
          catalog: catalog,
          sizesSectionDirty: _sizesSectionDirty,
          onChanged: (v) => setState(() => _blocks = v),
        ),
      ),
      StudioSection(
        key: _sections['steps'],
        title: t('menu.studio.sections.stepsTitle'),
        description: t('menu.studio.sections.stepsDesc'),
        dirty: _stepsDirty,
        child: StudioStepsSection(
          steps: _steps,
          readOnly: !canEditSteps,
          onChanged: (v) => setState(() => _steps = v),
        ),
      ),
      StudioSection(
        key: _sections['modifiers'],
        title: t('menu.studio.tabs.modifiers'),
        description: t('menu.studio.modifiers.desc'),
        dirty: _modifiersDirty,
        child: StudioModifiersSection(
          orgId: orgId,
          itemId: widget.itemId,
          attached: _attached,
          onChanged: (v) => setState(() => _attached = v),
        ),
      ),
      StudioSection(
        key: _sections['options'],
        title: t('menu.studio.tabs.options'),
        description: t('menu.studio.options.desc'),
        dirty: _optionsDirty,
        child: StudioOptionsSection(
          rows: _rows,
          catalog: catalog,
          onChanged: (v) => setState(() => _rows = v),
        ),
      ),
      StudioSection(
        title: t('combos.meal.title'),
        description: t('combos.meal.desc'),
        dirty: false,
        child: StudioMealSection(
          itemId: widget.itemId,
          categoryId: studio.categoryId,
        ),
      ),
      if (canPreview)
        StudioSection(
          title: t('modeling.preview.title'),
          description: t('modeling.preview.desc'),
          dirty: false,
          child: StudioPreviewPanel(studio: studio),
        ),
    ];

    return MenuUnsavedBarHost(
      bar: dirtyCount == 0
          ? null
          : MenuUnsavedBar(
              key: const ValueKey('studio-save-bar'),
              countText: t('menu.studio.unsavedN', count: dirtyCount),
              discardLabel: t('menu.studio.discard'),
              saveLabel: t('common.save'),
              saving: _saving,
              onDiscard: _discard,
              onSave: _save,
            ),
      child: DashPageScaffold(
        title: name.isEmpty ? t('menu.studio.untitled') : name,
        subtitleWidget: studio.isActive
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Wrap(
                  children: [
                    DashStatusPill(label: t('common.inactive'), small: true),
                  ],
                ),
              ),
        width: DashPageWidth.reading,
        onBack: _goBack,
        actions: [
          DashButton(
            label: t('menu.studio.pricingLink'),
            variant: DashButtonVariant.ghost,
            size: DashButtonSize.compact,
            trailingIcon: DashIcon.arrowForward(context),
            onPressed: () =>
                context.go(_keepingQuery('/menu/pricing').toString()),
          ),
          DashButton(
            label: t('menu.grid.duplicate'),
            icon: 'copy',
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            onPressed: _duplicate,
          ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, s) in sections.indexed) ...[
              if (i > 0) const StudioDivider(),
              s,
            ],
            // Room under the last section for the floating save bar.
            const SizedBox(height: StudioMetrics.saveBarRoom),
          ],
        ),
      ),
    );
  }
}
