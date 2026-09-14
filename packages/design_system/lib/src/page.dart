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
import 'package:design_system/src/tokens/dimens.dart';
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
    this.automaticBack = true,
    this.drawer,
    this.width,
    this.bodyInset = true,
    super.key,
  });

  /// Puts the page on the SPEC GRID (docs/design/SPEC.md §1–3): the header
  /// starts the title on the gutter (after the back tile on a pushed page),
  /// header and body share the gutter and are capped at this width on the
  /// leading edge, and the body starts [Space.lg] under the header.
  ///
  /// Null keeps the legacy shell (the body is laid as given, the back slot
  /// collapses on tab pages). New and migrated screens pass a width; the
  /// null path is deprecated and goes when the last screen moves.
  final MadarContentWidth? width;

  /// Spec grid only: pad the body with the gutter and cap it at [width].
  /// Off for a body that runs edge to edge (a floor canvas, a split view
  /// that lays its own panes with [MadarContentFrame]).
  final bool bodyInset;

  /// The page's content, laid under the header and given the rest of the
  /// height. Free-form: a page keeps whatever internals it had.
  final Widget body;

  /// Title for the built-in [MadarHeader]. Null builds no header at all,
  /// for a page that draws its own (a split auth layout, a canvas).
  final String? title;

  /// Muted second line under the title.
  final String? subtitle;

  /// What the back tile does. Null with [automaticBack] on shows the tile
  /// whenever the route can pop, and pops it — so a pushed page never has to
  /// remember its own back button, and a tab body never grows one.
  final VoidCallback? onBack;

  /// See [onBack]. Off only for a page that must not be left by back.
  final bool automaticBack;

  /// The key on the one header every titled page carries — what the shell
  /// guard test counts and measures.
  static const headerKey = ValueKey<String>('madar.page.header');

  /// End-aligned header actions.
  final List<Widget> actions;

  /// Full-width row under the title — a filter strip, a summary.
  final Widget? below;

  /// Painted over the page, inside the safe area: a toast host, a scrim.
  final Widget? overlay;

  /// See the class doc. True for a pushed route, false inside the tab shell.
  final bool safeTop;

  /// A navigation drawer for a shell page on a narrow layout. The page
  /// shell owns the only Scaffold, so the drawer is handed to it here.
  final Widget? drawer;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final layout = MadarLayout.of(context);
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final back =
        onBack ??
        (automaticBack && canPop ? () => Navigator.maybePop(context) : null);
    final spec = width;
    final header = title == null
        ? null
        : MadarHeader(
            key: headerKey,
            title: title!,
            subtitle: subtitle,
            onBack: back,
            actions: actions,
            below: below,
            safeTop: safeTop,
          );

    Widget content;
    if (spec == null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              // ONE geometry for every page: the gutter either side and
              // Space.md above, whatever the size class — the Sell tab's.
              padding: EdgeInsetsDirectional.fromSTEB(
                layout.gutter,
                Space.md,
                layout.gutter,
                0,
              ),
              child: header,
            ),
          Expanded(child: body),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: Space.md),
              child: MadarContentFrame(width: spec, child: header),
            ),
          Expanded(
            child: bodyInset
                ? Padding(
                    padding: EdgeInsetsDirectional.only(
                      top: header == null ? 0 : Space.lg,
                    ),
                    child: MadarContentFrame(width: spec, child: body),
                  )
                : body,
          ),
        ],
      );
    }

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
      drawer: drawer,
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
