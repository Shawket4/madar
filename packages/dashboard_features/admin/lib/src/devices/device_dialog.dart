/// The Edit device dialog (web `devices-page.tsx` `DeviceDialog`,
/// ADM-DEV-010..013, -029): the code (mono, uppercase, at most 6), the
/// name, the Retired switch; Save sends `{code, label, retired}`.
///
/// Page state, never the URL: a fresh dialog per open, filled from the
/// device. Escape, a tap outside, the × and Cancel close it; Cancel stays
/// enabled while saving. Below 760 wide it is a full-screen sheet.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Device, UpdateDeviceRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'devices_data.dart';

/// Opens the dialog for [device]; [host] is the page, which shows the
/// result's toast should the dialog already be gone when the answer lands.
Future<void> showDeviceDialog(
  BuildContext host,
  Device device,
) => showDashDialog<void>(
  host,
  builder: (_) => DeviceDialog(device: device, host: host),
);

/// Shows what is typed in capitals, as the web's `uppercase` input does.
class _Upper extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

class DeviceDialog extends ConsumerStatefulWidget {
  const DeviceDialog({required this.device, this.host, super.key});

  final Device device;
  final BuildContext? host;

  @override
  ConsumerState<DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends ConsumerState<DeviceDialog> {
  final _form = GlobalKey<FormState>();
  late String _code = widget.device.code;
  late String _label = widget.device.label ?? '';
  late bool _retired = widget.device.retiredAt != null;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    // zod: trim → uppercase → /^[A-Z0-9]{1,6}$/, shown under the field.
    if (!(_form.currentState?.validate() ?? false)) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final invalidate = ref.devicesInvalidate;
    final host = widget.host;
    final label = _label.trim();
    setState(() => _saving = true);
    try {
      await api.devices.updateDevice(
        id: widget.device.id,
        body: UpdateDeviceRequest(
          code: _code.trim().toUpperCase(),
          label: label.isEmpty ? null : label,
          retired: _retired,
          explicitNulls: label.isEmpty ? const {'label'} : const {},
        ),
      );
      invalidate.deviceSaved();
      final at = mounted ? context : host;
      if (at != null && at.mounted) DashToast.success(at, t('common.saved'));
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      final at = mounted ? context : host;
      if (at != null && at.mounted) {
        DashToast.error(at, devicesErrorText(e, t));
      }
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Form(
      key: _form,
      child: DashSurface(
        title: t('devices.edit'),
        description: t('devices.editHint'),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            DashTextField(
              key: const ValueKey('device-code'),
              label: t('devices.code'),
              value: _code,
              mono: true,
              maxLength: 6,
              autofocus: true,
              inputFormatters: [_Upper()],
              onChanged: (v) => setState(() => _code = v),
              onSubmitted: (_) => _save(),
              validator: (v) =>
                  deviceCodePattern.hasMatch(v.trim().toUpperCase())
                  ? null
                  : t('devices.codeInvalid'),
            ),
            DashTextField(
              key: const ValueKey('device-label'),
              label: t('devices.label'),
              value: _label,
              onChanged: (v) => setState(() => _label = v),
              onSubmitted: (_) => _save(),
            ),
            // The whole row is the switch's label: a tap anywhere toggles.
            DashPressable(
              key: const ValueKey('device-retired'),
              onTap: () => setState(() => _retired = !_retired),
              isButton: false,
              checked: _retired,
              semanticLabel: t('devices.retired'),
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
                  color: s.highlighted ? c.hover : null,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  spacing: Space.sm,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t('devices.retired'),
                            style: DashType.bodyMedium.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            t('devices.retiredHint'),
                            style: DashType.small.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DashSwitch(
                      value: _retired,
                      semanticLabel: t('devices.retired'),
                      onChanged: (v) => setState(() => _retired = v),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          DashButton(
            key: const ValueKey('device-cancel'),
            label: t('common.cancel'),
            variant: DashButtonVariant.outline,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          DashButton(
            key: const ValueKey('device-save'),
            label: t('common.save'),
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
