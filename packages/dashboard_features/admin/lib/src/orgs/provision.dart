/// The provision wizard's rules (the web's `features/orgs/provision.ts`):
/// the slug auto-fill, each step's checks, and the `POST /orgs/provision`
/// body. Pure: the wizard widget only sequences them.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ProvisionBranch, ProvisionOrgRequest, ProvisionOwner;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show dashParseNumber;

import '../shared/tax_rate.dart';

/// The slug a name suggests: lower case, trimmed, whitespace runs → "-",
/// anything but `a-z 0-9 -` dropped (an Arabic-only name gives "").
String slugify(String s) => s
    .toLowerCase()
    .trim()
    .replaceAll(RegExp(r'\s+'), '-')
    .replaceAll(RegExp('[^a-z0-9-]'), '');

/// zod v4's `z.email()` pattern, checked on the value as typed (untrimmed:
/// a leading space reads "Enter a valid email", ADM-ORG-059).
final RegExp emailPattern = RegExp(
  r"^(?!\.)(?!.*\.\.)([A-Za-z0-9_'+\-\.]*)[A-Za-z0-9_+-]@([A-Za-z0-9][A-Za-z0-9\-]*\.)+[A-Za-z]{2,}$",
);

/// A percent typed into a rate field, as `z.coerce.number()` reads it:
/// empty is 0, Latin or Arabic digits, null when it is not a number.
double? parsePercentInput(String raw) {
  if (raw.trim().isEmpty) return 0;
  return dashParseNumber(raw);
}

/// The 0..100 check of a rate field (`orgs.taxRateRange`), or null.
String? percentError(String raw, Translator t) {
  final n = parsePercentInput(raw);
  if (n == null || n.isNaN || n < 0 || n > kMaxPercent) {
    return t('orgs.taxRateRange');
  }
  return null;
}

/// The wizard's three steps (0-based): business, first branch, owner.
const int provisionStepCount = 3;

/// The fields each step owns (`STEP_FIELD`), for its Next.
const Map<int, List<String>> provisionStepFields = {
  0: ['name', 'slug', 'template', 'currency', 'timezone', 'taxRate', 'modules'],
  1: ['branchName', 'address', 'phone'],
  2: ['ownerName', 'email', 'password', 'pin'],
};

/// What the wizard holds (`ProvisionFormInput`), with the web's defaults
/// (`emptyProvisionForm`).
class ProvisionForm {
  String name = '';
  String slug = '';
  String template = '';
  String currency = 'EGP';
  String timezone = 'Africa/Cairo';

  /// A PERCENT as typed; a fraction on the wire.
  String taxRate = '0';

  /// In the order they were ticked (the web's array).
  List<String> modules = ['pos'];

  String branchName = '';
  String address = '';
  String phone = '';

  String ownerName = '';
  String email = '';
  String password = '';
  String pin = '';

  /// The step a field belongs to.
  static int stepOf(String field) => provisionStepFields.entries
      .firstWhere((e) => e.value.contains(field))
      .key;

  /// The error of [field], or null (`provisionSchemas`).
  String? errorOf(String field, Translator t) {
    final required = t('common.requiredField');
    switch (field) {
      case 'name':
        return name.trim().isEmpty ? required : null;
      case 'slug':
        return slug.trim().isEmpty ? required : null;
      case 'template':
        return template.isEmpty ? t('orgs.wizard.templateRequired') : null;
      case 'currency':
        return currency.trim().isEmpty ? required : null;
      case 'timezone':
        return timezone.isEmpty ? required : null;
      case 'taxRate':
        return percentError(taxRate, t);
      case 'modules':
        return modules.isEmpty ? t('dawam.modulesAtLeastOne') : null;
      case 'branchName':
        return branchName.trim().isEmpty ? required : null;
      case 'ownerName':
        return ownerName.trim().isEmpty ? required : null;
      case 'email':
        return emailPattern.hasMatch(email)
            ? null
            : t('orgs.wizard.emailInvalid');
      case 'password':
        return password.length < 8 ? t('orgs.wizard.passwordMin') : null;
      case 'pin':
        return pin.isEmpty || RegExp(r'^\d{6}$').hasMatch(pin)
            ? null
            : t('orgs.wizard.pinInvalid');
    }
    return null;
  }

  /// Every error of [step]'s fields.
  Map<String, String> errorsOf(int step, Translator t) => {
    for (final f in provisionStepFields[step]!) f: ?errorOf(f, t),
  };

  /// The rate the summary names (`Number(taxRate) || 0`).
  double get summaryRate {
    final n = parsePercentInput(taxRate);
    return n == null || n.isNaN ? 0 : n;
  }

  static String? _opt(String s) {
    final v = s.trim();
    return v.isEmpty ? null : v;
  }

  /// The `POST /orgs/provision` body (`toProvisionRequest`): trimmed, the
  /// currency upper-cased, the rate a fraction, blank optionals left out.
  ProvisionOrgRequest toRequest() => ProvisionOrgRequest(
    name: name.trim(),
    slug: slug.trim(),
    template: template,
    currencyCode: currency.trim().toUpperCase(),
    timezone: timezone,
    taxRate: percentToFraction(parsePercentInput(taxRate) ?? 0),
    modules: [...modules],
    branch: ProvisionBranch(
      name: branchName.trim(),
      address: _opt(address),
      phone: _opt(phone),
    ),
    owner: ProvisionOwner(
      name: ownerName.trim(),
      email: email.trim(),
      password: password,
      pin: _opt(pin),
    ),
  );
}
