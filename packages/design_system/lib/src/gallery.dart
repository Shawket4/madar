/// The design-system visual-QA gallery — a dev-only screen that renders
/// every token and widget in the package so both themes can be eyeballed
/// side by side. Not shipped in release navigation.
library;

import 'dart:async';

import 'package:design_system/src/banners.dart';
import 'package:design_system/src/brand.dart';
import 'package:design_system/src/icons.dart';
import 'package:design_system/src/money.dart';
import 'package:design_system/src/sheet.dart';
import 'package:design_system/src/skeleton.dart';
import 'package:design_system/src/states.dart';
import 'package:design_system/src/toast.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:design_system/src/touch.dart';
import 'package:flutter/material.dart';

/// Fixed height for the empty/error state demos (they normally fill a
/// screen; the gallery boxes them).
const double _stateDemoHeight = 300;

/// Width of one tile in the icon-catalog grid.
const double _iconTileWidth = 92;

/// Side of one color-swatch square.
const double _swatchSide = 56;

/// Radii demo box size.
const double _radiiBoxWidth = 72;
const double _radiiBoxHeight = 44;

/// The visual-QA gallery screen. Push it from a dev entry point:
///
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute<void>(builder: (_) => const GalleryScreen()),
/// );
/// ```
///
/// Theme (light/dark) is toggled by the HOST app — the gallery renders
/// whatever `Theme`/`MadarColors` it is given. An in-screen toggle flips
/// the text direction to QA RTL mirroring.
class GalleryScreen extends StatefulWidget {
  /// Creates the gallery screen.
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _rtl = false;
  ToastData? _toast;
  int _nextToastId = 0;

  void _showToast(ChipTone tone) {
    setState(() {
      _toast = ToastData(
        id: _nextToastId++,
        text: 'Toast · ${tone.name}',
        tone: tone,
        icon: _toneIcon(tone),
        actionLabel: 'Action',
      );
    });
  }

  void _dismissToast(int id) {
    if (_toast?.id == id) setState(() => _toast = null);
  }

  static String? _toneIcon(ChipTone tone) => switch (tone) {
    ChipTone.success => 'checkmark.circle',
    ChipTone.warning => 'exclamationmark.triangle',
    ChipTone.danger => 'xmark.circle',
    ChipTone.info || ChipTone.accent => 'checkmark.seal',
    ChipTone.neutral => null,
  };

  void _openSheet(BuildContext context, SheetSize size) {
    unawaited(
      showMadarSheet<void>(
        context,
        size: size,
        builder: (context) => _GallerySheetContent(size: size),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Scaffold(
      body: Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Stack(
          children: [
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.all(Space.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(colors),
                    const SizedBox(height: Space.xxl),
                    _buildBrandSection(colors),
                    const SizedBox(height: Space.xxl),
                    _buildColorSection(colors),
                    const SizedBox(height: Space.xxl),
                    _buildTypeSection(colors),
                    const SizedBox(height: Space.xxl),
                    _buildSpacingSection(colors),
                    const SizedBox(height: Space.xxl),
                    _buildRadiiSection(colors),
                    const SizedBox(height: Space.xxl),
                    _buildToneSection(colors),
                    const SizedBox(height: Space.xxl),
                    _buildButtonSection(colors),
                    const SizedBox(height: Space.xxl),
                    _buildSkeletonSection(colors),
                    const SizedBox(height: Space.xxl),
                    _buildStatesSection(colors),
                    const SizedBox(height: Space.xxl),
                    _buildMoneySection(colors),
                    const SizedBox(height: Space.xxl),
                    _buildOverlaySection(colors),
                    const SizedBox(height: Space.xxl),
                    _buildHapticsSection(colors),
                    const SizedBox(height: Space.xxl),
                    _buildIconSection(colors),
                  ],
                ),
              ),
            ),
            ToastHost(
              _toast,
              onAction: () => setState(() => _toast = null),
              onDismiss: _dismissToast,
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────

  Widget _buildHeader(MadarColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Design System Gallery',
          style: MadarType.h1.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: Space.xs),
        Text(
          'Dev-only visual QA. Theme (light/dark) is toggled by the '
          'host app; this screen renders whatever it is handed.',
          style: MadarType.bodySm.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.md),
        _GalleryButton(
          label: _rtl
              ? 'Direction: RTL (tap for LTR)'
              : 'Direction: LTR '
                    '(tap for RTL)',
          icon: 'arrow.up.arrow.down',
          filled: false,
          onTap: () => setState(() => _rtl = !_rtl),
        ),
      ],
    );
  }

  // ── Brand ─────────────────────────────────────────────────────────

  Widget _buildBrandSection(MadarColors colors) {
    return const _Section(
      title: 'Brand',
      child: Wrap(
        spacing: Space.xl,
        runSpacing: Space.lg,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          MadarLockup(),
          MadarLockup(arabic: true),
          MadarSymbol(),
        ],
      ),
    );
  }

  // ── Colors ────────────────────────────────────────────────────────

  Widget _buildColorSection(MadarColors colors) {
    final roles = <(String, Color)>[
      ('bg', colors.bg),
      ('surface', colors.surface),
      ('surfaceAlt', colors.surfaceAlt),
      ('surfaceRaised', colors.surfaceRaised),
      ('border', colors.border),
      ('borderLight', colors.borderLight),
      ('textPrimary', colors.textPrimary),
      ('textSecondary', colors.textSecondary),
      ('textMuted', colors.textMuted),
      ('textOnAccent', colors.textOnAccent),
      ('accent', colors.accent),
      ('accentBg', colors.accentBg),
      ('navy', colors.navy),
      ('navyBg', colors.navyBg),
      ('success', colors.success),
      ('successBg', colors.successBg),
      ('danger', colors.danger),
      ('dangerBg', colors.dangerBg),
      ('warning', colors.warning),
      ('warningBg', colors.warningBg),
    ];
    return _Section(
      title: 'Color roles',
      child: Wrap(
        spacing: Space.md,
        runSpacing: Space.md,
        children: [
          for (final (name, color) in roles)
            SizedBox(
              width: _iconTileWidth,
              child: Column(
                children: [
                  Container(
                    width: _swatchSide,
                    height: _swatchSide,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: colors.border),
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: MadarType.labelSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Type ──────────────────────────────────────────────────────────

  Widget _buildTypeSection(MadarColors colors) {
    final scale = <(String, TextStyle)>[
      ('display', MadarType.display),
      ('h1', MadarType.h1),
      ('h2', MadarType.h2),
      ('h3', MadarType.h3),
      ('title', MadarType.title),
      ('body', MadarType.body),
      ('bodySm', MadarType.bodySm),
      ('label', MadarType.label),
      ('labelSm', MadarType.labelSm),
      ('money', MadarType.money),
      ('moneyLg', MadarType.moneyLg),
      ('moneyDisplay', MadarType.moneyDisplay),
    ];
    return _Section(
      title: 'Type scale',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (name, style) in scale)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      name,
                      style: MadarType.labelSm.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      name.startsWith('money') ? '1,234.56' : 'Madar POS مدار',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Spacing ───────────────────────────────────────────────────────

  Widget _buildSpacingSection(MadarColors colors) {
    const steps = <(String, double)>[
      ('xs', Space.xs),
      ('sm', Space.sm),
      ('md', Space.md),
      ('lg', Space.lg),
      ('xl', Space.xl),
      ('xxl', Space.xxl),
    ];
    return _Section(
      title: 'Spacing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (name, value) in steps)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      '$name · ${value.toInt()}',
                      style: MadarType.labelSm.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                  Container(
                    width: value * 4,
                    height: Space.md,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(Radii.xs / 2),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Radii ─────────────────────────────────────────────────────────

  Widget _buildRadiiSection(MadarColors colors) {
    const steps = <(String, double)>[
      ('xs', Radii.xs),
      ('sm', Radii.sm),
      ('md', Radii.md),
      ('lg', Radii.lg),
      ('xl', Radii.xl),
      ('xxl', Radii.xxl),
      ('pill', Radii.pill),
    ];
    return _Section(
      title: 'Radii',
      child: Wrap(
        spacing: Space.md,
        runSpacing: Space.md,
        children: [
          for (final (name, value) in steps)
            Column(
              children: [
                Container(
                  width: _radiiBoxWidth,
                  height: _radiiBoxHeight,
                  decoration: BoxDecoration(
                    color: colors.accentBg,
                    borderRadius: BorderRadius.circular(value),
                    border: Border.all(color: colors.accent),
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  name,
                  style: MadarType.labelSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Tones ─────────────────────────────────────────────────────────

  Widget _buildToneSection(MadarColors colors) {
    return _Section(
      title: 'Tones · banners + chips',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final tone in ChipTone.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
              child: NoticeBanner(
                text: 'NoticeBanner · ${tone.name}',
                tone: tone,
                icon: _toneIcon(tone),
                trailing: tone == ChipTone.danger
                    ? const BannerActionPill(label: 'Act')
                    : null,
                onTap: tone == ChipTone.danger
                    ? () => _showToast(ChipTone.danger)
                    : null,
              ),
            ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final tone in ChipTone.values)
                StatusChip(label: tone.name, tone: tone),
              const StatusChip(
                label: 'with icon',
                tone: ChipTone.accent,
                icon: 'wifi',
              ),
              const StatusChip(
                label: 'pending',
                tone: ChipTone.warning,
                badgeCount: 7,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Buttons ───────────────────────────────────────────────────────

  Widget _buildButtonSection(MadarColors colors) {
    return _Section(
      title: 'Buttons · tactile press scales',
      child: Wrap(
        spacing: Space.md,
        runSpacing: Space.md,
        children: [
          _GalleryButton(
            label: 'pressScale ${MotionSpec.pressScale}',
            icon: 'cart',
            onTap: () => _showToast(ChipTone.accent),
          ),
          _GalleryButton(
            label: 'pressScaleKey ${MotionSpec.pressScaleKey}',
            icon: 'number',
            scale: MotionSpec.pressScaleKey,
            filled: false,
            onTap: () => _showToast(ChipTone.neutral),
          ),
        ],
      ),
    );
  }

  // ── Skeletons ─────────────────────────────────────────────────────

  Widget _buildSkeletonSection(MadarColors colors) {
    return const _Section(
      title: 'Skeletons · live pulse',
      child: SkeletonScope(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBlock(width: 180),
            SizedBox(height: Space.sm),
            SkeletonBlock(width: 120, height: 11),
            SizedBox(height: Space.md),
            SkeletonRow(),
            SkeletonList(count: 3),
          ],
        ),
      ),
    );
  }

  // ── States ────────────────────────────────────────────────────────

  Widget _buildStatesSection(MadarColors colors) {
    return _Section(
      title: 'Empty + error states',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: SizedBox(
              height: _stateDemoHeight,
              child: EmptyState(
                icon: 'tray',
                title: 'Nothing here yet',
                message: 'EmptyState — calm, not broken.',
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: SizedBox(
              height: _stateDemoHeight,
              child: ErrorState(
                message: 'ErrorState — something failed.',
                retryLabel: 'Retry',
                onRetry: () => _showToast(ChipTone.success),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Money ─────────────────────────────────────────────────────────

  Widget _buildMoneySection(MadarColors colors) {
    return _Section(
      title: 'Money',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MoneyText(1250, currency: 'egp'),
          const SizedBox(height: Space.sm),
          MoneyText(
            -50000,
            currency: 'egp',
            color: colors.danger,
          ),
          const SizedBox(height: Space.sm),
          const MoneyText(98765432, currency: 'egp'),
          const SizedBox(height: Space.sm),
          MoneyText(
            123456789,
            currency: 'egp',
            style: MadarType.moneyLg,
          ),
          const SizedBox(height: Space.sm),
          MoneyText(
            123456789,
            currency: 'egp',
            style: MadarType.moneyDisplay,
          ),
        ],
      ),
    );
  }

  // ── Sheets + toasts ───────────────────────────────────────────────

  Widget _buildOverlaySection(MadarColors colors) {
    return _Section(
      title: 'Sheets + toasts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final size in SheetSize.values)
                Builder(
                  builder: (context) => _GalleryButton(
                    label: 'Sheet · ${size.name}',
                    icon: 'chevron.up',
                    onTap: () => _openSheet(context, size),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final tone in ChipTone.values)
                _GalleryButton(
                  label: 'Toast · ${tone.name}',
                  filled: false,
                  onTap: () => _showToast(tone),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Haptics ───────────────────────────────────────────────────────

  Widget _buildHapticsSection(MadarColors colors) {
    final types = <(String, VoidCallback)>[
      ('selection', MadarHaptics.selection),
      ('impact', MadarHaptics.impact),
      ('success', MadarHaptics.success),
      ('warning', MadarHaptics.warning),
    ];
    return _Section(
      title: 'Haptics',
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final (name, fire) in types)
            _GalleryButton(label: name, filled: false, onTap: fire),
        ],
      ),
    );
  }

  // ── Icons ─────────────────────────────────────────────────────────

  Widget _buildIconSection(MadarColors colors) {
    return _Section(
      title: 'Icon catalog · ${debugCatalogNames.length} names',
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.md,
        children: [
          for (final name in debugCatalogNames)
            SizedBox(
              width: _iconTileWidth,
              child: Column(
                children: [
                  Container(
                    width: Metrics.iconTile,
                    height: Metrics.iconTile,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(Radii.xs),
                      border: Border.all(color: colors.borderLight),
                    ),
                    child: Center(
                      child: MadarIcon(
                        name,
                        tint: colors.textPrimary,
                        size: IconSize.xl,
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: MadarType.labelSm.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A gallery section: uppercase tracked label header + content.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: MadarType.label.copyWith(
            color: colors.textMuted,
            letterSpacing: MadarType.tracking,
          ),
        ),
        const SizedBox(height: Space.md),
        child,
      ],
    );
  }
}

/// A compact demo button on [TactileScale] — filled (accent) or outline.
class _GalleryButton extends StatelessWidget {
  const _GalleryButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.scale = MotionSpec.pressScale,
    this.filled = true,
  });

  final String label;
  final VoidCallback onTap;
  final String? icon;
  final double scale;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = filled ? colors.textOnAccent : colors.textPrimary;
    return Semantics(
      button: true,
      child: TactileScale(
        scale: scale,
        onTap: onTap,
        child: Container(
          height: Metrics.inputHeight,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.lg,
          ),
          decoration: BoxDecoration(
            color: filled ? colors.accent : colors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: filled ? null : Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                MadarIcon(icon, tint: fg, size: IconSize.lg),
                const SizedBox(width: Space.sm),
              ],
              Text(label, style: MadarType.title.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Demo content shown inside the gallery's [showMadarSheet] presentations.
class _GallerySheetContent extends StatelessWidget {
  const _GallerySheetContent({required this.size});

  final SheetSize size;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MadarSheet · ${size.name}',
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Height cap: ${(size.heightFraction * 100).round()}% of the '
            'container. Drag the handle down, tap the scrim, or press '
            'back to dismiss — the card always slides out first.',
            style: MadarType.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.xl),
          _GalleryButton(
            label: 'Close',
            icon: 'xmark',
            onTap: () => unawaited(Navigator.of(context).maybePop()),
          ),
        ],
      ),
    );
  }
}
