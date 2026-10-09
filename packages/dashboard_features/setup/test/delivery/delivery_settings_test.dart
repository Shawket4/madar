// `/settings/delivery` Delivery settings, driven through the real app shell
// (SET-DLV-001..022).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/brand_appearance/settings_shell.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

final String _helio = atBranch(SeedIds.heliopolis);
final String _newCairo = atBranch(SeedIds.newCairo);
final String _zamalek = atBranch(SeedIds.zamalek);

/// The seeded row of [branchId] (the area seed's `delivery_settings`).
MockRow _row(MockDb db, String branchId) =>
    db['delivery_settings'].firstWhere((r) => r['branch_id'] == branchId)!;

Future<void> _save(DashHarness h) async {
  await h.tester.ensureVisible(byKey('dlv-save'));
  await h.tap(byKey('dlv-save'));
}

Future<void> _toggle(DashHarness h, String key) async {
  final sw = inKey(key, find.byType(DashSwitch));
  await h.tester.ensureVisible(sw);
  await h.tap(sw);
}

/// Opens the select keyed [key] and picks [label].
Future<void> _pick(DashHarness h, String key, String label) async {
  await h.tester.ensureVisible(byKey(key));
  await h.tap(inKey(key, find.byType(DashSelectTrigger)));
  await h.tap(find.text(label).hitTestable().last);
}

String _trigger(WidgetTester tester, String key) => tester
    .widget<DashSelectTrigger>(inKey(key, find.byType(DashSelectTrigger)))
    .label;

void main() {
  group('header and states', () {
    testWidgets('SET-DLV-001 the pane header: "Delivery settings" and its '
        'description', (tester) async {
      final h = await pumpDelivery(tester, query: _helio);
      expect(inSettings(find.text('Delivery settings')), findsOneWidget);
      expect(
        inSettings(find.text(h.t('delivery.settingsSubtitle'))),
        findsOneWidget,
      );
    });

    testWidgets('SET-DLV-002 no branch picked: the pick-a-branch state, '
        'nothing read', (tester) async {
      final h = await pumpDelivery(tester);
      expect(
        inSettings(
          find.text(
            'Select a branch in the top bar to manage its delivery zones',
          ),
        ),
        findsOneWidget,
      );
      expect(h.server.callsTo(DeliveryRoutes.settings), isEmpty);
      expect(inSettings(byKey('dlv-save')), findsNothing);
    });

    testWidgets('SET-DLV-003 loading: four skeleton bars, then the form', (
      tester,
    ) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', DeliveryRoutes.settings);
      final h = await pumpDelivery(tester, query: _helio, backend: m);
      expect(inSettings(byKey('dlv-loading')), findsOneWidget);
      expect(
        inKey('dlv-loading', find.byType(DashSkeleton)),
        findsNWidgets(4),
      );
      expect(inSettings(byKey('dlv-save')), findsNothing);
      gate.release();
      await h.settle();
      expect(inSettings(byKey('dlv-loading')), findsNothing);
      expect(inSettings(byKey('dlv-save')), findsOneWidget);
    });

    testWidgets('SET-DLV-004 a failed read: the error state with the '
        'server\'s words; Retry asks again (spinning) and shows the form', (
      tester,
    ) async {
      final m = setupMockServer();
      final failure = MockResponse.error(500, 'Database unavailable');
      m.server.fail('GET', DeliveryRoutes.settings, failure);
      final h = await pumpDelivery(tester, query: _helio, backend: m);
      final error = inSettings(find.byType(DashErrorState));
      expect(error, findsOneWidget);
      expect(
        inSettings(find.text("Couldn't load this branch's delivery settings")),
        findsOneWidget,
      );
      expect(inSettings(find.text(h.refusalWords(failure))), findsOneWidget);
      final gate = m.server.hold('GET', DeliveryRoutes.settings);
      await h.tap(inSettings(find.text('Retry')));
      expect(tester.widget<DashErrorState>(error).retrying, isTrue);
      gate.release();
      await h.settle();
      expect(h.server.callsTo(DeliveryRoutes.settings), hasLength(2));
      expect(inSettings(byKey('dlv-save')), findsOneWidget);
    });

    testWidgets('SET-DLV-020 without delivery.settings.read: no Delivery '
        'entry in the rail; by URL the read\'s refusal is the error state', (
      tester,
    ) async {
      final h = await pumpDelivery(
        tester,
        query: atBranch(SeedIds.maadi),
        persona: Persona.limited,
      );
      expect(
        find.descendant(
          of: find.byType(SettingsShell),
          matching: find.text('Delivery'),
        ),
        findsNothing,
      );
      expect(
        inSettings(find.text("Couldn't load this branch's delivery settings")),
        findsOneWidget,
      );
      expect(
        inSettings(
          find.text(h.refusalWords(MockResponse.denied('delivery.settings.read'))),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-DLV-020 with the read: the Delivery entry shows in the '
        'rail and is the current pane', (tester) async {
      await pumpDelivery(tester, query: _helio);
      expect(
        find.descendant(
          of: find.byType(SettingsShell),
          matching: find.text('Delivery'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-DLV-020 a Dawam-only org meets the module gate; nothing '
        'read', (tester) async {
      final h = await pumpDelivery(tester, persona: Persona.dawamOnly);
      expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
      expect(h.server.callsTo(DeliveryRoutes.settings), isEmpty);
    });
  });

  group('the form', () {
    testWidgets('SET-DLV-005 filled from the server: fees in EGP, times on '
        'the 12-hour clock, empty times blank', (tester) async {
      await pumpDelivery(tester, query: _newCairo);
      expect(fieldText(tester, 'dlv-in-mall-fee'), '15');
      expect(fieldText(tester, 'dlv-in-mall-open'), '10:00 AM');
      expect(fieldText(tester, 'dlv-in-mall-close'), '10:00 PM');
      expect(fieldText(tester, 'dlv-distance'), '8,000');
      expect(fieldText(tester, 'dlv-prep'), '20');
      expect(fieldText(tester, 'dlv-pickup-fee'), '0');
    });

    testWidgets('SET-DLV-005 switching the header branch reloads the pane '
        'for that branch', (tester) async {
      final h = await pumpDelivery(tester, query: _newCairo);
      expect(fieldText(tester, 'dlv-prep'), '20');
      await h.go('$settingsPath$_zamalek');
      expect(fieldText(tester, 'dlv-prep'), '10');
      expect(
        h.server.callsTo(DeliveryRoutes.settings).last.query['branch_id'],
        [SeedIds.zamalek],
      );
    });

    testWidgets('SET-DLV-006 in-mall card: its words; the fields show only '
        'while it is on', (tester) async {
      final h = await pumpDelivery(tester, query: _helio);
      expect(inKey('dlv-card-in-mall', find.text('In-mall delivery')),
          findsOneWidget);
      expect(
        inKey('dlv-card-in-mall', find.text('Orders delivered within the mall.')),
        findsOneWidget,
      );
      expect(byKey('dlv-in-mall-fee'), findsNothing);
      await _toggle(h, 'dlv-in-mall');
      expect(byKey('dlv-in-mall-fee'), findsOneWidget);
      await _toggle(h, 'dlv-in-mall');
      expect(byKey('dlv-in-mall-fee'), findsNothing);
    });

    testWidgets('SET-DLV-007 in-mall fields: Opens, Closes, fee, discount '
        'and the Require GPS switch with its hint', (tester) async {
      final h = await pumpDelivery(tester, query: _newCairo);
      final card = 'dlv-card-in-mall';
      for (final w in [
        'Opens',
        'Closes',
        'In-mall fee (EGP)',
        'Discount',
        'Require GPS location',
        h.t('delivery.inMallRequireLocationHint'),
      ]) {
        expect(inKey(card, find.text(w)), findsOneWidget, reason: w);
      }
      expect(
        tester
            .widget<DashSwitch>(inKey('dlv-location', find.byType(DashSwitch)))
            .value,
        isTrue,
      );
    });

    testWidgets('SET-DLV-008 outside card: its words, Opens/Closes, the max '
        'road distance and a discount', (tester) async {
      await pumpDelivery(tester, query: _helio);
      const card = 'dlv-card-outside';
      for (final w in [
        'Outside delivery',
        'Road-distance delivery to customers outside the mall.',
        'Opens',
        'Closes',
        'Max road distance (meters)',
        'Discount',
      ]) {
        expect(inKey(card, find.text(w)), findsOneWidget, reason: w);
      }
      expect(fieldText(tester, 'dlv-distance'), '6,000');
      expect(fieldText(tester, 'dlv-outside-open'), '08:00 AM');
    });

    testWidgets('SET-DLV-009 umbrella card: off here; on, it asks hours, a '
        'fee and a discount', (tester) async {
      final h = await pumpDelivery(tester, query: _helio);
      const card = 'dlv-card-umbrella';
      expect(inKey(card, find.text('Umbrella delivery')), findsOneWidget);
      expect(
        inKey(
          card,
          find.text(
            'Delivered to a beach umbrella or sunbed number for a flat fee.',
          ),
        ),
        findsOneWidget,
      );
      expect(inKey(card, find.text('Opens')), findsNothing);
      await _toggle(h, 'dlv-umbrella');
      for (final w in ['Opens', 'Closes', 'Umbrella fee (EGP)', 'Discount']) {
        expect(inKey(card, find.text(w)), findsOneWidget, reason: w);
      }
    });

    testWidgets('SET-DLV-010 pickup card: its words, hours, the fee with '
        '"Leave at 0 for free pickup." and a discount', (tester) async {
      final h = await pumpDelivery(tester, query: _helio);
      const card = 'dlv-card-pickup';
      for (final w in [
        'Pickup',
        h.t('delivery.pickupHint'),
        'Opens',
        'Closes',
        'Pickup fee (EGP)',
        'Leave at 0 for free pickup.',
        'Discount',
      ]) {
        expect(inKey(card, find.text(w)), findsOneWidget, reason: w);
      }
    });

    testWidgets('SET-DLV-011 time fields: "930" and "9:30 pm" read on the '
        '12-hour clock and save as HH:MM:SS; cleared saves null', (
      tester,
    ) async {
      final h = await pumpDelivery(tester, query: _helio);
      await typeIn(h, 'dlv-outside-open', '930');
      expect(fieldText(tester, 'dlv-outside-open'), '09:30 AM');
      await typeIn(h, 'dlv-outside-close', '9:30 pm');
      expect(fieldText(tester, 'dlv-outside-close'), '09:30 PM');
      final clear = inKey(
        'dlv-pickup-open',
        find.bySemanticsLabel(h.t('inputs.clearTime')),
      );
      await tester.ensureVisible(clear);
      await h.tap(clear);
      expect(fieldText(tester, 'dlv-pickup-open'), '');
      await _save(h);
      final body = lastBody(h, 'PUT', DeliveryRoutes.settings);
      expect(body['outside_open_time'], '09:30:00');
      expect(body['outside_close_time'], '21:30:00');
      expect(body.containsKey('pickup_open_time'), isTrue);
      expect(body['pickup_open_time'], isNull);
      expect(body['pickup_close_time'], '23:30:00');
      await h.flushTimers();
    });

    testWidgets('SET-DLV-012 a negative fee: "Fee cannot be negative", '
        'nothing sent; an empty fee saves 0', (tester) async {
      final h = await pumpDelivery(tester, query: _newCairo);
      await typeIn(h, 'dlv-in-mall-fee', '-5');
      await _save(h);
      expect(
        inKey('dlv-card-in-mall', find.text('Fee cannot be negative')),
        findsOneWidget,
      );
      expect(countCalls(h, 'PUT', DeliveryRoutes.settings), 0);
      await typeIn(h, 'dlv-in-mall-fee', '');
      await _save(h);
      expect(lastBody(h, 'PUT', DeliveryRoutes.settings)['in_mall_fee'], 0);
      await h.flushTimers();
    });

    testWidgets('SET-DLV-012 fees in EGP go out in piastres, rounded', (
      tester,
    ) async {
      final h = await pumpDelivery(tester, query: _newCairo);
      await typeIn(h, 'dlv-in-mall-fee', '12.345');
      await _save(h);
      expect(lastBody(h, 'PUT', DeliveryRoutes.settings)['in_mall_fee'], 1235);
      await h.flushTimers();
    });

    testWidgets('SET-DLV-013 the distance: 0 is refused; an emptied one is '
        'refused too', (tester) async {
      final h = await pumpDelivery(tester, query: _helio);
      await typeIn(h, 'dlv-distance', '0');
      await _save(h);
      expect(
        inKey('dlv-card-outside', find.text('Distance must be greater than 0')),
        findsOneWidget,
      );
      await typeIn(h, 'dlv-distance', '');
      await _save(h);
      expect(
        inKey('dlv-card-outside', find.text('Distance must be greater than 0')),
        findsOneWidget,
      );
      expect(countCalls(h, 'PUT', DeliveryRoutes.settings), 0);
      await typeIn(h, 'dlv-distance', '4500');
      await _save(h);
      expect(
        lastBody(h, 'PUT', DeliveryRoutes.settings)['max_road_distance_meters'],
        4500,
      );
      await h.flushTimers();
    });

    testWidgets('SET-DLV-013 never set: the distance stays empty and saves '
        'null', (tester) async {
      final h = await pumpDelivery(tester, query: _zamalek);
      await _toggle(h, 'dlv-outside');
      expect(fieldText(tester, 'dlv-distance'), '');
      await _save(h);
      final body = lastBody(h, 'PUT', DeliveryRoutes.settings);
      expect(body.containsKey('max_road_distance_meters'), isTrue);
      expect(body['max_road_distance_meters'], isNull);
      expect(body['outside_enabled'], isTrue);
      await h.flushTimers();
    });

    testWidgets('SET-DLV-013 SET-DLV-022 (divergence) a wrong value inside a '
        'switched-off channel still blocks Save, and says why', (tester) async {
      final h = await pumpDelivery(tester, query: _helio);
      await typeIn(h, 'dlv-distance', '0');
      await _toggle(h, 'dlv-outside');
      await _save(h);
      expect(countCalls(h, 'PUT', DeliveryRoutes.settings), 0);
      await h.expectToast('Distance must be greater than 0');
    });

    testWidgets('SET-DLV-014 OTP: on by default here, its words; switched '
        'off it saves false', (tester) async {
      final h = await pumpDelivery(tester, query: _helio);
      expect(inKey('dlv-otp', find.text('Require OTP verification')),
          findsOneWidget);
      expect(inKey('dlv-otp', find.text(h.t('delivery.otpRequiredHint'))),
          findsOneWidget);
      expect(
        tester.widget<DashSwitch>(inKey('dlv-otp', find.byType(DashSwitch))).value,
        isTrue,
      );
      await _toggle(h, 'dlv-otp');
      await _save(h);
      expect(lastBody(h, 'PUT', DeliveryRoutes.settings)['otp_required'], false);
      await h.flushTimers();
    });

    testWidgets('SET-DLV-015 the discount select: "No discount", then every '
        'discount as name · value, with its hint; a pick is saved', (
      tester,
    ) async {
      final h = await pumpDelivery(tester, query: _helio);
      expect(
        inKey(
          'dlv-card-outside',
          find.text(h.t('delivery.channelDiscountHint')),
        ),
        findsOneWidget,
      );
      expect(_trigger(tester, 'dlv-outside-discount'), 'No discount');
      expect(
        h.server.callsTo(DeliveryRoutes.discounts).single.query['org_id'],
        [SeedIds.sabahOrg],
      );
      await h.tester.ensureVisible(byKey('dlv-outside-discount'));
      await h.tap(
        inKey('dlv-outside-discount', find.byType(DashSelectTrigger)),
      );
      for (final w in [
        'No discount',
        'Student Discount · 15%',
        'Loyalty Welcome · EGP 25.00',
        'Corporate: Vodafone · 13%',
      ]) {
        expect(find.text(w).hitTestable(), findsOneWidget, reason: w);
      }
      await h.tap(find.text('Student Discount · 15%').hitTestable());
      expect(_trigger(tester, 'dlv-outside-discount'), 'Student Discount · 15%');
      await _save(h);
      expect(
        lastBody(h, 'PUT', DeliveryRoutes.settings)['outside_discount_id'],
        DeliverySeed.discountId('student'),
      );
      await h.flushTimers();
    });

    testWidgets('SET-DLV-015 back to "No discount" saves null', (tester) async {
      final m = setupMockServer();
      _row(m.db, SeedIds.heliopolis)['pickup_discount_id'] =
          DeliverySeed.discountId('student');
      final h = await pumpDelivery(tester, query: _helio, backend: m);
      expect(_trigger(tester, 'dlv-pickup-discount'), 'Student Discount · 15%');
      await _pick(h, 'dlv-pickup-discount', 'No discount');
      await _save(h);
      final body = lastBody(h, 'PUT', DeliveryRoutes.settings);
      expect(body.containsKey('pickup_discount_id'), isTrue);
      expect(body['pickup_discount_id'], isNull);
      await h.flushTimers();
    });

    testWidgets('SET-DLV-015 SET-DLV-021 every channel off: the discounts '
        'still load once on mount, beside the settings', (tester) async {
      final m = setupMockServer();
      final row = _row(m.db, SeedIds.heliopolis);
      for (final c in ['in_mall', 'outside', 'umbrella', 'pickup']) {
        row['${c}_enabled'] = false;
      }
      final h = await pumpDelivery(tester, query: _helio, backend: m);
      expect(byKey('dlv-outside-discount'), findsNothing);
      expect(h.server.callsTo(DeliveryRoutes.discounts), hasLength(1));
      await h.flushTimers();
    });

    testWidgets('SET-DLV-015 Arabic: the discount\'s Arabic name, the money '
        'in Arabic', (tester) async {
      final h = await pumpDelivery(tester, query: _helio, locale: 'ar');
      await h.tester.ensureVisible(byKey('dlv-outside-discount'));
      await h.tap(
        inKey('dlv-outside-discount', find.byType(DashSelectTrigger)),
      );
      expect(find.text('خصم الطلاب · 15%').hitTestable(), findsOneWidget);
      final fmt = h.container.read(formatProvider);
      expect(
        find.text('ترحيب برنامج الولاء · ${fmt.fmtMoney(2500)}').hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('SET-DLV-016 prep time: its words; negative refused; saved '
        'as whole minutes', (tester) async {
      final h = await pumpDelivery(tester, query: _helio);
      expect(inSettings(find.text('Prep time (minutes)')), findsOneWidget);
      expect(
        inSettings(find.text('Added to the delivery ETA quoted to the customer.')),
        findsOneWidget,
      );
      await typeIn(h, 'dlv-prep', '-3');
      await _save(h);
      expect(inSettings(find.text('Prep time cannot be negative')),
          findsOneWidget);
      expect(countCalls(h, 'PUT', DeliveryRoutes.settings), 0);
      await typeIn(h, 'dlv-prep', '25');
      await _save(h);
      expect(lastBody(h, 'PUT', DeliveryRoutes.settings)['prep_time_minutes'],
          25);
      await h.flushTimers();
    });
  });

  group('saving', () {
    testWidgets('SET-DLV-017 Save sends every field (off channels too), '
        'toasts, and refetches /delivery/settings', (tester) async {
      final h = await pumpDelivery(tester, query: _helio);
      final seen = watchInvalidations(h);
      final reads = h.server.callsTo(DeliveryRoutes.settings).length;
      await _save(h);
      expect(lastBody(h, 'PUT', DeliveryRoutes.settings), {
        'branch_id': SeedIds.heliopolis,
        'in_mall_enabled': false,
        'outside_enabled': true,
        'umbrella_enabled': false,
        'pickup_enabled': true,
        'in_mall_open_time': null,
        'in_mall_close_time': null,
        'outside_open_time': '08:00:00',
        'outside_close_time': '23:00:00',
        'umbrella_open_time': null,
        'umbrella_close_time': null,
        'pickup_open_time': '07:30:00',
        'pickup_close_time': '23:30:00',
        'in_mall_fee': 0,
        'umbrella_fee': 0,
        'pickup_fee': 0,
        'prep_time_minutes': 15,
        'max_road_distance_meters': 6000,
        'in_mall_discount_id': null,
        'outside_discount_id': null,
        'umbrella_discount_id': null,
        'pickup_discount_id': null,
        'otp_required': true,
        'in_mall_require_location': true,
      });
      await h.expectToast('Branch delivery settings saved');
      expect(seen, [
        ['/delivery/settings'],
      ]);
      expect(h.server.callsTo(DeliveryRoutes.settings).length, reads + 2);
    });

    testWidgets('SET-DLV-017 Save shows its spinner while the request runs',
        (tester) async {
      final m = setupMockServer();
      final h = await pumpDelivery(tester, query: _helio, backend: m);
      final gate = m.server.hold('PUT', DeliveryRoutes.settings);
      await _save(h);
      expect(
        tester.widget<DashButton>(byKey('dlv-save')).loading,
        isTrue,
      );
      gate.release();
      await h.settle();
      expect(tester.widget<DashButton>(byKey('dlv-save')).loading, isFalse);
      await h.flushTimers();
    });

    testWidgets('SET-DLV-017 (divergence) the auto-reject minutes the form '
        'does not show are sent back, never cleared', (tester) async {
      final m = setupMockServer();
      _row(m.db, SeedIds.heliopolis)['auto_reject_minutes'] = 10;
      final h = await pumpDelivery(tester, query: _helio, backend: m);
      await _save(h);
      expect(
        lastBody(h, 'PUT', DeliveryRoutes.settings)['auto_reject_minutes'],
        10,
      );
      expect(_row(m.db, SeedIds.heliopolis)['auto_reject_minutes'], 10);
      await h.flushTimers();
    });

    testWidgets('SET-DLV-018 a refused save toasts the server\'s words; the '
        'form keeps what was typed', (tester) async {
      final m = setupMockServer();
      final h = await pumpDelivery(tester, query: _helio, backend: m);
      await typeIn(h, 'dlv-prep', '30');
      final denied = MockResponse.denied('delivery.settings.edit');
      m.server.fail('PUT', DeliveryRoutes.settings, denied);
      await _save(h);
      await h.expectToast(h.refusalWords(denied));
      expect(fieldText(tester, 'dlv-prep'), '30');
    });

    testWidgets('SET-DLV-018 the server\'s 400 (an inactive discount) is '
        'toasted in its words', (tester) async {
      final m = setupMockServer();
      _row(m.db, SeedIds.heliopolis)['outside_discount_id'] =
          DeliverySeed.discountId('opening-week');
      final h = await pumpDelivery(tester, query: _helio, backend: m);
      await _save(h);
      await h.expectToast(
        h.refusalWords(MockResponse.badRequest('Discount not found or inactive')),
      );
    });

    testWidgets('SET-DLV-019 phone (< 640): hours and fee/discount stack; '
        'wide they sit side by side', (tester) async {
      double dy(String key) => tester.getTopLeft(byKey(key)).dy;
      await pumpDelivery(tester, query: _newCairo);
      expect(dy('dlv-in-mall-open'), dy('dlv-in-mall-close'));
      expect(dy('dlv-in-mall-fee'), dy('dlv-in-mall-discount'));
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('SET-DLV-019 phone layout stacks the pairs', (tester) async {
      double dy(String key) => tester.getTopLeft(byKey(key)).dy;
      await pumpDelivery(tester, query: _newCairo, size: DashSize.phone);
      expect(dy('dlv-in-mall-close'), greaterThan(dy('dlv-in-mall-open')));
      expect(dy('dlv-in-mall-discount'), greaterThan(dy('dlv-in-mall-fee')));
    });

    testWidgets('SET-DLV-021 discounts still loading: only "No discount"; a '
        'saved discount not in the list shows empty and is sent back', (
      tester,
    ) async {
      final m = setupMockServer();
      final gone = mockUuid('discount:deleted');
      _row(m.db, SeedIds.heliopolis)['outside_discount_id'] = gone;
      final gate = m.server.hold('GET', DeliveryRoutes.discounts);
      final h = await pumpDelivery(tester, query: _helio, backend: m);
      expect(_trigger(tester, 'dlv-outside-discount'), '');
      await h.tester.ensureVisible(byKey('dlv-pickup-discount'));
      await h.tap(inKey('dlv-pickup-discount', find.byType(DashSelectTrigger)));
      expect(find.text('No discount').hitTestable(), findsWidgets);
      expect(find.text('Student Discount · 15%'), findsNothing);
      await h.tap(find.text('No discount').hitTestable().last);
      // The server refuses the unknown id; what matters is that it went out.
      await _save(h);
      expect(
        lastBody(h, 'PUT', DeliveryRoutes.settings)['outside_discount_id'],
        gone,
      );
      gate.release();
      await h.flushTimers();
    });

    testWidgets('SET-DLV-021 discounts failed: no error shown, only "No '
        'discount"', (tester) async {
      final m = setupMockServer();
      m.server.fail(
        'GET',
        DeliveryRoutes.discounts,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpDelivery(tester, query: _helio, backend: m);
      expect(inSettings(find.byType(DashErrorState)), findsNothing);
      await h.tester.ensureVisible(byKey('dlv-outside-discount'));
      await h.tap(
        inKey('dlv-outside-discount', find.byType(DashSelectTrigger)),
      );
      expect(find.text('Student Discount · 15%'), findsNothing);
      expect(find.text('No discount').hitTestable(), findsWidgets);
    });

    testWidgets('SET-DLV-022 a background refresh refills an untouched form; '
        'an edited one keeps the person\'s values', (tester) async {
      final m = setupMockServer();
      final h = await pumpDelivery(tester, query: _helio, backend: m);
      final bus = h.container.read(realtimeBusProvider);
      _row(m.db, SeedIds.heliopolis)['prep_time_minutes'] = 18;
      bus.invalidate(const ['/delivery/settings']);
      await h.settle();
      expect(fieldText(tester, 'dlv-prep'), '18');
      await typeIn(h, 'dlv-prep', '40');
      _row(m.db, SeedIds.heliopolis)['prep_time_minutes'] = 22;
      bus.invalidate(const ['/delivery/settings']);
      await h.settle();
      expect(fieldText(tester, 'dlv-prep'), '40');
    });

    testWidgets('SET-DLV-022 after a save the refetch resets the form to the '
        'server\'s values', (tester) async {
      final m = setupMockServer();
      final h = await pumpDelivery(tester, query: _helio, backend: m);
      await _toggle(h, 'dlv-in-mall');
      await typeIn(h, 'dlv-in-mall-fee', '7.5');
      await _save(h);
      await h.flushTimers();
      expect(fieldText(tester, 'dlv-in-mall-fee'), '7.5');
      expect(_row(m.db, SeedIds.heliopolis)['in_mall_fee'], 750);
      // Another device changes the row; the form follows again.
      _row(m.db, SeedIds.heliopolis)['in_mall_fee'] = 900;
      h.container.read(realtimeBusProvider).invalidate(const [
        '/delivery/settings',
      ]);
      await h.settle();
      expect(fieldText(tester, 'dlv-in-mall-fee'), '9');
    });
  });
}
