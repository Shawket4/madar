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
  const CustomerLinkControl({
    required this.canOpen,
    required this.open,
    this.warm,
  });

  /// Nobody may open anyone (tests, a surface without customers).
  static final CustomerLinkControl none = CustomerLinkControl(
    canOpen: false,
    open: (_) {},
  );

  /// The viewer holds `customers.view`.
  final bool canOpen;
  final void Function(String customerId) open;

  /// Warms what [open] reads, on intent (a pointer resting on the name).
  final void Function(String customerId)? warm;
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
        textDirection: dashTextDirectionOf(name),
        style: base,
      );
    }
    return DashPressable(
      onTap: () => control.open(id),
      onIntent: control.warm == null ? null : () => control.warm!(id),
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
              textDirection: dashTextDirectionOf(name),
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
