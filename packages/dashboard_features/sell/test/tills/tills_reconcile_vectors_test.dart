// madar-shared's reconcile_vectors.json (the web's pinned copy, via
// `sharedVectors`): the cases madar-till's live close check is tested against,
// as the web's `features/tills/util.test.ts` runs them. The close dialog must
// refuse exactly when the server would.
import 'package:dashboard_api/dashboard_api.dart' show ReconciliationInput;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_sell/src/tills/close_till_dialog.dart';
import 'package:dashboard_sell/src/tills/tills_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vectors = (sharedVectors('reconcile')! as List).cast<Map>();
  List<({String method, bool isCash})> totals(Map v) => [
    for (final t in (v['totals'] as List).cast<Map>())
      (method: t['method'] as String, isCash: t['is_cash'] as bool),
  ];
  List<Map> inputs(Map v) => (v['inputs'] as List).cast<Map>();

  test('reconcileRefusal names the code and method the server does', () {
    for (final v in vectors) {
      final err = (v['expected'] as Map)['Err'] as Map?;
      final got = reconcileRefusal(totals(v), [
        for (final i in inputs(v))
          ReconciliationInput(
            method: i['method'] as String,
            status: i['status'] as String,
            declaredAmount: i['declared_amount'] as int?,
            note: i['note'] as String?,
          ),
      ]);
      expect(
        got,
        err == null
            ? null
            : (code: err['code'] as String?, method: err['method'] as String),
        reason: v['name'] as String,
      );
    }
  });

  // The cases the form can say: one row per non-cash method, checked or
  // disagreed (no input reads as checked).
  final sayable = vectors.where((v) {
    final ins = inputs(v);
    return [
      for (var k = 0; k < ins.length; k++)
        ['checked', 'disagreed'].contains(ins[k]['status']) &&
            totals(v).any((t) => !t.isCash && t.method == ins[k]['method']) &&
            ins.indexWhere((j) => j['method'] == ins[k]['method']) == k,
    ].every((ok) => ok);
  }).toList();

  test('the form submits exactly when the server accepts', () {
    for (final v in sayable) {
      final rows = [
        for (final t in totals(v).where((t) => !t.isCash))
          () {
            final i = inputs(
              v,
            ).where((x) => x['method'] == t.method).firstOrNull;
            final amount = i?['declared_amount'] as int?;
            return CheckRow(t.method)
              ..disagreed = i?['status'] == 'disagreed'
              ..declared = amount == null ? '' : '${amount / 100}'
              ..note = (i?['note'] as String?) ?? '';
          }(),
      ];
      expect(
        rows.every((r) => r.valid),
        (v['expected'] as Map).containsKey('Ok'),
        reason: v['name'] as String,
      );
    }
    expect(
      sayable.where((v) => (v['expected'] as Map).containsKey('Err')),
      hasLength(5),
    );
  });

  test('a blank amount is sent as null, not 0', () {
    final r = CheckRow('card')
      ..disagreed = true
      ..note = 'x';
    expect(r.toInput().toJson(), containsPair('declared_amount', null));
    expect(r.valid, isFalse);
  });
}
