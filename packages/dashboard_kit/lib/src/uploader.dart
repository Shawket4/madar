import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';

import 'buttons.dart';
import 'foundation/l10n.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';

/// A file the person picked: its bytes, its name, its type.
@immutable
class DashPickedFile {
  const DashPickedFile({
    required this.bytes,
    required this.name,
    required this.mimeType,
  });
  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// The uniform image upload (the web's `ImageUploader`): an empty dashed
/// box to choose a picture, or the picture with Replace and Remove. The
/// kit never touches files: [onPick] asks the app's file gateway for one,
/// [onUpload] hands its bytes to the API and answers the new URL (null
/// while the server is still converting it). A file that is not an image or
/// is too large is refused in words, under the box.
class DashImageUploader extends StatefulWidget {
  const DashImageUploader({
    required this.value,
    required this.onPick,
    required this.onUpload,
    this.onRemove,
    this.hint,
    this.maxBytes = 5 * 1024 * 1024,
    this.square = true,
    this.enabled = true,
    this.processing = false,
    this.imageBuilder,
    this.semanticLabel,
    super.key,
  });

  /// The current image URL.
  final String? value;
  final Future<DashPickedFile?> Function() onPick;

  /// Uploads; answers the new URL, or null while it is processed. Throws
  /// with words on failure.
  final Future<String?> Function(DashPickedFile file) onUpload;
  final Future<void> Function()? onRemove;
  final String? hint;
  final int maxBytes;
  final bool square;
  final bool enabled;

  /// The server is converting the upload (an asset job).
  final bool processing;

  /// Draws an image URL (default: a network image).
  final Widget Function(BuildContext context, String url)? imageBuilder;
  final String? semanticLabel;

  @override
  State<DashImageUploader> createState() => _DashImageUploaderState();
}

class _DashImageUploaderState extends State<DashImageUploader> {
  bool _uploading = false;
  bool _removing = false;
  String? _error;
  String? _justUploaded;
  Uint8List? _preview;
  bool _hovered = false;

  @override
  void didUpdateWidget(DashImageUploader old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _justUploaded = null;
      _preview = null;
    }
  }

  Future<void> _choose() async {
    final t = context.dashStrings;
    final file = await widget.onPick();
    if (file == null || !mounted) return;
    setState(() => _error = null);
    if (!file.mimeType.startsWith('image/')) {
      setState(() => _error = t.notAnImage);
      return;
    }
    if (file.bytes.length > widget.maxBytes) {
      setState(() => _error = t.imageTooLarge);
      return;
    }
    setState(() => _uploading = true);
    try {
      final url = await widget.onUpload(file);
      if (!mounted) return;
      setState(() {
        _justUploaded = url;
        _preview = url == null ? file.bytes : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _remove() async {
    if (widget.onRemove == null) return;
    setState(() {
      _removing = true;
      _error = null;
    });
    try {
      await widget.onRemove!();
      if (mounted) {
        setState(() {
          _justUploaded = null;
          _preview = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final shown = _justUploaded ?? widget.value;
    final hasImage = (shown != null && shown.isNotEmpty) || _preview != null;
    final mouse = RendererBinding.instance.mouseTracker.mouseIsConnected;
    final showControls = !mouse || _hovered;

    Widget inner;
    if (widget.processing) {
      inner = Semantics(
        liveRegion: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: Space.sm,
          children: [
            SizedBox.square(
              dimension: IconSize.lg,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.textSecondary,
              ),
            ),
            Text(
              t.processing,
              style: DashType.smallMedium.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      );
    } else if (hasImage) {
      inner = Stack(
        fit: StackFit.expand,
        children: [
          if (_preview != null)
            Image.memory(_preview!, fit: BoxFit.cover)
          else
            widget.imageBuilder?.call(context, shown!) ??
                Image.network(
                  shown!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, e, s) => Center(
                    child: DashIcon(
                      'image',
                      size: IconSize.lg,
                      color: c.textMuted,
                    ),
                  ),
                ),
          if (widget.enabled)
            AnimatedOpacity(
              opacity: showControls ? 1 : 0,
              duration: DashMotion.of(context, DashMotion.fast),
              child: ColoredBox(
                color: c.textPrimary.withValues(alpha: 0.4),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs,
                    children: [
                      DashIconButton(
                        icon: 'upload',
                        semanticLabel: t.uploadReplace,
                        variant: DashButtonVariant.secondary,
                        loading: _uploading,
                        onPressed: _choose,
                      ),
                      if (widget.onRemove != null)
                        DashIconButton(
                          icon: 'x',
                          semanticLabel: t.uploadRemove,
                          variant: DashButtonVariant.destructive,
                          loading: _removing,
                          onPressed: _remove,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      inner = DashPressable(
        onTap: widget.enabled && !_uploading ? _choose : null,
        enabled: widget.enabled && !_uploading,
        semanticLabel: widget.semanticLabel ?? t.uploadChoose,
        excludeChildSemantics: true,
        pressScale: false,
        builder: (context, s) => Container(
          color: s.hovered ? c.muted.withValues(alpha: 0.3) : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: Space.sm,
            children: [
              if (_uploading)
                SizedBox.square(
                  dimension: IconSize.lg,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.textSecondary,
                  ),
                )
              else
                DashIcon(
                  'image',
                  size: IconSize.lg,
                  color: s.hovered ? c.textPrimary : c.textSecondary,
                ),
              Text(
                _uploading ? t.uploading : t.uploadChoose,
                style: DashType.smallMedium.copyWith(
                  color: s.hovered ? c.textPrimary : c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final box = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: AspectRatio(
        aspectRatio: widget.square ? 1 : 16 / 9,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.5,
            child: CustomPaint(
              foregroundPainter: hasImage && !widget.processing
                  ? null
                  : _DashedBorder(color: c.input, radius: Radii.control),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.control),
                child: inner,
              ),
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        box,
        if (widget.hint != null && _error == null)
          Text(
            widget.hint!,
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: DashType.small.copyWith(color: c.errorText),
            ),
          ),
      ],
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(1),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}
