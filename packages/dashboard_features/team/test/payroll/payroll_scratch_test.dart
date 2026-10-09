import 'package:flutter/widgets.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'payroll_support.dart';

void main() {
  testWidgets('scratch', (tester) async {
    final h = await pumpPayroll(tester);
    final texts = inPage(find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList();
    debugPrint('TEXTS: ${texts.join(' | ')}');
    debugPrint('CALLS: ${h.server.calls.map((c) => '${c.method} ${c.path} ${c.status}').join('\n')}');
    await h.shot('payroll/scratch');
  });
}
