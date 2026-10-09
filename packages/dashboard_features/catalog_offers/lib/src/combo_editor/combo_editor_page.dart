/// `/menu/combos/:comboId`: the combo editor (the web's
/// `combo-editor-page.tsx`, inventory OFFR-CED rows); `new` creates one.
///
/// One page, one Save (`POST /combos` or `PUT /combos/{id}`), the picked
/// image uploaded after it:
/// - General: image, names, price, category, descriptions, on/off;
/// - Slots: what the customer picks, with extras and size rules;
/// - Availability: optional windows (days, hours, dates, a branch);
/// - Branches and channels: links to where those live;
/// - Price check: live economics whose warnings never block a Save.
///
/// Without `menu.combos.edit` the page is read-only: every control
/// disabled, no Save, no Delete. The form is seeded once per combo: a
/// background refetch never overwrites what is being typed.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, ApiFilePart, Combo, UploadImageMultipart;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashRoutePrefetch;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../combos/combos_providers.dart' show warmCombosList;
import '../shared/menu_options.dart';
import '../shared/offers_cache.dart';
import '../shared/offers_page_gate.dart';
import '../shared/windows_editor.dart';
import 'combo_editor_providers.dart';
import 'combo_form.dart';
import 'economics_panel.dart';
import 'editor_parts.dart';
import 'slots_editor.dart';

class ComboEditorPage extends ConsumerWidget {
  const ComboEditorPage({required this.comboId, super.key});

  /// The combo's id, or `new`.
  final String comboId;

  bool get isNew => comboId == 'new';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return OffersPageGate(
      title: isNew ? t('combos.new') : t('combos.title'),
      caps: const [Cap.menuItemsRead],
      loading: const _EditorSkeleton(),
      // A new combo (after "Create combo" the URL names it) starts afresh.
      child: _ComboEditor(key: ValueKey(comboId), comboId: comboId),
    );
  }
}

/// The list the editor's Back, Delete and link rows lead to.
const String _listPath = '/menu/combos';

/// The editor while the rights or the combo load.
class _EditorSkeleton extends ConsumerWidget {
  const _EditorSkeleton();

  /// The title skeleton (`w-56`).
  static const double _titleWidth = Space.xxl * 7;

  /// The loading blocks (`h-44`, `h-72`).
  static const double _top = Space.xxl * 5 + Space.lg;
  static const double _bottom = Space.xxl * 9;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DashPageScaffold(
    title: '',
    onBack: () => context.go(_listPath),
    onBackIntent: () => warmCombosList(ref),
    subtitleWidget: const DashSkeleton(
      width: _titleWidth,
      height: Space.xl + Space.xs,
    ),
    body: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        DashSkeleton(height: _top, radius: Radii.sheet),
        DashSkeleton(height: _bottom, radius: Radii.sheet),
      ],
    ),
  );
}

class _ComboEditor extends ConsumerStatefulWidget {
  const _ComboEditor({required this.comboId, super.key});

  final String comboId;

  @override
  ConsumerState<_ComboEditor> createState() => _ComboEditorState();
}

class _ComboEditorState extends ConsumerState<_ComboEditor> {
  bool get _isNew => widget.comboId == 'new';

  late ComboDraft _v = ComboDraft.empty();

  /// What "unsaved" is measured against (the loaded or saved combo).
  late ComboDraft _base = _v;
  String? _seededFor;

  /// The loaded combo the form last looked at (a refresh is a new one).
  Combo? _seen;

  /// The picked image, uploaded after the next Save.
  DashPickedFile? _pending;

  /// Bumped to clear the uploader's own preview (after Save or Discard).
  int _imageGen = 0;

  /// Save was pressed: from now on every change re-checks the form.
  bool _submitted = false;
  bool _saving = false;

  /// The price check's body, 450 ms behind the form.
  Map<String, Object?>? _econBody;
  Timer? _econTimer;

  @override
  void dispose() {
    _econTimer?.cancel();
    super.dispose();
  }

  void _seed(Combo c) {
    _v = _base = ComboDraft.fromWire(c);
    _pending = null;
    _seededFor = c.id;
    _econBody = _v.economicsBody();
  }

  void _set(ComboDraft next) {
    setState(() => _v = next);
    _econTimer?.cancel();
    _econTimer = Timer(_econDelay, () {
      if (mounted) setState(() => _econBody = _v.economicsBody());
    });
  }

  bool get _canEdit => ref.read(authzProvider).can(Cap.menuCombosEdit);

  /// Nothing typed and no image picked since the form was seeded.
  bool get _untouched =>
      _pending == null && _v.fingerprint() == _base.fingerprint();

  /// Where a save's toasts go: the shell's navigator, which outlives this
  /// page, so a save finished after leaving still says how it went.
  BuildContext _toastContext() => Navigator.of(context).context;

  void _goBack() => context.go(_listPath);

  Future<DashPickedFile?> _pickImage() async {
    final f = await ref.read(fileGatewayProvider).pickImage();
    if (f == null) return null;
    return DashPickedFile(
      bytes: Uint8List.fromList(f.bytes),
      name: f.name,
      mimeType: f.mimeType ?? _mimeOf(f.name),
    );
  }

  Future<void> _submit() async {
    if (!_canEdit || _saving) return;
    // Save is disabled on an existing combo with nothing changed.
    if (!_isNew && _untouched) return;
    final t = ref.read(tProvider);
    setState(() => _submitted = true);
    if (!validateCombo(_v).isEmpty) {
      // Say it, and take the owner to it: a Save that silently does
      // nothing is the worst outcome.
      DashToast.error(context, t('combos.fixErrors'));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) scrollToFirstInvalid(context);
      });
      return;
    }
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    final router = GoRouter.of(context);
    final toast = _toastContext();
    final v = _v;
    final pending = _pending;
    final isNew = _isNew;
    setState(() => _saving = true);
    try {
      final saved = isNew
          ? await api.menu.createCombo(body: v.toWire())
          : await api.menu.updateCombo(id: widget.comboId, body: v.toWire());
      if (pending != null) {
        try {
          await api.uploads.uploadMenuItemImage(
            menuItemId: saved.id,
            body: UploadImageMultipart(
              image: ApiFilePart(
                field: 'image',
                filename: pending.name,
                bytes: pending.bytes,
                contentType: pending.mimeType,
              ),
            ),
          );
        } on Object catch (e) {
          if (toast.mounted) {
            DashToast.error(
              toast,
              t('combos.imageFailed', args: {'error': errorMessage(e, t)}),
            );
          }
        }
      }
      if (mounted) {
        setState(() {
          _seed(saved);
          // The refresh this save triggers brings the same combo back.
          if (!isNew) _seen = ref.read(comboProvider(widget.comboId)).value;
          _imageGen++;
          _submitted = false;
        });
      }
      if (toast.mounted) {
        DashToast.success(
          toast,
          isNew ? t('combos.created') : t('common.savedChanges'),
        );
      }
      // The web's query client refetches even if the page is gone.
      bus.invalidate(combosInvalidationPrefixes);
      if (isNew && mounted) router.go('$_listPath/${saved.id}');
    } on Object catch (e) {
      if (toast.mounted) DashToast.error(toast, _saveErrorText(e, v, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discard(Combo? loaded) {
    if (loaded == null) return;
    _econTimer?.cancel();
    setState(() {
      _seed(loaded);
      _imageGen++;
      _submitted = false;
    });
  }

  Future<void> _remove() async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('combos.deleteTitle', args: {'name': _v.name}),
      description: t('combos.deleteBody'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    final toast = _toastContext();
    try {
      await api.menu.deleteMenuItem(id: widget.comboId);
      // The web's query client refetches even if the page is gone.
      bus.invalidate(combosInvalidationPrefixes);
      if (toast.mounted) DashToast.success(toast, t('combos.deleted'));
      if (!mounted) return;
      setState(() => _base = _v);
      _goBack();
    } on Object catch (e) {
      if (toast.mounted) DashToast.error(toast, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final canEdit = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuCombosEdit)),
    );
    final branchId = ref.watch(currentScopeProvider.select((s) => s.branchId));
    final menu = ref.watch(menuOptionsProvider);

    Combo? loaded;
    if (!_isNew) {
      final q = ref.watch(comboProvider(widget.comboId));
      loaded = q.value;
      // The web's `isError || !data`: a failed refresh replaces the form
      // too; the error stays, its Retry spinning, until the answer lands.
      final failed = q.hasError && !q.retrying;
      if (q.awaitingFirst) {
        return const _EditorSkeleton();
      }
      if (failed || loaded == null) {
        return DashPageScaffold(
          title: t('combos.title'),
          onBack: _goBack,
          onBackIntent: () => warmCombosList(ref),
          body: DashErrorState(
            title: t('combos.loadError'),
            message: failed ? errorMessage(q.error, t) : null,
            retryLabel: t('common.retry'),
            retrying: q.isLoading,
            onRetry: () => ref.invalidate(comboProvider(widget.comboId)),
          ),
        );
      }
      if (_seededFor != loaded.id) {
        _seed(loaded);
        _seen = loaded;
      } else if (!identical(loaded, _seen)) {
        // A refresh landed: an untouched form follows it (equal data never
        // re-seeds); anything typed is kept.
        _seen = loaded;
        if (_untouched &&
            ComboDraft.fromWire(loaded).fingerprint() != _base.fingerprint()) {
          _seed(loaded);
        }
      }
    }

    final v = _v;
    final e = _submitted ? validateCombo(v) : const ComboErrors();
    final ro = !canEdit;
    final dirty = _pending != null || v.fingerprint() != _base.fingerprint();
    final c = context.madarColors;

    final title = v.name.trim().isNotEmpty
        ? v.name.trim()
        : (_isNew ? t('combos.new') : t('combos.untitled'));
    final pills = Padding(
      padding: const EdgeInsetsDirectional.only(top: Space.xs),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.xs,
        children: [
          DashStatusPill(
            label: isFixedDraft(v.slots)
                ? t('combos.fixedBundle')
                : t('combos.mealDeal'),
            tone: DashTone.info,
            small: true,
          ),
          if (!v.isActive)
            DashStatusPill(label: t('common.inactive'), small: true),
          if (ro) DashStatusPill(label: t('combos.readOnly'), small: true),
        ],
      ),
    );

    void onSubmit() => unawaited(_submit());

    Widget input({
      required String label,
      required String value,
      required ValueChanged<String> onChanged,
      String? error,
      String? hint,
      bool rtl = false,
      bool money = false,
      bool area = false,
    }) => LabelledField(
      label: label,
      error: error == null ? null : t(error),
      hint: hint,
      child: DashTextInput(
        value: value,
        onChanged: onChanged,
        semanticLabel: label,
        invalid: error != null,
        enabled: canEdit,
        textDirection: rtl
            ? TextDirection.rtl
            : (money ? TextDirection.ltr : null),
        keyboardType: money
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        mono: money,
        maxLines: area ? null : 1,
        minLines: area ? 2 : null,
        textInputAction: area ? null : TextInputAction.done,
        onSubmitted: area ? null : (_) => onSubmit(),
      ),
    );

    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.lg,
      children: [
        FieldGrid(
          children: [
            input(
              label: t('combos.name'),
              value: v.name,
              error: e.name,
              onChanged: (s) => _set(_v.copyWith(name: s)),
            ),
            input(
              label: t('combos.nameAr'),
              value: v.nameAr,
              rtl: true,
              onChanged: (s) => _set(_v.copyWith(nameAr: s)),
            ),
          ],
        ),
        FieldGrid(
          children: [
            input(
              label: t('combos.price'),
              value: v.price,
              error: e.price,
              hint: t('combos.priceHint'),
              money: true,
              onChanged: (s) => _set(_v.copyWith(price: s)),
            ),
            LabelledField(
              label: t('combos.col.category'),
              hint: t('combos.categoryHint'),
              child: DashSelect<String>(
                options: [
                  DashOption(value: '', label: t('combos.noCategory')),
                  for (final cat in menu.categories)
                    DashOption(value: cat.id, label: cat.name),
                ],
                value: v.categoryId,
                onChanged: (id) => _set(_v.copyWith(categoryId: id)),
                semanticLabel: t('combos.col.category'),
                enabled: canEdit,
              ),
            ),
          ],
        ),
        FieldGrid(
          children: [
            input(
              label: t('combos.description'),
              value: v.description,
              area: true,
              onChanged: (s) => _set(_v.copyWith(description: s)),
            ),
            input(
              label: t('combos.descriptionAr'),
              value: v.descriptionAr,
              area: true,
              rtl: true,
              onChanged: (s) => _set(_v.copyWith(descriptionAr: s)),
            ),
          ],
        ),
        _Boxed(
          child: Row(
            spacing: Space.lg,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t('combos.active'),
                      style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                    ),
                    HintLine(t('combos.activeHint')),
                  ],
                ),
              ),
              DashSwitch(
                value: v.isActive,
                semanticLabel: t('combos.active'),
                enabled: canEdit,
                onChanged: (on) => _set(_v.copyWith(isActive: on)),
              ),
            ],
          ),
        ),
      ],
    );

    final image = DashImageUploader(
      key: ValueKey('combo-image-$_imageGen'),
      value: loaded?.imageUrl,
      hint: t('menu.imageHint'),
      enabled: canEdit,
      onPick: _pickImage,
      onUpload: (file) async {
        setState(() => _pending = file);
        return null;
      },
      onRemove: _pending == null
          ? null
          : () async => setState(() => _pending = null),
    );

    final general = _Section(
      title: t('combos.sections.general'),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= _imageBesideWidth
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.xl,
                children: [
                  image,
                  Expanded(child: fields),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xl,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: image,
                  ),
                  fields,
                ],
              ),
      ),
    );

    final slots = _Section(
      title: t('combos.sections.slots'),
      description: t('combos.sections.slotsDesc'),
      child: SlotsEditor(
        value: v.slots,
        onChanged: (s) => _set(_v.copyWith(slots: s)),
        menu: menu,
        errors: e,
        enabled: canEdit,
        onSubmit: onSubmit,
      ),
    );

    final availability = _Section(
      title: t('combos.sections.availability'),
      description: t('combos.sections.availabilityDesc'),
      child: InvalidOr(
        invalid: e.windows.any((w) => w != null && !w.isEmpty),
        child: WindowsEditor(
          value: v.windows,
          onChanged: (w) => _set(_v.copyWith(windows: w)),
          branches: [for (final b in menu.branches) (id: b.id, name: b.name)],
          errors: e.windows,
          enabled: canEdit,
        ),
      ),
    );

    final branches = _Section(
      title: t('combos.sections.branches'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          _LinkRow(
            label: t('combos.branches.pricing'),
            hint: t('combos.branches.pricingHint'),
            to: '/menu/pricing',
          ),
          _LinkRow(
            label: t('combos.branches.channels'),
            hint: t('combos.branches.channelsHint'),
            to: '/settings/combos',
          ),
        ],
      ),
    );

    final econBody = _econBody;
    final priceCheck = ComboPriceCheck(
      requestKey: econBody == null
          ? null
          : comboEconomicsKey(econBody, branchId),
      branchLabel: branchId == null
          ? t('combos.econ.orgPrices')
          : (menu.branchName(branchId) ?? '—'),
      itemName: menu.itemName,
      slotName: (id) {
        for (final s in v.slots) {
          if (s.id == id && s.name.isNotEmpty) return s.name;
        }
        return null;
      },
    );

    final sections = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xl,
      children: [general, slots, availability, branches],
    );
    // Room for the floating save bar (`pb-24`).
    const barRoom = SizedBox(height: Space.xxl * 3);
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;
    final body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xl,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [sections, barRoom],
                  ),
                ),
              ),
              // The price check stays in view while the form scrolls.
              SizedBox(
                width: _asideWidth,
                child: SingleChildScrollView(child: priceCheck),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xl,
            children: [sections, priceCheck, barRoom],
          );

    final page = DashPageScaffold(
      title: title,
      subtitleWidget: pills,
      onBack: _goBack,
      onBackIntent: () => warmCombosList(ref),
      fillBody: wide,
      actions: [
        if (!_isNew && canEdit)
          DashButton(
            label: t('common.delete'),
            icon: 'trash-2',
            variant: DashButtonVariant.outlineDanger,
            size: DashButtonSize.compact,
            onPressed: () => unawaited(_remove()),
          ),
      ],
      body: body,
    );

    if (!canEdit) return page;
    return Stack(
      children: [
        Positioned.fill(child: page),
        PositionedDirectional(
          start: Space.lg,
          end: Space.lg,
          bottom: Space.lg,
          child: Center(
            child: _SaveBar(
              status: dirty
                  ? t('combos.unsaved')
                  : (_isNew ? t('combos.notSavedYet') : t('combos.allSaved')),
              discardLabel: dirty && !_isNew ? t('combos.discard') : null,
              onDiscard: _saving ? null : () => _discard(loaded),
              saveLabel: _isNew ? t('combos.create') : t('common.save'),
              saving: _saving,
              onSave: _saving || (!dirty && !_isNew) ? null : onSubmit,
            ),
          ),
        ),
      ],
    );
  }

  /// The price check's column (`20rem`).
  static const double _asideWidth = 320;

  /// The image sits beside the fields from this column width.
  static const double _imageBesideWidth = 640;

  /// The price check asks this long after the form stops changing.
  static const Duration _econDelay = Duration(milliseconds: 450);
}

/// A refused Save in the page's words: `COMBO_SLOT_INVALID {slot_index}`
/// names the slot from the form; anything else is the server's.
String _saveErrorText(Object e, ComboDraft v, Translator t) {
  if (e is ApiException && e.code == 'COMBO_SLOT_INVALID') {
    final details = e.details;
    final vars = details is Map ? details['vars'] : null;
    final idx = vars is Map ? vars['slot_index'] : null;
    if (idx is int) {
      final name = idx >= 0 && idx < v.slots.length ? v.slots[idx].name : '';
      return t(
        'errors.codes.COMBO_SLOT_INVALID',
        args: {
          'slot': name.isNotEmpty
              ? name
              : t('combos.slots.slotN', args: {'n': idx + 1}),
        },
      );
    }
  }
  return errorMessage(e, t);
}

String _mimeOf(String name) => switch (name.split('.').last.toLowerCase()) {
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  'webp' => 'image/webp',
  'gif' => 'image/gif',
  _ => 'application/octet-stream',
};

/// A section: its heading, an optional description, its body.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.description});

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.lg,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: DashMetrics.hair,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: DashType.sectionTitle.copyWith(color: c.textPrimary),
              ),
            ),
            if (description != null)
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DashMetrics.proseWide,
                ),
                child: Text(
                  description!,
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
              ),
          ],
        ),
        child,
      ],
    );
  }
}

/// A bordered box (`rounded-xl border p-3`).
class _Boxed extends StatelessWidget {
  const _Boxed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Radii.card),
      border: Border.all(color: context.madarColors.hairline),
    ),
    child: Padding(
      padding: const EdgeInsetsDirectional.all(Space.md),
      child: child,
    ),
  );
}

/// A row that leads to another page: its name, a quiet line, an arrow.
class _LinkRow extends ConsumerWidget {
  const _LinkRow({required this.label, required this.hint, required this.to});

  final String label;
  final String hint;

  /// The page it opens, warmed on intent.
  final String to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    return DashPressable(
      onTap: () => context.go(to),
      onIntent: () => ref.prefetchRoute(to),
      semanticLabel: '$label, $hint',
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) {
        final radius = BorderRadius.circular(Radii.card);
        return Container(
          foregroundDecoration: dashFocusRing(context, s, radius),
          decoration: BoxDecoration(
            color: s.highlighted ? c.hover : null,
            borderRadius: radius,
            border: Border.all(color: c.hairline),
          ),
          padding: const EdgeInsetsDirectional.all(Space.md),
          child: Row(
            spacing: Space.md,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                    ),
                    HintLine(hint),
                  ],
                ),
              ),
              DashIcon(DashIcon.arrowForward(context), color: c.textSecondary),
            ],
          ),
        );
      },
    );
  }
}

/// The floating pill at the foot of the page: the form's state, Discard
/// (an existing combo with changes) and Save.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.status,
    required this.discardLabel,
    required this.onDiscard,
    required this.saveLabel,
    required this.saving,
    required this.onSave,
  });

  final String status;
  final String? discardLabel;
  final VoidCallback? onDiscard;
  final String saveLabel;
  final bool saving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.lg,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.hairline),
        boxShadow: DashShadows.popover(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          Flexible(
            child: Semantics(
              liveRegion: true,
              child: MadarClippedText(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
            ),
          ),
          if (discardLabel != null)
            DashButton(
              label: discardLabel!,
              variant: DashButtonVariant.ghost,
              size: DashButtonSize.compact,
              onPressed: onDiscard,
            ),
          DashButton(
            label: saveLabel,
            size: DashButtonSize.compact,
            loading: saving,
            onPressed: onSave,
          ),
        ],
      ),
    );
  }
}
