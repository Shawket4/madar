import 'package:dashboard_api/mock.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/mock/team_board_mock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe', () {
    final db = MockDb.seeded();
    final server = MockServer(persona: Persona.owner, clock: db.clock);
    registerCoreMocks(server, db);
    teamArea.registerMocks!(server, db);
    final p = teamPresenceOf(db, orgId: SeedIds.sabahOrg, scope: null, now: db.clock.now);
    for (final r in p['rows']! as List) {
      final m = r as Map;
      print('${m['employee_name']} | ${m['branch_name']} | ${m['state']} | sch ${m['scheduled_minutes']} | in ${m['check_in_at']} | late ${m['late_minutes']} | opens ${m['punch_opens_at']} | ${db['employees'].find(m['employee_id'] as String)?['user_id'] != null}');
    }
    print({for (final k in ['business_date','present','late','absent','on_leave']) k: p[k]});
    for (final f in db[TeamTables.flags].rows) {
      print('${f['employee_name']} ${f['kind']} ${f['branch_id'] == SeedIds.zamalek} res=${f['resolution']} sug=${f['suggested_deduction_piastres']}');
    }
    print('manager ${SeedIds.manager}');
    for (final e in db['employees'].rows) {
      if (e['user_id'] == SeedIds.manager || e['user_id'] == SeedIds.owner) print('linked ${e['name']} ${e['user_id'] == SeedIds.manager ? 'manager' : 'owner'}');
    }
  });
}
