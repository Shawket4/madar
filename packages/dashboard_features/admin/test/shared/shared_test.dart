// The admin area's shared pieces: the rate conversions (the web's
// tax-rate.test.ts), the limits conversions (limits-button.test.ts), the
// capability catalog (catalog.test.ts), the URL helpers and the area seed.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/shared/capability_catalog.dart';
import 'package:dashboard_admin/src/shared/limits_button.dart';
import 'package:dashboard_admin/src/shared/tax_rate.dart';
import 'package:dashboard_admin/src/shared/url_params.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tax rate', () {
    test('fraction on the wire, percent on screen', () {
      expect(fractionToPercent(0.14), 14);
      expect(fractionToPercent(0.145), 14.5);
      expect(fractionToPercent(null), 0);
      expect(percentToFraction(14), 0.14);
      expect(percentToFraction(12.5), 0.125);
      expect(percentToFraction(double.nan), 0);
      expect(formatRate(0.14), '14%');
      expect(formatRate(0.1234), '12.34%');
      expect(formatRate(null), '0%');
    });
  });

  group('limits', () {
    test('typed pounds and percent are stored ×100, minutes as typed', () {
      expect(limitFromDraft('max_amount', '50'), 5000);
      expect(limitFromDraft('max_percent', '12.5'), 1250);
      expect(limitFromDraft('max_age_minutes', '10'), 10);
      expect(limitFromDraft('max_value', ''), isNull);
      expect(limitToDraft('max_amount', 5050), '50.5');
      expect(limitToDraft('max_amount', null), '');
      expect(hasLimits(const LimitsView()), isFalse);
      expect(hasLimits(const LimitsView(own: true)), isTrue);
      expect(hasLimits(const LimitsView(maxAgeMinutes: 10)), isTrue);
    });
  });

  group('capability catalog', () {
    test('no legacy capability is shown; advanced ones sit apart', () {
      final groups = catalogGroups();
      expect(groups, isNotEmpty);
      for (final g in groups) {
        expect(
          g.main.every((c) => c.tier != 'legacy' && c.tier != 'advanced'),
          isTrue,
        );
        expect(g.advanced.every((c) => c.tier == 'advanced'), isTrue);
      }
      expect(approvalCapabilities().map((c) => c.key), contains('orders.void'));
      final teller = roleHolds(const [], RoleKind.teller);
      for (final c in capabilityRegistry) {
        if (c.core.contains(RoleKind.teller)) expect(teller, contains(c.key));
      }
    });
  });

  group('url params', () {
    test('section links keep only the scope', () {
      final uri = Uri.parse('/access/users?edit=u1&branchId=b1&preset=7d');
      expect(
        scopedLocation('/access/roles', uri),
        '/access/roles?branchId=b1&preset=7d',
      );
      expect(
        withQueryParams(uri, {'edit': null}).toString(),
        '/access/users?branchId=b1&preset=7d',
      );
      expect(
        withQueryParams(Uri.parse('/orgs'), {'edit': 'new'}).toString(),
        '/orgs?edit=new',
      );
    });
  });

  group('area seed', () {
    test('loads once, on top of the core seed, in the spec shapes', () {
      final db = MockDb.seeded();
      loadAdminSeed(db);
      loadAdminSeed(db);
      expect(db['orgs'].length, 4);
      expect(db[AdminTables.devices].length, AdminSeed.devices.length);
      for (final r in db[AdminTables.devices].rows) {
        Device.fromJson(r);
      }
      for (final r in db[AdminTables.activationCodes].rows) {
        ActivationCode.fromJson(r);
      }
      for (final r in db[AdminTables.clientVersions].rows) {
        ClientSeen.fromJson(r);
      }
      for (final r in db[AdminTables.flags].rows) {
        ReplayFlag.fromJson(r);
      }
      // The counter till the core seed's orders were rung on.
      expect(
        db[AdminTables.devices].find(AdminSeed.deviceId('zamalek', 'T1')),
        isNotNull,
      );
      // Every assignment names a seeded person and branch.
      for (final r in db[AdminTables.userBranches].rows) {
        expect(db['users'].find(r['user_id']! as String), isNotNull);
        expect(db['branches'].find(r['branch_id']! as String), isNotNull);
      }
      expect(
        db[AdminTables.flags].where((f) => f['reviewed_at'] == null),
        hasLength(6),
      );
    });
  });
}
