// Renders the floor screen to PNG so its chrome can be LOOKED at.
//
// The floor is the screen a waiter stands in front of all shift, and it is the
// one that gets judged on how it looks. There is no simulator here, so this
// paints it into a file: `MADAR_RENDER=true` writes `build/render/floor-*.png`.
// Without the flag it still builds the screen at two sizes and fails on any
// layout exception, which is what CI needs from it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/tables_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

FloorTableStateView _table({
  required String id,
  required String label,
  required double x,
  required double y,
  String status = 'free',
  int seats = 4,
  String shape = 'rect',
}) => FloorTableStateView(
  id: id,
  sectionId: 'sec-in',
  label: label,
  seats: seats,
  shape: shape,
  status: status,
  posX: x,
  posY: y,
  width: 90,
  height: 90,
  rotation: 0,
  heldLockedByOther: false,
);

/// A room with something in every state, so one picture shows the whole
/// vocabulary: free, seated, needs-clearing.
final _layout = FloorLayoutView(
  sections: const [
    FloorSectionInfo(
      id: 'sec-in',
      name: 'Inside',
      ordering: 0,
      canvasW: 900,
      canvasH: 620,
    ),
  ],
  tables: [
    _table(id: 't1', label: 'T1', x: 40, y: 40),
    _table(id: 't2', label: 'T2', x: 200, y: 40, status: 'seated'),
    _table(id: 't3', label: 'T3', x: 360, y: 40, status: 'dirty'),
    _table(id: 't4', label: 'T4', x: 520, y: 40, seats: 2, shape: 'circle'),
    _table(id: 't5', label: 'T5', x: 40, y: 210, status: 'seated', seats: 6),
    _table(id: 't6', label: 'T6', x: 200, y: 210),
    _table(id: 't7', label: 'T7', x: 360, y: 210, seats: 2, shape: 'circle'),
    _table(id: 't8', label: 'T8', x: 520, y: 210, status: 'dirty'),
  ],
);

class _FakeBridge implements MadarBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #tr) {
      // Real words, so the picture shows what a person would read.
      const words = {
        'tables.title': 'Floor',
        'tables.seated': 'seated',
        'tables.free': 'free',
        'tables.needs_clearing': 'to clear',
        'tables.held_res': 'held',
        'tables.arrivals': 'Arrivals',
        'tables.waitlist': 'Waitlist',
        'tables.view_list': 'List',
        'tables.view_plan': 'Plan',
        'tables.all': 'All',
      };
      final key = invocation.namedArguments[#key] as String? ?? '';
      return words[key] ?? key.split('.').last.replaceAll('_', ' ');
    }
    if (name == #floorLayout) return Future<FloorLayoutView>.value(_layout);
    if (name == #refreshFloor) return Future<void>.value();
    if (name == #listTransferQueue) {
      return Future<List<TransferQueueView>>.value(const []);
    }
    if (name == #listArrivals) return Future<List<BookingView>>.value(const []);
    if (name == #refreshArrivals) return Future<void>.value();
    if (name == #listDrafts) return Future<List<DraftView>>.value(const []);
    if (name == #cartLines) return Future<List<CartLineView>>.value(const []);
    if (name == #currentSession) return null;
    if (name == #clockSkewMinutes) return 0;
    return null;
  }
}

Future<void> _shoot(
  WidgetTester tester,
  Size size,
  ThemeData theme,
  String name,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(_FakeBridge())],
        child: MaterialApp(
          theme: theme,
          home: const TablesScreen(isHome: true),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');

  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('build/render')..createSync(recursive: true);
  File(
    '${dir.path}/floor-$name.png',
  ).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('the floor on a tablet', (tester) async {
    await _shoot(tester, const Size(1180, 820), MadarTheme.light(), 'tablet');
  });

  testWidgets('the floor on a phone', (tester) async {
    await _shoot(tester, const Size(390, 844), MadarTheme.light(), 'phone');
  });

  testWidgets('the floor in the dark', (tester) async {
    await _shoot(tester, const Size(1180, 820), MadarTheme.dark(), 'dark');
  });
}
