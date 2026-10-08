/// Small pieces the recipe-bases and packaging-rules pages share, drawn the
/// web's way (`bases-page.tsx`, `packaging-rules-page.tsx`):
///
/// - [ModelingList] / [ModelingRow]: the bordered list with a name, an
///   "Inactive" pill, a muted sub-line and the Edit / Delete glyph buttons;
/// - [ModelingSkeleton]: the one 160 tall loading block;
/// - [ModelingAlert]: the web's `Alert` (title + description in a bordered
///   box), for "Rules applied";
/// - [ModelingBilingualName]: the paired English / Arabic name inputs whose
///   Enter submits the dialog (MENU-AREA-013);
/// - [ModelingSwitch]: the switch-then-label row of the dialogs' "Active";
/// - [ModelingDisclosure]: the `<details>` "Used by" toggle.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The web's `h-40` loading block.
const double _skeletonHeight = Space.xxl * 5;

/// The rows in one bordered card with hairlines between them (`divide-y
/// rounded-lg border`).
class ModelingList extends StatelessWidget {
  const ModelingList({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DashListCard(children: children);
}

/// One row: the name (one line) and an "Inactive" pill when off, the muted
/// sub-line, and — for a person who may edit — Edit and Delete.
class ModelingRow extends StatelessWidget {
  const ModelingRow({
    required this.name,
    required this.subtitle,
    required this.active,
    required this.inactiveLabel,
    this.truncateSubtitle = false,
    this.onEdit,
    this.onDelete,
    this.editLabel,
    this.deleteLabel,
    super.key,
  });

  final String name;
  final String subtitle;
  final bool active;
  final String inactiveLabel;

  /// One line with an ellipsis (rules) instead of wrapping (bases).
  final bool truncateSubtitle;

  /// Null hides the row actions (no `menu.items.edit`).
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final String? editLabel;
  final String? deleteLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final meta = DashType.meta.copyWith(color: c.textSecondary);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: DashMetrics.listRow),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: Space.lg,
          end: Space.sm,
          top: Space.sm,
          bottom: Space.sm,
        ),
        child: Row(
          spacing: Space.md,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: DashMetrics.hair,
                children: [
                  Row(
                    spacing: Space.sm,
                    children: [
                      Flexible(
                        child: MadarClippedText(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (!active)
                        DashStatusPill(label: inactiveLabel, small: true),
                    ],
                  ),
                  if (truncateSubtitle)
                    MadarClippedText(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: meta,
                    )
                  else
                    Text(subtitle, style: meta),
                ],
              ),
            ),
            if (onEdit != null)
              DashIconButton(
                icon: 'pencil',
                semanticLabel: editLabel ?? context.dashStrings.edit,
                onPressed: onEdit,
              ),
            if (onDelete != null)
              DashIconButton(
                icon: 'trash-2',
                color: c.danger,
                semanticLabel: deleteLabel ?? context.dashStrings.delete,
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

/// The list's loading block (`Skeleton h-40 w-full rounded-lg`).
class ModelingSkeleton extends StatelessWidget {
  const ModelingSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const DashSkeleton(
    width: double.infinity,
    height: _skeletonHeight,
    radius: Radii.control,
  );
}

/// The web's `Alert` (default variant): a bordered box with a title and a
/// description under it.
class ModelingAlert extends StatelessWidget {
  const ModelingAlert({
    required this.title,
    required this.description,
    super.key,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DashMetrics.hair,
          children: [
            Text(
              title,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            Text(
              description,
              style: DashType.body.copyWith(color: c.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The web's `BilingualField` for a name: English then Arabic (typed
/// right-to-left), side by side from 640 wide, stacked below. Enter in
/// either submits the dialog, as a browser submits the form.
class ModelingBilingualName extends StatelessWidget {
  const ModelingBilingualName({
    required this.label,
    required this.en,
    required this.ar,
    required this.onEnChanged,
    required this.onArChanged,
    required this.onSubmitted,
    this.enError,
    super.key,
  });

  final String label;
  final String en;
  final String ar;
  final ValueChanged<String> onEnChanged;
  final ValueChanged<String> onArChanged;
  final VoidCallback onSubmitted;
  final String? enError;

  @override
  Widget build(BuildContext context) {
    final enF = DashTextField(
      label: label,
      value: en,
      onChanged: onEnChanged,
      errorText: enError,
      textDirection: TextDirection.ltr,
      onSubmitted: (_) => onSubmitted(),
    );
    final arF = DashTextField(
      label: context.dashStrings.arabicLabel(label),
      value: ar,
      onChanged: onArChanged,
      textDirection: TextDirection.rtl,
      onSubmitted: (_) => onSubmitted(),
    );
    return MediaQuery.sizeOf(context).width >= DashBreakpoints.sm
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(child: enF),
              Expanded(child: arF),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [enF, arF],
          );
  }
}

/// The dialogs' "Active": the switch, then its label (a tap on the label
/// toggles it too, as the web's `<label>` does).
class ModelingSwitch extends StatelessWidget {
  const ModelingSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Row(
      spacing: Space.md,
      children: [
        DashSwitch(value: value, onChanged: onChanged, semanticLabel: label),
        Flexible(
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(!value),
              child: Text(
                label,
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A closed-by-default disclosure (the web's `<details>` / `<summary>`):
/// a muted summary with a turning chevron, the [child] under it when open.
class ModelingDisclosure extends StatefulWidget {
  const ModelingDisclosure({
    required this.summary,
    required this.child,
    super.key,
  });

  final String summary;
  final Widget child;

  @override
  State<ModelingDisclosure> createState() => _ModelingDisclosureState();
}

class _ModelingDisclosureState extends State<ModelingDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DashPressable(
            onTap: () => setState(() => _open = !_open),
            semanticLabel: widget.summary,
            selected: _open,
            excludeChildSemantics: true,
            pressScale: false,
            builder: (context, s) => ConstrainedBox(
              constraints: const BoxConstraints(minHeight: DashMetrics.target),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs,
                children: [
                  DashIcon(
                    _open ? 'chevron-down' : DashIcon.forward(context),
                    size: IconSize.sm,
                    color: c.textSecondary,
                  ),
                  Text(
                    widget.summary,
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open) widget.child,
      ],
    );
  }
}
