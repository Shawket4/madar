/// `/settings/delivery-zones` Delivery zones (SET-DZN-001..022; web
/// `features/delivery/zones-page.tsx`): the header branch's rings, closest
/// first and numbered, with New zone, edit (row tap or pencil) and delete
/// (confirmed).
///
/// Rendered inside the settings shell (`routes.dart`). No client gate (the
/// pane has no rail entry and no capability on the web): the server refuses
/// what the person may not do.
library;

import 'package:dashboard_api/dashboard_api.dart' show DeliveryZone;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'delivery_data.dart';
import 'zone_dialog.dart';

class DeliveryZonesPage extends ConsumerStatefulWidget {
  const DeliveryZonesPage({super.key});

  @override
  ConsumerState<DeliveryZonesPage> createState() => _DeliveryZonesPageState();
}

class _DeliveryZonesPageState extends ConsumerState<DeliveryZonesPage> {
  void _open(String branchId, DeliveryZone? zone) => showZoneDialog(
    context,
    branchId: branchId,
    zone: zone,
    zones: ref.read(deliveryZonesProvider(branchId)).value ?? const [],
  );

  /// The dialog reads the branch's zones (its defaults, its refreshes).
  void _warm(String branchId) => ref.warm(deliveryZonesProvider(branchId));

  Future<void> _remove(String branchId, DeliveryZone z) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      // The stored name, which may differ from the "Zone N" on the row.
      title: t('delivery.deleteZoneTitle', args: {'name': z.name}),
      description: t('delivery.deleteZoneHint'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider).delivery;
    final bus = ref.read(realtimeBusProvider);
    try {
      await api.deleteZone(id: z.id, branchId: branchId);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
      return;
    }
    invalidateZones(bus);
    if (mounted) DashToast.success(context, t('delivery.zoneDeleted'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
    return DashPageScaffold(
      title: t('delivery.zonesTitle'),
      subtitle: t('delivery.zonesSubtitle'),
      width: DashPageWidth.reading,
      actions: [
        if (branchId != null)
          DashButton(
            key: const ValueKey('dzn-new'),
            label: t('delivery.newZone'),
            icon: 'plus',
            onIntent: () => _warm(branchId),
            onPressed: () => _open(branchId, null),
          ),
      ],
      body: branchId == null
          ? DashEmptyState(icon: 'store', title: t('delivery.pickBranch'))
          : _table(t, branchId),
    );
  }

  Widget _table(Translator t, String branchId) {
    final q = ref.watch(deliveryZonesProvider(branchId));
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    return DashDataTable<NumberedZone>(
      key: const ValueKey('dzn-table'),
      rows: numberZones(q.value ?? const []),
      rowKey: (z) => z.zone.id,
      loading: q.awaitingFirst,
      errorMessage: q.failedFirst ? errorMessage(q.error, t) : null,
      onRetry: () => ref.invalidate(deliveryZonesProvider(branchId)),
      hideViewOptions: true,
      onRowTap: (z) => _open(branchId, z.zone),
      onRowIntent: (_) => _warm(branchId),
      rowSemanticLabel: (z) => zoneLabel(t, z.number),
      rowActionsWidth: DashMetrics.target * 2 + Space.sm,
      rowActions: (context, z) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DashIconButton(
            key: ValueKey('dzn-edit-${z.zone.id}'),
            icon: 'pencil',
            semanticLabel: t('common.edit'),
            onIntent: () => _warm(branchId),
            onPressed: () => _open(branchId, z.zone),
          ),
          DashIconButton(
            key: ValueKey('dzn-delete-${z.zone.id}'),
            icon: 'trash-2',
            semanticLabel: t('common.delete'),
            color: c.danger,
            onPressed: () => _remove(branchId, z.zone),
          ),
        ],
      ),
      empty: DashEmptyState(
        icon: 'map-pin',
        title: t('delivery.noZones'),
        description: t('delivery.noZonesHint'),
        action: DashButton(
          key: const ValueKey('dzn-empty-new'),
          label: t('delivery.newZone'),
          icon: 'plus',
          onIntent: () => _warm(branchId),
          onPressed: () => _open(branchId, null),
        ),
      ),
      columns: [
        DashColumn<NumberedZone>(
          id: 'zoneNumber',
          label: t('delivery.zone'),
          phone: DashPhoneRole.title,
          flex: 3,
          minWidth: 180,
          text: (z) => zoneLabel(t, z.number),
          cell: (context, z) => ZoneCell(zone: z),
        ),
        DashColumn<NumberedZone>(
          id: 'max_road_distance_meters',
          label: t('delivery.maxDistance'),
          numeric: true,
          text: (z) =>
              '${fmt.fmtNumber(z.zone.maxRoadDistanceMeters / 1000, const NumberOptions(maximumFractionDigits: 1))} '
              '${t('delivery.kmUnit')}',
        ),
        DashColumn<NumberedZone>(
          id: 'fee',
          label: t('delivery.zoneFeeShort'),
          numeric: true,
          text: (z) => fmt.fmtMoney(z.zone.fee),
        ),
        DashColumn<NumberedZone>(
          id: 'is_active',
          label: t('common.status'),
          cell: (context, z) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashStatusPill(
              label: t(z.zone.isActive ? 'common.active' : 'common.inactive'),
              tone: z.zone.isActive ? DashTone.success : DashTone.neutral,
            ),
          ),
        ),
      ],
    );
  }
}

/// The Zone cell: the ring number on a square badge, "Zone N" in bold, and
/// the zone's own name under it only when it says something else.
class ZoneCell extends ConsumerWidget {
  const ZoneCell({required this.zone, super.key});

  final NumberedZone zone;

  /// The badge (`size-8`).
  static const double badge = Space.xxl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final label = zoneLabel(t, zone.number);
    final name = zone.zone.name;
    return Row(
      spacing: Space.md,
      children: [
        Container(
          width: badge,
          height: badge,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
          child: Text(
            '${zone.number}',
            style: DashType.mono.copyWith(
              color: c.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MadarClippedText(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyMedium.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (name.isNotEmpty && name != label)
                MadarClippedText(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
