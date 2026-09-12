/// THE page shell. One Scaffold, one safe-area decision, one header slot.
///
/// Every screen in this app used to build its own `Scaffold`, make its own
/// call about insets, and pad its own header — 25 of them, and six had no
/// `SafeArea` at all, which is why the sign-in, device setup, station picker
/// and open-shift screens sat under the status bar. That was not six bugs.
/// It was one missing widget, reported six times.
///
/// The inset rule is the whole reason this exists, so it is stated once here
/// rather than guessed at 25 call sites:
///
/// * A page pushed on its own — sign-in, a bill, the sync centre — is the
///   topmost thing on the display and MUST pad the status bar itself.
/// * A page inside the tab shell — Sell, Floor, Queue, Till — has the
///   shell's top bar above it, which already paid that inset. Padding it
///   again leaves a visible band.
///
/// `safeTop` defaults to **true** because the two mistakes are not equal: a
/// page that pads when it needn't is loose, a page that doesn't pad when it
/// must is unreadable under the clock.
library;

import 'package:design_system/src/header.dart';
import 'package:design_system/src/responsive.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:flutter/material.dart';

class MadarPageScaffold extends StatelessWidget {
  /// Creates a page.
  const MadarPageScaffold({
    required this.body,
    this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.below,
    this.overlay,
    this.safeTop = true,
    this.gutter = true,
    super.key,
  });

  /// The page's content, laid under the header and given the rest of the
  /// height. Free-form: a page keeps whatever internals it had.
  final Widget body;

  /// Title for the built-in [MadarHeader]. Null builds no header at all,
  /// for a page that draws its own (a split auth layout, a canvas).
  final String? title;

  /// Muted second line under the title.
  final String? subtitle;

  /// Shows the back tile when set.
  final VoidCallback? onBack;

  /// End-aligned header actions.
  final List<Widget> actions;

  /// Full-width row under the title — a filter strip, a summary.
  final Widget? below;

  /// Painted over the page, inside the safe area: a toast host, a scrim.
  final Widget? overlay;

  /// See the class doc. True for a pushed route, false inside the tab shell.
  final bool safeTop;

  /// Applies the layout gutter either side of the header. Off for a page
  /// whose header has to reach the edges.
  final bool gutter;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final layout = MadarLayout.of(context);
    final header = title == null
        ? null
        : MadarHeader(
            title: title!,
            subtitle: subtitle,
            onBack: onBack,
            actions: actions,
            below: below,
            safeTop: safeTop,
          );

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: gutter ? layout.gutter : 0,
            ),
            child: header,
          ),
        Expanded(child: body),
      ],
    );

    // The header pays the TOP inset itself (it has to: the back tile is the
    // thing that would otherwise sit under the clock). A page with no header
    // has nothing to pay it, so the SafeArea does. Bottom is never padded
    // here — a page that reaches the home indicator usually wants to, and
    // the ones that don't say so in their own body.
    if (safeTop && header == null) {
      content = SafeArea(bottom: false, child: content);
    }

    return Scaffold(
      backgroundColor: colors.bg,
      body: overlay == null
          ? content
          : Stack(
              children: [
                content,
                SafeArea(child: overlay!),
              ],
            ),
    );
  }
}
