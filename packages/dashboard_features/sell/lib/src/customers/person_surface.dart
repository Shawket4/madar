/// The customer sheet's frame: the kit's [DashSurface] (same header, close ×,
/// scrolling body) with a title that carries a pill beside the name and a
/// description in mono, left-to-right (the web's `SheetTitle` with the
/// "Member" pill and the phone in `SheetDescription`). [DashSurface] takes
/// only words for both, so the customer sheet draws its own header here.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

class PersonSurface extends StatelessWidget {
  const PersonSurface({
    required this.title,
    required this.body,
    this.titleTrailing,
    this.description,
    this.onClose,
    super.key,
  });

  final String title;

  /// Beside the title, wrapping under it when the name is long.
  final Widget? titleTrailing;

  /// Under the title (the phone, LTR).
  final Widget? description;
  final Widget body;

  /// Defaults to popping the route.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final mode = DashSurfaceScope.maybeOf(context) ?? DashSurfaceMode.panel;
    final full = mode == DashSurfaceMode.fullScreen;
    final pad = full ? Space.lg : Space.card;
    final close = onClose ?? () => Navigator.of(context).maybePop();
    final closeButton = DashIconButton(
      icon: 'x',
      semanticLabel: t.close,
      onPressed: close,
      iconSize: full ? IconSize.md : IconSize.sm,
      color: full ? null : c.textSecondary,
    );
    final header = Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        full ? Space.xs : pad,
        full ? Space.sm : pad - Space.xs,
        Space.sm,
        Space.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (full)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Space.xs),
              child: closeButton,
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs,
                children: [
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          textDirection: _directionOf(title),
                          style: DashType.sectionTitle.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      ?titleTrailing,
                    ],
                  ),
                  ?description,
                ],
              ),
            ),
          ),
          if (!full) closeButton,
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(pad, Space.sm, pad, pad),
            child: body,
          ),
        ),
      ],
    );
  }
}

/// `dir="auto"`: the direction of the first strong character.
TextDirection? _directionOf(String s) {
  for (final r in s.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) ||
        (r >= 0xFB1D && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF)) {
      return TextDirection.rtl;
    }
    if ((r >= 0x41 && r <= 0x5A) ||
        (r >= 0x61 && r <= 0x7A) ||
        (r >= 0xC0 && r <= 0x24F)) {
      return TextDirection.ltr;
    }
  }
  return null;
}

/// [_directionOf] for the unit's other `dir="auto"` texts.
TextDirection? autoDirection(String s) => _directionOf(s);
