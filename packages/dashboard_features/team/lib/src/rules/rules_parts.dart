/// The Rules page's small building blocks: the web's `Card` / `CardHeader`
/// geometry, a labelled field, an equal-column grid by the web's viewport
/// breakpoints (`sm` 640, `md` 768, `lg` 1024), the quiet and error lines,
/// and the confirmation that lists what a save changes.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The viewport is at least the web's `sm` (640).
bool rulesSm(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;

/// The viewport is at least the web's `md` (768).
bool rulesMd(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= DashBreakpoints.phone + Space.sm;

/// The viewport is at least the web's `lg` (1024).
bool rulesLg(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;

/// A card (`rounded-2xl border bg-card py-6`, its parts `gap-6` apart).
class RulesCardFrame extends StatelessWidget {
  const RulesCardFrame({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final pad = DashBreakpoints.isPhone(context) ? Space.card : Space.xl;
    return DashCard(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xl,
        children: children,
      ),
    );
  }
}

/// A card's title (16/600) and description (14, muted), `gap-2`.
class RulesCardHead extends StatelessWidget {
  const RulesCardHead({
    required this.title,
    this.description,
    this.icon,
    super.key,
  });

  final String title;
  final String? description;

  /// A glyph before the title (the preview's flask).
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Semantics(
          header: true,
          child: Row(
            spacing: Space.sm,
            children: [
              if (icon != null)
                DashIcon(icon!, size: IconSize.sm, color: c.textSecondary),
              Flexible(
                child: Text(
                  title,
                  style: DashType.sectionTitle.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
        ),
        if (description != null)
          Text(
            description!,
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}

/// A field's label (`Label`: 14/500, or 12/500 when [small]).
class RulesLabelText extends StatelessWidget {
  const RulesLabelText(this.text, {this.small = false, super.key});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: (small ? DashType.smallMedium : DashType.bodyMedium).copyWith(
      color: context.madarColors.textPrimary,
    ),
  );
}

/// A label above its control (`space-y-1.5`), then an error line when one
/// is due.
class RulesLabeled extends StatelessWidget {
  const RulesLabeled({
    required this.label,
    required this.child,
    this.small = false,
    this.error,
    super.key,
  });

  final String label;
  final Widget child;
  final bool small;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    spacing: Space.xs + DashMetrics.hair,
    children: [
      RulesLabelText(label, small: small),
      child,
      if (error != null) RulesErrorText(error!, small: true),
    ],
  );
}

/// A quiet 12px line (`text-xs text-muted-foreground`).
class RulesHintText extends StatelessWidget {
  const RulesHintText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: DashType.small.copyWith(color: context.madarColors.textSecondary),
  );
}

/// A form error (`text-destructive`), read out when it appears.
class RulesErrorText extends StatelessWidget {
  const RulesErrorText(this.text, {this.small = false, super.key});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: (small ? DashType.small : DashType.body).copyWith(
        color: context.madarColors.errorText,
      ),
    ),
  );
}

/// [children] in [columns] equal columns, `gap-3` apart (a CSS grid).
class RulesGrid extends StatelessWidget {
  const RulesGrid({required this.columns, required this.children, super.key});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (columns <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: children,
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.md,
          children: [
            for (var j = i; j < i + columns; j++)
              Expanded(
                child: j < children.length
                    ? children[j]
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: rows,
    );
  }
}

/// A rounded note (`rounded-2xl border p-4 text-sm`): the read-only line and
/// the rules-first warning.
class RulesNote extends StatelessWidget {
  const RulesNote({
    required this.child,
    this.tone = DashTone.neutral,
    super.key,
  });

  final Widget child;
  final DashTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final warn = tone == DashTone.warning;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: warn ? tone.wash(c) : c.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(
            color: warn ? tone.solid(c).withValues(alpha: 0.4) : c.hairline,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// One line of the save confirmation: a rule's label and what changes.
typedef RulesConfirmLine = ({String label, String? change});

/// The save confirmation (`useConfirm` with a description that lists every
/// changed rule): resolves true on the confirm button, false on Cancel,
/// Escape or a tap outside.
Future<bool> showRulesConfirm(
  BuildContext context, {
  required String title,
  required String hint,
  required List<RulesConfirmLine> lines,
  required String confirmLabel,
}) async {
  final c = context.madarColors;
  final r = await showGeneralDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: context.dashStrings.cancel,
    barrierColor: c.scrim,
    transitionDuration: DashMotion.of(context, DashMotion.base),
    pageBuilder: (ctx, a, b) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: DashMetrics.dialog),
            child: Material(
              type: MaterialType.transparency,
              child: _RulesConfirmCard(
                title: title,
                hint: hint,
                lines: lines,
                confirmLabel: confirmLabel,
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: DashMotion.ease),
      child: child,
    ),
  );
  return r ?? false;
}

class _RulesConfirmCard extends StatelessWidget {
  const _RulesConfirmCard({
    required this.title,
    required this.hint,
    required this.lines,
    required this.confirmLabel,
  });

  final String title;
  final String hint;
  final List<RulesConfirmLine> lines;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final cancel = DashButton(
      label: t.cancel,
      variant: DashButtonVariant.outline,
      expand: !wide,
      onPressed: () => Navigator.of(context).pop(false),
    );
    final confirm = DashButton(
      label: confirmLabel,
      expand: !wide,
      onPressed: () => Navigator.of(context).pop(true),
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: title,
      child: Container(
        padding: const EdgeInsets.all(Space.xl),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: c.hairline),
          boxShadow: DashShadows.modal(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: DashType.paneTitle.copyWith(color: c.textPrimary),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.sm,
                  children: [
                    Text(
                      hint,
                      style: DashType.body.copyWith(color: c.textSecondary),
                    ),
                    for (final l in lines)
                      Wrap(
                        spacing: Space.sm,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          Text(
                            l.label,
                            style: DashType.bodyMedium.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                          if (l.change != null)
                            Text(
                              l.change!,
                              style: DashType.body.copyWith(
                                color: c.textSecondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (wide)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: Space.sm,
                children: [cancel, confirm],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.sm,
                children: [confirm, cancel],
              ),
          ],
        ),
      ),
    );
  }
}
