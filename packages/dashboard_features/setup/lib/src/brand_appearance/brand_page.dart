/// `/settings/brand` Brand (`features/settings/brand-pane.tsx`,
/// SET-BRD-001..021): the org's logo and card image (own-org uploads), its
/// web addresses, where else to find it (`social_links`), and the loyalty
/// card as customers will see it.
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane. No client gate (the server decides);
/// module `pos` at the route. The read failing is not an error state on the
/// web: the pane renders with no org data (SET-BRD-003).
library;

import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show
        ApiFilePart,
        Org,
        UpdateOrgRequest,
        UploadCardImageMultipart,
        UploadLogoMultipart;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/social_links.dart';
import 'brand_data.dart';
import 'brand_image.dart';
import 'card_face.dart';
import 'shop_address_card.dart';

/// The loading bars (`h-8 w-48`, two `h-40` cards).
abstract final class BrandMetrics {
  static const double titleBar = Space.xxl;
  static const double titleBarWidth = 192;
  static const double cardBar = 160;
}

class BrandPage extends ConsumerWidget {
  const BrandPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    final q = orgId == null ? null : ref.watch(orgBrandProvider(orgId));
    if (q != null && q.awaitingFirst) return const _BrandSkeleton();
    // A failed read is no error state: the pane goes on without the org.
    final org = q?.value;
    final c = context.madarColors;
    final brand = resolveCardBrand(org, programName: t('nav.loyalty'));

    Widget section(String title, Widget child, {String? description}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSectionHeader(title: title, description: description),
        child,
      ],
    );

    Widget uploader({
      required String key,
      required String? value,
      required String field,
      String? hint,
    }) => DashCard(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DashImageUploader(
          key: ValueKey(key),
          value: value,
          hint: hint,
          // No org in scope: nowhere to upload to.
          enabled: orgId != null,
          onPick: () => _pick(ref),
          onUpload: (f) => _upload(context, ref, orgId!, field, f),
          imageBuilder: (context, url) => brandImage(url),
        ),
      ),
    );

    return DashPageScaffold(
      title: t('settings.brand'),
      subtitle: t('settings.brandDesc'),
      width: DashPageWidth.reading,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xxl,
        children: [
          if (org != null && !org.customBranding) _TierNotice(t: t, c: c),
          section(
            t('settings.logo'),
            uploader(
              key: 'brand-logo',
              value: org?.logoUrl,
              field: 'logo',
              hint: t('settings.logoHint'),
            ),
          ),
          section(
            t('settings.cardImage'),
            description: t('settings.cardImageHint'),
            uploader(
              key: 'brand-card-image',
              value: org?.brandCardImage,
              field: 'image',
            ),
          ),
          if (org != null &&
              ShopAddressCard.shows(
                org.slug,
                org.customBranding,
                publicRootDomain(brandApiBase),
              ))
            ShopAddressCard(slug: org.slug, customBranding: org.customBranding),
          if (org != null)
            section(
              t('settings.links'),
              BrandLinksCard(key: ValueKey('brand-links-${org.id}'), org: org),
            ),
          section(
            t('settings.cardPreview'),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                BrandCardFace(
                  brand: brand,
                  balance: 3,
                  target: 5,
                  toGo: 2,
                  memberName: t('settings.previewMember'),
                ),
                Text(
                  t('settings.brandDerived'),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<DashPickedFile?> _pick(WidgetRef ref) async {
    final f = await ref.read(fileGatewayProvider).pickImage();
    if (f == null) return null;
    return DashPickedFile(
      bytes: Uint8List.fromList(f.bytes),
      name: f.name,
      mimeType: f.mimeType ?? _mimeOf(f.name),
    );
  }

  static String _mimeOf(String name) =>
      switch (name.split('.').last.toLowerCase()) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'svg' => 'image/svg+xml',
        _ => 'application/octet-stream',
      };

  /// `PUT /orgs/{id}/logo` (field `logo`) or `/card-image` (field `image`):
  /// toast, re-read the org (the palette is derived server-side), and hand
  /// the uploader the new address. A failure toasts the server's words and
  /// rethrows so the uploader shows them under the box too.
  static Future<String?> _upload(
    BuildContext context,
    WidgetRef ref,
    String orgId,
    String field,
    DashPickedFile f,
  ) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).orgs;
    final container = ProviderScope.containerOf(context, listen: false);
    final part = ApiFilePart(
      field: field,
      filename: f.name,
      bytes: f.bytes,
      contentType: f.mimeType,
    );
    final Org updated;
    try {
      updated = field == 'logo'
          ? await api.uploadOrgLogo(
              id: orgId,
              body: UploadLogoMultipart(logo: part),
            )
          : await api.uploadOrgCardImage(
              id: orgId,
              body: UploadCardImageMultipart(image: part),
            );
    } on Object catch (e) {
      if (context.mounted) DashToast.error(context, errorMessage(e, t));
      rethrow;
    }
    container.invalidate(orgBrandProvider(orgId));
    if (context.mounted) {
      DashToast.success(
        context,
        t(field == 'logo' ? 'settings.logoSaved' : 'settings.cardImageSaved'),
      );
    }
    final url = field == 'logo' ? updated.logoUrl : updated.brandCardImage;
    return url == null || url.isEmpty ? null : url;
  }
}

/// "Custom branding is not enabled", next to the preview it explains.
class _TierNotice extends StatelessWidget {
  const _TierNotice({required this.t, required this.c});

  final Translator t;
  final MadarColors c;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('brand-tier-off'),
    padding: const EdgeInsets.all(Space.md),
    decoration: BoxDecoration(
      color: c.muted.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(Radii.md),
      border: Border.all(color: c.hairline),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm + DashMetrics.hair,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: DashMetrics.hair),
          child: DashIcon('lock', size: IconSize.sm, color: c.textMuted),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xs,
            children: [
              Text(
                t('settings.brandTierOff'),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              Text(
                t('settings.brandTierOffHint'),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The loading state (the web returns only these bars, no header).
class _BrandSkeleton extends ConsumerWidget {
  const _BrandSkeleton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    key: const ValueKey('brand-loading'),
    label: ref.watch(tProvider)('common.loading'),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DashSkeleton(
            width: BrandMetrics.titleBarWidth,
            height: BrandMetrics.titleBar,
          ),
        ),
        DashSkeleton(height: BrandMetrics.cardBar, radius: Radii.card),
        DashSkeleton(height: BrandMetrics.cardBar, radius: Radii.card),
      ],
    ),
  );
}

/// Where else to find the shop (`SocialLinksCard`): the eight fields and
/// Save, `PATCH /orgs/{id}` with nothing but `social_links`. Seeded from the
/// saved links, and re-seeded when they change until the person edits.
class BrandLinksCard extends ConsumerStatefulWidget {
  const BrandLinksCard({required this.org, super.key});

  final Org org;

  @override
  ConsumerState<BrandLinksCard> createState() => _BrandLinksCardState();
}

class _BrandLinksCardState extends ConsumerState<BrandLinksCard> {
  final _formKey = GlobalKey<FormState>();
  late Map<String, String> _values;
  Map<String, Object?>? _from;
  bool _edited = false;
  bool _busy = false;

  static const _eq = DeepCollectionEquality();

  @override
  void initState() {
    super.initState();
    _seed(widget.org.socialLinks);
  }

  void _seed(Map<String, Object?> saved) {
    _from = saved;
    _values = socialLinksToForm(saved);
  }

  @override
  void didUpdateWidget(BrandLinksCard old) {
    super.didUpdateWidget(old);
    final saved = widget.org.socialLinks;
    if (!_edited && !_eq.equals(saved, _from)) _seed(saved);
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).orgs;
    final container = ProviderScope.containerOf(context, listen: false);
    final org = widget.org;
    setState(() => _busy = true);
    try {
      await api.updateOrg(
        id: org.id,
        body: UpdateOrgRequest(
          socialLinks: socialLinksPatch(_values, org.socialLinks),
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        DashToast.error(context, errorMessage(e, t));
      }
      return;
    }
    container.invalidate(orgBrandProvider(org.id));
    if (!mounted) return;
    // The re-read the save asked for re-seeds the form with what was kept.
    setState(() {
      _busy = false;
      _edited = false;
    });
    DashToast.success(context, t('settings.socialSaved'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return DashCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            SocialLinksFields(
              values: _values,
              enabled: !_busy,
              onChanged: (p, v) => setState(() {
                _edited = true;
                _values = {..._values, p: v};
              }),
              onSubmitted: _save,
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: DashButton(
                key: const ValueKey('brand-links-save'),
                label: t('common.save'),
                loading: _busy,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
