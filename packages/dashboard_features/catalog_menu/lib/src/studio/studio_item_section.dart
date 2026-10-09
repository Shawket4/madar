/// Studio section 1, Item details (the web's `section-item.tsx`): the image,
/// the bilingual name and description, the category (with "+" for a new
/// one) and the active switch. Every edit is a draft until Save; a picked
/// image is STAGED (shown at once, uploaded by the save).
library;

import 'dart:typed_data';

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/category_dialog.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_text.dart';
import 'studio_model.dart';
import 'studio_widgets.dart';

/// The uploader's address for a staged file (drawn from its bytes).
const String _staged = 'staged:';

/// The uploader's address for a server picture still being processed: drawn
/// as a skeleton, with Replace and Remove over it (the web's `AssetImage`).
const String _processing = 'processing:';

class StudioItemSection extends ConsumerWidget {
  const StudioItemSection({
    required this.orgId,
    required this.item,
    required this.onChanged,
    required this.imageUrl,
    required this.pendingBytes,
    required this.uploaderKey,
    required this.onPickImage,
    this.processing = false,
    this.onRemoveImage,
    super.key,
  });

  final String? orgId;
  final ItemDraft item;
  final ValueChanged<ItemDraft> onChanged;

  /// The server's picture, unless its removal is staged.
  final String? imageUrl;
  final bool processing;

  /// A staged file's bytes.
  final Uint8List? pendingBytes;

  /// Changes whenever the staged state resets (Discard, Save, remove).
  final Key uploaderKey;
  final ValueChanged<DashPickedFile> onPickImage;

  /// Null = nothing to remove.
  final VoidCallback? onRemoveImage;

  Future<DashPickedFile?> _pick(WidgetRef ref) async {
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
        _ => 'application/octet-stream',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final lang = ref.watch(localeProvider);
    final wide = MediaQuery.sizeOf(context).width >= StudioMetrics.sm;
    final org = orgId;
    final categories = org == null
        ? null
        : ref.watch(menuCategoriesProvider(org)).value;

    final uploader = SizedBox(
      width: StudioMetrics.imageBox,
      child: DashImageUploader(
        key: uploaderKey,
        value: pendingBytes != null
            ? _staged
            : processing
            ? _processing
            : imageUrl,
        hint: t('menu.imageHint'),
        semanticLabel: t('uploader.choose'),
        onPick: () => _pick(ref),
        onUpload: (file) async {
          onPickImage(file);
          return _staged;
        },
        onRemove: onRemoveImage == null ? null : () async => onRemoveImage!(),
        imageBuilder: (context, url) => url == _staged && pendingBytes != null
            ? Image.memory(pendingBytes!, fit: BoxFit.cover)
            : url == _processing
            ? const DashSkeleton(height: StudioMetrics.imageBox, radius: 0)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, e, s) => Center(
                  child: DashIcon(
                    'image',
                    size: IconSize.lg,
                    color: c.textMuted,
                  ),
                ),
              ),
      ),
    );

    final category = DashFormField<String>(
      label: t('common.category'),
      builder: (context, invalid) => Row(
        spacing: Space.sm,
        children: [
          Expanded(
            child: DashSelect<String>(
              options: [
                for (final cat in categories ?? const [])
                  DashOption(
                    value: cat.id,
                    label: translatedName(cat.name, cat.nameTranslations, lang),
                  ),
              ],
              value: item.categoryId.isEmpty ? null : item.categoryId,
              searchable: true,
              placeholder: t('menu.selectCategory'),
              semanticLabel: t('common.category'),
              searchPlaceholder: t('common.search'),
              emptyText: t('common.noResults'),
              onChanged: (v) => onChanged(item.copyWith(categoryId: v)),
            ),
          ),
          DashIconButton(
            icon: 'plus',
            semanticLabel: t('menu.newCategory'),
            variant: DashButtonVariant.outline,
            onPressed: org == null
                ? null
                : () async {
                    final created = await showCategoryDialog(
                      context,
                      orgId: org,
                    );
                    if (created != null) {
                      onChanged(item.copyWith(categoryId: created.id));
                    }
                  },
          ),
        ],
      ),
    );

    final active = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        DashSwitch(
          value: item.isActive,
          semanticLabel: t('common.active'),
          onChanged: (v) => onChanged(item.copyWith(isActive: v)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DashMetrics.hair,
              children: [
                Text(
                  t('common.active'),
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                StudioHint(t('menu.studio.basics.activeHint')),
              ],
            ),
          ),
        ),
      ],
    );

    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        DashBilingualField(
          label: t('common.name'),
          en: item.name,
          ar: item.nameAr,
          onEnChanged: (v) => onChanged(item.copyWith(name: v)),
          onArChanged: (v) => onChanged(item.copyWith(nameAr: v)),
        ),
        DashBilingualField(
          label: t('common.description'),
          textarea: true,
          en: item.description,
          ar: item.descriptionAr,
          onEnChanged: (v) => onChanged(item.copyWith(description: v)),
          onArChanged: (v) => onChanged(item.copyWith(descriptionAr: v)),
        ),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.lg,
            children: [
              Expanded(child: category),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: Space.xl),
                  child: active,
                ),
              ),
            ],
          )
        else ...[
          category,
          active,
        ],
      ],
    );

    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xl,
            children: [
              uploader,
              Expanded(child: fields),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xl,
            children: [uploader, fields],
          );
  }
}
