/// Create or edit a discount (the web's `features/discounts/discount-dialog
/// .tsx`, OFFR-DSC-024..045): its English and Arabic name, percentage or
/// fixed amount, the value, and whether cashiers may apply it.
///
/// A dialog 512 wide on a wide screen, the whole window on a phone. Save
/// checks the form first (no request while a red line shows), then creates or
/// updates, toasts, refreshes every `/discounts` read and closes; a failure
/// toasts the server's words and keeps the form. Cancel, × and Esc stay live
/// while a save runs: the save still finishes, toast and refresh included.
library;

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show CreateDiscountRequest, Discount, UpdateDiscountRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/offers_cache.dart';
import '../shared/offers_format.dart' show arabicOf;
import 'discounts_data.dart';

/// Where the dialog's toasts go: the page that opened it, so a save that
/// outlives the dialog still says how it went.
typedef DiscountToast = void Function(DashToastKind kind, String message);

/// Opens the discount dialog for [discount] (null = a new one) in [orgId]
/// and completes when it closes. [open] going false closes it from outside.
Future<void> showDiscountDialog(
  BuildContext context, {
  required String orgId,
  required Discount? discount,
  required DiscountToast toast,
  ValueListenable<bool>? open,
}) => showDashDialog<void>(
  context,
  builder: (context) => DiscountDialog(
    orgId: orgId,
    discount: discount,
    toast: toast,
    open: open,
  ),
);

class DiscountDialog extends ConsumerStatefulWidget {
  const DiscountDialog({
    required this.orgId,
    required this.discount,
    required this.toast,
    this.open,
    super.key,
  });

  final String orgId;

  /// The discount as listed when the dialog opened; null for a new one.
  final Discount? discount;
  final DiscountToast toast;
  final ValueListenable<bool>? open;

  @override
  ConsumerState<DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends ConsumerState<DiscountDialog> {
  late Discount? _discount = widget.discount;
  late String _seed = _fingerprint(widget.discount);
  late String _name;
  late String _nameAr;
  late String _dtype;
  late String _value;
  late bool _active;

  /// Save was pressed once: every change re-checks the form from then on
  /// (react-hook-form's re-validate on change).
  bool _submitted = false;
  bool _saving = false;
  bool _closing = false;

  static String _fingerprint(Discount? d) =>
      d == null ? '' : jsonEncode(d.toJson());

  @override
  void initState() {
    super.initState();
    _fill(widget.discount);
    widget.open?.addListener(_onOpenChanged);
  }

  @override
  void dispose() {
    widget.open?.removeListener(_onOpenChanged);
    super.dispose();
  }

  /// The form as the web's reset effect fills it (OFFR-DSC-025).
  void _fill(Discount? d) {
    _name = d?.name ?? '';
    _nameAr = arabicOf(d?.nameTranslations) ?? '';
    _dtype = d?.dtype == DiscountType.fixed
        ? DiscountType.fixed
        : DiscountType.percentage;
    _value = discountValueText(d);
    _active = d?.isActive ?? true;
  }

  void _onOpenChanged() {
    if (widget.open?.value == false) _close();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  /// The listed row changed while open (a refetch): the form re-seeds,
  /// dropping what was typed, as the web's reset effect does (OFFR-ALL-017).
  void _reseed(Discount row) => setState(() {
    _discount = row;
    _seed = _fingerprint(row);
    _fill(row);
    _submitted = false;
  });

  DiscountErrors get _errors =>
      validateDiscount(name: _name, dtype: _dtype, value: _value);

  Future<void> _submit() async {
    if (_saving) return;
    final e = _errors;
    if (e.name != null || e.value != null) {
      setState(() => _submitted = true);
      return;
    }
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).discounts;
    final bus = ref.read(realtimeBusProvider);
    final toast = widget.toast;
    final d = _discount;
    final value = discountWireValue(_dtype, _value);
    final names = _nameAr.isEmpty ? null : <String, Object?>{'ar': _nameAr};
    setState(() => _saving = true);
    try {
      if (d == null) {
        await api.createDiscount(
          body: CreateDiscountRequest(
            orgId: widget.orgId,
            name: _name,
            nameTranslations: names,
            dtype: _dtype,
            value: value,
            isActive: _active,
          ),
        );
      } else {
        await api.updateDiscount(
          id: d.id,
          body: UpdateDiscountRequest(
            name: _name,
            nameTranslations: names,
            dtype: _dtype,
            value: value,
            isActive: _active,
          ),
        );
      }
      bus.invalidate(const [OffersPaths.discounts]);
      toast(
        DashToastKind.success,
        t(d == null ? 'discounts.createdToast' : 'discounts.updatedToast'),
      );
      _close();
    } on Object catch (err) {
      toast(DashToastKind.error, discountErrorText(err, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final id = _discount?.id;
    if (id != null) {
      ref.listen(discountsProvider(widget.orgId), (_, next) {
        final rows = next.value;
        if (rows == null || next.isLoading) return;
        final row = rows.firstWhereOrNull((x) => x.id == id);
        if (row != null && _fingerprint(row) != _seed) _reseed(row);
      });
    }
    final c = context.madarColors;
    final e = _submitted ? _errors : (name: null, value: null);
    final pct = _dtype == DiscountType.percentage;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final label = t('discounts.discountName');
    final arLabel = t('bilingualField.arabicLabel', args: {'label': label});

    Widget text({
      required String value,
      required ValueChanged<String> onChanged,
      required String semanticLabel,
      bool invalid = false,
      TextDirection? direction,
      TextInputType? keyboard,
      List<TextInputFormatter>? formatters,
    }) => DashTextInput(
      value: value,
      onChanged: onChanged,
      semanticLabel: semanticLabel,
      invalid: invalid,
      textDirection: direction,
      keyboardType: keyboard,
      inputFormatters: formatters,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
    );

    final en = _Field(
      label: label,
      error: e.name == null ? null : t(e.name!),
      child: text(
        value: _name,
        semanticLabel: label,
        invalid: e.name != null,
        direction: TextDirection.ltr,
        onChanged: (s) => setState(() => _name = s),
      ),
    );
    final ar = _Field(
      label: arLabel,
      child: text(
        value: _nameAr,
        semanticLabel: arLabel,
        direction: TextDirection.rtl,
        onChanged: (s) => setState(() => _nameAr = s),
      ),
    );
    // `grid gap-3 sm:grid-cols-2`: side by side from 640, stacked below.
    final names = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(child: en),
              Expanded(child: ar),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [en, ar],
          );

    final type = _Field(
      label: t('discounts.dtype'),
      child: DashSelect<String>(
        options: [
          DashOption(
            value: DiscountType.percentage,
            label: t('discounts.percentage'),
            icon: 'percent',
          ),
          DashOption(
            value: DiscountType.fixed,
            label: t('discounts.fixed'),
            icon: 'banknote',
          ),
        ],
        value: _dtype,
        semanticLabel: t('discounts.dtype'),
        leadingIcon: pct ? 'percent' : 'banknote',
        // Switching keeps the typed number as it is (OFFR-DSC-045).
        onChanged: (v) => setState(() => _dtype = v),
      ),
    );
    final valueLabel = pct
        ? t('discounts.percentageValue')
        : t('discounts.amountValue');
    final value = _Field(
      label: valueLabel,
      hint: pct ? t('discounts.percentHint') : t('discounts.fixedHint'),
      error: e.value == null ? null : t(e.value!),
      child: text(
        value: _value,
        semanticLabel: valueLabel,
        invalid: e.value != null,
        direction: TextDirection.ltr,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        formatters: const [_NumberText()],
        onChanged: (s) => setState(() => _value = s),
      ),
    );

    final active = DecoratedBox(
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.md),
        child: Row(
          spacing: Space.md,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: DashMetrics.hair,
                children: [
                  Text(
                    t('common.active'),
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    t('discounts.activeHint'),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            DashSwitch(
              value: _active,
              semanticLabel: t('common.active'),
              onChanged: (on) => setState(() => _active = on),
            ),
          ],
        ),
      ),
    );

    return DashSurface(
      title: _discount == null
          ? t('discounts.newTitle')
          : t('discounts.editTitle'),
      description: t('discounts.subtitle'),
      onClose: _close,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.lg,
        children: [
          names,
          // `grid grid-cols-2 gap-3` at every width.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(child: type),
              Expanded(child: value),
            ],
          ),
          active,
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: _close,
        ),
        DashButton(
          label: _discount == null ? t('common.create') : t('common.save'),
          loading: _saving,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// What the number box takes (`type="number"`): digits, a point and a
/// minus; Arabic-Indic digits are read as Western ones.
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

/// A label, the control, its quiet hint, then its red line (both show: the
/// web's value field keeps the hint above the rule's message).
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.child,
    this.hint,
    this.error,
  });

  final String label;
  final Widget child;
  final String? hint;
  final String? error;

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
            style: DashType.bodyMedium.copyWith(
              color: error == null ? c.textPrimary : c.errorText,
            ),
          ),
        ),
        child,
        if (hint != null)
          Text(hint!, style: DashType.small.copyWith(color: c.textSecondary)),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: DashType.small.copyWith(color: c.errorText),
            ),
          ),
      ],
    );
  }
}
