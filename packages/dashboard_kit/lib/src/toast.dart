import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'foundation/l10n.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';

/// What a toast says it is.
enum DashToastKind { success, error, warning, info, loading, message }

/// A shown toast, to dismiss or replace (a loading toast that finishes).
class DashToastHandle {
  DashToastHandle._(this._entry, this._layer);
  final _ToastEntry _entry;
  final _ToastLayer _layer;

  void dismiss() => _layer.remove(_entry);

  /// Turn this toast into another (loading → success).
  void update(DashToastKind kind, String message, {String? description}) {
    _entry
      ..kind = kind
      ..message = message
      ..description = description;
    _layer.touch(_entry);
  }
}

/// The toasts (the web's sonner, `position="top-center" richColors
/// closeButton`): a stack at the top centre of the window, tinted by kind,
/// gone after four seconds (a loading toast stays until updated).
///
/// ```dart
/// DashToast.success(context, t('orders.voided'));
/// DashToast.error(context, e.message);
/// ```
abstract final class DashToast {
  static const Duration duration = Duration(seconds: 4);

  static DashToastHandle show(
    BuildContext context,
    String message, {
    DashToastKind kind = DashToastKind.message,
    String? description,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final layer = _ToastLayer.of(overlay);
    final entry = _ToastEntry(
      kind: kind,
      message: message,
      description: description,
      actionLabel: actionLabel,
      onAction: onAction,
    );
    layer.add(
      entry,
      kind == DashToastKind.loading ? null : (duration ?? DashToast.duration),
    );
    return DashToastHandle._(entry, layer);
  }

  static DashToastHandle success(
    BuildContext context,
    String message, {
    String? description,
  }) => show(
    context,
    message,
    kind: DashToastKind.success,
    description: description,
  );

  static DashToastHandle error(
    BuildContext context,
    String message, {
    String? description,
  }) => show(
    context,
    message,
    kind: DashToastKind.error,
    description: description,
  );

  static DashToastHandle warning(
    BuildContext context,
    String message, {
    String? description,
  }) => show(
    context,
    message,
    kind: DashToastKind.warning,
    description: description,
  );

  static DashToastHandle info(
    BuildContext context,
    String message, {
    String? description,
  }) => show(
    context,
    message,
    kind: DashToastKind.info,
    description: description,
  );

  static DashToastHandle loading(BuildContext context, String message) =>
      show(context, message, kind: DashToastKind.loading);

  /// Remove every toast (tests, sign-out).
  static void clear(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _ToastLayer._layers[overlay]?.clear();
  }
}

class _ToastEntry {
  _ToastEntry({
    required this.kind,
    required this.message,
    this.description,
    this.actionLabel,
    this.onAction,
  });
  DashToastKind kind;
  String message;
  String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  Timer? timer;
}

class _ToastLayer {
  _ToastLayer(this.overlay);
  final OverlayState overlay;
  final List<_ToastEntry> _items = [];
  OverlayEntry? _entry;
  bool _inserted = false;
  final _version = ValueNotifier<int>(0);

  static final Map<OverlayState, _ToastLayer> _layers = {};

  static _ToastLayer of(OverlayState overlay) =>
      _layers.putIfAbsent(overlay, () => _ToastLayer(overlay));

  void add(_ToastEntry e, Duration? life) {
    _items.insert(0, e);
    if (_items.length > 3) remove(_items.last);
    if (life != null) e.timer = Timer(life, () => remove(e));
    _entry ??= OverlayEntry(builder: (_) => _ToastStack(layer: this));
    if (!_inserted) {
      overlay.insert(_entry!);
      _inserted = true;
    }
    _version.value++;
  }

  void touch(_ToastEntry e) {
    e.timer?.cancel();
    if (e.kind != DashToastKind.loading) {
      e.timer = Timer(DashToast.duration, () => remove(e));
    }
    _version.value++;
  }

  void remove(_ToastEntry e) {
    e.timer?.cancel();
    _items.remove(e);
    _version.value++;
    if (_items.isEmpty) {
      if (_inserted) _entry?.remove();
      _inserted = false;
      _entry = null;
      _layers.remove(overlay);
    }
  }

  void clear() {
    for (final e in [..._items]) {
      remove(e);
    }
  }
}

class _ToastStack extends StatelessWidget {
  const _ToastStack({required this.layer});
  final _ToastLayer layer;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: layer._version,
      builder: (context, _, _) => SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.sm,
                children: [
                  for (final e in layer._items)
                    _ToastCard(
                      key: ObjectKey(e),
                      entry: e,
                      onClose: () => layer.remove(e),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.entry, required this.onClose, super.key});
  final _ToastEntry entry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final tone = switch (entry.kind) {
      DashToastKind.success => DashTone.success,
      DashToastKind.error => DashTone.danger,
      DashToastKind.warning => DashTone.warning,
      DashToastKind.info => DashTone.info,
      _ => null,
    };
    final fg = tone?.foreground(c) ?? c.textPrimary;
    final icon = switch (entry.kind) {
      DashToastKind.success => 'circle-check',
      DashToastKind.error => 'octagon-x',
      DashToastKind.warning => 'triangle-alert',
      DashToastKind.info => 'info',
      _ => null,
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: DashMotion.of(context, DashMotion.base),
      curve: DashMotion.ease,
      builder: (context, v, child) => Opacity(
        opacity: v,
        // Announced the moment it appears, not once it has faded in.
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * -Space.sm),
          child: child,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.lg,
              Space.md,
              Space.xs,
              Space.md,
            ),
            decoration: BoxDecoration(
              color: tone == null
                  ? c.card
                  : Color.alphaBlend(
                      tone.wash(c).withValues(alpha: 0.85),
                      c.card,
                    ),
              borderRadius: BorderRadius.circular(Radii.control),
              border: Border.all(
                color: tone == null
                    ? c.hairline
                    : tone.solid(c).withValues(alpha: 0.3),
              ),
              boxShadow: DashShadows.popover(context),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.sm,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: DashMetrics.hair),
                  child: entry.kind == DashToastKind.loading
                      ? SizedBox.square(
                          dimension: IconSize.sm,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.textSecondary,
                          ),
                        )
                      : icon == null
                      ? const SizedBox.shrink()
                      : DashIcon(icon, size: IconSize.sm, color: fg),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: DashMetrics.hair / 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: DashMetrics.hair,
                      children: [
                        Text(
                          entry.message,
                          style: DashType.bodyMedium.copyWith(color: fg),
                        ),
                        if (entry.description != null)
                          Text(
                            entry.description!,
                            style: DashType.small.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        if (entry.actionLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: DashPressable(
                              onTap: () {
                                entry.onAction?.call();
                                onClose();
                              },
                              semanticLabel: entry.actionLabel,
                              excludeChildSemantics: true,
                              builder: (context, s) => Text(
                                entry.actionLabel!,
                                style: DashType.smallStrong.copyWith(
                                  color: c.textPrimary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                DashPressable(
                  onTap: onClose,
                  semanticLabel: t.close,
                  excludeChildSemantics: true,
                  builder: (context, s) => SizedBox.square(
                    dimension: Space.xl,
                    child: Center(
                      child: DashIcon(
                        'x',
                        size: IconSize.xs,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
