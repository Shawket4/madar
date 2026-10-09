/// `/settings` Appearance (`features/settings/appearance-pane.tsx`,
/// SET-APP-001..009): this device's theme and language, the signed-in
/// account, and the legal documents. No request: everything is local.
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane: a section heading, no page gutter.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The About rows (`config/legal.ts`): the title's key and the address.
const List<(String, String)> appearanceLegal = [
  ('legal.privacy', 'https://legal.madar-pos.cloud/privacy-policy.html'),
  ('legal.terms', 'https://legal.madar-pos.cloud/terms-of-service.html'),
  ('legal.retention', 'https://legal.madar-pos.cloud/data-retention.html'),
];

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final theme = ref.watch(themePrefProvider);
    final lang = ref.watch(localeProvider);
    final user = ref.watch(currentSessionProvider)?.user;
    // Below 640 the theme segments are glyphs only (labels kept for readers).
    final iconsOnly = MediaQuery.sizeOf(context).width < DashBreakpoints.sm;
    final themes = [
      for (final p in ThemePref.values)
        DashOption(
          value: p,
          label: t(p.labelKey, defaultValue: p.fallback),
          icon: p.icon,
        ),
    ];
    void setTheme(ThemePref p) => ref.read(themePrefProvider.notifier).set(p);

    Widget group(String? title, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        if (title != null) DashSectionHeader(title: title),
        DashListCard(children: rows),
      ],
    );

    return DashPageScaffold(
      title: t('settings.appearance'),
      subtitle: t('settings.appearanceDesc'),
      width: DashPageWidth.reading,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xxl,
        children: [
          group(null, [
            DashListRow(
              key: const ValueKey('app-theme'),
              icon: theme.icon,
              title: t('settings.themeHint'),
              trailing: iconsOnly
                  ? _GlyphSegments(
                      options: themes,
                      value: theme,
                      onChanged: setTheme,
                    )
                  : DashSegmentedControl<ThemePref>(
                      options: themes,
                      value: theme,
                      onChanged: setTheme,
                      semanticLabel: t('settings.themeHint'),
                    ),
            ),
            DashListRow(
              key: const ValueKey('app-language'),
              icon: 'languages',
              title: t('nav.language'),
              trailing: DashSegmentedControl<String>(
                // The language names are written in their own language.
                options: const [
                  DashOption(value: 'en', label: 'English'),
                  DashOption(value: 'ar', label: 'العربية'),
                ],
                value: lang,
                onChanged: (v) => ref.read(localeProvider.notifier).set(v),
                semanticLabel: t('nav.language'),
              ),
            ),
          ]),
          if (user != null)
            group(t('settings.account'), [
              DashListRow(
                key: const ValueKey('app-account'),
                leading: _Initials(initials(user.name)),
                title: user.name,
                meta: user.email ?? '—',
                trailing: user.role.isEmpty
                    ? null
                    : DashStatusPill(
                        label: t('roles.${user.role}', defaultValue: user.role),
                      ),
              ),
            ]),
          group(t('settings.about'), [
            for (final (key, url) in appearanceLegal)
              DashListRow(
                key: ValueKey('app-$key'),
                icon: 'file-text',
                title: t(key),
                trailing: DashIcon(
                  'external-link',
                  size: IconSize.sm,
                  color: c.textMuted,
                ),
                onTap: () => ref.read(linkOpenerProvider)(Uri.parse(url)),
              ),
            DashListRow(
              key: const ValueKey('app-version'),
              leading: const _AppTile(),
              title: t('app.name'),
              meta: '© 2026 Madar',
              value: 'v1.0.0',
              numericValue: true,
            ),
          ]),
        ],
      ),
    );
  }
}

/// The account's initials disc (the web's `Avatar size-9`).
class _Initials extends StatelessWidget {
  const _Initials(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      width: Space.xxl + Space.xs,
      height: Space.xxl + Space.xs,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
      child: Text(
        text,
        style: DashType.smallMedium.copyWith(color: c.textPrimary),
      ),
    );
  }
}

/// Madar's "M" tile.
class _AppTile extends StatelessWidget {
  const _AppTile();

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      width: Space.xxl + Space.xs,
      height: Space.xxl + Space.xs,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        'M',
        style: DashType.bodyStrong.copyWith(color: c.textOnAccent),
      ),
    );
  }
}

/// The theme switch on a phone: [DashSegmentedControl]'s look with glyphs
/// only, each segment still named for screen readers.
class _GlyphSegments extends StatelessWidget {
  const _GlyphSegments({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<DashOption<ThemePref>> options;
  final ThemePref value;
  final ValueChanged<ThemePref> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      height: DashMetrics.control,
      padding: const EdgeInsets.all(DashMetrics.ring),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            DashPressable(
              onTap: () => onChanged(o.value),
              selected: o.value == value,
              checked: o.value == value,
              isButton: false,
              semanticLabel: o.label,
              excludeChildSemantics: true,
              pressScale: false,
              builder: (context, s) {
                final on = o.value == value;
                return Container(
                  height: DashMetrics.control - Space.xs - 2,
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  alignment: Alignment.center,
                  foregroundDecoration: dashFocusRing(
                    context,
                    s,
                    BorderRadius.circular(Radii.xs),
                  ),
                  decoration: BoxDecoration(
                    color: on
                        ? c.accent
                        : s.hovered
                        ? c.hover
                        : null,
                    borderRadius: BorderRadius.circular(Radii.xs),
                  ),
                  child: DashIcon(
                    o.icon!,
                    size: IconSize.sm,
                    color: on ? c.textOnAccent : c.textSecondary,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
