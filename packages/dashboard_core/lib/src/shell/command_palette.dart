/// The command palette (`command-palette.tsx`): Ctrl/Cmd+K anywhere in the
/// frame (or the search action), a search field, and every page this person
/// sees grouped as the sidebar groups them; typing narrows and ranks them,
/// the arrows move, Enter opens.
library;

import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/routes/nav.dart';
import 'package:dashboard_core/src/shell/prefetch.dart';
import 'package:dashboard_core/src/shell/shell_nav.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// One destination in the palette.
class PaletteItem {
  const PaletteItem({
    required this.to,
    required this.label,
    required this.icon,
    required this.group,
  });

  final String to;
  final String label;
  final String icon;
  final String group;

  /// What the search matches (cmdk's `value`): the label and the path.
  String get value => '$label $to';
}

/// The palette's groups for [query]: every visible leaf, grouped as the
/// sidebar groups them; with a query, only matches, best first, and groups
/// ordered by their best match (cmdk's sort).
List<(String, List<PaletteItem>)> paletteGroups(
  List<VisibleNavGroup> groups,
  Translator t,
  bool Function(NavLeaf) visible,
  String query,
) {
  final out = <(String, List<PaletteItem>, double)>[];
  for (final g in groups) {
    final heading = t(g.group.labelKey, defaultValue: g.group.fallback);
    final leaves = <NavLeaf>[
      for (final e in g.entries)
        ...switch (e) {
          NavLeaf() => visible(e) ? [e] : const <NavLeaf>[],
          NavParent(:final children) => children.where(visible),
        },
    ];
    final scored = <(PaletteItem, double)>[];
    for (final l in leaves) {
      final item = PaletteItem(
        to: l.to,
        label: t(l.labelKey, defaultValue: l.fallback),
        icon: l.icon,
        group: heading,
      );
      final score = paletteScore(item.value, query);
      if (score > 0) scored.add((item, score));
    }
    if (scored.isEmpty) continue;
    if (query.trim().isNotEmpty) {
      mergeSort(scored, compare: (a, b) => b.$2.compareTo(a.$2));
    }
    out.add((
      heading,
      [for (final s in scored) s.$1],
      scored.map((s) => s.$2).reduce((a, b) => a > b ? a : b),
    ));
  }
  if (query.trim().isNotEmpty) {
    mergeSort(out, compare: (a, b) => b.$3.compareTo(a.$3));
  }
  return [for (final g in out) (g.$1, g.$2)];
}

/// The palette list's cap on a wide window (cmdk's `max-h-[300px]` plus
/// the 44-point rows).
const double paletteListMaxHeight = 360;

/// Whether the platform's command key is ⌘ (Apple) rather than Ctrl.
bool get _apple =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// The shortcut's face (`⌘K` / `Ctrl K`).
String get paletteShortcutLabel => _apple ? '⌘K' : 'Ctrl K';

/// Whether [event] is the palette's shortcut (Ctrl+K or Cmd+K).
bool isPaletteShortcut(KeyEvent event) {
  if (event is! KeyDownEvent) return false;
  if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
  final k = HardwareKeyboard.instance;
  return k.isMetaPressed || k.isControlPressed;
}

/// Opens the palette over [context]; resolves when it closes.
Future<void> showDashCommandPalette(BuildContext context) =>
    showDashDialog<void>(
      context,
      width: DashMetrics.dialog,
      builder: (context) => const DashCommandPalette(),
    );

/// The palette's body.
class DashCommandPalette extends ConsumerStatefulWidget {
  const DashCommandPalette({super.key});

  @override
  ConsumerState<DashCommandPalette> createState() => _PaletteState();
}

class _PaletteState extends ConsumerState<DashCommandPalette> {
  String _query = '';
  int _cursor = 0;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _open(String to) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(to);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final visible = ref.watch(navLeafVisibleProvider);
    final groups = paletteGroups(visibleNavGroups(visible), t, visible, _query);
    final flat = [for (final g in groups) ...g.$2];
    if (_cursor >= flat.length) _cursor = flat.isEmpty ? 0 : flat.length - 1;
    final phone = DashBreakpoints.isPhone(context);
    var index = 0;
    final list = flat.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xl),
            child: Center(
              child: Text(
                t('common.noResults', defaultValue: 'No results found'),
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
            ),
          )
        : ListView(
            controller: _scroll,
            shrinkWrap: !phone,
            padding: const EdgeInsets.all(Space.xs),
            children: [
              for (final g in groups) ...[
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    Space.sm,
                    Space.sm,
                    Space.sm,
                    Space.xs,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      g.$1,
                      style: DashType.smallMedium.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
                for (final item in g.$2)
                  PrefetchOnIntent(
                    to: item.to,
                    child: _PaletteRow(
                      item: item,
                      selected: index++ == _cursor,
                      onTap: () => _open(item.to),
                    ),
                  ),
              ],
            ],
          );
    return DashSurface(
      scrollable: false,
      title: t('common.search', defaultValue: 'Search…'),
      description: t('commandPalette.hint', defaultValue: 'Jump to any page'),
      body: Column(
        mainAxisSize: phone ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashTextInput(
            value: _query,
            autofocus: true,
            leadingIcon: 'search',
            placeholder: t('common.searchPlaceholder', defaultValue: 'Search…'),
            semanticLabel: t('common.search', defaultValue: 'Search…'),
            textInputAction: TextInputAction.go,
            onChanged: (v) => setState(() {
              _query = v;
              _cursor = 0;
            }),
            onSubmitted: (_) {
              if (flat.isNotEmpty) _open(flat[_cursor].to);
            },
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                setState(
                  () => _cursor = (_cursor + 1).clamp(0, flat.length - 1),
                );
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                setState(
                  () => _cursor = (_cursor - 1).clamp(0, flat.length - 1),
                );
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.enter &&
                  flat.isNotEmpty) {
                _open(flat[_cursor].to);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
          ),
          const SizedBox(height: Space.sm),
          if (phone)
            Expanded(child: list)
          else
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: paletteListMaxHeight,
              ),
              child: list,
            ),
        ],
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final PaletteItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      selected: selected,
      pressScale: false,
      semanticLabel: item.label,
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.sm),
        decoration: BoxDecoration(
          color: selected || s.highlighted ? c.hover : null,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Row(
          spacing: Space.sm,
          children: [
            DashIcon(item.icon, size: IconSize.sm, color: c.textSecondary),
            Expanded(
              child: MadarClippedText(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
