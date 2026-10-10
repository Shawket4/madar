/// The customer's loyalty card face as Brand previews it
/// (`features/loyalty/public/card-face.tsx` + `stamp-row.tsx`, SET-BRD-018/019):
/// stamps mode, the org's resolved colours, its logo on a plate, the card
/// image band, the figure, the stamp row, the "more orders" line and the
/// member footer. Only what the preview draws is ported (no QR, no rewards
/// ready, no points bar).
library;

import 'dart:math' as math;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'brand_data.dart';
import 'brand_image.dart';

/// The card's fixed web sizes (`rounded-[28px]`, `size-56` blooms,
/// `text-[56px]` figure, …).
abstract final class CardFaceMetrics {
  static const double radius = 28;
  static const double bloom = 224;
  static const double logo = 48;
  static const double logoPad = 6;
  static const double bandRatio = 2.6;
  static const double figure = 56;
  static const double name = 15;
  static const double program = 11;
  static const double unit = 14;
  static const double line = 15;
  static const double memberLabel = 10;
  static const double member = 13;
  static const double stampText = 13;
  static const double stampGap = Space.xs;
  static const double track = 3;
}

class BrandCardFace extends ConsumerWidget {
  const BrandCardFace({
    required this.brand,
    required this.balance,
    required this.target,
    required this.toGo,
    this.memberName,
    super.key,
  });

  final CardBrand brand;
  final int balance;
  final int target;
  final int toGo;
  final String? memberName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final bg = hexColor(brand.background);
    final fg = hexColor(brand.foreground);
    final accent = hexColor(brand.accent);
    final muted = brand.muted;
    // Tracking spreads Latin capitals; it would break Arabic's joins.
    double track(double em, double size) => t.isRtl ? 0 : em * size;
    final unit = t('loyalty.unit.orders');
    final ofTarget = t('loyalty.ofTarget', args: {'n': target, 'unit': unit});
    const side = EdgeInsets.symmetric(horizontal: Space.xl);

    Widget bloom(double opacity) => IgnorePointer(
      child: Container(
        width: CardFaceMetrics.bloom,
        height: CardFaceMetrics.bloom,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: opacity),
          shape: BoxShape.circle,
        ),
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CardFaceMetrics.radius),
        boxShadow: DashShadows.popover(context),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg),
        child: Stack(
          children: [
            PositionedDirectional(end: -64, top: -96, child: bloom(0.20)),
            PositionedDirectional(start: -80, bottom: -112, child: bloom(0.10)),
            Padding(
              padding: const EdgeInsets.only(top: Space.xl, bottom: Space.card),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: side,
                    child: Row(
                      spacing: Space.md,
                      children: [
                        if (brand.logoUrl != null)
                          Container(
                            key: const ValueKey('card-logo'),
                            width: CardFaceMetrics.logo,
                            height: CardFaceMetrics.logo,
                            padding: const EdgeInsets.all(
                              CardFaceMetrics.logoPad,
                            ),
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(Radii.card),
                            ),
                            child: brandImage(
                              brand.logoUrl!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MadarClippedText(
                                brand.orgName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DashType.bodyStrong.copyWith(
                                  fontSize: CardFaceMetrics.name,
                                  height: 1.25,
                                  color: fg,
                                ),
                              ),
                              const SizedBox(height: DashMetrics.hair),
                              MadarClippedText(
                                brand.programName.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DashType.smallMedium.copyWith(
                                  fontSize: CardFaceMetrics.program,
                                  letterSpacing: track(
                                    0.16,
                                    CardFaceMetrics.program,
                                  ),
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (brand.cardImageUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.card),
                      child: AspectRatio(
                        key: const ValueKey('card-band'),
                        aspectRatio: CardFaceMetrics.bandRatio,
                        child: brandImage(brand.cardImageUrl!),
                      ),
                    ),
                  Padding(
                    padding: side.copyWith(top: Space.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Space.lg,
                      children: [
                        MergeSemantics(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            spacing: Space.sm,
                            children: [
                              Text(
                                '$balance',
                                style: DashType.monoStrong.copyWith(
                                  fontSize: CardFaceMetrics.figure,
                                  height: 1,
                                  color: fg,
                                ),
                              ),
                              Flexible(
                                child: MadarClippedText(
                                  ofTarget,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DashType.body.copyWith(
                                    fontSize: CardFaceMetrics.unit,
                                    color: muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ExcludeSemantics(
                          child: StampRow(
                            earned: balance,
                            target: target,
                            accent: accent,
                            onAccent: bg,
                            muted: muted,
                          ),
                        ),
                        Text(
                          t('loyalty.ordersToGo', args: {'n': toGo}),
                          style: DashType.body.copyWith(
                            fontSize: CardFaceMetrics.line,
                            height: 1.375,
                            color: fg,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (memberName != null)
                    Padding(
                      padding: side.copyWith(top: Space.xl),
                      child: Container(
                        padding: const EdgeInsets.only(top: Space.lg),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: muted)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('loyalty.member').toUpperCase(),
                              style: DashType.smallMedium.copyWith(
                                fontSize: CardFaceMetrics.memberLabel,
                                letterSpacing: track(
                                  0.18,
                                  CardFaceMetrics.memberLabel,
                                ),
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: DashMetrics.hair),
                            MadarClippedText(
                              memberName!.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DashType.bodyStrong.copyWith(
                                fontSize: CardFaceMetrics.member,
                                letterSpacing: track(
                                  0.08,
                                  CardFaceMetrics.member,
                                ),
                                color: fg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The steps toward the next reward (`StampRow`): one disc per step on a
/// track, done in the accent with a check, the next one ringed, numerals up
/// to nine steps.
class StampRow extends StatelessWidget {
  const StampRow({
    required this.earned,
    required this.target,
    required this.accent,
    required this.onAccent,
    required this.muted,
    super.key,
  });

  final int earned;
  final int target;
  final Color accent;
  final Color onAccent;
  final Color muted;

  /// A disc's largest size by how many there are (`2.5rem`, `2.125rem`,
  /// `1.625rem`).
  double get cap => target <= 5
      ? 40
      : target <= 9
      ? 34
      : 26;

  @override
  Widget build(BuildContext context) {
    final filled = earned.clamp(0, target);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final step = math.min(
          cap,
          (w - (target - 1) * CardFaceMetrics.stampGap) / target,
        );
        final done = filled > 1 && target > 1
            ? (w - step) * (filled - 1) / (target - 1)
            : 0.0;
        final top = (step - CardFaceMetrics.track) / 2;
        Widget bar(Color color, {double? width}) => Container(
          width: width,
          height: CardFaceMetrics.track,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
        );
        return SizedBox(
          height: step,
          child: Stack(
            children: [
              PositionedDirectional(
                start: step / 2,
                end: step / 2,
                top: top,
                child: bar(muted.withValues(alpha: muted.a * 0.4)),
              ),
              PositionedDirectional(
                start: step / 2,
                top: top,
                child: bar(accent, width: done),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < target; i++)
                    _Stamp(
                      size: step,
                      done: i < filled,
                      next: i == filled,
                      number: target <= 9 ? i + 1 : null,
                      accent: accent,
                      onAccent: onAccent,
                      muted: muted,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.size,
    required this.done,
    required this.next,
    required this.number,
    required this.accent,
    required this.onAccent,
    required this.muted,
  });

  final double size;
  final bool done;
  final bool next;
  final int? number;
  final Color accent;
  final Color onAccent;
  final Color muted;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: done ? accent : onAccent,
      border: done
          ? null
          : Border.all(color: next ? accent : muted, width: next ? 2 : 1.5),
    ),
    child: number == null
        ? null
        : done
        ? DashIcon('check', size: IconSize.xs, color: onAccent)
        : Text(
            '$number',
            style: DashType.bodyStrong.copyWith(
              fontSize: CardFaceMetrics.stampText,
              height: 1,
              color: muted,
            ),
          ),
  );
}
