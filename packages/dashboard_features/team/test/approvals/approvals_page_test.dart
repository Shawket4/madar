import 'package:dashboard_team/src/approvals/approvals_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'approvals_support.dart';

void main() {
  testWidgets('smoke: what the owner sees', (tester) async {
    final h = await pumpApprovals(tester);
    for (final r in tester.widgetList<PendingRow>(inPage(find.byType(PendingRow)))) {
      // ignore: avoid_print
      print('${r.item.key} | ${r.item.who} | ${r.item.kind} | ${r.item.detail} | ${r.item.at} | bulk=${r.item.batchable} | ro=${r.item.rejectOnly} | ${r.item.badges.map((b) => b.text).join(",")}');
    }
    for (final c in h.server.calls) {
      // ignore: avoid_print
      print('${c.method} ${c.path} ${c.query}');
    }
    expect(find.byType(Text), findsWidgets);
  });
}
