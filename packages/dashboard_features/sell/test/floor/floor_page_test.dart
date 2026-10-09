// Floor (SELL-FLR rows): one driven test per inventory row, the row id
// first in the name, through the real app shell on the mock server.
//
// Heliopolis at 10:00 (the seed's morning): T1 Nada Kamal's open bill, T2 an
// old bill marked ready, T3 and T6 held for bookings, T5 needs clearing, T9
// inactive; two parties in the transfer queue.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show DashAsyncState, orgIdProvider, transportProvider, webRetry;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:dashboard_sell/src/floor/floor_canvas.dart';
import 'package:dashboard_sell/src/floor/floor_inspector.dart';
import 'package:dashboard_sell/src/floor/floor_providers.dart';
import 'package:dashboard_sell/src/floor/floor_util.dart';
import 'package:dashboard_sell/src/floor/transfer_queue.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'floor_support.dart';

String _id(String label, [String branch = 'heliopolis']) =>
    SellIds.table(branch, label);

FloorViewport _vp(DashHarness h) =>
    h.tester.widget<FloorCanvas>(find.byType(FloorCanvas)).viewport;

/// Puts the camera at the origin, one pixel a unit: canvas pixels are
/// world units from here on.
Future<void> _origin(DashHarness h) async {
  _vp(h).jumpTo(const FloorView(x: 0, y: 0, zoom: 1));
  await h.settle(rounds: 2);
}

/// A world point as a global (screen) one.
Offset _at(DashHarness h, double x, double y) {
  final v = _vp(h).view;
  return h.tester.getTopLeft(find.byType(FloorCanvas)) +
      Offset((x - v.x) * v.zoom, (y - v.y) * v.zoom);
}

Future<void> _edit(DashHarness h) =>
    h.tap(find.byKey(const ValueKey('floor-lock')));

Future<void> _mouseTap(DashHarness h, Offset at) async {
  await h.tester.tapAt(at, kind: PointerDeviceKind.mouse);
  await h.settle(rounds: 3);
}

Future<void> _mouseDrag(
  DashHarness h,
  Offset from,
  Offset by, {
  int buttons = kPrimaryButton,
}) async {
  final g = await h.tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
    buttons: buttons,
  );
  await g.moveBy(by / 2);
  await g.moveBy(by / 2);
  await g.up();
  await h.settle(rounds: 3);
}

Future<void> _shiftTap(DashHarness h, Finder f) async {
  await h.tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await _mouseTap(h, h.tester.getCenter(f));
  await h.tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

Finder _inspector(Finder f) =>
    find.descendant(of: find.byType(FloorInspector), matching: f);

/// A plain text in the inspector (not the label field showing the same).
Finder _title(String s) =>
    _inspector(find.byWidgetPredicate((w) => w is Text && w.data == s));

/// [text] on the open dialog (the page behind shares words: "Cancel").
Future<void> _dialogTap(DashHarness h, String text) => h.tap(
  find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is DashSurface || w is DashConfirmDialog,
    ),
    matching: find.text(text),
  ),
);

Finder _queue(Finder f) =>
    find.descendant(of: find.byType(TransferQueue), matching: f);

String _semantics(String label) {
  final w = find
      .descendant(of: tableBox(label), matching: find.byType(Semantics))
      .evaluate()
      .map((e) => e.widget as Semantics)
      .firstWhere((s) => s.properties.label != null);
  return w.properties.label!;
}

Map<String, Object?> _body(MockCall c) =>
    (c.body! as Map).cast<String, Object?>();

/// The PUT /floor/layout row for [label].
Map<String, Object?> _saved(DashHarness h, String label) {
  final tables = _body(h.server.callsTo(layoutPath).last)['tables']! as List;
  return (tables.firstWhere((t) => (t as Map)['id'] == _id(label)) as Map)
      .cast();
}

void main() {
  group('header and reads', () {
    testWidgets('SELL-FLR-001 All branches: pick a branch, no reads', (
      tester,
    ) async {
      final h = await pumpFloor(tester, allBranches: true);
      expect(floorText('Floor'), findsOneWidget);
      expect(
        floorText('Select a branch in the top bar to see its floor'),
        findsOneWidget,
      );
      expect(h.server.callsTo(tablesPath), isEmpty);
      expect(h.server.callsTo(sectionsPath), isEmpty);
    });

    testWidgets('SELL-FLR-002 four reads by branch; open tickets best effort', (
      tester,
    ) async {
      final s = floorServer();
      s.server.fail(
        'GET',
        ticketsPath,
        MockResponse.denied('tickets.read'),
        times: null,
      );
      final h = await pumpFloor(tester, s: s);
      for (final p in [sectionsPath, tablesPath, transfersPath, ticketsPath]) {
        expect(h.server.callsTo(p).single.query['branch_id'], [
          SeedIds.heliopolis,
        ], reason: p);
      }
      // No names without the bills, and no retry; the floor still draws.
      expect(tester.widget<Tooltip>(tableBox('T1')).message, 'T1 · 4 seats');
      expect(find.byType(FloorCanvas), findsOneWidget);
    });

    testWidgets(
      'SELL-FLR-002/003/004/068/069 a 500 is retried once under the skeleton; '
      'open tickets are not retried',
      (tester) async {
        Future<int> asks(
          String path,
          FutureProvider<Object?> read, {
          required bool retried,
        }) async {
          final s = floorServer();
          s.server.fail(
            'GET',
            path,
            MockResponse.error(500, 'boom'),
            times: null,
          );
          final c = ProviderContainer(
            retry: webRetry,
            overrides: [
              transportProvider.overrideWithValue(s.server),
              orgIdProvider.overrideWithValue(SeedIds.sabahOrg),
            ],
          );
          final sub = c.listen(read, (_, _) {});
          await tester.pump(const Duration(milliseconds: 300));
          // Failed once: while the retry waits it is still the skeleton
          // (never the empty floor or the failure line).
          expect(sub.read().awaitingFirst, retried, reason: path);
          expect(sub.read().failedFirst, !retried, reason: path);
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(seconds: 1));
          }
          expect(sub.read().failedFirst, isTrue, reason: path);
          sub.close();
          c.dispose();
          return s.server.callsTo(path).length;
        }

        final b = SeedIds.heliopolis;
        expect(
          await asks(tablesPath, floorTablesProvider(b), retried: true),
          2,
        );
        expect(
          await asks(sectionsPath, floorSectionsProvider(b), retried: true),
          2,
        );
        expect(
          await asks(
            historyPath,
            floorTableHistoryProvider(_id('T1')),
            retried: true,
          ),
          2,
        );
        expect(
          await asks(ticketsPath, floorOpenTicketsProvider(b), retried: false),
          1,
        );
      },
    );

    testWidgets('SELL-FLR-003 a skeleton while tables or sections load', (
      tester,
    ) async {
      final s = floorServer();
      final gate = s.server.hold('GET', tablesPath);
      final h = await pumpFloor(tester, s: s);
      expect(inFloor(find.byType(DashSkeleton)), findsOneWidget);
      expect(find.byType(FloorCanvas), findsNothing);
      gate.release();
      await h.settle();
      expect(find.byType(FloorCanvas), findsOneWidget);
      await h.shot('floor/loading');
    });

    testWidgets(
      'SELL-FLR-004/088 failed reads stay silent: empty, never an error panel',
      (tester) async {
        final s = floorServer();
        for (final p in [
          tablesPath,
          sectionsPath,
          transfersPath,
          ticketsPath,
        ]) {
          s.server.fail('GET', p, MockResponse.error(500, 'boom'), times: null);
        }
        final h = await pumpFloor(tester, s: s);
        expect(
          floorText('No tables in this area yet. Unlock to add some.'),
          findsOneWidget,
        );
        expect(floorText('No one is waiting to move tables.'), findsOneWidget);
        expect(floorText('Main hall'), findsNothing);
        expect(floorText('All'), findsOneWidget);
        expect(inFloor(find.byType(DashErrorState)), findsNothing);
        await h.shot('floor/failed');
      },
    );

    testWidgets(
      'SELL-FLR-005/034/039 zoom buttons and keys step ×1.25 about the centre; Fit frames',
      (tester) async {
        final h = await pumpFloor(tester);
        final fitted = _vp(h).view;
        await h.tap(find.bySemanticsLabel('Zoom in'));
        expect(_vp(h).view.zoom, closeTo(fitted.zoom * 1.25, 1e-9));
        await h.tap(find.bySemanticsLabel('Zoom out'));
        expect(_vp(h).view.zoom, closeTo(fitted.zoom, 1e-9));
        expect(_vp(h).view.x, closeTo(fitted.x, 1e-6));
        await press(h, LogicalKeyboardKey.equal);
        await press(h, LogicalKeyboardKey.equal);
        expect(_vp(h).view.zoom, closeTo(fitted.zoom * 1.5625, 1e-9));
        await press(h, LogicalKeyboardKey.minus);
        expect(_vp(h).view.zoom, closeTo(fitted.zoom * 1.25, 1e-9));
        await press(h, LogicalKeyboardKey.digit0);
        expect(_vp(h).view, fitted);
        await h.tap(find.bySemanticsLabel('Zoom in'));
        await h.tap(find.bySemanticsLabel('Fit to room'));
        expect(_vp(h).view, fitted);
      },
    );

    testWidgets(
      'SELL-FLR-006/035 Locked ↔ Editing (button and ⌘E); starts Locked',
      (tester) async {
        final h = await pumpFloor(tester);
        expect(floorText('Locked'), findsOneWidget);
        expect(find.bySemanticsLabel('Undo'), findsNothing);
        await _edit(h);
        expect(floorText('Editing'), findsOneWidget);
        expect(find.bySemanticsLabel('Undo'), findsOneWidget);
        await pressMod(h, LogicalKeyboardKey.keyE);
        expect(floorText('Locked'), findsOneWidget);
        await pressMod(h, LogicalKeyboardKey.keyE);
        expect(floorText('Editing'), findsOneWidget);
      },
    );
  });

  group('area chips and sections', () {
    testWidgets(
      'SELL-FLR-007 All, the sections in order, Unassigned only when a table has none',
      (tester) async {
        final h = await pumpFloor(tester);
        final chips = ['All', 'Main hall', 'Terrace'];
        final xs = [
          for (final c in chips) tester.getCenter(floorText(c).first).dx,
        ];
        expect(xs, orderedEquals([...xs]..sort()));
        expect(floorText('Unassigned'), findsNothing);
        await h.tap(floorText('Terrace'));
        // The same plane, its active tables only (T9 is inactive).
        expect(tableBox('T7'), findsOneWidget);
        expect(tableBox('T8'), findsOneWidget);
        expect(tableBox('T9'), findsNothing);
        expect(tableBox('T1'), findsNothing);
        await h.tap(floorText('All'));
        expect(tableBox('T1'), findsOneWidget);
      },
    );

    testWidgets(
      'SELL-FLR-007 Zamalek has a table without an area: Unassigned',
      (tester) async {
        final h = await pumpFloor(tester, branchId: SeedIds.zamalek);
        await h.tap(floorText('Unassigned'));
        expect(tableBox('Bar 1', branch: 'zamalek'), findsOneWidget);
        expect(tableBox('T1', branch: 'zamalek'), findsNothing);
      },
    );

    testWidgets(
      'SELL-FLR-008 a chip change re-frames; a refetch does not fight panning',
      (tester) async {
        final h = await pumpFloor(tester);
        final all = _vp(h).view;
        await h.tap(floorText('Terrace'));
        final terrace = _vp(h).view;
        expect(terrace, isNot(all));
        _vp(h).panBy(50, 0);
        final panned = _vp(h).view;
        h.realtime.current!.emit('floor.layout_changed', data: '{}');
        await h.settle();
        expect(_vp(h).view, panned);
      },
    );

    testWidgets(
      'SELL-FLR-009/012/013/014 + Area: required name, created, made the active chip',
      (tester) async {
        final h = await pumpFloor(tester);
        expect(floorText('Area'), findsNothing);
        await _edit(h);
        await h.tap(floorText('Area'));
        expect(find.text('New section'), findsOneWidget);
        expect(find.text(h.t('floor.sectionHint')), findsOneWidget);
        await h.shot('floor/section-dialog');
        await h.tapText('Save');
        expect(find.text('This field is required'), findsOneWidget);
        expect(h.server.callsTo(sectionsPath, method: 'POST'), isEmpty);
        await h.enterText(
          find.byKey(const ValueKey('floor-section-name')),
          'Rooftop',
        );
        await h.tapText('Save');
        final post = h.server.callsTo(sectionsPath, method: 'POST').single;
        expect(_body(post), {
          'branch_id': SeedIds.heliopolis,
          'name': 'Rooftop',
          'ordering': 2,
        });
        await h.expectToast('Section created');
        expect(find.text('New section'), findsNothing);
        // The new area is the filter now: empty, ready for tables.
        expect(
          floorText('No tables here yet — add one to start the plan.'),
          findsOneWidget,
        );
        expect(h.server.callsTo(sectionsPath, method: 'GET'), hasLength(2));
      },
    );

    testWidgets(
      'SELL-FLR-010/015/090 the area menu: Rename keeps the create description',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        expect(find.bySemanticsLabel('Area actions'), findsNothing);
        await h.tap(floorText('Terrace'));
        await h.tap(find.bySemanticsLabel('Area actions'));
        await h.shot('floor/area-menu');
        await h.tapText('Rename');
        expect(find.text('Section settings'), findsOneWidget);
        expect(find.text(h.t('floor.sectionHint')), findsOneWidget);
        final field = find.byKey(const ValueKey('floor-section-name'));
        expect(
          find.descendant(of: field, matching: find.text('Terrace')),
          findsOneWidget,
        );
        await h.enterText(field, 'Garden terrace ');
        await h.tapText('Save');
        final patch = h.server
            .callsTo('/floor/sections/{id}', method: 'PATCH')
            .single;
        expect(
          patch.path,
          '/floor/sections/${SellIds.section('heliopolis', 'terrace')}',
        );
        expect(_body(patch), {'name': 'Garden terrace'});
        await h.expectToast('Section updated');
        expect(
          floorText('Garden terrace'),
          findsNWidgets(2),
        ); // the chip and the wish
      },
    );

    testWidgets(
      'SELL-FLR-015 an untouched name follows a refetch; a typed one stays',
      (tester) async {
        final s = floorServer();
        final h = await pumpFloor(tester, s: s);
        await _edit(h);
        await h.tap(floorText('Terrace'));
        await h.tap(find.bySemanticsLabel('Area actions'));
        await h.tapText('Rename');
        final field = find.byKey(const ValueKey('floor-section-name'));
        final row = s.db[SellTables.floorSections].find(
          SellIds.section('heliopolis', 'terrace'),
        )!;
        row['name'] = 'Roof terrace';
        h.realtime.current!.emit('floor.layout_changed', data: '{}');
        await h.settle();
        expect(
          find.descendant(of: field, matching: find.text('Roof terrace')),
          findsOneWidget,
        );
        await h.enterText(field, 'Patio');
        row['name'] = 'Upstairs';
        h.realtime.current!.emit('floor.layout_changed', data: '{}');
        await h.settle();
        expect(
          find.descendant(of: field, matching: find.text('Patio')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'SELL-FLR-011/089 delete an area: its tables (inactive too) move to Unassigned',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(floorText('Terrace'));
        await h.tap(find.bySemanticsLabel('Area actions'));
        await h.tapText('Delete');
        expect(find.text('Delete “Terrace”?'), findsOneWidget);
        expect(
          find.text(
            'Its 3 table(s) move to Unassigned — nothing is deleted and no order is affected.',
          ),
          findsOneWidget,
        );
        await h.shot('floor/delete-area');
        await h.tap(
          find.descendant(
            of: find.byType(DashConfirmDialog),
            matching: find.text('Delete'),
          ),
        );
        expect(
          h.server
              .callsTo('/floor/sections/{id}', method: 'DELETE')
              .single
              .path,
          '/floor/sections/${SellIds.section('heliopolis', 'terrace')}',
        );
        // Back to All; the moved tables now make an Unassigned chip.
        expect(floorText('Terrace'), findsNothing);
        expect(floorText('Unassigned'), findsOneWidget);
        expect(tableBox('T1'), findsOneWidget);
      },
    );

    testWidgets('SELL-FLR-011 an empty area says it holds no tables', (
      tester,
    ) async {
      final s = floorServer();
      s.db[SellTables.floorSections].insert({
        'id': 'rooftop',
        'org_id': SeedIds.sabahOrg,
        'branch_id': SeedIds.heliopolis,
        'name': 'Rooftop',
        'ordering': 2,
        'canvas_w': 1000,
        'canvas_h': 700,
      });
      final h = await pumpFloor(tester, s: s);
      await _edit(h);
      await h.tap(floorText('Rooftop'));
      await h.tap(find.bySemanticsLabel('Area actions'));
      await h.tapText('Delete');
      expect(
        find.text('The area is removed. It holds no tables.'),
        findsOneWidget,
      );
      await _dialogTap(h, 'Cancel');
      expect(
        h.server.callsTo('/floor/sections/{id}', method: 'DELETE'),
        isEmpty,
      );
    });

    testWidgets(
      'SELL-FLR-089 Unassigned appears for an inactive table alone, and opens empty',
      (tester) async {
        final s = floorServer();
        s.db[SellTables.floorTables].find(_id('T9'))!['section_id'] = null;
        final h = await pumpFloor(tester, s: s);
        await h.tap(floorText('Unassigned'));
        expect(
          floorText('No tables in this area yet. Unlock to add some.'),
          findsOneWidget,
        );
      },
    );
  });

  group('toolbar and add table', () {
    testWidgets(
      'SELL-FLR-016/017 the edit toolbar, its enablement and the hint',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        bool on(String label) =>
            tester
                .widget<DashIconButton>(
                  find.byWidgetPredicate(
                    (w) => w is DashIconButton && w.semanticLabel == label,
                  ),
                )
                .onPressed !=
            null;
        for (final l in [
          'Undo',
          'Redo',
          'Align horizontal centres',
          'Align vertical centres',
          'Space evenly across',
          'Copy',
          'Delete',
        ]) {
          expect(on(l), isFalse, reason: l);
        }
        await h.tap(tableBox('T1'));
        expect(on('Copy'), isTrue);
        expect(on('Delete'), isTrue);
        expect(on('Undo'), isTrue); // SELL-FLR-087: a press is a gesture
        expect(on('Align horizontal centres'), isFalse);
        await _shiftTap(h, tableBox('T2'));
        expect(on('Align vertical centres'), isTrue);
        expect(on('Space evenly across'), isFalse);
        await _shiftTap(h, tableBox('T4'));
        expect(on('Space evenly across'), isTrue);
        // The app's fonts lack ⌥ and ⌘: the keys by name.
        expect(
          floorText(
            'Drag to move · Alt ignores the grid · Ctrl/Cmd+C/V · pinch to zoom',
          ),
          findsOneWidget,
        );
        await h.shot('floor/toolbar');
      },
    );

    testWidgets(
      'SELL-FLR-018/019/020/021/022/023 add a table: defaults, checks, placement',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(floorText('Main hall'));
        await h.tap(inFloor(find.text('Add table')).first);
        expect(find.text('New table'), findsOneWidget);
        expect(
          find.text('Tables seat parties and back dine-in tickets.'),
          findsOneWidget,
        );
        final label = find.byKey(const ValueKey('floor-add-label'));
        final seats = find.byKey(const ValueKey('floor-add-seats'));
        expect(
          find.descendant(of: label, matching: find.text('T10')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: seats, matching: find.text('2')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('floor-add-shape')),
            matching: find.text('Rectangle'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('floor-add-section')),
            matching: find.text('Main hall'),
          ),
          findsOneWidget,
        );
        await h.shot('floor/add-table');
        await h.enterText(label, '');
        await h.enterText(seats, '120');
        await h.tap(
          find.descendant(
            of: find.byType(DashSurface),
            matching: find.text('Add table'),
          ),
        );
        expect(find.text('This field is required'), findsOneWidget);
        expect(
          find.text('Seats must be a whole number from 0 to 99'),
          findsOneWidget,
        );
        expect(h.server.callsTo(tablesPath, method: 'POST'), isEmpty);
        await h.shot('floor/add-table-errors');
        await h.enterText(label, ' T10 ');
        await h.enterText(seats, '6');
        await h.tap(find.byKey(const ValueKey('floor-add-shape')));
        await h.tapText('Circle');
        await h.tap(
          find.descendant(
            of: find.byType(DashSurface),
            matching: find.text('Add table'),
          ),
        );
        // Beside Main hall's six: leftmost 40 + (6 % 5) × 30; lowest bottom 270 + 20.
        expect(_body(h.server.callsTo(tablesPath, method: 'POST').single), {
          'branch_id': SeedIds.heliopolis,
          'label': 'T10',
          'seats': 6,
          'shape': 'circle',
          'section_id': SellIds.section('heliopolis', 'main'),
          'pos_x': 70.0,
          'pos_y': 290.0,
          'width': 90.0,
          'height': 90.0,
          'rotation': 0.0,
        });
        await h.expectToast('Table created');
        expect(find.byType(FloorCanvas), findsOneWidget);
        expect(h.server.callsTo(tablesPath, method: 'GET'), hasLength(2));
      },
    );

    testWidgets(
      'SELL-FLR-022/023 No section under All: the first table lands at the origin',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(inFloor(find.text('Add table')).first);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('floor-add-section')),
            matching: find.text('No section'),
          ),
          findsOneWidget,
        );
        await h.tap(
          find.descendant(
            of: find.byType(DashSurface),
            matching: find.text('Add table'),
          ),
        );
        final body = _body(h.server.callsTo(tablesPath, method: 'POST').single);
        expect(
          (body['section_id'], body['pos_x'], body['pos_y'], body['seats']),
          (null, 0.0, 0.0, 2),
        );
        expect(body.containsKey('section_id'), isTrue);
        await h.flushTimers();
      },
    );

    testWidgets(
      'SELL-FLR-090 a blank-looking label passes the form; the server refuses it',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(inFloor(find.text('Add table')).first);
        await h.enterText(find.byKey(const ValueKey('floor-add-label')), '   ');
        await h.tap(
          find.descendant(
            of: find.byType(DashSurface),
            matching: find.text('Add table'),
          ),
        );
        await h.expectToast(
          shownFor(h, MockResponse.badRequest('Table label is required')),
        );
        expect(find.text('New table'), findsOneWidget); // stays open
        await _dialogTap(h, 'Cancel');
        expect(find.text('New table'), findsNothing);
      },
    );
  });

  group('canvas', () {
    testWidgets(
      'SELL-FLR-024/025/027 the map, each table named with its state',
      (tester) async {
        final h = await pumpFloor(tester);
        final handle = tester.ensureSemantics();
        expect(find.bySemanticsLabel('Floor map'), findsOneWidget);
        handle.dispose();
        final t1 = tester.widget<Tooltip>(tableBox('T1')).message!;
        expect(t1, startsWith('T1 · 4 seats · T-'));
        final farida = h.db![SellTables.bookings].rows.firstWhere(
          (b) =>
              (b['table_ids']! as List).contains(_id('T3')) &&
              b['status'] == 'confirmed',
        )['guest_name'];
        expect(
          tester.widget<Tooltip>(tableBox('T3')).message,
          'T3 · 2 seats · $farida · 09:45 AM',
        );
        expect(tester.widget<Tooltip>(tableBox('T4')).message, 'T4 · 2 seats');
        expect(_semantics('T1'), endsWith('· Seated'));
        expect(_semantics('T3'), endsWith('· Reserved'));
        expect(_semantics('T5'), 'T5 · 6 seats · Needs clearing');
        expect(_semantics('T4'), 'T4 · 2 seats · Available');
      },
    );

    testWidgets(
      'SELL-FLR-026 tone: an open bill, a parked order, a cleared table',
      (tester) async {
        final h = await pumpFloor(tester, branchId: SeedIds.zamalek);
        String z(String l) => find
            .descendant(
              of: tableBox(l, branch: 'zamalek'),
              matching: find.byType(Semantics),
            )
            .evaluate()
            .map((e) => (e.widget as Semantics).properties.label)
            .firstWhere((l) => l != null)!;
        expect(z('T1'), endsWith('· Seated')); // a waiter's bill
        expect(z('T3'), endsWith('· Seated')); // parked on a till: no name
        expect(z('T3'), isNot(contains('T-')));
        expect(z('T4'), endsWith('· Needs clearing'));
        expect(z('T2'), endsWith('· Available'));
        await h.shot('floor/zamalek');
      },
    );

    testWidgets(
      'SELL-FLR-028 locked: a drag anywhere pans, a tap selects nothing',
      (tester) async {
        final h = await pumpFloor(tester);
        await h.tap(tableBox('T1'));
        expect(_inspector(find.text(h.t('floor.lockedHint'))), findsOneWidget);
        final before = _vp(h).view;
        await _mouseDrag(
          h,
          tester.getCenter(tableBox('T1')),
          const Offset(60, 30),
        );
        final after = _vp(h).view;
        expect(after.x, closeTo(before.x - 60 / before.zoom, 1e-6));
        expect(after.y, closeTo(before.y - 30 / before.zoom, 1e-6));
        expect(h.server.callsTo(layoutPath), isEmpty);
      },
    );

    testWidgets(
      'SELL-FLR-029 select: a tap, ⇧ toggles, a press keeps the group, empty floor clears, a marquee',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await _origin(h);
        await h.tap(tableBox('T1'));
        expect(_title('T1'), findsOneWidget);
        await _shiftTap(h, tableBox('T2'));
        expect(_inspector(find.text('2 tables')), findsOneWidget);
        await _mouseTap(h, tester.getCenter(tableBox('T1')));
        expect(_inspector(find.text('2 tables')), findsOneWidget);
        await _shiftTap(h, tableBox('T2'));
        expect(_title('T1'), findsOneWidget);
        await _mouseTap(h, _at(h, 700, 400));
        expect(_inspector(find.text(h.t('floor.selectHint'))), findsOneWidget);
        // From empty floor up-left of T1 to inside T4: touches T1, T2, T4, T5.
        await _mouseDrag(h, _at(h, 10, 10), const Offset(250, 210));
        expect(_inspector(find.text('4 tables')), findsOneWidget);
        expect(_inspector(find.text('16 seats')), findsOneWidget);
        await h.shot('floor/multi-select');
      },
    );

    testWidgets(
      'SELL-FLR-030/048/049/050 a drag moves the selection on the grid, then saves once',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await _origin(h);
        await h.tap(tableBox('T1'));
        await _shiftTap(h, tableBox('T2'));
        await _mouseDrag(
          h,
          tester.getCenter(tableBox('T1')),
          const Offset(33, 18),
        );
        expect(_inspector(find.text('2 tables')), findsOneWidget);
        expect(floorText('Saving…'), findsOneWidget);
        expect(h.server.callsTo(layoutPath), isEmpty);
        await letSave(h);
        final put = h.server.callsTo(layoutPath).single;
        expect(_body(put)['branch_id'], SeedIds.heliopolis);
        final t1 = _saved(h, 'T1');
        final t2Row = h.db![SellTables.floorTables].find(_id('T2'))!;
        expect(t1['pos_x'], 70.0);
        expect(t1['pos_y'], 60.0);
        expect(t1['section_id'], SellIds.section('heliopolis', 'main'));
        expect(t1['expected_updated_at'], isNotNull);
        expect(_saved(h, 'T2')['pos_x'], 250.0);
        expect(t2Row['pos_x'], 250.0);
        expect(floorText('Saved'), findsOneWidget);
        expect(
          h.server.callsTo(tablesPath, method: 'GET').length,
          greaterThan(1),
        );
        // A second save carries the token the first one returned.
        await h.tap(tableBox('T1'));
        await press(h, LogicalKeyboardKey.arrowRight);
        await letSave(h);
        expect(
          _saved(h, 'T1')['expected_updated_at'],
          h.db!.clock.now.toUtc().toIso8601String(),
        );
      },
    );

    testWidgets('SELL-FLR-030 ⌥ ignores the grid; a middle drag pans instead', (
      tester,
    ) async {
      final h = await pumpFloor(tester);
      await _edit(h);
      await _origin(h);
      await h.tap(tableBox('T1'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await _mouseDrag(
        h,
        tester.getCenter(tableBox('T1')),
        const Offset(33, 18),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(_inspector(find.text('73, 58 · 120×80')), findsOneWidget);
      await _mouseDrag(
        h,
        _at(h, 700, 400),
        const Offset(-40, 0),
        buttons: kMiddleMouseButton,
      );
      expect(_vp(h).view.x, closeTo(40, 1e-6));
      await letSave(h);
    });

    testWidgets(
      'SELL-FLR-031 an empty area: locked words; editing words and Add table',
      (tester) async {
        final s = floorServer();
        s.db[SellTables.floorSections].insert({
          'id': 'rooftop',
          'org_id': SeedIds.sabahOrg,
          'branch_id': SeedIds.heliopolis,
          'name': 'Rooftop',
          'ordering': 2,
          'canvas_w': 1000,
          'canvas_h': 700,
        });
        final h = await pumpFloor(tester, s: s);
        await h.tap(floorText('Rooftop'));
        expect(
          floorText('No tables in this area yet. Unlock to add some.'),
          findsOneWidget,
        );
        await h.shot('floor/empty-area');
        await _edit(h);
        expect(
          floorText('No tables here yet — add one to start the plan.'),
          findsOneWidget,
        );
        await h.tap(inFloor(find.widgetWithText(DashButton, 'Add table')).last);
        expect(find.text('New table'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('floor-add-section')),
            matching: find.text('Rooftop'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'SELL-FLR-032 one selected table: corners resize, the opposite corner pinned, min 24',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await _origin(h);
        await h.tap(tableBox('T1')); // 40, 40 · 120×80
        await _mouseDrag(
          h,
          _at(h, 160, 120),
          const Offset(37, 24),
        ); // SE corner
        expect(_inspector(find.text('40, 40 · 160×100')), findsOneWidget);
        await _mouseDrag(
          h,
          _at(h, 40, 40),
          const Offset(30, 40),
        ); // NW; SE stays
        expect(_inspector(find.text('70, 80 · 130×60')), findsOneWidget);
        await _mouseDrag(h, _at(h, 70, 80), const Offset(125, 55));
        expect(_inspector(find.text('176, 116 · 24×24')), findsOneWidget);
        await letSave(h);
        expect(
          (_saved(h, 'T1')['width'], _saved(h, 'T1')['height']),
          (24.0, 24.0),
        );
        await h.shot('floor/handles');
      },
    );

    testWidgets(
      'SELL-FLR-032 the arm above the table rotates in 15° steps; none on a group',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await _origin(h);
        await h.tap(tableBox('T4')); // 40, 180 · 90×90: the knob 28 px above
        await _mouseDrag(h, _at(h, 85, 152), const Offset(80, 71));
        expect(_inspector(find.text('90°')), findsOneWidget);
        await letSave(h);
        expect(_saved(h, 'T4')['rotation'], 90.0);
        // Two selected: no handles, so the same press is empty floor.
        await _shiftTap(h, tableBox('T1'));
        await _mouseDrag(h, _at(h, 85, 152), const Offset(80, 71));
        expect(_inspector(find.text(h.t('floor.selectHint'))), findsNothing);
      },
    );

    testWidgets(
      'SELL-FLR-033 ⌘ + wheel zooms about the cursor; a plain scroll pans; two fingers pinch',
      (tester) async {
        final h = await pumpFloor(tester);
        await _origin(h);
        final p = _at(h, 100, 100);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: p,
            scrollDelta: const Offset(0, -50),
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await h.settle(rounds: 2);
        final z = _vp(h).view;
        expect(z.zoom, greaterThan(1));
        expect(
          (100 - z.x) * z.zoom,
          closeTo(100, 1e-6),
        ); // the cursor's point held
        await _origin(h);
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: p,
            scrollDelta: const Offset(20, 30),
            kind: PointerDeviceKind.mouse,
          ),
        );
        await h.settle(rounds: 2);
        expect((_vp(h).view.x, _vp(h).view.y, _vp(h).view.zoom), (20, 30, 1));
        await _origin(h);
        final a = await tester.startGesture(_at(h, 300, 200), pointer: 7);
        final b = await tester.startGesture(_at(h, 400, 200), pointer: 8);
        await b.moveBy(const Offset(100, 0));
        await a.up();
        await b.up();
        await h.settle(rounds: 2);
        expect(_vp(h).view.zoom, closeTo(2, 1e-9));
      },
    );

    testWidgets('SELL-FLR-055/056 the legend and the capacity', (tester) async {
      final h = await pumpFloor(tester);
      for (final w in ['Available', 'Reserved', 'Seated', 'Needs clearing']) {
        expect(floorText(w), findsOneWidget, reason: w);
      }
      // 26 seats on the 8 active tables; T1 and T2 taken (8); T5 to clear.
      expect(
        floorText('18 of 26 seats free · 1 need clearing'),
        findsOneWidget,
      );
      await h.tap(floorText('Terrace'));
      expect(floorText('4 of 4 seats free'), findsOneWidget);
    });

    testWidgets(
      'SELL-FLR-079 a hold begins by the clock, re-read every minute',
      (tester) async {
        final s = floorServer();
        s.db.clock.set(DateTime.utc(2026, 10, 8, 6, 10)); // 09:10 Cairo
        final h = await pumpFloor(tester, s: s);
        expect(_semantics('T3'), endsWith('· 09:45 AM · Available'));
        s.db.clock.set(DateTime.utc(2026, 10, 8, 6, 16));
        await tester.pump(const Duration(minutes: 1));
        await h.settle(rounds: 2);
        expect(_semantics('T3'), endsWith('· 09:45 AM · Reserved'));
      },
    );

    testWidgets(
      'SELL-FLR-080 live: floor and ticket events refresh their reads',
      (tester) async {
        final h = await pumpFloor(tester);
        final tables = h.server.callsTo(tablesPath).length;
        final tickets = h.server.callsTo(ticketsPath).length;
        h.realtime.current!.emit('table.cleared', data: '{}');
        await h.settle();
        expect(h.server.callsTo(tablesPath).length, tables + 1);
        h.realtime.current!.emit('ticket.opened', data: '{}');
        await h.settle();
        expect(h.server.callsTo(ticketsPath).length, tickets + 1);
        expect(h.server.callsTo(tablesPath).length, tables + 2);
        h.realtime.current!.emit('transfer.requested', data: '{}');
        await h.settle();
        expect(h.server.callsTo(transfersPath).length, greaterThan(1));
      },
    );
  });

  group('keyboard and clipboard', () {
    testWidgets(
      'SELL-FLR-036/041/054 arrows nudge (⇧ by 1); ⌘Z, ⌘⇧Z, ⌘Y; each step saved',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(tableBox('T1'));
        await press(h, LogicalKeyboardKey.arrowRight);
        await press(h, LogicalKeyboardKey.arrowDown);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await press(h, LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(_inspector(find.text('49, 50 · 120×80')), findsOneWidget);
        await letSave(h);
        expect(h.server.callsTo(layoutPath), hasLength(1));
        await pressMod(h, LogicalKeyboardKey.keyZ);
        expect(_inspector(find.text('50, 50 · 120×80')), findsOneWidget);
        await pressMod(h, LogicalKeyboardKey.keyZ);
        await pressMod(h, LogicalKeyboardKey.keyZ);
        expect(_inspector(find.text('40, 40 · 120×80')), findsOneWidget);
        await letSave(h);
        expect(_saved(h, 'T1')['pos_x'], 40.0);
        await pressMod(h, LogicalKeyboardKey.keyZ, shift: true);
        expect(_inspector(find.text('50, 40 · 120×80')), findsOneWidget);
        await pressMod(h, LogicalKeyboardKey.keyY);
        expect(_inspector(find.text('50, 50 · 120×80')), findsOneWidget);
        await h.tap(find.bySemanticsLabel('Undo'));
        expect(_inspector(find.text('50, 40 · 120×80')), findsOneWidget);
        await h.tap(find.bySemanticsLabel('Redo'));
        expect(_inspector(find.text('50, 50 · 120×80')), findsOneWidget);
        await letSave(h);
        expect(_saved(h, 'T1')['pos_y'], 50.0);
      },
    );

    testWidgets(
      'SELL-FLR-037/044/045 ⌘C copies the blueprint; ⌘V pastes unique labels in the view centre',
      (tester) async {
        final clip = FakeClipboard(tester);
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(floorText('Main hall'));
        await _origin(h);
        await h.tap(tableBox('T1'));
        await _shiftTap(h, tableBox('T2'));
        await pressMod(h, LogicalKeyboardKey.keyC);
        await h.expectToast('2 copied');
        final payload = jsonDecode(clip.text!) as Map;
        expect(payload['kind'], 'madar.floor.tables.v1');
        expect((payload['tables'] as List).map((t) => (t as Map)['label']), [
          'T1',
          'T2',
        ]);
        await pressMod(h, LogicalKeyboardKey.keyV);
        final posts = h.server.callsTo(tablesPath, method: 'POST');
        expect(posts.map((c) => _body(c)['label']), ['T1 (2)', 'T2 (2)']);
        final size = tester.getSize(find.byType(FloorCanvas));
        final ox = snapTo(size.width / 2, true);
        final oy = snapTo(size.height / 2, true);
        expect(_body(posts.first)['pos_x'], ox + 20);
        expect(_body(posts.first)['pos_y'], oy + 20);
        expect(_body(posts.last)['pos_x'], ox + 180 + 20);
        expect(
          _body(posts.first)['section_id'],
          SellIds.section('heliopolis', 'main'),
        );
        // The pasted tables are the selection.
        expect(_inspector(find.text('2 tables')), findsOneWidget);
        // Locked: ⌘V does nothing; a stray paste is ignored silently.
        clip.text = 'hello';
        await pressMod(h, LogicalKeyboardKey.keyV);
        expect(h.server.callsTo(tablesPath, method: 'POST'), hasLength(2));
        await pressMod(h, LogicalKeyboardKey.keyE);
        clip.text = jsonEncode(payload);
        await pressMod(h, LogicalKeyboardKey.keyV);
        expect(h.server.callsTo(tablesPath, method: 'POST'), hasLength(2));
      },
    );

    testWidgets(
      'SELL-FLR-045 zoomed in, a paste still lands in the centre of the view',
      (tester) async {
        FakeClipboard(tester);
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(floorText('Main hall'));
        _vp(h).jumpTo(const FloorView(x: 0, y: 0, zoom: 2));
        await h.settle(rounds: 2);
        await h.tap(tableBox('T1'));
        await pressMod(h, LogicalKeyboardKey.keyC);
        await h.expectToast('1 copied');
        await pressMod(h, LogicalKeyboardKey.keyV);
        final post = h.server.callsTo(tablesPath, method: 'POST').single;
        final size = tester.getSize(find.byType(FloorCanvas));
        // Canvas units: half the view's screen size over the zoom (the web
        // adds the screen pixels themselves).
        expect(_body(post)['pos_x'], snapTo(size.width / 2 / 2, true) + 20);
        expect(_body(post)['pos_y'], snapTo(size.height / 2 / 2, true) + 20);
      },
    );

    testWidgets('SELL-FLR-044/045 a refused clipboard says so', (tester) async {
      final clip = FakeClipboard(tester)..refuse = true;
      final h = await pumpFloor(tester);
      await _edit(h);
      await h.tap(tableBox('T1'));
      await h.tap(find.bySemanticsLabel('Copy'));
      await h.expectToast('Could not use the clipboard');
      await pressMod(h, LogicalKeyboardKey.keyV);
      await h.expectToast('Could not use the clipboard');
      expect(clip.text, isNull);
    });

    testWidgets(
      'SELL-FLR-038/040 ⌘A selects every visible table; Escape clears',
      (tester) async {
        final h = await pumpFloor(tester);
        await pressMod(h, LogicalKeyboardKey.keyA);
        expect(_inspector(find.text('8 tables')), findsOneWidget);
        expect(_inspector(find.text('26 seats')), findsOneWidget);
        expect(_inspector(find.text(h.t('floor.multiHint'))), findsOneWidget);
        await press(h, LogicalKeyboardKey.escape);
        expect(_inspector(find.text(h.t('floor.lockedHint'))), findsOneWidget);
      },
    );

    testWidgets(
      'SELL-FLR-042/047 Delete asks, then removes each selected table',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(tableBox('T4'));
        await _shiftTap(h, tableBox('T3'));
        await press(h, LogicalKeyboardKey.delete);
        expect(find.text('Delete 2 table(s)?'), findsOneWidget);
        expect(find.text(h.t('floor.deleteBody')), findsOneWidget);
        await h.shot('floor/delete-tables');
        await h.tap(
          find.descendant(
            of: find.byType(DashConfirmDialog),
            matching: find.text('Delete'),
          ),
        );
        expect(
          h.server
              .callsTo('/floor/tables/{id}', method: 'DELETE')
              .map((c) => c.path),
          ['/floor/tables/${_id('T3')}', '/floor/tables/${_id('T4')}'],
        );
        expect(tableBox('T4'), findsNothing);
        expect(tableBox('T3'), findsNothing);
        expect(_inspector(find.text(h.t('floor.selectHint'))), findsOneWidget);
      },
    );

    testWidgets(
      'SELL-FLR-047 a table with a live bill refuses; those before it stay deleted',
      (tester) async {
        final h = await pumpFloor(tester, branchId: SeedIds.zamalek);
        await _edit(h);
        await h.tap(tableBox('Bar 1', branch: 'zamalek'));
        await _shiftTap(h, tableBox('T1', branch: 'zamalek'));
        await h.tap(find.bySemanticsLabel('Delete'));
        await h.tap(
          find.descendant(
            of: find.byType(DashConfirmDialog),
            matching: find.text('Delete'),
          ),
        );
        await h.expectToast(
          shownFor(
            h,
            MockResponse.conflict(
              'Cannot delete a table with a live open ticket — settle or move it first.',
            ),
          ),
        );
        expect(tableBox('Bar 1', branch: 'zamalek'), findsNothing);
        expect(tableBox('T1', branch: 'zamalek'), findsOneWidget);
      },
    );

    testWidgets('SELL-FLR-043 shortcuts never fire while typing', (
      tester,
    ) async {
      final h = await pumpFloor(tester);
      await _edit(h);
      await h.tap(tableBox('T1'));
      final field = find.byKey(ValueKey('floor-label-${_id('T1')}'));
      await h.tap(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      await press(h, LogicalKeyboardKey.arrowLeft);
      await press(h, LogicalKeyboardKey.backspace);
      await pressMod(h, LogicalKeyboardKey.keyA);
      expect(_inspector(find.text('40, 40 · 120×80')), findsOneWidget);
      expect(find.text('Delete 1 table(s)?'), findsNothing);
      expect(_inspector(find.text('8 tables')), findsNothing);
    });

    testWidgets(
      'SELL-FLR-046 align centres and space evenly: one step each, saved',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(tableBox('T1'));
        await _shiftTap(h, tableBox('T4')); // 40,40 120×80 and 40,180 90×90
        await h.tap(find.bySemanticsLabel('Align horizontal centres'));
        await letSave(h);
        final moved =
            _body(h.server.callsTo(layoutPath).single)['tables']! as List;
        expect(moved, hasLength(2));
        await h.tap(find.bySemanticsLabel('Undo'));
        await letSave(h);
        expect(_saved(h, 'T1')['pos_x'], 40.0);
        await pressMod(h, LogicalKeyboardKey.keyA);
        await h.tap(find.bySemanticsLabel('Align vertical centres'));
        await h.tap(find.bySemanticsLabel('Space evenly across'));
        await letSave(h);
        expect(h.server.callsTo(layoutPath), hasLength(3));
      },
    );
  });

  group('autosave failures', () {
    testWidgets(
      'SELL-FLR-051 someone else moved it: 409, Reload drops the edits',
      (tester) async {
        final s = floorServer();
        final h = await pumpFloor(tester, s: s);
        await _edit(h);
        await h.tap(tableBox('T1'));
        s.db[SellTables.floorTables].find(_id('T1'))!['updated_at'] =
            '2026-10-08T06:59:00.000Z';
        await press(h, LogicalKeyboardKey.arrowRight);
        await letSave(h);
        expect(h.server.callsTo(layoutPath).single.status, 409);
        expect(
          find.text(
            shownFor(
              h,
              MockResponse.conflict(
                'The layout changed while you were editing: T1. Nothing was saved. Reload the floor to pick up the current positions, then reapply your changes.',
              ),
            ),
          ),
          findsOneWidget,
        );
        expect(floorText('Not saved'), findsOneWidget);
        expect(_inspector(find.text('50, 40 · 120×80')), findsOneWidget);
        await h.shot('floor/conflict');
        await h.tapText('Reload');
        expect(floorText('Not saved'), findsNothing);
        expect(_inspector(find.text('40, 40 · 120×80')), findsOneWidget);
        // The next save guards with the token the re-read brought.
        await press(h, LogicalKeyboardKey.arrowDown);
        await letSave(h);
        expect(h.server.callsTo(layoutPath).last.status, 200);
        await tester.pump(const Duration(seconds: 13));
        await h.settle(rounds: 2);
      },
    );

    testWidgets(
      'SELL-FLR-052/083 a refused save (no floor.layout.edit): the permission words, Not saved, kept for later',
      (tester) async {
        final s = floorServer();
        s.server.fail(
          'PUT',
          layoutPath,
          MockResponse.denied('floor.layout.edit'),
          times: null,
        );
        final h = await pumpFloor(tester, branchId: SeedIds.zamalek, s: s);
        await _edit(h);
        await h.tap(tableBox('T2', branch: 'zamalek'));
        await press(h, LogicalKeyboardKey.arrowRight);
        await letSave(h);
        expect(h.server.callsTo(layoutPath).single.status, 403);
        expect(floorText('Not saved'), findsOneWidget);
        await h.expectToast(deniedWords(h));
        await press(h, LogicalKeyboardKey.arrowRight);
        await letSave(h);
        final retried =
            _body(h.server.callsTo(layoutPath).last)['tables']! as List;
        expect(retried, hasLength(1));
        await h.flushTimers();
      },
    );

    testWidgets(
      'SELL-FLR-053 (divergence) leaving the page saves the pending edit',
      (tester) async {
        final h = await pumpFloor(tester);
        h.allowUnmatched = true;
        await _edit(h);
        await h.tap(tableBox('T1'));
        await press(h, LogicalKeyboardKey.arrowDown);
        expect(h.server.callsTo(layoutPath), isEmpty);
        await h.go('/orders');
        await h.settle();
        expect(
          _body(h.server.callsTo(layoutPath).single)['tables'],
          hasLength(1),
        );
      },
    );

    testWidgets(
      'SELL-FLR-087 (divergence) undoing a press that moved nothing never sticks on Saving…',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(tableBox('T1'));
        await h.tap(find.bySemanticsLabel('Undo'));
        expect(floorText('Saving…'), findsOneWidget);
        await letSave(h);
        expect(floorText('Saving…'), findsNothing);
        expect(h.server.callsTo(layoutPath), isEmpty);
      },
    );

    testWidgets(
      'SELL-FLR-085 locked: ⌘Z still undoes and saves, the indicator hidden; ⌘C copies',
      (tester) async {
        final clip = FakeClipboard(tester);
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(tableBox('T1'));
        await press(h, LogicalKeyboardKey.arrowRight);
        await letSave(h);
        await pressMod(h, LogicalKeyboardKey.keyE); // Locked
        await pressMod(h, LogicalKeyboardKey.keyZ);
        expect(floorText('Saving…'), findsNothing);
        await letSave(h);
        expect(h.server.callsTo(layoutPath), hasLength(2));
        expect(_saved(h, 'T1')['pos_x'], 40.0);
        await press(h, LogicalKeyboardKey.arrowRight); // no nudge while locked
        await letSave(h);
        expect(h.server.callsTo(layoutPath), hasLength(2));
        await pressMod(h, LogicalKeyboardKey.keyC);
        await h.expectToast('1 copied');
        expect(clip.text, contains('"T1"'));
      },
    );
  });

  group('inspector', () {
    testWidgets(
      'SELL-FLR-057/058/063/064 hints, the header, geometry and area',
      (tester) async {
        final h = await pumpFloor(tester);
        expect(_inspector(find.text(h.t('floor.lockedHint'))), findsOneWidget);
        await _edit(h);
        expect(_inspector(find.text(h.t('floor.selectHint'))), findsOneWidget);
        await h.tap(tableBox('T5'));
        expect(_title('T5'), findsOneWidget);
        expect(_inspector(find.text('6 seats')), findsOneWidget);
        expect(_inspector(find.text('220, 180 · 160×90')), findsOneWidget);
        expect(_inspector(find.text('Main hall')), findsOneWidget);
        await _shiftTap(h, tableBox('T4'));
        expect(_inspector(find.text('2 tables')), findsOneWidget);
        expect(_inspector(find.text('8 seats')), findsOneWidget);
        expect(_inspector(find.text(h.t('floor.multiHint'))), findsOneWidget);
        expect(_inspector(find.text('—')), findsOneWidget);
      },
    );

    testWidgets('SELL-FLR-063 a table without an area reads Unassigned', (
      tester,
    ) async {
      final h = await pumpFloor(tester, branchId: SeedIds.zamalek);
      await _edit(h);
      await h.tap(tableBox('Bar 1', branch: 'zamalek'));
      expect(_inspector(find.text('Unassigned')), findsOneWidget);
    });

    testWidgets(
      'SELL-FLR-059/062 the label commits on Enter, trimmed; a blank one is not sent',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(tableBox('T4'));
        final field = find.byKey(ValueKey('floor-label-${_id('T4')}'));
        await h.enterText(field, '   ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await h.settle();
        expect(
          h.server.callsTo('/floor/tables/{id}', method: 'PATCH'),
          isEmpty,
        );
        await h.enterText(field, ' Window 4 ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await h.settle();
        final patch = h.server
            .callsTo('/floor/tables/{id}', method: 'PATCH')
            .single;
        expect(patch.path, '/floor/tables/${_id('T4')}');
        expect(_body(patch), {'label': 'Window 4'});
        expect(_title('Window 4'), findsOneWidget);
        expect(h.server.callsTo(tablesPath, method: 'GET'), hasLength(2));
      },
    );

    testWidgets(
      'SELL-FLR-060 seats commit when a whole 0–99; anything else stays, unsent',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(tableBox('T4'));
        final field = find.byKey(ValueKey('floor-seats-${_id('T4')}'));
        await h.enterText(field, '120');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await h.settle();
        expect(
          h.server.callsTo('/floor/tables/{id}', method: 'PATCH'),
          isEmpty,
        );
        expect(
          find.descendant(of: field, matching: find.text('120')),
          findsOneWidget,
        );
        await h.enterText(field, '3');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await h.settle();
        expect(
          _body(h.server.callsTo('/floor/tables/{id}', method: 'PATCH').single),
          {'seats': 3},
        );
        expect(_inspector(find.text('3 seats')), findsOneWidget);
      },
    );

    testWidgets(
      'SELL-FLR-059/048 a renamed table can then be moved: the save carries '
      "the PATCH's token",
      (tester) async {
        final s = floorServer();
        final h = await pumpFloor(tester, s: s);
        await _edit(h);
        await h.tap(tableBox('T4'));
        final later = s.db.clock.now.add(const Duration(minutes: 5));
        s.db.clock.set(later);
        final field = find.byKey(ValueKey('floor-label-${_id('T4')}'));
        await h.enterText(field, 'Window 4');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await h.settle();
        expect(
          h.server.callsTo('/floor/tables/{id}', method: 'PATCH').single.status,
          200,
        );
        await press(h, LogicalKeyboardKey.arrowRight);
        await letSave(h);
        final save = h.server.callsTo(layoutPath).single;
        expect(save.status, 200);
        expect(
          DateTime.parse(
            _saved(h, 'T4')['expected_updated_at']! as String,
          ).isAtSameMomentAs(later),
          isTrue,
        );
        expect(floorText('Not saved'), findsNothing);
        await tester.pump(const Duration(seconds: 13));
        await h.settle(rounds: 2);
      },
    );

    testWidgets('SELL-FLR-059/060 a failed save is sent again from the field', (
      tester,
    ) async {
      final s = floorServer();
      s.server.fail(
        'PATCH',
        '/floor/tables/{id}',
        MockResponse.error(500, 'boom'),
        times: 1,
      );
      final h = await pumpFloor(tester, s: s);
      await _edit(h);
      await h.tap(tableBox('T4'));
      final field = find.byKey(ValueKey('floor-label-${_id('T4')}'));
      await h.enterText(field, 'Window 4');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      List<MockCall> patches() =>
          h.server.callsTo('/floor/tables/{id}', method: 'PATCH');
      expect(patches().single.status, 500);
      await h.flushTimers();
      await tester.showKeyboard(field);
      await h.settle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(patches(), hasLength(2));
      expect(patches().last.status, 200);
      expect(_body(patches().last), {'label': 'Window 4'});
      expect(_title('Window 4'), findsOneWidget);
    });

    testWidgets('SELL-FLR-061 shape: the other one patches', (tester) async {
      final h = await pumpFloor(tester);
      await _edit(h);
      await h.tap(tableBox('T1'));
      await h.tap(_inspector(find.text('Rectangle')));
      expect(h.server.callsTo('/floor/tables/{id}', method: 'PATCH'), isEmpty);
      await h.tap(_inspector(find.text('Circle')));
      expect(
        _body(h.server.callsTo('/floor/tables/{id}', method: 'PATCH').single),
        {'shape': 'circle'},
      );
    });

    testWidgets(
      'SELL-FLR-062/083 a refused patch toasts the permission words',
      (tester) async {
        final s = floorServer();
        s.server.fail(
          'PATCH',
          '/floor/tables/{id}',
          MockResponse.denied('floor.layout.edit'),
          times: null,
        );
        final h = await pumpFloor(tester, branchId: SeedIds.zamalek, s: s);
        await _edit(h);
        await h.tap(tableBox('T2', branch: 'zamalek'));
        await h.tap(_inspector(find.text('Circle')));
        await h.expectToast(deniedWords(h));
      },
    );

    testWidgets(
      'SELL-FLR-065 rotate ±15° every selected table: one step, saved',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(tableBox('T4'));
        expect(_inspector(find.text('0°')), findsOneWidget);
        await h.tap(find.bySemanticsLabel('Rotate +15°'));
        await h.tap(find.bySemanticsLabel('Rotate +15°'));
        expect(_inspector(find.text('30°')), findsOneWidget);
        await h.tap(find.bySemanticsLabel('Rotate -15°'));
        expect(_inspector(find.text('15°')), findsOneWidget);
        await letSave(h);
        expect(_saved(h, 'T4')['rotation'], 15.0);
      },
    );

    testWidgets(
      'SELL-FLR-084 locked again: the inspector stays; shape and rotation lock, the label still saves',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(tableBox('T4'));
        await pressMod(h, LogicalKeyboardKey.keyE);
        expect(_title('T4'), findsOneWidget);
        await h.tap(_inspector(find.text('Circle')));
        await h.tap(find.bySemanticsLabel('Rotate +15°'));
        expect(
          h.server.callsTo('/floor/tables/{id}', method: 'PATCH'),
          isEmpty,
        );
        expect(_inspector(find.text('0°')), findsOneWidget);
        await h.enterText(
          find.byKey(ValueKey('floor-label-${_id('T4')}')),
          'Corner',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await h.settle();
        expect(
          _body(h.server.callsTo('/floor/tables/{id}', method: 'PATCH').single),
          {'label': 'Corner'},
        );
        await h.shot('floor/locked-inspector');
      },
    );

    testWidgets('SELL-FLR-066/073 sitting now opens the customer, read-only', (
      tester,
    ) async {
      final h = await pumpFloor(tester);
      h.allowUnmatched = true;
      await _edit(h);
      await h.tap(tableBox('T1'));
      expect(_inspector(find.text('Sitting now')), findsOneWidget);
      await h.tap(_inspector(find.text('Nada Kamal')).first);
      expect(h.server.callsTo('/customers/{id}'), isNotEmpty);
    });

    testWidgets(
      'SELL-FLR-066/067/072/073 a resting pointer warms the history and the '
      'customer; the press asks nothing more',
      (tester) async {
        final h = await pumpFloor(tester);
        h.allowUnmatched = true;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        // Locked, a press selects nothing: nothing is warmed.
        await mouse.moveTo(tester.getCenter(tableBox('T1')));
        await h.settle();
        expect(h.server.callsTo(historyPath), isEmpty);
        await mouse.moveTo(Offset.zero);
        await _edit(h);
        await mouse.moveTo(tester.getCenter(tableBox('T1')));
        await h.settle();
        expect(
          h.server.callsTo(historyPath).single.path,
          '/floor/tables/${_id('T1')}/history',
        );
        await h.tap(tableBox('T1'));
        expect(h.server.callsTo(historyPath), hasLength(1));

        final name = _inspector(find.text('Nada Kamal')).first;
        expect(h.server.callsTo('/customers/{id}'), isEmpty);
        await mouse.moveTo(tester.getCenter(name));
        await h.settle();
        expect(h.server.callsTo('/customers/{id}'), hasLength(1));
        await h.tap(name);
        expect(h.server.callsTo('/customers/{id}'), hasLength(1));
      },
    );

    testWidgets(
      'SELL-FLR-066 no customer on the bill: no Sitting now; without customers.view a plain name',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(tableBox('T2'));
        expect(_inspector(find.text('Sitting now')), findsNothing);
      },
    );

    testWidgets(
      'SELL-FLR-067/071/072 the last 30 days: figures, then the bills',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await h.tap(tableBox('T1'));
        final call = h.server.callsTo(historyPath).single;
        expect(call.path, '/floor/tables/${_id('T1')}/history');
        expect(call.query, isEmpty);
        final data = (await tester.runAsync(
          () => DashboardApi(h.server).floor.tableHistory(id: _id('T1')),
        ))!;
        expect(_inspector(find.text('Last 30 days')), findsOneWidget);
        // The seeded T1 month, as the web shows it (not the mock's own
        // answer run through the formatter).
        for (final figure in ['EGP 16,215.00', 'EGP 261.53', '1h 01m', '2.1']) {
          expect(_inspector(find.text(figure)), findsOneWidget, reason: figure);
        }
        expect(_inspector(find.text('Bills')), findsOneWidget);
        // The live bill: Nada, 28m · 3 covers, Still open.
        expect(_inspector(find.text('28m · 3 covers')), findsOneWidget);
        expect(_inspector(find.text('Still open')), findsOneWidget);
        final voided = data.sittings.where((s) => s.status == 'voided').length;
        expect(_inspector(find.text('Voided')), findsNWidgets(voided));
        await h.shot('floor/history');
      },
    );

    testWidgets('SELL-FLR-068/069 loading, then the failure line (no retry)', (
      tester,
    ) async {
      final s = floorServer();
      final gate = s.server.hold('GET', historyPath);
      final h = await pumpFloor(tester, s: s);
      await _edit(h);
      await h.tap(tableBox('T4'));
      expect(_inspector(find.byType(DashSkeleton)), findsNWidgets(2));
      await h.shot('floor/history-loading');
      gate.release();
      await h.settle();
      expect(_inspector(find.byType(DashSkeleton)), findsNothing);
      s.server.clearFailures();
      s.server.fail(
        'GET',
        historyPath,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      await h.tap(tableBox('T6'));
      expect(
        _inspector(find.text("Couldn't load this table's history.")),
        findsOneWidget,
      );
      expect(_inspector(find.text('Retry')), findsNothing);
    });

    testWidgets(
      'SELL-FLR-070/083 nothing sat here; without tickets.read the failure line',
      (tester) async {
        final s = floorServer();
        s.server.fail(
          'GET',
          historyPath,
          MockResponse.ok(
            TableHistory(
              tableId: _id('T4'),
              label: 'T4',
              from: DateTime.utc(2026, 9, 8, 7),
              to: DateTime.utc(2026, 10, 8, 7),
              sittings: const [],
              covers: 0,
              settledCount: 0,
              totalMinor: 0,
              averageBillMinor: 0,
              averageMinutes: 0,
              turnsPerDayX100: 0,
            ),
          ),
          times: 1,
        );
        final h = await pumpFloor(tester, s: s);
        await _edit(h);
        await h.tap(tableBox('T4'));
        expect(
          _inspector(find.text('Nothing has sat here in the last 30 days.')),
          findsOneWidget,
        );
        s.server.fail(
          'GET',
          historyPath,
          MockResponse.denied('tickets.read'),
          times: null,
        );
        await h.tap(tableBox('T6'));
        expect(
          _inspector(find.text("Couldn't load this table's history.")),
          findsOneWidget,
        );
      },
    );
  });

  group('transfer queue', () {
    testWidgets('SELL-FLR-074/075 the waiting parties, oldest first', (
      tester,
    ) async {
      await pumpFloor(tester);
      expect(_queue(find.text('Transfer queue')), findsOneWidget);
      expect(_queue(find.text('2')), findsOneWidget);
      final unnamed = tester.getTopLeft(_queue(find.text('Unnamed'))).dy;
      final nada = tester.getTopLeft(_queue(find.text('Nada Kamal'))).dy;
      expect(unnamed, lessThan(nada));
      expect(_queue(find.text('Terrace')), findsOneWidget);
      expect(_queue(find.text('T5')), findsOneWidget);
      expect(_queue(find.text('12m')), findsOneWidget);
      expect(_queue(find.text('5m')), findsOneWidget);
      expect(
        _queue(
          find.text('They would like to sit outside now that it is cooler.'),
        ),
        findsOneWidget,
      );
      expect(_queue(find.bySemanticsLabel('Open ticket')), findsNWidgets(2));
      expect(_queue(find.text('Fulfill')), findsNWidgets(2));
    });

    testWidgets('SELL-FLR-074 nobody waiting', (tester) async {
      final h = await pumpFloor(tester, branchId: SeedIds.maadi);
      expect(
        _queue(find.text('No one is waiting to move tables.')),
        findsOneWidget,
      );
      expect(_queue(find.byType(DashBadge)), findsNothing);
      await h.shot('floor/maadi');
    });

    testWidgets(
      'SELL-FLR-076 cancel asks, then cancels and re-reads floor and bills',
      (tester) async {
        final h = await pumpFloor(tester);
        await h.tap(_queue(find.text('Cancel')).last);
        expect(find.text('Cancel this transfer request?'), findsOneWidget);
        expect(
          find.text('Nada Kamal stays at their current table.'),
          findsOneWidget,
        );
        await h.shot('floor/cancel-transfer');
        await h.tapText('Keep waiting');
        expect(h.server.callsTo('/floor/transfers/{id}/cancel'), isEmpty);
        final tickets = h.server.callsTo(ticketsPath).length;
        await h.tap(_queue(find.text('Cancel')).first);
        expect(
          find.text('The party stays at their current table.'),
          findsOneWidget,
        );
        await h.tapText('Cancel request');
        expect(
          h.server.callsTo('/floor/transfers/{id}/cancel').single.path,
          '/floor/transfers/${SellIds.transfer('heliopolis', 1)}/cancel',
        );
        await h.expectToast('Transfer cancelled');
        expect(_queue(find.text('Unnamed')), findsNothing);
        expect(h.server.callsTo(ticketsPath).length, tickets + 1);
      },
    );

    testWidgets(
      'SELL-FLR-077/078/091 fulfil: free tables matching the wish, then Move here',
      (tester) async {
        final h = await pumpFloor(tester);
        // Nada wants T5, which needs clearing: nothing to offer.
        await h.tap(_queue(find.text('Fulfill')).last);
        expect(find.text('Move Nada Kamal'), findsOneWidget);
        expect(find.text(h.t('floor.noMatchingTables')), findsOneWidget);
        await _dialogTap(h, 'Cancel');
        // The unnamed party wants the Terrace: T7 and T8 (T9 is inactive).
        await h.tap(_queue(find.text('Fulfill')).first);
        expect(find.text('Move The party'), findsOneWidget);
        expect(
          find.text('Pick a free table that matches the request.'),
          findsOneWidget,
        );
        final dialog = find.byType(FulfillDialog);
        expect(
          find.descendant(of: dialog, matching: find.text('2 seats · Terrace')),
          findsNWidgets(2),
        );
        expect(
          find.descendant(of: dialog, matching: find.text('T9')),
          findsNothing,
        );
        await h.tapText('Move here');
        expect(h.server.callsTo('/floor/transfers/{id}/fulfill'), isEmpty);
        await h.tap(find.descendant(of: dialog, matching: find.text('T7')));
        await h.shot('floor/fulfill');
        await h.tapText('Move here');
        final post = h.server.callsTo('/floor/transfers/{id}/fulfill').single;
        expect(_body(post), {'table_id': _id('T7')});
        await h.expectToast('Party moved');
        expect(find.byType(FulfillDialog), findsNothing);
        expect(_semantics('T7'), contains('· Seated'));
      },
    );

    testWidgets(
      'SELL-FLR-078/083 without floor.transfers.edit: the permission words, the dialog stays',
      (tester) async {
        final s = floorServer(persona: Persona.manager);
        for (final p in [
          '/floor/transfers/{id}/fulfill',
          '/floor/transfers/{id}/cancel',
        ]) {
          s.server.fail(
            'POST',
            p,
            MockResponse.denied('floor.transfers.edit'),
            times: null,
          );
        }
        // Zamalek's manager: their own floor, every transfer action offered.
        final h = await pumpFloor(
          tester,
          persona: Persona.manager,
          branchId: SeedIds.zamalek,
          s: s,
        );
        await h.tap(_queue(find.text('Fulfill')));
        await h.tap(
          find.descendant(
            of: find.byType(FulfillDialog),
            matching: find.text('T2'),
          ),
        );
        await h.tapText('Move here');
        await h.expectToast(deniedWords(h));
        expect(find.byType(FulfillDialog), findsOneWidget);
        await _dialogTap(h, 'Cancel');
        await h.tap(_queue(find.text('Cancel')));
        await h.tapText('Cancel request');
        await h.expectToast(deniedWords(h));
      },
    );
  });

  group('layout, direction and refusals', () {
    testWidgets('SELL-FLR-081 desktop docks the 320 panel beside the canvas', (
      tester,
    ) async {
      await pumpFloor(tester);
      expect(
        tester.getTopLeft(find.byType(FloorInspector)).dx,
        greaterThanOrEqualTo(tester.getTopRight(find.byType(FloorCanvas)).dx),
      );
      // 320 with its start border.
      expect(tester.getSize(find.byType(FloorInspector)).width, 319);
    });

    testWidgets('SELL-FLR-081 a phone stacks the panel under the canvas', (
      tester,
    ) async {
      await pumpFloor(tester, size: DashSize.phone);
      expect(
        tester.getTopLeft(find.byType(FloorInspector)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(FloorCanvas)).dy),
      );
    });

    testWidgets(
      'SELL-FLR-082 Arabic: the room is never mirrored; the arrow is',
      (tester) async {
        final h = await pumpFloor(tester, locale: 'ar');
        expect(
          tester.getCenter(tableBox('T1')).dx,
          lessThan(tester.getCenter(tableBox('T2')).dx),
        );
        expect(
          tester.getCenter(tableBox('T1')).dx,
          lessThan(tester.getCenter(tableBox('T7')).dx),
        );
        final arrows = _queue(
          find.byType(DashIcon),
        ).evaluate().map((e) => (e.widget as DashIcon).name);
        expect(arrows, contains('arrow-left'));
        expect(arrows, isNot(contains('arrow-right')));
        // The chips read from the right.
        expect(
          tester.getCenter(floorText(h.t('floor.allAreas'))).dx,
          greaterThan(tester.getCenter(floorText('Main hall')).dx),
        );
      },
    );

    testWidgets(
      'SELL-FLR-083 without the floor caps the page still opens, empty, and says nothing more',
      (tester) async {
        final h = await pumpFloor(
          tester,
          persona: Persona.limited,
          branchId: SeedIds.maadi,
        );
        expect(
          floorText('No tables in this area yet. Unlock to add some.'),
          findsOneWidget,
        );
        expect(floorText('No one is waiting to move tables.'), findsOneWidget);
        expect(inFloor(find.byType(DashErrorState)), findsNothing);
        // The edit controls are offered; the server refuses each write.
        await _edit(h);
        await h.tap(inFloor(find.widgetWithText(DashButton, 'Add table')).last);
        await h.tap(
          find.descendant(
            of: find.byType(DashSurface),
            matching: find.text('Add table'),
          ),
        );
        await h.expectToast(deniedWords(h));
      },
    );

    testWidgets(
      'SELL-FLR-086 another area keeps the selection; commands act on what is visible',
      (tester) async {
        final h = await pumpFloor(tester);
        await _edit(h);
        await pressMod(h, LogicalKeyboardKey.keyA);
        await h.tap(floorText('Terrace'));
        expect(_inspector(find.text('2 tables')), findsOneWidget);
        await h.tap(find.bySemanticsLabel('Align horizontal centres'));
        await letSave(h);
        final ids = [
          for (final t
              in _body(h.server.callsTo(layoutPath).single)['tables']! as List)
            (t as Map)['id'],
        ];
        expect(ids.toSet().difference({_id('T7'), _id('T8')}), isEmpty);
        // One visible of a two-table selection: Align is on, and does nothing.
        await press(h, LogicalKeyboardKey.escape);
        await h.tap(floorText('All'));
        await h.tap(tableBox('T1'));
        await _shiftTap(h, tableBox('T7'));
        await h.tap(floorText('Main hall'));
        expect(_title('T1'), findsOneWidget);
        await h.tap(find.bySemanticsLabel('Align horizontal centres'));
        await letSave(h);
        expect(h.server.callsTo(layoutPath), hasLength(1));
      },
    );
  });
}
