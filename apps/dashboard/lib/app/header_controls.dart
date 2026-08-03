import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart';
import 'package:table_calendar/table_calendar.dart';

import 'providers.dart';

const String _kAllBranches = '__all__';

/// A pill-shaped header control. The label is [Flexible] so the pill shrinks
/// (ellipsizes) instead of overflowing when the header is tight.
class HeaderPill extends StatelessWidget {
  const HeaderPill({
    required this.leading,
    required this.label,
    this.chevron = true,
    this.muted = false,
    super.key,
  });

  final Widget leading;
  final String label;
  final bool chevron;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      height: 38,
      padding: const EdgeInsetsDirectional.fromSTEB(Space.md, 0, Space.sm, 0),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: Space.sm),
          Flexible(
            child: Text(
              label,
              style: MadarType.title.copyWith(
                color: muted ? c.textMuted : c.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              maxLines: 1,
            ),
          ),
          if (chevron) ...[
            const SizedBox(width: Space.xs),
            MadarIcon('chevron.down', tint: c.textMuted, size: IconSize.md),
          ],
        ],
      ),
    );
  }
}

RoundedRectangleBorder _menuShape(MadarColors c, double r) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(r),
      side: BorderSide(color: c.border),
    );

BranchView? _find(List<BranchView> list, String? id) {
  for (final b in list) {
    if (b.id == id) return b;
  }
  return null;
}

class BranchSelector extends ConsumerWidget {
  const BranchSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    final t = ref.watch(tProvider);
    final branches = ref.watch(branchesProvider);
    final selectedId = ref.watch(scopeProvider)?.branchId;
    final allSelected = selectedId == null;

    Widget row(String icon, String label, bool active) => Row(
      children: [
        MadarIcon(
          icon,
          tint: active ? c.accent : c.textMuted,
          size: IconSize.lg,
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(
            label,
            style: MadarType.body.copyWith(
              color: active ? c.accent : c.textPrimary,
              fontWeight: active ? FontWeight.w700 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (active) MadarIcon('checkmark', tint: c.accent, size: IconSize.md),
      ],
    );

    return branches.when(
      loading: () => HeaderPill(
        leading: MadarIcon('building.2', tint: c.textMuted, size: IconSize.lg),
        label: t('common.loading'),
        chevron: false,
        muted: true,
      ),
      error: (_, _) => HeaderPill(
        leading: MadarIcon('building.2', tint: c.accent, size: IconSize.lg),
        label: t('scope.allBranches'),
        chevron: false,
      ),
      data: (list) {
        final selected = _find(list, selectedId);
        return PopupMenuButton<String>(
          tooltip: '',
          padding: EdgeInsets.zero,
          position: PopupMenuPosition.under,
          color: c.surface,
          elevation: 8,
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
          shape: _menuShape(c, Radii.sm),
          onSelected: (v) => ref
              .read(scopeProvider.notifier)
              .setBranch(v == _kAllBranches ? null : v),
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: _kAllBranches,
              child: row('building.2', t('scope.allBranches'), allSelected),
            ),
            const PopupMenuDivider(),
            for (final b in list)
              PopupMenuItem<String>(
                value: b.id,
                child: row('storefront', b.name, b.id == selectedId),
              ),
          ],
          child: HeaderPill(
            leading: MadarIcon(
              allSelected ? 'building.2' : 'storefront',
              tint: c.accent,
              size: IconSize.lg,
            ),
            label: allSelected
                ? t('scope.allBranches')
                : (selected?.name ?? t('scope.selectBranch')),
          ),
        );
      },
    );
  }
}

/// Human label for the active period (preset name or the custom range).
String periodLabel(PeriodState s, String Function(String) t) {
  String d(DateTime x) =>
      '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}';
  return switch (s.preset) {
    Period.today => t('period.today'),
    Period.yesterday => t('period.yesterday'),
    Period.d7 => t('period.d7'),
    Period.d30 => t('period.d30'),
    Period.mtd => t('period.mtd'),
    Period.custom =>
      s.customFrom == null
          ? t('period.custom')
          : '${d(s.customFrom!)} – ${d(s.customTo ?? s.customFrom!)}',
  };
}

/// The period selector: a pill that opens an anchored popover (built on
/// OverlayPortal — MenuAnchor can't lay out a rich calendar child) with quick
/// presets + an inline range calendar, like the web dashboard.
class PeriodSelector extends ConsumerStatefulWidget {
  const PeriodSelector({super.key});

  @override
  ConsumerState<PeriodSelector> createState() => _PeriodSelectorState();
}

class _PeriodSelectorState extends ConsumerState<PeriodSelector> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  void _close() => _portal.hide();

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = ref.watch(tProvider);
    final state = ref.watch(periodProvider);

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Stack(
          children: [
            // Tap-outside barrier.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _close,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 6),
              child: Material(
                color: c.surface,
                elevation: 8,
                borderRadius: BorderRadius.circular(Radii.md),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(color: c.border),
                  ),
                  padding: const EdgeInsets.all(Space.md),
                  child: _PeriodPanel(
                    current: state,
                    t: t,
                    onPreset: (p) {
                      ref.read(periodProvider.notifier).setPreset(p);
                      _close();
                    },
                    onApply: (from, to) {
                      ref.read(periodProvider.notifier).setCustom(from, to);
                      _close();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: () => _portal.isShowing ? _portal.hide() : _portal.show(),
          child: HeaderPill(
            leading: Icon(
              Icons.calendar_today_outlined,
              color: c.accent,
              size: IconSize.lg,
            ),
            label: periodLabel(state, t),
          ),
        ),
      ),
    );
  }
}

class _PeriodPanel extends StatefulWidget {
  const _PeriodPanel({
    required this.current,
    required this.t,
    required this.onPreset,
    required this.onApply,
  });

  final PeriodState current;
  final String Function(String) t;
  final void Function(Period) onPreset;
  final void Function(DateTime from, DateTime to) onApply;

  @override
  State<_PeriodPanel> createState() => _PeriodPanelState();
}

class _PeriodPanelState extends State<_PeriodPanel> {
  DateTime? _start;
  DateTime? _end;
  late DateTime _focused;

  @override
  void initState() {
    super.initState();
    _start = widget.current.customFrom;
    _end = widget.current.customTo;
    _focused = _end ?? _start ?? DateTime.now();
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = widget.t;
    final now = DateTime.now();
    final rangeText = _start == null
        ? '—'
        : '${_fmt(_start!)}  →  ${_fmt(_end ?? _start!)}';

    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final (p, key) in const [
                (Period.today, 'period.today'),
                (Period.yesterday, 'period.yesterday'),
                (Period.d7, 'period.d7'),
                (Period.d30, 'period.d30'),
                (Period.mtd, 'period.mtd'),
              ])
                _PresetChip(
                  label: t(key),
                  active: widget.current.preset == p,
                  onTap: () => widget.onPreset(p),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Divider(color: c.border, height: 1),
          const SizedBox(height: Space.xs),
          TableCalendar<void>(
            firstDay: DateTime(now.year - 3),
            lastDay: now,
            focusedDay: _focused,
            rangeStartDay: _start,
            rangeEndDay: _end,
            rangeSelectionMode: RangeSelectionMode.toggledOn,
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: ''},
            startingDayOfWeek: StartingDayOfWeek.monday,
            rowHeight: 40,
            daysOfWeekHeight: 20,
            onPageChanged: (f) => _focused = f,
            onRangeSelected: (start, end, focused) {
              setState(() {
                _start = start;
                _end = end;
                _focused = focused;
              });
            },
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: MadarType.title.copyWith(color: c.textPrimary),
              leftChevronIcon: Icon(
                Icons.chevron_left,
                color: c.textSecondary,
                size: 20,
              ),
              rightChevronIcon: Icon(
                Icons.chevron_right,
                color: c.textSecondary,
                size: 20,
              ),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: MadarType.labelSm.copyWith(color: c.textMuted),
              weekendStyle: MadarType.labelSm.copyWith(color: c.textMuted),
            ),
            calendarStyle: CalendarStyle(
              rangeHighlightColor: c.accentBg,
              rangeStartDecoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
              ),
              rangeEndDecoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
              ),
              rangeStartTextStyle: MadarType.body.copyWith(
                color: c.textOnAccent,
              ),
              rangeEndTextStyle: MadarType.body.copyWith(color: c.textOnAccent),
              withinRangeTextStyle: MadarType.body.copyWith(
                color: c.textPrimary,
              ),
              todayDecoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              todayTextStyle: MadarType.body.copyWith(color: c.accent),
              defaultTextStyle: MadarType.body.copyWith(color: c.textPrimary),
              weekendTextStyle: MadarType.body.copyWith(color: c.textSecondary),
              outsideTextStyle: MadarType.body.copyWith(color: c.textMuted),
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  rangeText,
                  style: MadarType.bodySm.copyWith(color: c.textSecondary),
                ),
              ),
              FilledButton(
                onPressed: _start == null
                    ? null
                    : () => widget.onApply(_start!, _end ?? _start!),
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.textOnAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                ),
                child: Text(t('common.apply')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Material(
      color: active ? c.accent : c.surfaceAlt,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.md,
            vertical: Space.xs,
          ),
          child: Text(
            label,
            style: MadarType.label.copyWith(
              color: active ? c.textOnAccent : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

String _roleLabel(String role) => role
    .replaceAll('_', ' ')
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// The account menu behind the avatar: identity, language + appearance
/// toggles, and sign out.
class UserMenu extends ConsumerWidget {
  const UserMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    final t = ref.watch(tProvider);
    final session = ref.watch(sessionProvider);
    final locale = ref.watch(localeProvider);
    final dark = ref.watch(darkModeProvider);
    final name = session?.displayName ?? '?';

    return PopupMenuButton<String>(
      tooltip: '',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      color: c.surface,
      elevation: 10,
      constraints: const BoxConstraints(minWidth: 264, maxWidth: 300),
      shape: _menuShape(c, Radii.md),
      onSelected: (v) {
        switch (v) {
          case 'lang':
            ref.read(localeProvider.notifier).toggle();
          case 'theme':
            ref.read(darkModeProvider.notifier).toggle();
          case 'signout':
            ref.read(sessionProvider.notifier).signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: c.accentBg,
                child: Text(
                  initialsOf(name),
                  style: MadarType.title.copyWith(color: c.accent),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: MadarType.title.copyWith(color: c.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((session?.role ?? '').isNotEmpty)
                      Text(
                        _roleLabel(session!.role),
                        style: MadarType.bodySm.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'lang',
          child: _ActionRow(
            icon: Icon(
              Icons.language,
              color: c.textSecondary,
              size: IconSize.xl,
            ),
            title: t('user.language'),
            value: locale == 'ar' ? 'العربية' : 'English',
          ),
        ),
        PopupMenuItem<String>(
          value: 'theme',
          child: _ActionRow(
            icon: Icon(
              dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              color: c.textSecondary,
              size: IconSize.xl,
            ),
            title: t('user.appearance'),
            value: dark ? t('user.dark') : t('user.light'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'signout',
          child: Row(
            children: [
              Icon(Icons.logout, color: c.danger, size: IconSize.xl),
              const SizedBox(width: Space.md),
              Text(
                t('common.signOut'),
                style: MadarType.body.copyWith(
                  color: c.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: Space.sm),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: c.accentBg,
          child: Text(
            initialsOf(name),
            style: MadarType.label.copyWith(color: c.accent),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final Widget icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Row(
      children: [
        icon,
        const SizedBox(width: Space.md),
        Expanded(
          child: Text(
            title,
            style: MadarType.body.copyWith(color: c.textPrimary),
          ),
        ),
        Text(value, style: MadarType.label.copyWith(color: c.textMuted)),
      ],
    );
  }
}
