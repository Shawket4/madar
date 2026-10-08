/// Create or edit a deal (the web's `features/deals/deal-dialog.tsx`,
/// OFFR-DEA-024..049): its name, kind and numbers, the items it counts (and,
/// for buy X get Y, optionally a separate list the reward comes from), a cap
/// per order, when it runs, which branches run it, and whether it is on.
///
/// A dialog 672 wide on a wide screen, the whole window on a phone. Without
/// `menu.deals.edit` it opens read-only: every field disabled, no add or
/// remove, "Close" only.
///
/// Save checks the form on the fields first (no request while a red line
/// shows); then the deal call, then one branch call per changed branch (PUTs,
/// then DELETEs, each awaited; the first failure stops the rest), a toast,
/// `invalidateCombos()`, and the dialog closes. Closing mid-save lets the
/// save finish, its toast and refresh included.
library;

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show DealBranchWrite, DealRule;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_options.dart';
import '../shared/offers_cache.dart';
import '../shared/offers_format.dart';
import '../shared/windows_editor.dart';
import 'deal_form.dart';
import 'deals_data.dart';
import 'deals_format.dart';
import 'pool_editor.dart';

/// Where the dialog's toasts go: the page that opened it (so a save that
/// outlives the dialog still says how it went).
typedef DealToast = void Function(DashToastKind kind, String message);

/// Opens the deal dialog for [deal] (null = a new deal) and completes when it
/// closes. [open] going false closes it from outside (the deal left the
/// list, the page lost its `?edit`).
Future<void> showDealDialog(
  BuildContext context, {
  required DealRule? deal,
  required bool canEdit,
  required DealToast toast,
  ValueListenable<bool>? open,
}) => showDashDialog<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (context) =>
      DealDialog(deal: deal, canEdit: canEdit, toast: toast, open: open),
);

class DealDialog extends ConsumerStatefulWidget {
  const DealDialog({
    required this.deal,
    required this.canEdit,
    required this.toast,
    this.open,
    super.key,
  });

  /// The deal as listed when the dialog opened; null for a new one.
  final DealRule? deal;
  final bool canEdit;
  final DealToast toast;
  final ValueListenable<bool>? open;

  @override
  ConsumerState<DealDialog> createState() => _DealDialogState();
}

class _DealDialogState extends ConsumerState<DealDialog> {
  late DealRule? _deal = widget.deal;
  late String _seed = _fingerprint(widget.deal);
  late DealDraft _v = _draftOf(widget.deal);
  late Map<String, BranchState> _initialBranches = _v.branches;

  /// Save was pressed once: from now on every change re-checks the form
  /// (react-hook-form's re-validate on change).
  bool _submitted = false;
  bool _saving = false;
  bool _closing = false;

  bool get _ro => !widget.canEdit;

  static DealDraft _draftOf(DealRule? d) =>
      d == null ? DealDraft.empty() : DealDraft.fromWire(d);

  static String _fingerprint(DealRule? d) =>
      d == null ? '' : jsonEncode(d.toJson());

  @override
  void initState() {
    super.initState();
    widget.open?.addListener(_onOpenChanged);
  }

  @override
  void dispose() {
    widget.open?.removeListener(_onOpenChanged);
    super.dispose();
  }

  void _onOpenChanged() {
    if (widget.open?.value == false) _close();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  /// The form re-seeds from the list's row whenever its value changes
  /// (OFFR-ALL-017), dropping what was typed, as the web's reset effect does.
  void _reseed(DealRule row) {
    setState(() {
      _deal = row;
      _seed = _fingerprint(row);
      _v = DealDraft.fromWire(row);
      _initialBranches = _v.branches;
      _submitted = false;
    });
  }

  void _set(DealDraft next) => setState(() => _v = next);

  Future<void> _submit() async {
    if (_ro || _saving) return;
    final errors = validateDeal(_v);
    if (!errors.isEmpty) {
      setState(() => _submitted = true);
      return;
    }
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).menu;
    final bus = ref.read(realtimeBusProvider);
    final deal = _deal;
    final toast = widget.toast;
    final listed = ref.read(dealsProvider).value?.length ?? 0;
    final body = _v.toWire(sort: deal?.sort ?? listed);
    final calls = branchChanges(_initialBranches, _v.branches);
    setState(() => _saving = true);
    try {
      final saved = deal == null
          ? await api.createDeal(body: body)
          : await api.updateDeal(id: deal.id, body: body);
      for (final c in calls) {
        final on = c.isActive;
        if (on == null) {
          await api.deleteDealBranch(id: saved.id, branchId: c.branchId);
        } else {
          await api.putDealBranch(
            id: saved.id,
            branchId: c.branchId,
            body: DealBranchWrite(isActive: on),
          );
        }
      }
      toast(
        DashToastKind.success,
        deal == null ? t('deals.created') : t('common.savedChanges'),
      );
      bus.invalidate(combosInvalidationPrefixes);
      _close();
    } on Object catch (e) {
      toast(DashToastKind.error, dealErrorText(e, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final menu = ref.watch(menuOptionsProvider);
    final id = _deal?.id;
    if (id != null) {
      ref.listen(dealsProvider, (_, next) {
        final rows = next.value;
        if (rows == null || next.isLoading) return;
        final row = rows.firstWhereOrNull((d) => d.id == id);
        if (row == null) return;
        if (_fingerprint(row) != _seed) _reseed(row);
      });
    }

    final v = _v;
    final e = _submitted ? validateDeal(v) : const DealErrors();
    final nFor = v.isNForPrice;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final c = context.madarColors;

    // The rule as the list will read it (`Number(x) || fallback`).
    final preview = dealRuleText(
      t,
      f,
      kind: v.kind,
      qty: _numberOr(v.qty, 0),
      price: _moneyOrZero(v.price),
      getQty: _numberOr(v.getQty, 1),
      getPercent: _numberOr(v.getPercent, 100),
    );

    Widget grid(List<Widget> cells) => wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [for (final w in cells) Expanded(child: w)],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: cells,
          );

    final names = grid([
      _Field(
        label: t('deals.fields.name'),
        error: e.name == null ? null : t(e.name!),
        child: DashTextInput(
          value: v.name,
          onChanged: (s) => _set(v.copyWith(name: s)),
          placeholder: t('deals.namePlaceholder'),
          semanticLabel: t('deals.fields.name'),
          invalid: e.name != null,
          enabled: !_ro,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
      ),
      _Field(
        label: t('deals.fields.nameAr'),
        child: DashTextInput(
          value: v.nameAr,
          onChanged: (s) => _set(v.copyWith(nameAr: s)),
          semanticLabel: t('deals.fields.nameAr'),
          textDirection: TextDirection.rtl,
          enabled: !_ro,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
      ),
    ]);

    final kind = _Field(
      label: t('deals.fields.kind'),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DashSegmentedControl<String>(
          options: [
            DashOption(
              value: DealKind.nForPrice,
              label: t('deals.kind.nForPrice'),
            ),
            DashOption(value: DealKind.buyGet, label: t('deals.kind.buyGet')),
          ],
          value: v.kind,
          semanticLabel: t('deals.fields.kind'),
          enabled: !_ro,
          onChanged: (k) => _set(v.copyWith(kind: k)),
        ),
      ),
    );

    Widget number({
      required String label,
      required String value,
      required ValueChanged<String> onChanged,
      String? error,
      String? hint,
    }) => _Field(
      label: label,
      error: error == null ? null : t(error),
      hint: hint,
      child: DashTextInput(
        value: value,
        onChanged: onChanged,
        semanticLabel: label,
        keyboardType: TextInputType.number,
        inputFormatters: const [_NumberText()],
        textDirection: TextDirection.ltr,
        mono: true,
        invalid: error != null,
        enabled: !_ro,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
    );

    final numbers = grid([
      number(
        label: nFor ? t('deals.fields.qtyN') : t('deals.fields.qtyBuy'),
        value: v.qty,
        onChanged: (s) => _set(v.copyWith(qty: s)),
        error: e.qty,
      ),
      if (nFor)
        _Field(
          label: t('deals.fields.price'),
          error: e.price == null ? null : t(e.price!),
          child: DashTextInput(
            value: v.price,
            onChanged: (s) => _set(v.copyWith(price: s)),
            semanticLabel: t('deals.fields.price'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            mono: true,
            invalid: e.price != null,
            enabled: !_ro,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        )
      else ...[
        number(
          label: t('deals.fields.get'),
          value: v.getQty,
          onChanged: (s) => _set(v.copyWith(getQty: s)),
          error: e.getQty,
        ),
        number(
          label: t('deals.fields.getPercent'),
          value: v.getPercent,
          onChanged: (s) => _set(v.copyWith(getPercent: s)),
          error: e.getPercent,
          hint: t('deals.fields.percentHint'),
        ),
      ],
      // Three columns either way (`sm:grid-cols-3`).
      if (nFor && wide) const SizedBox.shrink(),
    ]);

    final previewBox = DecoratedBox(
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        child: Semantics(
          liveRegion: true,
          child: Text(
            preview,
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
        ),
      ),
    );

    final pool = _Section(
      label: t('deals.fields.pool'),
      children: [
        PoolEditor(
          label: t('deals.fields.pool'),
          value: v.pool,
          onChanged: (p) => _set(v.copyWith(pool: p)),
          menu: menu,
          errors: e.poolEntries,
          enabled: !_ro,
        ),
        if (e.pool != null) _ErrorText(t(e.pool!)),
        _HintText(t('deals.pool.hint')),
      ],
    );

    final reward = nFor
        ? null
        : _Boxed(
            children: [
              Row(
                spacing: Space.md,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: DashMetrics.hair,
                      children: [
                        Text(
                          t('deals.fields.rewardPool'),
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        _HintText(t('deals.reward.hint')),
                      ],
                    ),
                  ),
                  DashSwitch(
                    value: v.useRewardPool,
                    semanticLabel: t('deals.fields.rewardPool'),
                    enabled: !_ro,
                    onChanged: (on) => _set(v.copyWith(useRewardPool: on)),
                  ),
                ],
              ),
              if (v.useRewardPool) ...[
                PoolEditor(
                  label: t('deals.fields.rewardPool'),
                  value: v.rewardPool,
                  onChanged: (p) => _set(v.copyWith(rewardPool: p)),
                  menu: menu,
                  errors: e.rewardEntries,
                  enabled: !_ro,
                ),
                if (e.rewardPool != null) _ErrorText(t(e.rewardPool!)),
              ],
            ],
          );

    final maxBox = Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? _maxFieldWidth : double.infinity,
        ),
        child: number(
          label: t('deals.fields.maxPerOrder'),
          value: v.maxPerOrder,
          onChanged: (s) => _set(v.copyWith(maxPerOrder: s)),
          error: e.maxPerOrder,
          hint: t('deals.fields.maxHint'),
        ),
      ),
    );

    final availability = _Section(
      label: t('combos.sections.availability'),
      children: [
        WindowsEditor(
          value: v.windows,
          onChanged: (w) => _set(v.copyWith(windows: w)),
          branches: [for (final b in menu.branches) (id: b.id, name: b.name)],
          errors: e.windows,
          enabled: !_ro,
        ),
      ],
    );

    final branches = menu.branches.isEmpty
        ? null
        : _Section(
            label: t('deals.fields.branches'),
            children: [
              _HintText(t('deals.branchesHint')),
              _BranchList(
                branches: menu.branches,
                value: v.branches,
                enabled: !_ro,
                t: t,
                onChanged: (b) => _set(v.copyWith(branches: b)),
              ),
            ],
          );

    final active = _Boxed(
      children: [
        Row(
          spacing: Space.md,
          children: [
            Expanded(
              child: Text(
                t('deals.fields.active'),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
            ),
            DashSwitch(
              value: v.isActive,
              semanticLabel: t('deals.fields.active'),
              enabled: !_ro,
              onChanged: (on) => _set(v.copyWith(isActive: on)),
            ),
          ],
        ),
      ],
    );

    return DashSurface(
      title: _deal == null ? t('deals.new') : t('deals.edit'),
      description: t('deals.dialogHint'),
      onClose: _close,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.card,
        children: [
          names,
          kind,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.md,
            children: [numbers, previewBox],
          ),
          pool,
          ?reward,
          maxBox,
          availability,
          ?branches,
          active,
        ],
      ),
      actions: [
        DashButton(
          label: widget.canEdit ? t('common.cancel') : t('common.close'),
          variant: DashButtonVariant.outline,
          onPressed: _close,
        ),
        if (widget.canEdit)
          DashButton(
            label: _deal == null ? t('deals.create') : t('common.save'),
            loading: _saving,
            onPressed: _submit,
          ),
      ],
    );
  }

  /// "Most times per order" (`sm:max-w-48`).
  static const double _maxFieldWidth = 192;
}

/// `Number(text) || fallback`: 0, blank and junk read [fallback].
num _numberOr(String text, num fallback) {
  final n = jsNumber(text);
  return n.isFinite && n != 0 ? n : fallback;
}

/// `moneyIn(text) ?? 0` for the preview (junk reads as no price at all).
num _moneyOrZero(String text) {
  return moneyIn(text) ?? 0;
}

/// What a number box takes (the web's `type="number"`): digits, a point and
/// a minus; Arabic-Indic digits are read as Western ones.
class _NumberText extends TextInputFormatter {
  const _NumberText();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final latin = DashTime.latinDigits(newValue.text);
    if (!RegExp(r'^[0-9.\-]*$').hasMatch(latin)) return oldValue;
    if (latin == newValue.text) return newValue;
    return newValue.copyWith(text: latin);
  }
}

/// A label, a control, then its red line or its quiet hint (the web's
/// `space-y-1.5` field with a `text-xs` message).
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.child,
    this.error,
    this.hint,
  });

  final String label;
  final Widget child;
  final String? error;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
        ),
        child,
        if (error != null)
          _ErrorText(error!)
        else if (hint != null)
          _HintText(hint!),
      ],
    );
  }
}

/// A labelled block: the label, then its parts.
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Semantics(
          header: true,
          child: Text(
            label,
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// A bordered box (`rounded-xl border p-3`).
class _Boxed extends StatelessWidget {
  const _Boxed({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.sm,
          children: children,
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: DashType.small.copyWith(color: context.madarColors.errorText),
    ),
  );
}

class _HintText extends StatelessWidget {
  const _HintText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: DashType.small.copyWith(color: context.madarColors.textSecondary),
  );
}

/// One row per branch: its name and its switch for the deal (the select's
/// accessible name is the branch's name).
class _BranchList extends StatelessWidget {
  const _BranchList({
    required this.branches,
    required this.value,
    required this.enabled,
    required this.t,
    required this.onChanged,
  });

  final List<NamedOption> branches;
  final Map<String, BranchState> value;
  final bool enabled;
  final Translator t;
  final ValueChanged<Map<String, BranchState>> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final options = [
      DashOption(value: BranchState.inherit, label: t('deals.branch.follow')),
      DashOption(value: BranchState.on, label: t('combos.settings.on')),
      DashOption(value: BranchState.off, label: t('combos.settings.off')),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < branches.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.hairline),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Space.md,
                vertical: Space.xs,
              ),
              child: Row(
                spacing: Space.md,
                children: [
                  Expanded(
                    child: MadarClippedText(
                      branches[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashType.body.copyWith(color: c.textPrimary),
                    ),
                  ),
                  SizedBox(
                    width: _selectWidth,
                    child: DashSelect<BranchState>(
                      options: options,
                      value: value[branches[i].id] ?? BranchState.inherit,
                      semanticLabel: branches[i].name,
                      enabled: enabled,
                      onChanged: (s) =>
                          onChanged({...value, branches[i].id: s}),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The branch select's width (`w-40`).
  static const double _selectWidth = 160;
}
