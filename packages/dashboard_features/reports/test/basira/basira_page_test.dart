// Basira's page rows (REP-BAS-001–018, 026–031, 033), driven through the
// real shell on the mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashSidebar;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/basira/basira_charts.dart';
import 'package:dashboard_reports/src/basira/basira_models.dart';
import 'package:dashboard_reports/src/basira/basira_page.dart';
import 'package:dashboard_reports/src/basira/basira_result.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The owner's seeded conversations, newest first.
const String _top = 'Top 5 products last month';
const String _compare = 'Compare Maadi and Zamalek this month';
const String _waste = 'How much did we waste in the last 30 days?';
const String _prep = 'How long is prep taking at Zamalek?';

Finder _own(String s) => find.text(ownDirection(s));

/// The rail item titled [title].
Finder _item(String title) => inRail(find.text(title));

/// The ⋯ button of the rail item titled [title].
Finder _more(DashHarness h, String title) => find.descendant(
  of: find.ancestor(of: _item(title), matching: find.byType(Stack)).first,
  matching: find.bySemanticsLabel(h.t('common.more')),
);

/// The page header's title.
Finder _title(String s) => find.descendant(
  of: inPage(find.byType(DashPageHeader)),
  matching: find.text(s),
);

Map<String, Object?> _body(MockCall c) => (c.body! as Map).cast();

Future<void> _openConversation(DashHarness h, String title) =>
    h.tap(_item(title));

void main() {
  group('rail and header', () {
    testWidgets('REP-BAS-001 the Ask leaf under Basira opens the page', (
      tester,
    ) async {
      final h = await pumpBasira(tester);
      final sidebar = find.byType(DashSidebar);
      expect(
        find.descendant(of: sidebar, matching: find.text('Basira')),
        findsOneWidget,
      );
      await h.tap(find.descendant(of: sidebar, matching: find.text('Ask')));
      expect(h.location.path, basiraPath);
      expect(basiraPage, findsOneWidget);
    });

    testWidgets(
      'REP-BAS-001 without reports.read the leaf is hidden, the URL still '
      'renders the page and the refusal is a toast',
      (tester) async {
        final s = basiraServer(persona: Persona.limited);
        s.server.on(
          'GET',
          '/authz/me',
          (req) => MockResponse.ok({
            'user_id': Persona.limited.userId,
            'capabilities': ['orders.read', 'till.read'],
            'ask_manager': <String>[],
            'limits': <String, Object>{},
            'owner': false,
            'platform': false,
            'role_kinds': Persona.limited.roleKinds,
            'epoch': 1,
            'spec_version': 2,
          }),
        );
        final denied = MockResponse.denied('reports.read');
        s.server.fail('GET', listRoute, denied);
        final h = await pumpBasira(
          tester,
          persona: Persona.limited,
          server: s.server,
          db: s.db,
        );
        expect(
          find.descendant(
            of: find.byType(DashSidebar),
            matching: find.text('Ask'),
          ),
          findsNothing,
        );
        expect(basiraPage, findsOneWidget);
        await h.expectToast(h.refusalWords(denied));
        expect(inRail(find.text(h.t('basira.noChats'))), findsOneWidget);
      },
    );

    testWidgets('REP-BAS-002 a fixed header and composer; only the '
        'transcript scrolls', (tester) async {
      final h = await pumpBasira(tester);
      final composerAt = tester.getRect(composer);
      final headerAt = tester.getRect(inPage(find.byType(DashPageHeader)));
      for (final q in ['Top 3 products', 'Show the daily revenue trend']) {
        await askByTyping(h, q);
      }
      expect(tester.getRect(composer), composerAt);
      expect(tester.getRect(inPage(find.byType(DashPageHeader))), headerAt);
      final pos = tester
          .widget<SingleChildScrollView>(find.byKey(BasiraPage.transcriptKey))
          .controller!
          .position;
      expect(pos.maxScrollExtent, greaterThan(0));
    });

    testWidgets('REP-BAS-003 on mount the 30 most recent conversations are '
        'read, once', (tester) async {
      final h = await pumpBasira(tester);
      final calls = h.server.callsTo(listRoute);
      expect(calls, hasLength(1));
      expect(calls.single.query, {
        'limit': ['30'],
      });
      for (final t in [_top, _compare, _waste]) {
        expect(_item(t), findsOneWidget);
      }
    });

    testWidgets('REP-BAS-003 a failed list is a toast with the server\'s '
        'words and an empty list', (tester) async {
      final s = basiraServer();
      final boom = MockResponse.error(500, 'The AI store is unavailable');
      s.server.fail('GET', listRoute, boom);
      final h = await pumpBasira(tester, server: s.server, db: s.db);
      await h.expectToast(h.refusalWords(boom));
      expect(inRail(find.text(h.t('basira.noChats'))), findsOneWidget);
    });

    testWidgets('REP-BAS-003 conversations are private to their author', (
      tester,
    ) async {
      await pumpBasira(tester, persona: Persona.manager);
      expect(_item(_prep), findsOneWidget);
      expect(_item(_top), findsNothing);
    });

    testWidgets('REP-BAS-003 (refusal) a platform admin is refused: AI '
        'analytics needs an org-scoped account', (tester) async {
      final s = basiraServer(persona: Persona.platform);
      final h = await pumpBasira(
        tester,
        persona: Persona.platform,
        server: s.server,
        db: s.db,
      );
      expect(basiraPage, findsOneWidget);
      await h.expectToast(
        h.refusalWords(
          MockResponse.forbidden(
            'AI analytics requires an organization-scoped account',
          ),
        ),
      );
    });

    testWidgets('REP-BAS-004 the title is Basira, then the open '
        'conversation\'s title', (tester) async {
      final h = await pumpBasira(tester);
      expect(_title('Basira'), findsOneWidget);
      expect(
        pageText('Ask about your business in plain language.'),
        findsOneWidget,
      );
      await _openConversation(h, _compare);
      expect(_title(ownDirection(_compare)), findsOneWidget);
    });

    testWidgets('REP-BAS-005 below 1280 the header offers Conversations and '
        'New conversation; at 1280 and up it does not', (tester) async {
      final h = await pumpBasira(tester, size: DashSize.tablet);
      final header = inPage(find.byType(DashPageHeader));
      expect(
        find.descendant(of: header, matching: find.text('Conversations')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: header,
          matching: find.bySemanticsLabel('New conversation'),
        ),
        findsOneWidget,
      );
      expect(rail, findsNothing);
      // The icon button starts a new conversation.
      await h.tap(
        find.descendant(of: header, matching: find.text('Conversations')),
      );
      await h.tap(_item(_compare));
      expect(inPage(find.byType(BasiraBlockCard)), findsWidgets);
      await h.tap(
        find.descendant(
          of: header,
          matching: find.bySemanticsLabel('New conversation'),
        ),
      );
      expect(pageText(h.t('basira.welcomeTitle')), findsOneWidget);
    });

    testWidgets('REP-BAS-005 at 1280 the header has no actions', (
      tester,
    ) async {
      await pumpBasira(tester);
      final header = inPage(find.byType(DashPageHeader));
      expect(
        find.descendant(of: header, matching: find.text('Conversations')),
        findsNothing,
      );
    });

    for (final (lang, rtl) in [('en', false), ('ar', true)]) {
      testWidgets('REP-BAS-006 at 1280 the rail is pinned at the start side, '
          '276 wide ($lang)', (tester) async {
        await pumpBasira(tester, locale: lang);
        final r = tester.getRect(rail);
        final page = tester.getRect(basiraPage);
        // 276 less its 12 padding on each side and its end border.
        expect(r.width, BasiraMetrics.rail - 25);
        if (rtl) {
          expect(r.right, closeTo(page.right - 12, 1));
        } else {
          expect(r.left, closeTo(page.left + 12, 1));
        }
      });

      testWidgets('REP-BAS-006 below 1280 the rail is a slide-over from the '
          'start side, titled Conversations ($lang)', (tester) async {
        final h = await pumpBasira(tester, size: DashSize.tablet, locale: lang);
        await h.tap(inPage(find.text(h.t('basira.showConversations'))));
        expect(rail, findsOneWidget);
        expect(find.text(h.t('basira.conversations')), findsWidgets);
        final r = tester.getRect(rail);
        final screen = tester.getRect(find.byType(MaterialApp).first);
        // 86% of the window, capped at 340; less the padding and border.
        expect(r.width, BasiraMetrics.sheet - 25);
        if (rtl) {
          expect(r.right, closeTo(screen.right - 12, 1));
        } else {
          expect(r.left, closeTo(screen.left + 12, 1));
        }
        await h.shot('basira/rail-sheet');
      });
    }

    testWidgets('REP-BAS-007 the rail: New conversation, 4 skeleton rows '
        'while loading, then each conversation\'s title and count · date', (
      tester,
    ) async {
      final s = basiraServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpBasira(tester, server: s.server, db: s.db);
      expect(inRail(find.text('New conversation')), findsOneWidget);
      expect(inRail(find.byType(DashSkeleton)), findsNWidgets(4));
      gate.release();
      await h.settle();
      expect(inRail(find.byType(DashSkeleton)), findsNothing);
      expect(inRail(find.text('2 questions · 06 Oct 2026')), findsOneWidget);
      expect(inRail(find.text('1 question · 03 Oct 2026')), findsOneWidget);
    });

    testWidgets('REP-BAS-007 an empty list says conversations will appear '
        'here', (tester) async {
      final s = basiraServer();
      s.db['ai_conversations'].removeWhere((_) => true);
      final h = await pumpBasira(tester, server: s.server, db: s.db);
      expect(inRail(find.text(h.t('basira.noChats'))), findsOneWidget);
    });

    testWidgets('REP-BAS-007 the open conversation is highlighted; tapping '
        'one in the slide-over opens it and closes the slide-over', (
      tester,
    ) async {
      final h = await pumpBasira(tester, size: DashSize.tablet);
      await h.tap(inPage(find.text('Conversations')));
      await h.tap(_item(_compare));
      expect(rail, findsNothing);
      expect(h.server.callsTo(convRoute), hasLength(1));
      await h.tap(inPage(find.text('Conversations')));
      expect(
        tester.getSemantics(
          find
              .ancestor(
                of: _item(_compare),
                matching: find.byType(DashPressable),
              )
              .first,
        ),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(
          find
              .ancestor(of: _item(_top), matching: find.byType(DashPressable))
              .first,
        ),
        isSemantics(isSelected: false),
      );
    });

    testWidgets('REP-BAS-007 Arabic: plural question counts and Arabic '
        'dates', (tester) async {
      final h = await pumpBasira(tester, locale: 'ar');
      expect(
        inRail(
          find.text('${h.t('basira.turnCount', count: 2)} · 06 أكتوبر 2026'),
        ),
        findsOneWidget,
      );
      expect(h.t('basira.turnCount', count: 2), 'سؤالان');
    });

    testWidgets('REP-BAS-008 (divergence) at 1280 the ⋯ menu shows on hover, '
        'at the end side; it offers Rename and Delete', (tester) async {
      final h = await pumpBasira(tester);
      Opacity opacity() => tester.widget<Opacity>(
        find.ancestor(of: _more(h, _top), matching: find.byType(Opacity)).first,
      );
      expect(opacity().opacity, 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(_item(_top)));
      await tester.pump();
      expect(opacity().opacity, 1);
      // The end side: right of the title in English.
      expect(
        tester.getCenter(_more(h, _top)).dx,
        greaterThan(tester.getCenter(_item(_top)).dx),
      );
      await h.tap(_more(h, _top));
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await h.shot('basira/item-menu');
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('REP-BAS-008 below 1280 the ⋯ menu is always shown', (
      tester,
    ) async {
      final h = await pumpBasira(tester, size: DashSize.tablet);
      await h.tap(inPage(find.text('Conversations')));
      final o = tester.widget<Opacity>(
        find.ancestor(of: _more(h, _top), matching: find.byType(Opacity)).first,
      );
      expect(o.opacity, 1);
    });
  });

  group('conversations', () {
    testWidgets('REP-BAS-002/004 the header\'s own refresh re-reads the '
        'list and the open conversation', (tester) async {
      final h = await pumpBasira(tester);
      final refresh = find.descendant(
        of: inPage(find.byType(DashPageHeader)),
        matching: find.bySemanticsLabel(h.t('common.refresh')),
      );
      expect(refresh, findsOneWidget);
      await h.tap(refresh);
      expect(h.server.callsTo(listRoute), hasLength(2));
      expect(h.server.callsTo(convRoute), isEmpty);
      await _openConversation(h, _compare);
      await h.tap(refresh);
      expect(h.server.callsTo(listRoute), hasLength(3));
      expect(h.server.callsTo(convRoute), hasLength(2));
      expect(_title(ownDirection(_compare)), findsOneWidget);
    });

    testWidgets('REP-BAS-007 Arabic: a cut English title keeps its own '
        'direction, so its ellipsis ends it', (tester) async {
      await pumpBasira(tester, locale: 'ar');
      final title = tester.widget<MadarClippedText>(
        find
            .ancestor(
              of: _item(_waste),
              matching: find.byType(MadarClippedText),
            )
            .first,
      );
      expect(title.textDirection, TextDirection.ltr);
      expect(title.textAlign, TextAlign.right);
    });

    testWidgets('REP-BAS-009 resting on a conversation warms its read', (
      tester,
    ) async {
      final h = await pumpBasira(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(_item(_top)));
      await tester.pump(kDashIntentDwell);
      await h.settle();
      expect(h.server.callsTo(convRoute), hasLength(1), reason: 'warmed');
      expect(_title(ownDirection(_top)), findsNothing);
      await h.tap(_item(_top));
      expect(h.server.callsTo(convRoute), hasLength(1));
      expect(
        inTranscript(_own('And how are the branches doing this month?')),
        findsOneWidget,
      );
    });

    testWidgets('REP-BAS-009 a question asked after the warm read makes the '
        'press read again', (tester) async {
      final h = await pumpBasira(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(_item(_top)));
      await tester.pump(kDashIntentDwell);
      await h.settle();
      await mouse.moveTo(Offset.zero);
      await askByTyping(h, 'Top 3 products');
      await h.tap(_item(_top));
      expect(h.server.callsTo(convRoute), hasLength(2));
    });

    testWidgets('REP-BAS-009 opening shows 3 skeletons, then its turns, and '
        'switches the title', (tester) async {
      final s = basiraServer();
      final h = await pumpBasira(tester, server: s.server, db: s.db);
      final gate = s.server.hold('GET', convRoute);
      await _openConversation(h, _top);
      expect(inPage(find.byType(DashSkeleton)), findsNWidgets(3));
      expect(_title(ownDirection(_top)), findsOneWidget);
      gate.release();
      await h.settle();
      expect(inPage(find.byType(DashSkeleton)), findsNothing);
      expect(inTranscript(_own(_top)), findsWidgets);
      expect(
        inTranscript(_own('And how are the branches doing this month?')),
        findsOneWidget,
      );
      await h.shot('basira/history');
    });

    testWidgets('REP-BAS-009 opening aborts the question in flight', (
      tester,
    ) async {
      final h = await pumpBasira(tester);
      final live = mockOf(h).hold();
      await askByTyping(h, 'Top 3 products');
      expect(live.listened, isTrue);
      await _openConversation(h, _compare);
      expect(live.cancelled, isTrue);
      expect(mockOf(h).cancelled, 1);
      expect(inTranscript(_own('Top 3 products')), findsNothing);
    });

    testWidgets('REP-BAS-009 (corrected) a failed open toasts; the '
        'conversation stays marked and the previous transcript stays', (
      tester,
    ) async {
      final s = basiraServer();
      final h = await pumpBasira(tester, server: s.server, db: s.db);
      await _openConversation(h, _top);
      final missing = MockResponse.notFound('Conversation not found');
      s.server.fail('GET', convRoute, missing);
      await _openConversation(h, _compare);
      await h.expectToast(h.refusalWords(missing));
      expect(_title(ownDirection(_compare)), findsOneWidget);
      expect(
        inTranscript(_own('And how are the branches doing this month?')),
        findsOneWidget,
      );
    });

    testWidgets('REP-BAS-010 stored turns redraw their charts, dated; a '
        'turn stored without a snapshot keeps only its prose', (tester) async {
      final h = await pumpBasira(tester);
      await _openConversation(h, _top);
      final cards = inPage(find.byType(BasiraBlockCard));
      expect(cards, findsNWidgets(2));
      expect(pageText('Figures as at 06 Oct, 06:20 PM'), findsOneWidget);
      expect(pageText('Figures as at 06 Oct, 06:24 PM'), findsOneWidget);
      await _openConversation(h, _waste);
      expect(inPage(find.byType(BasiraBlockCard)), findsNothing);
      expect(inPage(find.textContaining('Figures as at')), findsNothing);
      final turn = mockOf(
        h,
      ).turnsOf(mockOf(h).conversationsOf(SeedIds.owner)[2]['id']! as String);
      expect(
        inTranscript(_own(turn.single['answer']! as String)),
        findsOneWidget,
      );
    });

    testWidgets('REP-BAS-011 New conversation aborts, clears the transcript '
        'and the active conversation', (tester) async {
      final h = await pumpBasira(tester);
      await _openConversation(h, _top);
      final live = mockOf(h).hold();
      await askByTyping(h, 'And yesterday?');
      await h.tap(inRail(find.text('New conversation')));
      expect(live.cancelled, isTrue);
      expect(_title('Basira'), findsOneWidget);
      expect(pageText(h.t('basira.welcomeTitle')), findsOneWidget);
      // The next question starts a new conversation.
      await askByTyping(h, 'Top 3 products');
      expect(_body(streams(h).last).containsKey('conversation_id'), isFalse);
    });

    testWidgets('REP-BAS-011 New conversation from the slide-over closes '
        'it', (tester) async {
      final h = await pumpBasira(tester, size: DashSize.phone);
      await h.tap(inPage(find.text('Conversations')));
      await h.tap(inRail(find.text('New conversation')));
      expect(rail, findsNothing);
    });

    testWidgets('REP-BAS-026 Rename: prefilled, Save disabled when blank, '
        'PATCHes the trimmed title and re-reads the list', (tester) async {
      final h = await pumpBasira(tester);
      await h.tap(_more(h, _compare));
      await h.tapText('Rename');
      final dialog = find.byType(DashSurface);
      expect(
        find.descendant(of: dialog, matching: find.text('Rename conversation')),
        findsOneWidget,
      );
      final field = find.descendant(
        of: dialog,
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(field).controller.text, _compare);
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
      await h.shot('basira/rename');
      await h.enterText(field, '   ');
      await h.tap(find.descendant(of: dialog, matching: find.text('Save')));
      expect(dialog, findsOneWidget);
      // Enter on a blank title does nothing either.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(dialog, findsOneWidget);
      final lists = h.server.callsTo(listRoute).length;
      await h.enterText(field, '  Branch race  ');
      await h.tap(find.descendant(of: dialog, matching: find.text('Save')));
      expect(dialog, findsNothing);
      final patch = h.server.callsTo(convRoute, method: 'PATCH').single;
      expect(patch.body, {'title': 'Branch race'});
      expect(h.server.callsTo(listRoute), hasLength(lists + 1));
      expect(_item('Branch race'), findsOneWidget);
    });

    testWidgets('REP-BAS-026 Enter submits; Cancel does nothing', (
      tester,
    ) async {
      final h = await pumpBasira(tester);
      await h.tap(_more(h, _compare));
      await h.tapText('Rename');
      final dialog = find.byType(DashSurface);
      await h.tap(find.descendant(of: dialog, matching: find.text('Cancel')));
      expect(dialog, findsNothing);
      expect(h.server.callsTo(convRoute, method: 'PATCH'), isEmpty);
      await h.tap(_more(h, _compare));
      await h.tapText('Rename');
      final field = find.descendant(
        of: find.byType(DashSurface),
        matching: find.byType(EditableText),
      );
      await h.enterText(field, 'Maadi vs Zamalek');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(h.server.callsTo(convRoute, method: 'PATCH').single.body, {
        'title': 'Maadi vs Zamalek',
      });
    });

    testWidgets('REP-BAS-026 a failed rename is a toast', (tester) async {
      final s = basiraServer();
      final h = await pumpBasira(tester, server: s.server, db: s.db);
      final bad = MockResponse.badRequest('title cannot be empty');
      s.server.fail('PATCH', convRoute, bad);
      await h.tap(_more(h, _compare));
      await h.tapText('Rename');
      await h.tap(
        find.descendant(
          of: find.byType(DashSurface),
          matching: find.text('Save'),
        ),
      );
      await h.expectToast(h.refusalWords(bad));
    });

    testWidgets('REP-BAS-027 Delete asks first; Cancel does nothing', (
      tester,
    ) async {
      final h = await pumpBasira(tester);
      await h.tap(_more(h, _compare));
      await h.tapText('Delete');
      expect(find.text('Delete this conversation?'), findsOneWidget);
      expect(
        find.text(
          'The questions and answers are removed. Your data is not affected.',
        ),
        findsOneWidget,
      );
      await h.shot('basira/delete-confirm');
      await h.tapText('Cancel');
      expect(h.server.callsTo(convRoute, method: 'DELETE'), isEmpty);
      expect(_item(_compare), findsOneWidget);
    });

    testWidgets('REP-BAS-027 deleting the open conversation starts a new '
        'one and re-reads the list', (tester) async {
      final h = await pumpBasira(tester);
      await _openConversation(h, _compare);
      final lists = h.server.callsTo(listRoute).length;
      await h.tap(_more(h, _compare));
      await h.tapText('Delete');
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      expect(h.server.callsTo(convRoute, method: 'DELETE'), hasLength(1));
      expect(h.server.callsTo(listRoute), hasLength(lists + 1));
      expect(_item(_compare), findsNothing);
      expect(_title('Basira'), findsOneWidget);
      expect(pageText(h.t('basira.welcomeTitle')), findsOneWidget);
    });

    testWidgets('REP-BAS-027 deleting another conversation keeps the open '
        'one; a failure is a toast', (tester) async {
      final s = basiraServer();
      final h = await pumpBasira(tester, server: s.server, db: s.db);
      await _openConversation(h, _top);
      final gone = MockResponse.notFound('Conversation not found');
      s.server.fail('DELETE', convRoute, gone);
      await h.tap(_more(h, _compare));
      await h.tapText('Delete');
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      await h.expectToast(h.refusalWords(gone));
      await h.tap(_more(h, _compare));
      await h.tapText('Delete');
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      expect(_item(_compare), findsNothing);
      expect(_title(ownDirection(_top)), findsOneWidget);
    });
  });

  group('asking', () {
    testWidgets('REP-BAS-012 the welcome: title, body and four starters in '
        'two columns from 640', (tester) async {
      await pumpBasira(tester);
      expect(pageText('What would you like to know?'), findsOneWidget);
      expect(
        pageText(
          'Ask in English or Arabic. Every answer comes with the chart and '
          'the exact query behind it.',
        ),
        findsOneWidget,
      );
      final starters = [
        'What sold best last month?',
        'Compare my branches this month',
        'When are we busiest?',
        'What am I wasting the most money on?',
      ];
      for (final s in starters) {
        expect(pageText(s), findsOneWidget);
      }
      final dy = {
        for (final s in starters) tester.getCenter(pageText(s)).dy.round(),
      };
      expect(dy, hasLength(2));
    });

    testWidgets('REP-BAS-012 one column on a phone; a starter asks its '
        'text', (tester) async {
      final h = await pumpBasira(tester, size: DashSize.phone);
      final dy = {
        for (final k in basiraStarters)
          tester.getCenter(pageText(h.t('basira.starters.$k'))).dy.round(),
      };
      expect(dy, hasLength(4));
      await h.tap(pageText('When are we busiest?'));
      expect(_body(streams(h).single)['question'], 'When are we busiest?');
      expect(inPage(find.byType(BasiraHeatmap)), findsOneWidget);
    });

    testWidgets('REP-BAS-012 Arabic starters ask in Arabic', (tester) async {
      final h = await pumpBasira(tester, locale: 'ar');
      // The rail holds a conversation of the same words: tap the starter.
      await h.tap(inTranscript(find.text(h.t('basira.starters.peakHours'))));
      final body = _body(streams(h).single);
      expect(body['question'], h.t('basira.starters.peakHours'));
      expect(body['locale'], 'ar');
    });

    testWidgets('REP-BAS-013/028 the composer: placeholder, disclaimer, Send '
        'disabled while blank', (tester) async {
      final h = await pumpBasira(tester);
      expect(pageText('Ask about sales, staff, stock…'), findsOneWidget);
      expect(
        pageText(
          'Reads your own business figures. Staff names are replaced with '
          'codes before anything leaves.',
        ),
        findsOneWidget,
      );
      await h.tap(inPage(find.bySemanticsLabel('Send')));
      await h.enterText(composer, '   ');
      await h.tap(inPage(find.bySemanticsLabel('Send')));
      expect(streams(h), isEmpty);
    });

    testWidgets(
      'REP-BAS-013 on a desktop Enter sends and Shift+Enter does not',
      (tester) async {
        final h = await pumpBasira(tester);
        await h.enterText(composer, 'Top 3 products');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await h.settle();
        expect(streams(h), isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await h.settle();
        expect(_body(streams(h).single)['question'], 'Top 3 products');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets('REP-BAS-013 on a touch device Enter is a new line', (
      tester,
    ) async {
      expect(defaultTargetPlatform, TargetPlatform.android);
      final h = await pumpBasira(tester, size: DashSize.phone);
      await h.enterText(composer, 'Top 3 products');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle();
      expect(streams(h), isEmpty);
    });

    testWidgets('REP-BAS-013 while an answer streams the box is disabled '
        'and Send spins', (tester) async {
      final h = await pumpBasira(tester);
      final live = mockOf(h).hold();
      await askByTyping(h, 'Top 3 products');
      expect(
        tester
            .widget<TextField>(
              find.ancestor(of: composer, matching: find.byType(TextField)),
            )
            .enabled,
        isFalse,
      );
      // The working line's spinner and Send's.
      expect(inPage(find.byType(CircularProgressIndicator)), findsNWidgets(2));
      await h.tap(inPage(find.bySemanticsLabel('Send')));
      expect(streams(h), hasLength(1));
      live.push({'event': 'error', 'message': 'Model timeout'});
      await live.close();
      await h.settle();
      expect(
        tester
            .widget<TextField>(
              find.ancestor(of: composer, matching: find.byType(TextField)),
            )
            .enabled,
        isTrue,
      );
    });

    testWidgets('REP-BAS-014/033 Ask trims, clears the box, heads an '
        'exchange with the question and posts it with the org and branch '
        'headers', (tester) async {
      final h = await pumpBasira(tester, branchId: SeedIds.zamalek);
      final live = mockOf(h).hold();
      await askByTyping(h, '   Top 3 products  ');
      expect(tester.widget<EditableText>(composer).controller.text, isEmpty);
      expect(inTranscript(_own('Top 3 products')), findsOneWidget);
      final call = streams(h).single;
      expect(_body(call), {'question': 'Top 3 products', 'locale': 'en'});
      expect(call.headers['X-Org-Id'], SeedIds.sabahOrg);
      expect(call.headers['X-Branch-Id'], SeedIds.zamalek);
      await live.close();
      await h.settle();
    });

    testWidgets('REP-BAS-014 a question in an open conversation carries its '
        'id', (tester) async {
      final h = await pumpBasira(tester);
      await _openConversation(h, _top);
      await askByTyping(h, 'And yesterday?');
      final id = mockOf(h)
          .conversationsOf(SeedIds.owner)
          .firstWhere((c) => c['title'] == _top)['id'];
      expect(_body(streams(h).single)['conversation_id'], id);
    });

    testWidgets('REP-BAS-015 the working line: thinking, refining, looking '
        'up', (tester) async {
      final h = await pumpBasira(tester);
      final live = mockOf(h).hold();
      await askByTyping(h, 'Top 3 products');
      expect(pageText('Working on it…'), findsOneWidget);
      live.push({'event': 'started'});
      live.push({'event': 'thinking', 'step': 1});
      await h.settle();
      expect(pageText('Working on it…'), findsOneWidget);
      live.push({
        'event': 'querying',
        'title': 'Top products',
        'dataset': 'sales_items',
      });
      await h.settle();
      expect(pageText('Looking up Top products…'), findsOneWidget);
      live.push({'event': 'thinking', 'step': 2});
      await h.settle();
      expect(pageText('Refining the query…'), findsOneWidget);
      live.push({'event': 'querying', 'dataset': 'sales_items'});
      await h.settle();
      expect(pageText('Looking up sales_items…'), findsOneWidget);
      await live.close();
      await h.settle();
    });

    testWidgets('REP-BAS-016 a result lands as a card at once; the answer '
        'replaces the cards with the final list', (tester) async {
      final h = await pumpBasira(tester);
      final live = mockOf(h).hold();
      await askByTyping(h, 'Top 3 products');
      live.push({'event': 'result', 'block': _block('Streamed')});
      await h.settle();
      expect(inPage(find.byType(BasiraBlockCard)), findsOneWidget);
      expect(inTranscript(_own('Streamed')), findsOneWidget);
      expect(pageText('Working on it…'), findsOneWidget);
      live.push('data: {not json');
      live.push({
        'event': 'answer',
        'response': {
          'kind': 'answer',
          'text': 'Latte led the week.',
          'results': [_block('Final A'), _block('Final B')],
          'provider': 'gemini',
          'timezone': 'Africa/Cairo',
        },
      });
      await live.close();
      await h.settle();
      expect(inTranscript(_own('Streamed')), findsNothing);
      expect(inPage(find.byType(BasiraBlockCard)), findsNWidgets(2));
      expect(inTranscript(_own('Latte led the week.')), findsOneWidget);
      expect(pageText('Working on it…'), findsNothing);
    });

    testWidgets('REP-BAS-016 a clarify is muted with no charts; incomplete '
        'shows its text and results', (tester) async {
      final h = await pumpBasira(tester);
      await askByTyping(h, 'Tell me something');
      final clarify = tester.widget<Text>(
        inTranscript(
          _own('Do you mean sales, orders or stock — and over which period?'),
        ),
      );
      expect(
        clarify.style!.color,
        tester.element(basiraPage).madarColors.textSecondary,
      );
      expect(inPage(find.byType(BasiraBlockCard)), findsNothing);
      await askByTyping(h, 'How much payroll did we pay?');
      expect(inPage(find.byType(BasiraBlockCard)), findsOneWidget);
      expect(
        inTranscript(
          _own(
            "I can't read payroll — Basira reads sales, orders, menu and stock "
            'only. Here is revenue by branch for this month instead.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-BAS-017 a new conversation becomes active and the list '
        'is re-read; asking in one re-reads it too', (tester) async {
      final h = await pumpBasira(tester);
      await askByTyping(h, 'Top 3 products');
      expect(h.server.callsTo(listRoute), hasLength(2));
      expect(_title(ownDirection('Top 3 products')), findsOneWidget);
      expect(_item('Top 3 products'), findsOneWidget);
      expect(inRail(find.text('1 question · 08 Oct 2026')), findsOneWidget);
      await askByTyping(h, 'And the bottom 3?');
      expect(h.server.callsTo(listRoute), hasLength(3));
      final id = _body(streams(h).last)['conversation_id'];
      expect(id, isNotNull);
      expect(inRail(find.text('2 questions · 08 Oct 2026')), findsOneWidget);
    });

    testWidgets('REP-BAS-018 an error frame is a failure box with the '
        'server\'s sentence and Retry', (tester) async {
      final h = await pumpBasira(tester);
      mockOf(h).script([
        {'event': 'started'},
        {'event': 'thinking', 'step': 1},
        {
          'event': 'error',
          'message': 'The model took too long. Try a narrower question.',
        },
      ]);
      await askByTyping(h, 'Top 3 products');
      expect(
        inTranscript(_own('The model took too long. Try a narrower question.')),
        findsOneWidget,
      );
      expect(pageText('Retry'), findsOneWidget);
      expect(pageText('Working on it…'), findsNothing);
      await h.shot('basira/failure');
    });

    testWidgets('REP-BAS-018 (corrected) Retry asks again as a new exchange '
        'below; the failed one stays', (tester) async {
      final h = await pumpBasira(tester);
      mockOf(h).script([
        {'event': 'error', 'message': 'Model timeout'},
      ]);
      await askByTyping(h, 'Top 3 products');
      await h.tap(pageText('Retry'));
      expect(streams(h), hasLength(2));
      expect(_body(streams(h).last)['question'], 'Top 3 products');
      expect(inTranscript(_own('Top 3 products')), findsNWidgets(2));
      expect(inTranscript(_own('Model timeout')), findsOneWidget);
      expect(inPage(find.byType(BasiraBlockCard)), findsOneWidget);
    });

    testWidgets('REP-BAS-018 Retry is ignored while another question '
        'streams', (tester) async {
      final h = await pumpBasira(tester);
      mockOf(h).script([
        {'event': 'error', 'message': 'Model timeout'},
      ]);
      await askByTyping(h, 'Top 3 products');
      final live = mockOf(h).hold();
      await askByTyping(h, 'When are we busiest?');
      await h.tap(pageText('Retry'));
      expect(streams(h), hasLength(2));
      await live.close();
      await h.settle();
    });

    testWidgets('REP-BAS-018 a refusal before the stream shows the server\'s '
        'words', (tester) async {
      final h = await pumpBasira(tester);
      final bad = MockResponse.badRequest(
        'question is too long (max 1000 characters)',
      );
      mockOf(h).refuseNext(bad);
      await askByTyping(h, 'Top 3 products');
      expect(inTranscript(_own(h.refusalWords(bad))), findsOneWidget);
    });

    testWidgets('REP-BAS-018 (refusal) without reports.read the question '
        'fails with the server\'s words', (tester) async {
      final h = await pumpBasira(tester);
      final denied = MockResponse.denied('reports.read');
      mockOf(h).refuseNext(denied);
      await askByTyping(h, 'Top 3 products');
      expect(inTranscript(_own(h.refusalWords(denied))), findsOneWidget);
    });

    testWidgets('REP-BAS-018 an HTTP error with no words is "Request failed '
        '(<status>)"', (tester) async {
      final h = await pumpBasira(tester);
      mockOf(h).refuseNext(MockResponse.text('Bad gateway', status: 502));
      await askByTyping(h, 'Top 3 products');
      expect(inTranscript(_own('Request failed (502)')), findsOneWidget);
    });

    testWidgets('REP-BAS-018 a dropped connection is a failure box', (
      tester,
    ) async {
      final h = await pumpBasira(tester);
      final live = mockOf(h).hold();
      await askByTyping(h, 'Top 3 products');
      live.drop('The connection was lost.');
      await h.settle();
      expect(inTranscript(_own('The connection was lost.')), findsOneWidget);
    });

    testWidgets('REP-BAS-018 (divergence) a stream that closes with no '
        'answer says it could not be answered', (tester) async {
      final h = await pumpBasira(tester);
      mockOf(h).script([
        {'event': 'started'},
        {'event': 'thinking', 'step': 1},
      ]);
      await askByTyping(h, 'Top 3 products');
      expect(
        inTranscript(_own('That question could not be answered')),
        findsOneWidget,
      );
      expect(pageText('Working on it…'), findsNothing);
    });

    testWidgets('REP-BAS-018 an aborted question shows nothing', (
      tester,
    ) async {
      final h = await pumpBasira(tester);
      final live = mockOf(h).hold();
      await askByTyping(h, 'Top 3 products');
      await h.tap(inRail(find.text('New conversation')));
      live.drop();
      await h.settle();
      expect(inPage(find.text('Retry')), findsNothing);
      expect(pageText(h.t('basira.welcomeTitle')), findsOneWidget);
    });

    testWidgets('REP-BAS-029 the transcript follows the newest exchange', (
      tester,
    ) async {
      final h = await pumpBasira(tester);
      for (final q in [
        'Top 3 products',
        'Show the daily revenue trend',
        'When are we busiest?',
      ]) {
        await askByTyping(h, q);
        final pos = tester
            .widget<SingleChildScrollView>(find.byKey(BasiraPage.transcriptKey))
            .controller!
            .position;
        expect(pos.pixels, pos.maxScrollExtent, reason: q);
      }
    });

    testWidgets('REP-BAS-030 leaving the page aborts the question in '
        'flight', (tester) async {
      final h = await pumpBasira(tester);
      final live = mockOf(h).hold();
      await askByTyping(h, 'Top 3 products');
      h.allowUnmatched = true;
      await h.go('/');
      expect(live.cancelled, isTrue);
      expect(mockOf(h).cancelled, 1);
    });

    testWidgets('REP-BAS-031 the question is a heading, the answer prose '
        'under it, then the cards', (tester) async {
      final h = await pumpBasira(tester);
      await askByTyping(h, 'Top 3 products');
      final q = inTranscript(_own('Top 3 products'));
      expect(tester.getSemantics(q).flagsCollection.isHeader, isTrue);
      final answer = inPage(find.textContaining('led September'));
      expect(
        tester.getTopLeft(answer).dy,
        greaterThan(tester.getTopLeft(q).dy),
      );
      expect(
        tester.getTopLeft(inPage(find.byType(BasiraBlockCard))).dy,
        greaterThan(tester.getTopLeft(answer).dy),
      );
    });

    testWidgets('REP-BAS-031 each exchange fades in over 180 ms', (
      tester,
    ) async {
      final h = await pumpBasira(tester, reducedMotion: false);
      final live = mockOf(h).hold();
      await h.enterText(composer, 'Top 3 products');
      await tester.tap(inPage(find.bySemanticsLabel('Send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final mid = tester.widget<Opacity>(
        find
            .ancestor(
              of: inTranscript(_own('Top 3 products')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(mid.opacity, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 120));
      final done = tester.widget<Opacity>(
        find
            .ancestor(
              of: inTranscript(_own('Top 3 products')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(done.opacity, 1);
      await live.close();
      await h.settle();
    });

    testWidgets('REP-BAS-033 the branch picked in the scope bar scopes the '
        'answer; changing it re-asks nothing', (tester) async {
      final h = await pumpBasira(tester, branchId: SeedIds.maadi);
      await askByTyping(h, 'How much did we take today?');
      expect(streams(h).single.headers['X-Branch-Id'], SeedIds.maadi);
      final badge = inPage(find.byType(BasiraScopeBadge));
      expect(
        find.descendant(of: badge, matching: find.text('Maadi')),
        findsOneWidget,
      );
      final lists = h.server.callsTo(listRoute).length;
      await h.container.read(scopeProvider.notifier).setBranch(null);
      await h.settle();
      expect(streams(h), hasLength(1));
      expect(h.server.callsTo(listRoute), hasLength(lists));
      await askByTyping(h, 'How much did we take today?');
      expect(streams(h).last.headers.containsKey('X-Branch-Id'), isFalse);
      expect(inPage(find.byType(BasiraScopeBadge)), findsOneWidget);
    });

    testWidgets('REP-BAS-023 the charts are drawn left to right in Arabic', (
      tester,
    ) async {
      final h = await pumpBasira(tester, locale: 'ar');
      await askByTyping(h, 'Show the daily revenue trend');
      final chart = inPage(find.byType(BasiraAreaChart));
      expect(
        Directionality.of(
          tester.element(
            find.descendant(of: chart, matching: find.byType(SizedBox)).first,
          ),
        ),
        TextDirection.ltr,
      );
    });
  });
}

Map<String, Object?> _block(String title) => {
  'title': title,
  'spec': {'dataset': 'sales_items'},
  'columns': [
    {'key': 'item', 'label': 'Item', 'kind': 'label'},
    {'key': 'revenue', 'label': 'Revenue', 'kind': 'money'},
  ],
  'rows': [
    {'item': 'Latte', 'revenue': 120000},
  ],
  'row_count': 1,
  'truncated': false,
  'grain': 'categorical',
  'viz': 'table',
  'scope': {'all_branches': true, 'branches': <String>[], 'label': 'All'},
};
