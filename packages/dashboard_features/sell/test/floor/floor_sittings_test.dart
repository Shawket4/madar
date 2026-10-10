// The floor's table history reads the core seed's one sittings model
// (`MockSeed.sittings`), the same one the reports' tables dataset (the
// Operations › Tables ledger) reads: for every table, the history's settled
// bills are exactly the shared model's, so the ledger and the history agree
// (REP-OPS-025/027/030 in the reports inventory).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'floor_support.dart';

void main() {
  test('the plan is the core seed\'s: every active table, same ids', () {
    final s = floorServer();
    final rows = s.db[SellTables.floorTables].rows;
    for (final b in SeedIds.sabahBranches) {
      final mine = [
        for (final r in rows)
          if (r['branch_id'] == b && r['is_active'] == true) '${r['id']}',
      ]..sort();
      final core = [
        for (final t in seedFloorTables)
          if (MockSeed.branchIdOf(t.branchKey) == b &&
              t.active &&
              t.retiredCairo == null)
            MockSeed.floorTableId(t.branchKey, t.label),
      ]..sort();
      expect(mine, core, reason: b);
    }
  });

  test('every table\'s settled bills are the shared sittings: count, money, '
      'covers', () async {
    final s = floorServer();
    final api = DashboardApi(s.server);
    final to = s.db.clock.now;
    final from = to.subtract(const Duration(days: 30));
    for (final r in s.db[SellTables.floorTables].rows) {
      if (r['is_active'] != true) continue;
      final id = '${r['id']}';
      final h = await api.floor.tableHistory(id: id, from: from, to: to);
      final shared = [
        for (final o in MockSeed.instance.orders)
          if (MockSeed.instance.sittingOf(o.id) case final st?
              when st.tableId == id &&
                  o.status != 'voided' &&
                  !st.seatedAt.isBefore(from) &&
                  st.seatedAt.isBefore(to))
            (o, st),
      ];
      expect(h.settledCount, shared.length, reason: '${r['label']}');
      expect(h.totalMinor, shared.fold<int>(0, (a, x) => a + x.$1.totalAmount));
      expect(h.covers, shared.fold<int>(0, (a, x) => a + x.$2.covers));
    }
  });
}
