// The Devices mock backend behaves like MadarRust's handlers
// (src/devices/{handlers,activation}.rs, src/client_seen/handlers.rs):
// gates, validation, refusals, ordering and state that persists.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<ApiException> refused(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

void main() {
  final zamalek = SeedIds.zamalek;
  final newCairo = SeedIds.newCairo;

  group('GET /devices', () {
    test('a branch\'s devices, live first, by code', () async {
      final b = DevicesBackend();
      final list = await b.api.devices.listDevices(branchId: zamalek);
      expect([for (final d in list) d.code], ['K1', 'T1', 'T2', 'W1', 'W2']);
      final maadi = await b.api.devices.listDevices(branchId: SeedIds.maadi);
      expect([for (final d in maadi) d.code], ['T1', 'T9']);
      expect(maadi.last.retiredAt, isNotNull);
    });

    test('code_conflict is computed live', () async {
      final b = DevicesBackend();
      var list = await b.api.devices.listDevices(branchId: newCairo);
      expect([for (final d in list) d.codeConflict], [false, true, true]);
      // Retiring one of the pair frees the code for the other only.
      await b.api.devices.updateDevice(
        id: AdminSeed.deviceId('new-cairo', 'T2-b'),
        body: const UpdateDeviceRequest(retired: true),
      );
      list = await b.api.devices.listDevices(branchId: newCairo);
      final drive = list.firstWhere((d) => d.label == 'Drive-through');
      final retired = list.firstWhere((d) => d.label == 'Counter 2');
      expect(drive.codeConflict, isFalse);
      expect(retired.codeConflict, isTrue);
      expect(list.last.id, retired.id, reason: 'retired sorts last');
    });

    test('needs branches.read and access to the branch', () async {
      final teller = DevicesBackend(persona: Persona.limited);
      expect(
        await teller.api.devices.listDevices(branchId: SeedIds.maadi),
        hasLength(2),
      );
      final e = await refused(
        teller.api.devices.listDevices(branchId: zamalek),
      );
      expect(e.status, 403);
      expect(e.message, contains('Not assigned to this branch'));
      final other = await refused(
        DevicesBackend().api.devices.listDevices(
          branchId: AdminSeed.gardenCity,
        ),
      );
      expect(other.status, 403);
      final unknown = await refused(
        DevicesBackend().api.devices.listDevices(branchId: mockUuid('nope')),
      );
      expect(unknown.status, 404);
    });
  });

  group('PATCH /devices/{id}', () {
    final t1 = AdminSeed.deviceId('zamalek', 'T1');

    test(
      'saves the code (trimmed, uppercased), the label and retired',
      () async {
        final b = DevicesBackend();
        final d = await b.api.devices.updateDevice(
          id: t1,
          body: const UpdateDeviceRequest(
            code: ' t5 ',
            label: '  Bar  ',
            retired: true,
          ),
        );
        expect(d.code, 'T5');
        expect(d.label, 'Bar');
        expect(d.retiredAt, b.db.clock.now);
        final cleared = await b.api.devices.updateDevice(
          id: t1,
          body: const UpdateDeviceRequest(
            code: 'T5',
            retired: false,
            explicitNulls: {'label'},
          ),
        );
        expect(cleared.label, isNull);
        expect(cleared.retiredAt, isNull);
        // A later list shows it.
        final list = await b.api.devices.listDevices(branchId: zamalek);
        expect(list.map((d) => d.code), contains('T5'));
      },
    );

    test('refuses a bad code (400) and a taken one (409)', () async {
      final b = DevicesBackend();
      final bad = await refused(
        b.api.devices.updateDevice(
          id: t1,
          body: const UpdateDeviceRequest(code: 'AB-12'),
        ),
      );
      expect(bad.status, 400);
      expect(bad.message, contains('1-6 letters or digits'));
      final taken = await refused(
        b.api.devices.updateDevice(
          id: t1,
          body: const UpdateDeviceRequest(code: 'k1'),
        ),
      );
      expect(taken.status, 409);
      expect(taken.code, 'DEVICE_CODE_TAKEN');
      // Saving a conflicting device unchanged is refused too (a code is sent).
      final pair = await refused(
        b.api.devices.updateDevice(
          id: AdminSeed.deviceId('new-cairo', 'T2'),
          body: const UpdateDeviceRequest(code: 'T2', retired: false),
        ),
      );
      expect(pair.code, 'DEVICE_CODE_TAKEN');
    });

    test('needs branches.edit; 404 for an unknown device', () async {
      final manager = DevicesBackend(persona: Persona.manager);
      final e = await refused(
        manager.api.devices.updateDevice(
          id: t1,
          body: const UpdateDeviceRequest(code: 'T1'),
        ),
      );
      expect(e.status, 403);
      expect(e.code, isNull);
      final missing = await refused(
        DevicesBackend().api.devices.updateDevice(
          id: mockUuid('device:none'),
          body: const UpdateDeviceRequest(code: 'T1'),
        ),
      );
      expect(missing.status, 404);
    });
  });

  group('activation codes', () {
    test('newest first, the state from the stamps', () async {
      final b = DevicesBackend();
      final list = await b.api.devices.listCodes(branchId: zamalek);
      expect(
        [for (final c in list) c.code],
        ['40721958', '77219034', '55102846', '18364052'],
      );
      expect(
        [for (final c in list) c.state.value],
        ['free', 'expired', 'revoked', 'used'],
      );
      // A day later the free one has expired.
      b.db.clock.advance(const Duration(days: 1));
      final later = await b.api.devices.listCodes(branchId: zamalek);
      expect(later.first.state, ActivationCodeState.expired);
    });

    test('issue: 201, 8 digits, free for 24 hours, then listed', () async {
      final b = DevicesBackend();
      final c = await b.api.devices.createCode(
        body: CreateActivationCodeRequest(
          branchId: zamalek,
          label: '  Bar tablet ',
          kind: DeviceKind.waiter,
        ),
      );
      expect(c.code, matches(RegExp(r'^\d{8}$')));
      expect(c.state, ActivationCodeState.free);
      expect(c.label, 'Bar tablet');
      expect(c.kind, DeviceKind.waiter);
      expect(c.expiresAt, b.db.clock.now.add(const Duration(hours: 24)));
      expect(b.server.calls.last.status, 201);
      final list = await b.api.devices.listCodes(branchId: zamalek);
      expect(list.first.id, c.id);
      final pos = await b.api.devices.createCode(
        body: CreateActivationCodeRequest(branchId: zamalek),
      );
      expect(pos.kind, DeviceKind.pos);
      expect(pos.code, isNot(c.code));
    });

    test('withdraw: free → revoked; used is refused; unknown is 404', () async {
      final b = DevicesBackend();
      final free = mockUuid('activation-code:40721958');
      final c = await b.api.devices.revokeCode(id: free);
      expect(c.state, ActivationCodeState.revoked);
      expect(c.revokedAt, b.db.clock.now);
      final used = await refused(
        b.api.devices.revokeCode(id: mockUuid('activation-code:18364052')),
      );
      expect(used.status, 409);
      expect(used.code, 'ACTIVATION_CODE_USED');
      final none = await refused(
        b.api.devices.revokeCode(id: mockUuid('activation-code:none')),
      );
      expect(none.status, 404);
    });

    test('every code call needs branches.edit', () async {
      final m = DevicesBackend(persona: Persona.manager);
      for (final call in <Future<Object?>>[
        m.api.devices.listCodes(branchId: zamalek),
        m.api.devices.createCode(
          body: CreateActivationCodeRequest(branchId: zamalek),
        ),
        m.api.devices.revokeCode(id: mockUuid('activation-code:40721958')),
      ]) {
        expect((await refused(call)).status, 403);
      }
    });
  });

  group('GET /devices/client-versions', () {
    test('legacy only by default, newest legacy hit first', () async {
      final b = DevicesBackend();
      final rows = await b.api.devices.listClientVersions();
      expect([for (final r in rows) r.deviceCode], ['T1', 'T2', 'W2']);
      expect(rows.every((r) => r.lastLegacyAt != null), isTrue);
      expect(rows.first.branchName, 'Heliopolis');
    });

    test('all clients in the window, one branch, a wider window', () async {
      final b = DevicesBackend();
      final all = await b.api.devices.listClientVersions(legacyOnly: false);
      expect(all, hasLength(12));
      expect(all.where((r) => r.deviceId == null), hasLength(1));
      final z = await b.api.devices.listClientVersions(
        legacyOnly: false,
        branchId: zamalek,
      );
      expect(z, hasLength(5));
      final wide = await b.api.devices.listClientVersions(
        legacyOnly: false,
        days: 90,
      );
      expect(wide, hasLength(13));
    });

    test('the device code follows the device', () async {
      final b = DevicesBackend();
      await b.api.devices.updateDevice(
        id: AdminSeed.deviceId('zamalek', 'W2'),
        body: const UpdateDeviceRequest(code: 'W9'),
      );
      final rows = await b.api.devices.listClientVersions(branchId: zamalek);
      expect(rows.single.deviceCode, 'W9');
    });

    test('refusals: no branches.edit (403), a bad window (400)', () async {
      final m = DevicesBackend(persona: Persona.manager);
      expect((await refused(m.api.devices.listClientVersions())).status, 403);
      final b = DevicesBackend();
      final e = await refused(b.api.devices.listClientVersions(days: 0));
      expect(e.status, 400);
      expect(e.message, contains('days must be between 1 and 365'));
    });
  });
}
