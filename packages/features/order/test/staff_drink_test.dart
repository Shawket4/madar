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
// The core decides all three; the fake bridge here only plays back what the
// core would answer, so a test that passes is a test about the UI obeying it.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
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

CartLineView _line() => const CartLineView(
  key: 'k-latte',
  itemId: 'latte',
  name: 'Latte',
  addons: [],
  optionals: [],
  unitPriceMinor: 4500,
  qty: 1,
  lineTotalMinor: 4500,
  bundleComponents: [],
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
    if (name == #locale) return 'en';
    if (name == #previewStaffDrink) {
      return _preview(invocation.namedArguments[#input]! as StaffDrinkInput);
    }
    if (name == #canRecordStaffDrink) return offered;
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
}
