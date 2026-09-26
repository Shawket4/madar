import 'package:design_system/src/clipped_text.dart';
import 'package:design_system/src/glyphs.dart';
import 'package:design_system/src/responsive.dart';
import 'package:design_system/src/sheet.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A region of a screen where sheets open IN PLACE instead of over the
/// window: the Sell screen's Fast mode, whose menu panel is replaced by
/// an item's choices, a combo, the charge or a note, and back.
///
/// Opt-in and invisible to the sheets themselves. [showMadarSheet] asks for
/// the nearest host. With one, the sheet is pushed as a page on the host's
/// [navigatorKey], a [Navigator] the screen places where the panel is. The
/// caller's future, `Navigator.maybePop(result)` and [MadarSheet.close]
/// behave exactly as they do for a sheet. Without a host nothing changes.
///
/// A sheet opened from OUTSIDE the panel (the cart beside it, the screen)
/// REPLACES whatever the panel shows: tapping another cart line while an
/// item's choices are up swaps them, it never stacks. A sheet opened from a
/// page already in the panel (a combo's "Customise") stacks on it, and
/// closing it returns to that page, as a sheet over a sheet would.
class MadarPanelHost extends InheritedWidget {
  /// Hosts sheets opened from under [child] in [navigatorKey]'s navigator.
  const MadarPanelHost({
    required this.navigatorKey,
    required super.child,
    this.backLabel,
    super.key,
  });

  /// The panel's navigator. Its first route is what the panel shows at rest.
  final GlobalKey<NavigatorState> navigatorKey;

  /// The words on the bar over every page the panel shows ("Back to
  /// menu"): a page here has no scrim to tap and no handle to drag, so the
  /// bar is its one visible way out. Null draws no bar.
  final String? backLabel;

  /// The nearest host above [context], or null. Does not subscribe.
  static MadarPanelHost? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MadarPanelHost>();

  /// Whether [context] sits on a page a host is showing, so a sheet's body
  /// can fill the panel instead of hugging its content.
  static bool isPanelPage(BuildContext context) =>
      ModalRoute.of(context) is MadarPanelRoute;

  /// Open [builder] in the panel; null when the panel's navigator is not
  /// mounted (the caller then falls back to a real sheet).
  Future<T?>? present<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    MadarSheetTone tone = MadarSheetTone.surface,
  }) {
    final nav = navigatorKey.currentState;
    if (nav == null) return null;
    final from = ModalRoute.of(context);
    final nested = from is MadarPanelRoute && from.navigator == nav;
    if (!nested) nav.popUntil((route) => route.isFirst);
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return nav.push(
      MadarPanelRoute<T>(
        builder: builder,
        tone: tone,
        animate: !reduced,
        backLabel: backLabel,
      ),
    );
  }

  @override
  bool updateShouldNotify(MadarPanelHost oldWidget) =>
      navigatorKey != oldWidget.navigatorKey ||
      backLabel != oldWidget.backLabel;
}

/// A sheet shown as a page of a [MadarPanelHost]: it fills the panel on the
/// sheet's own surface, fading and rising a little into place.
class MadarPanelRoute<T> extends PageRoute<T> {
  /// Creates the route. Prefer [showMadarSheet] under a host.
  MadarPanelRoute({
    required this.builder,
    this.tone = MadarSheetTone.surface,
    this.animate = true,
    this.backLabel,
  });

  /// The words on the page's back bar; null draws no bar.
  final String? backLabel;

  /// The sheet's content.
  final WidgetBuilder builder;

  /// The card's fill, as the sheet would paint it.
  final MadarSheetTone tone;

  /// False under reduced motion: the page swaps without a transition.
  final bool animate;

  @override
  Duration get transitionDuration =>
      animate ? MotionSpec.standardDuration : Duration.zero;

  @override
  Duration get reverseTransitionDuration =>
      animate ? const Duration(milliseconds: 160) : Duration.zero;

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final colors = context.madarColors;
    return _PanelPage(
      color: tone == MadarSheetTone.ground ? colors.bg : colors.surface,
      backLabel: backLabel,
      child: Builder(builder: builder),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: MotionSpec.standardCurve,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// The page itself. It is the [DismissibleSurface] [MadarSheet.close] looks
/// for, so a close from the content pops this page and never reaches past
/// it to a sheet or drawer the whole screen might be standing in.
class _PanelPage extends StatefulWidget {
  const _PanelPage({required this.color, required this.child, this.backLabel});

  final Color color;
  final Widget child;
  final String? backLabel;

  @override
  State<_PanelPage> createState() => _PanelPageState();
}

class _PanelPageState extends State<_PanelPage> implements DismissibleSurface {
  @override
  void dismissWith(Object? result) {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(result);
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final label = widget.backLabel;
    // Escape closes the page, as it would close a sheet on a keyboard.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            dismissWith(null),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: widget.color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (label != null) ...[
                Semantics(
                  button: true,
                  label: label,
                  excludeSemantics: true,
                  child: InkWell(
                    key: const ValueKey('panel-back'),
                    onTap: () => dismissWith(null),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: Metrics.buttonSmallHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: Space.md,
                        ),
                        child: Row(
                          spacing: Space.xs,
                          children: [
                            MadarGlyphIcon(
                              MadarGlyph.chevronBack,
                              color: colors.accent,
                            ),
                            Flexible(
                              child: MadarClippedText(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MadarType.title.copyWith(
                                  color: colors.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Divider(height: 1, thickness: 1, color: colors.borderLight),
              ],
              // The keyboard a field in the page raises (a note, the cash
              // amount) lifts the page's foot above it, as it lifts a sheet.
              Expanded(child: MadarKeyboardInset(child: widget.child)),
            ],
          ),
        ),
      ),
    );
  }
}
