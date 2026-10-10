/// Where else to find the shop (`features/orgs/social-links.tsx`): one
/// closed list of eight platforms, the https-only rule, the patch that is
/// sent, and the eight fields. Brand (SET-BRD-015..017) and the Links page
/// (SET-LNK-018) edit the same `organizations.social_links` map.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One platform: its key in `social_links`, its glyph (tellable apart, not a
/// logo), the web's English label default and the sample address.
class SocialPlatform {
  const SocialPlatform(this.key, this.icon, this.label, this.sample);

  final String key;
  final String icon;
  final String label;
  final String sample;
}

/// The platforms, in the order a card prints them.
const List<SocialPlatform> socialPlatforms = [
  SocialPlatform(
    'instagram',
    'camera',
    'Instagram',
    'https://instagram.com/yourshop',
  ),
  SocialPlatform(
    'facebook',
    'thumbs-up',
    'Facebook',
    'https://facebook.com/yourshop',
  ),
  SocialPlatform('tiktok', 'music', 'TikTok', 'https://tiktok.com/@yourshop'),
  SocialPlatform('x', 'x', 'X', 'https://x.com/yourshop'),
  SocialPlatform('youtube', 'play', 'YouTube', 'https://youtube.com/@yourshop'),
  SocialPlatform(
    'whatsapp',
    'message-circle',
    'WhatsApp',
    'https://wa.me/201234567890',
  ),
  SocialPlatform(
    'talabat',
    'shopping-bag',
    'Talabat',
    'https://www.talabat.com/egypt/yourshop',
  ),
  SocialPlatform('website', 'globe', 'Website', 'https://yourshop.com'),
];

/// `https` with a host, and nothing else — the server's rule. `http` is
/// refused, never upgraded.
bool isHttpsUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      !value.contains(' ');
}

/// Whether one link field is acceptable: empty (removes it) or https.
bool socialLinkValid(String value) {
  final v = value.trim();
  return v.isEmpty || isHttpsUrl(v);
}

/// What the server holds, as the form's values (unknown keys dropped).
Map<String, String> socialLinksToForm(Map<String, Object?>? saved) => {
  for (final p in socialPlatforms)
    p.key: switch (saved?[p.key]) {
      final String v => v,
      _ => '',
    },
};

/// What to send: a platform with a value, plus `""` for one that HAD a value
/// and was emptied; never-set platforms stay out.
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

/// The heading and the eight fields (two columns from 640). Each field
/// validates inside a surrounding [Form]: "Use the full address, starting
/// with https://".
class SocialLinksFields extends ConsumerWidget {
  const SocialLinksFields({
    required this.values,
    required this.onChanged,
    this.enabled = true,
    this.onSubmitted,
    super.key,
  });

  final Map<String, String> values;
  final void Function(String platform, String value) onChanged;
  final bool enabled;

  /// Enter in a field (submits the host form).
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final twoColumns = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;

    Widget field(SocialPlatform p) {
      final label = t('orgs.social.${p.key}', defaultValue: p.label);
      final value = values[p.key] ?? '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          Row(
            spacing: Space.xs + DashMetrics.hair,
            children: [
              DashIcon(p.icon, size: IconSize.xs, color: c.textSecondary),
              Flexible(
                child: Text(
                  label,
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
          DashFormField<String>(
            value: value,
            validator: (v) =>
                socialLinkValid(v) ? null : t('orgs.socialInvalid'),
            builder: (context, invalid) => DashTextInput(
              value: value,
              onChanged: (v) => onChanged(p.key, v),
              placeholder: p.sample,
              semanticLabel: label,
              invalid: invalid,
              enabled: enabled,
              keyboardType: TextInputType.url,
              // A URL reads left to right in every language.
              textDirection: TextDirection.ltr,
              onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
            ),
          ),
        ],
      );
    }

    final rows = <Widget>[];
    if (twoColumns) {
      for (var i = 0; i < socialPlatforms.length; i += 2) {
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(child: field(socialPlatforms[i])),
              Expanded(child: field(socialPlatforms[i + 1])),
            ],
          ),
        );
      }
    } else {
      rows.addAll(socialPlatforms.map(field));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
        ...rows,
      ],
    );
  }
}
