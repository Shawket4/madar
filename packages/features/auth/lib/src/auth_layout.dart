import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/brand_panel.dart';
import 'package:flutter/material.dart';

/// Form column width cap (natives: `widthIn(max = 400.dp)`).
const double _formMaxWidth = 400;

/// Form column vertical inset (natives: 48.dp).
const double _formVPad = 48;

/// Even brand/form split — the station picker's wide layout (natives:
/// `weight(1f)` each side; login/setup use [Responsive.brandPanelRatio]).
const double evenBrandRatio = 0.5;

/// The shared auth-screen scaffold: on wide containers a brand panel + form
/// split at [brandRatio]; stacked (centered form with logo) on narrow ones.
/// Mirror of the natives' LoginScreen.kt / StationPickerScreen.kt layout.
class AuthSplitScaffold extends StatelessWidget {
  /// Creates the split scaffold.
  const AuthSplitScaffold({
    required this.formBuilder,
    this.brandRatio = Responsive.brandPanelRatio,
    this.formMaxWidth = _formMaxWidth,
    super.key,
  });

  /// Builds the form column; `showLogo` is true on the stacked layout, where
  /// the brand panel (and its lockup) is hidden.
  final Widget Function(BuildContext context, {required bool showLogo})
  formBuilder;

  /// Brand panel share of the wide split (0–1).
  final double brandRatio;

  /// Width cap for the form column.
  final double formMaxWidth;

  Widget _formColumn(BuildContext context, {required bool showLogo}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.xxl,
          vertical: _formVPad,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: formMaxWidth),
          child: formBuilder(context, showLogo: showLogo),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brandFlex = (brandRatio * 100).round();

    // No header here — the brand panel IS this page's header — so the page
    // shell's SafeArea is what keeps the stacked form off the status bar.
    // It had none at all before, which is why sign-in and device setup
    // started under the clock.
    return MadarPageScaffold(
      body: ResponsiveBuilder(
        builder: (context, info) {
          if (!info.isWide) {
            return _formColumn(context, showLogo: true);
          }
          return Row(
            children: [
              // The brand panel is full-bleed art — it reaches the top edge
              // on purpose, so it opts out of the inset the form keeps.
              Expanded(
                flex: brandFlex,
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: const BrandPanel(),
                ),
              ),
              Expanded(
                flex: 100 - brandFlex,
                child: _formColumn(context, showLogo: false),
              ),
            ],
          );
        },
      ),
    );
  }
}
