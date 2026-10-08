// The Organizations rules on their own (the web's provision.test.ts,
// social-links.test.ts, tax-rate.test.ts and errors ladder): slugs, the
// provision body, social links, rates and the words for a failure.
import 'package:dashboard_admin/src/orgs/org_errors.dart';
import 'package:dashboard_admin/src/orgs/provision.dart';
import 'package:dashboard_admin/src/orgs/social_links.dart';
import 'package:dashboard_admin/src/shared/tax_rate.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';

Strings _tables() => Strings({
  'en': {
    'common.requiredField': 'This field is required',
    'orgs.taxRateRange': 'Enter a rate between 0 and 100',
    'orgs.wizard.templateRequired': 'Choose a template',
    'dawam.modulesAtLeastOne': 'Pick at least one module',
    'orgs.wizard.emailInvalid': 'Enter a valid email',
    'orgs.wizard.passwordMin': 'At least 8 characters',
    'orgs.wizard.pinInvalid': 'The PIN is exactly 6 digits',
    'orgs.socialInvalid': 'Use the full address, starting with https://',
    'errors.unauthorized': "You don't have permission to perform this action.",
    'errors.tooManyRequests': 'Too many requests just now.',
    'errors.unknown': 'An unexpected error occurred.',
    'errors.conflict': 'This action conflicts with the current state.',
    'errors.validation': 'Please check the highlighted fields.',
    'errors.server': 'Server error — please try again later.',
    'errors.notFound': 'Not found.',
    'errors.sessionExpired': 'Your session has expired.',
    'errors.networkError': 'Network error.',
    'errors.codes.ORG_SUSPENDED': 'This business is suspended.',
  },
  'ar': {
    'errors.unauthorized': 'ليس لديك صلاحية لتنفيذ هذا الإجراء.',
    'errors.conflict': 'هذا الإجراء يتعارض مع الحالة الحالية.',
    'errors.validation': 'يرجى مراجعة الحقول المظللة.',
    'errors.server': 'خطأ في الخادم.',
    'errors.notFound': 'غير موجود.',
    'errors.unknown': 'حدث خطأ غير متوقع.',
    'errors.tooManyRequests': 'طلبات كثيرة.',
    'errors.sessionExpired': 'انتهت جلستك.',
    'errors.networkError': 'خطأ في الشبكة.',
    'errors.codes.ORG_SUSPENDED': 'هذا النشاط موقوف.',
  },
});

ApiException _err(int status, String error, {String? code}) => ApiException(
  status: status,
  code: code,
  message: error,
  details: {'error': error, 'code': ?code},
);

void main() {
  final strings = _tables();
  final en = Translator(strings, 'en');
  final ar = Translator(strings, 'ar');

  group('ADM-ORG-027 slugify', () {
    test('lower case, dashes for spaces, nothing else', () {
      expect(slugify('Drops Coffee'), 'drops-coffee');
      expect(slugify('  Layali   Bistro 2! '), 'layali-bistro-2');
      expect(slugify('Café Riche'), 'caf-riche');
    });

    test('ADM-ORG-057 an Arabic-only name gives nothing', () {
      expect(slugify('ليالي'), '');
    });
  });

  group('ADM-ORG-028..037 the wizard\'s checks and body', () {
    ProvisionForm valid() => ProvisionForm()
      ..name = 'Drops'
      ..slug = 'drops'
      ..template = 'cafe'
      ..currency = 'egp'
      ..taxRate = '14'
      ..branchName = 'Zamalek'
      ..phone = '  '
      ..ownerName = 'Mona'
      ..email = 'mona@example.com'
      ..password = 'secret123';

    test('an empty step 1 needs name, slug and template', () {
      final e = ProvisionForm().errorsOf(0, en);
      expect(e.keys, containsAll(['name', 'slug', 'template']));
      expect(e['template'], 'Choose a template');
      expect(e.containsKey('currency'), isFalse);
    });

    test('rates outside 0..100 are refused; blank is 0', () {
      final f = valid()..taxRate = '100.5';
      expect(f.errorOf('taxRate', en), 'Enter a rate between 0 and 100');
      f.taxRate = '';
      expect(f.errorOf('taxRate', en), isNull);
      expect(f.summaryRate, 0);
      f.taxRate = '١٤';
      expect(f.errorOf('taxRate', en), isNull);
      expect(f.summaryRate, 14);
    });

    test('at least one module', () {
      final f = valid()..modules = [];
      expect(f.errorOf('modules', en), 'Pick at least one module');
    });

    test('the owner: email as typed, 8 characters, a 6-digit PIN', () {
      final f = valid()
        ..email = ' mona@example.com'
        ..password = '1234567'
        ..pin = '12a456';
      final e = f.errorsOf(2, en);
      expect(e['email'], 'Enter a valid email');
      expect(e['password'], 'At least 8 characters');
      expect(e['pin'], 'The PIN is exactly 6 digits');
      f
        ..email = 'mona@example.com'
        ..password = '12345678'
        ..pin = '';
      expect(f.errorsOf(2, en), isEmpty);
    });

    test('the body: trimmed, upper-cased currency, a fraction, blanks out', () {
      final body = valid().toRequest().toJson();
      expect(body, {
        'branch': {'name': 'Zamalek'},
        'currency_code': 'EGP',
        'modules': ['pos'],
        'name': 'Drops',
        'owner': {
          'email': 'mona@example.com',
          'name': 'Mona',
          'password': 'secret123',
        },
        'slug': 'drops',
        'tax_rate': 0.14,
        'template': 'cafe',
        'timezone': 'Africa/Cairo',
      });
    });
  });

  group('ADM-ORG-054 social links', () {
    test('https with a host, nothing else', () {
      expect(isHttpsUrl('https://instagram.com/rue'), isTrue);
      expect(isHttpsUrl('http://instagram.com/rue'), isFalse);
      expect(isHttpsUrl('@rue'), isFalse);
      expect(isHttpsUrl('instagram.com/rue'), isFalse);
      expect(isHttpsUrl('https://'), isFalse);
      expect(isHttpsUrl('javascript:alert(1)'), isFalse);
    });

    test('the fields take strings only', () {
      final form = socialLinksToForm({
        'instagram': 'https://a.example',
        'facebook': 42,
      });
      expect(form['instagram'], 'https://a.example');
      expect(form['facebook'], '');
      expect(form, hasLength(8));
    });

    test('a save sends what was typed and "" for a cleared link', () {
      final empty = socialLinksToForm(null);
      expect(socialLinksPatch({...empty, 'x': 'https://x.com/rue'}, null), {
        'x': 'https://x.com/rue',
      });
      expect(socialLinksPatch(empty, {'tiktok': 'https://tiktok.com/@rue'}), {
        'tiktok': '',
      });
      expect(
        socialLinksPatch(
          {...empty, 'whatsapp': '  https://wa.me/20  '},
          null,
        ),
        {'whatsapp': 'https://wa.me/20'},
      );
    });

    test('an invalid link reads "Use the full address…"', () {
      expect(
        socialLinkError('http://x.com', en),
        'Use the full address, starting with https://',
      );
      expect(socialLinkError('  ', en), isNull);
    });
  });

  group('ADM-ORG-008 / 046 rates', () {
    test('fraction on the wire, percent on screen', () {
      expect(fractionToPercent(0.14), 14);
      expect(percentToFraction(14), 0.14);
      expect(percentToFraction(12.5), 0.125);
      expect(formatRate(0.14), '14%');
      expect(formatRate(0.145), '14.5%');
      expect(formatRate(null), '0%');
    });
  });

  group('the words for a failure (getErrorMessage)', () {
    test('an uncoded 403 is "no permission", in both languages', () {
      final e = _err(403, 'Forbidden: Super admin access required');
      expect(orgErrorWords(e, en), "You don't have permission to perform this action.");
      expect(orgErrorWords(e, ar), 'ليس لديك صلاحية لتنفيذ هذا الإجراء.');
    });

    test('a server sentence loses its kind; Arabic gets the kind\'s words', () {
      final e = _err(409, "Conflict: Slug 'x' is already taken");
      expect(orgErrorWords(e, en), "Slug 'x' is already taken");
      expect(orgErrorWords(e, ar), 'هذا الإجراء يتعارض مع الحالة الحالية.');
    });

    test('a coded refusal reads in its own words', () {
      final e = _err(403, 'suspended', code: 'ORG_SUSPENDED');
      expect(orgErrorWords(e, en), 'This business is suspended.');
      expect(orgErrorWords(e, ar), 'هذا النشاط موقوف.');
    });

    test('words the core already chose pass through', () {
      const e = ApiException(status: 409, message: 'هذا الإجراء يتعارض');
      expect(orgErrorWords(e, ar), 'هذا الإجراء يتعارض');
      expect(orgErrorWords(StateError('x'), en), 'An unexpected error occurred.');
    });

    test('ADM-ORG-040 where a provisioning conflict belongs', () {
      final slug = provisionConflictTarget(
        _err(409, "Conflict: Slug 'drops' is already taken"),
        en,
      );
      expect(slug?.step, 0);
      expect(slug?.field, 'slug');
      expect(slug?.message, "Slug 'drops' is already taken");
      final email = provisionConflictTarget(
        _err(409, 'Conflict: Email already in use'),
        en,
      );
      expect(email?.step, 2);
      expect(email?.field, 'email');
      expect(
        provisionConflictTarget(_err(409, 'Conflict: something else'), en),
        isNull,
      );
      expect(
        provisionConflictTarget(_err(400, 'Bad request: slug bad'), en),
        isNull,
      );
    });
  });
}
