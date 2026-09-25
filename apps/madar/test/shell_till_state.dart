part of 'shell_render_test.dart';

// ── One till owner ───────────────────────────────────────────────────────────
//
// The owner's report (2026-09-25): "when configuring the device or
// reconfiguring it and opening a till, in the cart section it says no open
// till and open a till; pressing it routes to the open till screen even though
// we have a till open. Going back fixes everything and it doesn't recur until
// reconfiguring."
//
// These walk those steps through the REAL shell — the route host, the lock,
// the Till tab's opening form, the Sell tab's cart — and insist every reader
// of "is a till open here?" agrees the moment the core does.

/// The cart's "No till is open" notice with its Open till way on.
Finder _noTillNotice() => find.text(coreWord('sell.no_shift'));

/// The Open till button of the Till tab's opening form.
Finder _openTillButton() =>
    find.widgetWithText(MadarButton, coreWord('till.open_button'));

/// A first launch after the device was (re)configured: a fresh container and
/// a fresh shell, exactly what the app's reset hook mounts.
Future<ProviderContainer> _configure(
  WidgetTester tester,
  _FakeBridge bridge,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final container = await _mount(tester, bridge: bridge, size: _ipad);
  return container;
}

/// Count the drawer on the Till tab and tap Open till, the way a teller does.
Future<void> _openFromTillTab(WidgetTester tester) async {
  expect(
    _openTillButton(),
    findsOneWidget,
    reason: 'the Till tab offers the opening form',
  );
  await tester.tap(_openTillButton());
  await _settle(tester);
}

/// The rail's tab keys on screen.
Set<String> _railKeys(WidgetTester tester) => tester
    .widgetList<MadarRailTab>(find.byType(MadarRailTab))
    .map((t) => t.tab.key ?? '')
    .toSet();

/// The Sell tab's cart screen, as the [WidgetRef] a way-in call needs.
(BuildContext, WidgetRef) _sellRef(WidgetTester tester) {
  final element = tester.element(find.byType(OrderScreen));
  return (element, element as WidgetRef);
}

void tillStateMain() {
  for (final rtl in [false, true]) {
    final tag = rtl ? ' · ar' : '';
    testWidgets('owner report: configure → open a till → the cart shows the '
        'open till, with no "Open a till"$tag', (tester) async {
      final bridge = _FakeBridge(tillOpen: false, rtl: rtl);
      final container = await _configure(tester, bridge);
      // Walled to the Till tab: no drawer, no shop.
      expect(find.byType(OpenTillScreen), findsOneWidget);
      expect(find.byType(TakeawaySellScreen), findsNothing);

      final button = find.widgetWithText(
        MadarButton,
        coreWord('till.open_button', arabic: rtl),
      );
      expect(button, findsOneWidget);
      await tester.tap(button);
      await _settle(tester);

      expect(bridge.opens, 1, reason: 'the open reached the core once');
      expect(
        find.byType(TakeawaySellScreen),
        findsOneWidget,
        reason: 'with a drawer open the shell lands on Sell',
      );
      expect(
        find.text(coreWord('sell.no_shift', arabic: rtl)),
        findsNothing,
        reason: 'the cart must see the till the core just opened',
      );
      expect(
        find.text(coreWord('sell.open_till', arabic: rtl)),
        findsNothing,
        reason: 'and offer no way to open another',
      );
      // Every reader agrees because there is one: the shell's till.
      expect(container.read(shellProvider).till?.id, 'sh-1');
      expect(container.read(shellProvider).locked, isFalse);
      await _shot(tester, 'till-state-configure-open-cart${rtl ? '-ar' : ''}');
    });
  }

  testWidgets('owner report: reconfigure → open a till → the cart is right '
      'the first time too', (tester) async {
    final bridge = _FakeBridge(tillOpen: false);
    await _configure(tester, bridge);
    await _openFromTillTab(tester);
    expect(_noTillNotice(), findsNothing);

    // Reconfiguring needs the till closed first; the reset hook then mounts
    // a fresh container, and the next open is a different till.
    bridge
      ..tillOpen = false
      ..tillSeq = 2;
    final container = await _configure(tester, bridge);
    expect(find.byType(OpenTillScreen), findsOneWidget);
    await _openFromTillTab(tester);

    expect(find.byType(TakeawaySellScreen), findsOneWidget);
    expect(_noTillNotice(), findsNothing);
    expect(container.read(shellProvider).till?.id, 'sh-2');
  });

  testWidgets('close, then open again: every reader moves to the NEW till, '
      'with no screen asking', (tester) async {
    final bridge = _FakeBridge(tillOpen: false);
    final container = await _configure(tester, bridge);
    await _openFromTillTab(tester);
    expect(container.read(shellProvider).till?.id, 'sh-1');

    // The close lands in the core — here, or made on the dashboard and
    // brought by a pull. Nobody calls the shell: the core's `tills` table
    // change (the drawer tick) is enough.
    bridge
      ..tillOpen = false
      ..tillSeq = 2;
    container.read(drawerTickProvider.notifier).bump();
    await _settle(tester);
    expect(container.read(shellProvider).till, isNull);
    expect(_railKeys(tester), {'till'}, reason: 'locked the moment it closed');
    expect(find.byType(OpenTillScreen), findsOneWidget);
    expect(find.byType(TakeawaySellScreen), findsNothing);

    await _openFromTillTab(tester);
    expect(
      container.read(shellProvider).till?.id,
      'sh-2',
      reason: 'the till settles and sales book onto — never the closed one',
    );
    // The teller stays on the Till tab they opened from: the drawer now,
    // never the form, over an open till.
    expect(find.byType(OpenTillScreen), findsNothing);
    expect(_railKeys(tester), containsAll(<String>['sell', 'till']));
    await _tab(tester, 'sell');
    expect(find.byType(TakeawaySellScreen), findsOneWidget);
    expect(_noTillNotice(), findsNothing);
  });

  testWidgets('the way in refuses the open-till page over an open till, and '
      'says the till is already open', (tester) async {
    final bridge = _FakeBridge();
    final container = await _configure(tester, bridge);
    expect(container.read(shellProvider).tillOpen, isTrue);
    final (context, ref) = _sellRef(tester);
    await openTillPage(context, ref);
    await _settle(tester);
    expect(find.byType(OpenTillPage), findsNothing, reason: 'never pushed');
    expect(find.byType(OpenTillScreen), findsNothing);
    expect(bridge.opens, 0, reason: 'nothing asked the core to open');
    expect(find.text(coreWord('till.already_open')), findsOneWidget);
    // Let the toast's own timer run out.
    await tester.pump(const Duration(seconds: 3));
  });

  group('an open-till page already up', () {
    /// A shell that could not read the lock fails OPEN — the one way a
    /// teller reaches Sell with no till, and so its "Open till" way in.
    Future<ProviderContainer> pageUp(
      WidgetTester tester,
      _FakeBridge bridge,
    ) async {
      bridge.lockAnswers = false;
      final container = await _configure(tester, bridge);
      await _tab(tester, 'sell');
      expect(_noTillNotice(), findsOneWidget);
      await tester.tap(_noTillNotice());
      await _settle(tester);
      expect(find.byType(OpenTillPage), findsOneWidget);
      return container;
    }

    testWidgets('leaves the moment a till opens elsewhere', (tester) async {
      final bridge = _FakeBridge(tillOpen: false);
      final container = await pageUp(tester, bridge);
      await _shot(tester, 'till-state-open-page-up');

      // Opened on the Till tab, or on this person's other session and
      // pulled here: the core's till table moves, nobody touches the page.
      bridge.tillOpen = true;
      container.read(drawerTickProvider.notifier).bump();
      await _settle(tester);

      expect(find.byType(OpenTillPage), findsNothing, reason: 'it left');
      expect(bridge.opens, 0, reason: 'this page opened nothing');
      expect(_noTillNotice(), findsNothing, reason: 'the cart follows too');
    });

    testWidgets('opening from it lands back on the cart, till open', (
      tester,
    ) async {
      final bridge = _FakeBridge(tillOpen: false);
      final container = await pageUp(tester, bridge);
      await tester.tap(_openTillButton());
      await _settle(tester);
      expect(bridge.opens, 1);
      expect(find.byType(OpenTillPage), findsNothing);
      expect(_noTillNotice(), findsNothing);
      expect(container.read(shellProvider).till?.id, 'sh-1');
    });

    testWidgets('a core that answers "already open" mints nothing, and the '
        'teller is told', (tester) async {
      final bridge = _FakeBridge(tillOpen: false);
      await pageUp(tester, bridge);
      // The core holds a till the shell has not re-read yet (a race).
      bridge.tillOpen = true;
      await tester.tap(_openTillButton());
      await _settle(tester);
      expect(bridge.opens, 1, reason: 'the core was asked once');
      expect(bridge.tillSeq, 1, reason: 'and minted no second till');
      expect(find.byType(OpenTillPage), findsNothing);
      expect(find.text(coreWord('till.already_open')), findsOneWidget);
      expect(_noTillNotice(), findsNothing);
      // Let the toast's own timer run out.
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
