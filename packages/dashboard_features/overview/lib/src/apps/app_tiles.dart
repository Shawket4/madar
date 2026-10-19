/// The Madar apps, in the dashboard (web `features/setup/apps.tsx`): the same
/// list, icons, store badges and downloads pages as the marketing site. Every
/// tile opens the app's card: what it is, a QR code of its downloads page
/// (the tablet's camera opens it, so nobody types a URL on a till), its store
/// badge where it has one, and every other build. One component, two sizes:
/// the footer's small tile and the Setup hero's card.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show linkOpenerProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'apps.dart';

/// The app's name, line and scan hint (`apps.<key>.*`).
({String name, String line, String scan}) appCopy(Translator t, MadarApp a) => (
  name: t('apps.${a.name}.name'),
  line: t('apps.${a.name}.line'),
  scan: t('apps.${a.name}.scan'),
);

/// The app's icon (its own artwork, corners included).
class AppIcon extends StatelessWidget {
  const AppIcon(this.app, {this.size = 28, super.key});
  final MadarApp app;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset(app.icon, width: size, height: size),
  );
}

/// The app's downloads page as a QR code. Ink modules on a white tile in
/// both themes: a code drawn light on dark does not scan everywhere.
class AppQr extends ConsumerWidget {
  const AppQr(this.app, {this.size = 112, super.key});
  final MadarApp app;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final paper = MadarColors.light;
    return Semantics(
      image: true,
      label: t('apps.qrLabel', args: {'name': appCopy(t, app).name}),
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(Space.xs + DashMetrics.hair),
        decoration: BoxDecoration(
          color: paper.surface,
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(color: context.madarColors.hairline),
        ),
        child: SvgPicture.asset(
          app.qr(t.lang),
          colorFilter: ColorFilter.mode(paper.textPrimary, BlendMode.srcIn),
        ),
      ),
    );
  }
}

/// The stores' official badges (unaltered, at least 40 tall), only where the
/// app is listed; nothing for an app on no store.
class StoreBadges extends ConsumerWidget {
  const StoreBadges(this.app, {super.key});
  final MadarApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!app.isLive) return const SizedBox.shrink();
    final t = ref.watch(tProvider);
    final open = ref.watch(linkOpenerProvider);
    final name = appCopy(t, app).name;
    Widget badge(String label, String url, Widget art) => DashPressable(
      semanticLabel: '$label ${t('common.opensInNewTab')}',
      excludeChildSemantics: true,
      onTap: () => open(Uri.parse(url)),
      builder: (context, s) => Container(
        foregroundDecoration: dashFocusRing(
          context,
          s,
          BorderRadius.circular(Radii.xs),
        ),
        child: art,
      ),
    );
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (app.appStore case final url?)
          badge(
            t('apps.appStoreAlt', args: {'name': name}),
            url,
            SvgPicture.asset(appStoreBadge(t.lang), height: 40),
          ),
        // The Play artwork carries its own clear space: 58 shows it at 40.
        if (app.googlePlay case final url?)
          badge(
            t('apps.googlePlayAlt', args: {'name': name}),
            url,
            Image.asset(googlePlayBadge(t.lang), height: 58),
          ),
      ],
    );
  }
}

/// One app, whole: name and line, the QR to scan, its store badge, every
/// other build (the web's `AppCard`, the popover's content).
class AppCard extends ConsumerWidget {
  const AppCard(this.app, {super.key});
  final MadarApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final copy = appCopy(t, app);
    final downloads = t('apps.allDownloads');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.lg,
      children: [
        Row(
          spacing: Space.md,
          children: [
            AppIcon(app, size: 48),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(copy.name, style: DashType.bodyStrong),
                  Text(
                    copy.line,
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        Row(
          spacing: Space.lg,
          children: [
            AppQr(app),
            Expanded(
              child: Text(
                copy.scan,
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
        StoreBadges(app),
        DashPressable(
          semanticLabel: '$downloads ${t('common.opensInNewTab')}',
          excludeChildSemantics: true,
          isButton: false,
          pressScale: false,
          onTap: () => ref.read(linkOpenerProvider)(downloadsUri(t.lang, app)),
          builder: (context, s) => ConstrainedBox(
            constraints: const BoxConstraints(minHeight: DashMetrics.target),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                Flexible(
                  child: Text(
                    downloads,
                    style: DashType.bodyMedium.copyWith(
                      color: c.brand,
                      decoration: s.highlighted || s.focused
                          ? TextDecoration.underline
                          : null,
                      decorationColor: c.brand,
                    ),
                  ),
                ),
                // Up and out: up-left in Arabic.
                Transform.flip(
                  flipX: t.isRtl,
                  child: DashIcon(
                    'arrow-up-right',
                    size: IconSize.xs,
                    color: c.brand,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum AppTileSize {
  /// The footer's: the icon alone, 28 on a 44 target.
  small,

  /// The Setup hero's: the icon with the name and line, on the ink panel.
  large,
}

/// An app as a control that opens its card ([AppCard]). It lifts a little
/// under the pointer or the keyboard's focus (not under reduced motion).
class AppTile extends ConsumerWidget {
  const AppTile(
    this.app, {
    this.size = AppTileSize.small,
    this.lead,
    super.key,
  });

  final MadarApp app;
  final AppTileSize size;

  /// A line above the name (the hero's "Start here").
  final String? lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final copy = appCopy(t, app);
    final large = size == AppTileSize.large;
    return DashPopover(
      width: 320,
      maxHeight: 520,
      align: large ? DashPopoverAlign.start : DashPopoverAlign.center,
      anchor: (context, ctl) => DashPressable(
        key: ValueKey('app-tile-${app.name}'),
        semanticLabel: t('apps.open', args: {'name': copy.name}),
        tooltip: large ? null : copy.name,
        excludeChildSemantics: true,
        onTap: ctl.toggle,
        builder: (context, s) {
          final lift =
              (s.highlighted || s.focused || ctl.isOpen) &&
              !DashMotion.reduced(context);
          final face = large
              ? _LargeFace(app: app, copy: copy, lead: lead, state: s)
              : _SmallFace(app: app, state: s);
          return AnimatedSlide(
            offset: Offset(0, lift ? -0.04 * (large ? 1 : 3) : 0),
            duration: DashMotion.fast,
            curve: DashMotion.ease,
            child: face,
          );
        },
      ),
      content: (context, ctl) => SingleChildScrollView(
        padding: const EdgeInsets.all(Space.lg),
        child: AppCard(app),
      ),
    );
  }
}

class _SmallFace extends StatelessWidget {
  const _SmallFace({required this.app, required this.state});
  final MadarApp app;
  final DashPressState state;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.xs);
    return Container(
      width: DashMetrics.target,
      height: DashMetrics.target,
      alignment: Alignment.center,
      foregroundDecoration: dashFocusRing(context, state, radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xs - 2),
          boxShadow: state.highlighted ? DashShadows.popover(context) : null,
        ),
        child: AppIcon(app),
      ),
    );
  }
}

class _LargeFace extends StatelessWidget {
  const _LargeFace({
    required this.app,
    required this.copy,
    required this.lead,
    required this.state,
  });
  final MadarApp app;
  final ({String name, String line, String scan}) copy;
  final String? lead;
  final DashPressState state;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final radius = BorderRadius.circular(Radii.control);
    final hot = state.highlighted || state.focused;
    return AnimatedContainer(
      duration: DashMotion.fast,
      padding: const EdgeInsets.all(Space.md),
      foregroundDecoration: dashFocusRing(context, state, radius),
      decoration: BoxDecoration(
        color: hot ? c.chromeRaised : c.chromeAlt,
        borderRadius: radius,
        border: Border.all(
          color: hot
              ? MadarColors.dark.brand.withValues(alpha: 0.6)
              : c.onChrome.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        spacing: Space.md,
        children: [
          AppIcon(app, size: 44),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lead != null)
                  MadarClippedText(
                    lead!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.smallMedium.copyWith(
                      color: MadarColors.dark.brand,
                    ),
                  ),
                MadarClippedText(
                  copy.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyStrong.copyWith(color: c.onChrome),
                ),
                MadarClippedText(
                  copy.line,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.small.copyWith(color: c.onChromeMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Every app as a small tile with its label, for the frame's foot.
class MadarAppsRow extends ConsumerWidget {
  const MadarAppsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return Semantics(
      container: true,
      label: t('apps.footerLabel'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ExcludeSemantics(
              child: MadarClippedText(
                t('apps.footerLabel'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.small.copyWith(
                  color: context.madarColors.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.xs),
          for (final a in madarFamily) AppTile(a),
        ],
      ),
    );
  }
}

/// The footer slot ([DashArea.footer]).
Widget madarAppsFooter(BuildContext context) => const MadarAppsRow();
