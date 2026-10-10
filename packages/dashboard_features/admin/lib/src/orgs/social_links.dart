/// Where else to find the shop (the web's `features/orgs/social-links.tsx`,
/// ADM-ORG-054): the closed list of platforms in the order a loyalty card
/// prints them, the https-only rule the server holds to, what a save sends,
/// and the eight fields.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// One platform: its key, a glyph that tells the rows apart (lucide has no
/// brand marks; the row's name identifies it), and a sample address.
class SocialPlatform {
  const SocialPlatform(this.key, this.icon, this.sample);

  final String key;
  final String icon;
  final String sample;
}

/// The platforms, in card-print order.
const List<SocialPlatform> socialPlatforms = [
  SocialPlatform('instagram', 'camera', 'https://instagram.com/yourshop'),
  SocialPlatform('facebook', 'thumbs-up', 'https://facebook.com/yourshop'),
  SocialPlatform('tiktok', 'music', 'https://tiktok.com/@yourshop'),
  SocialPlatform('x', 'x', 'https://x.com/yourshop'),
  SocialPlatform('youtube', 'play', 'https://youtube.com/@yourshop'),
  SocialPlatform('whatsapp', 'message-circle', 'https://wa.me/201234567890'),
  SocialPlatform(
    'talabat',
    'shopping-bag',
    'https://www.talabat.com/egypt/yourshop',
  ),
  SocialPlatform('website', 'globe', 'https://yourshop.com'),
];

/// `https` with a host, nothing else (http is refused, never upgraded).
bool isHttpsUrl(String value) {
  if (value.contains(RegExp(r'\s'))) return false;
  final uri = Uri.tryParse(value);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

/// A link field's error: empty (removes the link) or a full https address.
String? socialLinkError(String value, Translator t) {
  final v = value.trim();
  return v.isEmpty || isHttpsUrl(v) ? null : t('orgs.socialInvalid');
}

/// What the server holds, as the eight fields (non-strings dropped).
Map<String, String> socialLinksToForm(Map<String, Object?>? saved) => {
  for (final p in socialPlatforms)
    p.key: switch (saved?[p.key]) {
      final String s => s,
      _ => '',
    },
};

/// What a save sends: every typed value (trimmed), plus `""` for a link
/// that existed and was cleared; platforms never set stay out.
Map<String, String> socialLinksPatch(
  Map<String, String> values,
  Map<String, Object?>? saved,
) {
  final patch = <String, String>{};
  for (final p in socialPlatforms) {
    final next = (values[p.key] ?? '').trim();
    final previous = saved?[p.key];
    final had = previous is String && previous.trim().isNotEmpty;
    if (next.isNotEmpty) {
      patch[p.key] = next;
    } else if (had) {
      patch[p.key] = '';
    }
  }
  return patch;
}

/// The heading, its hint and the eight LTR address fields (two columns from
/// 640 wide).
class OrgSocialLinksFields extends StatelessWidget {
  const OrgSocialLinksFields({
    required this.values,
    required this.errors,
    required this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    super.key,
  });

  final Map<String, String> values;

  /// Per platform key; shown under its field.
  final Map<String, String?> errors;
  final void Function(String key, String value) onChanged;
  final VoidCallback? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.translator;
    final twoUp = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    Widget field(SocialPlatform p) => DashFormField<String>(
      errorText: errors[p.key],
      label: null,
      builder: (context, invalid) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs + DashMetrics.hair,
        children: [
          Row(
            spacing: Space.xs + DashMetrics.hair,
            children: [
              DashIcon(p.icon, size: IconSize.xs, color: c.textSecondary),
              Flexible(
                child: Text(
                  t('orgs.social.${p.key}'),
                  style: DashType.small.copyWith(
                    color: invalid ? c.errorText : c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          DashTextInput(
            key: ValueKey('org-social-${p.key}'),
            value: values[p.key] ?? '',
            onChanged: (v) => onChanged(p.key, v),
            placeholder: p.sample,
            semanticLabel: t('orgs.social.${p.key}'),
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            invalid: invalid,
            enabled: enabled,
            onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
          ),
        ],
      ),
    );
    final fields = [for (final p in socialPlatforms) field(p)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: DashMetrics.hair,
          children: [
            Text(
              t('orgs.socialLinks'),
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            Text(
              t('orgs.socialLinksHint'),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ],
        ),
        if (twoUp)
          for (var i = 0; i < fields.length; i += 2)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(child: fields[i]),
                Expanded(child: fields[i + 1]),
              ],
            )
        else
          ...fields,
      ],
    );
  }
}
