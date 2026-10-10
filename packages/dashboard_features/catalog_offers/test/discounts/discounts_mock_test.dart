// The `/discounts` handlers against MadarRust `src/discounts/handlers.rs`:
// gates per persona, org scoping, validation words, the two value spellings,
// the name order and state that persists.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

({DashboardApi api, MockServer server, MockDb db}) _api(Persona persona) {
  final s = discountsServer(persona: persona);
  return (api: DashboardApi(s.server), server: s.server, db: s.db);
}

Future<ApiException> _refusal(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

final String _org = SeedIds.sabahOrg;

void main() {
  test('OFFR-DSC-043 the list: the org\'s discounts by name, both value '
      'spellings', () async {
    final a = _api(Persona.owner);
    final list = await a.api.discounts.listDiscounts(orgId: _org);
    expect([for (final d in list) d.name], seededNames);
    final vodafone = list.first;
    expect(vodafone.valueRate, 0.125);
    expect(vodafone.value, 13, reason: 'legacy: 12.5 % rounds half away');
    final late = list[1];
    expect(late.dtype, 'fixed');
    expect(late.valueRate, 5000);
    expect(late.value, 5000);
    expect(list.where((d) => d.isActive), hasLength(6));
  });

  test('OFFR-DSC-003 gates: list discounts.read; create, PATCH and delete '
      'their own capability', () async {
    final limited = _api(Persona.limited);
    final e = await _refusal(limited.api.discounts.listDiscounts(orgId: _org));
    expect(e.status, 403);
    expect(e.code, isNull);

    final manager = _api(Persona.manager);
    expect(
      await manager.api.discounts.listDiscounts(orgId: _org),
      hasLength(7),
    );
    final create = await _refusal(
      manager.api.discounts.createDiscount(
        body: CreateDiscountRequest(
          orgId: _org,
          name: 'Nope',
          dtype: 'percentage',
          value: 0.1,
        ),
      ),
    );
    expect(create.status, 403);
    expect(create.message, contains('discounts.create'));
    final del = await _refusal(
      manager.api.discounts.deleteDiscount(id: discountId('student')),
    );
    expect(del.status, 403);
    // discounts.edit is a branch manager default.
    final patched = await manager.api.discounts.updateDiscount(
      id: discountId('student'),
      body: const UpdateDiscountRequest(isActive: false),
    );
    expect(patched.isActive, isFalse);
  });

  test('another org\'s discounts are refused ("Not your org"); a platform '
      'admin passes', () async {
    final dawam = _api(Persona.dawamOnly);
    final e = await _refusal(dawam.api.discounts.listDiscounts(orgId: _org));
    expect(e.status, 403);
    expect(e.message, 'Forbidden: Not your org');
    final platform = _api(Persona.platform);
    expect(
      await platform.api.discounts.listDiscounts(orgId: _org),
      hasLength(7),
    );
  });

  test('a list without org_id is a 400', () async {
    final a = _api(Persona.owner);
    final e = await _refusal(
      a.server.send(const ApiRequest(method: 'GET', path: '/discounts')),
    );
    expect(e.status, 400);
  });

  test('OFFR-DSC-033 create: the fraction is stored, `en` mirrors the name, '
      'the next list shows it', () async {
    final a = _api(Persona.owner);
    final d = await a.api.discounts.createDiscount(
      body: CreateDiscountRequest(
        orgId: _org,
        name: 'Ramadan',
        nameTranslations: {'ar': 'رمضان'},
        dtype: 'percentage',
        value: 0.14,
        isActive: true,
      ),
    );
    expect(d.valueRate, 0.14);
    expect(d.value, 14);
    expect(d.nameTranslations, {'ar': 'رمضان', 'en': 'Ramadan'});
    final list = await a.api.discounts.listDiscounts(orgId: _org);
    expect(list.map((x) => x.name), contains('Ramadan'));
    expect(list.map((x) => x.name).toList()..sort(), list.map((x) => x.name));
  });

  test('validation: type, a negative value, a percentage over 1', () async {
    final a = _api(Persona.owner);
    Future<ApiException> make(String dtype, double value) => _refusal(
      a.api.discounts.createDiscount(
        body: CreateDiscountRequest(
          orgId: _org,
          name: 'X',
          dtype: dtype,
          value: value,
        ),
      ),
    );
    expect(
      (await make('bogus', 0.1)).message,
      "Bad request: type must be 'percentage' or 'fixed'",
    );
    expect(
      (await make('fixed', -1)).message,
      'Bad request: value must be >= 0',
    );
    expect(
      (await make('percentage', 14)).message,
      'Bad request: a percentage discount is a fraction between 0 and 1 '
      '(0.14 = 14%)',
    );
    // A fixed amount has no ceiling.
    final big = await a.api.discounts.createDiscount(
      body: CreateDiscountRequest(
        orgId: _org,
        name: 'Big',
        dtype: 'fixed',
        value: 10000000,
      ),
    );
    expect(big.valueRate, 10000000);
  });

  test('OFFR-DSC-034 PATCH: a name keeps the stored Arabic (as the '
      'backend); translations without a name replace them; 404', () async {
    final a = _api(Persona.owner);
    final renamed = await a.api.discounts.updateDiscount(
      id: discountId('student'),
      body: const UpdateDiscountRequest(
        name: 'Student Card',
        nameTranslations: {'ar': 'بطاقة الطالب'},
        dtype: 'percentage',
        value: 0.2,
      ),
    );
    expect(renamed.name, 'Student Card');
    expect(renamed.nameTranslations['en'], 'Student Card');
    expect(renamed.nameTranslations['ar'], 'خصم الطلاب');
    expect(renamed.valueRate, 0.2);
    expect(renamed.value, 20);

    final ar = await a.api.discounts.updateDiscount(
      id: discountId('student'),
      body: const UpdateDiscountRequest(nameTranslations: {'ar': 'بطاقة'}),
    );
    expect(ar.nameTranslations, {'ar': 'بطاقة', 'en': 'Student Card'});

    final missing = await _refusal(
      a.api.discounts.updateDiscount(
        id: mockUuid('nope'),
        body: const UpdateDiscountRequest(isActive: true),
      ),
    );
    expect(missing.status, 404);
    expect(missing.message, 'Not found: Discount not found');
  });

  test('PATCH checks the value only with a type (as the backend)', () async {
    final a = _api(Persona.owner);
    final e = await _refusal(
      a.api.discounts.updateDiscount(
        id: discountId('student'),
        body: const UpdateDiscountRequest(dtype: 'percentage', value: 2),
      ),
    );
    expect(e.status, 400);
  });

  test('OFFR-DSC-017 delete removes it; a second delete is a 404', () async {
    final a = _api(Persona.owner);
    await a.api.discounts.deleteDiscount(id: discountId('opening-week'));
    expect(
      a.db.table(OffersTables.discounts).find(discountId('opening-week')),
      isNull,
    );
    final again = await _refusal(
      a.api.discounts.deleteDiscount(id: discountId('opening-week')),
    );
    expect(again.status, 404);
    expect(await a.api.discounts.listDiscounts(orgId: _org), hasLength(6));
  });
}
