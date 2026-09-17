// The waste screen sequences the core: pick, quantity, reason, record — and a
// waste over the person's limit goes through the manager's PIN first.

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_till/feature_till.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Bridge implements MadarBridge {
  _Bridge({required this.outcome});

  /// What the core decides for the waste.
  final String outcome;
  final List<WasteInput> recorded = [];
  final List<ApprovalView?> approvals = [];
  final List<String> pins = [];

  static const _approval = ApprovalView(
    id: 'ap-1',
    capability: 'inventory.waste.record',
    approverId: 'm-1',
    approverName: 'Mona',
    valueMinor: 1200,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final args = invocation.namedArguments;
    if (name == #tr) return args[#key];
    if (name == #currentSession) return null;
    if (name == #wasteItems) {
      return const [
        WasteItemView(id: 'latte', name: 'Latte', sizes: ['Small', 'Large']),
      ];
    }
    if (name == #wasteIngredients) {
      return const [
        WasteIngredientView(
          id: 'milk',
          name: 'Milk',
          unit: 'ml',
          units: ['ml', 'l'],
        ),
      ];
    }
    if (name == #wasteReasons) {
      return const [
        WasteReasonView(key: 'spoiled', label: 'Spoiled'),
        WasteReasonView(key: 'other', label: 'Other'),
      ];
    }
    if (name == #previewWaste) {
      return WastePreviewView(
        lines: const [WasteLineView(name: 'Beans', quantity: 18, unit: 'g')],
        valueMinor: 1200,
        valuePartial: false,
        decision: ActDecisionView(
          outcome: outcome,
          reason: outcome == 'allow' ? '' : 'over your limit',
        ),
      );
    }
    if (name == #approveWaste) {
      pins.add(args[#approverPin] as String);
      return Future<ApprovalView>.value(_approval);
    }
    if (name == #recordWaste) {
      recorded.add(args[#input] as WasteInput);
      approvals.add(args[#approval] as ApprovalView?);
      return Future<WasteRecordedView>.value(
        const WasteRecordedView(
          id: 'w-1',
          subjectName: 'Latte',
          quantity: 1,
          unit: 'pcs',
          valueMinor: 1200,
        ),
      );
    }
    if (name == #formatMoney) return '12.00';
    return super.noSuchMethod(invocation);
  }
}

Future<void> _pump(WidgetTester tester, _Bridge bridge) async {
  tester.view.physicalSize = const Size(1194, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
      child: MaterialApp(theme: MadarTheme.light(), home: const WasteScreen()),
    ),
  );
  await tester.pump();
}

Future<void> _fill(WidgetTester tester) async {
  await tester.tap(find.text('Latte'));
  await tester.pump();
  await tester.tap(find.text('Large'));
  await tester.enterText(
    find
        .byWidgetPredicate(
          (w) => w is EditableText && w.controller.text.isEmpty,
        )
        .at(1),
    '2',
  );
  await tester.pump();
  await tester.tap(find.text('Spoiled'));
  await tester.pump();
}

void main() {
  testWidgets('a waste within the limit is recorded as picked', (tester) async {
    final bridge = _Bridge(outcome: 'allow');
    await _pump(tester, bridge);
    await _fill(tester);
    expect(find.text('Beans'), findsOneWidget, reason: 'the preview lines');
    await tester.tap(find.text('waste.record').last);
    await tester.pump();
    await tester.pump();

    expect(bridge.recorded, hasLength(1));
    final input = bridge.recorded.single;
    expect(input.subjectKind, 'menu_item');
    expect(input.subjectId, 'latte');
    expect(input.sizeLabel, 'Large');
    expect(input.quantity, 2);
    expect(input.reason, 'spoiled');
    expect(bridge.approvals.single, isNull);
    expect(bridge.pins, isEmpty);
  });

  testWidgets(
    'a waste over the limit asks a manager and carries the approval',
    (tester) async {
      final bridge = _Bridge(outcome: 'needs_approval');
      await _pump(tester, bridge);
      await _fill(tester);
      await tester.tap(find.text('waste.record').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('approval.title'), findsOneWidget);
      await tester.enterText(find.byType(EditableText).last, '123456');
      await tester.tap(find.text('approval.approve'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(bridge.pins, ['123456']);
      expect(bridge.recorded, hasLength(1));
      expect(bridge.approvals.single?.id, 'ap-1');
    },
  );

  testWidgets('a refused waste records nothing and says why', (tester) async {
    final bridge = _Bridge(outcome: 'deny');
    await _pump(tester, bridge);
    await _fill(tester);
    await tester.tap(find.text('waste.record').last);
    await tester.pump();

    expect(bridge.recorded, isEmpty);
    expect(find.text('over your limit'), findsOneWidget);
  });
}
