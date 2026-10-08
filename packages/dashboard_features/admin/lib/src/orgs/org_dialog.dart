/// The organization editor (the web's `features/orgs/org-dialog.tsx` in edit
/// mode, ADM-ORG-041..059), opened by `?edit=<id>`: logo (uploaded at
/// once), name, slug, currency, rates, the tax and table switches, timezone,
/// receipt footer, active, custom branding, modules (platform admins only)
/// and the social links; Save sends one `PATCH /orgs/{id}`.
///
/// The create mode of the web's dialog is never opened from this page (New
/// opens the provision wizard), so it is not ported (ADM-ORG-055).
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show ApiFilePart, Org, UpdateOrgRequest, UploadLogoMultipart;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/tax_rate.dart';
import 'org_errors.dart';
import 'org_form_parts.dart';
import 'org_logo.dart';
import 'orgs_providers.dart';
import 'provision.dart' show percentError, parsePercentInput;
import 'social_links.dart';

/// Opens the editor for [org]; resolves when it closes.
Future<void> showOrgDialog(BuildContext context, {required Org org}) =>
    showDashDialog<void>(context, builder: (_) => OrgDialog(org: org));

class OrgDialog extends ConsumerStatefulWidget {
  const OrgDialog({required this.org, super.key});

  /// The row as it was when the editor opened (the fields start from it).
  final Org org;

  @override
  ConsumerState<OrgDialog> createState() => _OrgDialogState();
}

class _OrgDialogState extends ConsumerState<OrgDialog> {
  late final Org _org = widget.org;
  late String _name = _org.name;
  late String _slug = _org.slug ?? '';
  late String _currency = _org.currencyCode;
  late String _taxRate = jsNumber(fractionToPercent(_org.taxRate));
  late bool _taxInclusive = _org.taxInclusive;
  late String _serviceCharge = jsNumber(
    fractionToPercent(_org.serviceChargeRate),
  );
  late bool _serviceChargeTaxable = _org.serviceChargeTaxable;
  late String _timezone = _org.timezone;
  late String _receiptFooter = _org.receiptFooter ?? '';
  late bool _active = _org.isActive;
  late bool _requireTable = _org.requireTableForOrders;
  late bool _customBranding = _org.customBranding;
  late List<String> _modules = [
    for (final m in _org.modules)
      if (orgModuleKeys.contains(m)) m,
  ];
  late final Map<String, String> _social = socialLinksToForm(_org.socialLinks);

  /// Save was pressed once: from then on every change re-checks
  /// (react-hook-form's `reValidateMode: onChange`).
  bool _submitted = false;
  bool _busy = false;
  Map<String, String> _errors = const {};

  Translator get _t => ref.read(tProvider);

  /// The checks of the web's schema. Name, slug and currency are NOT
  /// trimmed here (ADM-ORG-059); the wizard's are.
  Map<String, String> _validate() {
    final t = _t;
    final required = t('common.requiredField');
    return {
      if (_name.isEmpty) 'name': required,
      if (_slug.isEmpty) 'slug': required,
      if (_currency.isEmpty) 'currency': required,
      'taxRate': ?percentError(_taxRate, t),
      'serviceCharge': ?percentError(_serviceCharge, t),
      if (_timezone.isEmpty) 'timezone': required,
      if (_modules.isEmpty) 'modules': t('dawam.modulesAtLeastOne'),
      for (final p in socialPlatforms)
        'social.${p.key}': ?socialLinkError(_social[p.key] ?? '', t),
    };
  }

  void _changed(VoidCallback apply) {
    setState(() {
      apply();
      if (_submitted) _errors = _validate();
    });
  }

  bool get _platform =>
      ref.read(currentSessionProvider)?.isPlatform ?? false;

  Future<void> _save() async {
    if (_busy) return;
    final t = _t;
    final errors = _validate();
    setState(() {
      _submitted = true;
      _errors = errors;
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    final footer = _receiptFooter;
    try {
      await ref
          .read(apiProvider)
          .orgs
          .updateOrg(
            id: _org.id,
            body: UpdateOrgRequest(
              name: _name,
              slug: _slug,
              currencyCode: _currency,
              taxRate: percentToFraction(parsePercentInput(_taxRate) ?? 0),
              receiptFooter: footer.isEmpty ? null : footer,
              timezone: _timezone,
              isActive: _active,
              customBranding: _customBranding,
              modules: _platform ? [..._modules] : null,
              taxInclusive: _taxInclusive,
              serviceChargeRate: percentToFraction(
                parsePercentInput(_serviceCharge) ?? 0,
              ),
              serviceChargeTaxable: _serviceChargeTaxable,
              requireTableForOrders: _requireTable,
              socialLinks: socialLinksPatch(_social, _org.socialLinks),
              explicitNulls: {if (footer.isEmpty) 'receipt_footer'},
            ),
          );
      if (!mounted) return;
      invalidateOrgs(ref);
      DashToast.success(context, t('orgs.updatedToast'));
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, orgErrorWords(e, t));
    }
  }

  // ── Logo (uploaded at once, ADM-ORG-042 / 043) ────────────────────────

  Future<void> _syncPickedOrg(String? logoUrl) async {
    final picked = ref.read(selectedOrgProvider);
    if (picked?.id != _org.id) return;
    await ref
        .read(selectedOrgProvider.notifier)
        .select(_org.id, logoUrl: logoUrl);
  }

  Future<String?> _upload(DashPickedFile file) async {
    final t = _t;
    try {
      final updated = await ref
          .read(apiProvider)
          .orgs
          .uploadOrgLogo(
            id: _org.id,
            body: UploadLogoMultipart(
              logo: ApiFilePart(
                field: 'logo',
                filename: file.name,
                bytes: file.bytes,
                contentType: file.mimeType,
              ),
            ),
          );
      invalidateOrgs(ref);
      await _syncPickedOrg(updated.logoUrl);
      return updated.logoUrl;
    } on Object catch (e) {
      throw OrgFailure(orgErrorWords(e, t));
    }
  }

  Future<void> _removeLogo() async {
    final t = _t;
    try {
      await ref
          .read(apiProvider)
          .orgs
          .updateOrg(
            id: _org.id,
            body: const UpdateOrgRequest(explicitNulls: {'logo_url'}),
          );
      invalidateOrgs(ref);
      await _syncPickedOrg(null);
      if (mounted) DashToast.success(context, t('orgs.logoRemoved'));
    } on Object catch (e) {
      throw OrgFailure(orgErrorWords(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    // The logo follows the server's row (it changes under the editor);
    // what was typed does not (docs/fdash/divergences/admin-orgs.md).
    final live =
        ref
            .watch(orgsListProvider)
            .value
            ?.firstWhereOrNull((o) => o.id == _org.id) ??
        _org;
    final zones = ref.watch(orgTimezonesProvider).value ?? const <String>[];
    final platform =
        ref.watch(currentSessionProvider.select((s) => s?.isPlatform)) ??
        false;
    final twoUp = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final logo = live.logoUrl;
    final hasLogo = logo != null && logo.isNotEmpty;

    Widget text(
      String field, {
      required String label,
      required String value,
      required ValueChanged<String> onChanged,
      bool mono = false,
      String? description,
      TextInputType? keyboard,
      TextDirection? direction,
      List<TextInputFormatter>? formatters,
    }) => DashTextField(
      key: ValueKey('org-$field'),
      label: label,
      value: value,
      mono: mono,
      description: description,
      errorText: _errors[field],
      keyboardType: keyboard,
      textDirection: direction,
      inputFormatters: formatters,
      onChanged: (v) => _changed(() => onChanged(v)),
      onSubmitted: (_) => _save(),
    );

    final serviceCharge = text(
      'serviceCharge',
      label: t('orgs.serviceCharge'),
      value: _serviceCharge,
      onChanged: (v) => _serviceCharge = v,
      description: t('orgs.serviceChargeHint'),
      keyboard: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      direction: TextDirection.ltr,
      formatters: percentInputFormatters,
    );
    final serviceTaxable = OrgSwitchBox(
      label: t('orgs.serviceChargeTaxable'),
      value: _serviceChargeTaxable,
      onChanged: (v) => _changed(() => _serviceChargeTaxable = v),
    );

    return DashSurface(
      title: t('orgs.editTitle'),
      description: t('orgs.editDescription'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.lg,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs + DashMetrics.hair,
            children: [
              OrgFieldLabel(t('orgs.logo')),
              DashImageUploader(
                key: const ValueKey('org-logo'),
                value: logo,
                hint: t('orgs.logoHint'),
                semanticLabel: t('orgs.logo'),
                onPick: () => pickOrgImage(ref),
                onUpload: _upload,
                onRemove: hasLogo ? _removeLogo : null,
                imageBuilder: (context, url) => orgImage(
                  url,
                  fallback: (_) => Center(
                    child: DashIcon(
                      'image',
                      size: IconSize.lg,
                      color: c.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          text(
            'name',
            label: t('orgs.orgName'),
            value: _name,
            onChanged: (v) => _name = v,
          ),
          text(
            'slug',
            label: t('orgs.slug'),
            value: _slug,
            mono: true,
            direction: TextDirection.ltr,
            onChanged: (v) => _slug = v,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(
                child: text(
                  'currency',
                  label: t('orgs.currency'),
                  value: _currency,
                  mono: true,
                  direction: TextDirection.ltr,
                  formatters: const [UpperCaseFormatter()],
                  onChanged: (v) => _currency = v,
                ),
              ),
              Expanded(
                child: text(
                  'taxRate',
                  label: t('orgs.taxRate'),
                  value: _taxRate,
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  direction: TextDirection.ltr,
                  formatters: percentInputFormatters,
                  onChanged: (v) => _taxRate = v,
                ),
              ),
            ],
          ),
          OrgSwitchBox(
            label: t('orgs.taxInclusive'),
            hint: t('orgs.taxInclusiveHint'),
            value: _taxInclusive,
            onChanged: (v) => _changed(() => _taxInclusive = v),
          ),
          if (twoUp)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: Space.lg,
              children: [
                Expanded(child: serviceCharge),
                Expanded(child: serviceTaxable),
              ],
            )
          else ...[
            serviceCharge,
            serviceTaxable,
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              DashTimezoneSelect(
                key: const ValueKey('org-timezone'),
                zones: zones,
                value: _timezone,
                label: t('orgs.timezone'),
                errorText: _errors['timezone'],
                onChanged: (v) => _changed(() => _timezone = v),
              ),
              Text(
                t('orgs.timezoneHint'),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ],
          ),
          text(
            'receiptFooter',
            label: t('orgs.receiptFooter'),
            value: _receiptFooter,
            onChanged: (v) => _receiptFooter = v,
          ),
          OrgSwitchBox(
            label: t('common.active'),
            value: _active,
            onChanged: (v) => _changed(() => _active = v),
          ),
          OrgSwitchBox(
            label: t('orgs.requireTable'),
            hint: t('orgs.requireTableHint'),
            value: _requireTable,
            onChanged: (v) => _changed(() => _requireTable = v),
          ),
          OrgSwitchBox(
            label: t('orgs.customBranding'),
            hint: t('orgs.customBrandingHint'),
            value: _customBranding,
            onChanged: (v) => _changed(() => _customBranding = v),
          ),
          if (platform)
            OrgModulesBox(
              modules: _modules,
              showHint: true,
              error: _errors['modules'],
              onChanged: (v) => _changed(() => _modules = v),
            ),
          OrgSocialLinksFields(
            values: _social,
            errors: {
              for (final p in socialPlatforms) p.key: _errors['social.${p.key}'],
            },
            onChanged: (key, v) => _changed(() => _social[key] = v),
            onSubmitted: _save,
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          key: const ValueKey('org-save'),
          label: t('common.save'),
          loading: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}
