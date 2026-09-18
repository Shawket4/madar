// "N actions need a manager": the till indicator, the list of what and why,
// and the one PIN that clears the batch — including a partial result, which
// must stay on screen with every item the approver could not cover.

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_till/feature_till.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _refusedVoid = ManagerActionView(
  id: 'op:7',
  kind: 'refused',
  what: 'Void',
  why: 'The server would not accept it without a manager.',
  capability: 'orders.void',
  personName: 'Sara',
  personId: 'u-teller',
  occurredAt: '2026-09-17T10:00:00Z',
  amountMinor: 500,
);
const _flaggedDiscount = ManagerActionView(
  id: 'flag:3',
  kind: 'flagged',
  what: 'Discount over the cap',
  why: 'It went through, but without the permission.',
  capability: 'orders.discount.manual_amount',
  personName: 'Sara',
  personId: 'u-teller',
  occurredAt: '2026-09-17T09:00:00Z',
);

class _Bridge implements MadarBridge {
  _Bridge({required this.view, required this.result});

  ManagerActionsView view;
  final BatchAuthorizeView result;
  final List<String> pins = [];
  final List<List<String>> batches = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final args = invocation.namedArguments;
    if (name == #tr) return args[#key];
    if (name == #currentSession) return null;
    if (name == #formatStamp) return '17 Sep 10:00';
    if (name == #pendingManagerActions) return view;
    if (name == #refreshReviewFlags) return Future<int>.value(0);
    if (name == #authorizeManagerActions) {
      pins.add(args[#approverPin] as String);
      batches.add(args[#ids] as List<String>);
      // Whatever was cleared leaves the list.
      view = ManagerActionsView(
        count: result.left.length,
        items: result.left,
        headline: '${result.left.length} review.needs_manager',
        canAuthorize: result.left.isNotEmpty,
        blockedReason: '',
      );
      return Future<BatchAuthorizeView>.value(result);
    }
    return super.noSuchMethod(invocation);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Bridge bridge,
  Widget home, {
  Size size = const Size(1194, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
      child: MaterialApp(theme: MadarTheme.light(), home: home),
    ),
  );
  await tester.pump();
}

ManagerActionsView _list(
  List<ManagerActionView> items, {
  bool canAuthorize = true,
  String blocked = '',
}) => ManagerActionsView(
  count: items.length,
  items: items,
  headline: '${items.length} actions need a manager',
  canAuthorize: canAuthorize,
  blockedReason: blocked,
);

void main() {
  testWidgets('the indicator is silent with nothing to clear', (tester) async {
    final bridge = _Bridge(
      view: _list(const [], canAuthorize: false),
      result: const BatchAuthorizeView(
        authorized: [],
        left: [],
        summary: '0 of 0',
      ),
    );
    await _pump(tester, bridge, const ManagerActionsBanner());
    expect(find.byType(NoticeBanner), findsNothing);
  });

  testWidgets('the indicator counts what needs a manager', (tester) async {
    final bridge = _Bridge(
      view: _list(const [_refusedVoid, _flaggedDiscount]),
      result: const BatchAuthorizeView(
        authorized: [],
        left: [],
        summary: '0 of 0',
      ),
    );
    await _pump(tester, bridge, const ManagerActionsBanner());
    expect(find.text('2 actions need a manager'), findsOneWidget);
  });

  for (final size in const [Size(1080, 810), Size(810, 1080)]) {
    testWidgets('the batch lays out on the small iPad at $size', (
      tester,
    ) async {
      final bridge = _Bridge(
        view: _list(const [_refusedVoid, _flaggedDiscount]),
        result: const BatchAuthorizeView(
          authorized: [],
          left: [],
          summary: '0 of 0',
        ),
      );
      await _pump(tester, bridge, const ManagerActionsScreen(), size: size);
      expect(find.text('Void'), findsWidgets);
      expect(tester.takeException(), isNull, reason: '$size laid out cleanly');
    });
  }

  testWidgets('the list says what each one was, who and why', (tester) async {
    final bridge = _Bridge(
      view: _list(const [_refusedVoid, _flaggedDiscount]),
      result: const BatchAuthorizeView(
        authorized: [],
        left: [],
        summary: '0 of 0',
      ),
    );
    await _pump(tester, bridge, const ManagerActionsScreen());
    expect(find.text('Void'), findsWidgets);
    expect(find.text('Discount over the cap'), findsWidgets);
    expect(find.textContaining('Sara'), findsWidgets);
    expect(
      find.textContaining('would not accept it without a manager'),
      findsOneWidget,
    );
  });

  testWidgets('offline, the list shows and says it needs a connection', (
    tester,
  ) async {
    final bridge = _Bridge(
      view: _list(
        const [_refusedVoid],
        canAuthorize: false,
        blocked: 'Connect to the internet to let a manager clear these.',
      ),
      result: const BatchAuthorizeView(
        authorized: [],
        left: [],
        summary: '0 of 0',
      ),
    );
    await _pump(tester, bridge, const ManagerActionsScreen());
    expect(find.text('Void'), findsWidgets);
    expect(find.textContaining('Connect to the internet'), findsOneWidget);
    await tester.tap(find.text('review.title').last);
    await tester.pump();
    expect(bridge.pins, isEmpty, reason: 'the PIN is not even asked for');
  });

  testWidgets('one PIN clears the whole batch', (tester) async {
    final bridge = _Bridge(
      view: _list(const [_refusedVoid, _flaggedDiscount]),
      result: const BatchAuthorizeView(
        authorized: ['op:7', 'flag:3'],
        left: [],
        summary: '2 of 2',
      ),
    );
    await _pump(tester, bridge, const ManagerActionsScreen());
    await tester.tap(find.text('review.title').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, '9999');
    await tester.tap(find.text('approval.approve'));
    await tester.pumpAndSettle();

    expect(bridge.pins, ['9999']);
    expect(
      bridge.batches.single,
      isEmpty,
      reason: 'nothing picked = all of it',
    );
    expect(find.text('2 of 2'), findsOneWidget);
  });

  testWidgets('a partial result keeps what is left, with its reason', (
    tester,
  ) async {
    final bridge = _Bridge(
      view: _list(const [_refusedVoid, _flaggedDiscount]),
      result: const BatchAuthorizeView(
        authorized: ['flag:3'],
        left: [
          ManagerActionView(
            id: 'op:7',
            kind: 'refused',
            what: 'Void',
            why: 'Mona may not approve a void.',
            capability: 'orders.void',
            personName: 'Sara',
            personId: 'u-teller',
            occurredAt: '2026-09-17T10:00:00Z',
          ),
        ],
        summary: '1 of 2',
      ),
    );
    await _pump(tester, bridge, const ManagerActionsScreen());
    await tester.tap(find.text('review.title').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, '9999');
    await tester.tap(find.text('approval.approve'));
    await tester.pumpAndSettle();

    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Void'), findsWidgets, reason: 'still listed');
    expect(find.textContaining('may not approve a void'), findsOneWidget);
    expect(
      find.text('Discount over the cap'),
      findsNothing,
      reason: 'what was cleared is gone',
    );
  });

  testWidgets('picking narrows the batch to what was chosen', (tester) async {
    final bridge = _Bridge(
      view: _list(const [_refusedVoid, _flaggedDiscount]),
      result: const BatchAuthorizeView(
        authorized: ['flag:3'],
        left: [],
        summary: '1 of 1',
      ),
    );
    await _pump(tester, bridge, const ManagerActionsScreen());
    // Everything starts picked; tapping one drops exactly that one.
    await tester.tap(find.text('Void').first);
    await tester.pump();
    await tester.tap(find.text('review.title').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, '9999');
    await tester.tap(find.text('approval.approve'));
    await tester.pumpAndSettle();

    expect(bridge.batches.single, ['flag:3']);
  });
}
