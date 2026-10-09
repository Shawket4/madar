// The Payment methods mock handlers against the backend's rules
// (MadarRust `src/payment_methods/{handlers,availability}.rs`), straight on
// the typed API, no app.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'pm_support.dart';

({DashboardApi api, MockDb db, MockServer server}) _backend([
  Persona persona = Persona.owner,
]) {
  final m = setupMockServer(persona: persona);
  return (api: DashboardApi(m.server), db: m.db, server: m.server);
}

Future<ApiException> _refusal(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

const _create = CreatePaymentMethodRequest(
  name: 'valu',
  labelTranslations: {'en': 'valU', 'ar': 'فاليو'},
  color: '#0F172A',
  icon: 'credit_card',
  isCash: false,
);

void main() {
  group('methods', () {
    test('the list: the org\'s eight methods, oldest first', () async {
      final b = _backend();
      final list = await b.api.paymentMethods.listPaymentMethods();
      expect([for (final m in list) m.name], [
        'cash',
        'card',
        'digital_wallet',
        'mixed',
        'talabat_online',
        'talabat_cash',
        'instapay',
        'gift_card',
      ]);
      expect(list.where((m) => m.isActive), hasLength(6));
      expect(list.where((m) => !m.visibleInIntegrations).map((m) => m.name), [
        'mixed',
        'gift_card',
      ]);
    });

    test('a create defaults active and shared, then lists last', () async {
      final b = _backend();
      final made = await b.api.paymentMethods.createPaymentMethod(
        body: _create,
      );
      expect(made.isActive, isTrue);
      expect(made.visibleInIntegrations, isTrue);
      expect(made.orgId, SeedIds.sabahOrg);
      expect(b.server.calls.last.method, 'POST');
      final list = await b.api.paymentMethods.listPaymentMethods();
      expect(list.last.id, made.id);
    });

    test('a name the org has is refused (409), on create and on rename',
        () async {
      final b = _backend();
      final dup = await _refusal(
        b.api.paymentMethods.createPaymentMethod(
          body: const CreatePaymentMethodRequest(
            name: 'cash',
            labelTranslations: {'en': 'Cash'},
            color: '#10B981',
            icon: 'money',
            isCash: true,
          ),
        ),
      );
      expect(dup.status, 409);
      final rename = await _refusal(
        b.api.paymentMethods.updatePaymentMethod(
          id: pmId('instapay'),
          body: const UpdatePaymentMethodRequest(name: 'card'),
        ),
      );
      expect(rename.status, 409);
    });

    test('an update changes only what it sends; unknown ids are 404',
        () async {
      final b = _backend();
      final out = await b.api.paymentMethods.updatePaymentMethod(
        id: pmId('instapay'),
        body: const UpdatePaymentMethodRequest(color: '#2563EB'),
      );
      expect(out.color, '#2563EB');
      expect(out.icon, 'smartphone');
      expect(out.labelTranslations, {'en': 'InstaPay', 'ar': 'إنستاباي'});
      final missing = await _refusal(
        b.api.paymentMethods.activatePaymentMethod(id: mockUuid('nope')),
      );
      expect(missing.status, 404);
    });

    test('activate / deactivate flip is_active', () async {
      final b = _backend();
      expect(
        (await b.api.paymentMethods.activatePaymentMethod(
          id: pmId('talabat_cash'),
        )).isActive,
        isTrue,
      );
      expect(
        (await b.api.paymentMethods.deactivatePaymentMethod(
          id: pmId('cash'),
        )).isActive,
        isFalse,
      );
    });

    test('capabilities: the manager reads but may not add or edit; the '
        'cashier may not read', () async {
      final mgr = _backend(Persona.manager);
      expect(await mgr.api.paymentMethods.listPaymentMethods(), hasLength(8));
      final add = await _refusal(
        mgr.api.paymentMethods.createPaymentMethod(body: _create),
      );
      expect(add.status, 403);
      expect(add.message, contains('payment_methods.create'));
      final edit = await _refusal(
        mgr.api.paymentMethods.deactivatePaymentMethod(id: pmId('cash')),
      );
      expect(edit.message, contains('payment_methods.edit'));
      final cashier = _backend(Persona.limited);
      final read = await _refusal(
        cashier.api.paymentMethods.listPaymentMethods(),
      );
      expect(read.status, 403);
      expect(read.message, contains('payment_methods.read'));
    });

    test('another org sees none of these', () async {
      final b = _backend(Persona.dawamOnly);
      expect(await b.api.paymentMethods.listPaymentMethods(), isEmpty);
      final other = await _refusal(
        b.api.paymentMethods.deactivatePaymentMethod(id: pmId('cash')),
      );
      expect(other.status, 404);
    });
  });

  group('availability', () {
    test('Zamalek: its list, every teller list, its devices\' lists',
        () async {
      final b = _backend();
      final a = await b.api.paymentMethods.getAvailability(
        branchId: SeedIds.zamalek,
      );
      expect(a.branchId, SeedIds.zamalek);
      expect(a.branch.restricted, isTrue);
      expect(a.branch.paymentMethodIds, [
        pmId('cash'),
        pmId('card'),
        pmId('digital_wallet'),
        pmId('instapay'),
      ]);
      expect(a.users.single.userId, SeedIds.user('youssef'));
      expect(a.users.single.paymentMethodIds, [pmId('cash')]);
      expect(a.devices.single.deviceId, PmSeed.deviceId('zamalek', 'T2'));
    });

    test('Heliopolis: unrestricted, the org\'s teller lists, no devices',
        () async {
      final b = _backend();
      final a = await b.api.paymentMethods.getAvailability(
        branchId: SeedIds.heliopolis,
      );
      expect(a.branch.restricted, isFalse);
      expect(a.branch.paymentMethodIds, isEmpty);
      expect(a.users, hasLength(1));
      expect(a.devices, isEmpty);
    });

    test('a branch outside the org is 404', () async {
      final b = _backend();
      final e = await _refusal(
        b.api.paymentMethods.getAvailability(branchId: SeedIds.dokki),
      );
      expect(e.status, 404);
    });

    test('a PUT replaces the list and answers the stored one, in method '
        'order', () async {
      final b = _backend();
      final out = await b.api.paymentMethods.putUserAvailability(
        userId: SeedIds.user('mariam'),
        body: AllowList(
          restricted: true,
          paymentMethodIds: [pmId('instapay'), pmId('cash'), pmId('cash')],
        ),
      );
      expect(out.paymentMethodIds, [pmId('cash'), pmId('instapay')]);
      final off = await b.api.paymentMethods.putBranchAvailability(
        branchId: SeedIds.zamalek,
        body: const AllowList(restricted: false, paymentMethodIds: []),
      );
      expect(off.restricted, isFalse);
      final a = await b.api.paymentMethods.getAvailability(
        branchId: SeedIds.zamalek,
      );
      expect(a.branch.restricted, isFalse);
      expect(a.users, hasLength(2));
    });

    test('refusals: an empty restricted list (EMPTY_ALLOW_LIST), an owner '
        'outside the org, an unknown method, no edit right', () async {
      final b = _backend();
      final empty = await _refusal(
        b.api.paymentMethods.putDeviceAvailability(
          deviceId: PmSeed.deviceId('zamalek', 'T1'),
          body: const AllowList(restricted: true, paymentMethodIds: []),
        ),
      );
      expect(empty.status, 400);
      expect(empty.code, 'EMPTY_ALLOW_LIST');
      final owner = await _refusal(
        b.api.paymentMethods.putUserAvailability(
          userId: SeedIds.dawamOwner,
          body: AllowList(restricted: true, paymentMethodIds: [pmId('cash')]),
        ),
      );
      expect(owner.status, 404);
      final unknown = await _refusal(
        b.api.paymentMethods.putBranchAvailability(
          branchId: SeedIds.zamalek,
          body: AllowList(
            restricted: true,
            paymentMethodIds: [mockUuid('nope')],
          ),
        ),
      );
      expect(unknown.status, 400);
      final mgr = _backend(Persona.manager);
      final denied = await _refusal(
        mgr.api.paymentMethods.putBranchAvailability(
          branchId: SeedIds.zamalek,
          body: AllowList(restricted: true, paymentMethodIds: [pmId('cash')]),
        ),
      );
      expect(denied.status, 403);
    });
  });

  group('people and devices', () {
    test('GET /users: the org\'s people by name; GET /devices: the branch\'s, '
        'live first by code', () async {
      final b = _backend();
      final users = await b.api.users.listUsers(orgId: SeedIds.sabahOrg);
      expect(users.first.name, 'Adham Reda');
      expect(users.every((u) => u.orgId == SeedIds.sabahOrg), isTrue);
      final devices = await b.api.devices.listDevices(
        branchId: SeedIds.maadi,
      );
      expect([for (final d in devices) d.code], ['T1', 'T9']);
      expect(devices.last.retiredAt, isNotNull);
    });
  });
}
