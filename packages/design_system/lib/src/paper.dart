/// The thermal-paper palette — the one place in the app that is deliberately
/// NOT theme-aware.
///
/// A receipt and a Z-report are previews of something a printer will put on a
/// roll of white paper in dark ink. Tinting them with the app's dark theme
/// would show the teller a document that does not exist: they would check a
/// total against a black card and then hand a customer a white slip. So these
/// are fixed values, and the natives hardcode the same ones in both themes.
///
/// They lived twice — once in the checkout's receipt preview and once in the
/// shift's Z-report — which is exactly how two documents that must look
/// identical start to differ.
library;

import 'package:flutter/painting.dart';

/// Ink on paper. Fixed in both themes, on purpose.
abstract final class Paper {
  /// The roll.
  static const Color paper = Color(0xFFFFFFFF);

  /// Printed text.
  static const Color ink = Color(0xFF1A1A1A);

  /// Secondary text — a line's unit price, a footer.
  static const Color faint = Color(0xFF6B6B6B);

  /// A separator rule between blocks.
  static const Color rule = Color(0xFFCCCCCC);

  /// The unfilled part of a bar (a Z-report's payment split).
  static const Color track = Color(0xFFEEEEEE);

  /// Over — a surplus in the drawer.
  static const Color success = Color(0xFF2E7D32);

  /// Short — a shortfall, and the VOIDED stamp.
  static const Color danger = Color(0xFFB71C1C);

  /// Needs attention without being wrong.
  static const Color warning = Color(0xFFB26A00);
}
