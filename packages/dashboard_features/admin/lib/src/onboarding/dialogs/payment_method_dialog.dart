/// "New payment method" (ADM-ONB-016; the web's
/// `features/payment-methods/payment-method-dialog.tsx` in create mode, the
/// only mode onboarding opens): identifier, English and Arabic labels, icon,
/// colour, "Accepts cash", "Active" and "Share with partners". Save posts
/// `POST /payment-methods`, refreshes every `/payment-methods…` read, toasts
/// "Saved" and closes; a refusal toasts the server's words and keeps it open.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show CreatePaymentMethodRequest, OrgPaymentMethod;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'menu_reads.dart';

/// Opens the dialog; resolves with the created method, or null.
Future<OrgPaymentMethod?> showPaymentMethodDialog(BuildContext context) =>
    showDashDialog<OrgPaymentMethod>(
      context,
      width: PaymentMethodDialog.width,
      builder: (_) => const PaymentMethodDialog(),
    );

/// The selectable icons (`PM_ICONS`): the stored id, its label key and glyph.
const List<(String id, String glyph)> pmIcons = [
  ('money', 'banknote'),
  ('credit_card', 'credit-card'),
  ('wallet', 'wallet'),
  ('pie_chart', 'pie-chart'),
  ('delivery', 'truck'),
  ('qr_code', 'qr-code'),
  ('bank', 'landmark'),
  ('gift_card', 'gift'),
  ('smartphone', 'smartphone'),
  ('receipt', 'receipt'),
  ('store', 'store'),
  ('star', 'star'),
  ('link', 'link'),
];

/// The accent colours a method may carry (`PM_COLORS`). They are the
/// method's own identity, stored as hex and drawn literally in both themes,
/// so they are data here, not theme tokens.
const List<String> pmColors = [
  '#0F172A',
  '#334155',
  '#10B981',
  '#059669',
  '#3B82F6',
  '#2563EB',
  '#8B5CF6',
  '#7C3AED',
  '#F59E0B',
  '#D97706',
  '#EF4444',
  '#DC2626',
  '#EC4899',
  '#DB2777',
];

/// The identifier as typed: lowercase, anything but `a-z 0-9 _` becomes `_`
/// (the web's onChange).
String pmIdentifier(String v) =>
    v.toLowerCase().replaceAll(RegExp('[^a-z0-9_]'), '_');

/// The form's messages (zod's schema), keyed by field; empty = valid.
Map<String, String> validatePaymentMethod({
  required String name,
  required String labelEn,
  required Translator t,
}) => {
  if (name.isEmpty)
    'name': t('common.requiredField')
  else if (!RegExp(r'^[a-z0-9_]+$').hasMatch(name))
    'name': t('settings.pm.idError'),
  if (labelEn.isEmpty) 'labelEn': t('common.requiredField'),
};

class PaymentMethodDialog extends ConsumerStatefulWidget {
  const PaymentMethodDialog({super.key});

  /// `sm:max-w-[480px]`.
  static const double width = 480;

  @override
  ConsumerState<PaymentMethodDialog> createState() =>
      _PaymentMethodDialogState();
}

class _PaymentMethodDialogState extends ConsumerState<PaymentMethodDialog> {
  String _name = '';
  String _labelEn = '';
  String _labelAr = '';
  String _icon = 'money';
  String _color = pmColors[2];
  bool _isCash = false;
  bool _isActive = true;
  bool _visible = true;
  bool _submitted = false;
  bool _busy = false;

  Future<void> _save() async {
    final t = ref.read(tProvider);
    setState(() => _submitted = true);
    if (validatePaymentMethod(
      name: _name,
      labelEn: _labelEn,
      t: t,
    ).isNotEmpty) {
      return;
    }
    setState(() => _busy = true);
    final invalidate = ref.menuInvalidate;
    try {
      final created = await ref
          .read(apiProvider)
          .paymentMethods
          .createPaymentMethod(
            body: CreatePaymentMethodRequest(
              name: _name,
              labelTranslations: {'en': _labelEn, 'ar': _labelAr},
              color: _color,
              icon: _icon,
              isCash: _isCash,
              isActive: _isActive,
              visibleInIntegrations: _visible,
            ),
          );
      invalidate.paymentMethods();
      if (!mounted) return;
      DashToast.success(context, t('common.saved'));
      Navigator.of(context).pop(created);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final errors = _submitted
        ? validatePaymentMethod(name: _name, labelEn: _labelEn, t: t)
        : const <String, String>{};
    final twoUp = !DashBreakpoints.isPhone(context);

    Widget pair(Widget a, Widget b) => twoUp
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(child: a),
              Expanded(child: b),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [a, b],
          );

    return DashSurface(
      title: t('settings.pm.newTitle'),
      description: t('settings.paymentMethodsHint'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DashTextField(
            key: const ValueKey('pm-id'),
            label: t('settings.pm.id'),
            value: _name,
            // A literal sample identifier, as on the web.
            placeholder: 'e.g. visa_card',
            mono: true,
            textDirection: TextDirection.ltr,
            description: t('settings.pm.idHint'),
            errorText: errors['name'],
            inputFormatters: const [_IdentifierFormatter()],
            onChanged: (v) => setState(() => _name = v),
          ),
          pair(
            DashTextField(
              key: const ValueKey('pm-label-en'),
              label: t('settings.pm.labelEn'),
              value: _labelEn,
              placeholder: 'Visa Card',
              errorText: errors['labelEn'],
              onChanged: (v) => setState(() => _labelEn = v),
            ),
            DashTextField(
              key: const ValueKey('pm-label-ar'),
              label: t('settings.pm.labelAr'),
              value: _labelAr,
              placeholder: 'فيزا',
              textDirection: TextDirection.rtl,
              onChanged: (v) => setState(() => _labelAr = v),
            ),
          ),
          DashSelectField<String>(
            key: const ValueKey('pm-icon'),
            label: t('settings.pm.icon'),
            value: _icon,
            options: [
              for (final (id, glyph) in pmIcons)
                DashOption(
                  value: id,
                  label: t('settings.pm.iconLabel.$id'),
                  icon: glyph,
                ),
            ],
            onChanged: (v) => setState(() => _icon = v),
          ),
          _ColorPicker(
            label: t('settings.pm.color'),
            value: _color,
            onChanged: (v) => setState(() => _color = v),
          ),
          pair(
            _SwitchCard(
              label: t('settings.pm.acceptsCash'),
              description: t('settings.pm.acceptsCashHint'),
              value: _isCash,
              onChanged: (v) => setState(() => _isCash = v),
            ),
            _SwitchCard(
              label: t('common.active'),
              description: t('settings.pm.statusHint'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ),
          _SwitchCard(
            label: t('settings.pm.visibleInIntegrations'),
            description: t('settings.pm.visibleInIntegrationsHint'),
            value: _visible,
            onChanged: (v) => setState(() => _visible = v),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(label: t('common.save'), loading: _busy, onPressed: _save),
      ],
    );
  }
}

class _IdentifierFormatter extends TextInputFormatter {
  const _IdentifierFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: pmIdentifier(newValue.text));
}

/// A switch with its words in a bordered card (the web's `FormItem` box).
class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.hairline),
      ),
      child: DashSwitchField(
        label: label,
        description: description,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// The 14 swatches, 40 round, the picked one ticked.
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  static const double _swatch = Space.xxl + Space.sm;

  static Color _parse(String hex) =>
      Color(int.parse('FF${hex.substring(1)}', radix: 16));

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        Text(label, style: DashType.bodyMedium.copyWith(color: c.textPrimary)),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final hex in pmColors)
              DashPressable(
                key: ValueKey('pm-color-$hex'),
                onTap: () => onChanged(hex),
                semanticLabel: hex,
                selected: hex == value,
                excludeChildSemantics: true,
                builder: (context, s) => Container(
                  width: _swatch,
                  height: _swatch,
                  alignment: Alignment.center,
                  foregroundDecoration: dashFocusRing(
                    context,
                    s,
                    BorderRadius.circular(_swatch),
                  ),
                  decoration: BoxDecoration(
                    color: _parse(hex),
                    shape: BoxShape.circle,
                  ),
                  child: hex == value
                      ? DashIcon('check', color: c.textOnAccent)
                      : null,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
