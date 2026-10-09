/// `/settings/links` Links page editor (`features/links/admin/
/// links-pane.tsx`, SET-LNK-001..026): the shop's own address, the line
/// under its name, the buttons and their order, its own links, the socials
/// (one map with Brand), "Visit us", and beside it the public page as saved.
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane. No client gate: the reads 403 into
/// the error state; module `pos` at the route.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show LinksItemKind, LinksModuleStatus, LinksPageItem, LinksPageSettings;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show linkOpenerProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/qr_preview_dialog.dart';
import '../shared/social_links.dart';
import 'links_data.dart';
import 'links_preview.dart';
import 'links_providers.dart';

/// The pane's fixed sizes.
abstract final class LinksMetrics {
  /// `xl:`: the preview sits beside the form from here.
  static const double besideFrom = 1280;

  /// `400px`: the preview column; `h-[720px]`: its frame.
  static const double preview = 400;
  static const double frame = 720;
  static const double frameBorder = 6;
  static const double frameRadius = 28;

  /// The loading bars (`h-8 w-48`, `h-40`, `h-64`).
  static const double titleBarWidth = 192;
  static const double cardBar = 160;
  static const double tallBar = 256;
}

class LinksPage extends ConsumerWidget {
  const LinksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    if (orgId == null) {
      return DashPageScaffold(
        title: t('links.editor.title'),
        subtitle: t('links.editor.desc'),
        width: DashPageWidth.reading,
        body: DashEmptyState(icon: 'link-2', title: t('branches.pickOrg')),
      );
    }
    final q = ref.watch(linksPageProvider(orgId));
    if (q.awaitingFirst) return const _LinksSkeleton();
    if (q.failedFirst) {
      return DashPageScaffold(
        title: t('links.editor.title'),
        subtitle: t('links.editor.desc'),
        width: DashPageWidth.reading,
        body: DashErrorState(
          title: t('common.loadFailed'),
          message: errorMessage(q.error, t),
          retryLabel: t('common.retry'),
          retrying: q.isLoading,
          onRetry: () => ref.invalidate(linksPageProvider(orgId)),
        ),
      );
    }
    // Keyed by org: another org's page starts a fresh draft (SET-LNK-024).
    return LinksEditor(
      key: ValueKey(orgId),
      orgId: orgId,
      saved: q.requireValue,
    );
  }
}

/// The loading state (the web shows only these bars, no header).
class _LinksSkeleton extends ConsumerWidget {
  const _LinksSkeleton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    key: const ValueKey('links-loading'),
    label: ref.watch(tProvider)('common.loading'),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DashSkeleton(
            width: LinksMetrics.titleBarWidth,
            height: Space.xxl,
          ),
        ),
        DashSkeleton(height: LinksMetrics.cardBar, radius: Radii.card),
        DashSkeleton(height: LinksMetrics.tallBar, radius: Radii.card),
      ],
    ),
  );
}

class LinksEditor extends ConsumerStatefulWidget {
  const LinksEditor({required this.orgId, required this.saved, super.key});

  final String orgId;
  final LinksPageSettings saved;

  @override
  ConsumerState<LinksEditor> createState() => _LinksEditorState();
}

class _LinksEditorState extends ConsumerState<LinksEditor> {
  static const _eq = DeepCollectionEquality();

  final _form = GlobalKey<FormState>();
  late List<LinksPageItem> _items;
  late List<LinksBranchDraft> _branches;
  late String _taglineEn;
  late String _taglineAr;
  late bool _showCover;
  late bool _showBranches;
  late Map<String, String> _social;
  bool _edited = false;
  bool _busy = false;
  bool _qrBusy = false;

  /// Bumped after a save so the preview starts over on the new page.
  int _previewKey = 0;

  @override
  void initState() {
    super.initState();
    _seed(widget.saved);
  }

  void _seed(LinksPageSettings s) {
    _items = s.items;
    _branches = s.branches.map(LinksBranchDraft.of).toList();
    _taglineEn = s.taglineEn ?? '';
    _taglineAr = s.taglineAr ?? '';
    _showCover = s.showCover;
    _showBranches = s.showBranches;
    _social = socialLinksToForm(s.socialLinks);
  }

  List<Object?> _json(List<LinksPageItem> items) =>
      items.map((i) => i.toJson()).toList();

  @override
  void didUpdateWidget(LinksEditor old) {
    super.didUpdateWidget(old);
    final now = widget.saved;
    if (_eq.equals(now.toJson(), old.saved.toJson())) return;
    if (!_edited) {
      _seed(now);
    } else if (!_eq.equals(_json(now.items), _json(old.saved.items))) {
      // The server minted ids for new links: keep the draft in step so a
      // second save does not duplicate them (the web's effect on items).
      _items = now.items;
    }
  }

  void _edit(VoidCallback change) => setState(() {
    _edited = true;
    change();
  });

  Map<LinksItemKind, LinksModuleStatus> get _modules => {
    for (final m in widget.saved.modules) m.kind: m,
  };

  void _move(int i, int by) => _edit(() {
    final j = i + by;
    if (j < 0 || j >= _items.length) return;
    final next = [..._items];
    final a = next[i];
    next[i] = next[j];
    next[j] = a;
    _items = next;
  });

  void _patch(int i, LinksPageItem next) =>
      _edit(() => _items = [..._items]..[i] = next);

  Future<void> _save() async {
    if (_busy) return;
    final t = ref.read(tProvider);
    if (!(_form.currentState?.validate() ?? false)) return;
    if (linksCustomProblem(_items) || linksMapsProblem(_branches)) {
      DashToast.error(context, t('links.editor.fixLinks'));
      return;
    }
    final api = ref.read(apiProvider).orgs;
    final bus = ref.read(realtimeBusProvider);
    final orgId = widget.orgId;
    final body = linksSaveBody(
      items: _items,
      taglineEn: _taglineEn,
      taglineAr: _taglineAr,
      showCover: _showCover,
      showBranches: _showBranches,
      branches: _branches,
      social: _social,
      savedSocial: widget.saved.socialLinks,
    );
    setState(() => _busy = true);
    try {
      await api.putLinksPage(id: orgId, body: body);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        DashToast.error(context, errorMessage(e, t));
      }
      return;
    }
    // Unconditional: the re-read happens even if the pane closed mid-save.
    bus.invalidate(linksSavedPaths(orgId));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _edited = false;
      _previewKey++;
    });
    DashToast.success(context, t('links.editor.saved'));
  }

  Future<void> _copy(String url) async {
    final t = ref.read(tProvider);
    try {
      await Clipboard.setData(ClipboardData(text: url));
    } on Object {
      return; // The web says nothing when the clipboard refuses.
    }
    if (mounted) DashToast.success(context, t('links.editor.copied'));
  }

  Future<void> _showQr() async {
    final t = ref.read(tProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final read = linksQrProvider(widget.orgId);
    setState(() => _qrBusy = true);
    try {
      final qr = await container.read(read.future);
      if (mounted) {
        unawaited(
          showQrPreview(context, qr: qr, title: t('links.editor.qrTitle')),
        );
      }
    } on Object catch (e) {
      container.invalidate(read);
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _qrBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final viewport = MediaQuery.sizeOf(context).width;
    final form = Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          _addressCard(t),
          _aboutCard(t),
          _buttonsCard(t),
          DashCard(
            key: const ValueKey('links-socials'),
            padding: const EdgeInsets.all(Space.lg),
            child: SocialLinksFields(
              values: _social,
              onChanged: (p, v) => _edit(() => _social = {..._social, p: v}),
              onSubmitted: _save,
            ),
          ),
          _visitCard(t),
        ],
      ),
    );
    final preview = _Preview(
      key: ValueKey('links-preview-$_previewKey'),
      orgId: widget.orgId,
    );
    return DashPageScaffold(
      title: t('links.editor.title'),
      subtitle: t('links.editor.desc'),
      width: DashPageWidth.reading,
      actions: [
        DashButton(
          key: const ValueKey('links-save'),
          label: t('common.save'),
          loading: _busy,
          onPressed: _busy ? null : _save,
        ),
      ],
      body: viewport >= LinksMetrics.besideFrom
          ? _StickyBeside(main: form, aside: preview)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xl,
              children: [form, preview],
            ),
    );
  }

  Widget _input({
    required String value,
    required ValueChanged<String> onChanged,
    required TextDirection direction,
    String? placeholder,
    String? label,
    int? maxLength,
    bool url = false,
    bool invalid = false,
    bool enabled = true,
    Key? key,
  }) => DashTextInput(
    key: key,
    value: value,
    onChanged: onChanged,
    placeholder: placeholder,
    semanticLabel: label ?? placeholder,
    maxLength: maxLength,
    textDirection: direction,
    keyboardType: url ? TextInputType.url : null,
    invalid: invalid,
    enabled: enabled,
    onSubmitted: (_) => _save(),
  );

  Widget _addressCard(Translator t) {
    final c = context.madarColors;
    final url = widget.saved.publicUrl;
    return _Card(
      key: const ValueKey('links-address'),
      title: t('links.editor.address'),
      hint: t('links.editor.addressHint'),
      children: [
        if (url != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm + DashMetrics.hair,
            ),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.xs),
              border: Border.all(color: c.border),
            ),
            child: Text(
              url,
              textDirection: TextDirection.ltr,
              style: MadarType.num.copyWith(
                fontWeight: FontWeight.w400,
                color: c.textPrimary,
              ),
            ),
          ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              DashButton(
                key: const ValueKey('links-copy'),
                label: t('links.editor.copy'),
                icon: 'copy',
                variant: DashButtonVariant.outline,
                onPressed: () => _copy(url),
              ),
              DashButton(
                key: const ValueKey('links-qr'),
                label: t('links.editor.qr'),
                icon: 'qr-code',
                variant: DashButtonVariant.outline,
                loading: _qrBusy,
                onPressed: _qrBusy ? null : _showQr,
                onIntent: () => ref.warm(linksQrProvider(widget.orgId)),
              ),
              DashButton(
                key: const ValueKey('links-open'),
                label: t('links.editor.open'),
                icon: 'external-link',
                variant: DashButtonVariant.outline,
                onPressed: () =>
                    ref.read(linkOpenerProvider)(Uri.parse(url)),
              ),
            ],
          ),
        ] else
          Text(
            t('links.editor.noAddress'),
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }

  Widget _aboutCard(Translator t) {
    final c = context.madarColors;
    return _Card(
      key: const ValueKey('links-about'),
      title: t('links.editor.about'),
      hint: t('links.editor.aboutHint'),
      spacing: Space.lg,
      children: [
        DashFormField<String>(
          label: t('links.editor.taglineEn'),
          builder: (context, _) => _input(
            key: const ValueKey('links-tagline-en'),
            value: _taglineEn,
            label: t('links.editor.taglineEn'),
            maxLength: linksMaxTagline,
            direction: TextDirection.ltr,
            onChanged: (v) => _edit(() => _taglineEn = v),
          ),
        ),
        DashFormField<String>(
          label: t('links.editor.taglineAr'),
          builder: (context, _) => _input(
            key: const ValueKey('links-tagline-ar'),
            value: _taglineAr,
            label: t('links.editor.taglineAr'),
            maxLength: linksMaxTagline,
            direction: TextDirection.rtl,
            onChanged: (v) => _edit(() => _taglineAr = v),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.xs),
            border: Border.all(color: c.border),
          ),
          child: _SwitchRow(
            key: const ValueKey('links-cover'),
            label: t('links.editor.cover'),
            hint: widget.saved.cardImageUrl != null
                ? t('links.editor.coverHint')
                : t('links.editor.coverNone'),
            value: _showCover,
            onChanged: (v) => _edit(() => _showCover = v),
          ),
        ),
      ],
    );
  }

  Widget _buttonsCard(Translator t) {
    final c = context.madarColors;
    final modules = _modules;
    final twoColumns = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final rows = <Widget>[];
    for (final (i, it) in _items.indexed) {
      final custom = it.kind == LinksItemKind.custom;
      final status = custom ? null : modules[it.kind];
      final unavailable = status != null && !status.available;
      final title = linksRowTitle(it, t);
      final key = it.id ?? it.kind.value;
      Widget field({
        required String id,
        required String value,
        required String placeholder,
        required TextDirection direction,
        required ValueChanged<String> onChanged,
        int? maxLength,
        bool url = false,
      }) => _input(
        key: ValueKey('links-item-$key-$id'),
        value: value,
        placeholder: placeholder,
        maxLength: maxLength,
        direction: direction,
        url: url,
        invalid: url && linkUrlInvalid(value),
        onChanged: onChanged,
      );
      final titleEn = field(
        id: 'title-en',
        value: it.titleEn ?? '',
        placeholder: t('links.editor.titleEn'),
        maxLength: linksMaxTitle,
        direction: TextDirection.ltr,
        onChanged: (v) => _patch(i, patchLink(it, titleEn: v)),
      );
      final titleAr = field(
        id: 'title-ar',
        value: it.titleAr ?? '',
        placeholder: t('links.editor.titleAr'),
        maxLength: linksMaxTitle,
        direction: TextDirection.rtl,
        onChanged: (v) => _patch(i, patchLink(it, titleAr: v)),
      );
      final url = field(
        id: 'url',
        value: it.url ?? '',
        placeholder: 'https://',
        direction: TextDirection.ltr,
        url: true,
        onChanged: (v) => _patch(i, patchLink(it, url: v)),
      );
      rows.add(
        Padding(
          key: ValueKey('links-item-$key'),
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              Row(
                spacing: Space.sm,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DashIconButton(
                        icon: 'arrow-up',
                        semanticLabel: t('links.editor.up'),
                        onPressed: i == 0 ? null : () => _move(i, -1),
                      ),
                      DashIconButton(
                        icon: 'arrow-down',
                        semanticLabel: t('links.editor.down'),
                        onPressed: i == _items.length - 1
                            ? null
                            : () => _move(i, 1),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MadarClippedText(
                          title,
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                          maxLines: 1,
                        ),
                        MadarClippedText(
                          linksRowSubtitle(it, status, t),
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  if (custom)
                    DashIconButton(
                      icon: 'trash-2',
                      semanticLabel: t('links.editor.remove'),
                      onPressed: () =>
                          _edit(() => _items = [..._items]..removeAt(i)),
                    ),
                  DashSwitch(
                    value: it.visible != false && !unavailable,
                    enabled: !unavailable,
                    semanticLabel: t(
                      'links.editor.show',
                      args: {'name': title},
                    ),
                    onChanged: (v) => _patch(i, patchLink(it, visible: v)),
                  ),
                ],
              ),
              if (custom) ...[
                if (twoColumns)
                  Row(
                    spacing: Space.sm,
                    children: [
                      Expanded(child: titleEn),
                      Expanded(child: titleAr),
                    ],
                  )
                else ...[
                  titleEn,
                  titleAr,
                ],
                url,
              ],
            ],
          ),
        ),
      );
    }
    return _Card(
      key: const ValueKey('links-buttons'),
      title: t('links.editor.buttons'),
      hint: t('links.editor.buttonsHint'),
      children: [
        _Framed(children: rows),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DashButton(
            key: const ValueKey('links-add'),
            label: t('links.editor.addLink'),
            icon: 'plus',
            variant: DashButtonVariant.outline,
            onPressed: () => _edit(() => _items = [..._items, newCustomLink()]),
          ),
        ),
      ],
    );
  }

  Widget _visitCard(Translator t) {
    final c = context.madarColors;
    return _Card(
      key: const ValueKey('links-visit'),
      children: [
        _SwitchRow(
          key: const ValueKey('links-show-branches'),
          label: t('links.editor.visit'),
          hint: t('links.editor.visitHint'),
          value: _showBranches,
          onChanged: (v) => _edit(() => _showBranches = v),
        ),
        if (_showBranches && _branches.isNotEmpty)
          _Framed(
            children: [
              for (final (i, b) in _branches.indexed)
                Padding(
                  key: ValueKey('links-branch-${b.branchId}'),
                  padding: const EdgeInsets.all(Space.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Space.sm + DashMetrics.hair,
                    children: [
                      Row(
                        spacing: Space.md,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.name,
                                  style: DashType.bodyMedium.copyWith(
                                    color: c.textPrimary,
                                  ),
                                ),
                                if (b.address case final a? when a.isNotEmpty)
                                  Text(
                                    a,
                                    style: DashType.small.copyWith(
                                      color: c.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          DashSwitch(
                            value: b.visible,
                            semanticLabel: t(
                              'links.editor.show',
                              args: {'name': b.name},
                            ),
                            onChanged: (v) => _edit(
                              () => _branches = [..._branches]
                                ..[i] = b.copyWith(visible: v),
                            ),
                          ),
                        ],
                      ),
                      _input(
                        key: ValueKey('links-maps-${b.branchId}'),
                        value: b.mapsUrl,
                        placeholder: t('links.editor.maps'),
                        direction: TextDirection.ltr,
                        url: true,
                        enabled: b.visible,
                        invalid: linkUrlInvalid(b.mapsUrl),
                        onChanged: (v) => _edit(
                          () => _branches = [..._branches]
                            ..[i] = b.copyWith(mapsUrl: v),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// A card that opens with a title and one line under it (`CardHeading`).
class _Card extends StatelessWidget {
  const _Card({
    required this.children,
    this.title,
    this.hint,
    this.spacing = Space.md,
    super.key,
  });

  final String? title;
  final String? hint;
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: spacing,
        children: [
          if (title != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DashMetrics.hair,
              children: [
                Text(
                  title!,
                  style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
          ...children,
        ],
      ),
    );
  }
}

/// A bordered list with a hairline between rows (`divide-y rounded-lg
/// border`).
class _Framed extends StatelessWidget {
  const _Framed({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, w) in children.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.border),
            w,
          ],
        ],
      ),
    );
  }
}

/// A label and its hint, the switch at the end.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Row(
      spacing: Space.md,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              Text(hint, style: DashType.small.copyWith(color: c.textSecondary)),
            ],
          ),
        ),
        DashSwitch(value: value, semanticLabel: label, onChanged: onChanged),
      ],
    );
  }
}

/// "Preview (as saved)" over a phone-shaped frame holding the public page.
class _Preview extends ConsumerWidget {
  const _Preview({required this.orgId, super.key});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Text(
          t('links.editor.preview').toUpperCase(),
          style: DashType.small.copyWith(
            color: c.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        Container(
          height: LinksMetrics.frame,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(LinksMetrics.frameRadius),
            border: Border.all(
              color: c.textPrimary.withValues(alpha: 0.1),
              width: LinksMetrics.frameBorder,
            ),
          ),
          child: SingleChildScrollView(
            primary: false,
            child: LinksPublicPreview(orgId: orgId),
          ),
        ),
      ],
    );
  }
}

/// The form with the preview beside it, the preview following the page's
/// scroll 16 below the top until the form ends (`xl:sticky xl:top-4`).
class _StickyBeside extends StatefulWidget {
  const _StickyBeside({required this.main, required this.aside});

  final Widget main;
  final Widget aside;

  @override
  State<_StickyBeside> createState() => _StickyBesideState();
}

class _StickyBesideState extends State<_StickyBeside> {
  final _aside = GlobalKey();
  ScrollableState? _scrollable;
  double _shift = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = Scrollable.maybeOf(context);
    if (s != _scrollable) {
      _scrollable?.position.removeListener(_follow);
      _scrollable = s?..position.addListener(_follow);
    }
  }

  @override
  void dispose() {
    _scrollable?.position.removeListener(_follow);
    super.dispose();
  }

  void _follow() {
    final row = context.findRenderObject() as RenderBox?;
    final aside = _aside.currentContext?.findRenderObject() as RenderBox?;
    final view = _scrollable?.context.findRenderObject() as RenderBox?;
    if (row == null || aside == null || view == null) return;
    if (!row.hasSize || !aside.hasSize || !row.attached || !view.attached) {
      return;
    }
    final top = row.localToGlobal(Offset.zero, ancestor: view).dy;
    final room = math.max(0.0, row.size.height - aside.size.height);
    final next = (Space.lg - top).clamp(0.0, room);
    if (next != _shift) setState(() => _shift = next);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _follow();
    });
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.xl,
      children: [
        Expanded(child: widget.main),
        Transform.translate(
          offset: Offset(0, _shift),
          child: SizedBox(
            key: _aside,
            width: LinksMetrics.preview,
            child: widget.aside,
          ),
        ),
      ],
    );
  }
}
