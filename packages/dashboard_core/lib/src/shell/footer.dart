/// The frame's foot (`app-footer.tsx`), the legal links (`legal-links.tsx`)
/// and the shop's public brand the sidebar and the foot read
/// (`usePublicBrand`).
library;

import 'package:dashboard_api/dashboard_api.dart' show PublicBrand;
import 'package:dashboard_core/src/api_provider.dart';
import 'package:dashboard_core/src/format/tz.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/session/session.dart';
import 'package:dashboard_core/src/shell/shell_prefs.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shop's public brand (`GET /public/orgs/brand?org_id=`): its own logo
/// on the branding tier. A miss is Madar's chrome, never an error state.
final publicBrandProvider = FutureProvider<PublicBrand?>((ref) async {
  final orgId = ref.watch(orgIdProvider);
  if (orgId == null) return null;
  try {
    return await ref.watch(apiProvider).orgs.publicOrgBrand(orgId: orgId);
  } on Object {
    return null;
  }
}, retry: (_, _) => null);

/// The year the copyright line names: Cairo's, in the page's numerals
/// ("2026" or "٢٠٢٦", the web's `currentYear`).
final copyrightYearProvider = Provider<String>((ref) {
  final year = '${inZone(ref.watch(clockProvider)(), appTimezone).year}';
  if (!ref.watch(localeProvider).startsWith('ar')) return year;
  return String.fromCharCodes(year.codeUnits.map((u) => u - 0x30 + 0x0660));
});

/// `© {{year}} Madar. All rights reserved.`
String copyrightLine(WidgetRef ref) => ref.watch(tProvider)(
  'common.copyright',
  args: {'year': ref.watch(copyrightYearProvider)},
  defaultValue: '© {{year}} Madar',
);

/// Privacy · Terms, opening the public legal site outside the app.
class DashLegalLinks extends ConsumerWidget {
  const DashLegalLinks({this.color, this.center = true, super.key});

  /// The links' colour (muted text by default; the chrome's muted on ink).
  final Color? color;
  final bool center;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final open = ref.watch(linkOpenerProvider);
    final c = context.madarColors;
    final tint = color ?? c.textMuted;
    final style = DashType.small.copyWith(color: tint);
    Widget link(String label, Uri uri) => DashPressable(
      semanticLabel: label,
      isButton: false,
      pressScale: false,
      excludeChildSemantics: true,
      onTap: () => open(uri),
      builder: (context, s) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: style.copyWith(
              decoration: s.highlighted ? TextDecoration.underline : null,
              decorationColor: tint,
            ),
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      label: t('legal.label', defaultValue: 'Legal'),
      child: Wrap(
        alignment: center ? WrapAlignment.center : WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.sm,
        children: [
          link(t('legal.privacy'), LegalUrls.privacy),
          ExcludeSemantics(child: Text('·', style: style)),
          link(t('legal.terms'), LegalUrls.terms),
        ],
      ),
    );
  }
}

/// The frame's foot: the copyright, "Powered by Madar" for a shop on its own
/// branding, and the legal links.
class DashFooter extends ConsumerWidget {
  const DashFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    final brand = ref.watch(publicBrandProvider).value;
    final style = DashType.small.copyWith(color: c.textMuted);
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
      child: Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: Text(
              copyrightLine(ref),
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (brand?.customBranding ?? false)
            Flexible(child: _PoweredByMadar(style: style)),
          const DashLegalLinks(center: false),
        ],
      ),
    );
  }
}

/// "Powered by Madar" on a shop's own branding: a link to Madar POS's site,
/// opened outside the app (`app-footer.tsx`).
class _PoweredByMadar extends ConsumerWidget {
  const _PoweredByMadar({required this.style});

  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final label = t(
      'publicShell.poweredBy.generic',
      defaultValue: 'Powered by Madar',
    );
    final uri = madarSiteHref(
      ref.watch(localeProvider),
      'dashboard',
      'dashboard',
    );
    return DashPressable(
      semanticLabel: '$label ${t('common.opensInNewTab')}',
      isButton: false,
      pressScale: false,
      excludeChildSemantics: true,
      onTap: () => ref.read(linkOpenerProvider)(uri),
      builder: (context, s) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            Flexible(
              child: Text(
                label,
                style: style.copyWith(
                  color: s.highlighted ? context.madarColors.textPrimary : null,
                  decoration: TextDecoration.underline,
                  decorationColor: style.color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Up and out: up-left in Arabic.
            Transform.flip(
              flipX: Directionality.of(context) == TextDirection.rtl,
              child: DashIcon(
                'arrow-up-right',
                size: IconSize.xs,
                color: style.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
