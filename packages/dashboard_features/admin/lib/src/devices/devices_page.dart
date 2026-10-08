/// `/devices` Devices (ADM-DEV-001..029): the branch's devices with the edit
/// dialog and the activation codes section, and the Client versions view
/// (`?view=clients`, `?days=7|30|90`, `?all=true`). POS module only. Web:
/// `features/devices/{devices-page,activation-codes,api}.tsx`.
///
/// No route guard and no `<Restricted>`: whoever reaches the URL sees the
/// page; the server refuses what they may not read (the Client versions
/// read without `branches.edit`, ADM-DEV-027) or change (Save, ADM-DEV-013).
library;

import 'package:dashboard_api/dashboard_api.dart' show Device;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/url_params.dart';
import 'activation_codes.dart';
import 'client_versions.dart';
import 'device_dialog.dart';
import 'devices_data.dart';
import 'devices_table.dart';

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  static const String path = '/devices';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final branchId = ref.watch(currentScopeProvider.select((s) => s.branchId));
    final search = DevicesSearch.parse(
      GoRouterState.of(context).uri.queryParameters,
    );
    final view = search.effectiveView;

    // `usePageSearch().update`: merge into the current query (scope params
    // and the other page params stay).
    void update(Map<String, String?> changes) =>
        context.setQueryParams(changes);

    final Widget body;
    if (view == DevicesView.clients) {
      body = ClientVersionsView(
        branchId: branchId,
        days: search.effectiveDays,
        legacyOnly: search.legacyOnly,
        onDays: (d) => update({'days': d == defaultClientWindow ? null : '$d'}),
        onLegacyOnly: (on) => update({'all': on ? null : 'true'}),
      );
    } else if (branchId == null) {
      body = DashEmptyState(
        key: const ValueKey('devices-pick-branch'),
        icon: 'tablet',
        title: t('tills.pickBranch'),
        description: t('devices.pickBranchHint'),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xxl,
        children: [
          DevicesSection(
            branchId: branchId,
            onEdit: (Device d) => showDeviceDialog(context, d),
          ),
          ActivationCodesSection(branchId: branchId),
        ],
      );
    }

    return DashPageScaffold(
      title: t('devices.title'),
      subtitle: t('devices.subtitle'),
      tabs: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DashSegmentedControl<DevicesView>(
          key: const ValueKey('devices-view'),
          value: view,
          options: [
            DashOption(
              value: DevicesView.devices,
              label: t('devices.tabDevices'),
            ),
            DashOption(
              value: DevicesView.clients,
              label: t('devices.clients.title'),
            ),
          ],
          onChanged: (v) =>
              update({'view': v == DevicesView.devices ? null : 'clients'}),
        ),
      ),
      body: body,
    );
  }
}
