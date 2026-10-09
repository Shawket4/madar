/// The floor itself: one canvas, always live — the web's `floor-canvas.tsx`
/// and the camera of `use-floor-viewport.ts` (SELL-FLR-024 – 034).
///
/// An unbounded plane in canvas units, drawn in PHYSICAL coordinates: never
/// mirrored in Arabic (every table box is a `Positioned`, never a
/// `PositionedDirectional`). Locked, a drag anywhere pans; editing, a table
/// is selected, dragged, resized and rotated, and a drag on empty floor draws
/// a marquee. Pointer input is read raw (a [Listener]), as the web reads
/// pointer events, and the canvas claims every touch so a page that scrolls
/// around it on a phone never steals a drag.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart' show FloorTable;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'floor_util.dart';
import 'table_glyph.dart';

/// The camera over the plane: where the window is, and how close.
class FloorViewport extends ChangeNotifier {
  FloorView view = const FloorView(x: 0, y: 0, zoom: 1);

  /// The canvas in pixels (the web starts at 900 × 600 until measured).
  Size size = const Size(900, 600);
  bool _measured = false;
  FloorRect? _fitPending;

  /// Called by the canvas with its size, during its build.
  void layout(Size s) {
    if (s.width <= 0 || s.height <= 0 || !s.isFinite) return;
    final first = !_measured;
    _measured = true;
    size = s;
    final fit = _fitPending;
    if (first && fit != null) view = fitView(fit, s.width, s.height);
    _fitPending = null;
  }

  /// Frames [items] (`fitTo`); an empty set frames [kEmptyView].
  void fitTo(Iterable<GeoItem> items, {bool notify = true}) {
    final bounds = boundsOf(items, kEmptyView);
    view = fitView(bounds, size.width, size.height);
    if (!_measured) _fitPending = bounds;
    if (notify) notifyListeners();
  }

  /// Zooms by [factor] about [anchor] (a world point; the view's centre by
  /// default, so buttons and keys hold the middle).
  void zoomBy(double factor, [Offset? anchor]) {
    final a =
        anchor ??
        Offset(
          view.x + size.width / (2 * view.zoom),
          view.y + size.height / (2 * view.zoom),
        );
    final next = zoomAt(view, factor, a.dx, a.dy);
    if (next == view) return;
    view = next;
    notifyListeners();
  }

  /// Puts the window at [v].
  void jumpTo(FloorView v) {
    view = v;
    notifyListeners();
  }

  /// Moves the window by a screen-pixel delta.
  void panBy(double dx, double dy) {
    if (dx == 0 && dy == 0) return;
    view = view.copyWith(
      x: view.x + dx / view.zoom,
      y: view.y + dy / view.zoom,
    );
    notifyListeners();
  }

  /// A canvas-local pixel → a world point.
  Offset toWorld(Offset local) =>
      Offset(view.x + local.dx / view.zoom, view.y + local.dy / view.zoom);

  /// A world point → a canvas-local pixel.
  Offset toScreen(double x, double y) =>
      Offset((x - view.x) * view.zoom, (y - view.y) * view.zoom);
}

/// Today's booking on a table: the chip text and whether its hold began.
typedef FloorReservation = ({String label, bool held});

class FloorCanvas extends StatefulWidget {
  const FloorCanvas({
    required this.tables,
    required this.geoOf,
    required this.occupants,
    required this.reservations,
    required this.selection,
    required this.onSelectionChange,
    required this.editable,
    required this.viewport,
    required this.beginGesture,
    required this.onGeoChange,
    super.key,
  });

  /// The visible (active, in-area) tables, in draw order.
  final List<FloorTable> tables;
  final GeoItem Function(FloorTable) geoOf;
  final Map<String, String> occupants;
  final Map<String, FloorReservation> reservations;
  final Set<String> selection;
  final ValueChanged<Set<String>> onSelectionChange;

  /// Editing enabled? Locked, the canvas only pans and zooms.
  final bool editable;
  final FloorViewport viewport;
  final VoidCallback beginGesture;
  final ValueChanged<List<GeoItem>> onGeoChange;

  @override
  State<FloorCanvas> createState() => _FloorCanvasState();
}

/// A handle's half size and its rotate arm, in screen pixels.
const double _handleR = 6;
const double _armLength = 28;

/// How far from a handle's centre a press still takes it (screen pixels).
const double _handleHit = 12;

const List<(double, double)> _corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)];

sealed class _Gesture {}

class _Pan extends _Gesture {
  _Pan(this.last);
  Offset last;
}

class _Marquee extends _Gesture {
  _Marquee(this.from);
  final Offset from;
}

class _Drag extends _Gesture {
  _Drag(this.from, this.origin);
  final Offset from;
  final List<GeoItem> origin;
}

class _Rotate extends _Gesture {
  _Rotate(this.id, this.centre);
  final String id;
  final Offset centre;
}

class _Resize extends _Gesture {
  _Resize(this.id, this.sx, this.sy, this.theta, this.fixed);
  final String id;
  final double sx;
  final double sy;
  final double theta;
  final Offset fixed;
}

Offset _rotate(Offset p, double theta) => Offset(
  p.dx * math.cos(theta) - p.dy * math.sin(theta),
  p.dx * math.sin(theta) + p.dy * math.cos(theta),
);

class _FloorCanvasState extends State<FloorCanvas> {
  _Gesture? _it;
  FloorRect? _marquee;
  final Map<int, Offset> _touches = {};
  double? _pinchDist;
  double _panZoomScale = 1;

  FloorViewport get _v => widget.viewport;

  FloorTable? get _sole => widget.selection.length == 1
      ? widget.tables.where((t) => t.id == widget.selection.first).firstOrNull
      : null;

  bool get _snap => !HardwareKeyboard.instance.isAltPressed;
  bool get _shift => HardwareKeyboard.instance.isShiftPressed;

  /// The topmost table whose body holds [world] (rotation included).
  FloorTable? _tableAt(Offset world) {
    for (final t in widget.tables.reversed) {
      final g = widget.geoOf(t);
      final c = Offset(g.cx, g.cy);
      final p = _rotate(world - c, -g.rot * math.pi / 180);
      if (t.shape == 'circle') {
        final rx = g.w / 2;
        final ry = g.h / 2;
        if (rx > 0 &&
            ry > 0 &&
            (p.dx * p.dx) / (rx * rx) + (p.dy * p.dy) / (ry * ry) <= 1) {
          return t;
        }
      } else if (p.dx.abs() <= g.w / 2 && p.dy.abs() <= g.h / 2) {
        return t;
      }
    }
    return null;
  }

  /// A handle of the one selected table under [local] (screen pixels).
  _Gesture? _handleAt(Offset local, FloorTable t) {
    final g = widget.geoOf(t);
    final theta = g.rot * math.pi / 180;
    final c = Offset(g.cx, g.cy);
    final z = _v.view.zoom;
    final knob = c + _rotate(Offset(0, -g.h / 2 - _armLength / z), theta);
    if ((_v.toScreen(knob.dx, knob.dy) - local).distance <= _handleHit) {
      return _Rotate(t.id, c);
    }
    for (final (sx, sy) in _corners) {
      final corner = c + _rotate(Offset(sx * g.w / 2, sy * g.h / 2), theta);
      final d = _v.toScreen(corner.dx, corner.dy) - local;
      if (d.dx.abs() <= _handleHit && d.dy.abs() <= _handleHit) {
        // The corner diagonally opposite stays put for the whole gesture.
        final fixed = c + _rotate(Offset(-sx * g.w / 2, -sy * g.h / 2), theta);
        return _Resize(t.id, sx, sy, theta, fixed);
      }
    }
    return null;
  }

  // ── Touch pinch: two fingers and their distance are the whole gesture.

  bool _trackDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return false;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2) {
      final [a, b] = _touches.values.toList();
      _pinchDist = (a - b).distance;
      return true;
    }
    return false;
  }

  bool _trackMove(PointerMoveEvent e) {
    if (e.kind != PointerDeviceKind.touch || !_touches.containsKey(e.pointer)) {
      return false;
    }
    _touches[e.pointer] = e.localPosition;
    final prev = _pinchDist;
    if (_touches.length != 2 || prev == null) return false;
    final [a, b] = _touches.values.toList();
    final dist = (a - b).distance;
    _v.zoomBy(pinchFactor(prev, dist), _v.toWorld((a + b) / 2));
    _pinchDist = dist;
    return true;
  }

  void _trackUp(PointerEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    _touches.remove(e.pointer);
    if (_touches.length < 2) _pinchDist = null;
  }

  // ── Pointer handling ───────────────────────────────────────────────────

  void _down(PointerDownEvent e) {
    if (_trackDown(e)) return;
    final world = _v.toWorld(e.localPosition);
    if (widget.editable) {
      final sole = _sole;
      final handle = sole == null ? null : _handleAt(e.localPosition, sole);
      if (handle != null) {
        widget.beginGesture();
        _it = handle;
        return;
      }
      final t = _tableAt(world);
      if (t != null) {
        // Shift extends; a plain press on an unselected table replaces; a
        // press on a selected one keeps the group, so it drags together.
        var next = widget.selection;
        if (_shift) {
          next = {...next};
          if (!next.remove(t.id)) next.add(t.id);
          widget.onSelectionChange(next);
          return;
        }
        if (!next.contains(t.id)) {
          next = {t.id};
          widget.onSelectionChange(next);
        }
        widget.beginGesture();
        _it = _Drag(world, [
          for (final x in widget.tables)
            if (next.contains(x.id)) widget.geoOf(x),
        ]);
        return;
      }
    }
    // Pan when there is nothing to select into: locked, a middle drag, or a
    // finger. Otherwise a drag on empty floor draws a marquee.
    if (!widget.editable ||
        e.buttons == kMiddleMouseButton ||
        e.kind == PointerDeviceKind.touch) {
      _it = _Pan(e.localPosition);
      return;
    }
    if (!_shift) widget.onSelectionChange(<String>{});
    _it = _Marquee(world);
  }

  void _move(PointerMoveEvent e) {
    if (_trackMove(e)) return;
    final it = _it;
    if (it == null) return;
    final p = _v.toWorld(e.localPosition);
    switch (it) {
      case _Pan():
        final d = it.last - e.localPosition;
        it.last = e.localPosition;
        _v.panBy(d.dx, d.dy);
      case _Marquee(:final from):
        setState(
          () => _marquee = FloorRect(
            from.dx,
            from.dy,
            p.dx - from.dx,
            p.dy - from.dy,
          ),
        );
      case _Drag(:final from, :final origin):
        final dx = p.dx - from.dx;
        final dy = p.dy - from.dy;
        widget.onGeoChange([
          for (final g in origin)
            g.copyWith(x: snapTo(g.x + dx, _snap), y: snapTo(g.y + dy, _snap)),
        ]);
      case _Rotate(:final id, :final centre):
        final g = _geoById(id);
        if (g == null) return;
        final deg =
            math.atan2(p.dy - centre.dy, p.dx - centre.dx) * 180 / math.pi + 90;
        final rot = _snap
            ? jsRoundInt(deg / kRotationStep) * kRotationStep
            : deg;
        widget.onGeoChange([g.copyWith(rot: normalizeAngle(rot))]);
      case _Resize(:final id, :final sx, :final sy, :final theta, :final fixed):
        final g = _geoById(id);
        if (g == null) return;
        // In the table's own frame, so a rotated table resizes along its own
        // edges; the opposite corner stays pinned.
        final local = _rotate(p - fixed, -theta);
        final w = math.max(kMinTableSize, snapTo(local.dx.abs(), _snap));
        final h = math.max(kMinTableSize, snapTo(local.dy.abs(), _snap));
        final centre = _rotate(Offset(sx * w / 2, sy * h / 2), theta);
        widget.onGeoChange([
          g.copyWith(
            w: w,
            h: h,
            x: fixed.dx + centre.dx - w / 2,
            y: fixed.dy + centre.dy - h / 2,
          ),
        ]);
    }
  }

  GeoItem? _geoById(String id) {
    final t = widget.tables.where((t) => t.id == id).firstOrNull;
    return t == null ? null : widget.geoOf(t);
  }

  void _up(PointerEvent e) {
    _trackUp(e);
    final it = _it;
    _it = null;
    final m = _marquee;
    if (it is _Marquee && m != null) {
      final hits = marqueeHits(m, widget.tables.map(widget.geoOf));
      widget.onSelectionChange(
        _shift ? {...widget.selection, ...hits} : hits.toSet(),
      );
    }
    if (m != null) setState(() => _marquee = null);
  }

  /// A wheel or a trackpad: ctrl/⌘ + wheel zooms about the cursor, a plain
  /// scroll pans. Claimed, so the page around never scrolls with it.
  void _signal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent && e is! PointerScaleEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final at = _v.toWorld(ev.localPosition);
      if (ev is PointerScaleEvent) {
        _v.zoomBy(ev.scale, at);
        return;
      }
      final s = ev as PointerScrollEvent;
      final kb = HardwareKeyboard.instance;
      switch (wheelIntent(
        deltaX: s.scrollDelta.dx,
        deltaY: s.scrollDelta.dy,
        ctrlOrMeta: kb.isControlPressed || kb.isMetaPressed,
      )) {
        case WheelZoom(:final factor):
          _v.zoomBy(factor, at);
        case WheelPan(:final dx, :final dy):
          _v.panBy(dx, dy);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final seatsWord = context.t('floor.seatsShort');
    return ListenableBuilder(
      listenable: _v,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          _v.layout(box.biggest);
          final visuals = [
            for (final t in widget.tables)
              FloorTableVisual(
                id: t.id,
                geo: widget.geoOf(t),
                shape: t.shape,
                label: t.label,
                seats: t.seats,
                status: t.status,
                occupant: widget.occupants[t.id],
                reservation: widget.reservations[t.id]?.label,
                held: widget.reservations[t.id]?.held ?? false,
              ),
          ];
          final sole = widget.editable ? _sole : null;
          return Semantics(
            container: true,
            label: context.t('floor.canvasAria'),
            child: MouseRegion(
              cursor: widget.editable
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.grab,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                onPointerSignal: _signal,
                onPointerPanZoomStart: (_) => _panZoomScale = 1,
                onPointerPanZoomUpdate: (e) {
                  _v
                    ..panBy(-e.panDelta.dx, -e.panDelta.dy)
                    ..zoomBy(
                      e.scale / _panZoomScale,
                      _v.toWorld(e.localPosition),
                    );
                  _panZoomScale = e.scale;
                },
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: {
                    EagerGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          EagerGestureRecognizer
                        >(EagerGestureRecognizer.new, (_) {}),
                  },
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: _FloorPainter(
                            view: _v.view,
                            visuals: visuals,
                            selection: widget.selection,
                            handles: sole == null ? null : widget.geoOf(sole),
                            marquee: _marquee,
                            style: FloorPaintStyle(
                              colors: c,
                              seatsWord: seatsWord,
                              textDirection: Directionality.of(context),
                            ),
                          ),
                        ),
                        for (final t in visuals)
                          _tableBox(
                            t,
                            seatsWord,
                            context.t('floor.tone_${t.tone.name}'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// One table's hover title and screen-reader name (the title and its
  /// state, never colour alone), over its rotated bounds (physical:
  /// [Positioned], never directional).
  Widget _tableBox(FloorTableVisual t, String seatsWord, String toneWord) {
    final g = t.geo;
    final th = g.rot * math.pi / 180;
    final hw = ((g.w * math.cos(th)).abs() + (g.h * math.sin(th)).abs()) / 2;
    final hh = ((g.w * math.sin(th)).abs() + (g.h * math.cos(th)).abs()) / 2;
    final z = _v.view.zoom;
    final c = _v.toScreen(g.cx, g.cy);
    final title = t.title(seatsWord);
    return Positioned(
      left: c.dx - hw * z,
      top: c.dy - hh * z,
      width: hw * 2 * z,
      height: hh * 2 * z,
      child: Tooltip(
        key: ValueKey('floor-table-${t.id}'),
        message: title,
        excludeFromSemantics: true,
        child: Semantics(
          label: '$title · $toneWord',
          selected: widget.selection.contains(t.id),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _FloorPainter extends CustomPainter {
  _FloorPainter({
    required this.view,
    required this.visuals,
    required this.selection,
    required this.handles,
    required this.marquee,
    required this.style,
  });

  final FloorView view;
  final List<FloorTableVisual> visuals;
  final Set<String> selection;

  /// The one selected table, when editing (its resize and rotate handles).
  final GeoItem? handles;
  final FloorRect? marquee;
  final FloorPaintStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final c = style.colors;
    final z = view.zoom;
    Offset s(double x, double y) => Offset((x - view.x) * z, (y - view.y) * z);

    // The light 50-unit grid.
    final grid = Paint()
      ..color = c.border.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    const pitch = kFloorGrid * 5;
    final right = view.x + size.width / z;
    final bottom = view.y + size.height / z;
    for (
      var x = (view.x / pitch).floorToDouble() * pitch;
      x <= right;
      x += pitch
    ) {
      canvas.drawLine(s(x, view.y), s(x, bottom), grid);
    }
    for (
      var y = (view.y / pitch).floorToDouble() * pitch;
      y <= bottom;
      y += pitch
    ) {
      canvas.drawLine(s(view.x, y), s(right, y), grid);
    }

    final primary = c.accent;
    for (final t in visuals) {
      final g = t.geo;
      canvas
        ..save()
        ..translate(s(g.cx, g.cy).dx, s(g.cx, g.cy).dy)
        ..rotate(g.rot * math.pi / 180)
        ..translate(-g.w * z / 2, -g.h * z / 2);
      paintTableGlyph(canvas, t, z, style);
      if (selection.contains(t.id)) {
        final outline = Path()
          ..addRect(
            Rect.fromLTWH(-4 * z, -4 * z, (g.w + 8) * z, (g.h + 8) * z),
          );
        canvas.drawPath(
          dashPath(outline, 6, 4),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = primary
            ..strokeWidth = 2,
        );
      }
      canvas.restore();
    }

    final h = handles;
    if (h != null) {
      final fill = Paint()..color = c.bg;
      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..color = primary
        ..strokeWidth = 1.5;
      canvas
        ..save()
        ..translate(s(h.cx, h.cy).dx, s(h.cx, h.cy).dy)
        ..rotate(h.rot * math.pi / 180);
      final hw = h.w * z / 2;
      final hh = h.h * z / 2;
      for (final (sx, sy) in _corners) {
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(sx * hw, sy * hh),
            width: _handleR * 2,
            height: _handleR * 2,
          ),
          const Radius.circular(2),
        );
        canvas
          ..drawRRect(r, fill)
          ..drawRRect(r, edge);
      }
      final knob = Offset(0, -hh - _armLength);
      canvas
        ..drawLine(Offset(0, -hh), knob, edge)
        ..drawCircle(knob, _handleR, fill)
        ..drawCircle(knob, _handleR, edge)
        ..restore();
    }

    final m = marquee;
    if (m != null) {
      final r = normalizedRect(m);
      final rect = Rect.fromPoints(s(r.x, r.y), s(r.x + r.w, r.y + r.h));
      canvas
        ..drawRect(rect, Paint()..color = primary.withValues(alpha: 0.08))
        ..drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = primary
            ..strokeWidth = 1,
        );
    }
  }

  @override
  bool shouldRepaint(_FloorPainter old) => true;
}
