/// Basira's page state and actions (`basira-page.tsx`'s hooks): the
/// conversation list, the open conversation, the transcript and the one
/// question in flight.
///
/// The web keeps all of this in component state and calls the API by hand —
/// no React Query, so nothing is cached and nothing is invalidated
/// (REP-ALL-009: "Basira has no query cache"). The same here: an autoDispose
/// notifier that lives as long as the page, reads the list on mount, and
/// aborts the stream when the page goes (REP-BAS-030). Failures the web
/// toasts are handed to the page as a [BasiraNotice].
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' as wire;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'basira_models.dart';

/// A failure to toast (a fresh object each time, so a repeat still shows).
class BasiraNotice {
  BasiraNotice(this.message);
  final String message;
}

@immutable
class BasiraState {
  const BasiraState({
    this.conversations = const [],
    this.loadingList = true,
    this.activeId,
    this.exchanges = const [],
    this.loadingThread = false,
    this.busy = false,
    this.notice,
  });

  final List<wire.ConversationSummary> conversations;
  final bool loadingList;
  final String? activeId;
  final List<BasiraExchange> exchanges;
  final bool loadingThread;

  /// A question is streaming.
  final bool busy;
  final BasiraNotice? notice;

  /// The header's title: the open conversation's, when the list has it.
  String? get activeTitle {
    for (final c in conversations) {
      if (c.id == activeId) return c.title;
    }
    return null;
  }

  static const Object _keep = Object();

  BasiraState copyWith({
    List<wire.ConversationSummary>? conversations,
    bool? loadingList,
    Object? activeId = _keep,
    List<BasiraExchange>? exchanges,
    bool? loadingThread,
    bool? busy,
    BasiraNotice? notice,
  }) => BasiraState(
    conversations: conversations ?? this.conversations,
    loadingList: loadingList ?? this.loadingList,
    activeId: identical(activeId, _keep) ? this.activeId : activeId as String?,
    exchanges: exchanges ?? this.exchanges,
    loadingThread: loadingThread ?? this.loadingThread,
    busy: busy ?? this.busy,
    notice: notice ?? this.notice,
  );
}

final basiraProvider =
    NotifierProvider.autoDispose<BasiraController, BasiraState>(
      BasiraController.new,
    );

/// The words of a failed question (REP-BAS-018): the server's own; a refusal
/// with no `{error}` body is "Request failed (`status`)", as the web words
/// an HTTP error it cannot read.
String basiraErrorText(Object? error, Translator t) {
  if (error is wire.ApiException && error.status > 0 && error.details is! Map) {
    return t('basira.requestFailed', args: {'status': error.status});
  }
  return errorMessage(error, t);
}

class BasiraController extends Notifier<BasiraState> {
  int _seq = 0;

  /// The question in flight; [_Turn.cancel] aborts it.
  _Turn? _turn;

  /// The latest conversation read: an older answer arriving late is dropped.
  int _openSeq = 0;

  /// A conversation read started on intent, used once by [open]. Not a
  /// cache: the web reads a conversation fresh on every press.
  (String, Future<wire.ConversationDetail>, DateTime)? _warm;

  @override
  BasiraState build() {
    ref.onDispose(() => _abort(dispose: true));
    Future.microtask(() {
      if (ref.mounted) refreshList();
    });
    return const BasiraState();
  }

  wire.AiApi get _ai => ref.read(apiProvider).ai;
  Translator get _t => ref.read(tProvider);

  void _set(BasiraState Function(BasiraState s) fn) {
    if (ref.mounted) state = fn(state);
  }

  void _toast(Object error) =>
      _set((s) => s.copyWith(notice: BasiraNotice(errorMessage(error, _t))));

  /// The 30 most recent conversations (REP-BAS-003/017). A failure toasts
  /// and leaves the list as it was.
  Future<void> refreshList() async {
    try {
      final list = await _ai.listConversations(limit: 30);
      _set((s) => s.copyWith(conversations: list.conversations));
    } on Object catch (e) {
      _toast(e);
    } finally {
      _set((s) => s.copyWith(loadingList: false));
    }
  }

  bool _warmFor(String id) {
    final w = _warm;
    return w != null &&
        w.$1 == id &&
        DateTime.now().difference(w.$3) < const Duration(seconds: 30);
  }

  /// Starts [open]'s read while the pointer rests on a conversation
  /// (REP-BAS-009), so the press finds it under way. Not while a question
  /// streams: its answer would land after the read.
  void warmOpen(String id) {
    if (state.busy || _warmFor(id)) return;
    final read = _ai.getConversation(id: id);
    // A warm read nobody opens must not surface as an uncaught error.
    unawaited(read.then((_) {}, onError: (Object _) {}));
    _warm = (id, read, DateTime.now());
  }

  /// Opens a stored conversation (REP-BAS-009/010).
  Future<void> open(String id) async {
    final read = _warmFor(id) ? _warm!.$2 : _ai.getConversation(id: id);
    _warm = null;
    _abort();
    final seq = ++_openSeq;
    _set((s) => s.copyWith(activeId: id, loadingThread: true));
    try {
      final detail = await read;
      if (seq != _openSeq) return;
      _set(
        (s) => s.copyWith(
          exchanges: [
            for (final turn in detail.turns)
              BasiraExchange(
                id: turn.id,
                question: turn.question,
                answer: turn.answer,
                kind: turn.kind,
                results: blocksFromStoredTurn(turn),
                capturedAt: capturedAtOf(turn),
                fromHistory: true,
              ),
          ],
        ),
      );
    } on Object catch (e) {
      if (seq == _openSeq) _toast(e);
    } finally {
      if (seq == _openSeq) _set((s) => s.copyWith(loadingThread: false));
    }
  }

  /// A new conversation (REP-BAS-011).
  void startNew() {
    _abort();
    _openSeq++;
    _set(
      (s) =>
          s.copyWith(activeId: null, exchanges: const [], loadingThread: false),
    );
  }

  /// Asks [text] (REP-BAS-014–018): ignored when blank or while another
  /// question streams.
  Future<void> ask(String text) async {
    final question = text.trim();
    if (question.isEmpty || state.busy) return;
    _warm = null;
    final id = 'x${++_seq}';
    final conversationId = state.activeId;
    _set(
      (s) => s.copyWith(
        busy: true,
        exchanges: [
          ...s.exchanges,
          BasiraExchange(id: id, question: question, pending: true),
        ],
      ),
    );
    void patch(BasiraExchange Function(BasiraExchange x) fn) => _set(
      (s) => s.copyWith(
        exchanges: [for (final x in s.exchanges) x.id == id ? fn(x) : x],
      ),
    );

    final turn = _Turn();
    _turn = turn;
    String? createdId;
    var ended = false;
    try {
      final stream = _ai.chatStream(
        body: wire.AiChatRequest(
          question: question,
          conversationId: conversationId,
          locale: ref.read(localeProvider).startsWith('ar') ? 'ar' : 'en',
        ),
      );
      await turn.run(stream, (raw) {
        switch (decodeChatFrame(raw)) {
          case wire.ChatFrameStarted(:final conversationId?):
            createdId = conversationId;
          case wire.ChatFrameThinking(:final step):
            patch((x) => x.copyWith(step: step, querying: null));
          case wire.ChatFrameQuerying(:final title, :final dataset):
            patch((x) => x.copyWith(querying: title ?? dataset));
          case wire.ChatFrameResult(:final block):
            patch(
              (x) => x.copyWith(results: [...x.results, block], querying: null),
            );
          case wire.ChatFrameAnswer(:final response):
            ended = true;
            createdId = response.conversationId ?? createdId;
            final (kind, words, results) = switch (response.aiChatKind) {
              wire.AiChatKindAnswer(:final text, :final results) => (
                'answer',
                text,
                results,
              ),
              wire.AiChatKindIncomplete(:final text, :final results) => (
                'incomplete',
                text,
                results,
              ),
              wire.AiChatKindClarify(:final question) => (
                'clarify',
                question,
                const <wire.ResultBlock>[],
              ),
              wire.AiChatKindUnknown(:final json) => (
                '${json['kind']}',
                json['text'] as String?,
                const <wire.ResultBlock>[],
              ),
            };
            // The terminal frame is the contract: its results replace the
            // streamed ones, so a dropped progress frame loses no chart.
            patch(
              (x) => x.copyWith(
                pending: false,
                step: null,
                querying: null,
                kind: kind,
                answer: words,
                results: results,
              ),
            );
          case wire.ChatFrameError(:final message):
            ended = true;
            patch(
              (x) => x.copyWith(pending: false, step: null, error: message),
            );
          default:
          // An unreadable frame is dropped; the terminal one carries all.
        }
      });
      if (!ended) {
        // The stream closed with no terminal frame: the web would spin
        // forever; say the question could not be answered instead.
        patch(
          (x) => x.copyWith(
            pending: false,
            step: null,
            querying: null,
            error: _t('basira.failed'),
          ),
        );
      }
      final created = createdId;
      if (created != null && created != conversationId) {
        _set((s) => s.copyWith(activeId: created));
        unawaited(refreshList());
      } else if (conversationId != null) {
        unawaited(refreshList());
      }
    } on _Aborted {
      return;
    } on Object catch (e) {
      patch(
        (x) => x.copyWith(
          pending: false,
          step: null,
          error: basiraErrorText(e, _t),
        ),
      );
    } finally {
      if (identical(_turn, turn)) {
        _turn = null;
        _set((s) => s.copyWith(busy: false));
      }
    }
  }

  /// Renames [c] to [title] (REP-BAS-026); blank does nothing.
  Future<void> rename(wire.ConversationSummary c, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    try {
      await _ai.renameConversation(
        id: c.id,
        body: wire.RenameConversationRequest(title: trimmed),
      );
      unawaited(refreshList());
    } on Object catch (e) {
      _toast(e);
    }
  }

  /// Deletes [c] (REP-BAS-027); the open one gives way to a new one.
  Future<void> delete(wire.ConversationSummary c) async {
    _warm = null;
    try {
      await _ai.deleteConversation(id: c.id);
      if (c.id == state.activeId) startNew();
      unawaited(refreshList());
    } on Object catch (e) {
      _toast(e);
    }
  }

  void _abort({bool dispose = false}) {
    final turn = _turn;
    if (turn == null) return;
    _turn = null;
    turn.cancel();
    if (!dispose) _set((s) => s.copyWith(busy: false));
  }
}

class _Aborted implements Exception {
  const _Aborted();
}

/// One streamed question: reads [run]'s stream until it closes, fails, or
/// [cancel] stops it (the web's `AbortController`).
class _Turn {
  StreamSubscription<String>? _sub;
  final Completer<void> _done = Completer<void>();

  Future<void> run(Stream<String> stream, void Function(String raw) onData) {
    _sub = stream.listen(
      onData,
      onError: (Object e) {
        unawaited(_sub?.cancel());
        if (!_done.isCompleted) _done.completeError(e);
      },
      onDone: () {
        if (!_done.isCompleted) _done.complete();
      },
    );
    return _done.future;
  }

  void cancel() {
    unawaited(_sub?.cancel());
    if (!_done.isCompleted) _done.completeError(const _Aborted());
  }
}
