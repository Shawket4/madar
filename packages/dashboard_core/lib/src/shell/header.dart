/// The ink header (`app-header.tsx`) and the phone's app bar: the sidebar
/// trigger, the command palette, the scope bar (`scope-bar.tsx`: the org
/// picker for platform admins, the branch picker, the period picker), the
/// theme and language toggles, and the user menu.
///
/// The chrome is ink in both themes, so its controls are drawn with the dark
/// palette (their menus open the same way); the work surface stays paper.
library;

import 'package:dashboard_api/dashboard_api.dart' show Org;
import 'package:dashboard_core/src/format/format.dart' show initials;
import 'package:dashboard_core/src/format/tz.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/scope/period.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/session/session.dart';
import 'package:dashboard_core/src/shell/command_palette.dart';
import 'package:dashboard_core/src/shell/shell_prefs.dart';
import 'package:dashboard_core/src/shell/sidebar.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chrome's height (the web's `h-14`, the POS top bar).
const double headerHeight = Metrics.buttonHeight;

/// The controls on the chrome wear the dark palette in both themes.
Widget onChrome(Widget child) => Theme(data: MadarTheme.dark(), child: child);

/// The wide header.
class DashHeader extends ConsumerWidget {
  const DashHeader({required this.paperContext, super.key});

  /// A context outside the chrome's palette (sheets open paper from it).
  final BuildContext paperContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Container(
      height: headerHeight,
      decoration: BoxDecoration(
        color: c.chrome,
        border: Border(bottom: BorderSide(color: c.sidebarBorder)),
      ),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.md),
      child: onChrome(
        LayoutBuilder(
          builder: (context, box) => Row(
            spacing: Space.sm,
            children: [
              DashIconButton(
                icon: 'panel-left',
                semanticLabel: t('shell.toggleSidebar'),
                color: c.onChromeMuted,
                onPressed: () =>
                    ref.read(sidebarCollapsedProvider.notifier).toggle(),
              ),
              PaletteButton(
                wide: box.maxWidth >= DashBreakpoints.lg - Space.xxl,
              ),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: Space.xs,
                      children: const [
                        DashScopeControls(),
                        SizedBox(width: Space.xs),
                        ThemeMenu(),
                        LanguageToggle(),
                        DashUserMenu(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The phone's app bar: the mark, search, the scope behind one button, the
/// toggles and the user menu (the web's mobile header, its sidebar trigger
/// replaced by the bottom bar's More).
class DashPhoneBar extends ConsumerWidget {
  const DashPhoneBar({required this.paperContext, super.key});

  final BuildContext paperContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Container(
      color: c.chrome,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: headerHeight,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.sidebarBorder)),
          ),
          padding: const EdgeInsetsDirectional.only(
            start: Space.md,
            end: Space.xs,
          ),
          child: onChrome(
            Row(
              children: [
                const MadarSymbol(size: Space.xxl - Space.xs, reversed: true),
                const SizedBox(width: Space.xs),
                DashIconButton(
                  icon: 'search',
                  semanticLabel: t('shell.searchPages'),
                  color: c.onChromeMuted,
                  onPressed: () => showDashCommandPalette(paperContext),
                ),
                const Spacer(),
                DashIconButton(
                  icon: 'sliders-horizontal',
                  semanticLabel: t('common.filters', defaultValue: 'Filters'),
                  color: c.onChromeMuted,
                  onPressed: () => showDashPickerSheet<void>(
                    paperContext,
                    title: t('common.filters', defaultValue: 'Filters'),
                    builder: (context) => const SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        Space.card,
                        Space.xs,
                        Space.card,
                        Space.xl,
                      ),
                      child: DashScopeControls(vertical: true),
                    ),
                  ),
                ),
                const ThemeMenu(),
                const LanguageToggle(),
                const DashUserMenu(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The search trigger (`CommandPalette`'s button): the word and the shortcut
/// on a wide header, the glyph alone when the header is tight.
class PaletteButton extends ConsumerWidget {
  const PaletteButton({this.wide = true, super.key});

  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final label = t('common.search', defaultValue: 'Search…');
    if (!wide) {
      return DashIconButton(
        icon: 'search',
        semanticLabel: label,
        variant: DashButtonVariant.outline,
        onPressed: () => showDashCommandPalette(context),
      );
    }
    return DashPressable(
      onTap: () => showDashCommandPalette(context),
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        width: DashMetrics.searchWidth - Space.xxl,
        height: DashMetrics.control,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          color: s.highlighted ? c.hover : c.card,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: c.input),
        ),
        child: Row(
          spacing: Space.sm,
          children: [
            DashIcon('search', size: IconSize.sm, color: c.textSecondary),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.xs + DashMetrics.hair,
                vertical: DashMetrics.hair,
              ),
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Radii.xs / 2),
                border: Border.all(color: c.hairline),
              ),
              child: Text(
                paletteShortcutLabel,
                style: DashType.small.copyWith(
                  color: c.textSecondary,
                  fontFamily: MadarType.monoFamily,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The key the branch select uses for "all branches".
const String _allBranches = '__all__';

/// The scope bar's controls, in a row (the header) or a column (the phone's
/// filters sheet).
class DashScopeControls extends ConsumerWidget {
  const DashScopeControls({this.vertical = false, super.key});

  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = <Widget>[
      const DashOrgPicker(),
      const DashBranchPicker(),
      const DashPeriodPicker(),
    ];
    return vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              for (final w in children) _Stretch(vertical: true, child: w),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: children,
          );
  }
}

class _Stretch extends StatelessWidget {
  const _Stretch({required this.vertical, required this.child});
  final bool vertical;
  final Widget child;

  @override
  Widget build(BuildContext context) => _VerticalScope(
    vertical: vertical,
    child: vertical
        ? Align(alignment: AlignmentDirectional.centerStart, child: child)
        : child,
  );
}

class _VerticalScope extends InheritedWidget {
  const _VerticalScope({required this.vertical, required super.child});
  final bool vertical;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_VerticalScope>()?.vertical ??
      false;

  @override
  bool updateShouldNotify(_VerticalScope old) => old.vertical != vertical;
}

/// Which shop a platform admin is looking at (`org-picker.tsx`). Inactive
/// shops are listed: a platform admin is exactly who needs to open one.
class DashOrgPicker extends ConsumerWidget {
  const DashOrgPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    if (session == null || !session.isPlatform) return const SizedBox.shrink();
    final t = ref.watch(tProvider);
    final q = ref.watch(orgsProvider);
    final orgs = q.value ?? const <Org>[];
    final selected = ref.watch(selectedOrgProvider);
    final vertical = _VerticalScope.of(context);
    return DashSelect<String>(
      options: [
        for (final o in orgs)
          DashOption(
            value: o.id,
            label: o.name,
            keywords: o.slug,
            hint: o.isActive
                ? null
                : t('orgs.inactive', defaultValue: 'Inactive'),
          ),
      ],
      value: selected?.id,
      searchable: true,
      expand: vertical,
      minWidth: DashMetrics.menu - Space.xxl - Space.xxl,
      placeholder: t('scope.pickOrg', defaultValue: 'Select a shop'),
      semanticLabel: t('scope.pickOrg', defaultValue: 'Select a shop'),
      sheetTitle: t('scope.pickOrg', defaultValue: 'Select a shop'),
      searchPlaceholder: t('scope.searchOrgs', defaultValue: 'Search shops…'),
      emptyText: t('scope.noOrgs', defaultValue: 'No shops found'),
      enabled: !q.isLoading,
      // Nothing picked is why the page is empty: say so.
      active: selected == null,
      onChanged: (id) async {
        final org = orgs.where((o) => o.id == id).firstOrNull;
        await ref
            .read(selectedOrgProvider.notifier)
            .select(id, logoUrl: org?.logoUrl);
        // A branch of the previous shop never rides into this one.
        await ref.read(scopeProvider.notifier).setBranch(null);
      },
    );
  }
}

/// The branch (or all branches), for whoever works every branch
/// (`canPickBranch`); everyone else is scoped by the server.
class DashBranchPicker extends ConsumerWidget {
  const DashBranchPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canPickBranchProvider)) return const SizedBox.shrink();
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final orgId = ref.watch(orgIdProvider);
    final q = ref.watch(branchesProvider);
    final vertical = _VerticalScope.of(context);
    if (orgId != null && q.isLoading && !q.hasValue) {
      return Semantics(
        liveRegion: true,
        label: t('common.loading', defaultValue: 'Loading…'),
        child: Container(
          height: DashMetrics.control,
          constraints: const BoxConstraints(minWidth: DashMetrics.menu / 2),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.md),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: c.input),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              SizedBox.square(
                dimension: IconSize.sm,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.textSecondary,
                ),
              ),
              Text(
                t('common.loading', defaultValue: 'Loading…'),
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    final active = ref.watch(activeBranchesProvider) ?? const [];
    final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
    final label = t('nav.branches', defaultValue: 'Branches');
    return DashSelect<String>(
      options: [
        DashOption(
          value: _allBranches,
          label: t('scope.allBranches', defaultValue: 'All branches'),
        ),
        for (final b in active) DashOption(value: b.id, label: b.name),
      ],
      value: branchId ?? _allBranches,
      leadingIcon: 'store',
      expand: vertical,
      minWidth: DashMetrics.menu / 2 + Space.xxl,
      semanticLabel: label,
      sheetTitle: label,
      onChanged: (v) => ref
          .read(scopeProvider.notifier)
          .setBranch(v == _allBranches ? null : v),
    );
  }
}

/// The period (`DateRangePicker` with the scope presets).
class DashPeriodPicker extends ConsumerWidget {
  const DashPeriodPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final scope = ref.watch(currentScopeProvider);
    final now = ref.watch(clockProvider)();
    DateTime day(DateTime instant) {
      final z = inZone(instant, scope.timezone);
      return DateTime(z.year, z.month, z.day);
    }

    return DashDateRangePicker(
      preset: scope.preset.wire,
      presets: [
        for (final p in scopePresets)
          DashPeriodPreset(
            value: p.wire,
            label: t(p.labelKey, defaultValue: p.fallback),
          ),
      ],
      from: day(scope.range.fromInstant),
      to: day(scope.range.toInstant),
      today: day(now),
      onSelectPreset: (wire) {
        final p = ScopePreset.fromWire(wire);
        if (p != null) ref.read(scopeProvider.notifier).setPreset(p);
      },
      onApplyCustom: (from, to) =>
          ref.read(scopeProvider.notifier).setCustomDays(from, to),
    );
  }
}

/// Light / Dark / System (`theme-toggle.tsx`).
class ThemeMenu extends ConsumerWidget {
  const ThemeMenu({this.color, super.key});

  /// The glyph's colour (the chrome's muted ink by default).
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final pref = ref.watch(themePrefProvider);
    final c = context.madarColors;
    final dark =
        pref == ThemePref.dark ||
        (pref == ThemePref.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final icon = pref == ThemePref.system
        ? 'monitor'
        : dark
        ? 'moon'
        : 'sun';
    return DashMenu(
      items: [
        for (final p in ThemePref.values)
          DashMenuItem(
            label: t(p.labelKey, defaultValue: p.fallback),
            icon: p.icon,
            checked: p == pref,
            onSelected: () => ref.read(themePrefProvider.notifier).set(p),
          ),
      ],
      builder: (context, ctl) => DashIconButton(
        icon: icon,
        semanticLabel: t('theme.toggle', defaultValue: 'Toggle theme'),
        color: color ?? c.onChromeMuted,
        onPressed: ctl.toggle,
      ),
    );
  }
}

/// One tap between English and Arabic; shows the language you would switch
/// to (`language-toggle.tsx`).
class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({this.color, super.key});

  /// The mark's colour (the chrome's muted ink by default).
  final Color? color;

  /// The other language's own mark, as the web draws it.
  static String markFor(String nextLang) => nextLang == 'ar' ? 'ع' : 'EN';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final next = lang == 'ar' ? 'en' : 'ar';
    final c = context.madarColors;
    return DashPressable(
      onTap: () => ref.read(localeProvider.notifier).set(next),
      semanticLabel: t('language.switch', defaultValue: 'Switch language'),
      tooltip: t('language.switch', defaultValue: 'Switch language'),
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        width: DashMetrics.target,
        height: DashMetrics.target,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s.highlighted ? c.hover : null,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Text(
          markFor(next),
          style: DashType.smallStrong.copyWith(color: color ?? c.onChromeMuted),
        ),
      ),
    );
  }
}

/// The avatar and its menu (`user-menu.tsx`): who is signed in, the
/// language and the theme, and Sign out.
class DashUserMenu extends ConsumerWidget {
  const DashUserMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final user = ref.watch(currentSessionProvider)?.user;
    final c = context.madarColors;
    final mark = initials(user?.name ?? '');
    return DashPopover(
      width: DashMetrics.menu + Space.xxl,
      align: DashPopoverAlign.end,
      anchor: (context, ctl) => DashPressable(
        onTap: ctl.toggle,
        semanticLabel: t('common.account', defaultValue: 'Account'),
        excludeChildSemantics: true,
        builder: (context, s) => SizedBox.square(
          dimension: DashMetrics.target,
          child: Center(
            child: Container(
              width: Space.xxl,
              height: Space.xxl,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.brand,
                shape: BoxShape.circle,
                border: s.focused
                    ? Border.all(color: c.onChrome, width: 2)
                    : null,
              ),
              child: mark.isEmpty
                  ? DashIcon('user-round', size: IconSize.sm, color: c.onBrand)
                  : Text(
                      mark,
                      style: DashType.smallStrong.copyWith(color: c.onBrand),
                    ),
            ),
          ),
        ),
      ),
      content: (context, ctl) => _UserMenuBody(close: ctl.close),
    );
  }
}

class _UserMenuBody extends ConsumerWidget {
  const _UserMenuBody({required this.close});
  final VoidCallback close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final user = ref.watch(currentSessionProvider)?.user;
    final lang = ref.watch(localeProvider);
    final pref = ref.watch(themePrefProvider);
    final role = user?.role;
    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Divider(height: 1, thickness: 1, color: c.hairline),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DashMetrics.hair,
              children: [
                MadarClippedText(
                  user?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                ),
                if (user?.email != null)
                  MadarClippedText(
                    user!.email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                if (role != null && role.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      t('roles.$role', defaultValue: role),
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          divider(),
          _MenuRow(
            icon: 'languages',
            label: t('nav.language', defaultValue: 'Language'),
            // The other language by its own name, as the appearance pane
            // names them.
            hint: lang == 'ar' ? 'English' : 'العربية',
            semanticLabel: t(
              'language.switch',
              defaultValue: 'Switch language',
            ),
            onTap: () {
              close();
              ref.read(localeProvider.notifier).toggle();
            },
          ),
          divider(),
          for (final p in ThemePref.values)
            _MenuRow(
              icon: p.icon,
              label: t(p.labelKey, defaultValue: p.fallback),
              checked: p == pref,
              onTap: () {
                close();
                ref.read(themePrefProvider.notifier).set(p);
              },
            ),
          divider(),
          _MenuRow(
            icon: 'log-out',
            label: t('nav.signOut', defaultValue: 'Sign Out'),
            destructive: true,
            onTap: () {
              close();
              ref.read(sessionProvider.notifier).signOut();
            },
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.checked,
    this.destructive = false,
    this.semanticLabel,
  });

  final String icon;
  final String label;
  final String? hint;
  final bool? checked;
  final bool destructive;
  final String? semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final fg = destructive ? c.errorText : c.textPrimary;
    return DashPressable(
      onTap: onTap,
      pressScale: false,
      checked: checked,
      semanticLabel: semanticLabel ?? label,
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(
          minHeight: DashMetrics.target - Space.xs,
        ),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.sm),
        decoration: BoxDecoration(
          color: s.highlighted || s.focused ? c.hover : null,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Row(
          spacing: Space.sm,
          children: [
            DashIcon(
              icon,
              size: IconSize.sm,
              color: destructive ? fg : c.textSecondary,
            ),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.body.copyWith(color: fg),
              ),
            ),
            if (checked ?? false)
              DashIcon('check', size: IconSize.sm, color: c.textPrimary),
            if (hint != null)
              Text(hint!, style: DashType.small.copyWith(color: c.textMuted)),
          ],
        ),
      ),
    );
  }
}
