/// A customer's name wherever staff meet it — an order row, the order sheet,
/// a floor sitting, a booking (the web's `features/customers/customer-link.tsx`,
/// SELL-ALL-015).
///
/// It opens the customer when there is one to open (`customerId`) and the
/// viewer may (`control.canOpen`, i.e. `customers.view`); otherwise it is
/// plain text in its own direction. The name shown is the row's SNAPSHOT,
/// never today's customer name. A tap on the link never reaches the row
/// underneath (rows are often tappable themselves).
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

/// Whether the viewer may open a customer at all, and how (`CustomerLinkControl`).
/// Build one per surface with `customerSheetControl` (shared/sheets.dart).
@immutable
class CustomerLinkControl {
  const CustomerLinkControl({required this.canOpen, required this.open});

  /// Nobody may open anyone (tests, a surface without customers).
  static final CustomerLinkControl none = CustomerLinkControl(
    canOpen: false,
    open: (_) {},
  );

  /// The viewer holds `customers.view`.
  final bool canOpen;
  final void Function(String customerId) open;
}

class CustomerLink extends StatelessWidget {
  const CustomerLink({
    required this.name,
    required this.control,
    this.customerId,
    this.style,
    this.maxLines = 1,
    super.key,
  });

  final String name;
  final String? customerId;
  final CustomerLinkControl control;

  /// The plain text's style (the link keeps its size, in the link colour).
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final base = style ?? DashType.body.copyWith(color: c.textPrimary);
    final id = customerId;
    if (id == null || id.isEmpty || !control.canOpen) {
      return MadarClippedText(
        name,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textDirection: _directionOf(name),
        style: base,
      );
    }
    return DashPressable(
      onTap: () => control.open(id),
      semanticLabel: name,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) {
        final fg = dashButtonColors(
          context,
          DashButtonVariant.link,
          s,
          enabled: true,
        ).fg;
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DashMetrics.target),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: MadarClippedText(
              name,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              textDirection: _directionOf(name),
              style: base.copyWith(
                color: fg,
                decoration: s.highlighted ? TextDecoration.underline : null,
                decorationColor: fg,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `dir="auto"`: the direction of the first strong character.
TextDirection? _directionOf(String s) {
  for (final r in s.runes) {
    if (_isRtl(r)) return TextDirection.rtl;
    if (_isLtrLetter(r)) return TextDirection.ltr;
  }
  return null;
}

bool _isRtl(int r) =>
    (r >= 0x0590 && r <= 0x08FF) ||
    (r >= 0xFB1D && r <= 0xFDFF) ||
    (r >= 0xFE70 && r <= 0xFEFF);

bool _isLtrLetter(int r) =>
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0xC0 && r <= 0x24F);
