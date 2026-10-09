/// Add a customer, or edit one (the web's
/// `features/customers/customer-dialog.tsx`, SELL-CUS-022 … 025, 032): the
/// same form both ways; a phone another customer already has comes back as a
/// 409 and is shown on the phone field.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/phone.dart';
import 'customers_data.dart';

/// Opens the form: [customer] present = edit it; absent = add one.
/// Resolves with the saved customer, or null when cancelled. [onSaved] runs
/// on success even when the dialog was closed while it saved, and the toast
/// then shows through the opener's [context] (the web's mutation outlives
/// its dialog).
Future<CustomerDetail?> showCustomerDialog(
  BuildContext context, {
  Customer? customer,
  ValueChanged<CustomerDetail>? onSaved,
}) => showDashDialog<CustomerDetail>(
  context,
  builder: (_) =>
      CustomerDialog(customer: customer, onSaved: onSaved, host: context),
);

class CustomerDialog extends ConsumerStatefulWidget {
  const CustomerDialog({this.customer, this.onSaved, this.host, super.key});

  final Customer? customer;
  final ValueChanged<CustomerDetail>? onSaved;

  /// The opener's context: it outlives the dialog, so a save that finishes
  /// after the dialog closed still toasts.
  final BuildContext? host;

  @override
  ConsumerState<CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends ConsumerState<CustomerDialog> {
  final _form = GlobalKey<FormState>();
  final _phoneFocus = FocusNode();
  late String _name = widget.customer?.name ?? '';
  late String _phone = widget.customer?.phone ?? '';
  late String _notes = widget.customer?.notes ?? '';
  String? _phoneServerError;
  bool _pending = false;

  /// Typed into: from then on a fresher copy of the customer no longer
  /// re-seeds the form.
  bool _dirty = false;

  /// The copy the form was last seeded from.
  CustomerDetail? _from;

  bool get _editing => widget.customer != null;

  /// Toasts here, or through the opener once the dialog has closed.
  void _toast(String words, {bool error = false}) {
    final at = mounted ? context : widget.host;
    if (at == null || !at.mounted) return;
    if (error) {
      DashToast.error(at, words);
    } else {
      DashToast.success(at, words);
    }
  }

  @override
  void dispose() {
    _phoneFocus.dispose();
    super.dispose();
  }

  String? _nameError(String v, Translator t) {
    final n = v.trim();
    if (n.isEmpty) {
      return t('customers.errors.nameRequired', args: {'max': customerNameMax});
    }
    if (n.length > customerNameMax) {
      return t('customers.errors.nameLong', args: {'max': customerNameMax});
    }
    return null;
  }

  String? _phoneError(String v, Translator t) {
    final p = v.trim();
    if (p.isEmpty || isValidPhone(p)) return null;
    return t('customers.errors.phoneInvalid', args: {'max': customerNameMax});
  }

  String? _notesError(String v, Translator t) =>
      v.trim().length > customerNotesMax
      ? t('customers.errors.notesLong', args: {'max': customerNotesMax})
      : null;

  Future<void> _submit() async {
    final t = ref.read(tProvider);
    setState(() => _phoneServerError = null);
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _pending = true);
    final api = ref.read(apiProvider).customers;
    final invalidate = peopleInvalidator(ref);
    try {
      final c = widget.customer;
      final detail = c == null
          ? await api.createCustomer(
              body: CreateCustomerRequest(
                name: _name.trim(),
                phone: _phone.trim().isEmpty ? null : _phone.trim(),
                notes: _notes.trim().isEmpty ? null : _notes.trim(),
                explicitNulls: {
                  if (_phone.trim().isEmpty) 'phone',
                  if (_notes.trim().isEmpty) 'notes',
                },
              ),
            )
          : await api.updateCustomer(
              id: c.id,
              // PATCH semantics: "" clears phone and notes.
              body: UpdateCustomerRequest(
                name: _name.trim(),
                phone: _phone.trim(),
                notes: _notes.trim(),
              ),
            );
      invalidate();
      _toast(_editing ? t('customers.saved') : t('customers.created'));
      if (mounted) Navigator.of(context).pop(detail);
      widget.onSaved?.call(detail);
    } on Object catch (e) {
      if (mounted && isPhoneTaken(e)) {
        setState(() => _phoneServerError = t('customers.errors.phoneTaken'));
        _phoneFocus.requestFocus();
        return;
      }
      _toast(peopleErrorMessage(e, t), error: true);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final optional = '(${t('common.optional')})';
    // Editing a cached copy: a background refresh landing re-seeds the form
    // until something is typed, so a stale copy is never saved over newer
    // data.
    if (widget.customer case final c?) {
      final fresh = ref.watch(customerDetailProvider(c.id)).value;
      if (!_dirty && fresh != null && !identical(fresh, _from)) {
        _from = fresh;
        _name = fresh.customer.name;
        _phone = fresh.customer.phone ?? '';
        _notes = fresh.customer.notes ?? '';
      }
    }
    return DashSurface(
      title: _editing ? t('customers.editTitle') : t('customers.addTitle'),
      description: t('customers.formHint'),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          label: _editing ? t('common.save') : t('customers.add'),
          loading: _pending,
          onPressed: _submit,
        ),
      ],
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            DashTextField(
              key: const ValueKey('customer-name'),
              label: t('customers.name'),
              value: _name,
              maxLength: customerNameMax,
              onChanged: (v) => setState(() {
                _name = v;
                _dirty = true;
              }),
              validator: (v) => _nameError(v, t),
            ),
            DashFormField<String>(
              key: const ValueKey('customer-phone'),
              label: t('customers.phone'),
              optionalText: optional,
              value: _phone,
              errorText: _phoneServerError,
              validator: (v) => _phoneError(v, t),
              builder: (context, invalid) => DashTextInput(
                value: _phone,
                focusNode: _phoneFocus,
                semanticLabel: t('customers.phone'),
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                mono: true,
                invalid: invalid,
                onChanged: (v) => setState(() {
                  _phone = v;
                  _phoneServerError = null;
                  _dirty = true;
                }),
              ),
            ),
            DashFormField<String>(
              key: const ValueKey('customer-notes'),
              label: t('customers.notes'),
              optionalText: optional,
              value: _notes,
              validator: (v) => _notesError(v, t),
              builder: (context, invalid) => DashTextInput(
                value: _notes,
                semanticLabel: t('customers.notes'),
                minLines: 3,
                maxLines: 6,
                invalid: invalid,
                onChanged: (v) => setState(() {
                  _notes = v;
                  _dirty = true;
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
