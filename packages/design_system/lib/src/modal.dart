/// THE centred modal — the one dialog shape. A refusal's Retry / Discard, a
/// "Close the shift?" confirm.
///
/// A sheet slides up for a task with several controls; a modal floats in the
/// middle for one question with two answers. 20px corners, 24px inset, the
/// deep modal shadow, a 440 cap. On a phone it is edge-inset by the gutter
/// instead of capped.
library;

import 'package:design_system/src/controls.dart';
import 'package:design_system/src/responsive.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/elevation.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:flutter/material.dart';

/// A modal's width cap on a tablet.
const double modalMaxWidth = 440;

/// Presents [builder]'s content as a centred modal over a scrim. Resolves
/// with whatever the content pops.
Future<T?> showMadarModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final colors = context.madarColors;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: Opacities.scrim),
    transitionDuration: MotionSpec.standardDuration,
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: MotionSpec.springOut,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, _, _) {
      final gutter = MadarLayout.of(context).gutter;
      return SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: modalMaxWidth),
              child: Material(
                type: MaterialType.transparency,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(Radii.sheet),
                    boxShadow: MadarElevation.raised.shadows(
                      colors,
                      dark: dark,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(Space.xl),
                    child: Builder(builder: builder),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The standard modal body: a title, an optional line of body text, and a
/// row of one or two actions. Every string arrives localised.
///
/// ```dart
/// final retry = await showMadarModal<bool>(
///   context,
///   builder: (_) => MadarModalBody(
///     title: tr('outbox.stuck_title'),
///     body: serverSentence,
///     primary: MadarModalAction(tr('outbox.retry'), () => Navigator.pop(context, true)),
///     secondary: MadarModalAction(tr('outbox.discard'), () => Navigator.pop(context, false),
///       danger: true),
///   ),
/// );
/// ```
class MadarModalBody extends StatelessWidget {
  const MadarModalBody({
    required this.title,
    required this.primary,
    this.body,
    this.secondary,
    this.content,
    super.key,
  });

  final String title;
  final String? body;

  /// Anything between the text and the actions (a reason chip row).
  final Widget? content;
  final MadarModalAction primary;
  final MadarModalAction? secondary;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Text(title, style: MadarType.h2.copyWith(color: colors.textPrimary)),
        if (body != null)
          Text(
            body!,
            style: MadarType.body.copyWith(color: colors.textSecondary),
          ),
        ?content,
        Row(
          spacing: Space.md,
          children: [
            if (secondary != null)
              Expanded(
                child: MadarButton(
                  label: secondary!.label,
                  onTap: secondary!.onTap,
                  variant: secondary!.danger
                      ? MadarButtonVariant.danger
                      : MadarButtonVariant.secondary,
                ),
              ),
            Expanded(
              child: MadarButton(
                label: primary.label,
                onTap: primary.onTap,
                variant: primary.danger
                    ? MadarButtonVariant.danger
                    : MadarButtonVariant.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One answer in a [MadarModalBody].
@immutable
class MadarModalAction {
  const MadarModalAction(this.label, this.onTap, {this.danger = false});

  final String label;
  final VoidCallback onTap;

  /// Draws the danger fill. A discard, a void.
  final bool danger;
}
