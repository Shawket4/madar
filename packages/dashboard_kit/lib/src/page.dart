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

  /// Pull to refresh (phone) — the web's refetch.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final embedded = DashEmbeddedPages.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final phone = DashBreakpoints.isPhoneWidth(
          MediaQuery.sizeOf(context).width,
        );
        final gutter = embedded ? 0.0 : DashBreakpoints.gutter(w);
        final header = DashPageHeader(
          title: title,
          subtitle: subtitle,
          subtitleWidget: subtitleWidget,
          actions: actions,
          onBack: onBack,
          tabs: tabs,
          filters: filters,
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
        final unbounded = !constraints.hasBoundedHeight;
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
          physics: onRefresh != null
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
    this.tabs,
    this.filters,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final Widget? tabs;
  final Widget? filters;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final embedded = DashEmbeddedPages.of(context);
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
    this.semanticLabel,
    super.key,
  });

  final List<DashTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;
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
  });
  final DashTab<T> tab;
  final bool first;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: tab.enabled ? onTap : null,
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
    super.key,
  });
  final List<DashTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) =>
      DashTabStrip<T>(tabs: tabs, value: value, onChanged: onChanged);
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
    super.key,
  });

  final List<DashSectionTab> tabs;
  final String currentPath;
  final ValueChanged<String> onNavigate;

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
    );
  }
}
