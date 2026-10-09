/// The station editor (web `station-dialog.tsx`, SET-KST-014..019, -024):
/// name, the printer block (model, IP and port when there is a printer), the
/// default and active switches. New → `POST /kitchen/stations` with the
/// branch; edit → `PATCH /kitchen/stations/{id}`. A success toasts "Station
/// created" / "Station updated", refetches `/kitchen/stations*` and closes;
/// a failure toasts the server's words and stays open. Below 760 wide it is
/// a full-screen sheet.
///
/// It opens on the station's values (or the defaults) each time, and while
/// nothing has been touched it follows a background refresh of the station.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        CreateStationRequest,
        KitchenStation,
        PrinterBrand,
        UpdateStationRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kitchen_data.dart';

/// Opens the editor for [station] (null = a new one at [branchId]); [host]
/// is the page, which shows the result's toast should the dialog be gone.
Future<void> showStationDialog(
  BuildContext host, {
  required String branchId,
  KitchenStation? station,
}) => showDashDialog<void>(
  host,
  builder: (_) =>
      StationDialog(branchId: branchId, station: station, host: host),
);

/// The printer model choice; `none` = no printer.
const String _noPrinter = 'none';

/// The port a new printer starts on.
const String _defaultPort = '9100';

class StationDialog extends ConsumerStatefulWidget {
  const StationDialog({
    required this.branchId,
    required this.station,
    this.host,
    super.key,
  });

  final String branchId;
  final KitchenStation? station;
  final BuildContext? host;

  @override
  ConsumerState<StationDialog> createState() => _StationDialogState();
}

class _StationDialogState extends ConsumerState<StationDialog> {
  final _form = GlobalKey<FormState>();
  String _name = '';
  String _brand = _noPrinter;
  String _ip = '';
  String _port = _defaultPort;
  bool _isDefault = false;
  bool _isActive = true;
  bool _saving = false;

  /// Touched by the person: a refresh no longer re-seeds.
  bool _dirty = false;

  /// The station version the form holds.
  DateTime? _seededAt;

  @override
  void initState() {
    super.initState();
    _seed(widget.station);
  }

  void _seed(KitchenStation? s) {
    _name = s?.name ?? '';
    _brand = s?.printerBrand?.value ?? _noPrinter;
    _ip = s?.printerIp ?? '';
    _port = '${s?.printerPort ?? _defaultPort}';
    _isDefault = s?.isDefault ?? false;
    _isActive = s?.isActive ?? true;
    _seededAt = s?.updatedAt;
  }

  void _edit(VoidCallback change) => setState(() {
    _dirty = true;
    change();
  });

  Future<void> _save() async {
    if (_saving) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).kitchen;
    final bus = ref.read(realtimeBusProvider);
    final host = widget.host;
    final hasPrinter = _brand != _noPrinter;
    final brand = hasPrinter ? PrinterBrand.fromJson(_brand) : null;
    final ip = hasPrinter && _ip.isNotEmpty ? _ip : null;
    // An emptied port is no port (the web's `numOrNull` intent).
    final port = hasPrinter ? int.tryParse(_port) : null;
    const nulls = {'printer_brand', 'printer_ip', 'printer_port'};
    final s = widget.station;
    setState(() => _saving = true);
    try {
      if (s != null) {
        await api.updateStation(
          id: s.id,
          body: UpdateStationRequest(
            name: _name.trim(),
            isDefault: _isDefault,
            isActive: _isActive,
            printerBrand: brand,
            printerIp: ip,
            printerPort: port,
            explicitNulls: nulls,
          ),
        );
      } else {
        await api.createStation(
          body: CreateStationRequest(
            branchId: widget.branchId,
            name: _name.trim(),
            isDefault: _isDefault,
            isActive: _isActive,
            printerBrand: brand,
            printerIp: ip,
            printerPort: port,
            explicitNulls: nulls,
          ),
        );
      }
    } on Object catch (e) {
      final at = mounted ? context : host;
      if (at != null && at.mounted) DashToast.error(at, errorMessage(e, t));
      if (mounted) setState(() => _saving = false);
      return;
    }
    invalidateStations(bus);
    final at = mounted ? context : host;
    if (at != null && at.mounted) {
      DashToast.success(
        at,
        t(s == null ? 'kitchen.stationCreated' : 'kitchen.stationUpdated'),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final id = widget.station?.id;
    if (id != null) {
      // A background refresh lands: follow it until the person edits.
      ref.listen(kitchenStationsProvider(widget.branchId), (_, next) {
        if (_dirty || _saving) return;
        for (final s in next.value ?? const <KitchenStation>[]) {
          if (s.id == id && s.updatedAt != _seededAt) {
            setState(() => _seed(s));
          }
        }
      });
    }
    final hasPrinter = _brand != _noPrinter;
    return Form(
      key: _form,
      child: DashSurface(
        title: t(id == null ? 'kitchen.newStation' : 'kitchen.editStation'),
        description: t('kitchen.stationSubtitle'),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            DashTextField(
              key: const ValueKey('station-name'),
              label: t('kitchen.stationName'),
              value: _name,
              placeholder: t('kitchen.stationNamePlaceholder'),
              onChanged: (v) => _edit(() => _name = v),
              onSubmitted: (_) => _save(),
              validator: (v) =>
                  v.isEmpty ? t('common.requiredField') : null,
            ),
            Container(
              key: const ValueKey('station-printer'),
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.xs),
                border: Border.all(color: c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.md,
                children: [
                  Row(
                    spacing: Space.sm,
                    children: [
                      DashIcon(
                        'printer',
                        size: IconSize.xs,
                        color: c.textSecondary,
                      ),
                      Expanded(
                        child: Text(
                          t('branches.printerConfig'),
                          style: DashType.bodyStrong.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  DashSelectField<String>(
                    key: const ValueKey('station-brand'),
                    label: t('branches.printerBrand'),
                    value: _brand,
                    options: [
                      DashOption(
                        value: _noPrinter,
                        label: t('branches.brands.none'),
                      ),
                      for (final b in PrinterBrand.values)
                        DashOption(value: b.value, label: printerBrandLabel(b)),
                    ],
                    onChanged: (v) => _edit(() => _brand = v),
                  ),
                  if (hasPrinter)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.md,
                      children: [
                        Expanded(
                          child: DashTextField(
                            key: const ValueKey('station-ip'),
                            label: t('branches.printerIp'),
                            value: _ip,
                            mono: true,
                            textDirection: TextDirection.ltr,
                            keyboardType: TextInputType.url,
                            placeholder: '192.168.1.50',
                            onChanged: (v) => _edit(() => _ip = v),
                            onSubmitted: (_) => _save(),
                          ),
                        ),
                        Expanded(
                          child: DashTextField(
                            key: const ValueKey('station-port'),
                            label: t('branches.printerPort'),
                            value: _port,
                            mono: true,
                            textDirection: TextDirection.ltr,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (v) => _edit(() => _port = v),
                            onSubmitted: (_) => _save(),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            _SwitchCard(
              key: const ValueKey('station-default'),
              label: t('kitchen.defaultStation'),
              hint: t('kitchen.defaultStationHint'),
              value: _isDefault,
              onChanged: (v) => _edit(() => _isDefault = v),
            ),
            _SwitchCard(
              key: const ValueKey('station-active'),
              label: t('common.active'),
              value: _isActive,
              onChanged: (v) => _edit(() => _isActive = v),
            ),
          ],
        ),
        actions: [
          DashButton(
            key: const ValueKey('station-cancel'),
            label: t('common.cancel'),
            variant: DashButtonVariant.outline,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          DashButton(
            key: const ValueKey('station-save'),
            label: t(_saving ? 'common.saving' : 'common.save'),
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// A bordered switch row (`rounded-lg border p-3`): the label, an optional
/// quiet hint, the switch; a tap anywhere on it toggles.
class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    super.key,
  });

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: () => onChanged(!value),
      isButton: false,
      checked: value,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(
          Space.md,
          Space.sm,
          Space.xs,
          Space.sm,
        ),
        decoration: BoxDecoration(
          color: s.highlighted ? c.hover : c.card,
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(color: c.border),
        ),
        child: Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: DashMetrics.hair,
                children: [
                  Text(
                    label,
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  if (hint != null)
                    Text(
                      hint!,
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                ],
              ),
            ),
            DashSwitch(value: value, semanticLabel: label, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
