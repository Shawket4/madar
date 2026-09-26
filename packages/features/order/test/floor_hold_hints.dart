// Hold hints on the Floor at real sizes, EN and AR: a table whose label is
// cut — on the room's plan, on the inspector beside it, on the phone's list —
// says it whole on a long press; a label that fits says nothing, and a tap
// still selects the table.
part of 'floor_render_test.dart';

const _longTable = 'Terrace by the fountain, window 12';
const _longTableAr = 'التراس بجانب النافورة، النافذة ١٢';

/// The room with one long table label (T4's place) beside the short ones.
class _LongLabelFake extends _Fake {
  _LongLabelFake({super.rtl});

  String get longLabel => rtl ? _longTableAr : _longTable;

  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #floorLayout) {
      return Future<FloorLayoutView>.value(
        FloorLayoutView(
          sections: _layout.sections,
          tables: [
            for (final t in _layout.tables)
              if (t.id == 't4')
                FloorTableStateView(
                  id: t.id,
                  sectionId: t.sectionId,
                  label: longLabel,
                  seats: t.seats,
                  shape: t.shape,
                  status: t.status,
                  posX: t.posX,
                  posY: t.posY,
                  width: t.width,
                  height: t.height,
                  rotation: t.rotation,
                  heldLockedByOther: false,
                )
              else
                t,
          ],
        ),
      );
    }
    return super.noSuchMethod(i);
  }
}

/// The kit's hint bubble saying exactly [text] (ink on paper), never the
/// text in place.
Finder _bubble(String text) {
  final look = BoxDecoration(
    color: MadarColors.light.textPrimary,
    borderRadius: BorderRadius.circular(Radii.sm),
  );
  return find.byElementPredicate((e) {
    final w = e.widget;
    if (w is! Text || (w.data ?? w.textSpan?.toPlainText()) != text) {
      return false;
    }
    var inBubble = false;
    e.visitAncestorElements((a) {
      final box = a.widget;
      if (box is DecoratedBox && box.decoration == look) {
        inBubble = true;
        return false;
      }
      return true;
    });
    return inBubble;
  }, description: 'hint bubble "$text"');
}

bool _hinted(Finder text) => find
    .ancestor(of: text, matching: find.byType(Tooltip))
    .evaluate()
    .isNotEmpty;

void _floorHoldHintsMain() {
  for (final device in [
    _Device.ipad,
    _Device.ipad9,
    _Device.ipad9Portrait,
    _Device.tab8,
    _Device.lenovo,
    _Device.phone,
  ]) {
    for (final rtl in [false, true]) {
      final tag = '${device.name}-${rtl ? 'ar' : 'en'}';
      testWidgets('a long table label says itself whole on a hold; a short '
          'one says nothing ($tag)', (tester) async {
        final fake = _LongLabelFake(rtl: rtl);
        await _mount(tester, device: device, rtl: rtl, fake: fake);
        if (device == _Device.phone) {
          // A phone opens on the list, where this label has the row to
          // itself and FITS — so it hints nothing there. The plan cuts it.
          final row = find.text(fake.longLabel);
          await tester.scrollUntilVisible(
            row,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(_hinted(row), isFalse, reason: 'it fits the list row');
          await tester.tap(
            find.text(coreWord('tables.view_plan', arabic: rtl)),
          );
          await _settle(tester);
        }
        final label = find.text(fake.longLabel);
        expect(label, findsWidgets);
        // On the plan it is cut, and so it hints.
        final cut = label.first;
        expect(_hinted(cut), isTrue, reason: 'cut on the $tag floor');
        final short = find.text('T5').first;
        expect(_hinted(short), isFalse, reason: 'T5 fits');

        await tester.longPress(cut);
        await tester.pump();
        expect(_bubble(fake.longLabel), findsOneWidget);
        if (_render) {
          await tester.pump(const Duration(milliseconds: 300));
          await _capture(tester, 'hint-table-$tag');
        }
        await tester.pump(const Duration(seconds: 4));
        await _settle(tester);
        expect(_bubble(fake.longLabel), findsNothing);

        await tester.longPress(short);
        await tester.pump();
        expect(_bubble('T5'), findsNothing);
        await tester.pump(const Duration(seconds: 4));
        await _settle(tester);

        // A tap still selects it: the inspector (or the phone's sheet)
        // names the table — and says the whole of it on a hold there too.
        await tester.tap(cut);
        await _settle(tester);
        final named = find.text(fake.longLabel);
        expect(named, findsWidgets);
        final hinted = [
          for (final e in named.evaluate())
            if (_hinted(find.byElementPredicate((x) => x == e))) e,
        ];
        expect(hinted, isNotEmpty, reason: 'the detail cuts it too');
        await _capture(tester, 'hint-table-selected-$tag');
      });
    }
  }
}
