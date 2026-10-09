// The studio's Item details, How it's made, Modifiers and Options sections
// (MENU-STUDIO-023..029, 062..089, 112), driven through the real shell.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/studio/studio_steps.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

import 'support.dart';

final String _latte = item('latte');
String _ing(String k) => MenuSeedIds.ingredient(k);

/// The text field of the option row [i].
Finder optionRow(int i) => find.byKey(ValueKey('studio-option-$i'));

/// The step row [i].
Finder stepRow(int i) => find.byKey(ValueKey('studio-step-$i'));

/// The attached group card.
Finder groupCard(String key) =>
    find.byKey(ValueKey('studio-group-${MenuSeedIds.group(key)}'));

/// An option row's words in an open list (not the search box).
Finder option(String name) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DashOptionList),
  matching: find.byWidgetPredicate((w) => w is Text && w.data == name),
);

void main() {
  group('MENU-STUDIO-023..029 item details', () {
    testWidgets('MENU-STUDIO-023 the image beside the fields; above on a '
        'phone', (tester) async {
      final h = await pumpStudio(tester);
      final image = studioLabel(h.t('uploader.choose'));
      final name = fieldWithText('Caffè Latte');
      expect(
        tester.getTopLeft(image).dx,
        lessThan(tester.getTopLeft(name).dx),
      );
      expect(studioText(h.t('menu.imageHint')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-023 phone: stacked', (tester) async {
      final h = await pumpStudio(tester, size: DashSize.phone);
      expect(
        tester.getBottomLeft(studioLabel(h.t('uploader.choose'))).dy,
        lessThan(tester.getTopLeft(fieldWithText('Caffè Latte')).dy),
      );
    });

    testWidgets('MENU-STUDIO-024 a picked image is staged and shown', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      h.files.imageQueue.add(
        PickedFile(name: 'latte.png', bytes: _png, mimeType: 'image/png'),
      );
      await h.tap(studioLabel(h.t('uploader.choose')));
      expect(inStudio(find.byType(Image)), findsWidgets);
      expect(h.server.callsTo(uploadT), isEmpty);
      expect(saveBar, findsOneWidget);
      await h.shot('studio/image-staged');
    });

    testWidgets('MENU-STUDIO-024 refused files: not an image, too large', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      h.files.imageQueue.add(
        const PickedFile(
          name: 'notes.txt',
          bytes: [1, 2, 3],
          mimeType: 'text/plain',
        ),
      );
      await h.tap(studioLabel(h.t('uploader.choose')));
      expect(studioText(h.t('uploader.notAnImage')), findsOneWidget);
      h.files.imageQueue.add(
        PickedFile(
          name: 'huge.png',
          bytes: List.filled(5 * 1024 * 1024 + 1, 0),
          mimeType: 'image/png',
        ),
      );
      await h.tap(studioLabel(h.t('uploader.choose')));
      expect(studioText(h.t('uploader.tooLarge')), findsOneWidget);
      expect(saveBar, findsNothing);
    });

    testWidgets('MENU-STUDIO-025 removing a staged file is clean again', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      expect(inSection(
          h.t('menu.studio.basics.title'),
          find.bySemanticsLabel(h.t('uploader.remove')),
        ), findsNothing);
      h.files.imageQueue.add(
        PickedFile(name: 'latte.png', bytes: _png, mimeType: 'image/png'),
      );
      await h.tap(studioLabel(h.t('uploader.choose')));
      await h.tap(inSection(
          h.t('menu.studio.basics.title'),
          find.bySemanticsLabel(h.t('uploader.remove')),
        ));
      expect(saveBar, findsNothing);
      expect(inSection(
          h.t('menu.studio.basics.title'),
          find.bySemanticsLabel(h.t('uploader.remove')),
        ), findsNothing);
      expect(studioLabel(h.t('uploader.choose')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-025 a server image: removal is staged', (
      tester,
    ) async {
      final s = studioServer();
      s.db[MenuTables.menuItems].update(_latte, {
        'image_url': 'https://cdn.sabah.test/latte.webp',
      });
      final h = await pumpStudio(tester, seeded: s);
      await h.tap(inSection(
          h.t('menu.studio.basics.title'),
          find.bySemanticsLabel(h.t('uploader.remove')),
        ));
      expect(studioLabel(h.t('uploader.choose')), findsOneWidget);
      expect(saveBar, findsOneWidget);
      expect(h.server.callsTo(itemT, method: 'PATCH'), isEmpty);
      await h.tap(inSaveBar(h.t('menu.studio.discard')));
      expect(inSection(
          h.t('menu.studio.basics.title'),
          find.bySemanticsLabel(h.t('uploader.remove')),
        ), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-025 a picture still processing (no legacy '
        'address) can be removed', (tester) async {
      final s = studioServer();
      s.db[MenuTables.menuItems].update(_latte, {
        'image_url': null,
        'image': {'status': 'processing', 'job_id': 'job-latte'},
      });
      final h = await pumpStudio(tester, seeded: s);
      final remove = inSection(
        h.t('menu.studio.basics.title'),
        find.bySemanticsLabel(h.t('uploader.remove')),
      );
      expect(remove, findsOneWidget);
      await h.shot('studio/image-processing');
      await h.tap(remove);
      expect(studioLabel(h.t('uploader.choose')), findsOneWidget);
      await tapSave(h);
      final body = lastBody(h, 'PATCH', itemT);
      expect(body.containsKey('image_url'), isTrue);
      expect(body['image_url'], isNull);
      await h.flushTimers();
    });

    testWidgets('MENU-STUDIO-026/027 bilingual name and description', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      expect(studioText(h.t('common.name')), findsWidgets);
      expect(
        studioText(
          h.t('bilingualField.arabicLabel', args: {'label': h.t('common.name')}),
        ),
        findsOneWidget,
      );
      expect(fieldWithText('لاتيه'), findsOneWidget);
      // The Arabic description is always seeded empty.
      final descs = inStudio(
        find.byWidgetPredicate((w) => w is EditableText && w.maxLines != 1),
      );
      expect(descs, findsNWidgets(2));
      expect(tester.widget<EditableText>(descs.at(1)).controller.text, '');
    });

    testWidgets('MENU-STUDIO-028 the category: translated choices, "+" '
        'creates and selects', (tester) async {
      final h = await pumpStudio(tester, locale: 'ar');
      expect(lastCall(h, 'GET', categoriesT).query['org_id'], [SeedIds.sabahOrg]);
      await h.tap(
        find.descendant(
          of: inSection(
            h.t('menu.studio.basics.title'),
            find.byType(DashSelect<String>),
          ),
          matching: find.byType(DashSelectTrigger),
        ).first,
      );
      expect(option('مخبوزات'), findsWidgets);
    });

    testWidgets('MENU-STUDIO-028 "+": a new category is selected (dirty)', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(studioLabel(h.t('menu.newCategory')));
      await h.enterText(
        find.descendant(
          of: find.byType(DashSurface),
          matching: find.byType(EditableText),
        ).first,
        'Seasonal',
      );
      await h.tap(find.text(h.t('common.save')).last);
      expect(lastBody(h, 'POST', categoriesT)['name'], 'Seasonal');
      await h.flushTimers();
      expect(studioText('Seasonal'), findsOneWidget);
      await tapSave(h);
      final created = h.db![MenuTables.categories].firstWhere(
        (c) => c['name'] == 'Seasonal',
      )!;
      expect(lastBody(h, 'PATCH', itemT)['category_id'], created['id']);
      await h.flushTimers();
    });

    testWidgets('MENU-STUDIO-029 the active switch and its hint', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      expect(studioText(h.t('menu.studio.basics.activeHint')), findsOneWidget);
      await h.tap(
        inSection(
          h.t('menu.studio.basics.title'),
          find.bySemanticsLabel(h.t('common.active')),
        ).first,
      );
      await tapSave(h);
      expect(lastBody(h, 'PATCH', itemT)['is_active'], isFalse);
      await h.flushTimers();
    });
  });

  group('MENU-STUDIO-062..073 how it is made', () {
    testWidgets('MENU-STUDIO-062/064/071 the library, numbered rows, frames', (
      tester,
    ) async {
      final h = await pumpStudio(tester, key: 'spanish');
      expect(h.server.callsTo(presetsT), hasLength(1));
      for (var i = 0; i < 4; i++) {
        expect(
          find.descendant(of: stepRow(i), matching: find.text('${i + 1}')),
          findsOneWidget,
        );
      }
      // Preset rows hold their animation's still frame; a written row a
      // sparkle.
      expect(
        h.server.callsTo('/recipes/step-presets/{slug}/animation').map(
          (c) => c.path,
        ),
        containsAll([
          '/recipes/step-presets/pull-espresso/animation',
          '/recipes/step-presets/steam-milk/animation',
        ]),
      );
      expect(
        find.descendant(of: stepRow(0), matching: find.byType(Lottie)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: stepRow(1), matching: find.byType(Lottie)),
        findsNothing,
      );
      final lottie = tester.widget<Lottie>(
        find.descendant(of: stepRow(0), matching: find.byType(Lottie)),
      );
      expect(lottie.animate, isFalse);
    });

    testWidgets('MENU-STUDIO-063 no steps: the dashed sentence', (
      tester,
    ) async {
      final h = await pumpStudio(tester, key: 'cappuccino');
      expect(studioText(h.t('menu.studio.steps.empty')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-065 preset name and note; "From the library"; a '
        'retired step', (tester) async {
      final s = studioServer();
      s.db[MenuTables.steps].insert({
        'menu_item_id': _latte,
        'position': 4,
        'kind': 'preset',
        'preset_slug': 'old-foam',
        'name': null,
        'name_ar': null,
        'note': null,
        'note_ar': null,
      }, timestamps: false);
      final h = await pumpStudio(tester, seeded: s);
      expect(
        find.descendant(of: stepRow(0), matching: find.text('Pull the espresso')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stepRow(0),
          matching: find.text('18 g in, 36 g out in 25 to 30 seconds'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: stepRow(2),
          matching: find.text(h.t('menu.studio.steps.fromLibrary')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: stepRow(3), matching: find.text('old-foam')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stepRow(3),
          matching: find.text(h.t('menu.studio.steps.retired')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-065 Arabic: the library\'s Arabic name', (
      tester,
    ) async {
      await pumpStudio(tester, locale: 'ar');
      expect(
        find.descendant(of: stepRow(0), matching: find.text('استخلص الإسبريسو')),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-066/067 a written step: two names, two notes', (
      tester,
    ) async {
      final h = await pumpStudio(tester, key: 'spanish');
      final row = stepRow(1);
      expect(
        find.descendant(
          of: row,
          matching: find.bySemanticsLabel(h.t('menu.studio.steps.titleEn')),
        ),
        findsOneWidget,
      );
      final ar = find.descendant(
        of: row,
        matching: find.bySemanticsLabel(h.t('menu.studio.steps.titleAr')),
      );
      expect(
        tester.widget<EditableText>(
          find.descendant(of: ar, matching: find.byType(EditableText)),
        ).textDirection,
        TextDirection.rtl,
      );
      final note = find.descendant(
        of: row,
        matching: find.bySemanticsLabel(h.t('menu.studio.steps.noteEn')),
      );
      expect(note, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.text(h.t('menu.studio.steps.notePlaceholder')),
        ),
        findsOneWidget,
      );
      await h.enterText(note, 'x' * 300);
      expect(editableIn(tester, note).controller.text.length, 280);
      expect(
        find.descendant(
          of: row,
          matching: find.bySemanticsLabel(h.t('menu.studio.steps.noteAr')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-068 move up / down / remove', (tester) async {
      final h = await pumpStudio(tester);
      DashIconButton btn(int i, String key) => tester.widget<DashIconButton>(
        find
            .descendant(
              of: stepRow(i),
              matching: find.byWidgetPredicate(
                (w) => w is DashIconButton && w.semanticLabel == h.t(key),
              ),
            )
            .first,
      );
      expect(btn(0, 'menu.studio.steps.moveUp').onPressed, isNull);
      expect(btn(2, 'menu.studio.steps.moveDown').onPressed, isNull);
      await h.tap(
        find.descendant(
          of: stepRow(0),
          matching: find.bySemanticsLabel(h.t('menu.studio.steps.moveDown')),
        ),
      );
      expect(
        find.descendant(of: stepRow(0), matching: find.text('Steam the milk')),
        findsOneWidget,
      );
      await h.tap(
        find.descendant(
          of: stepRow(2),
          matching: find.bySemanticsLabel(h.t('common.remove')),
        ),
      );
      expect(stepRow(2), findsNothing);
      await tapSave(h);
      final steps = (lastBody(h, 'PUT', stepsT)['steps']! as List)
          .cast<Map<String, Object?>>();
      expect(steps.map((s) => s['preset_slug']), [
        'steam-milk',
        'pull-espresso',
      ]);
      await h.flushTimers();
    });

    testWidgets('MENU-STUDIO-069 "Write your own" appends a written step', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('menu.studio.steps.addCustom')));
      expect(stepRow(3), findsOneWidget);
      expect(
        find.descendant(
          of: stepRow(3),
          matching: find.bySemanticsLabel(h.t('menu.studio.steps.titleEn')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-069/070 the library picker: tiles, pick one', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('menu.studio.steps.addFromLibrary')));
      expect(find.text(h.t('menu.studio.steps.pickTitle')), findsWidgets);
      expect(find.text(h.t('menu.studio.steps.pickDesc')), findsOneWidget);
      expect(find.byKey(const ValueKey('step-preset-blend')), findsOneWidget);
      await h.shot('studio/step-picker');
      await h.tap(find.byKey(const ValueKey('step-preset-blend')));
      expect(find.text(h.t('menu.studio.steps.pickDesc')), findsNothing);
      expect(
        find.descendant(of: stepRow(3), matching: find.text('Blend until smooth')),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-070 the picker\'s own "Write your own" and Close', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('menu.studio.steps.addFromLibrary')));
      await h.tap(find.text(h.t('common.close')).last);
      expect(stepRow(3), findsNothing);
      await h.tap(studioText(h.t('menu.studio.steps.addFromLibrary')));
      await h.tap(
        find.descendant(
          of: find.byType(DashSurface),
          matching: find.text(h.t('menu.studio.steps.addCustom')),
        ),
      );
      expect(find.text(h.t('menu.studio.steps.pickDesc')), findsNothing);
      expect(
        find.descendant(
          of: stepRow(3),
          matching: find.bySemanticsLabel(h.t('menu.studio.steps.titleEn')),
        ),
        findsOneWidget,
      );
    });

    for (final locale in ['en', 'ar']) {
      testWidgets('MENU-STUDIO-070 the picker\'s footer ($locale): "Write '
          'your own" at the start, Close at the end', (tester) async {
        final h = await pumpStudio(tester, locale: locale);
        await h.tap(studioText(h.t('menu.studio.steps.addFromLibrary')));
        final surface = find.byType(DashSurface);
        final write = tester.getRect(
          find.descendant(
            of: surface,
            matching: find.text(h.t('menu.studio.steps.addCustom')),
          ),
        );
        final close = tester.getRect(
          find.descendant(
            of: surface,
            matching: find.text(h.t('common.close')),
          ),
        );
        final mid = tester.getRect(surface).center.dx;
        final rtl = locale == 'ar';
        expect(write.center.dx < mid, !rtl);
        expect(close.center.dx > mid, !rtl);
        await h.shot('studio/step-picker-footer');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await h.settle();
      });
    }

    testWidgets('MENU-STUDIO-070 an empty library', (tester) async {
      final s = studioServer();
      s.db[MenuTables.stepPresets].clear();
      final h = await pumpStudio(tester, seeded: s);
      await h.tap(studioText(h.t('menu.studio.steps.addFromLibrary')));
      expect(find.text(h.t('menu.studio.steps.noPresets')), findsOneWidget);
      await h.shot('studio/step-picker-empty');
    });

    testWidgets('MENU-STUDIO-070 loading: six tile skeletons; a failed '
        'library: the error and Retry', (tester) async {
      final s = studioServer();
      final gate = s.server.hold('GET', presetsT);
      final h = await pumpStudio(tester, seeded: s);
      await h.tap(studioText(h.t('menu.studio.steps.addFromLibrary')));
      expect(
        find.descendant(
          of: find.byType(DashSurface),
          matching: find.byType(DashSkeleton),
        ),
        findsNWidgets(6),
      );
      expect(find.text(h.t('menu.studio.steps.noPresets')), findsNothing);
      await h.shot('studio/step-picker-loading');
      gate.release();
      await h.settle();
      expect(find.byKey(const ValueKey('step-preset-blend')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-070 a failed library: the reason and Retry, '
        'never "empty"', (tester) async {
      final s = studioServer();
      final failure = MockResponse.error(500, 'Library offline');
      s.server.fail('GET', presetsT, failure, times: null);
      final h = await pumpStudio(tester, seeded: s);
      await h.tap(studioText(h.t('menu.studio.steps.addFromLibrary')));
      expect(find.text(h.t('menu.studio.steps.noPresets')), findsNothing);
      expect(find.text(h.refusalWords(failure)), findsOneWidget);
      await h.shot('studio/step-picker-failed');
      s.server.clearFailures();
      await h.tap(find.text(h.t('common.retry')).last);
      expect(find.byKey(const ValueKey('step-preset-blend')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-072 refusal (manager): shown, not edited', (
      tester,
    ) async {
      final h = await pumpStudio(
        tester,
        key: 'spanish',
        persona: Persona.manager,
      );
      expect(stepRow(1), findsOneWidget);
      expect(
        tester.widget<TextField>(
          find.descendant(of: stepRow(1), matching: find.byType(TextField)).first,
        ).enabled,
        isFalse,
      );
      expect(
        find.descendant(
          of: stepRow(0),
          matching: find.bySemanticsLabel(h.t('menu.studio.steps.moveDown')),
        ),
        findsNothing,
      );
      expect(studioText(h.t('menu.studio.steps.addFromLibrary')), findsNothing);
      expect(studioText(h.t('menu.studio.steps.addCustom')), findsNothing);
    });

    testWidgets('MENU-STUDIO-073 a name typed in one language seeds the '
        'Arabic box empty', (tester) async {
      final s = studioServer();
      s.db[MenuTables.steps].insert({
        'menu_item_id': _latte,
        'position': 4,
        'kind': 'custom',
        'preset_slug': null,
        'name': 'Dust with cocoa',
        'name_ar': 'Dust with cocoa',
        'note': null,
        'note_ar': null,
      }, timestamps: false);
      final h = await pumpStudio(tester, seeded: s);
      final ar = find.descendant(
        of: stepRow(3),
        matching: find.bySemanticsLabel(h.t('menu.studio.steps.titleAr')),
      );
      expect(editableIn(tester, ar).controller.text, '');
      expect(saveBar, findsNothing);
    });
  });

  group('MENU-STUDIO-074..084 modifiers', () {
    testWidgets('MENU-STUDIO-074/076 the org groups; a card per attached '
        'group', (tester) async {
      final h = await pumpStudio(tester);
      final call = lastCall(h, 'GET', orgGroupsT);
      expect(call.query['org_id'], [SeedIds.sabahOrg]);
      final milk = groupCard('milk');
      expect(find.descendant(of: milk, matching: find.text('Milk')), findsWidgets);
      expect(
        find.descendant(
          of: milk,
          matching: find.text(h.t('menu.studio.modifiers.single')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: groupCard('extras'),
          matching: find.text(h.t('menu.studio.modifiers.multi')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-075 none attached: the empty state', (
      tester,
    ) async {
      final h = await pumpStudio(tester, key: 'v60');
      expect(studioText(h.t('menu.studio.modifiers.empty')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-077 "Edit group" opens its editor', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      h.allowUnmatched = true;
      await h.tap(
        find.descendant(
          of: groupCard('milk'),
          matching: find.text(h.t('menu.groups.editGroup')),
        ),
      );
      expect(h.location.path, '/menu/groups');
      expect(h.location.queryParameters, {'edit': MenuSeedIds.group('milk')});
    });

    testWidgets('MENU-STUDIO-078 detach drops the card (no confirm)', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(
        find.descendant(
          of: groupCard('milk'),
          matching: find.bySemanticsLabel(h.t('menu.studio.modifiers.detach')),
        ),
      );
      expect(groupCard('milk'), findsNothing);
      expect(saveBar, findsOneWidget);
    });

    testWidgets('MENU-STUDIO-079 chips: toggle out, back in collapses to all', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      final milk = MenuSeedIds.group('milk');
      final chip = find.byKey(
        ValueKey('chip-$milk-${MenuSeedIds.option('milk', 'oat')}'),
      );
      await h.tap(chip);
      expect(saveBar, findsOneWidget);
      await h.tap(chip);
      expect(saveBar, findsNothing);
    });

    testWidgets('MENU-STUDIO-079 a group with no options says so', (
      tester,
    ) async {
      final s = studioServer();
      s.db[MenuTables.groups].insert({
        'id': mockUuid('group:empty'),
        'org_id': SeedIds.sabahOrg,
        'name': 'Cup art',
        'name_translations': const <String, Object?>{},
        'selection_type': 'multi',
        'min_selections': 0,
        'max_selections': null,
        'is_required': false,
        'is_active': true,
        'effect': 'none',
        'legacy_addon_type': null,
        'sort': 99,
        'is_item_options': false,
        'options': const <Object?>[],
      });
      s.db[MenuTables.groupLinks].insert({
        'menu_item_id': _latte,
        'group_id': mockUuid('group:empty'),
        'sort': 9,
      }, timestamps: false);
      final h = await pumpStudio(tester, seeded: s);
      expect(studioText(h.t('menu.studio.modifiers.noOptions')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-080 each option\'s recipe and cost, read-only', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      final extras = groupCard('extras');
      expect(
        find.descendant(
          of: extras,
          matching: studioPlain('House espresso blend 18 g'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: extras,
          matching: find.textContaining(h.t('menu.groups.studio.cost')),
        ),
        findsWidgets,
      );
    });

    testWidgets('MENU-STUDIO-080 Arabic: the deduction units in Arabic', (
      tester,
    ) async {
      final h = await pumpStudio(tester, locale: 'ar');
      final grams = h.t('units.g');
      expect(grams, isNot('g'));
      await tester.ensureVisible(groupCard('extras'));
      await h.settle();
      await h.shot('studio/modifiers-units');
      expect(
        find.descendant(
          of: groupCard('extras'),
          matching: studioPlain('18 $grams'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(of: groupCard('extras'), matching: studioPlain('18 g')),
        findsNothing,
      );
    });

    testWidgets('MENU-STUDIO-081 Required, Min, Max (blank = ∞)', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      final card = groupCard('extras');
      final max = find.descendant(
        of: card,
        matching: find.bySemanticsLabel(h.t('menu.studio.modifiers.max')),
      );
      await h.enterText(max, '');
      expect(
        find.descendant(
          of: card,
          matching: find.text(h.t('menu.studio.modifiers.unlimited')),
        ),
        findsOneWidget,
      );
      await h.enterText(
        find.descendant(
          of: card,
          matching: find.bySemanticsLabel(h.t('menu.studio.modifiers.min')),
        ),
        '2',
      );
      await tapSave(h);
      final groups = (lastBody(h, 'PUT', groupsT)['groups']! as List)
          .cast<Map<String, Object?>>();
      final e = groups.firstWhere(
        (g) => g['group_id'] == MenuSeedIds.group('extras'),
      );
      expect(e['min_override'], 2);
      expect(e['max_override'], isNull);
      await h.flushTimers();
    });

    testWidgets('MENU-STUDIO-082 attach: active, reusable, not attached', (
      tester,
    ) async {
      final s = studioServer();
      seedItemOptions(s, 'mocha', [
        {'name': 'Marshmallows', 'price': 1500, 'is_active': true},
      ]);
      final h = await pumpStudio(tester, key: 'v60', seeded: s);
      await h.tap(studioText(h.t('menu.studio.modifiers.attach')));
      expect(option('Milk'), findsWidgets);
      expect(option('Extras'), findsOneWidget);
      // Another item's own options are not offered.
      expect(option('Options'), findsNothing);
      await h.tap(option('Milk').first);
      expect(groupCard('milk'), findsOneWidget);
      await tapSave(h);
      final groups = (lastBody(h, 'PUT', groupsT)['groups']! as List)
          .cast<Map<String, Object?>>();
      expect(groups.single['group_id'], MenuSeedIds.group('milk'));
      expect(groups.single['included_option_ids'], isNull);
      await h.flushTimers();
    });

    testWidgets('MENU-STUDIO-083 "New group" opens the choice-group editor; '
        'closing it refreshes the studio', (tester) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('menu.groups.new')));
      expect(find.text(h.t('menu.groups.editor.newTitle')), findsWidgets);
      final before = h.server.callsTo(studioT).length;
      await h.tap(find.bySemanticsLabel(h.t('common.close')).last);
      expect(h.server.callsTo(studioT).length, before + 1);
    });

    testWidgets('MENU-STUDIO-084 refusal (manager): no Edit / New group', (
      tester,
    ) async {
      final h = await pumpStudio(tester, persona: Persona.manager);
      expect(studioText(h.t('menu.groups.editGroup')), findsNothing);
      expect(studioText(h.t('menu.groups.new')), findsNothing);
      expect(
        studioLabel(h.t('menu.studio.modifiers.detach')),
        findsWidgets,
      );
    });
  });

  group('MENU-STUDIO-085..089, 112 options', () {
    testWidgets('MENU-STUDIO-085/088/112 no options: only the dashed add; a '
        'new row', (tester) async {
      final h = await pumpStudio(tester);
      expect(optionRow(0), findsNothing);
      await h.tap(studioText(h.t('menu.studio.options.add')));
      final row = optionRow(0);
      expect(
        find.descendant(
          of: row,
          matching: find.text(h.t('menu.studio.options.namePh')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('${h.t('common.price')} (EGP)')),
        findsOneWidget,
      );
      expect(
        editableIn(
          tester,
          find.descendant(
            of: row,
            matching: find.bySemanticsLabel('${h.t('common.price')} (EGP)'),
          ),
        ).controller.text,
        '0',
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(h.t('menu.studio.options.noDeduction')),
        ),
        findsOneWidget,
      );
      await h.tap(
        find.descendant(of: row, matching: find.bySemanticsLabel(h.t('common.remove'))),
      );
      expect(optionRow(0), findsNothing);
    });

    testWidgets('MENU-STUDIO-085 Arabic: the price label names the currency '
        'in Arabic', (tester) async {
      final h = await pumpStudio(tester, locale: 'ar');
      await h.tap(studioText(h.t('menu.studio.options.add')));
      final label = '${h.t('common.price')} (ج.م)';
      expect(
        find.descendant(of: optionRow(0), matching: find.text(label)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: optionRow(0), matching: find.bySemanticsLabel(label)),
        findsWidgets,
      );
      expect(
        find.descendant(of: optionRow(0), matching: find.textContaining('EGP')),
        findsNothing,
      );
    });

    for (final (size, locale) in [
      (DashSize.desktop, 'en'),
      (DashSize.desktop, 'ar'),
      (DashSize.phone, 'en'),
    ]) {
      testWidgets('MENU-STUDIO-085 layout (${size.name}, $locale): Name '
          'stretches, the trash sits at the row\'s end', (tester) async {
        final h = await pumpStudio(tester, size: size, locale: locale);
        await h.tap(studioText(h.t('menu.studio.options.add')));
        final row = tester.getRect(optionRow(0));
        Rect rect(Finder f) => tester.getRect(
          find.descendant(of: optionRow(0), matching: f).first,
        );
        final name = rect(find.bySemanticsLabel(h.t('common.name')));
        final price = rect(
          find.bySemanticsLabel('${h.t('common.price')} (${locale == 'ar' ? 'ج.م' : 'EGP'})'),
        );
        final trash = rect(find.bySemanticsLabel(h.t('common.remove')));
        expect(name.width, greaterThan(price.width));
        // The row's inner edge is its padding (Space.md) in.
        const slack = 12.0 + 1;
        if (locale == 'ar') {
          expect(trash.left - row.left, lessThanOrEqualTo(slack));
        } else {
          expect(row.right - trash.right, lessThanOrEqualTo(slack));
        }
        await h.shot('studio/option-row');
      });
    }

    testWidgets('MENU-STUDIO-086/087 deducts: pick, quantity, cost, clear', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('menu.studio.options.add')));
      final row = optionRow(0);
      await h.enterText(
        find.descendant(of: row, matching: find.bySemanticsLabel(h.t('common.name'))),
        'Caramel drizzle',
      );
      await h.tap(
        find.descendant(
          of: row,
          matching: find.text(h.t('menu.studio.options.noDeduction')),
        ),
      );
      await pickOption(h, 'Caramel syrup');
      final qty = find.descendant(
        of: row,
        matching: find.bySemanticsLabel(h.t('common.quantity')),
      );
      expect(find.descendant(of: row, matching: find.text('ml')), findsOneWidget);
      await h.enterText(qty, '15');
      // 15 ml × EGP 0.08.
      expect(
        find.descendant(
          of: row,
          matching: find.text(
            h.t('menu.studio.options.cost', args: {'cost': 'EGP 1.20'}),
          ),
        ),
        findsOneWidget,
      );
      await tapSave(h);
      final opt = ((lastBody(h, 'PUT', optionsT)['options']! as List).single
          as Map);
      expect(opt['recipe'], [
        {'ingredient_id': _ing('caramel_syrup'), 'quantity': 15.0, 'unit': 'ml'},
      ]);
      await h.flushTimers();
      // Clear: the deduction goes (an empty recipe is sent).
      await h.tap(
        find.descendant(of: optionRow(0), matching: find.text(h.t('common.clear'))),
      );
      expect(
        find.descendant(
          of: optionRow(0),
          matching: find.bySemanticsLabel(h.t('common.quantity')),
        ),
        findsNothing,
      );
      await tapSave(h);
      final cleared = ((lastBody(h, 'PUT', optionsT)['options']! as List).single
          as Map);
      expect(cleared['recipe'], <Object?>[]);
      expect(cleared['id'], isNotNull);
      await h.flushTimers();
      expect(
        find.descendant(
          of: optionRow(0),
          matching: find.text(h.t('menu.studio.options.noDeduction')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-089 only the first recipe line is editable', (
      tester,
    ) async {
      final s = studioServer();
      seedItemOptions(s, 'latte', [
        {
          'name': 'Affogato style',
          'price': 2500,
          'is_active': true,
          'recipe': [
            {'ingredient_id': _ing('vanilla_syrup'), 'quantity': 10, 'unit': 'ml'},
            {'ingredient_id': _ing('whipped_cream'), 'quantity': 20, 'unit': 'g'},
          ],
        },
      ]);
      final h = await pumpStudio(tester, seeded: s);
      final row = optionRow(0);
      expect(fieldWithText('Affogato style'), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Vanilla syrup')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Whipped cream')), findsNothing);
      expect(
        editableIn(
          tester,
          find.descendant(of: row, matching: find.bySemanticsLabel(h.t('common.quantity'))),
        ).controller.text,
        '10',
      );
      expect(fieldWithText('25'), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-112 ungated: a manager may stage an option; the '
        'server refuses the save', (tester) async {
      final h = await pumpStudio(tester, persona: Persona.manager);
      await h.tap(studioText(h.t('menu.studio.options.add')));
      await h.enterText(
        find.descendant(
          of: optionRow(0),
          matching: find.bySemanticsLabel(h.t('common.name')),
        ),
        'Extra foam',
      );
      await tapSave(h);
      await h.expectToast(
        h.t(
          'menu.studio.saveFailedIn',
          args: {
            'section': h.t('menu.studio.tabs.options'),
            'error': h.refusalWords(MockResponse.denied('menu.items.edit')),
          },
        ),
      );
    });
  });

  testWidgets('StepPreview never moves with reduced motion', (tester) async {
    final h = await pumpStudio(tester);
    await h.tap(studioText(h.t('menu.studio.steps.addFromLibrary')));
    final tiles = find.descendant(
      of: find.byType(DashSurface),
      matching: find.byType(StepPreview),
    );
    expect(tiles, findsWidgets);
    for (final l in tester.widgetList<Lottie>(
      find.descendant(of: find.byType(DashSurface), matching: find.byType(Lottie)),
    )) {
      expect(l.animate, isFalse);
    }
  });
}

/// A 1×1 PNG.
const List<int> _png = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];
