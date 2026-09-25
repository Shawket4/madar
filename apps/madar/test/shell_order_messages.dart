part of 'shell_render_test.dart';

// ── Order messages reach the screen ──────────────────────────────────────────
//
// The silent-failure bug (2026-09-25): the order, cart, floor and bill screens
// kept telling the teller things — "Being edited on another till", "This bill
// was closed on another till", a refused round — into a toast slot nothing had
// drawn since the legacy order screen went (944b5fd5). The teller saw nothing.
//
// These walk each kind of message through the REAL shell and insist it is ON
// SCREEN, in the toast, over whatever is in front: a tab, a pushed page, a
// sheet. Reading the notifier's state proves nothing — that is exactly the
// check that passed while the teller was told nothing.

/// The toast on screen saying [text] — the one pill the app draws, wherever
/// it is drawn from.
Finder _toastSaying(String text) =>
    find.descendant(of: find.byType(ToastHost), matching: find.text(text));

/// The fixtures' room plus T8, whose parked order another till is editing.
FloorLayoutView _roomWithLockedTable() => FloorLayoutView(
  sections: _layout.sections,
  tables: [
    ..._layout.tables,
    FloorTableStateView(
      id: 't8',
      sectionId: 'sec-in',
      label: 'T8',
      seats: 4,
      shape: 'rect',
      status: 'seated',
      posX: 680,
      posY: 40,
      width: 90,
      height: 90,
      rotation: 0,
      heldOrderId: 'held-8',
      heldLockedByOther: true,
      heldSince: _ago(6),
    ),
  ],
);

/// The cart's Fire bar ("Fire · 3 items").
Finder _fireButton() =>
    find.textContaining('${coreWord('sell.fire')} · ').first;

/// Let a toast's own timer run out, so no timer outlives the test.
Future<void> _toastTimesOut(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 6));

void orderMessagesMain() {
  for (final rtl in [false, true]) {
    final tag = rtl ? ' · ar' : '';

    testWidgets('table locked: tapping a table another till is editing says '
        'so on the Floor$tag', (tester) async {
      final bridge = _FakeBridge(rtl: rtl)..layout = _roomWithLockedTable();
      await _mount(tester, bridge: bridge, size: _ipad);
      await _tab(tester, 'floor');
      await tester.tap(find.text('T8').first);
      await _settle(tester);
      expect(
        _toastSaying(coreWord('tables.locked', arabic: rtl)),
        findsOneWidget,
        reason: 'the refusal is shown, not only kept in a state',
      );
      await _shot(tester, 'order-messages-table-locked${rtl ? '-ar' : ''}');
      await _toastTimesOut(tester);
    });

    testWidgets('bill gone: a bill settled on another till while it is open '
        'says so and leaves$tag', (tester) async {
      final bridge = _FakeBridge(rtl: rtl);
      final container = await _mount(tester, bridge: bridge, size: _ipad);
      await _tab(tester, 'floor');
      _pageStack(tester).push(
        MaterialPageRoute<void>(
          builder: (_) => const BillScreen(ticketId: 'tk-1', canCharge: true),
        ),
      );
      await _settle(tester);
      expect(find.byType(BillScreen), findsOneWidget);

      // Settled on the other till: the pull drops the bill, the tick says so.
      bridge.tickets = _tickets.where((t) => t.id != 'tk-1').toList();
      container.read(ticketTickProvider.notifier).bump();
      await _settle(tester);

      expect(find.byType(BillScreen), findsNothing, reason: 'it left');
      expect(
        _toastSaying(coreWord('bill.gone', arabic: rtl)),
        findsOneWidget,
        reason: 'and the teller is told why',
      );
      await _shot(tester, 'order-messages-bill-gone${rtl ? '-ar' : ''}');
      await _toastTimesOut(tester);
    });
  }

  testWidgets("a round the core refuses says why, over the table's Sell", (
    tester,
  ) async {
    final bridge = _FakeBridge()
      ..tableCarts['t1'] = [_cartLine('latte', 'Latte', 4500, 2)]
      ..fireError = const MadarError.transient(detail: 'timeout');
    await _mount(tester, bridge: bridge, size: _ipad);
    await _tab(tester, 'floor');
    _pageStack(tester).push(
      MaterialPageRoute<void>(
        builder: (_) => const TableOrderScreen(tableId: 't1'),
      ),
    );
    await _settle(tester);
    await tester.tap(_fireButton());
    await _settle(tester);
    expect(
      _toastSaying(coreWord('err.network')),
      findsOneWidget,
      reason: 'a failed fire used to land in OrderState.error, drawn nowhere',
    );
    await _shot(tester, 'order-messages-fire-refused');
    await _toastTimesOut(tester);
  });

  testWidgets('a round that goes says it went', (tester) async {
    final bridge = _FakeBridge()
      ..tableCarts['t1'] = [_cartLine('latte', 'Latte', 4500, 2)];
    await _mount(tester, bridge: bridge, size: _ipad);
    await _tab(tester, 'floor');
    _pageStack(tester).push(
      MaterialPageRoute<void>(
        builder: (_) => const TableOrderScreen(tableId: 't1'),
      ),
    );
    await _settle(tester);
    await tester.tap(_fireButton());
    await _settle(tester);
    expect(_toastSaying(coreWord('waiter.fired')), findsOneWidget);
    await _toastTimesOut(tester);
  });

  testWidgets('a message raised while a sheet is up shows OVER the sheet, '
      'and its action answers', (tester) async {
    final container = await _mount(tester, bridge: _FakeBridge(), size: _ipad);
    unawaited(
      showMadarSheet<void>(
        tester.element(find.byType(MadarShellScaffold)),
        builder: (_) => const SizedBox(
          height: 320,
          child: Center(child: Text('A sheet in front')),
        ),
      ),
    );
    await _settle(tester);
    var undone = 0;
    container
        .read(orderProvider.notifier)
        .showToast(
          'Moved',
          actionLabel: 'Undo',
          action: () => undone += 1,
          seconds: 5,
        );
    await _settle(tester);
    expect(_toastSaying('Moved'), findsOneWidget);
    // A toast drawn UNDER the sheet's barrier cannot be tapped: this tap
    // would land on the barrier and the action would never run.
    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect(undone, 1, reason: 'the Undo answered over the sheet');
    expect(find.text('A sheet in front'), findsOneWidget);
    await _toastTimesOut(tester);
  });

  testWidgets('a Till notice raised while Sell is in front is shown on Sell', (
    tester,
  ) async {
    final bridge = _FakeBridge();
    final container = await _mount(tester, bridge: bridge, size: _ipad);
    await _tab(tester, 'till');
    await _tab(tester, 'sell');
    // The core keeps the sentence once; the Till drains it on its next read,
    // which a drawer move triggers whichever tab is in front.
    const said = 'Pay-out recorded without its advance tag';
    bridge.payOutNotices = [said];
    container.read(drawerTickProvider.notifier).bump();
    await _settle(tester);
    expect(find.byType(TakeawaySellScreen), findsOneWidget);
    expect(
      _toastSaying(said),
      findsOneWidget,
      reason: 'drained once: a toast drawn on the hidden Till tab is lost',
    );
    await _toastTimesOut(tester);
  });
}
