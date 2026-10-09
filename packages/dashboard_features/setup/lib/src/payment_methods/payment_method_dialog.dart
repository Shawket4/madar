/// The payment method editor (web `payment-method-dialog.tsx`,
/// SET-PAY-013..019, -041): identifier, the two labels, icon, colour and the
/// three switches. New → `POST /payment-methods`; edit → `PUT
/// /payment-methods/{id}` with every field. A success toasts "Saved",
/// refetches `/payment-methods*` and closes; a failure toasts the server's
/// words and stays open. Below 760 wide it is a full-screen sheet.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        CreatePaymentMethodRequest,
        OrgPaymentMethod,
        UpdatePaymentMethodRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pm_data.dart';

/// The dialog's width (`sm:max-w-[480px]`).
const double pmDialogWidth = 480;

/// Opens the editor for [method] (null = a new one); [host] is the page,
/// which shows the result's toast should the dialog already be gone.
Future<void> showPaymentMethodDialog(
  BuildContext host,
  OrgPaymentMethod? method,
) => showDashDialog<void>(
  host,
  width: pmDialogWidth,
  builder: (_) => PaymentMethodDialog(method: method, host: host),
);

/// Typing into the identifier: lowercase, `a-z0-9_` only.
class _Identifier extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: sanitizeIdentifier(newValue.text));
}

class PaymentMethodDialog extends ConsumerStatefulWidget {
  const PaymentMethodDialog({required this.method, this.host, super.key});

  final OrgPaymentMethod? method;
  final BuildContext? host;

  @override
  ConsumerState<PaymentMethodDialog> createState() => _PmDialogState();
}

class _PmDialogState extends ConsumerState<PaymentMethodDialog> {
  final _form = GlobalKey<FormState>();
  late OrgPaymentMethod? _m = widget.method;
  late String _name;
  late String _labelEn;
  late String _labelAr;
  late String _icon;
  late String _color;
  late bool _isCash;
  late bool _isActive;
  late bool _visible;

  /// Set by the person's first change: until then a fresher row from the
  /// list fills the form again (a background refresh lands).
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _seed(_m);
  }

  void _seed(OrgPaymentMethod? m) {
    final tr = m == null ? const <String, String>{} : pmTranslations(m);
    _name = m?.name ?? '';
    _labelEn = tr['en'] ?? '';
    _labelAr = tr['ar'] ?? '';
    _icon = (m?.icon.isNotEmpty ?? false) ? m!.icon : 'money';
    _color = (m?.color.startsWith('#') ?? false) ? m!.color : pmDefaultColor;
    _isCash = m?.isCash ?? false;
    _isActive = m?.isActive ?? true;
    _visible = m?.visibleInIntegrations ?? true;
  }

  void _edit(VoidCallback change) => setState(() {
    _edited = true;
    change();
  });
  bool _saving = false;

  /// Identifiers never change once created (and a system method's never).
  bool get _locked => _m != null;

  Future<void> _save() async {
    if (_saving) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).paymentMethods;
    final bus = ref.read(realtimeBusProvider);
    final host = widget.host;
    final labels = {'en': _labelEn, 'ar': _labelAr};
    setState(() => _saving = true);
    try {
      final m = _m;
      if (m != null) {
        await api.updatePaymentMethod(
          id: m.id,
          body: UpdatePaymentMethodRequest(
            name: _name,
            labelTranslations: labels,
            color: _color,
            icon: _icon,
            isCash: _isCash,
            isActive: _isActive,
            visibleInIntegrations: _visible,
          ),
        );
      } else {
        await api.createPaymentMethod(
          body: CreatePaymentMethodRequest(
            name: _name,
            labelTranslations: labels,
            color: _color,
            icon: _icon,
            isCash: _isCash,
            isActive: _isActive,
            visibleInIntegrations: _visible,
          ),
        );
      }
      invalidatePaymentMethods(bus);
      final at = mounted ? context : host;
      if (at != null && at.mounted) DashToast.success(at, t('common.saved'));
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      final at = mounted ? context : host;
      if (at != null && at.mounted) DashToast.error(at, errorMessage(e, t));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    if (_m != null) {
      final fresh = ref
          .watch(paymentMethodsProvider)
          .value
          ?.where((m) => m.id == _m!.id)
          .firstOrNull;
      if (fresh != null && !_edited && !identical(fresh, _m)) {
        _m = fresh;
        _seed(fresh);
      }
    }
    return Form(
      key: _form,
      child: DashSurface(
        title: t(_locked ? 'settings.pm.editTitle' : 'settings.pm.newTitle'),
        description: t('settings.paymentMethodsHint'),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            DashTextField(
              key: const ValueKey('pm-id'),
              label: t('settings.pm.id'),
              value: _name,
              mono: true,
              enabled: !_locked,
              textDirection: TextDirection.ltr,
              placeholder: t('settings.pm.idPlaceholder'),
              description: t(
                _locked ? 'settings.pm.idLocked' : 'settings.pm.idHint',
              ),
              inputFormatters: [_Identifier()],
              onChanged: (v) => _edit(() => _name = v),
              onSubmitted: (_) => _save(),
              validator: (v) => v.isEmpty
                  ? t('common.requiredField')
                  : pmIdentifierPattern.hasMatch(v)
                  ? null
                  : t('settings.pm.idError'),
            ),
            // Two columns at every width, as the web's form.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(
                  child: DashTextField(
                    key: const ValueKey('pm-label-en'),
                    label: t('settings.pm.labelEn'),
                    value: _labelEn,
                    placeholder: t('settings.pm.labelEnPlaceholder'),
                    onChanged: (v) => _edit(() => _labelEn = v),
                    onSubmitted: (_) => _save(),
                    validator: (v) =>
                        v.isEmpty ? t('common.requiredField') : null,
                  ),
                ),
                Expanded(
                  child: DashTextField(
                    key: const ValueKey('pm-label-ar'),
                    label: t('settings.pm.labelAr'),
                    value: _labelAr,
                    textDirection: TextDirection.rtl,
                    placeholder: t('settings.pm.labelArPlaceholder'),
                    onChanged: (v) => _edit(() => _labelAr = v),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
            DashSelectField<String>(
              key: const ValueKey('pm-icon'),
              label: t('settings.pm.icon'),
              value: _icon,
              options: [
                for (final i in pmIcons)
                  DashOption(value: i.id, label: t(i.labelKey), icon: i.glyph),
              ],
              onChanged: (v) => _edit(() => _icon = v),
            ),
            DashFormField<String>(
              label: t('settings.pm.color'),
              value: _color,
              builder: (context, _) => Wrap(
                key: const ValueKey('pm-colors'),
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final hex in pmColors)
                    _Swatch(
                      hex: hex,
                      selected: _color == hex,
                      onTap: () => _edit(() => _color = hex),
                    ),
                ],
              ),
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.md,
                children: [
                  Expanded(
                    child: _SwitchCard(
                      key: const ValueKey('pm-is-cash'),
                      label: t('settings.pm.acceptsCash'),
                      hint: t('settings.pm.acceptsCashHint'),
                      value: _isCash,
                      onChanged: (v) => _edit(() => _isCash = v),
                    ),
                  ),
                  Expanded(
                    child: _SwitchCard(
                      key: const ValueKey('pm-is-active'),
                      label: t('common.active'),
                      hint: t('settings.pm.statusHint'),
                      value: _isActive,
                      onChanged: (v) => _edit(() => _isActive = v),
                    ),
                  ),
                ],
              ),
            ),
            _SwitchCard(
              key: const ValueKey('pm-visible'),
              label: t('settings.pm.visibleInIntegrations'),
              hint: t('settings.pm.visibleInIntegrationsHint'),
              value: _visible,
              onChanged: (v) => _edit(() => _visible = v),
            ),
          ],
        ),
        actions: [
          DashButton(
            key: const ValueKey('pm-cancel'),
            label: t('common.cancel'),
            variant: DashButtonVariant.outline,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          DashButton(
            key: const ValueKey('pm-save'),
            label: t('common.save'),
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// One colour choice: a 40 disc in its literal colour, a check on the chosen
/// one; its name for a screen reader is the hex (`aria-label`, pressed).
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DashPressable(
    key: ValueKey('pm-color-$hex'),
    onTap: onTap,
    selected: selected,
    semanticLabel: hex,
    excludeChildSemantics: true,
    builder: (context, s) => SizedBox.square(
      dimension: DashMetrics.target,
      child: Center(
        child: Container(
          width: Space.xxl + Space.sm,
          height: Space.xxl + Space.sm,
          decoration: BoxDecoration(
            color: hexColor(hex),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          // The identity colours are drawn literally in both themes.
          child: selected
              ? const DashIcon('check', size: IconSize.sm, color: Colors.white)
              : null,
        ),
      ),
    ),
  );
}

/// A bordered switch row (label, quiet hint, the switch); a tap anywhere on
/// it toggles.
class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String hint;
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
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: DashMetrics.hair,
                children: [
                  Text(
                    label,
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    hint,
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
