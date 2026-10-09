/// `/settings/kitchen-stations` Kitchen stations (web
/// `features/kitchen-stations/stations-page.tsx`, SET-KST-001..024): the
/// header branch's routing mode ("Where tickets show") and its stations,
/// with the station editor and delete.
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane. Nothing is gated in the client: the
/// rail hides the pane without `kitchen.stations.edit`, and by URL the reads
/// 403 into the table's error and the writes toast the refusal (SET-KST-022).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show KitchenStation, SetRoutingModeRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kitchen_data.dart';
import 'station_dialog.dart';

/// The mode select's width (`w-40`).
const double kitchenSelectWidth = Space.xxl * 5;

class KitchenStationsPage extends ConsumerStatefulWidget {
  const KitchenStationsPage({super.key});

  @override
  ConsumerState<KitchenStationsPage> createState() =>
      _KitchenStationsPageState();
}

class _KitchenStationsPageState extends ConsumerState<KitchenStationsPage> {
  void _open(String branchId, [KitchenStation? s]) =>
      showStationDialog(context, branchId: branchId, station: s);

  Future<void> _remove(KitchenStation s) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).kitchen;
    final bus = ref.read(realtimeBusProvider);
    final ok = await showDashConfirm(
      context,
      title: t('common.confirmDelete', args: {'name': s.name}),
      description: t('kitchen.deleteStationConsequence'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await api.deleteStation(id: s.id);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
      return;
    }
    invalidateStations(bus);
    if (mounted) DashToast.success(context, t('kitchen.stationDeleted'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final branchId = ref.watch(currentScopeProvider.select((s) => s.branchId));
    if (branchId == null) {
      return DashPageScaffold(
        title: t('kitchen.stationsTitle'),
        subtitle: t('kitchen.stationsSubtitle'),
        width: DashPageWidth.reading,
        body: DashEmptyState(
          key: const ValueKey('kitchen-pick-branch'),
          icon: 'store',
          title: t('kitchen.pickBranch'),
        ),
      );
    }
    final list = ref.watch(kitchenStationsProvider(branchId));
    final loading = list.awaitingFirst;
    final error = list.failedFirst ? list.error : null;
    final newStation = DashButton(
      key: const ValueKey('kitchen-new-station'),
      label: t('kitchen.newStation'),
      icon: 'plus',
      onPressed: () => _open(branchId),
    );
    return DashPageScaffold(
      title: t('kitchen.stationsTitle'),
      subtitle: t('kitchen.stationsSubtitle'),
      width: DashPageWidth.reading,
      actions: [newStation],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          RoutingModeBar(branchId: branchId),
          StationsTable(
            stations: list.value ?? const [],
            loading: loading,
            errorText: error == null ? null : errorMessage(error, t),
            onRetry: () => ref.invalidate(kitchenStationsProvider(branchId)),
            onEdit: (s) => _open(branchId, s),
            onDelete: _remove,
            emptyAction: DashButton(
              key: const ValueKey('kitchen-empty-new-station'),
              label: t('kitchen.newStation'),
              icon: 'plus',
              onPressed: () => _open(branchId),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Where tickets show": the effective mode and the stored one, which saves
/// as soon as it is chosen (SET-KST-003..006, -023). The read has no loading
/// or error state of its own: until it answers the select reads "Auto" and
/// no "Now:" pill shows.
class RoutingModeBar extends ConsumerStatefulWidget {
  const RoutingModeBar({required this.branchId, super.key});

  final String branchId;

  @override
  ConsumerState<RoutingModeBar> createState() => _RoutingModeBarState();
}

class _RoutingModeBarState extends ConsumerState<RoutingModeBar> {
  Future<void> _set(String value) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).kitchen;
    final bus = ref.read(realtimeBusProvider);
    try {
      await api.setRoutingMode(
        body: SetRoutingModeRequest(
          branchId: widget.branchId,
          mode: value == 'auto' ? null : value,
          explicitNulls: const {'mode'},
        ),
      );
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
      return;
    }
    invalidateRouting(bus);
    if (mounted) DashToast.success(context, t('kitchen.modeUpdated'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final mode = ref.watch(kitchenRoutingModeProvider(widget.branchId)).value;
    final effective = mode?.effective ?? '';
    final pill = effective.isEmpty
        ? null
        : DashStatusPill(
            key: const ValueKey('kitchen-effective'),
            label:
                '${t('kitchen.effective')}: '
                '${t.exists('kitchen.mode.$effective') ? t('kitchen.mode.$effective') : effective}',
            tone: DashTone.info,
          );
    final select = DashSelect<String>(
      key: const ValueKey('kitchen-mode'),
      value: mode?.mode ?? 'auto',
      width: kitchenSelectWidth,
      expand: false,
      semanticLabel: t('kitchen.routingMode'),
      options: [
        for (final m in kitchenModes)
          DashOption(
            value: m,
            // The select says "POS queue" where the pill says "Till queue".
            label: t(
              m == 'till' ? 'kitchenStations.routing.till' : 'kitchen.mode.$m',
            ),
          ),
      ],
      onChanged: _set,
    );
    final header = DashSectionHeader(
      title: t('kitchen.routingMode'),
      description: t('kitchen.routingModeHint'),
    );
    final controls = Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [?pill, select],
    );
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    return Container(
      key: const ValueKey('kitchen-mode-bar'),
      padding: EdgeInsets.symmetric(
        horizontal: wide ? Space.card : Space.lg,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      // `flex-wrap`: the controls sit beside the words while the words keep
      // their 240 basis, else they drop under them.
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= _barRowWidth
            ? Row(
                spacing: Space.md,
                children: [
                  Expanded(child: header),
                  controls,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.md,
                children: [header, controls],
              ),
      ),
    );
  }
}

/// The bar's width from which the words (`basis-60`) and the controls (the
/// pill and the select) share a line.
const double _barRowWidth = 240 + Space.md + 2 * kitchenSelectWidth;

/// The stations table (SET-KST-007..013, -020): Name (a "Default" pill on
/// the default station), Printer, Status; the pencil and the trash; a client
/// search over the name and the printer model; ten a page; phone cards.
class StationsTable extends ConsumerWidget {
  const StationsTable({
    required this.stations,
    required this.loading,
    required this.errorText,
    required this.onRetry,
    required this.onEdit,
    required this.onDelete,
    required this.emptyAction,
    super.key,
  });

  final List<KitchenStation> stations;
  final bool loading;
  final String? errorText;
  final VoidCallback onRetry;
  final ValueChanged<KitchenStation> onEdit;
  final ValueChanged<KitchenStation> onDelete;
  final Widget emptyAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return DashDataTable<KitchenStation>(
      key: const ValueKey('kitchen-stations-table'),
      rows: stations,
      rowKey: (s) => s.id,
      loading: loading,
      errorMessage: errorText,
      onRetry: onRetry,
      onRowTap: onEdit,
      hideViewOptions: true,
      searchPlaceholder: t('common.search'),
      rowSemanticLabel: (s) => s.name,
      empty: DashEmptyState(
        key: const ValueKey('kitchen-no-stations'),
        icon: 'chef-hat',
        title: t('kitchen.noStations'),
        description: t('kitchen.noStationsHint'),
        action: emptyAction,
      ),
      rowActions: (context, s) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DashIconButton(
            key: ValueKey('kitchen-edit-${s.id}'),
            icon: 'pencil',
            semanticLabel: t('common.edit'),
            onPressed: () => onEdit(s),
          ),
          DashIconButton(
            key: ValueKey('kitchen-delete-${s.id}'),
            icon: 'trash-2',
            semanticLabel: t('common.delete'),
            color: c.danger,
            onPressed: () => onDelete(s),
          ),
        ],
      ),
      rowActionsWidth: 2 * DashMetrics.target + Space.lg,
      columns: [
        DashColumn<KitchenStation>(
          id: 'name',
          label: t('kitchen.stationName'),
          phone: DashPhoneRole.title,
          flex: 2,
          text: (s) => s.name,
          cell: (context, s) => Row(
            spacing: Space.sm,
            children: [
              Flexible(
                child: MadarClippedText(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                ),
              ),
              if (s.isDefault)
                DashStatusPill(
                  key: ValueKey('kitchen-default-${s.id}'),
                  label: t('kitchen.default'),
                  tone: DashTone.accent,
                  icon: 'star',
                  small: true,
                ),
            ],
          ),
        ),
        // Searched by the model as stored ("epson"); the address is not.
        DashColumn<KitchenStation>(
          id: 'printer_brand',
          label: t('branches.printer'),
          flex: 2,
          minWidth: 180,
          text: (s) => s.printerBrand?.value ?? '',
          cell: (context, s) => StationPrinter(station: s),
        ),
        DashColumn<KitchenStation>(
          id: 'is_active',
          label: t('common.status'),
          searchable: false,
          cell: (context, s) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashStatusPill(
              label: t(s.isActive ? 'common.active' : 'common.inactive'),
              tone: s.isActive ? DashTone.success : DashTone.neutral,
            ),
          ),
        ),
      ],
    );
  }
}

/// The Printer cell: the glyph, the model and the address ("Epson ·
/// 192.168.1.60", the address left to right); "—" with none.
class StationPrinter extends StatelessWidget {
  const StationPrinter({required this.station, super.key});

  final KitchenStation station;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final style = DashType.body.copyWith(color: c.textSecondary);
    final brand = station.printerBrand;
    if (brand == null) return Text('—', style: style);
    final ip = station.printerIp;
    return Row(
      spacing: Space.xs + DashMetrics.hair,
      children: [
        DashIcon('printer', size: IconSize.xs, color: c.textSecondary),
        Flexible(
          child: MadarClippedText.rich(
            TextSpan(
              children: [
                TextSpan(text: printerBrandLabel(brand)),
                if (ip != null && ip.isNotEmpty) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: ltr(ip),
                    style: DashType.mono.copyWith(
                      fontSize: style.fontSize,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
