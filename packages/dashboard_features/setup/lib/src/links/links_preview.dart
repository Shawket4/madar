/// The editor's preview (SET-LNK-023): the shop's public links page
/// (`features/links/public/links-page.tsx`) as a customer gets it, reading
/// what is SAVED (`GET /public/orgs/links?org_id=`), at the page's narrow
/// layout. Buttons, socials, directions and calls open outside the app as
/// the page's links do; the page's share / theme / language controls are
/// drawn, not live (they would act on the dashboard, see the divergences).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show LinksItemKind, PublicLinksBranch, PublicLinksItem, PublicLinksPage;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart'
    show
        DashLegalLinks,
        ShellWordmark,
        copyrightLine,
        linkOpenerProvider,
        madarSiteHref;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand_appearance/brand_image.dart';
import '../shared/social_links.dart' show socialPlatforms;
import 'links_data.dart';
import 'links_providers.dart';

/// The public page's fixed sizes (Tailwind's, in px).
abstract final class LinksPreviewMetrics {
  /// `max-w-[480px]`: the page's column.
  static const double column = 480;

  /// `h-44`: the cover.
  static const double cover = 176;

  /// `h-24`: the scrim over the cover's top.
  static const double scrim = 96;

  /// `size-24`: the mark's plate; `rounded-[28px]`.
  static const double plate = 96;
  static const double plateRadius = 28;

  /// `-mt-12`: how far the mark rides over the cover's edge.
  static const double overlap = 48;

  /// `size-9`: a header control.
  static const double control = 36;

  /// `min-h-[72px]`: a button.
  static const double row = 72;

  /// `size-11`: a button's glyph tile.
  static const double tile = 44;

  /// `text-[30px]`: the shop's name; `text-4xl`: the initial on the plate.
  static const double name = 30;
  static const double initial = 36;

  /// The footer badge's Madar symbol (`size-[26px]`) and wordmark height.
  static const double symbol = 26;
  static const double wordmark = 16;
}

/// The glyph per button (`ICON`).
const Map<String, String> _glyph = {
  'order': 'shopping-bag',
  'menu': 'book-open',
  'rewards': 'wallet',
  'book': 'calendar-days',
  'custom': 'link-2',
};

class LinksPublicPreview extends ConsumerWidget {
  const LinksPublicPreview({required this.orgId, super.key});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final q = ref.watch(publicLinksProvider(orgId));
    if (q.awaitingFirst) return const _PreviewSkeleton();
    final page = q.value;
    if (q.failedFirst || page == null) {
      // `PageNotice`: the page's own words, with a retry.
      return Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: DashErrorState(
          framed: false,
          title: t('links.error.title'),
          message: t('links.error.body'),
          retryLabel: t('common.retry'),
          retrying: q.isLoading,
          onRetry: () => ref.invalidate(publicLinksProvider(orgId)),
        ),
      );
    }
    return _PublicPage(page: page);
  }
}

class _PreviewSkeleton extends ConsumerWidget {
  const _PreviewSkeleton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    label: ref.watch(tProvider)('common.loading'),
    child: const Padding(
      padding: EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          DashSkeleton(
            width: LinksPreviewMetrics.plate,
            height: LinksPreviewMetrics.plate,
            radius: LinksPreviewMetrics.plateRadius,
          ),
          DashSkeleton(width: 192, height: Space.xxl),
          SizedBox(height: Space.md),
          DashSkeleton(height: LinksPreviewMetrics.row, radius: Radii.card),
          DashSkeleton(height: LinksPreviewMetrics.row, radius: Radii.card),
          DashSkeleton(height: LinksPreviewMetrics.row, radius: Radii.card),
        ],
      ),
    ),
  );
}

class _PublicPage extends ConsumerWidget {
  const _PublicPage({required this.page});

  final PublicLinksPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final brand = page.brand;
    final bandBg = brand.backgroundColor.isEmpty
        ? linksMadarTeal
        : brand.backgroundColor;
    final bandFg = linksReadableOn(
      brand.foregroundColor.isEmpty ? '#FFFFFF' : brand.foregroundColor,
      bandBg,
    );
    final accent = hexColor(
      linksReadableOn(bandBg, dark ? linksGroundDark : linksGroundLight),
    );
    final cover = page.coverImageUrl;
    final open = ref.read(linkOpenerProvider);

    Widget column(Widget child) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: LinksPreviewMetrics.column),
        child: child,
      ),
    );

    final main = column(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Identity(
              name: brand.name,
              tagline: page.taglineEn,
              taglineAr: page.taglineAr,
              logoUrl: brand.logoUrl,
              plate: hexColor(bandBg),
              initialColor: hexColor(bandFg),
            ),
            const SizedBox(height: Space.xl + Space.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xl + Space.xs,
              children: [
                if (page.items.isNotEmpty)
                  Semantics(
                    container: true,
                    label: t('links.navLabel', args: {'name': brand.name}),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Space.md,
                      children: [
                        for (final item in page.items)
                          _LinkRow(
                            item: item,
                            accent: accent,
                            loyaltyMode: page.loyaltyMode,
                            onTap: () => open(Uri.parse(item.href)),
                          ),
                      ],
                    ),
                  ),
                if (page.socials.any((s) => _safe(s.url)))
                  _Socials(page: page, accent: accent),
                if (page.branches.isNotEmpty)
                  _VisitUs(branches: page.branches, accent: accent),
              ],
            ),
            const _Footer(),
          ],
        ),
      ),
    );

    return ColoredBox(
      color: c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cover != null)
            SizedBox(
              height: LinksPreviewMetrics.cover,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: c.surfaceAlt),
                  brandImage(cover),
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: LinksPreviewMetrics.scrim,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.fromRGBO(0, 0, 0, 0.35),
                            Color.fromRGBO(0, 0, 0, 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: column(
                      const Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(
                          Space.lg,
                          Space.md + DashMetrics.hair,
                          Space.lg,
                          0,
                        ),
                        child: _Controls(),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            column(
              const Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  Space.card,
                  Space.lg,
                  Space.card,
                  0,
                ),
                child: _Controls(),
              ),
            ),
          if (cover != null)
            // The mark rides half over the cover's edge (`-mt-12`).
            Transform.translate(
              offset: const Offset(0, -LinksPreviewMetrics.overlap),
              child: main,
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: main,
            ),
        ],
      ),
    );
  }
}

/// `isSafe`: the public row only links to `https://` addresses.
bool _safe(String url) => RegExp(r'^https://\S+$').hasMatch(url);

/// Share, theme and language: the page's header icons, drawn only.
class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget icon(String name) => Container(
      width: LinksPreviewMetrics.control,
      height: LinksPreviewMetrics.control,
      decoration: BoxDecoration(
        color: c.surface,
        shape: BoxShape.circle,
        border: Border.all(color: c.border),
      ),
      alignment: Alignment.center,
      child: DashIcon(name, size: IconSize.xs, color: c.textPrimary),
    );
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: Space.sm,
        children: [
          icon('share-2'),
          icon(dark ? 'sun' : 'moon'),
          icon('languages'),
        ],
      ),
    );
  }
}

/// The mark on its plate, then the name and the line under it.
class _Identity extends ConsumerWidget {
  const _Identity({
    required this.name,
    required this.tagline,
    required this.taglineAr,
    required this.logoUrl,
    required this.plate,
    required this.initialColor,
  });

  final String name;
  final String? tagline;
  final String? taglineAr;
  final String? logoUrl;
  final Color plate;
  final Color initialColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final ar = (t.isRtl ? taglineAr?.trim() : '') ?? '';
    final line = ar.isNotEmpty ? ar : (tagline?.trim() ?? '');
    final initial = name.trim().isEmpty
        ? ''
        : name.trim().characters.first.toUpperCase();
    final logo = logoUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.md + DashMetrics.hair,
      children: [
        Container(
          width: LinksPreviewMetrics.plate,
          height: LinksPreviewMetrics.plate,
          clipBehavior: Clip.antiAlias,
          padding: logo != null ? const EdgeInsets.all(Space.md) : null,
          decoration: BoxDecoration(
            // White plate, the card's rule: a logo on its own colour vanishes.
            color: logo != null ? Colors.white : plate,
            borderRadius: BorderRadius.circular(
              LinksPreviewMetrics.plateRadius,
            ),
            border: Border.all(color: c.bg, width: Space.xs),
            boxShadow: elevationShadows(context, MadarElevation.raised),
          ),
          alignment: Alignment.center,
          child: logo != null
              ? brandImage(logo, fit: BoxFit.contain)
              : Text(
                  initial,
                  style: MadarType.h1.copyWith(
                    fontSize: LinksPreviewMetrics.initial,
                    fontWeight: FontWeight.w600,
                    color: initialColor,
                  ),
                ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.xs + DashMetrics.hair,
          children: [
            Text(
              name,
              style: MadarType.h1.copyWith(
                fontSize: LinksPreviewMetrics.name,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            if (line.isNotEmpty)
              Text(
                line,
                style: MadarType.body.copyWith(
                  fontWeight: FontWeight.w400,
                  height: 1.6,
                  color: c.textSecondary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A button: a row (the narrow layout).
class _LinkRow extends ConsumerWidget {
  const _LinkRow({
    required this.item,
    required this.accent,
    required this.loyaltyMode,
    required this.onTap,
  });

  final PublicLinksItem item;
  final Color accent;
  final String? loyaltyMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final custom = item.kind == LinksItemKind.custom;
    final text = linksItemText(item, loyaltyMode, t, arabic: t.isRtl);
    return DashPressable(
      onTap: onTap,
      semanticLabel: '${text.title}, ${text.hint}',
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(minHeight: LinksPreviewMetrics.row),
        padding: const EdgeInsets.all(Space.md + DashMetrics.hair),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: s.highlighted ? c.textMuted : c.border),
          boxShadow: elevationShadows(context, MadarElevation.card),
        ),
        child: Row(
          spacing: Space.md + DashMetrics.hair,
          children: [
            Container(
              width: LinksPreviewMetrics.tile,
              height: LinksPreviewMetrics.tile,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: custom ? null : accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: DashIcon(
                _glyph[item.kind.value] ?? 'link-2',
                size: IconSize.lg,
                color: custom ? c.textMuted : accent,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MadarClippedText(
                    text.title,
                    style: MadarType.title.copyWith(color: c.textPrimary),
                    maxLines: 1,
                  ),
                  if (text.hint.isNotEmpty)
                    MadarClippedText(
                      text.hint,
                      style: MadarType.bodySm.copyWith(
                        fontWeight: FontWeight.w400,
                        color: c.textSecondary,
                      ),
                      maxLines: 2,
                    ),
                ],
              ),
            ),
            DashIcon(
              custom ? 'external-link' : DashIcon.forward(context),
              size: IconSize.lg,
              color: c.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Find us": the socials as pills (`SocialLinks`).
class _Socials extends ConsumerWidget {
  const _Socials({required this.page, required this.accent});

  final PublicLinksPage page;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final open = ref.read(linkOpenerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.md,
      children: [
        Text(
          t('loyalty.findUs'),
          style: MadarType.title.copyWith(color: c.textPrimary),
        ),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final l in page.socials.where((s) => _safe(s.url)))
              Builder(
                builder: (context) {
                  final label = t.exists('loyalty.social.${l.key}')
                      ? t('loyalty.social.${l.key}')
                      : l.label;
                  final glyph = socialPlatforms
                      .where((p) => p.key == l.key)
                      .map((p) => p.icon)
                      .firstOrNull;
                  return DashPressable(
                    onTap: () => open(Uri.parse(l.url)),
                    semanticLabel: label,
                    excludeChildSemantics: true,
                    pressScale: false,
                    builder: (context, s) => Container(
                      height: DashMetrics.target,
                      padding: const EdgeInsetsDirectional.only(
                        start: Space.md,
                        end: Space.lg,
                      ),
                      decoration: BoxDecoration(
                        color: s.highlighted ? c.surfaceAlt : c.surface,
                        borderRadius: BorderRadius.circular(Radii.pill),
                        border: Border.all(color: c.border),
                        boxShadow: elevationShadows(
                          context,
                          MadarElevation.card,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: Space.sm,
                        children: [
                          DashIcon(
                            glyph ?? 'globe',
                            size: IconSize.md,
                            color: accent,
                          ),
                          Text(
                            label,
                            style: DashType.bodyMedium.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// "Visit us": one card, one block per branch.
class _VisitUs extends ConsumerWidget {
  const _VisitUs({required this.branches, required this.accent});

  final List<PublicLinksBranch> branches;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final open = ref.read(linkOpenerProvider);

    Widget action(String icon, String label, Uri uri) => Expanded(
      child: DashPressable(
        onTap: () => open(uri),
        semanticLabel: label,
        excludeChildSemantics: true,
        pressScale: false,
        builder: (context, s) => Container(
          height: DashMetrics.target,
          decoration: BoxDecoration(
            color: s.highlighted ? c.border : c.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: Space.sm,
            children: [
              DashIcon(icon, size: IconSize.md, color: c.textPrimary),
              Flexible(
                child: MadarClippedText(
                  label,
                  style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.sheet),
        border: Border.all(color: c.border),
        boxShadow: elevationShadows(context, MadarElevation.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.card,
              Space.lg,
              Space.card,
              Space.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              spacing: Space.md,
              children: [
                Expanded(
                  child: Text(
                    t('links.visit.title'),
                    style: MadarType.title.copyWith(color: c.textPrimary),
                  ),
                ),
                if (branches.length > 1)
                  Text(
                    t('links.visit.count', count: branches.length),
                    style: MadarType.bodySm.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
          ),
          for (final (i, b) in branches.indexed)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.card,
                vertical: Space.lg,
              ),
              decoration: i > 0
                  ? BoxDecoration(
                      border: Border(top: BorderSide(color: c.border)),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.md,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.md,
                    children: [
                      DashIcon('map-pin', size: IconSize.lg, color: accent),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: Space.xs / 2,
                          children: [
                            Text(
                              b.name,
                              style: MadarType.body.copyWith(
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary,
                              ),
                            ),
                            if (b.address case final a? when a.isNotEmpty)
                              Text(
                                a,
                                style: MadarType.bodySm.copyWith(
                                  fontWeight: FontWeight.w400,
                                  color: c.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (b.directionsUrl != null || b.phone != null)
                    Row(
                      spacing: Space.sm,
                      children: [
                        if (b.directionsUrl case final d?)
                          action(
                            'navigation',
                            t('links.visit.directions'),
                            Uri.parse(d),
                          ),
                        if (b.phone case final p?)
                          action(
                            'phone',
                            t('links.visit.call'),
                            Uri.parse(
                              'tel:${p.replaceAll(RegExp(r'[^\d+]'), '')}',
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Madar's footer: the store badge, the copyright and the legal links.
class _Footer extends ConsumerWidget {
  const _Footer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? c.chromeRaised : c.chrome;
    final uri = madarSiteHref(
      ref.watch(localeProvider),
      'dashboard',
      'shop_page',
    );
    return Padding(
      padding: const EdgeInsets.only(
        top: Space.xxl * 1.5,
        bottom: Space.xxl + Space.sm,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: Space.xxl),
          child: Column(
            spacing: Space.card,
            children: [
              DashPressable(
                onTap: () => ref.read(linkOpenerProvider)(uri),
                semanticLabel:
                    '${t('publicShell.signature.by.generic')} ${t('publicShell.signature.name')} ${t('common.opensInNewTab')}',
                excludeChildSemantics: true,
                pressScale: false,
                builder: (context, s) => Container(
                  height: Space.xxl + Space.lg,
                  padding: const EdgeInsetsDirectional.only(
                    start: Space.md + DashMetrics.hair,
                    end: Space.lg,
                  ),
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(Radii.sm + 1),
                    boxShadow: dark
                        ? null
                        : elevationShadows(context, MadarElevation.raised),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.sm + DashMetrics.hair,
                    children: [
                      const MadarSymbol(
                        size: LinksPreviewMetrics.symbol,
                        reversed: true,
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.xs,
                        children: [
                          Text(
                            t('publicShell.signature.by.generic'),
                            style: MadarType.labelSm.copyWith(
                              fontWeight: FontWeight.w500,
                              color: c.onChromeMuted,
                            ),
                          ),
                          const ShellWordmark(
                            height: LinksPreviewMetrics.wordmark,
                            reversed: true,
                          ),
                        ],
                      ),
                      Transform.flip(
                        flipX: Directionality.of(context) == TextDirection.rtl,
                        child: DashIcon(
                          'arrow-up-right',
                          size: IconSize.sm,
                          color: c.onChromeMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                spacing: Space.xs + DashMetrics.hair,
                children: [
                  Text(
                    copyrightLine(ref),
                    textAlign: TextAlign.center,
                    style: MadarType.labelSm.copyWith(
                      fontWeight: FontWeight.w400,
                      color: c.textMuted,
                    ),
                  ),
                  const DashLegalLinks(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
