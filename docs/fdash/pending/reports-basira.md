# reports/basira: verifier findings to fix (NOT at parity: 2 major, 2 minor)
1 MAJOR (REP-BAS-009 intent): pressing a conversation fires GET /ai/conversations/{id}, but the item has no intent hook. Fix with a one-shot warm, keeping it uncached like the web:
- BasiraController.warmOpen(id) stores (id, _ai.getConversation(id: id), DateTime.now());
- open(id) uses the stored future if the id matches, it is < 30 s old and no ask ran since, then clears it; otherwise it fetches;
- ask and delete clear the stored future;
- wrap the item's DashPressable (basira_page.dart _ConversationItemState.build ~528) in DashIntent(onIntent: () => ref.read(basiraProvider.notifier).warmOpen(conv.id), …).
Test "REP-BAS-009 resting on a conversation warms its read": hover 90 ms, tap, exactly one GET.
2 MAJOR (REP-BAS-002/004): the shell's header refresh (DashPageHeader refreshAction: true) and Cmd/Ctrl+R run queryCache.refetchActive(), but Basira keeps no webCache reads, so the button spins and does nothing. Fix:
- refreshAction: false;
- add your own DashIconButton('refresh-cw', semanticLabel: context.dashStrings.refresh, loading: …) that runs Future.wait([_c.refreshList(), if (activeId != null && !busy) _c.open(activeId)]).
Test: pressing it makes one more GET /ai/conversations?limit=30. (Cmd/Ctrl+R reaching a no-cache page is a foundation item; not yours.)
3 minor (REP-BAS-007): a cut English title in the Arabic rail puts the ellipsis on the wrong side ("…How much did we waste in the last 30 da"). Don't wrap the rail title in ownDirection(); give MadarClippedText the content's first-strong textDirection and textAlign isRtl ? right : left.
4 minor (tokens): raw fontSize 11 at basira_page.dart:564, 792, 1016, basira_result.dart:251, 307, 386, basira_charts.dart:49; fontSize 12/10 at basira_charts.dart:129 and basira_result.dart:485; spacing arithmetic (Space.xs + 2, Space.md + 2). Use DashType tokens and named BasiraMetrics constants.
