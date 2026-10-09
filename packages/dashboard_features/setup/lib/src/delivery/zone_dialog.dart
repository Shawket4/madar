/// The zone editor (web `features/delivery/zone-dialog.tsx`, SET-DZN-014..
/// 019, 021, 022): name, "Up to … km", fee and Active. New →
/// `POST /delivery/zones`, edit → `PATCH /delivery/zones/{id}`; a success
/// toasts, refetches `/delivery/zones*` and closes; a 409 says a ring at
/// that distance exists, any other failure the server's words, and the
/// dialog stays open. Below 760 wide it is a full-screen sheet.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, DeliveryZone, ZoneInput;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'delivery_data.dart';

/// Opens the editor for [zone] (null = a new one) over the branch's
/// [zones] (the list on screen; the dialog follows its refreshes); [host]
/// is the page, which shows the result's toast should the dialog be gone.
Future<void> showZoneDialog(
  BuildContext host, {
  required String branchId,
  required DeliveryZone? zone,
  required List<DeliveryZone> zones,
}) => showDashDialog<void>(
  host,
  builder: (_) =>
      ZoneDialog(branchId: branchId, zone: zone, zones: zones, host: host),
);

class ZoneDialog extends ConsumerStatefulWidget {
  const ZoneDialog({
    required this.branchId,
    required this.zone,
    required this.zones,
    this.host,
    super.key,
  });

  final String branchId;
  final DeliveryZone? zone;
  final List<DeliveryZone> zones;
  final BuildContext? host;

  @override
  ConsumerState<ZoneDialog> createState() => _ZoneDialogState();
}

class _ZoneDialogState extends ConsumerState<ZoneDialog> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  double? _km;
  double? _fee;
  bool _active = true;
  bool _busy = false;

  /// What the fields were filled from; until the person types, a refreshed
  /// list refills them (the zone's new values, a new zone's new default).
  Object? _seed;
  bool _edited = false;

  bool get _editing => widget.zone != null;

  void _follow(List<DeliveryZone> zones) {
    final id = widget.zone?.id;
    final zone = id == null
        ? null
        : zones.where((z) => z.id == id).firstOrNull ?? widget.zone;
    final seed = zone ?? defaultZoneKm(zones);
    if (_edited || seed == _seed) return;
    _seed = seed;
    _name = zone?.name ?? '';
    _km = zone == null
        ? defaultZoneKm(zones)
        : zone.maxRoadDistanceMeters / 1000;
    _fee = zone == null ? 0 : piastresToEgp(zone.fee);
    _active = zone?.isActive ?? true;
  }

  void _edit(VoidCallback change) => setState(() {
    _edited = true;
    change();
  });

  Future<void> _save(String fallbackName) async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).delivery;
    final bus = ref.read(realtimeBusProvider);
    final host = widget.host;
    final zone = widget.zone;
    final name = _name.trim();
    final body = ZoneInput(
      branchId: widget.branchId,
      name: name.isEmpty ? fallbackName : name,
      // Carried through: omitted, the backend stores JSON null over them.
      nameTranslations: zone?.nameTranslations ?? const {},
      maxRoadDistanceMeters: kmToMeters(_km ?? 0),
      fee: egpToPiastres(_fee ?? 0),
      isActive: _active,
    );
    setState(() => _busy = true);
    try {
      if (zone != null) {
        await api.updateZone(id: zone.id, body: body);
      } else {
        await api.createZone(body: body);
      }
    } on Object catch (e) {
      final at = mounted ? context : host;
      if (at != null && at.mounted) {
        DashToast.error(
          at,
          e is ApiException && e.status == 409
              ? t('delivery.errZoneDistanceExists')
              : errorMessage(e, t),
        );
      }
      if (mounted) setState(() => _busy = false);
      return;
    }
    invalidateZones(bus);
    final at = mounted ? context : host;
    if (at != null && at.mounted) {
      DashToast.success(
        at,
        t(zone != null ? 'delivery.zoneUpdated' : 'delivery.zoneCreated'),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final zones =
        ref.watch(deliveryZonesProvider(widget.branchId)).value ??
        widget.zones;
    _follow(zones);
    // Always the next ring's number, in the edit dialog too (the web's).
    final fallbackName = zoneLabel(t, zones.length + 1);
    return Form(
      key: _formKey,
      child: DashSurface(
        title: t(_editing ? 'delivery.editZone' : 'delivery.newZone'),
        description: t('delivery.zoneSubtitle'),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            DashTextField(
              key: const ValueKey('dzn-name'),
              label: t('delivery.zoneName'),
              value: _name,
              placeholder: fallbackName,
              description: t('delivery.zoneNameHint'),
              onChanged: (v) => _edit(() => _name = v),
              onSubmitted: (_) => _save(fallbackName),
            ),
            // Side by side at every width, as the web's `grid-cols-2`.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(
                  child: DashNumberField(
                    key: const ValueKey('dzn-km'),
                    label: t('delivery.maxRoadDistanceKm'),
                    description: t('delivery.maxRoadDistanceHint'),
                    value: _km,
                    step: 0.5,
                    decimals: 3,
                    allowEmpty: true,
                    // The live value: Enter validates before the field rebuilds.
                    validator: (_) => _km != null && !_km!.isNaN && _km! > 0
                        ? null
                        : t('delivery.errDistancePositive'),
                    onChanged: (v) => _edit(() => _km = v),
                    onSubmitted: (_) => _save(fallbackName),
                  ),
                ),
                Expanded(
                  child: DashNumberField(
                    key: const ValueKey('dzn-fee'),
                    label: t('delivery.zoneFee'),
                    description: t('delivery.zoneFeeHint'),
                    value: _fee,
                    decimals: 2,
                    allowEmpty: true,
                    validator: (_) => DeliveryForm.feeOk(_fee)
                        ? null
                        : t('delivery.errFeeNonNeg'),
                    onChanged: (v) => _edit(() => _fee = v),
                    onSubmitted: (_) => _save(fallbackName),
                  ),
                ),
              ],
            ),
            Container(
              key: const ValueKey('dzn-active'),
              padding: const EdgeInsetsDirectional.fromSTEB(
                Space.md,
                Space.xs,
                Space.xs,
                Space.xs,
              ),
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
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
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          t('delivery.zoneActiveHint'),
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DashSwitch(
                    value: _active,
                    semanticLabel: t('common.active'),
                    onChanged: (v) => _edit(() => _active = v),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          DashButton(
            key: const ValueKey('dzn-cancel'),
            label: t('common.cancel'),
            variant: DashButtonVariant.outline,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          DashButton(
            key: const ValueKey('dzn-save'),
            label: t(_editing ? 'common.save' : 'common.create'),
            loading: _busy,
            onPressed: () => _save(fallbackName),
          ),
        ],
      ),
    );
  }
}
