/// The provision wizard (the web's `features/orgs/provision-wizard.tsx`,
/// ADM-ORG-025..040, 057), opened by `?edit=new`: three steps — the
/// business, its first branch, its owner — then ONE `POST /orgs/provision`
/// that creates all three, and the logo uploaded to the new org after.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ApiFilePart, OrgTemplate, UploadLogoMultipart;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/tax_rate.dart' show jsNumber;
import 'org_errors.dart';
import 'org_form_parts.dart';
import 'orgs_providers.dart';
import 'provision.dart';

/// Opens the wizard; resolves when it closes.
Future<void> showProvisionWizard(BuildContext context) =>
    showDashDialog<void>(context, builder: (_) => const ProvisionWizard());

class ProvisionWizard extends ConsumerStatefulWidget {
  const ProvisionWizard({super.key});

  @override
  ConsumerState<ProvisionWizard> createState() => _ProvisionWizardState();
}

class _ProvisionWizardState extends ConsumerState<ProvisionWizard> {
  final ProvisionForm _form = ProvisionForm();
  int _step = 0;
  bool _busy = false;

  /// Create was pressed once: changes re-check the field they touch.
  bool _submitted = false;
  final Map<String, String> _errors = {};

  /// The logo, held here until the org exists (ADM-ORG-026).
  DashPickedFile? _pendingLogo;

  Translator get _t => ref.read(tProvider);

  List<String> _stepTitles(Translator t) => [
    t('orgs.wizard.stepBusiness'),
    t('orgs.wizard.stepBranch'),
    t('orgs.wizard.stepOwner'),
  ];

  void _changed(String field, VoidCallback apply, {String? also}) {
    setState(() {
      apply();
      if (_submitted) {
        for (final f in [field, ?also]) {
          final e = _form.errorOf(f, _t);
          if (e == null) {
            _errors.remove(f);
          } else {
            _errors[f] = e;
          }
        }
      }
    });
  }

  void _next() {
    final errors = _form.errorsOf(_step, _t);
    setState(() {
      for (final f in provisionStepFields[_step]!) {
        _errors.remove(f);
      }
      _errors.addAll(errors);
      if (errors.isEmpty) _step = (_step + 1).clamp(0, provisionStepCount - 1);
    });
  }

  void _back() => setState(() => _step = (_step - 1).clamp(0, 2));

  void _submit() => _step < provisionStepCount - 1 ? _next() : _create();

  Future<void> _create() async {
    if (_busy) return;
    final t = _t;
    final errors = <String, String>{
      for (var s = 0; s < provisionStepCount; s++) ..._form.errorsOf(s, t),
    };
    setState(() {
      _submitted = true;
      _errors
        ..clear()
        ..addAll(errors);
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    final api = ref.read(apiProvider);
    try {
      final created = await api.orgs.provisionOrg(body: _form.toRequest());
      final logo = _pendingLogo;
      if (logo != null) {
        try {
          await api.orgs.uploadOrgLogo(
            id: created.org.id,
            body: UploadLogoMultipart(
              logo: ApiFilePart(
                field: 'logo',
                filename: logo.name,
                bytes: logo.bytes,
                contentType: logo.mimeType,
              ),
            ),
          );
        } on Object catch (e) {
          // The org exists; a failed logo is fixable from the editor.
          if (mounted) DashToast.error(context, orgErrorWords(e, t));
        }
      }
      if (!mounted) return;
      invalidateOrgs(ref);
      DashToast.success(context, t('orgs.createdToast'));
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      final target = provisionConflictTarget(e, t);
      setState(() {
        _busy = false;
        if (target != null) {
          _step = target.step;
          _errors[target.field] = target.message;
        }
      });
      if (target == null) DashToast.error(context, orgErrorWords(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final titles = _stepTitles(t);
    final last = _step == provisionStepCount - 1;
    return DashSurface(
      title: t('orgs.newTitle'),
      description:
          '${t('orgs.wizard.stepOf', args: {'current': _step + 1, 'total': provisionStepCount})}'
          ' · ${titles[_step]}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.lg,
        children: [
          _Progress(titles: titles, step: _step, label: t('orgs.wizard.progress')),
          ...switch (_step) {
            0 => _business(context, t),
            1 => _branch(t),
            _ => _owner(context, t),
          },
        ],
      ),
      actions: [
        if (_step == 0)
          DashButton(
            label: t('common.cancel'),
            variant: DashButtonVariant.outline,
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          )
        else
          DashButton(
            label: t('common.back'),
            variant: DashButtonVariant.outline,
            onPressed: _busy ? null : _back,
          ),
        if (!last)
          DashButton(
            key: const ValueKey('wizard-next'),
            label: t('common.next'),
            onPressed: _next,
          )
        else
          DashButton(
            key: const ValueKey('wizard-create'),
            label: t('common.create'),
            loading: _busy,
            onPressed: _create,
          ),
      ],
    );
  }

  Widget _text(
    String field, {
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    bool mono = false,
    bool obscure = false,
    int? maxLength,
    TextInputType? keyboard,
    TextDirection? direction,
    List<TextInputFormatter>? formatters,
    String? also,
  }) => DashTextField(
    key: ValueKey('wizard-$field'),
    label: label,
    value: value,
    mono: mono,
    obscure: obscure,
    maxLength: maxLength,
    keyboardType: keyboard,
    textDirection: direction,
    inputFormatters: formatters,
    errorText: _errors[field],
    onChanged: (v) => _changed(field, () => onChanged(v), also: also),
    onSubmitted: (_) => _submit(),
  );

  List<Widget> _business(BuildContext context, Translator t) {
    final c = context.madarColors;
    final templates = ref.watch(orgTemplatesProvider);
    final zones = ref.watch(orgTimezonesProvider).value ?? const <String>[];
    final templateError = _errors['template'];
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs + DashMetrics.hair,
        children: [
          OrgFieldLabel(t('orgs.logo')),
          DashImageUploader(
            key: const ValueKey('wizard-logo'),
            value: null,
            hint: t('orgs.logoHint'),
            semanticLabel: t('orgs.logo'),
            onPick: () => pickOrgImage(ref),
            onUpload: (file) async {
              setState(() => _pendingLogo = file);
              return null;
            },
            onRemove: _pendingLogo == null
                ? null
                : () async => setState(() => _pendingLogo = null),
          ),
        ],
      ),
      _text(
        'name',
        label: t('orgs.orgName'),
        value: _form.name,
        also: 'slug',
        onChanged: (v) {
          _form
            ..name = v
            ..slug = slugify(v);
        },
      ),
      _text(
        'slug',
        label: t('orgs.slug'),
        value: _form.slug,
        mono: true,
        direction: TextDirection.ltr,
        onChanged: (v) => _form.slug = v,
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          OrgFieldLabel(
            t('orgs.wizard.template'),
            invalid: templateError != null,
          ),
          _TemplateCards(
            templates: templates.value ?? const [],
            selected: _form.template,
            arabic: t.isRtl,
            onPick: (key) =>
                _changed('template', () => _form.template = key),
          ),
          if (templates.hasError && !templates.isLoading)
            Text(
              orgErrorWords(templates.error, t),
              style: DashType.small.copyWith(color: c.errorText),
            ),
          if (templateError != null)
            Semantics(
              liveRegion: true,
              child: Text(
                templateError,
                style: DashType.body.copyWith(color: c.errorText),
              ),
            ),
        ],
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          Expanded(
            child: _text(
              'currency',
              label: t('orgs.currency'),
              value: _form.currency,
              mono: true,
              direction: TextDirection.ltr,
              formatters: const [UpperCaseFormatter()],
              onChanged: (v) => _form.currency = v,
            ),
          ),
          Expanded(
            child: _text(
              'taxRate',
              label: t('orgs.taxRate'),
              value: _form.taxRate,
              keyboard: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              direction: TextDirection.ltr,
              formatters: percentInputFormatters,
              onChanged: (v) => _form.taxRate = v,
            ),
          ),
        ],
      ),
      DashTimezoneSelect(
        key: const ValueKey('wizard-timezone'),
        zones: zones,
        value: _form.timezone.isEmpty ? null : _form.timezone,
        label: t('orgs.timezone'),
        errorText: _errors['timezone'],
        onChanged: (v) => _changed('timezone', () => _form.timezone = v),
      ),
      OrgModulesBox(
        modules: _form.modules,
        error: _errors['modules'],
        onChanged: (v) => _changed('modules', () => _form.modules = v),
      ),
    ];
  }

  List<Widget> _branch(Translator t) => [
    _text(
      'branchName',
      label: t('orgs.wizard.branchName'),
      value: _form.branchName,
      onChanged: (v) => _form.branchName = v,
    ),
    _text(
      'address',
      label: t('orgs.wizard.address'),
      value: _form.address,
      onChanged: (v) => _form.address = v,
    ),
    _text(
      'phone',
      label: t('orgs.wizard.phone'),
      value: _form.phone,
      keyboard: TextInputType.phone,
      direction: TextDirection.ltr,
      onChanged: (v) => _form.phone = v,
    ),
  ];

  List<Widget> _owner(BuildContext context, Translator t) {
    final c = context.madarColors;
    final bullet = DashType.body.copyWith(color: c.textSecondary);
    Widget line(String s) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        ExcludeSemantics(child: Text('•', style: bullet)),
        Expanded(child: Text(s, style: bullet)),
      ],
    );
    return [
      _text(
        'ownerName',
        label: t('orgs.wizard.ownerName'),
        value: _form.ownerName,
        onChanged: (v) => _form.ownerName = v,
      ),
      _text(
        'email',
        label: t('orgs.wizard.email'),
        value: _form.email,
        keyboard: TextInputType.emailAddress,
        direction: TextDirection.ltr,
        onChanged: (v) => _form.email = v,
      ),
      _text(
        'password',
        label: t('orgs.wizard.password'),
        value: _form.password,
        obscure: true,
        onChanged: (v) => _form.password = v,
      ),
      _text(
        'pin',
        label: t('orgs.wizard.pin'),
        value: _form.pin,
        mono: true,
        maxLength: 6,
        keyboard: TextInputType.number,
        direction: TextDirection.ltr,
        onChanged: (v) => _form.pin = v,
      ),
      OrgMutedBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            Text(
              t('orgs.wizard.summaryTitle'),
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: Space.xs),
            line(t('orgs.wizard.summaryVoid')),
            line(t('orgs.wizard.summaryRefund')),
            line(t('orgs.wizard.summaryWaiter')),
            line(
              t(
                'orgs.wizard.summaryTax',
                args: {'rate': jsNumber(_form.summaryRate)},
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

/// The steps strip (aria "Progress"): done steps show a check, the current
/// one is marked.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.titles,
    required this.step,
    required this.label,
  });

  final List<String> titles;
  final int step;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Semantics(
      container: true,
      label: label,
      child: Row(
        spacing: Space.sm,
        children: [
          for (var i = 0; i < titles.length; i++)
            Expanded(
              child: Semantics(
                selected: i == step,
                child: Row(
                  spacing: Space.sm,
                  children: [
                    Container(
                      width: Space.xl,
                      height: Space.xl,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < step ? c.accent : null,
                        border: Border.all(
                          color: i <= step ? c.accent : c.border,
                        ),
                      ),
                      child: i < step
                          ? DashIcon(
                              'check',
                              size: IconSize.xs,
                              color: c.textOnAccent,
                            )
                          : Text(
                              '${i + 1}',
                              style: DashType.smallStrong.copyWith(
                                color: i == step
                                    ? c.textPrimary
                                    : c.textSecondary,
                              ),
                            ),
                    ),
                    Flexible(
                      child: MadarClippedText(
                        titles[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (i == step
                                ? DashType.smallMedium
                                : DashType.small)
                            .copyWith(
                              color: i == step
                                  ? c.textPrimary
                                  : c.textSecondary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The template radio cards (two up from 640 wide): the name in the active
/// language and, for the two known templates, a line on what it sets up.
class _TemplateCards extends StatelessWidget {
  const _TemplateCards({
    required this.templates,
    required this.selected,
    required this.arabic,
    required this.onPick,
  });

  final List<OrgTemplate> templates;
  final String selected;
  final bool arabic;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.translator;
    final twoUp = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    Widget card(OrgTemplate tpl) {
      final on = tpl.key == selected;
      final hint = switch (tpl.key) {
        'restaurant' => t('orgs.wizard.restaurantHint'),
        'cafe' => t('orgs.wizard.cafeHint'),
        _ => null,
      };
      final name = arabic ? tpl.nameAr : tpl.nameEn;
      return Semantics(
        inMutuallyExclusiveGroup: true,
        child: DashPressable(
          key: ValueKey('wizard-template-${tpl.key}'),
          onTap: () => onPick(tpl.key),
          checked: on,
          semanticLabel: name,
          pressScale: false,
          builder: (context, s) => Container(
            constraints: const BoxConstraints(minHeight: DashMetrics.target),
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: on
                  ? c.accent.withValues(alpha: 0.05)
                  : (s.highlighted ? c.hover : null),
              borderRadius: BorderRadius.circular(Radii.xs),
              border: Border.all(color: on ? c.accent : c.border),
            ),
            foregroundDecoration: dashFocusRing(
              context,
              s,
              BorderRadius.circular(Radii.xs),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                Text(
                  name,
                  style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                ),
                if (hint != null)
                  Text(
                    hint,
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final cards = [for (final tpl in templates) card(tpl)];
    if (!twoUp) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: cards,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        for (var i = 0; i < cards.length; i += 2)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                Expanded(child: cards[i]),
                if (i + 1 < cards.length)
                  Expanded(child: cards[i + 1])
                else
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
      ],
    );
  }
}
