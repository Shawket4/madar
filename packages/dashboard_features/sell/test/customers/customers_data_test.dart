// The unit's pure rules: error wording (SELL-ALL-017), birthdays, address
// lines, the ledger's words and signs, balances and the merge refusals.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_sell/src/customers/customers_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dashboard_sell/src/shared/error_text.dart';

const _tables = {
  'en': {
    'errors.codes.EXPORT_RATE_LIMITED':
        'Too many exports just now. Try again in a minute.',
    'errors.tooManyRequests': 'Too many requests just now.',
    'errors.unauthorized': "You don't have permission to perform this action.",
    'errors.networkError': 'Network error.',
    'errors.server': 'Server error.',
    'errors.notFound': 'Not found.',
    'customers.addresses.unit': 'Unit {{n}}',
    'customers.addresses.floor': 'Floor {{n}}',
    'loyalty.ledger.sale': 'Earned on a sale',
    'loyalty.ledger.voidEarn': 'Earn reversed (void)',
    'loyalty.ledger.refundRedeem': 'Reward returned (refund)',
    'loyalty.ledger.manual': 'Manual adjustment',
    'loyalty.ledger.by': 'by {{name}}',
    'loyalty.ledger.bySystem': 'automatic',
    'loyalty.errors.serverNoteRequired': 'Say why — the reason is required.',
  },
};

final _t = Translator(Strings(_tables), 'en');

ApiException _e(int status, String message, {String? code, Object? env}) =>
    ApiException(status: status, message: message, code: code, details: env);

LedgerEntry _entry({
  required String kind,
  required String source,
  int points = 1,
  String? reverses,
  String? by,
  String? byName,
}) => LedgerEntry(
  id: '$kind-$source',
  branchId: 'b',
  createdAt: DateTime.utc(2026, 10, 1),
  currency: 'visits',
  kind: kind,
  source: source,
  points: points,
  reversesId: reverses,
  createdBy: by,
  createdByName: byName,
);

void main() {
  test('SELL-ALL-017 error wording', () {
    expect(
      sellErrorText(_e(429, 'x', code: 'EXPORT_RATE_LIMITED'), _t),
      'Too many exports just now. Try again in a minute.',
    );
    expect(
      sellErrorText(_e(429, 'slow down'), _t),
      'Too many requests just now.',
    );
    expect(
      sellErrorText(_e(403, 'Forbidden: nope'), _t),
      "You don't have permission to perform this action.",
    );
    expect(
      sellErrorText(_e(409, 'Conflict: Till already open'), _t),
      'Till already open',
    );
    expect(sellErrorText(_e(0, 'offline'), _t), 'Network error.');
    expect(sellErrorText(_e(500, ''), _t), 'Server error.');
    // The mock's bare answer (no envelope) is no sentence: by status.
    expect(sellErrorText(_e(404, 'HTTP 404'), _t), 'Not found.');
    // Real mode: the core worded it in Arabic; the envelope stays English.
    expect(
      sellErrorText(
        _e(404, 'العميل غير موجود', env: {'error': 'Not found: Customer'}),
        _t,
      ),
      'العميل غير موجود',
    );
    expect(sellErrorText(const ExportTooLargeError(60000), _t), isNotEmpty);
  });

  test(
    'the adjust "note required" refusal is recognised in either language',
    () {
      final en = loyaltyServerError(
        _e(400, 'Bad request: Say why the points are being adjusted (note)'),
        _t,
      );
      expect(en.noteRequired, isTrue);
      final ar = loyaltyServerError(
        _e(
          400,
          'اذكر سبب التعديل',
          env: {
            'error':
                'Bad request: Say why the points are being adjusted (note)',
          },
        ),
        _t,
      );
      expect(ar.noteRequired, isTrue);
      expect(ar.message, 'Say why — the reason is required.');
      expect(
        loyaltyServerError(_e(400, 'Bad request: nope'), _t).noteRequired,
        isFalse,
      );
    },
  );

  test('member refusals by code', () {
    expect(isPhoneTaken(_e(409, 'x', code: 'CUSTOMER_PHONE_EXISTS')), isTrue);
    expect(isPhoneTaken(_e(400, 'x', code: 'CUSTOMER_PHONE_EXISTS')), isFalse);
    expect(
      isMemberMustSurvive(_e(409, 'x', code: 'CUSTOMER_MERGE_MEMBER_SURVIVES')),
      isTrue,
    );
  });

  test('birthdays have no year; 29 February survives', () {
    expect(formatBirthday(3, 14, 'en'), '14 March');
    expect(formatBirthday(3, 14, 'ar'), '١٤ مارس');
    expect(formatBirthday(2, 29, 'en'), '29 February');
    expect(formatBirthday(null, 4, 'en'), isNull);
    expect(formatBirthday(13, 4, 'en'), isNull);
  });

  test('an address line drops blanks and joins with dots', () {
    final a = CustomerAddress(
      id: 'a',
      customerId: 'c',
      channel: 'outside',
      placeName: '  ',
      unitNumber: '14',
      floor: '3',
      addressLine: '12 El-Thawra St',
      landmark: 'Next to Korba metro ',
      useCount: 1,
      createdAt: DateTime.utc(2026),
      lastUsedAt: DateTime.utc(2026),
    );
    expect(
      formatAddressLine(a, _t),
      'Unit 14 · Floor 3 · 12 El-Thawra St · Next to Korba metro',
    );
  });

  test('the ledger: words, tones, signs, actors, reversals', () {
    final earn = _entry(kind: 'earn', source: 'sale', by: 'u', byName: 'Mona');
    final undo = _entry(
      kind: 'reverse_earn',
      source: 'void',
      points: -1,
      reverses: earn.id,
    );
    expect(ledgerLabel(earn, _t), 'Earned on a sale');
    expect(ledgerLabel(undo, _t), 'Earn reversed (void)');
    expect(
      ledgerLabel(_entry(kind: 'reverse_redeem', source: 'refund'), _t),
      'Reward returned (refund)',
    );
    expect(ledgerTone(earn), LedgerTone.earn);
    expect(ledgerTone(undo), LedgerTone.reversal);
    expect(
      ledgerTone(_entry(kind: 'adjust', source: 'manual')),
      LedgerTone.manual,
    );
    expect(
      ledgerTone(_entry(kind: 'earn', source: 'birthday')),
      LedgerTone.gift,
    );
    expect(
      ledgerTone(_entry(kind: 'redeem', source: 'redemption')),
      LedgerTone.spend,
    );
    expect(reversedIds([earn, undo]), {earn.id});
    expect(signedAmount(12), '+12');
    expect(signedAmount(-5), '−5');
    expect(signedAmount(0), '0');
    expect(ledgerActor(earn, _t), 'by Mona');
    expect(ledgerActor(undo, _t), 'automatic');
  });

  test('a row\'s balance follows the programme\'s mode, members only', () {
    Customer c({bool member = true}) => Customer(
      id: 'c',
      name: 'Nada',
      isMember: member,
      visitsBalance: 4,
      pointsBalance: 120,
      ordersCount: 0,
      totalSpent: 0,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    expect(PersonRow(customer: c(), mode: 'visits').balance, 4);
    expect(PersonRow(customer: c(), mode: 'points').balance, 120);
    expect(PersonRow(customer: c(), mode: null).balance, isNull);
    expect(
      PersonRow(customer: c(member: false), mode: 'visits').balance,
      isNull,
    );
    expect(isCustomerSource('table_qr'), isTrue);
    expect(isCustomerSource('order_now'), isFalse);
  });
}
