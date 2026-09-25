// The staff-drink action on a cart line, at TABLET sizes — the till's real
// shape, where the sheet lives beside a menu grid and not on a phone.
//
// Three things are pinned here, and each one is a rule somebody could quietly
// lose in a refactor:
//   * the action is HIDDEN when the core says it is not offered — no grant, no
//     pool, an item off the list. Hidden, not greyed;
//   * Save stays DEAD on a blank or whitespace note. The note is the only
//     record of who drank it, and whitespace is not a note;
//   * the over-allowance warning RENDERS and Save stays alive under it. An
//     overspend is warned about and then allowed, because the drink was already
//     made and the sale already rung.
//
//   * saving MARKS the line (it records nothing — the pool entry is written
//     when the order is charged); a marked line wears a "Staff drink" badge and
//     its normal price struck through beside what is still charged; the badge
//     reopens the sheet to edit the note or take the mark off;
//   * a table's bill never offers the action.
//
// The core decides all of it; the fake bridge here only plays back what the
// core would answer, so a test that passes is a test about the UI obeying it.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/staff_drink_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The iPad, landscape — the primary target.
const Size _ipad = Size(1194, 834);
const Size _ipadPortrait = Size(834, 1194);

/// The iPad 9th generation (10.2"): the smallest iPad the till ships on.
const Size _ipad9 = Size(1080, 810);

/// An 8" Android tablet, portrait.
const Size _tab8 = Size(800, 1280);

const _tablets = <(String, Size)>[
  ('ipad', _ipad),
  ('ipadp', _ipadPortrait),
  ('ipad9', _ipad9),
  ('tab8', _tab8),
];

/// The same line once the core has marked it: normal 4500, [charged] still due.
CartLineView _marked({int charged = 0}) => CartLineView(
  dealCutMinor: 0,
  kind: 'item',
  parts: const [],
  key: 'k-latte|staff:d1',
  itemId: 'latte',
  name: 'Latte',
  addons: const [],
  optionals: const [],
  unitPriceMinor: 4500,
  qty: 1,
  lineTotalMinor: 4500,
  staffDrink: CartStaffDrinkView(
    id: 'd1',
    note: 'for Sara',
    compMinor: 4500 - charged,
    chargedMinor: charged,
  ),
);

CartLineView _line() => const CartLineView(
  dealCutMinor: 0,
  kind: 'item',
  parts: [],
  key: 'k-latte',
  itemId: 'latte',
  name: 'Latte',
  addons: [],
  optionals: [],
  unitPriceMinor: 4500,
  qty: 1,
  lineTotalMinor: 4500,
);

StaffPoolDay _day({int allowance = 5, int used = 0}) => StaffPoolDay(
  businessDate: '2026-09-19',
  allowance: allowance,
  used: used,
  remaining: allowance - used < 0 ? 0 : allowance - used,
  over: used - allowance < 0 ? 0 : used - allowance,
);

/// A bridge that answers exactly what the core would, for one scenario.
class _FakeBridge implements MadarBridge {
  _FakeBridge({
    this.offered = true,
    this.overspent = false,
    this.access = 'allow',
  });

  /// The core says this line is on the pool and this person may act.
  final bool offered;

  /// This drink would go past today's allowance.
  final bool overspent;

  /// `allow` / `needs_approval` / `deny`.
  final String access;

  /// Every input the sheet asked the core about, in order.
  final List<StaffDrinkInput> asked = [];

  /// Every drink actually recorded.
  final List<StaffDrinkInput> recorded = [];

  /// Every (line key, note) MARKED, every note edit, every mark removed.
  final List<(String, String)> marked = [];
  final List<(String, String)> edited = [];
  final List<String> removed = [];

  /// The table context each of those calls named.
  final List<String?> contexts = [];

  StaffDrinkPreviewView _preview(StaffDrinkInput input) {
    asked.add(input);
    // The engine's order: the pool, then the item, then the note. Here the
    // first two already passed (that is what `offered` means), so the only
    // thing left to refuse is a blank note — whitespace included.
    final hasNote = input.note.trim().isNotEmpty;
    final pool = overspent
        ? _day(allowance: 2, used: hasNote ? 3 : 2)
        : _day(used: hasNote ? 1 : 0);
    return StaffDrinkPreviewView(
      offered: offered,
      access: ActDecisionView(outcome: access, reason: 'a manager must say so'),
      decision: StaffDrinkDecision(
        allowed: hasNote,
        refusal: hasNote ? null : StaffDrinkRefusal.noteRequired,
        overspent: hasNote && overspent,
        pool: pool,
      ),
      reason: hasNote ? '' : coreWord('staff_pool.refused.note'),
      overWarning: hasNote && overspent
          ? coreWord('staff_pool.over_warning')
          : '',
      poolLabel: overspent
          ? coreWord('staff_pool.over_today').replaceAll('{count}', '1')
          : coreWord(
              'staff_pool.left_today',
            ).replaceAll('{count}', '${pool.remaining}'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => 'manager');
    if (can != null) return can;
    final name = invocation.memberName;
    if (name == #tr) {
      return coreWord(invocation.namedArguments[#key] as String? ?? '');
    }
    if (name == #isRtl) return false;
    if (name == #currentSession) return null;
    if (name == #locale) return 'en';
    if (name == #previewStaffDrink) {
      return _preview(invocation.namedArguments[#input]! as StaffDrinkInput);
    }
    if (name == #canRecordStaffDrink) return offered;
    final args = invocation.namedArguments;
    if (name == #markStaffDrink) {
      contexts.add(args[#tableId] as String?);
      marked.add((args[#lineKey]! as String, args[#note]! as String));
      return Future<List<CartLineView>>.value([_marked()]);
    }
    if (name == #editStaffDrinkNote) {
      contexts.add(args[#tableId] as String?);
      edited.add((args[#lineKey]! as String, args[#note]! as String));
      return Future<List<CartLineView>>.value([_marked()]);
    }
    if (name == #unmarkStaffDrink) {
      contexts.add(args[#tableId] as String?);
      removed.add(args[#lineKey]! as String);
      return Future<List<CartLineView>>.value([_line()]);
    }
    // What the cart re-reads after the core changed it.
    if (name == #takeStaffDrinkNotices) return <String>[];
    if (name == #cartLines) {
      return Future<List<CartLineView>>.value([
        if (removed.isEmpty) _marked() else _line(),
      ]);
    }
    if (name == #cartTotals) {
      return Future<CartTotals>.value(
        const CartTotals(
          itemCount: 1,
          subtotalMinor: 0,
          discountMinor: 0,
          taxMinor: 0,
          serviceChargeMinor: 0,
          totalMinor: 0,
        ),
      );
    }
    if (name == #cartMeta) {
      return Future<CartMeta>.value(const CartMeta(name: ''));
    }
    if (name == #recordStaffDrink) {
      final input = invocation.namedArguments[#input]! as StaffDrinkInput;
      recorded.add(input);
      return Future<StaffDrinkRecordedView>.value(
        StaffDrinkRecordedView(
          id: 'd1',
          itemName: 'Latte',
          quantity: 1,
          overspent: overspent,
          pool: _day(used: 1),
          message: coreWord('staff_pool.recorded'),
        ),
      );
    }
    throw UnimplementedError('$name');
  }
}

Future<void> _mount(
  WidgetTester tester, {
  required Widget child,
  required Size size,
  required _FakeBridge bridge,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: MadarTheme.light(),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  for (final (device, size) in _tablets) {
    group('the staff drink action on $device', () {
      testWidgets('is hidden when the core does not offer it', (tester) async {
        // No grant, no pool, or an item off the list — one absence, one answer.
        // Hidden, not greyed: there is nothing to explain about a pool the
        // branch never switched on.
        final bridge = _FakeBridge(offered: false);
        await _mount(
          tester,
          size: size,
          bridge: bridge,
          child: StaffDrinkTile(line: _line()),
        );
        expect(find.byType(MadarGlyphTile), findsNothing);
        expect(find.byKey(const ValueKey('staff-drink-k-latte')), findsNothing);
      });

      testWidgets('is drawn when the core offers it', (tester) async {
        final bridge = _FakeBridge();
        await _mount(
          tester,
          size: size,
          bridge: bridge,
          child: StaffDrinkTile(line: _line()),
        );
        expect(
          find.byKey(const ValueKey('staff-drink-k-latte')),
          findsOneWidget,
        );
      });

      testWidgets('will not save without a note, and whitespace is not one', (
        tester,
      ) async {
        final bridge = _FakeBridge();
        await _mount(
          tester,
          size: size,
          bridge: bridge,
          child: StaffDrinkSheet(line: _line()),
        );
        final save = find.byKey(const ValueKey('staff-drink-save'));
        expect(save, findsOneWidget);
        expect(
          tester.widget<MadarButton>(save).enabled,
          isFalse,
          reason: 'a blank note saves nothing',
        );

        await tester.enterText(
          find.byKey(const ValueKey('staff-drink-note')),
          '   \t  ',
        );
        await tester.pump();
        expect(
          tester.widget<MadarButton>(save).enabled,
          isFalse,
          reason: 'whitespace is not a note',
        );

        await tester.enterText(
          find.byKey(const ValueKey('staff-drink-note')),
          'for Sara, closing shift',
        );
        await tester.pump();
        expect(tester.widget<MadarButton>(save).enabled, isTrue);
        expect(bridge.recorded, isEmpty, reason: 'nothing recorded yet');
      });

      testWidgets('warns over the allowance and STILL lets it through', (
        tester,
      ) async {
        // The drink was already made and the sale already rung: refusing the
        // record now would only lose the evidence.
        final bridge = _FakeBridge(overspent: true);
        await _mount(
          tester,
          size: size,
          bridge: bridge,
          child: StaffDrinkSheet(line: _line()),
        );
        await tester.enterText(
          find.byKey(const ValueKey('staff-drink-note')),
          'for Sara',
        );
        await tester.pump();
        expect(
          find.text(coreWord('staff_pool.over_warning')),
          findsOneWidget,
          reason: 'the teller is told, in words',
        );
        expect(
          tester
              .widget<MadarButton>(
                find.byKey(const ValueKey('staff-drink-save')),
              )
              .enabled,
          isTrue,
          reason: 'an overspend is warned about, never blocked',
        );
      });
    });
  }

  testWidgets('a teller without the grant is still offered the action', (
    tester,
  ) async {
    // The capability carries `approval = true`: the answer to "you may not" is
    // a manager's PIN on this device, not a wall. The tile is drawn, and the
    // sheet is reached; the PIN is asked for at the moment of recording.
    final bridge = _FakeBridge(access: 'needs_approval');
    await _mount(
      tester,
      size: _ipad,
      bridge: bridge,
      child: StaffDrinkTile(line: _line()),
    );
    expect(find.byKey(const ValueKey('staff-drink-k-latte')), findsOneWidget);
  });

  testWidgets('the sheet asks the core about the note the teller typed', (
    tester,
  ) async {
    // Not about an empty field: the refusal and the warning have to be about
    // what is actually written, or the sheet would argue with itself.
    final bridge = _FakeBridge();
    await _mount(
      tester,
      size: _ipad,
      bridge: bridge,
      child: StaffDrinkSheet(line: _line()),
    );
    await tester.enterText(
      find.byKey(const ValueKey('staff-drink-note')),
      'for Sara',
    );
    await tester.pump();
    expect(bridge.asked.last.note, 'for Sara');
    expect(bridge.asked.last.menuItemId, 'latte');
  });

  testWidgets('saving MARKS the line and records nothing', (tester) async {
    // The pool entry is written when the order is charged, with the order —
    // an abandoned cart must not burn the allowance.
    final bridge = _FakeBridge();
    await _mount(
      tester,
      size: _ipad,
      bridge: bridge,
      child: StaffDrinkSheet(line: _line()),
    );
    await tester.enterText(
      find.byKey(const ValueKey('staff-drink-note')),
      'for Sara',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('staff-drink-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(bridge.marked, [('k-latte', 'for Sara')]);
    expect(bridge.contexts, [null], reason: "the counter's cart");
    expect(bridge.recorded, isEmpty, reason: 'nothing is spent at tap time');
  });

  testWidgets('a marked line wears the badge and loses the tile', (
    tester,
  ) async {
    final bridge = _FakeBridge();
    await _mount(
      tester,
      size: _ipad,
      bridge: bridge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StaffDrinkBadge(line: _marked()),
          StaffDrinkTile(line: _marked()),
          // An unmarked line has no badge at all.
          StaffDrinkBadge(line: _line()),
        ],
      ),
    );
    // A tag sets its label in capitals.
    expect(
      find.text(coreWord('staff_pool.badge').toUpperCase()),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('staff-badge-k-latte|staff:d1')),
      findsOneWidget,
    );
    expect(
      find.byType(MadarGlyphTile),
      findsNothing,
      reason: "a marked line's way back in is its badge",
    );
  });

  testWidgets('a free staff drink strikes its normal price and says Free', (
    tester,
  ) async {
    await _mount(
      tester,
      size: _ipad,
      bridge: _FakeBridge(),
      child: StaffDrinkPrice(line: _marked(), currency: 'EGP'),
    );
    final normal = tester.widget<MoneyText>(
      find.byKey(const ValueKey('staff-normal-k-latte|staff:d1')),
    );
    expect(normal.minor, 4500, reason: 'the NORMAL price is still shown');
    expect(normal.style?.decoration, TextDecoration.lineThrough);
    expect(find.text(coreWord('staff_pool.line_free')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('staff-charged-k-latte|staff:d1')),
      findsNothing,
    );
  });

  testWidgets('extras on a staff drink show what is still charged', (
    tester,
  ) async {
    await _mount(
      tester,
      size: _ipad,
      bridge: _FakeBridge(),
      child: StaffDrinkPrice(line: _marked(charged: 2500), currency: 'EGP'),
    );
    expect(find.text(coreWord('staff_pool.line_extras')), findsOneWidget);
    final charged = tester.widget<MoneyText>(
      find.byKey(const ValueKey('staff-charged-k-latte|staff:d1')),
    );
    expect(charged.minor, 2500, reason: "the core's figure, not a sum");
    expect(find.text(coreWord('staff_pool.line_free')), findsNothing);
  });

  testWidgets('the badge reopens the sheet to edit the note', (tester) async {
    final bridge = _FakeBridge();
    await _mount(
      tester,
      size: _ipad,
      bridge: bridge,
      child: StaffDrinkSheet(line: _marked()),
    );
    // Opened on what was written, not on an empty field.
    expect(find.text('for Sara'), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-drink-save')), findsNothing);
    // The pool is asked about THIS line, so it does not count itself.
    expect(bridge.asked.last.lineKey, 'k-latte|staff:d1');

    // The note stays required.
    await tester.enterText(find.byKey(const ValueKey('staff-drink-note')), ' ');
    await tester.pump();
    final save = find.byKey(const ValueKey('staff-drink-save-note'));
    expect(tester.widget<MadarButton>(save).enabled, isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('staff-drink-note')),
      'for Omar',
    );
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(bridge.edited, [('k-latte|staff:d1', 'for Omar')]);
    expect(bridge.removed, isEmpty);
  });

  testWidgets('Remove takes the mark off and the price comes back', (
    tester,
  ) async {
    final bridge = _FakeBridge();
    late WidgetRef seen;
    await _mount(
      tester,
      size: _ipad,
      bridge: bridge,
      child: Consumer(
        builder: (context, ref, _) {
          seen = ref;
          return StaffDrinkSheet(line: _marked());
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('staff-drink-remove')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(bridge.removed, ['k-latte|staff:d1']);
    // The cart was re-read from the core: the line is a plain one again.
    final lines = seen.read(cartProvider(null)).lines;
    expect(lines.single.staffDrink, isNull);
    expect(lines.single.lineTotalMinor, 4500);
  });

  testWidgets("a table's bill never offers the action", (tester) async {
    // The server refuses a pooled line on a ticket, so the tile is not there
    // to be tapped: not in a table's cart, not in a cart that fires a round.
    final bridge = _FakeBridge();
    await _mount(
      tester,
      size: _ipad,
      bridge: bridge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StaffDrinkTile(line: _line(), tableId: 'table-4'),
          StaffDrinkTile(line: _line(), counterSale: false),
        ],
      ),
    );
    expect(find.byType(MadarGlyphTile), findsNothing);
    expect(bridge.asked, isEmpty, reason: 'the pool is not even consulted');
  });
}
