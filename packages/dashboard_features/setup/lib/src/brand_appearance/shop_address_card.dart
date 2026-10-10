/// "Your web address" (`features/settings/shop-address-card.tsx`,
/// SET-BRD-011..014): the shop's own customer addresses, on the branding
/// tier only, each with Copy (a check for two seconds) and Open.
library;

import 'dart:async';

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'brand_data.dart';

class ShopAddressCard extends ConsumerStatefulWidget {
  const ShopAddressCard({
    required this.slug,
    required this.customBranding,
    this.root,
    super.key,
  });

  final String? slug;
  final bool customBranding;

  /// The public root domain; default: derived from the app's API address.
  final String? root;

  /// How long a copied address shows its check.
  static const Duration copiedFor = Duration(seconds: 2);

  /// Whether the card shows at all.
  static bool shows(String? slug, bool customBranding, String? root) =>
      customBranding && shopAddresses(slug, root).isNotEmpty;

  @override
  ConsumerState<ShopAddressCard> createState() => _ShopAddressCardState();
}

class _ShopAddressCardState extends ConsumerState<ShopAddressCard> {
  String? _copied;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy(String url) async {
    final t = ref.read(tProvider);
    try {
      await Clipboard.setData(ClipboardData(text: url));
    } on Object {
      if (mounted) DashToast.error(context, t('common.copyFailed'));
      return;
    }
    if (!mounted) return;
    setState(() => _copied = url);
    _reset?.cancel();
    _reset = Timer(ShopAddressCard.copiedFor, () {
      if (mounted) setState(() => _copied = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final root = widget.root ?? publicRootDomain(brandApiBase);
    final addresses = shopAddresses(widget.slug, root);
    if (!widget.customBranding || addresses.isEmpty) {
      return const SizedBox.shrink();
    }
    return DashCard(
      key: const ValueKey('brand-address'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.sm + DashMetrics.hair,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: DashMetrics.hair),
                child: DashIcon('globe', size: IconSize.sm, color: c.textMuted),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.xs,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        t('settings.address.title'),
                        style: DashType.sectionTitle.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      t('settings.address.hint'),
                      style: DashType.body.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [for (final a in addresses) _row(t, c, a)],
          ),
        ],
      ),
    );
  }

  Widget _row(Translator t, MadarColors c, ShopAddress a) {
    final copied = _copied == a.url;
    return Container(
      key: ValueKey('brand-address-${a.key}'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('settings.address.${a.key}'),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
                Tooltip(
                  message: a.url,
                  // A URL is not prose: it reads left to right in Arabic too.
                  child: MadarClippedText(
                    a.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: DashType.mono.copyWith(color: c.textPrimary),
                  ),
                ),
                const SizedBox(height: DashMetrics.hair),
                Text(
                  t('settings.address.${a.key}Hint'),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          DashIconButton(
            key: ValueKey('brand-copy-${a.key}'),
            icon: copied ? 'check' : 'copy',
            semanticLabel: t('common.copy'),
            color: copied ? DashTone.success.foreground(c) : null,
            onPressed: () => _copy(a.url),
          ),
          DashIconButton(
            key: ValueKey('brand-open-${a.key}'),
            icon: 'external-link',
            semanticLabel: t('common.open'),
            onPressed: () => ref.read(linkOpenerProvider)(Uri.parse(a.url)),
          ),
        ],
      ),
    );
  }
}
