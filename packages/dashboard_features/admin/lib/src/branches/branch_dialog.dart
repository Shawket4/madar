/// The branch editor (ADM-BRA-020..037; web `features/branches/branch-dialog.tsx`):
/// a dialog on a wide screen, a full-screen sheet on a phone.
///
/// CROSS-UNIT CONTRACT: the onboarding wizard's branch step (ADM-ONB-015)
/// opens this same dialog in create mode, so keep [showBranchDialog]'s
/// signature stable.
///
/// What it sends (the web's `submit`):
/// - edit: one `PATCH /branches/{id}` with every field — name, address,
///   phone, timezone, the printer (explicit nulls with no model), the
///   location, the tax overrides (explicit nulls with the override off), the
///   till settings and `is_active`;
/// - create: `POST /branches` (which takes no till settings), then
///   `PATCH /branches/{newId}` with `{old_bill_hours, standard_float}` — and,
///   for a platform admin who switched the override on, the four tax
///   overrides (the create call drops them; see the divergence log).
/// A branch the POST made is remembered, so pressing Create again after a
/// failed follow-up PATCH retries the PATCH instead of making a second
/// branch (ADM-BRA-036).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Branch, CreateBranchRequest, PrinterBrand, UpdateBranchRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/tax_rate.dart';
import 'branches_data.dart';

/// Opens the branch dialog: [branch] null = "New Branch" (create), else
/// "Edit Branch". Resolves true when a branch was created or saved, false
/// when the dialog closed without one.
Future<bool> showBranchDialog(BuildContext context, {Branch? branch}) async {
  final saved = await showDashDialog<bool>(
    context,
    builder: (_) => BranchDialog(branch: branch),
  );
  return saved ?? false;
}

/// The printer model choices (`printer_brand`; "none" = no printer).
const List<String> branchPrinterModels = ['none', 'star', 'epson'];

class BranchDialog extends ConsumerStatefulWidget {
  const BranchDialog({this.branch, super.key});

  /// The branch being edited; null creates one.
  final Branch? branch;

  @override
  ConsumerState<BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends ConsumerState<BranchDialog> {
  final _form = GlobalKey<FormState>();
  bool _busy = false;

  /// The branch the create call made, when its follow-up PATCH failed.
  Branch? _created;

  late String _name;
  late String _phone;
  late String _address;
  late String _timezone;
  late bool _active;
  late String _printer;
  late String _printerIp;
  late double? _printerPort;
  late double? _latitude;
  late double? _longitude;
  late double? _radius;
  late bool _taxOverride;
  late double? _taxRate;
  late bool _taxInclusive;
  late double? _serviceCharge;
  late bool _serviceChargeTaxable;
  late double? _oldBillHours;
  late double? _standardFloat;

  Branch? get _branch => widget.branch;
  bool get _editing => _branch != null;

  @override
  void initState() {
    super.initState();
    // The web's `form.reset(...)` on open: from the branch, or the defaults.
    final b = _branch;
    _name = b?.name ?? '';
    _phone = b?.phone ?? '';
    _address = b?.address ?? '';
    _timezone = b?.timezone ?? 'Africa/Cairo';
    _active = b?.isActive ?? true;
    final brand = b?.printerBrand?.toJson();
    _printer = branchPrinterModels.contains(brand) ? brand! : 'none';
    _printerIp = b?.printerIp ?? '';
    _printerPort = (b?.printerPort ?? 9100).toDouble();
    _latitude = b?.latitude;
    _longitude = b?.longitude;
    _radius = (b?.geoRadiusMeters ?? 200).toDouble();
    // Any override present means this branch has opted out of the org's
    // policy; the switch reflects that rather than being stored separately.
    _taxOverride =
        b?.taxRate != null ||
        b?.taxInclusive != null ||
        b?.serviceChargeRate != null ||
        b?.serviceChargeTaxable != null;
    _taxRate = fractionToPercent(b?.taxRate);
    _taxInclusive = b?.taxInclusive ?? false;
    _serviceCharge = fractionToPercent(b?.serviceChargeRate);
    _serviceChargeTaxable = b?.serviceChargeTaxable ?? true;
    _oldBillHours = (b?.oldBillHours ?? 3).toDouble();
    final float = b?.standardFloat;
    _standardFloat = float == null ? null : float / 100;
  }

  bool get _platform =>
      ref.read(currentSessionProvider)?.isPlatform ?? false;

  // ── validation (the web's zod schema, in the kit's words) ──────────────

  String? _required(String v) =>
      v.isEmpty ? ref.read(tProvider)('common.requiredField') : null;

  String _between(num min, num max) {
    final f = context.dashFormats;
    return context.dashStrings.between(f.figure(min), f.figure(max), '');
  }

  String? _hours(double? v) =>
      v == null || v.isNaN || v < 1 || v > 168 || v != v.roundToDouble()
      ? _between(1, 168)
      : null;

  String? _rate(double? v) => v != null && (v.isNaN || v < 0 || v > kMaxPercent)
      ? _between(0, kMaxPercent)
      : null;

  String? _atLeastZero(double? v) => v != null && (v.isNaN || v < 0)
      ? context.dashStrings.atLeast(context.dashFormats.figure(0), '')
      : null;

  String? _coordinate(double? v, num limit) =>
      v != null && (v.isNaN || v < -limit || v > limit)
      ? _between(-limit, limit)
      : null;

  // ── the payloads ───────────────────────────────────────────────────────

  static double? _num(double? v) => v == null || v.isNaN ? null : v;
  static int? _int(double? v) => _num(v)?.round();

  /// A text box left blank: null on a new branch; on an edit, an empty string
  /// when the branch had a value (the server keeps a null, so only an empty
  /// string clears it; see the divergence log), else null.
  String? _blank(String v, String? stored) {
    if (v.isNotEmpty) return v;
    return _editing && hasText(stored) ? '' : null;
  }

  bool get _hasPrinter => _printer != 'none';

  PrinterBrand? get _printerBrand =>
      _hasPrinter ? PrinterBrand.fromJson(_printer) : null;

  /// The four tax overrides as this save sends them: the form's (platform
  /// admin, switch on), explicit nulls (platform admin, switch off), or the
  /// stored values exactly (anyone else, who never sees the block).
  ({double? rate, bool? inclusive, double? service, bool? serviceTaxable})
  get _tax {
    if (!_platform) {
      final b = _branch;
      return (
        rate: b?.taxRate,
        inclusive: b?.taxInclusive,
        service: b?.serviceChargeRate,
        serviceTaxable: b?.serviceChargeTaxable,
      );
    }
    if (!_taxOverride) {
      return (rate: null, inclusive: null, service: null, serviceTaxable: null);
    }
    return (
      rate: percentToFraction(_num(_taxRate) ?? 0),
      inclusive: _taxInclusive,
      service: percentToFraction(_num(_serviceCharge) ?? 0),
      serviceTaxable: _serviceChargeTaxable,
    );
  }

  int? get _floatPiastres {
    final v = _num(_standardFloat);
    return v == null ? null : (v * 100).round();
  }

  /// Every field, as the edit's PATCH (and a create's retried PATCH) sends.
  UpdateBranchRequest _fullUpdate() {
    final b = _branch;
    final tax = _tax;
    final body = UpdateBranchRequest(
      name: _name,
      address: _blank(_address, b?.address),
      phone: _blank(_phone, b?.phone),
      timezone: _timezone,
      printerBrand: _printerBrand,
      printerIp: _hasPrinter && _printerIp.isNotEmpty ? _printerIp : null,
      printerPort: _hasPrinter ? _int(_printerPort) : null,
      latitude: _num(_latitude),
      longitude: _num(_longitude),
      geoRadiusMeters: _int(_radius),
      taxRate: tax.rate,
      taxInclusive: tax.inclusive,
      serviceChargeRate: tax.service,
      serviceChargeTaxable: tax.serviceTaxable,
      oldBillHours: _int(_oldBillHours),
      standardFloat: _floatPiastres,
      isActive: _editing ? _active : null,
    );
    return _withNulls(body.toJson(), {
      'address',
      'phone',
      'printer_brand',
      'printer_ip',
      'printer_port',
      'latitude',
      'longitude',
      'geo_radius_meters',
      'tax_rate',
      'tax_inclusive',
      'service_charge_rate',
      'service_charge_taxable',
      'standard_float',
    });
  }

  /// The create's follow-up PATCH: the till settings, and a platform
  /// admin's tax overrides when the switch is on.
  UpdateBranchRequest _tillsUpdate() {
    final tax = _platform && _taxOverride ? _tax : null;
    final body = UpdateBranchRequest(
      oldBillHours: _int(_oldBillHours),
      standardFloat: _floatPiastres,
      taxRate: tax?.rate,
      taxInclusive: tax?.inclusive,
      serviceChargeRate: tax?.service,
      serviceChargeTaxable: tax?.serviceTaxable,
    );
    return _withNulls(body.toJson(), {'standard_float'});
  }

  /// [json] as a request that also sends each of [nullable] that is unset
  /// as an explicit null (the web's `null`s).
  static UpdateBranchRequest _withNulls(
    Map<String, Object?> json,
    Set<String> nullable,
  ) {
    final r = UpdateBranchRequest.fromJson(json);
    return UpdateBranchRequest(
      address: r.address,
      geoRadiusMeters: r.geoRadiusMeters,
      isActive: r.isActive,
      latitude: r.latitude,
      longitude: r.longitude,
      name: r.name,
      oldBillHours: r.oldBillHours,
      phone: r.phone,
      printerBrand: r.printerBrand,
      printerIp: r.printerIp,
      printerPort: r.printerPort,
      serviceChargeRate: r.serviceChargeRate,
      serviceChargeTaxable: r.serviceChargeTaxable,
      standardFloat: r.standardFloat,
      taxInclusive: r.taxInclusive,
      taxRate: r.taxRate,
      timezone: r.timezone,
      explicitNulls: {
        for (final k in nullable)
          if (json[k] == null) k,
      },
    );
  }

  CreateBranchRequest _create(String orgId) {
    final body = CreateBranchRequest(
      orgId: orgId,
      name: _name,
      address: _address.isEmpty ? null : _address,
      phone: _phone.isEmpty ? null : _phone,
      timezone: _timezone,
      printerBrand: _printerBrand,
      printerIp: _hasPrinter && _printerIp.isNotEmpty ? _printerIp : null,
      printerPort: _hasPrinter ? _int(_printerPort) : null,
      latitude: _num(_latitude),
      longitude: _num(_longitude),
      geoRadiusMeters: _int(_radius),
      explicitNulls: const {
        'address',
        'phone',
        'printer_brand',
        'printer_ip',
        'printer_port',
        'latitude',
        'longitude',
        'geo_radius_meters',
      },
    );
    return body;
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).branches;
    final b = _branch;
    setState(() => _busy = true);
    try {
      if (b != null) {
        await api.patchBranch(id: b.id, body: _fullUpdate());
      } else if (_created case final made?) {
        await api.patchBranch(id: made.id, body: _fullUpdate());
      } else {
        final orgId = ref.read(orgIdProvider);
        if (orgId == null) return;
        final made = await api.createBranch(body: _create(orgId));
        _created = made;
        // The branch exists from here on, whatever the next call does.
        invalidateBranches(ref);
        await api.patchBranch(id: made.id, body: _tillsUpdate());
      }
      invalidateBranches(ref);
      if (!mounted) return;
      DashToast.success(
        context,
        t(_editing ? 'branches.updatedToast' : 'branches.createdToast'),
      );
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, branchErrorText(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── the form ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final platform =
        ref.watch(currentSessionProvider.select((s) => s?.isPlatform)) ??
        false;
    final zones = ref.watch(branchTimezonesProvider).value ?? const <String>[];
    final wide =
        DashSurfaceScope.maybeOf(context) != DashSurfaceMode.fullScreen;

    Widget pair(Widget a, Widget b) => wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: Space.md,
            children: [
              Expanded(child: a),
              Expanded(child: b),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.lg,
            children: [a, b],
          );

    Widget box(String icon, String title, List<Widget> children) => Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Row(
            spacing: Space.sm,
            children: [
              DashIcon(icon, size: IconSize.xs, color: c.textSecondary),
              Expanded(
                child: Text(
                  title,
                  style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
          ...children,
        ],
      ),
    );

    Widget muted(Widget child) => Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: child,
    );

    final name = DashTextField(
      key: const ValueKey('branch-name'),
      label: t('branches.branchName'),
      value: _name,
      onChanged: (v) => setState(() => _name = v),
      validator: _required,
      onSubmitted: (_) => _submit(),
    );
    final phone = DashTextField(
      key: const ValueKey('branch-phone'),
      label: t('branches.phone'),
      value: _phone,
      keyboardType: TextInputType.phone,
      textDirection: TextDirection.ltr,
      onChanged: (v) => setState(() => _phone = v),
      onSubmitted: (_) => _submit(),
    );
    final timezone = DashTimezoneSelect(
      key: const ValueKey('branch-timezone'),
      label: t('branches.timezone'),
      zones: zones,
      value: _timezone,
      onChanged: (v) => setState(() => _timezone = v),
    );
    final hours = DashNumberField(
      key: const ValueKey('branch-old-bill-hours'),
      label: t('branches.oldBillHours'),
      value: _oldBillHours,
      min: 1,
      max: 168,
      decimals: 0,
      onChanged: (v) => setState(() => _oldBillHours = v),
      validator: _hours,
    );
    final float = DashNumberField(
      key: const ValueKey('branch-standard-float'),
      label: t('branches.standardFloat'),
      value: _standardFloat,
      step: 0.01,
      decimals: 2,
      allowEmpty: true,
      onChanged: (v) => setState(() => _standardFloat = v),
      validator: _atLeastZero,
    );
    final address = DashTextField(
      key: const ValueKey('branch-address'),
      label: t('branches.address'),
      value: _address,
      onChanged: (v) => setState(() => _address = v),
      onSubmitted: (_) => _submit(),
    );

    final printer = box('printer', t('branches.printerConfig'), [
      DashSelectField<String>(
        key: const ValueKey('branch-printer-model'),
        label: t('branches.printerBrand'),
        value: _printer,
        options: [
          for (final m in branchPrinterModels)
            DashOption(value: m, label: t('branches.brands.$m')),
        ],
        onChanged: (v) => setState(() => _printer = v),
      ),
      if (_hasPrinter)
        pair(
          DashTextField(
            key: const ValueKey('branch-printer-ip'),
            label: t('branches.printerIp'),
            value: _printerIp,
            placeholder: '192.168.1.100',
            mono: true,
            textDirection: TextDirection.ltr,
            onChanged: (v) => setState(() => _printerIp = v),
            onSubmitted: (_) => _submit(),
          ),
          DashNumberField(
            key: const ValueKey('branch-printer-port'),
            label: t('branches.printerPort'),
            value: _printerPort,
            decimals: 0,
            allowEmpty: true,
            onChanged: (v) => setState(() => _printerPort = v),
            validator: _atLeastZero,
          ),
        ),
    ]);

    final latitude = DashNumberField(
      key: const ValueKey('branch-latitude'),
      label: t('branches.latitude'),
      value: _latitude,
      min: -90,
      max: 90,
      decimals: 7,
      allowEmpty: true,
      onChanged: (v) => setState(() => _latitude = v),
      validator: (v) => _coordinate(v, 90),
    );
    final longitude = DashNumberField(
      key: const ValueKey('branch-longitude'),
      label: t('branches.longitude'),
      value: _longitude,
      min: -180,
      max: 180,
      decimals: 7,
      allowEmpty: true,
      onChanged: (v) => setState(() => _longitude = v),
      validator: (v) => _coordinate(v, 180),
    );
    final radius = DashNumberField(
      key: const ValueKey('branch-radius'),
      label: t('branches.geoRadius'),
      value: _radius,
      decimals: 0,
      allowEmpty: true,
      onChanged: (v) => setState(() => _radius = v),
      validator: _atLeastZero,
    );
    final location = box('map-pin', t('branches.location'), [
      Text(
        t('branches.geoHint'),
        style: DashType.small.copyWith(color: c.textSecondary),
      ),
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: Space.md,
          children: [
            Expanded(child: latitude),
            Expanded(child: longitude),
            Expanded(child: radius),
          ],
        )
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [latitude, longitude, radius],
        ),
    ]);

    final tax = platform
        ? [
            muted(
              DashSwitchField(
                key: const ValueKey('branch-tax-override'),
                label: t('branches.taxOverride'),
                description: t('branches.taxOverrideHint'),
                value: _taxOverride,
                onChanged: (v) => setState(() => _taxOverride = v),
              ),
            ),
            if (_taxOverride)
              Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: Border.all(color: c.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.lg,
                  children: [
                    pair(
                      DashNumberField(
                        key: const ValueKey('branch-tax-rate'),
                        label: t('orgs.taxRate'),
                        value: _taxRate,
                        max: kMaxPercent,
                        step: 0.1,
                        decimals: 4,
                        allowEmpty: true,
                        onChanged: (v) => setState(() => _taxRate = v),
                        validator: _rate,
                      ),
                      DashNumberField(
                        key: const ValueKey('branch-service-charge'),
                        label: t('orgs.serviceCharge'),
                        value: _serviceCharge,
                        max: kMaxPercent,
                        step: 0.1,
                        decimals: 4,
                        allowEmpty: true,
                        onChanged: (v) => setState(() => _serviceCharge = v),
                        validator: _rate,
                      ),
                    ),
                    DashSwitchField(
                      key: const ValueKey('branch-tax-inclusive'),
                      label: t('orgs.taxInclusive'),
                      value: _taxInclusive,
                      onChanged: (v) => setState(() => _taxInclusive = v),
                    ),
                    DashSwitchField(
                      key: const ValueKey('branch-service-taxable'),
                      label: t('orgs.serviceChargeTaxable'),
                      value: _serviceChargeTaxable,
                      onChanged: (v) =>
                          setState(() => _serviceChargeTaxable = v),
                    ),
                  ],
                ),
              ),
          ]
        : const <Widget>[];

    final active = _editing
        ? muted(
            DashSwitchField(
              key: const ValueKey('branch-active'),
              label: t('common.active'),
              description: t('branches.activeHint'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          )
        : null;

    return DashSurface(
      title: t(_editing ? 'branches.editTitle' : 'branches.newTitle'),
      description: t('branches.subtitle'),
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            name,
            pair(phone, timezone),
            pair(hours, float),
            address,
            printer,
            location,
            ...tax,
            ?active,
          ],
        ),
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        DashButton(
          key: const ValueKey('branch-submit'),
          label: t(_editing ? 'common.save' : 'common.create'),
          loading: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
