import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'buttons.dart';
import 'foundation/l10n.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';

/// How wide a page's content may grow (the web's `PageWidth`).
enum DashPageWidth {
  /// Tables and boards, capped at 1600 so a 4K monitor keeps sane lines.
  full,

  /// Prose and detail (880).
  reading,

  /// A single form column (560).
  form;

  double get max => switch (this) {
    DashPageWidth.full => DashMetrics.pageFull,
    DashPageWidth.reading => DashMetrics.pageReading,
    DashPageWidth.form => DashMetrics.pageForm,
  };
}

/// Set by a shell that already owns the page (Settings): a nested
/// [DashPageScaffold] drops its gutter and renders its title as a pane
/// heading, so the screen keeps one title.
class DashEmbeddedPages extends InheritedWidget {
  const DashEmbeddedPages({required super.child, super.key});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashEmbeddedPages>() != null;

  @override
  bool updateShouldNotify(DashEmbeddedPages oldWidget) => false;
}

/// The open page's refresh by hand (owner rule, beyond the web): the shell
/// sets one around every page ([DashPageRefreshScope]). [DashPageScaffold]
/// makes it pull to refresh where the page scrolls, and a refresh action in
/// the header where the page owns its gestures (a canvas, a chat, a board);
/// the shell's Cmd/Ctrl+R calls [refresh].
class DashPageRefresh extends ChangeNotifier {
  DashPageRefresh(this._run);

  final Future<void> Function() _run;
  Future<void>? _running;
  final List<GlobalKey<RefreshIndicatorState>> _pulls = [];
  bool _disposed = false;

  /// A refresh is running (the header action spins).
  bool get refreshing => _running != null;

  /// Refreshes the open page, its pull indicator showing when it has one. A
  /// refresh already running is joined, never doubled.
  Future<void> refresh() {
    final pull = _pulls.lastOrNull?.currentState;
    if (_running == null && pull != null) return pull.show();
    return _go();
  }

  Future<void> _go() {
    final running = _running;
    if (running != null) return running;
    final f = _running = _run().whenComplete(() {
      _running = null;
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
    return f;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static DashPageRefresh? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DashPageRefreshScope>()
      ?.controller;
}

/// Puts [controller] over the pages below.
class DashPageRefreshScope extends InheritedWidget {
  const DashPageRefreshScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final DashPageRefresh controller;

  @override
  bool updateShouldNotify(DashPageRefreshScope oldWidget) =>
      controller != oldWidget.controller;
}

/// The pull indicator for [controller], known to it so Cmd/Ctrl+R shows it.
class _Pull extends StatefulWidget {
  const _Pull({required this.controller, required this.child});

  final DashPageRefresh controller;
  final Widget child;

  @override
  State<_Pull> createState() => _PullState();
}

class _PullState extends State<_Pull> {
  final _key = GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    widget.controller._pulls.add(_key);
  }

  @override
  void didUpdateWidget(_Pull oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller._pulls.remove(_key);
    widget.controller._pulls.add(_key);
  }

  @override
  void dispose() {
    widget.controller._pulls.remove(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    key: _key,
    onRefresh: widget.controller._go,
    color: context.madarColors.accent,
    backgroundColor: context.madarColors.card,
    child: widget.child,
  );
}

/// The header's refresh action, spinning while a refresh runs.
class _RefreshAction extends StatelessWidget {
  const _RefreshAction({required this.controller});

  final DashPageRefresh controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => DashIconButton(
      icon: 'refresh-cw',
      semanticLabel: context.dashStrings.refresh,
      variant: DashButtonVariant.outline,
      loading: controller.refreshing,
      onPressed: controller.refresh,
    ),
  );
}

/// A page (the web's `Page` + `PageHeader`):
///
/// ```text
/// gutter ┌ ‹ Title — 28/700 in a 48 row ─────────┐ actions ┐
///        │ Subtitle — 14 muted                    │         │
///        └────────────────────────────────────────┘         ┘
///        tabs (section or page) — underline strip
///        filters row
///        body
/// ```
///
/// The header and the body scroll together; with [fillBody] the body takes
/// the rest of the height instead (a table that scrolls under its own sticky
/// header, a board). Below [DashBreakpoints.phone] the title is 24, the
/// actions take their own full-width row, and [phoneBody] replaces [body]
/// when given.
class DashPageScaffold extends StatelessWidget {
  const DashPageScaffold({
    required this.title,
    required this.body,
    this.subtitle,
    this.subtitleWidget,
    this.actions = const [],
    this.onBack,
    this.onBackIntent,
    this.tabs,
    this.filters,
    this.phoneBody,
    this.width = DashPageWidth.full,
    this.fillBody = false,
    this.scrollController,
    this.onRefresh,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// A richer subtitle (a link, figures).
  final Widget? subtitleWidget;

  /// Header actions, end side (buttons, an export).
  final List<Widget> actions;

  /// A pushed page's back button.
  final VoidCallback? onBack;

  /// Back is about to be pressed ([DashIntent]): warm the page it returns to
  /// (`ref.prefetchRoute`).
  final VoidCallback? onBackIntent;

  /// A [DashSectionTabs] or [DashPageTabs] strip under the title.
  final Widget? tabs;

  /// The filter row (a [DashFilterBar]).
  final Widget? filters;
  final Widget body;

  /// The phone layout's body, when it differs from [body].
  final Widget? phoneBody;
  final DashPageWidth width;

  /// The body fills the remaining height instead of scrolling with the
  /// header.
  final bool fillBody;
  final ScrollController? scrollController;

  /// Pull to refresh (phone) — the web's refetch. Without it the shell's
  /// [DashPageRefresh] refreshes the page.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final embedded = DashEmbeddedPages.of(context);
    final shellRefresh = onRefresh == null
        ? DashPageRefresh.maybeOf(context)
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final phone = DashBreakpoints.isPhoneWidth(
          MediaQuery.sizeOf(context).width,
        );
        final gutter = embedded ? 0.0 : DashBreakpoints.gutter(w);
        final unbounded = !constraints.hasBoundedHeight;
        final header = DashPageHeader(
          title: title,
          subtitle: subtitle,
          subtitleWidget: subtitleWidget,
          actions: actions,
          onBack: onBack,
          onBackIntent: onBackIntent,
          tabs: tabs,
          filters: filters,
          // A page that owns its height has nothing to pull.
          refreshAction: fillBody && !unbounded,
        );
        final content = phone && phoneBody != null ? phoneBody! : body;
        final pad = EdgeInsetsDirectional.only(
          start: gutter,
          end: gutter,
          top: embedded ? 0 : (w >= DashBreakpoints.lg ? Space.lg : Space.md),
          bottom: embedded ? 0 : Space.xxl,
        );
        Widget capped(Widget child) => Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width.max),
            child: child,
          ),
        );
        if (fillBody && !unbounded) {
          return Padding(
            padding: pad,
            child: capped(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: Space.xl),
                  Expanded(child: content),
                ],
              ),
            ),
          );
        }
        final column = capped(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              header,
              const SizedBox(height: Space.xl),
              content,
            ],
          ),
        );
        if (unbounded) return Padding(padding: pad, child: column);
        Widget scroll = SingleChildScrollView(
          controller: scrollController,
          physics: onRefresh != null || shellRefresh != null
              ? const AlwaysScrollableScrollPhysics()
              : null,
          padding: pad,
          child: column,
        );
        if (onRefresh != null) {
          scroll = RefreshIndicator(
            onRefresh: onRefresh!,
            color: context.madarColors.accent,
            backgroundColor: context.madarColors.card,
            child: scroll,
          );
        } else if (shellRefresh != null) {
          scroll = _Pull(controller: shellRefresh, child: scroll);
        }
        return scroll;
      },
    );
  }
}

/// The page's header block on its own (for a page that lays itself out).
class DashPageHeader extends StatelessWidget {
  const DashPageHeader({
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.actions = const [],
    this.onBack,
    this.onBackIntent,
    this.tabs,
    this.filters,
    this.refreshAction = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final List<Widget> actions;
  final VoidCallback? onBack;

  /// Back is about to be pressed: warm the page it returns to.
  final VoidCallback? onBackIntent;
  final Widget? tabs;
  final Widget? filters;

  /// Ends the actions with the shell's refresh ([DashPageRefresh]), for a
  /// page with nothing to pull; never on an embedded pane.
  final bool refreshAction;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final embedded = DashEmbeddedPages.of(context);
    final refresh = refreshAction && !embedded
        ? DashPageRefresh.maybeOf(context)
        : null;
    final actions = [
      ...this.actions,
      if (refresh != null) _RefreshAction(controller: refresh),
    ];
    final phone = DashBreakpoints.isPhone(context);
    final sub =
        subtitleWidget ??
        (subtitle == null
            ? null
            : Text(
                subtitle!,
                style: DashType.body.copyWith(color: c.textSecondary),
              ));
    final below = [?tabs, ?filters];

    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.start,
            spacing: Space.lg,
            runSpacing: Space.sm,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: DashType.paneTitle.copyWith(color: c.textPrimary),
                    ),
                  ),
                  if (sub != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: sub,
                    ),
                ],
              ),
              if (actions.isNotEmpty)
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: actions,
                ),
            ],
          ),
          ...below,
        ],
      );
    }

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: DashMetrics.headerRow,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              header: true,
              child: MadarClippedText(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (phone ? DashType.pageTitlePhone : DashType.pageTitle)
                    .copyWith(color: c.textPrimary),
              ),
            ),
          ),
        ),
        if (sub != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: DashMetrics.proseWide),
            child: sub,
          ),
      ],
    );
    final back = onBack == null
        ? null
        : SizedBox(
            height: DashMetrics.headerRow,
            child: Center(
              child: DashIconButton(
                icon: DashIcon.backward(context),
                semanticLabel: context.dashStrings.back,
                variant: DashButtonVariant.outline,
                iconSize: IconSize.lg,
                onPressed: onBack,
                onIntent: onBackIntent,
              ),
            ),
          );
    final actionRow = actions.isEmpty
        ? null
        : Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        if (phone)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.md,
                children: [
                  ?back,
                  Expanded(child: titleBlock),
                ],
              ),
              ?actionRow,
            ],
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                ?back,
                Expanded(child: titleBlock),
                if (actionRow != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: DashMetrics.headerRow,
                      maxWidth: constraints.maxWidth * 0.6,
                    ),
                    child: Center(widthFactor: 1, child: actionRow),
                  ),
              ],
            ),
          ),
        ...below,
      ],
    );
  }
}

/// One tab of a [DashTabStrip].
@immutable
class DashTab<T> {
  const DashTab({
    required this.value,
    required this.label,
    this.count,
    this.enabled = true,
  });
  final T value;
  final String label;

  /// A small count after the label.
  final int? count;
  final bool enabled;
}

/// The underline tab strip the web draws for page and section tabs: 44
/// tall, 14/500 labels, the active tab inked with a 2px underline over a
/// hairline track, scrolling sideways when it does not fit.
class DashTabStrip<T> extends StatelessWidget {
  const DashTabStrip({
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.onIntent,
    this.semanticLabel,
    super.key,
  });

  final List<DashTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  /// A tab is about to be pressed ([DashIntent]): warm the read it shows.
  final ValueChanged<T>? onIntent;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Semantics(
      label: semanticLabel,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.hairline)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                _TabButton<T>(
                  tab: tabs[i],
                  first: i == 0,
                  active: tabs[i].value == value,
                  onTap: () => onChanged(tabs[i].value),
                  onIntent: onIntent == null
                      ? null
                      : () => onIntent!(tabs[i].value),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton<T> extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.first,
    required this.active,
    required this.onTap,
    this.onIntent,
  });
  final DashTab<T> tab;
  final bool first;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onIntent;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: tab.enabled ? onTap : null,
      onIntent: onIntent,
      enabled: tab.enabled,
      selected: active,
      pressScale: false,
      semanticLabel: tab.label,
      excludeChildSemantics: true,
      builder: (context, s) {
        final fg = !tab.enabled
            ? c.disabledText
            : active || s.hovered
            ? c.textPrimary
            : c.textSecondary;
        return AnimatedContainer(
          duration: DashMotion.of(context, DashMotion.base),
          height: DashMetrics.tab,
          padding: EdgeInsetsDirectional.only(
            start: first ? 0 : Space.md,
            end: Space.md,
          ),
          foregroundDecoration: dashFocusRing(
            context,
            s,
            BorderRadius.circular(Radii.xs),
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? c.textPrimary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs + DashMetrics.hair,
            children: [
              Text(tab.label, style: DashType.bodyMedium.copyWith(color: fg)),
              if (tab.count != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.xs + DashMetrics.hair,
                  ),
                  decoration: BoxDecoration(
                    color: c.muted,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    '${tab.count}',
                    style: DashType.monoMedium.copyWith(
                      fontSize: 12,
                      color: c.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// In-page tabs over one page's views (the web's `PageTabsList` +
/// `PageTabsTrigger`).
class DashPageTabs<T> extends StatelessWidget {
  const DashPageTabs({
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.onIntent,
    super.key,
  });
  final List<DashTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  /// A tab is about to be pressed: warm the read it shows.
  final ValueChanged<T>? onIntent;

  @override
  Widget build(BuildContext context) => DashTabStrip<T>(
    tabs: tabs,
    value: value,
    onChanged: onChanged,
    onIntent: onIntent,
  );
}

/// One route-level section tab: a label and where it goes.
@immutable
class DashSectionTab {
  const DashSectionTab({required this.path, required this.label});
  final String path;
  final String label;
}

/// Route-level section tabs (Access: Users · Roles): the active tab is the
/// one whose path is [currentPath] or a parent of it; [onNavigate] goes.
class DashSectionTabs extends StatelessWidget {
  const DashSectionTabs({
    required this.tabs,
    required this.currentPath,
    required this.onNavigate,
    this.onIntent,
    super.key,
  });

  final List<DashSectionTab> tabs;
  final String currentPath;
  final ValueChanged<String> onNavigate;

  /// A tab is about to be pressed: warm its page (`ref.prefetchRoute`).
  final ValueChanged<String>? onIntent;

  /// The tab [path] that is active for [current].
  static String? activeFor(List<DashSectionTab> tabs, String current) {
    String? best;
    for (final t in tabs) {
      if (current == t.path) return t.path;
      final deeper = best == null || t.path.length > best.length;
      if (current.startsWith('${t.path}/') && deeper) best = t.path;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return DashTabStrip<String>(
      tabs: [for (final t in tabs) DashTab(value: t.path, label: t.label)],
      value: activeFor(tabs, currentPath) ?? '',
      onChanged: onNavigate,
      onIntent: onIntent,
    );
  }
}
