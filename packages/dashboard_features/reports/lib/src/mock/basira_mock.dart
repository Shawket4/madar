/// The mock backend for Basira (REP-BAS): `/ai/conversations` (list, read,
/// rename, delete), `POST /ai/chat/stream` (the streamed turn) and
/// `POST /ai/chat` (the same turn in one body).
///
/// Behaves like MadarRust `ai/{handlers,stream,store}.rs`:
/// - every call needs `reports.read` AND an org-scoped account (a platform
///   admin is refused "AI analytics requires an organization-scoped
///   account");
/// - conversations are private to the person who made them (another
///   person's id is a 404 "Conversation not found"), listed most recently
///   used first, titled from the first question (80 characters, cut on a
///   word), renamed only to a non-blank title;
/// - a turn is validated BEFORE the stream opens (blank question, longer
///   than 1000 characters, a conversation that is not yours: an HTTP error);
///   then `started`, `thinking`, `querying`, `result` … and one terminal
///   `answer` (or `error`) frame;
/// - the answer is scoped like `analytics::scope::resolve`: a branch the
///   question names (within what the person may see), else the selected
///   branch (`X-Branch-Id`), else every branch they may see; a branch named
///   but not found falls back and says so (`unmatched_branch`);
/// - the figures come from the core seed's orders (the area's sold set) and
///   the area seed's ingredients, so they agree with the other reports;
/// - a finished turn is stored with a snapshot of its blocks (a new
///   conversation is created lazily, and its id arrives on `answer`).
///
/// Tests steer it through [basiraMockOf]: script the next stream's frames,
/// hold a stream open and push frames by hand, refuse the next turn before
/// it streams, and see which streams were cancelled.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show DashFormat;

import '../area_seed.dart';

const String _conversations = 'ai_conversations';
const String _turns = 'ai_turns';

/// The longest question the backend takes.
const int basiraMaxQuestion = 1000;

/// The longest stored title (`store::MAX_TITLE_LEN`).
const int basiraMaxTitle = 80;

final Expando<BasiraMock> _mocks = Expando<BasiraMock>('basira');

/// The Basira mock registered on [server] (tests steer it through this).
BasiraMock basiraMockOf(MockServer server) =>
    _mocks[server] ??
    (throw StateError('registerBasiraMocks was not called on this server'));

void registerBasiraMocks(MockServer server, MockDb db) {
  final mock = BasiraMock._(server, db);
  _mocks[server] = mock;
  mock._seed();
  mock._register();
}

/// A stream a test drives by hand ([BasiraMock.hold]).
class BasiraLiveStream {
  BasiraLiveStream._();

  final StreamController<String> _c = StreamController<String>();
  bool _listened = false;
  bool _cancelled = false;

  /// The page started reading it.
  bool get listened => _listened;

  /// The page stopped reading before it closed (an abort).
  bool get cancelled => _cancelled;

  /// Sends one frame: a map (JSON-encoded) or raw text as it is.
  void push(Object frame) {
    if (_c.isClosed) return;
    _c.add(frame is String ? frame : jsonEncode(frame));
  }

  /// The connection drops mid-stream (a transport failure).
  void drop([String message = 'Connection reset by peer']) {
    if (_c.isClosed) return;
    _c.addError(ApiException(status: 0, message: message));
    unawaited(_c.close());
  }

  /// The server closes the stream.
  Future<void> close() async {
    if (!_c.isClosed) await _c.close();
  }
}

/// What the Basira mock holds and what tests may ask of it.
class BasiraMock {
  BasiraMock._(this.server, this.db);

  final MockServer server;
  final MockDb db;

  final List<List<Object>> _scripts = [];
  final List<BasiraLiveStream> _held = [];
  MockResponse? _refuseNext;

  /// Streams the page stopped reading before they finished (aborts).
  int cancelled = 0;

  /// Streams that ran to their end.
  int completed = 0;

  /// The next turn streams exactly [frames] (maps are JSON-encoded, strings
  /// go as they are) and nothing is stored.
  void script(List<Object> frames) => _scripts.add(frames);

  /// The next turn's stream stays open until the test pushes and closes it.
  BasiraLiveStream hold() {
    final live = BasiraLiveStream._();
    _held.add(live);
    return live;
  }

  /// The next turn is refused before its stream opens.
  void refuseNext(MockResponse response) => _refuseNext = response;

  /// The conversations of [userId], as stored (newest use first).
  List<MockRow> conversationsOf(String userId) {
    final rows = [
      for (final c in db[_conversations].rows)
        if (c['user_id'] == userId) c,
    ]..sort((a, b) => _usedAt(b).compareTo(_usedAt(a)));
    return rows;
  }

  /// The stored turns of [conversationId], oldest first.
  List<MockRow> turnsOf(String conversationId) => [
    for (final t in db[_turns].rows)
      if (t['conversation_id'] == conversationId) t,
  ]..sort((a, b) => (a['seq']! as int).compareTo(b['seq']! as int));

  static String _usedAt(MockRow c) =>
      (c['last_turn_at'] ?? c['created_at'])! as String;

  // ── routes ──────────────────────────────────────────────────────────────

  void _register() {
    server.on('GET', '/ai/conversations', (req) {
      final user = _caller(req);
      final limit = (req.qInt('limit') ?? 30).clamp(1, 100);
      final offset = (req.qInt('offset') ?? 0).clamp(0, 1 << 30);
      final mine = conversationsOf(user);
      return MockResponse.ok({
        'conversations': [
          for (final c in mine.skip(offset).take(limit)) _summary(c),
        ],
      });
    });

    server.on('GET', '/ai/conversations/{id}', (req) {
      final user = _caller(req);
      final c = _owned(req.param('id'), user);
      final limit = (req.qInt('limit') ?? 50).clamp(1, 200);
      final turns = turnsOf(c['id']! as String);
      final recent = turns.length > limit
          ? turns.sublist(turns.length - limit)
          : turns;
      return MockResponse.ok({
        ..._summary(c),
        'condensed': ?c['summary'],
        'turns': [for (final t in recent) _turnJson(t)],
      });
    });

    server.on('PATCH', '/ai/conversations/{id}', (req) {
      final user = _caller(req);
      final title = req.json['title'];
      if (title is! String) {
        req.badRequest(
          'Json deserialize error: missing field `title` at line 1 column 2',
        );
      }
      final c = _owned(req.param('id'), user);
      if (title.trim().isEmpty) req.badRequest('title cannot be empty');
      c['title'] = basiraTitleFrom(title);
      c['updated_at'] = db.nowIso;
      return MockResponse.empty();
    });

    server.on('DELETE', '/ai/conversations/{id}', (req) {
      final user = _caller(req);
      final c = _owned(req.param('id'), user);
      final id = c['id']! as String;
      db[_turns].removeWhere((t) => t['conversation_id'] == id);
      db[_conversations].delete(id);
      return MockResponse.empty();
    });

    server.onStream('POST', '/ai/chat/stream', (req) {
      final turn = _prepare(req);
      final scripted = _scripts.isEmpty ? null : _scripts.removeAt(0);
      if (scripted != null) return _scripted(scripted);
      final live = _held.isEmpty ? null : _held.removeAt(0);
      if (live != null) return _live(live);
      return _answer(turn);
    });

    server.on('POST', '/ai/chat', (req) {
      final turn = _prepare(req);
      final plan = _plan(turn);
      final response = _finish(turn, plan);
      return MockResponse.ok(response);
    });
  }

  /// `conversation_caller`: authenticated, `reports.read`, org-scoped.
  String _caller(MockRequest req) {
    req.requireCap('reports.read');
    if (req.persona.isPlatform || req.persona.orgId == null) {
      req.fail(
        MockResponse.forbidden(
          'AI analytics requires an organization-scoped account',
        ),
      );
    }
    return req.persona.userId;
  }

  /// The caller's conversation [id], or a 404 (another person's too).
  MockRow _owned(String id, String userId) {
    final c = db[_conversations].find(id);
    if (c == null || c['user_id'] != userId) {
      throw MockHttpError(MockResponse.notFound('Conversation not found'));
    }
    return c;
  }

  Map<String, Object?> _summary(MockRow c) => {
    'id': c['id'],
    'title': c['title'],
    'turn_count': c['turn_count'],
    'last_turn_at': ?c['last_turn_at'],
    'created_at': c['created_at'],
    'compacted': c['compacted'] ?? false,
  };

  Map<String, Object?> _turnJson(MockRow t) => {
    'id': t['id'],
    'seq': t['seq'],
    'question': t['question'],
    'answer': ?t['answer'],
    'kind': t['kind'],
    'specs': t['specs'],
    'provider': ?t['provider'],
    'created_at': t['created_at'],
  };

  // ── a turn ──────────────────────────────────────────────────────────────

  /// `prepare_turn`: everything that fails cheaply fails here, before the
  /// stream opens.
  _Turn _prepare(MockRequest req) {
    final user = _caller(req);
    final refusal = _refuseNext;
    if (refusal != null) {
      _refuseNext = null;
      req.fail(refusal);
    }
    final raw = req.json['question'];
    if (raw is! String) {
      req.badRequest(
        'Json deserialize error: missing field `question` at line 1 column 2',
      );
    }
    final question = raw.trim();
    if (question.isEmpty) req.badRequest('question cannot be empty');
    if (question.runes.length > basiraMaxQuestion) {
      req.badRequest(
        'question is too long (max $basiraMaxQuestion characters)',
      );
    }
    final convId = req.json['conversation_id'];
    if (convId is String) _owned(convId, user);
    final locale = req.json['locale'] == 'ar' ? 'ar' : 'en';
    final accessible = [
      for (final b in SeedIds.sabahBranches)
        if (req.persona.seesBranch(b)) b,
    ];
    final header = req.branchHeader;
    return _Turn(
      question: question,
      locale: locale,
      userId: user,
      orgId: req.orgId ?? SeedIds.sabahOrg,
      conversationId: convId is String ? convId : null,
      accessible: accessible,
      selected: header != null && accessible.contains(header) ? header : null,
      now: req.now,
    );
  }

  Stream<String> _scripted(List<Object> frames) async* {
    var done = false;
    try {
      for (final f in frames) {
        yield f is String ? f : jsonEncode(f);
      }
      done = true;
      completed++;
    } finally {
      if (!done) cancelled++;
    }
  }

  Stream<String> _live(BasiraLiveStream live) {
    live._c.onListen = () {
      live._listened = true;
    };
    live._c.onCancel = () {
      if (!live._c.isClosed) {
        live._cancelled = true;
        cancelled++;
      }
    };
    return live._c.stream;
  }

  Stream<String> _answer(_Turn turn) async* {
    var done = false;
    try {
      final plan = _plan(turn);
      yield jsonEncode({
        'event': 'started',
        'conversation_id': turn.conversationId,
      });
      var step = 1;
      yield jsonEncode({'event': 'thinking', 'step': step});
      for (final (i, b) in plan.blocks.indexed) {
        if (i > 0) yield jsonEncode({'event': 'thinking', 'step': ++step});
        yield jsonEncode({
          'event': 'querying',
          'title': ?b['title'],
          'dataset': (b['spec']! as Map)['dataset'],
        });
        yield jsonEncode({'event': 'result', 'block': b});
      }
      final response = _finish(turn, plan);
      yield jsonEncode({'event': 'answer', 'response': response});
      done = true;
      completed++;
    } finally {
      if (!done) cancelled++;
    }
  }

  /// Stores the turn (creating the conversation on the first one) and
  /// returns the `AiChatResponse` body.
  Map<String, Object?> _finish(_Turn turn, _Plan plan) {
    final now = turn.now.toIso8601String();
    var c = turn.conversationId == null
        ? null
        : db[_conversations].find(turn.conversationId!);
    c ??= db[_conversations].insert({
      'org_id': turn.orgId,
      'user_id': turn.userId,
      'title': basiraTitleFrom(turn.question),
      'locale': turn.locale,
      'turn_count': 0,
      'compacted': false,
      'created_at': now,
    });
    final seq = (c['turn_count']! as int) + 1;
    db[_turns].insert({
      'conversation_id': c['id'],
      'seq': seq,
      'question': turn.question,
      'answer': plan.kind == 'clarify' ? plan.clarify : plan.text,
      'kind': plan.kind,
      'specs': [for (final b in plan.blocks) storedQuery(b, now)],
      'provider': 'gemini',
      'created_at': now,
    });
    c
      ..['turn_count'] = seq
      ..['last_turn_at'] = now
      ..['updated_at'] = now;
    return {
      'kind': plan.kind,
      if (plan.kind == 'clarify')
        'question': plan.clarify
      else ...{
        'text': plan.text,
        'results': plan.blocks,
      },
      'conversation_id': c['id'],
      'provider': 'gemini',
      'timezone': MockClock.timezone,
    };
  }

  // ── the seeded history ────────────────────────────────────────────────

  void _seed() {
    db.lazyTable(_conversations, () => _history().$1);
    db.lazyTable(_turns, () => _history().$2);
  }

  (List<MockRow>, List<MockRow>)? _seeded;

  (List<MockRow>, List<MockRow>) _history() => _seeded ??= _buildHistory();

  (List<MockRow>, List<MockRow>) _buildHistory() {
    final convs = <MockRow>[];
    final turns = <MockRow>[];
    void conv(
      String key,
      String userId,
      List<String> access,
      List<(String question, String locale, DateTime at, bool snapshot)> qs,
    ) {
      final id = mockUuid('basira:conversation:$key');
      final first = qs.first;
      for (final (i, (q, locale, at, snapshot)) in qs.indexed) {
        final turn = _Turn(
          question: q,
          locale: locale,
          userId: userId,
          orgId: SeedIds.sabahOrg,
          conversationId: id,
          accessible: access,
          now: at,
        );
        final plan = _plan(turn);
        final iso = at.toIso8601String();
        turns.add({
          'id': mockUuid('basira:turn:$key:$i'),
          'conversation_id': id,
          'seq': i + 1,
          'question': q,
          'answer': plan.kind == 'clarify' ? plan.clarify : plan.text,
          'kind': plan.kind,
          'specs': [
            for (final b in plan.blocks)
              snapshot
                  ? storedQuery(b, iso)
                  // Stored before snapshots existed: the spec alone.
                  : {
                      'title': b['title'],
                      'preset_id': b['preset_id'],
                      'spec': b['spec'],
                    },
          ],
          'provider': 'gemini',
          'created_at': iso,
        });
      }
      convs.add({
        'id': id,
        'org_id': SeedIds.sabahOrg,
        'user_id': userId,
        'title': basiraTitleFrom(first.$1),
        'locale': first.$2,
        'turn_count': qs.length,
        'last_turn_at': qs.last.$3.toIso8601String(),
        'compacted': false,
        'created_at': first.$3.toIso8601String(),
        'updated_at': qs.last.$3.toIso8601String(),
      });
    }

    final all = SeedIds.sabahBranches;
    conv('top-products', SeedIds.owner, all, [
      (
        'Top 5 products last month',
        'en',
        MockClock.fromCairo(2026, 10, 6, 18, 20),
        true,
      ),
      (
        'And how are the branches doing this month?',
        'en',
        MockClock.fromCairo(2026, 10, 6, 18, 24),
        true,
      ),
    ]);
    conv('maadi-zamalek', SeedIds.owner, all, [
      (
        'Compare Maadi and Zamalek this month',
        'en',
        MockClock.fromCairo(2026, 10, 3, 9, 12),
        true,
      ),
    ]);
    conv('waste-september', SeedIds.owner, all, [
      (
        'How much did we waste in the last 30 days?',
        'en',
        MockClock.fromCairo(2026, 9, 27, 21, 5),
        false,
      ),
    ]);
    conv('peak-ar', SeedIds.owner, all, [
      (
        'متى تكون ساعات الذروة لدينا؟',
        'ar',
        MockClock.fromCairo(2026, 9, 20, 11, 40),
        true,
      ),
    ]);
    conv('daily-revenue', SeedIds.owner, all, [
      (
        'Show the daily revenue trend',
        'en',
        MockClock.fromCairo(2026, 9, 15, 16, 2),
        true,
      ),
    ]);
    conv(
      'zamalek-prep',
      SeedIds.manager,
      [SeedIds.zamalek],
      [
        (
          'How long is prep taking at Zamalek?',
          'en',
          MockClock.fromCairo(2026, 10, 7, 14, 30),
          true,
        ),
      ],
    );
    return (convs, turns);
  }

  // ── the agent: a question → its blocks and its words ──────────────────

  _Plan _plan(_Turn t) {
    final q = t.question.toLowerCase();
    bool has(List<String> words) => words.any(q.contains);
    final ar = t.locale == 'ar';
    if (has(['payroll', 'salary', 'salaries', 'wages', 'رواتب', 'مرتبات'])) {
      final b = _branchRevenue(t);
      return _Plan.incomplete(
        ar
            ? 'لا أستطيع قراءة الرواتب — بصيرة تقرأ المبيعات والطلبات والقائمة والمخزون فقط. إليك الإيراد حسب الفرع لهذا الشهر بدلًا منها.'
            : "I can't read payroll — Basira reads sales, orders, menu and stock only. Here is revenue by branch for this month instead.",
        [b.block],
      );
    }
    if (has(['wast', 'هدر', 'نخسر', 'الهالك'])) return _waste(t);
    if (has(['busiest', 'peak', 'rush', 'الذروة', 'زحمة', 'الزحمة'])) {
      return _peak(t);
    }
    if (has(['refund', 'استرجاع', 'مرتجع'])) return _refunds(t);
    if (has(['every order', 'all orders', 'list orders', 'كل الطلبات'])) {
      return _orderList(t);
    }
    if (has(['prep', 'how long', 'wait', 'التحضير', 'الانتظار'])) {
      return _prep(t);
    }
    if (has(['pay', 'cash', 'card', 'الدفع', 'كاش', 'نقد'])) {
      return _payments(t);
    }
    if (has(['trend', 'daily', 'per day', 'over time', 'اتجاه', 'يومي'])) {
      return _trend(t);
    }
    if (has([
      'sold best',
      'best sell',
      'best-sell',
      'top',
      'popular',
      'أكثر',
    ])) {
      return _topProducts(t);
    }
    if (has(['compare', 'branches', 'قارن', 'الفروع', 'بالفروع'])) {
      final b = _branchRevenue(t);
      return _Plan.answer(b.text, [b.block]);
    }
    if (has([
      'revenue',
      'sales',
      'how much',
      'today',
      'إيراد',
      'مبيعات',
      'اليوم',
    ])) {
      return _today(t);
    }
    return _Plan.clarify(
      ar
          ? 'تقصد المبيعات أم الطلبات أم المخزون؟ وعن أي فترة؟'
          : 'Do you mean sales, orders or stock — and over which period?',
    );
  }

  DashFormat _fmt(_Turn t) => DashFormat(lang: t.locale);

  _Plan _topProducts(_Turn t) {
    final scope = _scope(t);
    final p = _Period.lastMonth(t.now);
    final limit = RegExp(r'\b(?:top\s+)?(\d{1,2})\b').firstMatch(t.question);
    final n = (int.tryParse(limit?.group(1) ?? '') ?? 10).clamp(1, 20);
    final agg = <String, (int, int)>{};
    for (final o in _sold(scope.ids, p)) {
      for (final (item, qty, total) in _linesOf(o['id']! as String)) {
        final cur = agg[item] ?? (0, 0);
        agg[item] = (cur.$1 + qty, cur.$2 + total);
      }
    }
    final ranked = agg.entries.toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    final ar = t.locale == 'ar';
    final rows = [
      for (final e in ranked.take(n))
        {
          'item': _itemName(e.key, ar),
          'revenue': e.value.$2,
          'quantity': e.value.$1,
        },
    ];
    final f = _fmt(t);
    final month = ar ? 'سبتمبر' : 'September';
    String text;
    if (rows.isEmpty) {
      text = ar
          ? 'لم تُسجَّل مبيعات في $month.'
          : 'Nothing was sold in $month.';
    } else {
      final top = rows.first;
      final second = rows.length > 1 ? rows[1] : null;
      text = ar
          ? 'تصدّر ${top['item']} مبيعات $month بإيراد ${f.fmtMoney(top['revenue']! as int)} من ${f.fmtNumber(top['quantity']! as int)} قطعة'
                '${second == null ? '' : '، يليه ${second['item']} (${f.fmtMoney(second['revenue']! as int)})'}.'
          : '${top['item']} led $month with ${f.fmtMoney(top['revenue']! as int)} from ${f.fmtNumber(top['quantity']! as int)} sold'
                '${second == null ? '' : ', ahead of ${second['item']} (${f.fmtMoney(second['revenue']! as int)})'}.';
    }
    return _Plan.answer(text, [
      _block(
        t,
        title: ar ? 'الأصناف الأعلى مبيعًا' : 'Top products',
        presetId: 'top_products',
        spec: {
          'dataset': 'sales_items',
          'dimensions': ['item'],
          'measures': ['revenue', 'quantity'],
          'filters': {'status': 'completed'},
          'period': {'preset': 'last_month'},
          'sort': {'measure': 'revenue', 'dir': 'desc'},
          'limit': n,
          'branch': ?scope.named,
        },
        columns: [
          _col('item', ar ? 'الصنف' : 'Item', 'label'),
          _col('revenue', ar ? 'الإيراد' : 'Revenue', 'money'),
          _col('quantity', ar ? 'الكمية المباعة' : 'Qty sold', 'count'),
        ],
        rows: rows,
        grain: 'categorical',
        viz: 'row',
        scope: scope.info,
        period: p,
      ),
    ]);
  }

  ({Map<String, Object?> block, String text}) _branchRevenue(_Turn t) {
    final scope = _scope(t);
    final p = _Period.thisMonth(t.now);
    final ar = t.locale == 'ar';
    final rows = <Map<String, Object?>>[];
    for (final b in scope.ids) {
      final s = summarizeSales(_sold([b], p));
      rows.add({
        'branch': _branchName(b, ar),
        'revenue': s.revenue,
        'orders': s.orders,
      });
    }
    rows.sort((a, b) => (b['revenue']! as int).compareTo(a['revenue']! as int));
    final f = _fmt(t);
    String text;
    if (rows.length < 2) {
      final r = rows.firstOrNull;
      text = r == null
          ? (ar ? 'لا توجد فروع في نطاقك.' : 'There are no branches in scope.')
          : (ar
                ? 'حقق ${r['branch']} ${f.fmtMoney(r['revenue']! as int)} من ${f.fmtNumber(r['orders']! as int)} طلبًا هذا الشهر.'
                : '${r['branch']} took ${f.fmtMoney(r['revenue']! as int)} from ${f.fmtNumber(r['orders']! as int)} orders this month.');
    } else {
      final best = rows.first;
      final worst = rows.last;
      text = ar
          ? 'يتصدّر ${best['branch']} هذا الشهر بإيراد ${f.fmtMoney(best['revenue']! as int)} من ${f.fmtNumber(best['orders']! as int)} طلبًا، وأقلها ${worst['branch']} بإيراد ${f.fmtMoney(worst['revenue']! as int)}.'
          : '${best['branch']} is ahead this month with ${f.fmtMoney(best['revenue']! as int)} from ${f.fmtNumber(best['orders']! as int)} orders; ${worst['branch']} is lowest at ${f.fmtMoney(worst['revenue']! as int)}.';
    }
    return (
      text: text,
      block: _block(
        t,
        title: ar ? 'الإيراد حسب الفرع' : 'Revenue by branch',
        presetId: 'branch_comparison',
        spec: {
          'dataset': 'sales',
          'dimensions': ['branch'],
          'measures': ['revenue', 'orders'],
          'period': {'preset': 'this_month'},
          'sort': {'measure': 'revenue', 'dir': 'desc'},
          'branch': ?scope.named,
        },
        columns: [
          _col('branch', ar ? 'الفرع' : 'Branch', 'label'),
          _col('revenue', ar ? 'الإيراد' : 'Revenue', 'money'),
          _col('orders', ar ? 'الطلبات' : 'Orders', 'count'),
        ],
        rows: rows,
        grain: 'categorical',
        viz: 'bar',
        scope: scope.info,
        period: p,
      ),
    );
  }

  static const List<String> _daysEn = [
    'Sat',
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
  ];
  static const List<String> _daysAr = [
    'السبت',
    'الأحد',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
  ];

  _Plan _peak(_Turn t) {
    final scope = _scope(t);
    final p = _Period.lastDays(t.now, 30);
    final ar = t.locale == 'ar';
    final counts = <(int, int), int>{};
    for (final o in _sold(scope.ids, p)) {
      final at = DateTime.parse(o['created_at']! as String);
      final w = MockClock.wall(at);
      // Saturday first, as the Egyptian week starts.
      final day = (w.weekday + 1) % 7;
      counts[(day, w.hour)] = (counts[(day, w.hour)] ?? 0) + 1;
    }
    final hours = {for (final k in counts.keys) k.$2}.toList()..sort();
    final rows = <Map<String, Object?>>[];
    (int, int)? best;
    for (var d = 0; d < 7; d++) {
      for (final h in hours) {
        final n = counts[(d, h)] ?? 0;
        if (n == 0) continue;
        if (best == null || n > counts[best]!) best = (d, h);
        rows.add({
          'weekday': (ar ? _daysAr : _daysEn)[d],
          'hour': h.toString().padLeft(2, '0'),
          'orders': n,
        });
      }
    }
    final f = _fmt(t);
    final text = best == null
        ? (ar
              ? 'لا توجد طلبات في آخر 30 يومًا.'
              : 'There were no orders in the last 30 days.')
        : (ar
              ? 'أكثر ساعة ازدحامًا هي ${_daysAr[best.$1]} الساعة ${best.$2.toString().padLeft(2, '0')}:00، بعدد ${f.fmtNumber(counts[best]!)} طلبًا في آخر 30 يومًا.'
              : 'Your busiest hour is ${_daysEn[best.$1]} at ${best.$2.toString().padLeft(2, '0')}:00, with ${f.fmtNumber(counts[best]!)} orders over the last 30 days.');
    return _Plan.answer(text, [
      _block(
        t,
        title: ar ? 'الطلبات حسب اليوم والساعة' : 'Orders by day and hour',
        presetId: 'peak_hours',
        spec: {
          'dataset': 'orders',
          'dimensions': ['weekday', 'hour'],
          'measures': ['orders'],
          'period': {'preset': 'last_30_days'},
          'branch': ?scope.named,
        },
        columns: [
          _col('weekday', ar ? 'اليوم' : 'Day', 'label'),
          _col('hour', ar ? 'الساعة' : 'Hour', 'label'),
          _col('orders', ar ? 'الطلبات' : 'Orders', 'count'),
        ],
        rows: rows,
        grain: 'table',
        viz: 'heatmap',
        scope: scope.info,
        period: p,
      ),
    ]);
  }

  static const Map<String, (String, String)> _wasteReasons = {
    'expired': ('Expired', 'منتهي الصلاحية'),
    'spilled': ('Spilled', 'انسكاب'),
    'damaged': ('Damaged', 'تالف'),
    'prep_error': ('Prep error', 'خطأ في التحضير'),
  };

  _Plan _waste(_Turn t) {
    final scope = _scope(t);
    final p = _Period.lastDays(t.now, 30);
    final ar = t.locale == 'ar';
    final rows = <Map<String, Object?>>[];
    var total = 0;
    for (final ing in reportIngredients) {
      final unitCost = ing.unitCost;
      if (unitCost == null) continue;
      final rng = MockRandom('basira:waste:${ing.key}');
      final rate = 0.01 + rng.nextDouble() * 0.04;
      var qty = 0.0;
      for (final b in scope.ids) {
        qty += usedOver(b, ing.key, 30) * rate;
      }
      qty = (qty * 10).round() / 10;
      if (qty <= 0) continue;
      final cost = (qty * unitCost).round();
      total += cost;
      final reason = _wasteReasons.entries.elementAt(
        rng.nextInt(_wasteReasons.length),
      );
      rows.add({
        'ingredient': ar ? ing.ar : ing.name,
        'reason': ar ? reason.value.$2 : reason.value.$1,
        'quantity': qty,
        'unit': ing.unit,
        'waste_cost': cost,
      });
    }
    rows.sort(
      (a, b) => (b['waste_cost']! as int).compareTo(a['waste_cost']! as int),
    );
    final top = rows.take(8).toList();
    final f = _fmt(t);
    final text = top.isEmpty
        ? (ar
              ? 'لم يُسجَّل هدر في آخر 30 يومًا.'
              : 'No waste was logged in the last 30 days.')
        : (ar
              ? 'بلغت تكلفة الهدر ${f.fmtMoney(total)} في آخر 30 يومًا. أكبر بند هو ${top.first['ingredient']} بتكلفة ${f.fmtMoney(top.first['waste_cost']! as int)}.'
              : 'Waste cost ${f.fmtMoney(total)} over the last 30 days. ${top.first['ingredient']} is the biggest line at ${f.fmtMoney(top.first['waste_cost']! as int)}.');
    return _Plan.answer(text, [
      _block(
        t,
        title: ar ? 'الهدر، آخر 30 يومًا' : 'Waste, last 30 days',
        presetId: 'waste_total',
        spec: {
          'dataset': 'waste',
          'measures': ['waste_cost', 'items'],
          'period': {'preset': 'last_30_days'},
          'branch': ?scope.named,
        },
        columns: [
          _col('waste_cost', ar ? 'تكلفة الهدر' : 'Waste cost', 'money'),
          _col('items', ar ? 'مكوّنات مهدرة' : 'Ingredients wasted', 'count'),
        ],
        rows: [
          {'waste_cost': total, 'items': rows.length},
        ],
        grain: 'scalar',
        viz: 'kpi',
        scope: scope.info,
        period: p,
      ),
      _block(
        t,
        title: ar ? 'الهدر حسب المكوّن' : 'Waste by ingredient',
        presetId: 'waste_by_ingredient',
        spec: {
          'dataset': 'waste',
          'dimensions': ['ingredient', 'reason'],
          'measures': ['quantity', 'waste_cost'],
          'period': {'preset': 'last_30_days'},
          'sort': {'measure': 'waste_cost', 'dir': 'desc'},
          'limit': 8,
          'branch': ?scope.named,
        },
        columns: [
          _col('ingredient', ar ? 'المكوّن' : 'Ingredient', 'label'),
          _col('reason', ar ? 'السبب' : 'Reason', 'label'),
          _col('unit', ar ? 'الوحدة' : 'Unit', 'label'),
          _col('quantity', ar ? 'الكمية' : 'Quantity', 'number'),
          _col('waste_cost', ar ? 'التكلفة' : 'Cost', 'money'),
        ],
        rows: top,
        grain: 'table',
        viz: 'table',
        scope: scope.info,
        period: p,
      ),
    ]);
  }

  _Plan _trend(_Turn t) {
    final scope = _scope(t);
    final p = _Period.lastDays(t.now, 30);
    final ar = t.locale == 'ar';
    final byDay = <String, int>{};
    for (final o in _sold(scope.ids, p)) {
      final day = MockClock.cairoDate(
        DateTime.parse(o['created_at']! as String),
      );
      byDay[day] =
          (byDay[day] ?? 0) + ((o['total_amount'] as num?)?.toInt() ?? 0);
    }
    final rows = <Map<String, Object?>>[];
    var day = DateTime.parse(p.from);
    final end = DateTime.parse(p.to);
    while (!day.isAfter(end)) {
      final key = MockClock.cairoDate(day);
      rows.add({'day': key, 'revenue': byDay[key]});
      day = day.add(const Duration(days: 1));
    }
    final known = [
      for (final r in rows)
        if (r['revenue'] != null) r,
    ];
    final f = _fmt(t);
    String text;
    if (known.isEmpty) {
      text = ar
          ? 'لا توجد مبيعات في آخر 30 يومًا.'
          : 'There were no sales in the last 30 days.';
    } else {
      final sum = known.fold<int>(0, (s, r) => s + (r['revenue']! as int));
      final best = known.reduce(
        (a, b) => (a['revenue']! as int) >= (b['revenue']! as int) ? a : b,
      );
      final avg = (sum / known.length).round();
      text = ar
          ? 'بلغ متوسط الإيراد اليومي ${f.fmtMoney(avg)} في آخر 30 يومًا، وأفضل يوم كان ${best['day']} بإيراد ${f.fmtMoney(best['revenue']! as int)}.'
          : 'Revenue averaged ${f.fmtMoney(avg)} a day over the last 30 days; the best day was ${best['day']} at ${f.fmtMoney(best['revenue']! as int)}.';
    }
    return _Plan.answer(text, [
      _block(
        t,
        title: ar ? 'الإيراد اليومي' : 'Daily revenue',
        presetId: 'daily_revenue',
        spec: {
          'dataset': 'sales',
          'dimensions': ['day'],
          'measures': ['revenue'],
          'period': {'preset': 'last_30_days'},
          'branch': ?scope.named,
        },
        columns: [
          _col('day', ar ? 'اليوم' : 'Day', 'date'),
          _col('revenue', ar ? 'الإيراد' : 'Revenue', 'money'),
        ],
        rows: rows,
        grain: 'series',
        viz: 'area',
        scope: scope.info,
        period: p,
      ),
    ]);
  }

  _Plan _payments(_Turn t) {
    final scope = _scope(t);
    final p = _Period.lastDays(t.now, 30);
    final ar = t.locale == 'ar';
    final s = summarizeSales(_sold(scope.ids, p));
    final entries = s.byMethod.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    String label(String code) {
      for (final m in seedPaymentMethods) {
        if (m.name == code) return ar ? m.ar : m.en;
      }
      return code;
    }

    final rows = [
      for (final e in entries) {'method': label(e.key), 'revenue': e.value},
    ];
    final f = _fmt(t);
    final total = entries.fold<int>(0, (a, e) => a + e.value);
    final text = entries.isEmpty
        ? (ar
              ? 'لا توجد مدفوعات في آخر 30 يومًا.'
              : 'No payments in the last 30 days.')
        : (ar
              ? 'استحوذ ${label(entries.first.key)} على ${f.fmtShare(entries.first.value, total)} من الإيراد في آخر 30 يومًا.'
              : '${label(entries.first.key)} took ${f.fmtShare(entries.first.value, total)} of revenue over the last 30 days.');
    return _Plan.answer(text, [
      _block(
        t,
        title: ar ? 'الإيراد حسب طريقة الدفع' : 'Revenue by payment method',
        presetId: 'payment_mix',
        spec: {
          'dataset': 'payments',
          'dimensions': ['method'],
          'measures': ['revenue'],
          'period': {'preset': 'last_30_days'},
          'branch': ?scope.named,
        },
        columns: [
          _col('method', ar ? 'طريقة الدفع' : 'Payment method', 'label'),
          _col('revenue', ar ? 'الإيراد' : 'Revenue', 'money'),
        ],
        rows: rows,
        grain: 'categorical',
        viz: 'donut',
        scope: scope.info,
        period: p,
      ),
    ]);
  }

  _Plan _today(_Turn t) {
    final scope = _scope(t);
    final p = _Period.today(t.now);
    final ar = t.locale == 'ar';
    final s = summarizeSales(_sold(scope.ids, p));
    final f = _fmt(t);
    final text = s.orders == 0
        ? (ar ? 'لا توجد طلبات اليوم حتى الآن.' : 'No orders yet today.')
        : (ar
              ? 'اليوم حتى الآن: ${f.fmtMoney(s.revenue)} من ${f.fmtNumber(s.orders)} طلبًا، بمتوسط فاتورة ${f.fmtMoney(s.aov)}.'
              : 'Today so far: ${f.fmtMoney(s.revenue)} from ${f.fmtNumber(s.orders)} orders, an average ticket of ${f.fmtMoney(s.aov)}.');
    return _Plan.answer(text, [
      _block(
        t,
        title: ar ? 'اليوم حتى الآن' : 'Today so far',
        presetId: 'sales_today',
        spec: {
          'dataset': 'sales',
          'measures': ['revenue', 'orders', 'avg_ticket'],
          'period': {'preset': 'today'},
          'branch': ?scope.named,
        },
        columns: [
          _col('revenue', ar ? 'الإيراد' : 'Revenue', 'money'),
          _col('orders', ar ? 'الطلبات' : 'Orders', 'count'),
          _col('avg_ticket', ar ? 'متوسط الفاتورة' : 'Average ticket', 'money'),
        ],
        rows: [
          {'revenue': s.revenue, 'orders': s.orders, 'avg_ticket': s.aov},
        ],
        rowCount: s.orders == 0 ? 0 : 1,
        grain: 'scalar',
        viz: 'kpi',
        scope: scope.info,
        period: p,
      ),
    ]);
  }

  /// Average prep and the longest wait per branch, in minutes (the KDS's
  /// bump times; fixed per branch so the figures are stable).
  static final Map<String, (double, double)> _prepMinutes = {
    SeedIds.heliopolis: (6.4, 38),
    SeedIds.maadi: (8.2, 52),
    SeedIds.newCairo: (12.6, 75),
    SeedIds.zamalek: (9.5, 47),
  };

  _Plan _prep(_Turn t) {
    final scope = _scope(t);
    final p = _Period.lastDays(t.now, 7);
    final ar = t.locale == 'ar';
    final rows =
        [
          for (final b in scope.ids)
            {
              'branch': _branchName(b, ar),
              'avg_prep': _prepMinutes[b]!.$1,
              'max_wait': _prepMinutes[b]!.$2,
            },
        ]..sort(
          (a, b) =>
              (b['avg_prep']! as double).compareTo(a['avg_prep']! as double),
        );
    final f = _fmt(t);
    final slow = rows.firstOrNull;
    final text = slow == null
        ? (ar
              ? 'لا توجد تذاكر في آخر 7 أيام.'
              : 'No tickets in the last 7 days.')
        : (ar
              ? 'أبطأ فرع هو ${slow['branch']} بمتوسط ${f.fmtNumber((slow['avg_prep']! as double).round())} دقيقة من الطلب حتى التجهيز.'
              : '${slow['branch']} is slowest, averaging ${f.fmtNumber((slow['avg_prep']! as double).round())} minutes from order to ready.');
    return _Plan.answer(text, [
      _block(
        t,
        title: ar ? 'وقت التحضير حسب الفرع' : 'Prep time by branch',
        presetId: 'prep_time',
        spec: {
          'dataset': 'tickets',
          'dimensions': ['branch'],
          'measures': ['avg_prep', 'max_wait'],
          'period': {'preset': 'last_7_days'},
          'branch': ?scope.named,
        },
        columns: [
          _col('branch', ar ? 'الفرع' : 'Branch', 'label'),
          _col('avg_prep', ar ? 'متوسط التحضير' : 'Avg prep', 'minutes'),
          _col('max_wait', ar ? 'أطول انتظار' : 'Longest wait', 'minutes'),
        ],
        rows: rows,
        grain: 'categorical',
        viz: 'row',
        scope: scope.info,
        period: p,
      ),
    ]);
  }

  _Plan _refunds(_Turn t) {
    final scope = _scope(t);
    final p = _Period.lastDays(t.now, 30);
    final ar = t.locale == 'ar';
    final refunded = [
      for (final o in reportOrders(
        db,
        branchIds: scope.ids,
        from: DateTime.parse(p.from),
        to: DateTime.parse(p.to),
      ))
        if (o['status'] == 'refunded') o,
    ];
    final f = _fmt(t);
    final text = refunded.isEmpty
        ? (ar
              ? 'لم يُسترجع أي طلب في آخر 30 يومًا.'
              : 'No orders were refunded in the last 30 days.')
        : (ar
              ? 'استُرجع ${f.fmtNumber(refunded.length)} طلبًا في آخر 30 يومًا.'
              : '${f.fmtNumber(refunded.length)} orders were refunded in the last 30 days.');
    final rows = <Map<String, Object?>>[];
    for (final b in scope.ids) {
      final mine = refunded.where((o) => o['branch_id'] == b).toList();
      if (mine.isEmpty) continue;
      rows.add({
        'branch': _branchName(b, ar),
        'refunds': mine.length,
        'refund_amount': mine.fold<int>(
          0,
          (s, o) => s + ((o['total_amount'] as num?)?.toInt() ?? 0),
        ),
      });
    }
    return _Plan.answer(text, [
      _block(
        t,
        title: ar ? 'المرتجعات حسب الفرع' : 'Refunds by branch',
        presetId: 'refunds',
        spec: {
          'dataset': 'refunds',
          'dimensions': ['branch'],
          'measures': ['refunds', 'refund_amount'],
          'filters': {'status': 'refunded'},
          'period': {'preset': 'last_30_days'},
          'branch': ?scope.named,
        },
        columns: [
          _col('branch', ar ? 'الفرع' : 'Branch', 'label'),
          _col('refunds', ar ? 'المرتجعات' : 'Refunds', 'count'),
          _col('refund_amount', ar ? 'المبلغ' : 'Amount', 'money'),
        ],
        rows: rows,
        grain: 'categorical',
        viz: 'bar',
        scope: scope.info,
        period: p,
      ),
    ]);
  }

  /// The executor's row cap for a raw list.
  static const int _listCap = 50;

  _Plan _orderList(_Turn t) {
    final scope = _scope(t);
    final p = _Period.today(t.now);
    final ar = t.locale == 'ar';
    final orders = _sold(scope.ids, p).toList().reversed.toList();
    final f = DashFormat(lang: t.locale, timezone: MockClock.timezone);
    final rows = [
      for (final o in orders.take(_listCap))
        {
          'order_ref': o['order_ref'] ?? o['id'],
          'branch': _branchName(o['branch_id']! as String, ar),
          'time': f.fmtTime(o['created_at']),
          'total': o['total_amount'],
        },
    ];
    final text = ar
        ? 'هذه طلبات اليوم، الأحدث أولًا (${f.fmtNumber(orders.length)} طلبًا).'
        : "Here are today's orders, newest first (${f.fmtNumber(orders.length)} in all).";
    return _Plan.answer(text, [
      _block(
        t,
        title: ar ? 'طلبات اليوم' : "Today's orders",
        presetId: null,
        spec: {
          'dataset': 'orders',
          'dimensions': ['order_ref', 'branch', 'time'],
          'measures': ['total'],
          'filters': {'status': 'completed'},
          'period': {'preset': 'today'},
          'limit': _listCap,
          'branch': ?scope.named,
        },
        columns: [
          _col('order_ref', ar ? 'الطلب' : 'Order', 'label'),
          _col('branch', ar ? 'الفرع' : 'Branch', 'label'),
          _col('time', ar ? 'الوقت' : 'Time', 'label'),
          _col('total', ar ? 'الإجمالي' : 'Total', 'money'),
        ],
        rows: rows,
        truncated: orders.length > _listCap,
        grain: 'table',
        viz: 'table',
        scope: scope.info,
        period: p,
      ),
    ]);
  }

  // ── pieces ──────────────────────────────────────────────────────────────

  static Map<String, Object?> _col(String key, String label, String kind) => {
    'key': key,
    'label': label,
    'kind': kind,
  };

  Map<String, Object?> _block(
    _Turn t, {
    required String? title,
    required String? presetId,
    required Map<String, Object?> spec,
    required List<Map<String, Object?>> columns,
    required List<Map<String, Object?>> rows,
    required String grain,
    required String viz,
    required Map<String, Object?> scope,
    required _Period period,
    int? rowCount,
    bool truncated = false,
  }) => {
    'title': ?title,
    'preset_id': ?presetId,
    'spec': {...spec, 'viz': viz},
    'columns': columns,
    'rows': rows,
    'row_count': rowCount ?? rows.length,
    'truncated': truncated,
    'grain': grain,
    'viz': viz,
    'scope': scope,
    'period_from': period.from,
    'period_to': period.to,
  };

  /// The orders of [branchIds] in [p] that count as sold.
  Iterable<MockRow> _sold(List<String> branchIds, _Period p) => reportOrders(
    db,
    branchIds: branchIds,
    from: DateTime.parse(p.from),
    to: DateTime.parse(p.to),
  ).where(isSold);

  /// `analytics::scope::resolve`.
  _Scope _scope(_Turn t) {
    final q = t.question.toLowerCase();
    final named = <String>[];
    for (final b in seedBranches) {
      final id = MockSeed.branchIdOf(b.key);
      if (!t.accessible.contains(id)) continue;
      if (q.contains(b.name.toLowerCase()) || t.question.contains(b.ar)) {
        named.add(id);
      }
    }
    if (named.isNotEmpty) {
      final names = [for (final id in named) _branchName(id, false)];
      return _Scope(
        ids: named,
        named: names.join(', '),
        info: {
          'all_branches': false,
          'branches': names,
          'label': names.join(', '),
        },
      );
    }
    String? unmatched;
    for (final place in _elsewhere) {
      final at = q.indexOf(place.toLowerCase());
      if (at >= 0) {
        unmatched = t.question.substring(at, at + place.length);
        break;
      }
    }
    final sel = t.selected;
    if (sel != null) {
      final name = _branchName(sel, false);
      return _Scope(
        ids: [sel],
        info: {
          'all_branches': false,
          'branches': [name],
          'label': name,
          'unmatched_branch': ?unmatched,
        },
      );
    }
    final names = [for (final id in t.accessible) _branchName(id, false)];
    return _Scope(
      ids: t.accessible,
      info: {
        'all_branches': true,
        'branches': names,
        'label': switch (names.length) {
          0 => 'No branches',
          1 => names.single,
          final n => 'All branches ($n)',
        },
        'unmatched_branch': ?unmatched,
      },
    );
  }

  /// Places people name that are not Sabah branches.
  static const List<String> _elsewhere = [
    'Alexandria',
    'Dokki',
    'Nasr City',
    'Sheikh Zayed',
    'الإسكندرية',
    'الدقي',
    'مدينة نصر',
    'الشيخ زايد',
  ];

  static String _branchName(String id, bool ar) {
    for (final b in seedBranches) {
      if (MockSeed.branchIdOf(b.key) == id) return ar ? b.ar : b.name;
    }
    return id;
  }

  static final Map<String, SeedItem> _itemsById = {
    for (final m in seedMenu) MockSeed.menuItemId(m.key): m,
  };

  static String _itemName(String key, bool ar) {
    for (final m in seedMenu) {
      if (m.key == key) return ar ? m.ar : m.name;
    }
    return key;
  }

  /// Each order's lines as (item key, quantity, line total), read once from
  /// the seed (the seed never changes).
  static final Map<String, List<(String, int, int)>> _lines = {};

  static List<(String, int, int)> _linesOf(String orderId) =>
      _lines[orderId] ??= [
        for (final l in MockSeed.instance.orderItems(orderId))
          (
            _itemsById[l.menuItemId]?.key ?? l.menuItemId ?? '',
            l.quantity,
            l.lineTotal,
          ),
      ];
}

/// A stored query: what ran and the snapshot of what it returned
/// (`handlers::snapshot_of`, 200 rows kept).
Map<String, Object?> storedQuery(
  Map<String, Object?> block,
  String capturedAt,
) {
  final rows = block['rows']! as List;
  return {
    'title': block['title'],
    'preset_id': block['preset_id'],
    'spec': block['spec'],
    'captured_at': capturedAt,
    'snapshot': {
      'columns': block['columns'],
      'rows': rows.take(200).toList(),
      'row_count': block['row_count'],
      'truncated': block['truncated'] == true || rows.length > 200,
      'grain': block['grain'],
      'viz': block['viz'],
      'facet_by': block['facet_by'],
      'scope': block['scope'],
      'period_from': block['period_from'],
      'period_to': block['period_to'],
    },
  };
}

/// `store::title_from`: the question trimmed, cut to 80 characters on a
/// word boundary (with "…") when longer.
String basiraTitleFrom(String question) {
  final trimmed = question.trim();
  final chars = trimmed.runes.toList();
  if (chars.length <= basiraMaxTitle) return trimmed;
  final cut = String.fromCharCodes(chars.take(basiraMaxTitle));
  final space = cut.lastIndexOf(' ');
  if (space >= 0) {
    final head = cut.substring(0, space);
    if (head.runes.length > basiraMaxTitle ~/ 2) return '$head…';
  }
  return '$cut…';
}

class _Turn {
  const _Turn({
    required this.question,
    required this.locale,
    required this.userId,
    required this.orgId,
    required this.accessible,
    required this.now,
    this.conversationId,
    this.selected,
  });

  final String question;
  final String locale;
  final String userId;
  final String orgId;
  final String? conversationId;
  final List<String> accessible;
  final String? selected;
  final DateTime now;
}

class _Scope {
  const _Scope({required this.ids, required this.info, this.named});

  final List<String> ids;
  final Map<String, Object?> info;

  /// The branch(es) the question named (the spec's `branch`).
  final String? named;
}

class _Plan {
  const _Plan._(this.kind, {this.text, this.clarify, this.blocks = const []});

  factory _Plan.answer(String text, List<Map<String, Object?>> blocks) =>
      _Plan._('answer', text: text, blocks: blocks);

  factory _Plan.incomplete(String text, List<Map<String, Object?>> blocks) =>
      _Plan._('incomplete', text: text, blocks: blocks);

  factory _Plan.clarify(String question) =>
      _Plan._('clarify', clarify: question);

  final String kind;
  final String? text;
  final String? clarify;
  final List<Map<String, Object?>> blocks;
}

/// A resolved period in Cairo, as UTC instants (`to_rfc3339`).
class _Period {
  const _Period(this.from, this.to);

  factory _Period.lastMonth(DateTime now) {
    final w = MockClock.wall(now);
    final y = w.month == 1 ? w.year - 1 : w.year;
    final m = w.month == 1 ? 12 : w.month - 1;
    final start = MockClock.fromCairo(y, m, 1);
    final end = MockClock.fromCairo(w.year, w.month, 1);
    return _Period(
      start.toIso8601String(),
      end.subtract(const Duration(milliseconds: 1)).toIso8601String(),
    );
  }

  factory _Period.thisMonth(DateTime now) {
    final w = MockClock.wall(now);
    return _Period(
      MockClock.fromCairo(w.year, w.month, 1).toIso8601String(),
      now.toUtc().toIso8601String(),
    );
  }

  factory _Period.lastDays(DateTime now, int days) {
    final start = MockClock.startOfCairoDay(now);
    final w = MockClock.wall(start);
    return _Period(
      MockClock.fromCairo(
        w.year,
        w.month,
        w.day - (days - 1),
      ).toIso8601String(),
      now.toUtc().toIso8601String(),
    );
  }

  factory _Period.today(DateTime now) => _Period(
    MockClock.startOfCairoDay(now).toIso8601String(),
    now.toUtc().toIso8601String(),
  );

  final String from;
  final String to;
}
