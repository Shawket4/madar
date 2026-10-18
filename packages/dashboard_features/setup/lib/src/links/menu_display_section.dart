/// "Menu (no prices)": the settings of the shop's menu without prices
/// (`features/links/admin/menu-display-section.tsx`).
///
/// Self-contained (its own read, draft and save), so it sits on the Links
/// page for every plan: a Free shop has no links page, but it has this. It
/// is NOT one of the links page's buttons; the page lives at its own address
/// (`<slug>.madar-pos.cloud/menu`, else `loyalty.madar-pos.cloud/menu/<org>`,
/// the server's `public_url`), shown here with Copy, Open and its QR code
/// (the links page's own code endpoint, `target=menu_display`).
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart'
    show MenuDisplayInput, MenuDisplaySettings;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show linkOpenerProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/qr_preview_dialog.dart';
import 'links_data.dart' show codeUnitLimit;
import 'links_providers.dart';

/// Matches the server's limit (`orgs::menu_display::MAX_TITLE_CHARS`).
const int maxMenuTitle = 60;

/// The branch picker's "no pick" value: the shop's first branch.
const String menuDisplayDefaultBranch = '__default__';

/// The section's fixed sizes: the loading bar (`h-56`) and the picker
/// (`sm:w-80`).
abstract final class MenuDisplayMetrics {
  static const double loading = 224;
  static const double picker = 320;
}

class MenuDisplaySection extends ConsumerWidget {
  const MenuDisplaySection({required this.orgId, super.key});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(menuDisplayProvider(orgId));
    if (q.awaitingFirst) {
      return const DashSkeleton(
        key: ValueKey('menu-display-loading'),
        height: MenuDisplayMetrics.loading,
        radius: Radii.card,
      );
    }
    if (q.failedFirst) {
      // Divergence: the web keeps its skeleton on a failed read; here the
      // section says so and offers Retry.
      final t = ref.watch(tProvider);
      return DashErrorState(
        key: const ValueKey('menu-display-error'),
        title: t('common.loadFailed'),
        message: errorMessage(q.error, t),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(menuDisplayProvider(orgId)),
      );
    }
    return MenuDisplayForm(
      key: ValueKey('menu-display-$orgId'),
      orgId: orgId,
      saved: q.requireValue,
    );
  }
}

class MenuDisplayForm extends ConsumerStatefulWidget {
  const MenuDisplayForm({required this.orgId, required this.saved, super.key});

  final String orgId;
  final MenuDisplaySettings saved;

  @override
  ConsumerState<MenuDisplayForm> createState() => _MenuDisplayFormState();
}

class _MenuDisplayFormState extends ConsumerState<MenuDisplayForm> {
  /// What the server last answered: the read, then each save's reply (the
  /// web's `setQueryData`).
  late MenuDisplaySettings _saved;
  late bool _enabled;
  late String _titleEn;
  late String _titleAr;
  late String _branch;
  bool _busy = false;
  bool _qrBusy = false;

  /// Bumped on a reseed so the inputs show the saved text.
  int _seedKey = 0;

  @override
  void initState() {
    super.initState();
    _seed(widget.saved);
  }

  void _seed(MenuDisplaySettings s) {
    _saved = s;
    _enabled = s.enabled;
    _titleEn = s.titleEn ?? '';
    _titleAr = s.titleAr ?? '';
    _branch = s.branchId ?? menuDisplayDefaultBranch;
    _seedKey++;
  }

  @override
  void didUpdateWidget(MenuDisplayForm old) {
    super.didUpdateWidget(old);
    // The web's `form.reset(toForm(saved))` whenever the read changes.
    if (widget.saved.toString() != old.saved.toString()) _seed(widget.saved);
  }

  String? _clean(String v) {
    final s = v.trim();
    return s.isEmpty ? null : s;
  }

  Future<void> _save() async {
    if (_busy) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).orgs;
    final bus = ref.read(realtimeBusProvider);
    final orgId = widget.orgId;
    setState(() => _busy = true);
    final MenuDisplaySettings next;
    try {
      next = await api.putMenuDisplay(
        id: orgId,
        body: MenuDisplayInput(
          enabled: _enabled,
          titleEn: _clean(_titleEn),
          titleAr: _clean(_titleAr),
          branchId: _branch == menuDisplayDefaultBranch ? null : _branch,
          explicitNulls: const {'title_en', 'title_ar', 'branch_id'},
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        DashToast.error(context, errorMessage(e, t));
      }
      return;
    }
    bus.invalidate([menuDisplayPath(orgId)]);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _seed(next);
    });
    DashToast.success(context, t('menuDisplay.editor.saved'));
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
    final read = menuDisplayQrProvider(widget.orgId);
    setState(() => _qrBusy = true);
    try {
      final qr = await container.read(read.future);
      if (mounted) {
        unawaited(
          showQrPreview(
            context,
            qr: qr,
            title: t('menuDisplay.editor.qrTitle'),
          ),
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
    final c = context.madarColors;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final s = _saved;
    final firstBranch = s.branches.isEmpty ? null : s.branches.first.name;

    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.md,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DashMetrics.hair,
            children: [
              Text(
                t('menuDisplay.editor.title'),
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
              Text(
                t('menuDisplay.editor.hint'),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
        DashButton(
          key: const ValueKey('menu-display-save'),
          label: t('common.save'),
          loading: _busy,
          onPressed: _busy ? null : _save,
        ),
      ],
    );

    final enabled = Container(
      key: const ValueKey('menu-display-enabled'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: c.border),
      ),
      child: Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('menuDisplay.editor.enabled'),
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                Text(
                  t('menuDisplay.editor.enabledHint'),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          DashSwitch(
            value: _enabled,
            semanticLabel: t('menuDisplay.editor.enabled'),
            onChanged: (v) => setState(() => _enabled = v),
          ),
        ],
      ),
    );

    Widget title({
      required String id,
      required String label,
      required String value,
      required String placeholder,
      required TextDirection direction,
      required ValueChanged<String> onChanged,
    }) => DashFormField<String>(
      label: label,
      builder: (context, _) => DashTextInput(
        key: ValueKey('menu-display-$id-$_seedKey'),
        value: value,
        onChanged: onChanged,
        placeholder: placeholder,
        semanticLabel: label,
        maxLength: maxMenuTitle,
        inputFormatters: [codeUnitLimit(maxMenuTitle)],
        textDirection: direction,
        onSubmitted: (_) => _save(),
      ),
    );
    final titleEn = title(
      id: 'title-en',
      label: t('menuDisplay.editor.titleEn'),
      value: _titleEn,
      placeholder: t('menuDisplay.title'),
      direction: TextDirection.ltr,
      onChanged: (v) => setState(() => _titleEn = v),
    );
    final titleAr = title(
      id: 'title-ar',
      label: t('menuDisplay.editor.titleAr'),
      value: _titleAr,
      placeholder: 'المنيو',
      direction: TextDirection.rtl,
      onChanged: (v) => setState(() => _titleAr = v),
    );

    final branch = DashFormField<String>(
      label: t('menuDisplay.editor.branch'),
      description: t('menuDisplay.editor.branchHint'),
      builder: (context, _) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          width: wide ? MenuDisplayMetrics.picker : double.infinity,
          child: DashSelect<String>(
            key: const ValueKey('menu-display-branch'),
            semanticLabel: t('menuDisplay.editor.branch'),
            value: _branch,
            options: [
              DashOption(
                value: menuDisplayDefaultBranch,
                label: firstBranch != null
                    ? t(
                        'menuDisplay.editor.branchDefaultNamed',
                        args: {'name': firstBranch},
                      )
                    : t('menuDisplay.editor.branchDefault'),
              ),
              for (final b in s.branches)
                DashOption(value: b.id, label: b.name),
            ],
            onChanged: (v) => setState(() => _branch = v),
          ),
        ),
      ),
    );

    final url = s.publicUrl;
    final live = s.enabled;
    final address = Container(
      padding: const EdgeInsets.only(top: Space.lg),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          Text(
            t('menuDisplay.editor.address'),
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
          if (url != null) ...[
            Container(
              key: const ValueKey('menu-display-url'),
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
            if (!live)
              Text(
                t('menuDisplay.editor.offNote'),
                key: const ValueKey('menu-display-off-note'),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                DashButton(
                  key: const ValueKey('menu-display-copy'),
                  label: t('links.editor.copy'),
                  icon: 'copy',
                  variant: DashButtonVariant.outline,
                  onPressed: () => _copy(url),
                ),
                DashButton(
                  key: const ValueKey('menu-display-qr'),
                  label: t('links.editor.qr'),
                  icon: 'qr-code',
                  variant: DashButtonVariant.outline,
                  loading: _qrBusy,
                  onPressed: _qrBusy ? null : _showQr,
                  onIntent: () => ref.warm(menuDisplayQrProvider(widget.orgId)),
                ),
                if (live)
                  DashButton(
                    key: const ValueKey('menu-display-open'),
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
              t('menuDisplay.editor.noAddress'),
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
        ],
      ),
    );

    return DashCard(
      key: const ValueKey('menu-display-section'),
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          heading,
          enabled,
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.lg,
              children: [
                Expanded(child: titleEn),
                Expanded(child: titleAr),
              ],
            )
          else ...[
            titleEn,
            titleAr,
          ],
          branch,
          address,
        ],
      ),
    );
  }
}
