/// Settings › Links & QR codes (`features/links-qr/links-qr-page.tsx`): the
/// shop's addresses and every code that opens them, on one page. It replaced
/// two (2026-11-06): Settings › Links page and Settings › QR codes. Their old
/// addresses redirect here (`/settings/links`, `/settings/qr` and the older
/// `/qr`, the generated legacy redirects), the QR ones straight to the codes
/// (`?section=codes`).
///
/// Three sections, in the order a shop sets them up:
///  1. **Links page**: the page the shop's own address opens on, and its
///     editor (paid; shown locked on Free).
///  2. **Menu (no prices)**: every plan.
///  3. **QR codes**: every code, under one set of output switches
///     (Unbranded, and under it the logo in the middle), with a live sample.
///     The same switches sit inside every code's preview, and the "QR code"
///     buttons in sections 1 and 2 open those same live codes.
///
/// Every plan opens the page; each section locks what its plan lacks.
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../links/links_page.dart';
import '../links/menu_display_section.dart';
import '../qr/codes_section.dart';

/// The page's sections, in order (`LINKS_QR_SECTIONS`).
enum LinksQrSection {
  links,
  menu,
  codes;

  /// `?section=` as the route reads it; anything else is no section.
  static LinksQrSection? parse(String? value) =>
      values.where((s) => s.name == value).firstOrNull;
}

class LinksQrPage extends ConsumerStatefulWidget {
  const LinksQrPage({this.section, super.key});

  /// The section a link asked for (`?section=menu|codes`).
  final LinksQrSection? section;

  @override
  ConsumerState<LinksQrPage> createState() => _LinksQrPageState();
}

class _LinksQrPageState extends ConsumerState<LinksQrPage> {
  final _keys = {for (final s in LinksQrSection.values) s: GlobalKey()};

  /// The section asked for has been scrolled to (once per visit).
  bool _landed = false;

  void _jump(LinksQrSection s, {bool animate = true}) {
    final target = _keys[s]!.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: animate
          ? DashMotion.of(context, DashMotion.slow)
          : Duration.zero,
      curve: DashMotion.ease,
    );
  }

  /// Land on the section a link asked for. The links editor above it
  /// arrives after its read, which pushes everything under it down, so the
  /// scroll waits until the links section reports its height.
  void _linksReady() {
    final s = widget.section;
    if (_landed || s == null || s == LinksQrSection.links || !mounted) return;
    _landed = true;
    _jump(s, animate: false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final orgId = ref.watch(orgIdProvider);
    if (orgId == null) {
      return DashPageScaffold(
        title: t('linksQr.title'),
        width: DashPageWidth.reading,
        body: DashEmptyState(icon: 'qr-code', title: t('branches.pickOrg')),
      );
    }

    final jumps = [
      (LinksQrSection.links, t('linksQr.jump.links'), 'link-2'),
      (LinksQrSection.menu, t('linksQr.jump.menu'), 'book-open'),
      (LinksQrSection.codes, t('linksQr.jump.codes'), 'qr-code'),
    ];
    final chips = Semantics(
      container: true,
      label: t('linksQr.jump.label'),
      child: Wrap(
        key: const ValueKey('links-qr-jumps'),
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final (s, label, icon) in jumps)
            DashPressable(
              key: ValueKey('links-qr-jump-${s.name}'),
              semanticLabel: label,
              excludeChildSemantics: true,
              pressScale: false,
              onTap: () => _jump(s),
              builder: (context, st) {
                final radius = BorderRadius.circular(Radii.pill);
                return Container(
                  height: DashMetrics.control,
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  foregroundDecoration: dashFocusRing(context, st, radius),
                  decoration: BoxDecoration(
                    color: st.highlighted ? c.hover : c.card,
                    borderRadius: radius,
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs + DashMetrics.hair,
                    children: [
                      DashIcon(
                        icon,
                        size: IconSize.xs - 2,
                        color: st.highlighted ? c.textPrimary : c.textSecondary,
                      ),
                      Text(
                        label,
                        style: DashType.smallMedium.copyWith(
                          color: st.highlighted
                              ? c.textPrimary
                              : c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );

    return DashPageScaffold(
      key: const ValueKey('links-qr-page'),
      title: t('linksQr.title'),
      subtitle: t('linksQr.desc'),
      width: DashPageWidth.reading,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xxl,
        children: [
          chips,
          KeyedSubtree(
            key: _keys[LinksQrSection.links],
            child: LinksPageSection(
              key: const ValueKey('links-qr-links'),
              onReady: _linksReady,
            ),
          ),
          KeyedSubtree(
            key: _keys[LinksQrSection.menu],
            child: MenuDisplaySection(
              key: const ValueKey('links-qr-menu'),
              orgId: orgId,
            ),
          ),
          KeyedSubtree(
            key: _keys[LinksQrSection.codes],
            child: Column(
              key: const ValueKey('links-qr-codes'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.lg,
              children: [
                DashSectionHeader(
                  title: t('linksQr.codes.title'),
                  description: t('linksQr.codes.desc'),
                ),
                QrCodesSection(orgId: orgId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
