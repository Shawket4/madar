import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'buttons.dart';
import 'foundation/l10n.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';

/// How a [DashSurface] is being shown.
enum DashSurfaceMode {
  /// A centred dialog over a scrim (wide screens).
  dialog,

  /// A panel on the end side (wide screens).
  panel,

  /// The whole window (phones).
  fullScreen,
}

/// Tells a surface's content how it is being shown.
class DashSurfaceScope extends InheritedWidget {
  const DashSurfaceScope({required this.mode, required super.child, super.key});
  final DashSurfaceMode mode;

  static DashSurfaceMode? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashSurfaceScope>()?.mode;

  @override
  bool updateShouldNotify(DashSurfaceScope oldWidget) => mode != oldWidget.mode;
}

/// The content of a dialog, a side panel or a phone sheet: a header (title,
/// description, close ×), a scrolling body, a footer of actions. It draws
/// itself for the [DashSurfaceScope] it is shown in — the same widget is a
/// centred dialog on a desktop and a full-screen page on a phone.
class DashSurface extends StatelessWidget {
  const DashSurface({
    required this.title,
    required this.body,
    this.description,
    this.actions = const [],
    this.headerTrailing,
    this.titleTrailing,
    this.footerLeading,
    this.wrapActions = false,
    this.onClose,
    this.scrollable = true,
    this.bodyPadding,
    this.showClose = true,
    super.key,
  });

  final String title;
  final String? description;
  final Widget body;

  /// Footer buttons, in reading order (Cancel, then the primary). On a phone
  /// they stack full width with the primary on top.
  final List<Widget> actions;

  /// Extra header controls beside the close ×.
  final Widget? headerTrailing;

  /// Right after the title on its line (a badge, a status pill).
  final Widget? titleTrailing;

  /// The footer's start, across from [actions] (the web's
  /// `sm:justify-between`: "Download again" · "Done", or a note). Under the
  /// stacked actions on a phone.
  final Widget? footerLeading;

  /// On a phone, keep [actions] in one wrapping row (a sheet's
  /// `flex-row flex-wrap` footer) instead of stacking them full width.
  final bool wrapActions;

  /// Defaults to popping the route.
  final VoidCallback? onClose;
  final bool scrollable;
  final EdgeInsetsGeometry? bodyPadding;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final mode = DashSurfaceScope.maybeOf(context) ?? DashSurfaceMode.dialog;
    final close = onClose ?? () => Navigator.of(context).maybePop();
    final full = mode == DashSurfaceMode.fullScreen;
    // A dialog on a phone reads as the web's there: the title centred and
    // the buttons stacked full width, the main one on top.
    final phoneDialog =
        mode == DashSurfaceMode.dialog && DashBreakpoints.isPhone(context);
    final pad = mode == DashSurfaceMode.dialog
        ? Space.xl
        : (full ? Space.lg : Space.card);

    Widget titleLine = Semantics(
      header: true,
      child: Text(
        title,
        textAlign: phoneDialog ? TextAlign.center : null,
        style:
            (mode == DashSurfaceMode.panel
                    ? DashType.sectionTitle
                    : DashType.paneTitle)
                .copyWith(color: c.textPrimary),
      ),
    );
    if (titleTrailing != null) {
      titleLine = Row(
        spacing: Space.sm,
        children: [
          Flexible(child: titleLine),
          titleTrailing!,
        ],
      );
    }

    final header = Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        pad,
        full ? Space.sm : pad - Space.xs,
        Space.sm,
        Space.sm,
      ),
      child: Row(
        crossAxisAlignment: full
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (full && showClose)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Space.xs),
              child: DashIconButton(
                icon: 'x',
                semanticLabel: t.close,
                onPressed: close,
                iconSize: IconSize.md,
              ),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: full ? 0 : Space.xs),
              child: Column(
                crossAxisAlignment: phoneDialog
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs,
                children: [
                  titleLine,
                  if (description != null)
                    Text(
                      description!,
                      textAlign: phoneDialog ? TextAlign.center : null,
                      style: DashType.body.copyWith(color: c.textSecondary),
                    ),
                ],
              ),
            ),
          ),
          ?headerTrailing,
          if (!full && showClose)
            DashIconButton(
              icon: 'x',
              semanticLabel: t.close,
              onPressed: close,
              color: c.textSecondary,
            ),
        ],
      ),
    );

    final bodyInsets =
        bodyPadding ?? EdgeInsetsDirectional.fromSTEB(pad, Space.sm, pad, pad);
    final content = scrollable
        ? SingleChildScrollView(padding: bodyInsets, child: body)
        : Padding(padding: bodyInsets, child: body);

    Widget? footer;
    if (actions.isNotEmpty || footerLeading != null) {
      final row = Wrap(
        alignment: WrapAlignment.end,
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: actions,
      );
      footer = Container(
        padding: EdgeInsetsDirectional.fromSTEB(
          pad,
          Space.md,
          pad,
          full ? Space.md : pad,
        ),
        decoration: mode == DashSurfaceMode.dialog
            ? null
            : BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
        child: (full || phoneDialog) && !wrapActions
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.sm,
                children: [for (final a in actions.reversed) a, ?footerLeading],
              )
            : footerLeading == null
            ? row
            : Row(
                spacing: Space.sm,
                children: [
                  Flexible(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: footerLeading,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.sm,
                    children: actions,
                  ),
                ],
              ),
      );
    }

    return Column(
      mainAxisSize: mode == DashSurfaceMode.dialog
          ? MainAxisSize.min
          : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (mode == DashSurfaceMode.dialog)
          Flexible(child: content)
        else
          Expanded(child: content),
        if (footer != null) full ? SafeArea(top: false, child: footer) : footer,
      ],
    );
  }
}

/// The dialog entry point by its web name: `DashDialog.show(context, ...)`.
abstract final class DashDialog {
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    double width = DashMetrics.dialog,
  }) => showDashDialog<T>(context, builder: builder, width: width);
}

/// The end-side panel by its name: `DashSidePanel.show(context, ...)`.
abstract final class DashSidePanel {
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    double width = DashMetrics.sidePanel,
  }) => showDashSidePanel<T>(context, builder: builder, width: width);
}

/// The form dialog by its name: `DashSheet.show(context, ...)`.
abstract final class DashSheet {
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) => showDashSheet<T>(context, builder: builder);
}

/// Shows [builder]'s [DashSurface] as a centred dialog (the web's `Dialog`),
/// on a phone too: a card 16 px in from the screen's edges, lifted over the
/// keyboard, as the web shows it there.
Future<T?> showDashDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = DashMetrics.dialog,
  bool barrierDismissible = true,
}) {
  final c = context.madarColors;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: barrierDismissible,
    barrierLabel: context.dashStrings.close,
    barrierColor: c.scrim,
    transitionDuration: DashMotion.of(context, DashMotion.base),
    pageBuilder: (ctx, a, b) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(
            Space.lg,
          ).add(EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: ctx.madarColors.bg,
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: Border.all(color: ctx.madarColors.hairline),
                  boxShadow: DashShadows.modal(ctx),
                ),
                child: DashSurfaceScope(
                  mode: DashSurfaceMode.dialog,
                  child: Builder(builder: builder),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: DashMotion.ease);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.95, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Shows [builder]'s [DashSurface] as a panel on the end side (the web's
/// `Sheet side="right"` — record detail, edit forms), on a phone too, as the
/// web slides it in from the side there.
Future<T?> showDashSidePanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = DashMetrics.sidePanel,
  bool barrierDismissible = true,
}) {
  final c = context.madarColors;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: barrierDismissible,
    barrierLabel: context.dashStrings.close,
    barrierColor: c.scrim,
    transitionDuration: DashMotion.of(context, DashMotion.slow),
    pageBuilder: (ctx, a, b) {
      final screen = MediaQuery.sizeOf(ctx).width;
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: width.clamp(0, screen * 0.9),
            height: double.infinity,
            decoration: BoxDecoration(
              color: ctx.madarColors.bg,
              border: BorderDirectional(
                start: BorderSide(color: ctx.madarColors.hairline),
              ),
              boxShadow: DashShadows.modal(ctx),
            ),
            child: SafeArea(
              child: DashSurfaceScope(
                mode: DashSurfaceMode.panel,
                child: Builder(builder: builder),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final rtl = Directionality.of(ctx) == TextDirection.rtl;
      final curved = CurvedAnimation(parent: anim, curve: DashMotion.ease);
      return SlideTransition(
        position: Tween(
          begin: Offset(rtl ? -1 : 1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// A form as a centred dialog (the phone's too, as on the web).
Future<T?> showDashSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = DashMetrics.dialog,
}) => showDashDialog<T>(context, builder: builder, width: width);

/// The web's `useConfirm()`: name what is lost in [title] ("Delete the
/// Zamalek branch?"), the consequence in [description]. Resolves true on
/// Confirm, false on Cancel, Escape or a tap outside.
Future<bool> showDashConfirm(
  BuildContext context, {
  required String title,
  String? description,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
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
          padding: const EdgeInsets.all(
            Space.lg,
          ).add(EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: DashMetrics.dialog),
            child: Material(
              type: MaterialType.transparency,
              child: DashConfirmDialog(
                title: title,
                description: description,
                confirmLabel: confirmLabel,
                cancelLabel: cancelLabel,
                destructive: destructive,
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: DashMotion.ease);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.95, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
  return r ?? false;
}

/// The confirmation card itself (the web's `AlertDialog`): a danger disc
/// beside the title when [destructive], Cancel and Confirm at the foot.
class DashConfirmDialog extends StatelessWidget {
  /// [showDashConfirm] by the widget's name.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? description,
    String? confirmLabel,
    String? cancelLabel,
    bool destructive = false,
  }) => showDashConfirm(
    context,
    title: title,
    description: description,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    destructive: destructive,
  );

  const DashConfirmDialog({
    required this.title,
    this.description,
    this.confirmLabel,
    this.cancelLabel,
    this.destructive = false,
    this.onConfirm,
    this.onCancel,
    super.key,
  });

  final String title;
  final String? description;
  final String? confirmLabel;
  final String? cancelLabel;
  final bool destructive;

  /// Default: pop `true`.
  final VoidCallback? onConfirm;

  /// Default: pop `false`.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final disc = destructive
        ? Container(
            width: DashMetrics.target,
            height: DashMetrics.target,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DashTone.danger.wash(c),
              shape: BoxShape.circle,
            ),
            child: DashIcon(
              'alert-triangle',
              size: IconSize.lg,
              color: DashTone.danger.foreground(c),
            ),
          )
        : null;
    final words = Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: wide ? TextAlign.start : TextAlign.center,
            style: DashType.paneTitle.copyWith(color: c.textPrimary),
          ),
        ),
        if (description != null)
          Text(
            description!,
            textAlign: wide ? TextAlign.start : TextAlign.center,
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
      ],
    );
    final cancel = DashButton(
      label: cancelLabel ?? t.cancel,
      variant: DashButtonVariant.outline,
      expand: !wide,
      onPressed: onCancel ?? () => Navigator.of(context).pop(false),
    );
    final confirm = DashButton(
      label: confirmLabel ?? t.confirm,
      variant: destructive
          ? DashButtonVariant.destructive
          : DashButtonVariant.primary,
      expand: !wide,
      onPressed: onConfirm ?? () => Navigator.of(context).pop(true),
    );
    return Container(
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
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.lg,
              children: [
                ?disc,
                Expanded(child: words),
              ],
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.md,
              children: [?disc, words],
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
    );
  }
}
