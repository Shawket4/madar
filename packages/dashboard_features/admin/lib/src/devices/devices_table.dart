/// The branch's devices (web `devices-page.tsx` `DevicesSection` /
/// `DevicesTable`, ADM-DEV-004..009): 20 a page, no search, no Columns menu;
/// a row (or its pencil) opens the Edit device dialog.
library;

import 'package:dashboard_api/dashboard_api.dart' show Device, DeviceKind;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/row_action.dart';
import 'devices_data.dart';

/// `devices.kinds.<kind>`, or the raw kind a newer server sent.
String deviceKindLabel(Translator t, DeviceKind kind) {
  final key = 'devices.kinds.${kind.value}';
  return t.exists(key) ? t(key) : kind.value;
}

/// The muted "—" an empty cell shows.
class DevicesDash extends StatelessWidget {
  const DevicesDash({super.key});

  @override
  Widget build(BuildContext context) => Text(
    '—',
    style: DashType.body.copyWith(color: context.madarColors.textSecondary),
  );
}

class DevicesSection extends ConsumerWidget {
  const DevicesSection({
    required this.branchId,
    required this.onEdit,
    super.key,
  });

  final String branchId;
  final ValueChanged<Device> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final q = ref.watch(devicesListProvider(branchId));
    final error = q.shownError;
    return DevicesTable(
      devices: q.value ?? const [],
      loading: q.firstLoad,
      errorMessage: error == null ? null : devicesErrorText(error, t),
      onRetry: () => ref.invalidate(devicesListProvider(branchId)),
      onEdit: onEdit,
    );
  }
}

class DevicesTable extends ConsumerWidget {
  const DevicesTable({
    required this.devices,
    required this.onEdit,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    super.key,
  });

  final List<Device> devices;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final ValueChanged<Device> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final muted = DashType.body.copyWith(color: c.textSecondary);
    String app(Device d) => [
      d.platform,
      d.appVersion,
    ].where((s) => s != null && s.isNotEmpty).join(' · ');
    return DashDataTable<Device>(
      key: const ValueKey('devices-table'),
      rows: devices,
      rowKey: (d) => d.id,
      loading: loading,
      errorMessage: errorMessage,
      onRetry: onRetry,
      onRowTap: onEdit,
      hideViewOptions: true,
      pageSize: 20,
      rowSemanticLabel: (d) => d.label == null ? d.code : '${d.code} ${d.label}',
      rowActions: (context, d) => AdminRowAction(
        icon: 'pencil',
        label: t('common.edit'),
        onPressed: () => onEdit(d),
      ),
      empty: DashEmptyState(
        icon: 'tablet',
        title: t('devices.empty'),
        description: t('devices.emptyHint'),
      ),
      columns: [
        DashColumn<Device>(
          id: 'code',
          label: t('devices.code'),
          text: (d) => d.code,
          phone: DashPhoneRole.title,
          flex: 2,
          minWidth: 200,
          cell: (context, d) => Wrap(
            key: ValueKey('device-row-${d.id}'),
            spacing: Space.sm,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                d.code,
                style: DashType.monoStrong.copyWith(color: c.textPrimary),
              ),
              if (d.codeConflict)
                DashStatusPill(
                  key: ValueKey('code-conflict-${d.id}'),
                  label: t('devices.codeConflict'),
                  tone: DashTone.warning,
                  small: true,
                ),
            ],
          ),
        ),
        DashColumn<Device>(
          id: 'label',
          label: t('devices.label'),
          text: (d) => d.label ?? '',
          cell: (context, d) => d.label == null
              ? const DevicesDash()
              : MadarClippedText(
                  d.label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.body.copyWith(color: c.textPrimary),
                ),
        ),
        DashColumn<Device>(
          id: 'kind',
          label: t('devices.kind'),
          text: (d) => deviceKindLabel(t, d.kind),
        ),
        DashColumn<Device>(
          id: 'app',
          label: t('devices.app'),
          text: app,
          cell: (context, d) => MadarClippedText(
            app(d).isEmpty ? '—' : app(d),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ),
        DashColumn<Device>(
          id: 'state',
          label: t('common.status'),
          text: (d) => d.retiredAt != null
              ? t('devices.retired')
              : t('devices.active'),
          cell: (context, d) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: d.retiredAt != null
                ? DashStatusPill(label: t('devices.retired'), small: true)
                : DashStatusPill(
                    label: t('devices.active'),
                    tone: DashTone.success,
                    small: true,
                  ),
          ),
        ),
        DashColumn<Device>(
          id: 'last_seen_at',
          label: t('devices.lastSeen'),
          numeric: true,
          text: (d) => fmt.fmtStamp(d.lastSeenAt),
        ),
      ],
    );
  }
}
