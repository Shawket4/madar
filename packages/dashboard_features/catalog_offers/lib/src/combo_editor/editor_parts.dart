/// The small pieces the combo editor's sections share: a labelled field
/// with its red line or quiet hint, the marker a failed Save scrolls to, and
/// the number boxes' input rule.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Marks a field (or its red line) as failing, so a refused Save can bring
/// the first one into view ([scrollToFirstInvalid]).
class InvalidMark extends StatelessWidget {
  const InvalidMark({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// [InvalidMark] around [child] when [invalid].
class InvalidOr extends StatelessWidget {
  const InvalidOr({required this.invalid, required this.child, super.key});

  final bool invalid;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      invalid ? InvalidMark(child: child) : child;
}

/// Brings the first [InvalidMark] under [root] (in reading order) to the
/// middle of its scroll view (`scrollIntoView({block: "center"})`).
void scrollToFirstInvalid(BuildContext root) {
  Element? first;
  void visit(Element e) {
    if (first != null) return;
    if (e.widget is InvalidMark) {
      first = e;
      return;
    }
    e.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  final target = first;
  if (target == null) return;
  Scrollable.ensureVisible(
    target,
    alignment: 0.5,
    duration: DashMotion.of(target, DashMotion.base),
  );
}

/// A red line under a field (`role="alert"`).
class ErrorLine extends StatelessWidget {
  const ErrorLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => InvalidMark(
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: DashType.small.copyWith(color: context.madarColors.errorText),
      ),
    ),
  );
}

/// A quiet hint under a field.
class HintLine extends StatelessWidget {
  const HintLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: DashType.small.copyWith(color: context.madarColors.textSecondary),
  );
}

/// A label, its control, then its red line or its hint (`space-y-1.5`).
class LabelledField extends StatelessWidget {
  const LabelledField({
    required this.label,
    required this.child,
    this.error,
    this.hint,
    this.small = false,
    super.key,
  });

  final String label;
  final Widget child;
  final String? error;
  final String? hint;

  /// A `text-xs` label (inside a choice row).
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: small ? Space.xs : Space.xs + DashMetrics.hair,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: (small ? DashType.smallMedium : DashType.bodyMedium)
                .copyWith(color: c.textPrimary),
          ),
        ),
        if (error != null) InvalidMark(child: child) else child,
        if (error != null)
          ErrorLine(error!)
        else if (hint != null)
          HintLine(hint!),
      ],
    );
  }
}

/// What a number box takes (the web's `type="number"`): digits, a point and
/// a minus; Arabic-Indic digits are read as Western ones.
class NumberText extends TextInputFormatter {
  const NumberText();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final latin = DashTime.latinDigits(newValue.text);
    if (!RegExp(r'^[0-9.\-]*$').hasMatch(latin)) return oldValue;
    if (latin == newValue.text) return newValue;
    return newValue.copyWith(text: latin);
  }
}

/// Two or more fields side by side when there is room (`sm:grid-cols-2`),
/// else stacked.
class FieldGrid extends StatelessWidget {
  const FieldGrid({required this.children, this.gap = Space.md, super.key});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => box.maxWidth >= fieldGridWidth
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: gap,
            children: [
              for (final w in children) Expanded(child: w),
              // A lone field keeps its half (`grid-cols-2`).
              if (children.length == 1) const Spacer(),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: gap,
            children: children,
          ),
  );
}

/// Fields pair up from this column width (the web's `sm`, measured on the
/// column the fields live in).
const double fieldGridWidth = 480;
