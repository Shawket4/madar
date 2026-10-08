/// The supplier dialog (INV-PUR-052…057, web `supplier-dialog.tsx`): New
/// supplier, or Edit supplier with the Active switch. Save is off while the
/// name is blank; the others are sent trimmed or null.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show CreateSupplierRequest, Supplier, UpdateSupplierRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';

/// Opens the dialog for [orgId]: a new supplier, or [supplier] to edit; true
/// once saved (inventory invalidated, toast shown).
Future<bool?> showSupplierDialog(
  BuildContext context, {
  required String orgId,
  Supplier? supplier,
}) => showDashDialog<bool>(
  context,
  builder: (_) => SupplierDialog(orgId: orgId, supplier: supplier),
);

class SupplierDialog extends ConsumerStatefulWidget {
  const SupplierDialog({required this.orgId, this.supplier, super.key});

  final String orgId;
  final Supplier? supplier;

  @override
  ConsumerState<SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends ConsumerState<SupplierDialog> {
  late String _name = widget.supplier?.name ?? '';
  late String _contact = widget.supplier?.contactName ?? '';
  late String _email = widget.supplier?.email ?? '';
  late String _phone = widget.supplier?.phone ?? '';
  late bool _active = widget.supplier?.isActive ?? true;
  bool _busy = false;

  bool get _editing => widget.supplier != null;

  String? _orNull(String v) => v.trim().isEmpty ? null : v.trim();

  Future<void> _submit() async {
    if (_name.trim().isEmpty) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).purchasing;
    setState(() => _busy = true);
    final nulls = {
      if (_orNull(_contact) == null) 'contact_name',
      if (_orNull(_email) == null) 'email',
      if (_orNull(_phone) == null) 'phone',
    };
    try {
      if (_editing) {
        await api.updateSupplier(
          id: widget.supplier!.id,
          body: UpdateSupplierRequest(
            name: _name.trim(),
            contactName: _orNull(_contact),
            email: _orNull(_email),
            phone: _orNull(_phone),
            isActive: _active,
            explicitNulls: nulls,
          ),
        );
      } else {
        await api.createSupplier(
          orgId: widget.orgId,
          body: CreateSupplierRequest(
            name: _name.trim(),
            contactName: _orNull(_contact),
            email: _orNull(_email),
            phone: _orNull(_phone),
            explicitNulls: nulls,
          ),
        );
      }
      invalidateInventory(ref);
      if (!mounted) return;
      DashToast.success(context, t('common.savedChanges'));
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return DashSurface(
      title: _editing
          ? t('inventory.purchasing.editSupplier')
          : t('inventory.purchasing.newSupplier'),
      description: t('inventory.purchasing.suppliers'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          DashTextField(
            key: const ValueKey('supplier-name'),
            label: t('inventory.purchasing.supplier'),
            value: _name,
            autofocus: true,
            onChanged: (v) => setState(() => _name = v),
          ),
          DashTextField(
            key: const ValueKey('supplier-contact'),
            label: t('inventory.purchasing.contactName'),
            value: _contact,
            onChanged: (v) => setState(() => _contact = v),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(
                child: DashTextField(
                  key: const ValueKey('supplier-email'),
                  label: t('inventory.purchasing.email'),
                  value: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  onChanged: (v) => setState(() => _email = v),
                ),
              ),
              Expanded(
                child: DashTextField(
                  key: const ValueKey('supplier-phone'),
                  label: t('inventory.purchasing.phone'),
                  value: _phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  onChanged: (v) => setState(() => _phone = v),
                ),
              ),
            ],
          ),
          if (_editing)
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: c.hairline),
              ),
              child: DashSwitchField(
                key: const ValueKey('supplier-active'),
                label: t('inventory.purchasing.supplierActive'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DashButton(
          key: const ValueKey('supplier-save'),
          label: t('common.save'),
          loading: _busy,
          onPressed: _name.trim().isEmpty ? null : _submit,
        ),
      ],
    );
  }
}
