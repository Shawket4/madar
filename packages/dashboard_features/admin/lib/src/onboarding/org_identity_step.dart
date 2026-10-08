/// "Name your café" (ADM-ONB-012..014, 030, 031; web `OrgIdentityBody`): the
/// logo (uploaded the moment it is picked), the café's name and currency,
/// and "Save & continue". What is typed lives only while this step shows;
/// coming back reads the org again.
library;

import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart'
    show ApiFilePart, UpdateOrgRequest, UploadLogoMultipart;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'onboarding_config.dart';
import 'onboarding_data.dart';

class OnbOrgIdentityStep extends ConsumerStatefulWidget {
  const OnbOrgIdentityStep({
    required this.orgId,
    required this.onNext,
    super.key,
  });

  final String orgId;
  final VoidCallback onNext;

  /// The logo box's widest (the uploader's own cap).
  static const double logoWidth = 200;

  @override
  ConsumerState<OnbOrgIdentityStep> createState() => _OnbOrgIdentityStepState();
}

class _OnbOrgIdentityStepState extends ConsumerState<OnbOrgIdentityStep> {
  String? _name;
  String? _currency;
  bool _busy = false;

  Future<void> _save(String name, String currency) async {
    final t = ref.read(tProvider);
    setState(() => _busy = true);
    try {
      final trimmed = name.trim();
      await ref
          .read(apiProvider)
          .orgs
          .updateOrg(
            id: widget.orgId,
            body: UpdateOrgRequest(
              name: trimmed.isEmpty ? null : trimmed,
              currencyCode: currency,
            ),
          );
      invalidateOnbOrg(ref, widget.orgId);
      await ref.read(onbOrgProvider(widget.orgId).future);
      refreshOnboarding(ref, widget.orgId);
      if (!mounted) return;
      DashToast.success(context, t('onboarding.steps.org_profile.saved'));
      widget.onNext();
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<DashPickedFile?> _pick() async {
    final f = await ref.read(fileGatewayProvider).pickImage();
    if (f == null) return null;
    return DashPickedFile(
      bytes: Uint8List.fromList(f.bytes),
      name: f.name,
      mimeType: f.mimeType ?? _mimeOf(f.name),
    );
  }

  Future<String?> _upload(DashPickedFile file) async {
    final t = ref.read(tProvider);
    try {
      final updated = await ref
          .read(apiProvider)
          .orgs
          .uploadOrgLogo(
            id: widget.orgId,
            body: UploadLogoMultipart(
              logo: ApiFilePart(
                field: 'logo',
                filename: file.name,
                bytes: file.bytes,
                contentType: file.mimeType,
              ),
            ),
          );
      final logo = updated.logoUrl;
      // A platform admin's picked org keeps its logo for the shell (the
      // same org, so the branch stays).
      final session = ref.read(currentSessionProvider);
      if (logo != null && (session?.isPlatform ?? false)) {
        await ref
            .read(selectedOrgProvider.notifier)
            .select(widget.orgId, logoUrl: logo);
      }
      invalidateOnbOrg(ref, widget.orgId);
      refreshOnboarding(ref, widget.orgId);
      return logo;
    } on Object catch (e) {
      // The server's words, under the picker.
      throw OnbUploadFailure(errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final org = ref.watch(onbOrgProvider(widget.orgId)).value;
    final name = _name ?? org?.name ?? '';
    final currency = _currency ?? org?.currencyCode ?? 'EGP';
    final twoUp = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    const k = 'onboarding.steps.org_profile';

    final nameField = DashTextField(
      key: const ValueKey('onb-org-name'),
      label: t('$k.name'),
      placeholder: t('$k.namePh'),
      value: name,
      onChanged: (v) => setState(() => _name = v),
    );
    final currencyField = DashSelectField<String>(
      key: const ValueKey('onb-org-currency'),
      label: t('$k.currency'),
      value: currency,
      options: [
        for (final code in onboardingCurrencies)
          DashOption(value: code, label: code),
      ],
      onChanged: (v) => setState(() => _currency = v),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg + DashMetrics.hair * 2,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final logo = (box.maxWidth * 0.45).clamp(
              Space.xxl * 3,
              OnbOrgIdentityStep.logoWidth,
            );
            return Row(
              spacing: Space.lg,
              children: [
                SizedBox(
                  width: logo,
                  child: DashImageUploader(
                    key: const ValueKey('onb-logo'),
                    value: org?.logoUrl,
                    hint: t('$k.logoHint'),
                    onPick: _pick,
                    onUpload: _upload,
                    imageBuilder: (context, url) => OnbImage(url: url),
                  ),
                ),
                Expanded(
                  child: Text(
                    t('$k.logoCopy'),
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                ),
              ],
            );
          },
        ),
        if (twoUp)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.lg,
            children: [
              Expanded(child: nameField),
              Expanded(child: currencyField),
            ],
          )
        else ...[
          nameField,
          currencyField,
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DashButton(
            label: t('$k.save'),
            loading: _busy,
            onPressed: () => _save(name, currency),
          ),
        ),
      ],
    );
  }
}

/// A failed logo upload, worded for the person (shown under the picker).
class OnbUploadFailure implements Exception {
  const OnbUploadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

String _mimeOf(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  return 'application/octet-stream';
}

/// An image by address: a `data:` URI drawn from its bytes, anything else
/// from the network, a store glyph when it cannot be drawn.
class OnbImage extends StatelessWidget {
  const OnbImage({required this.url, this.fit = BoxFit.cover, super.key});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    Widget fallback(BuildContext context, Object e, StackTrace? s) => Center(
      child: DashIcon('store', size: IconSize.lg, color: c.textMuted),
    );
    if (url.startsWith('data:')) {
      Uint8List? bytes;
      try {
        bytes = Uri.parse(url).data?.contentAsBytes();
      } on FormatException {
        bytes = null;
      }
      if (bytes == null || bytes.isEmpty) {
        return fallback(context, 'empty', null);
      }
      return Image.memory(bytes, fit: fit, errorBuilder: fallback);
    }
    return Image.network(url, fit: fit, errorBuilder: fallback);
  }
}
