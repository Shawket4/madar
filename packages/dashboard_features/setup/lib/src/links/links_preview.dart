/// The editor's preview (SET-LNK-023): the shop's public links page
/// (`features/links/public/links-page.tsx`) as a customer gets it, reading
/// what is SAVED (`GET /public/orgs/links?org_id=`). Its narrow layout, or
/// its wide one once the frame is 768 px across (the page's `@3xl`
/// container query: the preview stacked under a wide form). Buttons, socials, directions and calls open outside the app as
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

  /// `@3xl`: the wide layout from a 768 px container.
  static const double wideFrom = 768;

  /// The wide layout's sizes: `max-w-[1040px]`, the cover's `h-60`, the
  /// plate's `size-32` and `rounded-[34px]`, the `-mt-16` overlap, the name's
  /// `pt-[76px]` (it starts below the cover) and `text-[40px]`.
  static const double wideColumn = 1040;
  static const double wideCover = 240;
  static const double widePlate = 128;
  static const double widePlateRadius = 34;
  static const double wideOverlap = 64;
  static const double wideNameDrop = 76;
  static const double wideName = 40;

  /// `360px`: Visit us, beside the buttons.
  static const double wideSide = 360;

  /// `min-h-[132px]`: a card; `min-h-[80px]`: a lone last button's row.
  static const double card = 132;
  static const double wideRow = 80;

  /// The wide layout's text: the tagline (`text-base`), a button's title
  /// (`text-[17px]`) and its hint (`text-sm`).
  static const double wideTagline = 16;
  static const double wideTitle = 17;
  static const double wideHint = 14;
}

/// How a button is drawn: a row on a phone; on a desktop a card, or a row
/// across the grid for a last button with no partner.
enum _Shape { row, wideRow, card }

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
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, box) =>
        _page(context, ref, wide: box.maxWidth >= LinksPreviewMetrics.wideFrom),
  );

  Widget _page(BuildContext context, WidgetRef ref, {required bool wide}) {
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
    final gutter = wide ? Space.xxl : Space.card;

    Widget column(Widget child) => Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide
              ? LinksPreviewMetrics.wideColumn
              : LinksPreviewMetrics.column,
        ),
        child: child,
      ),
    );

    Widget button(PublicLinksItem item, _Shape shape) => _LinkRow(
      item: item,
      accent: accent,
      loyaltyMode: page.loyaltyMode,
      shape: shape,
      onTap: () => open(Uri.parse(item.href)),
    );

    final items = page.items;
    final buttons = Semantics(
      container: true,
      label: t('links.navLabel', args: {'name': brand.name}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          if (!wide)
            for (final item in items) button(item, _Shape.row)
          else
            // Two cards a line, as tall as each other; a last card with no
            // partner spans the line as a row.
            for (var i = 0; i < items.length; i += 2)
              if (i + 1 < items.length)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Space.md,
                    children: [
                      Expanded(child: button(items[i], _Shape.card)),
                      Expanded(child: button(items[i + 1], _Shape.card)),
                    ],
                  ),
                )
              else
                button(items[i], _Shape.wideRow),
        ],
      ),
    );
    final socials = page.socials.any((s) => _safe(s.url))
        ? _Socials(page: page, accent: accent)
        : null;
    final visit = page.branches.isEmpty
        ? null
        : _VisitUs(branches: page.branches, accent: accent);
    final lead = [if (items.isNotEmpty) buttons, ?socials];

    final main = column(
      Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
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
              wide: wide,
              overlap: cover != null,
            ),
            SizedBox(height: wide ? Space.xxl + Space.sm : Space.xl + Space.xs),
            if (wide)
              // The buttons and the socials, with Visit us beside them in
              // its own 360 px column (kept even when there is no branch).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.xxl,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Space.xl + Space.xs,
                      children: lead,
                    ),
                  ),
                  SizedBox(width: LinksPreviewMetrics.wideSide, child: visit),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.xl + Space.xs,
                children: [...lead, ?visit],
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
              height: wide
                  ? LinksPreviewMetrics.wideCover
                  : LinksPreviewMetrics.cover,
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
                      Padding(
                        padding: wide
                            ? const EdgeInsetsDirectional.fromSTEB(
                                Space.xxl,
                                Space.card,
                                Space.xxl,
                                0,
                              )
                            : const EdgeInsetsDirectional.fromSTEB(
                                Space.lg,
                                Space.md + DashMetrics.hair,
                                Space.lg,
                                0,
                              ),
                        child: const _Controls(),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            column(
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  gutter,
                  wide ? Space.xl : Space.lg,
                  gutter,
                  0,
                ),
                child: const _Controls(),
              ),
            ),
          if (cover != null)
            // The mark rides half over the cover's edge (`-mt-12`, `-mt-16`).
            Transform.translate(
              offset: Offset(
                0,
                -(wide
                    ? LinksPreviewMetrics.wideOverlap
                    : LinksPreviewMetrics.overlap),
              ),
              child: main,
            )
          else
            Padding(
              padding: EdgeInsets.only(top: wide ? Space.lg : Space.sm),
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
    required this.wide,
    required this.overlap,
  });

  final String name;
  final String? tagline;
  final String? taglineAr;
  final String? logoUrl;
  final Color plate;
  final Color initialColor;

  /// The wide layout: the mark beside the name.
  final bool wide;

  /// Under a cover (the mark rides over its edge).
  final bool overlap;

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
    final side = wide
        ? LinksPreviewMetrics.widePlate
        : LinksPreviewMetrics.plate;
    final mark = Container(
      width: side,
      height: side,
      clipBehavior: Clip.antiAlias,
      padding: logo != null ? EdgeInsets.all(wide ? Space.lg : Space.md) : null,
      decoration: BoxDecoration(
        // White plate, the card's rule: a logo on its own colour vanishes.
        color: logo != null ? Colors.white : plate,
        borderRadius: BorderRadius.circular(
          wide
              ? LinksPreviewMetrics.widePlateRadius
              : LinksPreviewMetrics.plateRadius,
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
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        Text(
          name,
          style: MadarType.h1.copyWith(
            fontSize: wide
                ? LinksPreviewMetrics.wideName
                : LinksPreviewMetrics.name,
            height: 1.1,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        if (line.isNotEmpty)
          Text(
            line,
            style: MadarType.body.copyWith(
              fontSize: wide ? LinksPreviewMetrics.wideTagline : null,
              fontWeight: FontWeight.w400,
              height: 1.6,
              color: c.textSecondary,
            ),
          ),
      ],
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md + DashMetrics.hair,
        children: [mark, words],
      );
    }
    // Beside the mark; under a cover the name starts below its edge, so only
    // the mark crosses it.
    return Row(
      crossAxisAlignment: overlap
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      spacing: Space.xl,
      children: [
        mark,
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top: overlap ? LinksPreviewMetrics.wideNameDrop : 0,
            ),
            child: words,
          ),
        ),
      ],
    );
  }
}

/// A button: a row on a phone, a card in a two-column grid on a desktop.
class _LinkRow extends ConsumerWidget {
  const _LinkRow({
    required this.item,
    required this.accent,
    required this.loyaltyMode,
    required this.shape,
    required this.onTap,
  });

  final PublicLinksItem item;
  final Color accent;
  final String? loyaltyMode;
  final _Shape shape;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final custom = item.kind == LinksItemKind.custom;
    final text = linksItemText(item, loyaltyMode, t, arabic: t.isRtl);
    final wide = shape != _Shape.row;
    final card = shape == _Shape.card;
    final tile = Container(
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
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MadarClippedText(
          text.title,
          style: MadarType.title.copyWith(
            fontSize: wide ? LinksPreviewMetrics.wideTitle : null,
            color: c.textPrimary,
          ),
          maxLines: 1,
          // `truncate`, `line-clamp-2`.
          overflow: TextOverflow.ellipsis,
        ),
        if (text.hint.isNotEmpty)
          MadarClippedText(
            text.hint,
            style: MadarType.bodySm.copyWith(
              fontSize: wide ? LinksPreviewMetrics.wideHint : null,
              fontWeight: FontWeight.w400,
              color: c.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
    return DashPressable(
      onTap: onTap,
      semanticLabel: '${text.title}, ${text.hint}',
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        constraints: BoxConstraints(
          minHeight: switch (shape) {
            _Shape.row => LinksPreviewMetrics.row,
            _Shape.wideRow => LinksPreviewMetrics.wideRow,
            _Shape.card => LinksPreviewMetrics.card,
          },
        ),
        padding: switch (shape) {
          _Shape.row => const EdgeInsets.all(Space.md + DashMetrics.hair),
          _Shape.wideRow => const EdgeInsets.symmetric(
            horizontal: Space.card,
            vertical: Space.md + DashMetrics.hair,
          ),
          _Shape.card => const EdgeInsets.all(Space.card),
        },
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: s.highlighted ? c.textMuted : c.border),
          boxShadow: elevationShadows(context, MadarElevation.card),
        ),
        // A card: the glyph on top, the words at the foot, no arrow.
        child: card
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                spacing: Space.md + DashMetrics.hair,
                children: [tile, words],
              )
            : Row(
                spacing: Space.md + DashMetrics.hair,
                children: [
                  tile,
                  Expanded(child: words),
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
