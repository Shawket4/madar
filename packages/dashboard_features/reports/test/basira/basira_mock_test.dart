// The Basira mock against the backend's rules (MadarRust ai/{handlers,
// stream,store}.rs) and against the seed's own figures.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_reports/src/mock/basira_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

({MockServer server, DashboardApi api, BasiraMock mock}) _setUp([
  Persona persona = Persona.owner,
]) {
  final s = basiraServer(persona: persona);
  return (
    server: s.server,
    api: DashboardApi(s.server),
    mock: basiraMockOf(s.server),
  );
}

Future<List<Map<String, Object?>>> _frames(
  DashboardApi api,
  String question, {
  String? conversationId,
  String locale = 'en',
}) async => [
  for (final raw
      in await api.ai
          .chatStream(
            body: AiChatRequest(
              question: question,
              conversationId: conversationId,
              locale: locale,
            ),
          )
          .toList())
    (jsonDecode(raw) as Map).cast<String, Object?>(),
];

Future<ApiException> _refusal(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

void main() {
  test('every call needs reports.read and an org-scoped account', () async {
    final p = _setUp(Persona.platform);
    final e = await _refusal(() => p.api.ai.listConversations());
    expect(e.status, 403);
    expect(
      e.message,
      endsWith('AI analytics requires an organization-scoped account'),
    );
    final s = await _refusal(
      () => p.api.ai
          .chatStream(body: const AiChatRequest(question: 'Top products'))
          .toList(),
    );
    expect(s.status, 403);
  });

  test('the list is the caller\'s own, newest first, limited', () async {
    final p = _setUp();
    final all = await p.api.ai.listConversations(limit: 30);
    expect(
      [for (final c in all.conversations) c.title],
      [
        'Top 5 products last month',
        'Compare Maadi and Zamalek this month',
        'How much did we waste in the last 30 days?',
        'متى تكون ساعات الذروة لدينا؟',
        'Show the daily revenue trend',
      ],
    );
    final two = await p.api.ai.listConversations(limit: 2, offset: 1);
    expect(
      [for (final c in two.conversations) c.title],
      [
        'Compare Maadi and Zamalek this month',
        'How much did we waste in the last 30 days?',
      ],
    );
    final m = _setUp(Persona.manager);
    final mine = await m.api.ai.listConversations();
    expect(
      [for (final c in mine.conversations) c.title],
      ['How long is prep taking at Zamalek?'],
    );
  });

  test('another person\'s conversation is not found', () async {
    final owner = _setUp();
    final id = (await owner.api.ai.listConversations()).conversations.first.id;
    final m = _setUp(Persona.manager);
    final e = await _refusal(() => m.api.ai.getConversation(id: id));
    expect(e.status, 404);
    expect(e.message, endsWith('Conversation not found'));
    final s = await _refusal(
      () => _frames(m.api, 'Top products', conversationId: id),
    );
    expect(s.status, 404);
  });

  test('a question is checked before the stream opens', () async {
    final p = _setUp();
    final blank = await _refusal(() => _frames(p.api, '   '));
    expect(blank.status, 400);
    expect(blank.message, endsWith('question cannot be empty'));
    final long = await _refusal(() => _frames(p.api, 'x' * 1001));
    expect(
      long.message,
      endsWith('question is too long (max 1000 characters)'),
    );
    expect(p.mock.completed, 0);
  });

  test('a turn streams started, thinking, querying, result, then one '
      'answer, and is stored with a snapshot', () async {
    final p = _setUp();
    final frames = await _frames(p.api, 'Top 3 products');
    expect(
      [for (final f in frames) f['event']],
      ['started', 'thinking', 'querying', 'result', 'answer'],
    );
    final response = frames.last['response']! as Map;
    final id = response['conversation_id']! as String;
    final detail = await p.api.ai.getConversation(id: id);
    expect(detail.title, 'Top 3 products');
    expect(detail.turnCount, 1);
    final stored = (detail.turns.single.specs! as List).single as Map;
    expect(stored['captured_at'], isNotNull);
    expect(((stored['snapshot']! as Map)['rows']! as List), hasLength(3));
    // The next question continues it.
    await _frames(p.api, 'And the bottom 3?', conversationId: id);
    expect((await p.api.ai.getConversation(id: id)).turnCount, 2);
  });

  test(
    'rename trims and refuses a blank title; delete removes the turns',
    () async {
      final p = _setUp();
      final id = (await p.api.ai.listConversations()).conversations.first.id;
      final e = await _refusal(
        () => p.api.ai.renameConversation(
          id: id,
          body: const RenameConversationRequest(title: '  '),
        ),
      );
      expect(e.status, 400);
      expect(e.message, endsWith('title cannot be empty'));
      await p.api.ai.renameConversation(
        id: id,
        body: const RenameConversationRequest(title: 'Best sellers'),
      );
      expect(
        (await p.api.ai.listConversations()).conversations.first.title,
        'Best sellers',
      );
      await p.api.ai.deleteConversation(id: id);
      expect(p.mock.turnsOf(id), isEmpty);
      final gone = await _refusal(() => p.api.ai.getConversation(id: id));
      expect(gone.status, 404);
    },
  );

  test('titles are cut at 80 characters on a word', () {
    final long = List.filled(20, 'espresso').join(' ');
    final title = basiraTitleFrom(long);
    expect(title.endsWith('…'), isTrue);
    expect(title.runes.length, lessThanOrEqualTo(81));
    expect(title.contains('espress…'), isFalse);
  });

  test(
    'the payment mix and the daily trend agree over the same 30 days',
    () async {
      final p = _setUp();
      Future<int> total(String question, String key) async {
        final frames = await _frames(p.api, question);
        final block =
            ((frames.last['response']! as Map)['results']! as List).single
                as Map;
        return [
          for (final r in block['rows']! as List) (r as Map)[key] as int? ?? 0,
        ].fold<int>(0, (a, b) => a + b);
      }

      final mix = await total('Payment mix this month', 'revenue');
      final trend = await total('Show the daily revenue trend', 'revenue');
      expect(mix, greaterThan(0));
      expect(mix, trend);
    },
  );

  test('a branch named in the question scopes the answer; one not found '
      'says so', () async {
    final p = _setUp();
    Map<String, Object?> scope(List<Map<String, Object?>> frames) =>
        ((((frames.last['response']! as Map)['results']! as List).first
                    as Map)['scope']!
                as Map)
            .cast();
    final named = scope(await _frames(p.api, 'Top 3 products at Maadi'));
    expect(named['all_branches'], isFalse);
    expect(named['label'], 'Maadi');
    final unknown = scope(
      await _frames(p.api, 'Top 3 products at our Dokki branch'),
    );
    expect(unknown['unmatched_branch'], 'Dokki');
    expect(unknown['all_branches'], isTrue);
  });
}
