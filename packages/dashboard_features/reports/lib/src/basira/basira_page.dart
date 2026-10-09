/// `/basira` Basira (REP-BAS rows): the AI analytics workspace — the
/// conversation rail, the streamed answers with their result blocks, rename
/// and delete (`features/basira/*`). The web has no in-page guard: a refusal
/// surfaces as a toast or as a question's failure box (REP-BAS-001).
///
/// A full-height workspace, not a page that scrolls (REP-BAS-002): a fixed
/// header, the transcript scrolling inside, the composer pinned under it.
/// From 1280 wide the rail is pinned at the start side; below that it is a
/// slide-over from the start side (REP-BAS-005/006).
library;

import 'package:dashboard_api/dashboard_api.dart' as wire;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show Bidi;

import 'basira_charts.dart';
import 'basira_controller.dart';
import 'basira_models.dart';
import 'basira_result.dart';

/// The route's page (`DashRoute.builder`).
Widget basiraPageBuilder(BuildContext context, GoRouterState state) =>
    const BasiraPage();

/// The web's four starters (REP-BAS-012).
const List<String> basiraStarters = [
  'topProducts',
  'branchCompare',
  'peakHours',
  'waste',
];

class BasiraPage extends ConsumerStatefulWidget {
  const BasiraPage({super.key});

  /// The transcript's scroll view.
  static const Key transcriptKey = ValueKey('basira-transcript');

  @override
  ConsumerState<BasiraPage> createState() => _BasiraPageState();
}

class _BasiraPageState extends ConsumerState<BasiraPage> {
  final ScrollController _scroll = ScrollController();
  String _question = '';
  bool _railOpen = false;
  bool _refreshing = false;

  BasiraController get _c => ref.read(basiraProvider.notifier);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The transcript follows the newest exchange (REP-BAS-029).
  void _followEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (DashMotion.reduced(context)) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(
          end,
          duration: DashMotion.slow,
          curve: DashMotion.ease,
        );
      }
    });
  }

  void _send(String text) {
    if (text.trim().isEmpty || ref.read(basiraProvider).busy) return;
    setState(() => _question = '');
    _c.ask(text);
  }

  void _closeRail() {
    if (_railOpen) Navigator.of(context, rootNavigator: true).maybePop();
  }

  void _open(String id) {
    _closeRail();
    _c.open(id);
  }

  void _startNew() {
    _closeRail();
    _c.startNew();
  }

  Future<void> _rename(wire.ConversationSummary c) async {
    final title = await showDashDialog<String>(
      context,
      width: BasiraMetrics.renameDialog,
      builder: (context) => _RenameDialog(initial: c.title),
    );
    if (title != null) await _c.rename(c, title);
  }

  Future<void> _delete(wire.ConversationSummary c) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('basira.deleteTitle'),
      description: t('basira.deleteBody'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok) return;
    final wasOpen = c.id == ref.read(basiraProvider).activeId;
    await _c.delete(c);
    if (wasOpen && mounted && ref.read(basiraProvider).activeId == null) {
      _closeRail();
    }
  }

  /// The header's refresh: Basira keeps no query cache for the shell's
  /// refresh to refetch, so it re-reads the list and the open conversation.
  Future<void> _refresh() async {
    final s = ref.read(basiraProvider);
    final id = s.activeId;
    setState(() => _refreshing = true);
    try {
      await Future.wait([
        _c.refreshList(),
        if (id != null && !s.busy) _c.open(id),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _showRail() async {
    setState(() => _railOpen = true);
    await showBasiraRail(context, builder: (_) => _rail());
    if (mounted) setState(() => _railOpen = false);
  }

  Widget _rail() => BasiraConversationList(
    onOpen: _open,
    onNew: _startNew,
    onRename: _rename,
    onDelete: _delete,
  );

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    ref.listen(basiraProvider.select((s) => s.notice), (_, next) {
      if (next != null) DashToast.error(context, next.message);
    });
    ref.listen(
      basiraProvider.select((s) => (s.exchanges, s.loadingThread)),
      (_, _) => _followEnd(),
    );
    final title = ref.watch(basiraProvider.select((s) => s.activeTitle));
    final width = MediaQuery.sizeOf(context).width;
    final pinned = width >= DashBreakpoints.xl;
    final gutter = DashBreakpoints.gutter(width);

    final header = Container(
      padding: EdgeInsetsDirectional.fromSTEB(
        gutter,
        width >= DashBreakpoints.lg ? Space.lg : Space.md,
        gutter,
        Space.md,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: DashPageHeader(
        title: title == null ? t('basira.title') : ownDirection(title),
        subtitle: t('basira.subtitle'),
        refreshAction: false,
        actions: [
          if (!pinned) ...[
            DashButton(
              label: t('basira.showConversations'),
              icon: 'message-square',
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onPressed: _showRail,
            ),
            DashIconButton(
              icon: 'message-square-plus',
              semanticLabel: t('basira.newChat'),
              variant: DashButtonVariant.outline,
              onPressed: _startNew,
            ),
          ],
          DashIconButton(
            icon: 'refresh-cw',
            semanticLabel: context.dashStrings.refresh,
            variant: DashButtonVariant.outline,
            loading: _refreshing,
            onPressed: _refresh,
          ),
        ],
      ),
    );

    return ColoredBox(
      color: c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pinned)
                  Container(
                    width: BasiraMetrics.rail,
                    padding: const EdgeInsets.all(Space.md),
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        end: BorderSide(color: c.hairline),
                      ),
                    ),
                    child: _rail(),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _transcript(width, gutter)),
                      _Composer(
                        gutter: gutter,
                        value: _question,
                        onChanged: (v) => setState(() => _question = v),
                        onSend: () => _send(_question),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _transcript(double width, double gutter) {
    final s = ref.watch(basiraProvider);
    final Widget content;
    if (s.loadingThread) {
      content = const _ThreadSkeleton();
    } else if (s.exchanges.isEmpty) {
      content = _Welcome(onPick: _send);
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xxl + Space.xs,
        children: [
          for (final x in s.exchanges)
            BasiraExchangeView(
              key: ValueKey(x.id),
              exchange: x,
              onRetry: () => _c.ask(x.question),
            ),
        ],
      );
    }
    final wide = width >= DashBreakpoints.sm;
    return SingleChildScrollView(
      key: BasiraPage.transcriptKey,
      controller: _scroll,
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: gutter,
        vertical: wide ? Space.xxl : Space.lg + Space.xs,
      ),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BasiraMetrics.measure),
          child: content,
        ),
      ),
    );
  }
}

/// Opens the conversation rail as a slide-over from the start side (left
/// in English, right in Arabic), 86% of the window up to 340.
Future<void> showBasiraRail(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final c = context.madarColors;
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: context.dashStrings.close,
    barrierColor: c.scrim,
    transitionDuration: DashMotion.of(context, DashMotion.slow),
    pageBuilder: (ctx, a, b) {
      final screen = MediaQuery.sizeOf(ctx).width;
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: (screen * 0.86).clamp(0, BasiraMetrics.sheet),
            height: double.infinity,
            decoration: BoxDecoration(
              color: ctx.madarColors.bg,
              border: BorderDirectional(
                end: BorderSide(color: ctx.madarColors.hairline),
              ),
              boxShadow: DashShadows.modal(ctx),
            ),
            child: SafeArea(child: _RailSheet(builder: builder)),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final rtl = Directionality.of(ctx) == TextDirection.rtl;
      return SlideTransition(
        position: Tween(
          begin: Offset(rtl ? 1 : -1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: DashMotion.ease)),
        child: child,
      );
    },
  );
}

class _RailSheet extends ConsumerWidget {
  const _RailSheet({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.md,
            Space.xs,
            Space.xs,
            Space.xs,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    t('basira.conversations'),
                    style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                  ),
                ),
              ),
              DashIconButton(
                icon: 'x',
                semanticLabel: context.dashStrings.close,
                color: c.textSecondary,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Builder(builder: builder),
          ),
        ),
      ],
    );
  }
}

/// The rail (`ConversationList`, REP-BAS-007/008).
class BasiraConversationList extends ConsumerWidget {
  const BasiraConversationList({
    required this.onOpen,
    required this.onNew,
    required this.onRename,
    required this.onDelete,
    super.key,
  });

  final ValueChanged<String> onOpen;
  final VoidCallback onNew;
  final ValueChanged<wire.ConversationSummary> onRename;
  final ValueChanged<wire.ConversationSummary> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final s = ref.watch(basiraProvider);
    final Widget list;
    if (s.loadingList) {
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: BasiraMetrics.tight,
        children: [
          for (var i = 0; i < 4; i++)
            const DashSkeleton(height: DashMetrics.target),
        ],
      );
    } else if (s.conversations.isEmpty) {
      list = Padding(
        padding: const EdgeInsetsDirectional.only(
          start: Space.xs,
          top: Space.sm,
        ),
        child: Text(
          t('basira.noChats'),
          style: DashType.small.copyWith(color: c.textSecondary),
        ),
      );
    } else {
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DashMetrics.hair,
        children: [
          for (final conv in s.conversations)
            _ConversationItem(
              key: ValueKey(conv.id),
              conversation: conv,
              active: conv.id == s.activeId,
              onOpen: () => onOpen(conv.id),
              onRename: () => onRename(conv),
              onDelete: () => onDelete(conv),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashButton(
          label: t('basira.newChat'),
          icon: 'message-square-plus',
          variant: DashButtonVariant.outline,
          expand: true,
          onPressed: onNew,
        ),
        Expanded(child: SingleChildScrollView(child: list)),
      ],
    );
  }
}

class _ConversationItem extends ConsumerStatefulWidget {
  const _ConversationItem({
    required this.conversation,
    required this.active,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    super.key,
  });

  final wire.ConversationSummary conversation;
  final bool active;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  ConsumerState<_ConversationItem> createState() => _ConversationItemState();
}

class _ConversationItemState extends ConsumerState<_ConversationItem> {
  bool _hovered = false;
  bool _focused = false;
  final DashPopoverController _menu = DashPopoverController();

  @override
  void initState() {
    super.initState();
    _menu.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _menu
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final conv = widget.conversation;
    final last = conv.lastTurnAt;
    final meta =
        '${t('basira.turnCount', count: conv.turnCount)}'
        '${last == null ? '' : ' · ${fmt.fmtDate(last)}'}';
    // On hover at 1280 and up; always on narrower windows and touch.
    final hoverOnly =
        MediaQuery.sizeOf(context).width >= DashBreakpoints.xl &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS;
    final showMenu = !hoverOnly || _hovered || _focused || _menu.isOpen;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        children: [
          DashIntent(
            onIntent: () => ref.read(basiraProvider.notifier).warmOpen(conv.id),
            child: DashPressable(
              onTap: widget.onOpen,
              selected: widget.active,
              semanticLabel: '${conv.title}, $meta',
              excludeChildSemantics: true,
              pressScale: false,
              builder: (context, s) => Container(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  BasiraMetrics.snug,
                  Space.sm,
                  Space.xxl + Space.xs,
                  Space.sm,
                ),
                decoration: BoxDecoration(
                  color: widget.active
                      ? c.muted
                      : (s.highlighted ? c.muted.withValues(alpha: 0.6) : null),
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The title's own direction, so a cut English title in
                    // the Arabic rail ends in its ellipsis (REP-BAS-007).
                    MadarClippedText(
                      conv.title,
                      textDirection: Bidi.startsWithRtl(conv.title)
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      textAlign: t.isRtl ? TextAlign.right : TextAlign.left,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashType.meta.copyWith(
                        fontWeight: FontWeight.w500,
                        color: widget.active || s.highlighted
                            ? c.textPrimary
                            : c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: DashMetrics.hair),
                    MadarClippedText(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashType.small.copyWith(
                        fontSize: BasiraMetrics.caption,
                        color: c.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            end: Space.xs,
            top: 0,
            bottom: 0,
            child: Center(
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (f) => setState(() => _focused = f),
                child: Opacity(
                  opacity: showMenu ? 1 : 0,
                  alwaysIncludeSemantics: true,
                  child: DashMenu(
                    controller: _menu,
                    items: [
                      DashMenuItem(
                        label: t('common.rename'),
                        icon: 'pencil',
                        onSelected: widget.onRename,
                      ),
                      DashMenuItem(
                        label: t('common.delete'),
                        icon: 'trash-2',
                        destructive: true,
                        onSelected: widget.onDelete,
                      ),
                    ],
                    builder: (context, m) => DashIconButton(
                      icon: 'more-horizontal',
                      semanticLabel: t('common.more'),
                      iconSize: IconSize.xs,
                      onPressed: m.toggle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadSkeleton extends StatelessWidget {
  const _ThreadSkeleton();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.lg,
      children: [
        DashSkeleton(height: Space.xl, width: box.maxWidth * 0.4),
        DashSkeleton(height: Space.xxl * 2 + Space.lg, width: box.maxWidth),
        DashSkeleton(height: Space.xxl * 6, width: box.maxWidth),
      ],
    ),
  );
}

/// The empty transcript (REP-BAS-012).
class _Welcome extends ConsumerWidget {
  const _Welcome({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final two = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final starters = [
      for (final key in basiraStarters)
        _Starter(label: t('basira.starters.$key'), onPick: onPick),
    ];
    return Padding(
      padding: EdgeInsets.symmetric(vertical: two ? Space.xl : Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              t('basira.welcomeTitle'),
              style: DashType.paneTitle.copyWith(color: c.textPrimary),
            ),
          ),
          const SizedBox(height: Space.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: DashMetrics.proseWide),
            child: Text(
              t('basira.welcomeBody'),
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
          ),
          const SizedBox(height: Space.xl + Space.xs),
          if (two)
            Column(
              spacing: Space.sm,
              children: [
                for (var i = 0; i < starters.length; i += 2)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Space.sm,
                      children: [
                        Expanded(child: starters[i]),
                        Expanded(
                          child: i + 1 < starters.length
                              ? starters[i + 1]
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.sm,
              children: starters,
            ),
        ],
      ),
    );
  }
}

class _Starter extends StatelessWidget {
  const _Starter({required this.label, required this.onPick});

  final String label;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: () => onPick(label),
      semanticLabel: label,
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        padding: const EdgeInsets.symmetric(
          horizontal: BasiraMetrics.roomy,
          vertical: Space.md,
        ),
        foregroundDecoration: dashFocusRing(
          context,
          s,
          BorderRadius.circular(Radii.md),
        ),
        decoration: BoxDecoration(
          color: s.highlighted ? c.hover : c.card,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.hairline),
        ),
        child: Text(label, style: DashType.body.copyWith(color: c.textPrimary)),
      ),
    );
  }
}

/// One question and what came back (REP-BAS-031): the question as a
/// heading, the answer as prose, then the evidence.
class BasiraExchangeView extends ConsumerWidget {
  const BasiraExchangeView({
    required this.exchange,
    required this.onRetry,
    super.key,
  });

  final BasiraExchange exchange;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final x = exchange;
    final reduced = DashMotion.reduced(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            ownDirection(x.question),
            style: DashType.sectionTitle.copyWith(color: c.textPrimary),
          ),
        ),
        const SizedBox(height: Space.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            if (x.pending && x.answer == null)
              _Working(step: x.step, querying: x.querying),
            if (x.answer case final answer? when answer.isNotEmpty)
              Text(
                ownDirection(answer),
                style: DashType.body.copyWith(
                  color: x.kind == 'clarify' ? c.textSecondary : c.textPrimary,
                ),
              ),
            if (x.capturedAt != null && x.results.isNotEmpty)
              Row(
                spacing: BasiraMetrics.tight,
                children: [
                  DashIcon('clock-3', size: Space.md, color: c.textSecondary),
                  Expanded(
                    child: Text(
                      t(
                        'basira.asAt',
                        args: {'when': fmt.fmtDateTime(x.capturedAt)},
                      ),
                      style: DashType.small.copyWith(
                        fontSize: BasiraMetrics.caption,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            for (final (i, block) in x.results.indexed)
              BasiraBlockCard(
                key: ValueKey('${x.id}:$i'),
                block: block,
                stale: x.capturedAt != null,
              ),
            if (x.error case final error?)
              _Failure(message: error, onRetry: onRetry),
          ],
        ),
      ],
    );
    if (reduced) return body;
    // Each exchange fades in (180 ms, a 6 px rise).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - v)),
          child: child,
        ),
      ),
      child: body,
    );
  }
}

/// The working line until the answer lands (REP-BAS-015).
class _Working extends ConsumerWidget {
  const _Working({this.step, this.querying});

  final int? step;
  final String? querying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final label = querying != null
        ? t('basira.running', args: {'what': querying})
        : (step ?? 0) > 1
        ? t('basira.rethinking')
        : t('basira.thinking');
    return Semantics(
      liveRegion: true,
      child: Row(
        spacing: Space.sm,
        children: [
          SizedBox.square(
            dimension: IconSize.xs,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: c.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              label,
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A failed question (REP-BAS-018): the server's sentence first, Retry
/// beside it.
class _Failure extends ConsumerWidget {
  const _Failure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final icon = DashIcon(
      'alert-circle',
      size: IconSize.xs,
      color: DashTone.danger.foreground(c),
    );
    final words = Text(
      ownDirection(message),
      style: DashType.meta.copyWith(color: c.textPrimary),
    );
    final retry = DashButton(
      label: t('common.retry'),
      icon: 'refresh-cw',
      variant: DashButtonVariant.outline,
      size: DashButtonSize.compact,
      onPressed: onRetry,
    );
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(BasiraMetrics.roomy),
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.danger.withValues(alpha: 0.3)),
        ),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.md,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: DashMetrics.hair),
                    child: icon,
                  ),
                  Expanded(child: words),
                  retry,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: BasiraMetrics.snug,
                children: [icon, words, retry],
              ),
      ),
    );
  }
}

/// The composer (REP-BAS-013/028): a growing box, a round Send, the
/// disclaimer under them.
class _Composer extends ConsumerWidget {
  const _Composer({
    required this.gutter,
    required this.value,
    required this.onChanged,
    required this.onSend,
  });

  final double gutter;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  /// Enter sends on a desktop; a touch keyboard's Enter is a new line.
  static bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final busy = ref.watch(basiraProvider.select((s) => s.busy));
    final canSend = !busy && value.trim().isNotEmpty;
    return Container(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: gutter,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BasiraMetrics.measure),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: Space.sm,
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: BasiraMetrics.composer,
                      ),
                      child: DashTextInput(
                        value: value,
                        onChanged: onChanged,
                        placeholder: t('basira.placeholder'),
                        semanticLabel: t('basira.placeholder'),
                        enabled: !busy,
                        minLines: 1,
                        maxLines: 6,
                        onKeyEvent: (node, event) {
                          final enter =
                              event.logicalKey == LogicalKeyboardKey.enter ||
                              event.logicalKey ==
                                  LogicalKeyboardKey.numpadEnter;
                          if (!enter ||
                              _touch ||
                              HardwareKeyboard.instance.isShiftPressed) {
                            return KeyEventResult.ignored;
                          }
                          if (event is KeyDownEvent) onSend();
                          return KeyEventResult.handled;
                        },
                      ),
                    ),
                  ),
                  _SendButton(
                    label: t('basira.send'),
                    busy: busy,
                    onPressed: canSend ? onSend : null,
                  ),
                ],
              ),
              Text(
                t('basira.disclaimer'),
                style: DashType.small.copyWith(
                  fontSize: BasiraMetrics.caption,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round Send (`size-11 rounded-full`), a spinner while busy.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.label, required this.busy, this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return DashPressable(
      onTap: onPressed,
      enabled: enabled,
      semanticLabel: label,
      tooltip: label,
      excludeChildSemantics: true,
      builder: (context, s) {
        final colors = dashButtonColors(
          context,
          DashButtonVariant.primary,
          s,
          enabled: enabled,
        );
        final round = BorderRadius.circular(Radii.pill);
        return Container(
          width: DashMetrics.target,
          height: DashMetrics.target,
          alignment: Alignment.center,
          foregroundDecoration: dashFocusRing(context, s, round),
          decoration: BoxDecoration(color: colors.fill, borderRadius: round),
          child: busy
              ? SizedBox.square(
                  dimension: IconSize.xs,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.fg,
                  ),
                )
              : DashIcon('arrow-up', size: IconSize.xs, color: colors.fg),
        );
      },
    );
  }
}

/// Rename (REP-BAS-026): pops the new title, or nothing.
class _RenameDialog extends ConsumerStatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  ConsumerState<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends ConsumerState<_RenameDialog> {
  late String _value = widget.initial;

  void _save() {
    if (_value.trim().isEmpty) return;
    Navigator.of(context).pop(_value);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return DashSurface(
      title: t('basira.renamePrompt'),
      body: DashTextInput(
        value: _value,
        autofocus: true,
        semanticLabel: t('basira.renamePrompt'),
        selectAllOnFocus: false,
        textInputAction: TextInputAction.done,
        onChanged: (v) => setState(() => _value = v),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(
          label: t('common.save'),
          onPressed: _value.trim().isEmpty ? null : _save,
        ),
      ],
    );
  }
}
