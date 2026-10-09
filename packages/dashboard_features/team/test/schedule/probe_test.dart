import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_support.dart';

void main() {
  test('probe', () async {
    final s = scheduleServer();
    Future<Object?> get(String path, Map<String, String> q) async {
      final r = await s.server.send(ApiRequest(method: 'GET', path: path, query: {for (final e in q.entries) e.key: [e.value]}));
      return jsonDecode(utf8.decode(r.bodyBytes));
    }
    final v = await get(rosterT, {'branch_id': SeedIds.zamalek, 'from': week, 'to': wd(6)}) as Map;
    for (final p in v['staff'] as List) {
      print('STAFF ${p['name']} ${p['employee_id']} pref=${p['pref_time']} cant=${p['cant_work_days']} by=${p['prefs_set_by']}');
    }
    for (final sh in v['shifts'] as List) {
      print('SHIFT ${sh['employee_name']} ${sh['date']} ${sh['shift_name']} ${sh['start_time']}-${sh['end_time']} ch=${sh['changed']} ed=${sh['times_edited']} leave=${sh['on_leave']} br=${sh['branch_id'] == SeedIds.zamalek ? 'Z' : sh['branch_id']}');
    }
    print('ELSEWHERE ${v['elsewhere']}');
    print('WARN ${v['warnings']}');
    print('SETS ${v['date_sets']}');
    print('OPEN ${v['open_shifts']}');
    print('WS ${v['work_shifts']}');
    print('HOL ${v['holidays']} PUB ${v['published_weeks']}');
    print('SUG ${await get(suggestionsT, {'branch_id': SeedIds.zamalek, 'week_start': week})}');
    print('COV ${await get(coverageT, {'branch_id': SeedIds.zamalek})}');
    print('FAIR ${await get(fairnessT, {'month': '2026-10-01'})}');
    final b = await get('/branches', {'org_id': SeedIds.sabahOrg});
    print('BR ${(b as List).map((x) => '${x['name']}:${x['id']}').join(', ')}');
  });
}
