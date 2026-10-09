/// `/settings/combos` Combos and deals (SET-CMB-001 … 018; web
/// `features/combos/combo-settings-page.tsx`): where combos and deals are
/// sold (one switch per channel for the organisation, a branch may differ)
/// and the minimum margin the combo editor warns below.
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane. It refuses in place without
/// `org.settings.read`/`menu.combos.edit` and asks nothing (SET-CMB-001); a
/// reader sees every control disabled and no Save (SET-CMB-005).
library;

import 'package:dashboard_api/dashboard_api.dart' show Branch, ComboSettings;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/scope.dart';
import '../shared/setup_note.dart';
import 'combo_settings_data.dart';

class ComboSettingsPage extends ConsumerWidget {
  const ComboSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    final title = t('combos.settings.title');
    if (authz.ready &&
        !authz.canAny(const [Cap.orgSettingsRead, Cap.menuCombosEdit])) {
      return SetupRefusalPane(
        key: const ValueKey('cmb-restricted'),
        title: title,
        stateTitle: t('common.restrictedTitle'),
        message: t('combos.settings.noAccess'),
      );
    }
    if (!authz.ready && authz.error != null) return const AuthzLoadError();
    final orgId = ref.watch(orgIdProvider);
    return DashPageScaffold(
      title: title,
      subtitle: t('combos.settings.subtitle'),
      width: DashPageWidth.reading,
      // Keyed by org: a platform admin's switch reloads the form.
      body: ComboSettingsBody(key: ValueKey('cmb-form-$orgId'), orgId: orgId),
    );
  }
}

/// The skeleton cards' heights (`h-40`, `h-28`).
const double _skeletonTop = Space.xxl * 5;
const double _skeletonBottom = Space.xxl * 3.5;

/// The margin box (`w-36`) and a branch cell's floor (`min-w-28`).
const double _marginWidth = Space.xxl * 4.5;
const double _cellMin = Space.xxl * 3.5;

/// The exceptions table's floor (`min-w-[36rem]`): narrower scrolls sideways.
const double _tableMin = 576;

class ComboSettingsBody extends ConsumerStatefulWidget {
  const ComboSettingsBody({required this.orgId, super.key});

  final String? orgId;

  @override
  ConsumerState<ComboSettingsBody> createState() => _ComboSettingsBodyState();
}

class _ComboSettingsBodyState extends ConsumerState<ComboSettingsBody> {
  /// The answer [_base] was filled from; [_form] is what is on screen.
  /// Until the person changes it, a refreshed answer refills both (also
  /// after a branch exception's re-read: divergence SET-CMB-018).
  ComboSettings? _from;
  ComboSettingsForm? _base;
  ComboSettingsForm? _form;

  /// A Save was attempted: the margin's error shows, and follows each
  /// change after (react-hook-form's submit-then-change validation).
  bool _submitted = false;
  bool _saving = false;

  /// The branch whose exception is being saved (its row is busy).
  String? _savingBranch;

  /// Retry with no organisation in scope asks anyway (TanStack's `refetch`
  /// runs a disabled query), and the server says why it cannot answer.
  bool _forced = false;

  bool get _dirty => _form != _base;

  void _follow(ComboSettings s) {
    if (identical(s, _from)) return;
    _from = s;
    if (_form != null && _dirty) return;
    _base = _form = ComboSettingsForm.from(s);
  }

  void _edit(ComboSettingsForm next) => setState(() => _form = next);

  Future<void> _save() async {
    final f = _form!;
    setState(() => _submitted = true);
    if (!marginOk(f.minMargin)) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).menu;
    // Captured before the await: the pane may close mid-save, and the
    // re-reads still run (the web's query client refetches regardless).
    final bus = ref.read(realtimeBusProvider);
    setState(() => _saving = true);
    final ComboSettings saved;
    try {
      saved = await api.putSettings(body: f.toWire());
    } on Object catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        DashToast.error(context, errorMessage(e, t));
      }
      return;
    }
    bus.invalidate(ComboSettingsPaths.invalidated);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _submitted = false;
      _base = _form = ComboSettingsForm.from(saved);
    });
    DashToast.success(context, t('combos.settings.saved'));
  }

  /// A branch cell changed: its whole override, merged, saves at once; a
  /// change that leaves nothing set deletes it (SET-CMB-012/013).
  Future<void> _setBranch(
    ComboSettings settings,
    String branchId,
    ComboChannel channel,
    ComboTri value,
  ) async {
    final now = overrideOf(settings, branchId);
    if (triOf(overrideValue(now, channel)) == value) return;
    final next = overrideWith(now, channel, boolOf(value));
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).menu;
    final bus = ref.read(realtimeBusProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final read = comboSettingsProvider(widget.orgId);
    setState(() => _savingBranch = branchId);
    try {
      if (overrideSetsAny(next)) {
        await api.putBranchChannels(branchId: branchId, body: next);
      } else {
        await api.deleteBranchChannels(branchId: branchId);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _savingBranch = null);
        DashToast.error(context, errorMessage(e, t));
      }
      return;
    }
    bus.invalidate(ComboSettingsPaths.invalidated);
    if (mounted) DashToast.success(context, t('combos.settings.branchSaved'));
    // The row stays busy until the re-read lands (`await q.refetch()`), so
    // the cell never shows the old value in between.
    try {
      await container.read(read.future);
    } on Object catch (_) {
      // The pane's own read shows its failure.
    }
    if (mounted) setState(() => _savingBranch = null);
  }

  Widget _skeleton(Translator t) => Semantics(
    key: const ValueKey('cmb-loading'),
    label: t('common.loading'),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSkeleton(height: _skeletonTop, radius: Radii.card),
        DashSkeleton(height: _skeletonBottom, radius: Radii.card),
      ],
    ),
  );

  Widget _failed(Translator t, {String? message, bool retrying = false}) =>
      DashErrorState(
        key: const ValueKey('cmb-failed'),
        title: t('combos.settings.loadFailed'),
        message: message,
        retryLabel: t('common.retry'),
        retrying: retrying,
        onRetry: () {
          if (!_forced) setState(() => _forced = true);
          ref.invalidate(comboSettingsProvider(widget.orgId));
        },
      );

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    // Grants still loading: the web's disabled query reads as a failure
    // here; it is a wait (divergence SET-CMB-017).
    if (!authz.ready) return _skeleton(t);
    if (widget.orgId == null && !_forced) return _failed(t);
    final q = ref.watch(comboSettingsProvider(widget.orgId));
    if (q.awaitingFirst) return _skeleton(t);
    if (q.failedFirst || !q.hasValue) {
      return _failed(
        t,
        message: errorMessage(q.error, t),
        retrying: q.isLoading,
      );
    }
    final settings = q.requireValue;
    _follow(settings);
    final f = _form!;
    final canEdit = authz.can(Cap.menuCombosEdit);
    final c = context.madarColors;
    final pad = EdgeInsets.all(
      DashBreakpoints.isPhone(context) ? Space.lg : Space.card,
    );
    final marginError = _submitted && !marginOk(f.minMargin)
        ? t('combos.errors.percent')
        : null;
    final muted = DashType.small.copyWith(color: c.textSecondary);
    final strong = DashType.bodyStrong.copyWith(color: c.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        if (!canEdit)
          SetupNote(
            t('combos.settings.readOnly'),
            key: const ValueKey('cmb-ro'),
          ),
        DashCard(
          key: const ValueKey('cmb-channels'),
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('combos.settings.channelsTitle'), style: strong),
              const SizedBox(height: Space.xs),
              Text(t('combos.settings.channelsHint'), style: muted),
              const SizedBox(height: Space.sm),
              for (final ch in ComboChannel.values)
                _ChannelRow(
                  key: ValueKey('cmb-sell-${ch.name}'),
                  channel: ch,
                  first: ch == ComboChannel.values.first,
                  value: f.sell[ch]!,
                  enabled: canEdit,
                  onChanged: (v) => _edit(f.withChannel(ch, v)),
                ),
            ],
          ),
        ),
        DashCard(
          key: const ValueKey('cmb-margin-card'),
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              Text(t('combos.settings.minMargin'), style: strong),
              Row(
                spacing: Space.sm,
                children: [
                  SizedBox(
                    width: _marginWidth,
                    child: DashTextInput(
                      key: const ValueKey('cmb-margin'),
                      value: f.minMargin,
                      placeholder: t('combos.settings.noWarning'),
                      semanticLabel: t('combos.settings.minMargin'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textDirection: TextDirection.ltr,
                      mono: true,
                      invalid: marginError != null,
                      enabled: canEdit,
                      onChanged: (v) => _edit(f.withMargin(v)),
                      onSubmitted: (_) {
                        if (canEdit && _dirty && !_saving) _save();
                      },
                    ),
                  ),
                  Text('%', style: DashType.body.copyWith(color: c.textSecondary)),
                ],
              ),
              if (marginError != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    marginError,
                    key: const ValueKey('cmb-margin-error'),
                    style: DashType.small.copyWith(color: c.errorText),
                  ),
                )
              else
                Text(t('combos.settings.minMarginHint'), style: muted),
            ],
          ),
        ),
        if (canEdit)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashButton(
              key: const ValueKey('cmb-save'),
              label: t('common.save'),
              loading: _saving,
              onPressed: _dirty && !_saving ? _save : null,
            ),
          ),
        DashCard(
          key: const ValueKey('cmb-branches'),
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.xs,
                children: [
                  Text(t('combos.settings.branchesTitle'), style: strong),
                  Text(t('combos.settings.branchesHint'), style: muted),
                ],
              ),
              _branches(t, settings, canEdit),
            ],
          ),
        ),
      ],
    );
  }

  Widget _branches(Translator t, ComboSettings settings, bool canEdit) {
    final c = context.madarColors;
    final q = ref.watch(branchesProvider);
    if (q.awaitingFirst) {
      return const DashSkeleton(
        key: ValueKey('cmb-branches-loading'),
        height: DashMetrics.tableRow,
      );
    }
    if (q.failedFirst) {
      return DashErrorState(
        key: const ValueKey('cmb-branches-failed'),
        framed: false,
        message: errorMessage(q.error, t),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(branchesProvider),
      );
    }
    final branches = [...?q.value?.where(isSelling)];
    if (branches.isEmpty) {
      return Text(
        t('combos.settings.noBranches'),
        key: const ValueKey('cmb-no-branches'),
        style: DashType.body.copyWith(color: c.textSecondary),
      );
    }
    final org = channelsOf(settings.channels);
    Widget cell(Branch b, ComboChannel ch) {
      final label = t(ch.labelKey);
      return DashSelect<ComboTri>(
        key: ValueKey('cmb-cell-${b.id}-${ch.name}'),
        value: triOf(overrideValue(overrideOf(settings, b.id), ch)),
        semanticLabel: t(
          'combos.settings.branchChannel',
          args: {'branch': b.name, 'channel': label},
        ),
        sheetTitle: '${b.name} · $label',
        minWidth: _cellMin,
        enabled: canEdit && _savingBranch != b.id,
        onChanged: (v) => _setBranch(settings, b.id, ch, v),
        options: [
          DashOption(
            value: ComboTri.inherit,
            label: t(
              org[ch]!
                  ? 'combos.settings.followOn'
                  : 'combos.settings.followOff',
            ),
          ),
          DashOption(value: ComboTri.on, label: t('combos.settings.on')),
          DashOption(value: ComboTri.off, label: t('combos.settings.off')),
        ],
      );
    }

    final name = DashType.bodyMedium.copyWith(color: c.textPrimary);
    if (DashBreakpoints.isPhone(context)) {
      // Phone: one block per branch, a line per channel.
      return Column(
        key: const ValueKey('cmb-branch-list'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, b) in branches.indexed)
            Container(
              key: ValueKey('cmb-row-${b.id}'),
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: c.hairline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.sm,
                children: [
                  MadarClippedText(b.name, maxLines: 1, style: name),
                  for (final ch in ComboChannel.values)
                    Row(
                      spacing: Space.md,
                      children: [
                        Expanded(
                          child: Text(
                            t(ch.labelKey),
                            style: DashType.body.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                        SizedBox(width: _marginWidth, child: cell(b, ch)),
                      ],
                    ),
                ],
              ),
            ),
        ],
      );
    }
    final header = DashType.tableHeader.copyWith(color: c.textSecondary);
    Widget th(String text) => Padding(
      padding: const EdgeInsetsDirectional.only(
        top: Space.sm,
        bottom: Space.sm,
        end: Space.xs,
      ),
      child: Text(text.toUpperCase(), style: header),
    );
    final table = Table(
      key: const ValueKey('cmb-branch-table'),
      columnWidths: const {0: FlexColumnWidth(1.4)},
      defaultColumnWidth: const FlexColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(horizontalInside: BorderSide(color: c.hairline)),
      children: [
        TableRow(
          children: [
            th(t('combos.settings.branch')),
            for (final ch in ComboChannel.values) th(t(ch.labelKey)),
          ],
        ),
        for (final b in branches)
          TableRow(
            key: ValueKey('cmb-row-${b.id}'),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Space.md),
                child: MadarClippedText(b.name, maxLines: 1, style: name),
              ),
              for (final ch in ComboChannel.values)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.xs,
                    vertical: Space.sm,
                  ),
                  child: cell(b, ch),
                ),
            ],
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= _tableMin
          ? table
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: _tableMin, child: table),
            ),
    );
  }
}

/// One channel's line: icon, name and hint, and the org's switch.
class _ChannelRow extends ConsumerWidget {
  const _ChannelRow({
    required this.channel,
    required this.first,
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final ComboChannel channel;
  final bool first;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final label = t(channel.labelKey);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.hairline)),
      ),
      child: Row(
        spacing: Space.lg,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs / 2),
                  child: DashIcon(channel.icon, color: c.textSecondary),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: DashType.bodyMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        t(channel.hintKey),
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          DashSwitch(
            value: value,
            semanticLabel: label,
            enabled: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
