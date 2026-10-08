/// The Suppliers tab (INV-PUR-017…021, -059): every supplier of the org
/// (inactive ones too), searchable; ⋯ Edit / Delete per row. No row click.
library;

import 'package:dashboard_api/dashboard_api.dart' show Supplier;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';
import 'purchasing_data.dart';
import 'supplier_dialog.dart';

class SuppliersTab extends ConsumerWidget {
  const SuppliersTab({required this.orgId, super.key});

  final String orgId;

  Future<void> _delete(BuildContext context, WidgetRef ref, Supplier s) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t(
        'inventory.purchasing.deleteSupplierConfirm',
        args: {'name': s.name},
      ),
      description: t('inventory.purchasing.deleteSupplierConsequence'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(apiProvider).purchasing.deleteSupplier(id: s.id);
      invalidateInventory(ref);
      if (context.mounted) DashToast.success(context, t('common.done'));
    } on Object catch (e) {
      if (context.mounted) DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final async = ref.watch(inventorySuppliersProvider(orgId));

    Widget orDash(String? v, {bool mono = false}) => MadarClippedText(
      v ?? '—',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textDirection: mono && v != null ? TextDirection.ltr : null,
      style: (mono && v != null ? DashType.mono : DashType.body).copyWith(
        color: c.textPrimary,
      ),
    );

    return DashDataTable<Supplier>(
      key: const ValueKey('supplier-table'),
      columns: [
        DashColumn(
          id: 'name',
          label: t('inventory.purchasing.supplier'),
          text: (s) => s.name,
          cell: (context, s) => MadarClippedText(
            s.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
          phone: DashPhoneRole.title,
          minWidth: Space.xxl * 4,
        ),
        DashColumn(
          id: 'contact_name',
          label: t('inventory.purchasing.contactName'),
          text: (s) => s.contactName ?? '',
          cell: (context, s) => orDash(s.contactName),
          minWidth: Space.xxl * 4,
        ),
        DashColumn(
          id: 'email',
          label: t('inventory.purchasing.email'),
          text: (s) => s.email ?? '',
          cell: (context, s) => orDash(s.email),
          minWidth: Space.xxl * 5,
        ),
        DashColumn(
          id: 'phone',
          label: t('inventory.purchasing.phone'),
          text: (s) => s.phone ?? '',
          cell: (context, s) => orDash(s.phone, mono: true),
          numeric: true,
          align: DashAlign.start,
          minWidth: Space.xxl * 4,
        ),
        DashColumn(
          id: 'is_active',
          label: t('common.status'),
          text: (s) => s.isActive ? t('common.active') : t('common.inactive'),
          cell: (context, s) => s.isActive
              ? DashStatusPill(
                  label: t('common.active'),
                  tone: DashTone.success,
                )
              : DashStatusPill(
                  label: t('common.inactive'),
                  icon: 'minus-circle',
                ),
          searchable: false,
          minWidth: Space.xxl * 3,
        ),
      ],
      rows: async.value ?? const [],
      rowKey: (s) => s.id,
      loading: async.firstLoad,
      errorMessage: async.errorText(t),
      onRetry: () => ref.invalidate(inventorySuppliersProvider(orgId)),
      searchPlaceholder: t('common.search'),
      empty: DashEmptyState(
        icon: 'users',
        title: t('inventory.purchasing.noSuppliers'),
      ),
      rowActions: (context, s) => DashMenu(
        key: ValueKey('supplier-menu-${s.id}'),
        items: [
          DashMenuItem(
            label: t('common.edit'),
            onSelected: () =>
                showSupplierDialog(context, orgId: orgId, supplier: s),
          ),
          DashMenuItem(
            label: t('common.delete'),
            destructive: true,
            onSelected: () => _delete(context, ref, s),
          ),
        ],
        builder: (context, ctl) => DashIconButton(
          icon: 'more-horizontal',
          semanticLabel: t('common.moreActions'),
          onPressed: ctl.toggle,
        ),
      ),
    );
  }
}
