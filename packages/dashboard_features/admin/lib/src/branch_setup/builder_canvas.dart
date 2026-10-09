/// The branch as a drawing (the web's `builder-canvas.tsx`): every piece of
/// hardware a card, every connection a line, on the floor editor's camera
/// (an unbounded plane, wheel and trackpad pan and pinch, touch pinch) and
/// its grid.
///
/// Pieces are dragged into place; a line is drawn by dragging from a card's
/// port onto another card. Only lines that mean something are accepted
/// ([linkKindFor]); while one is drawn the cards that would take it get a
/// ring and the rest fade. Dragging is never the only way: every card is
/// reached with Tab, moved with the arrow keys (the page's keyboard) and
/// linked from the inspector. A floor plan is physical space: positions are
/// never mirrored in Arabic, and the port sits on the physical right edge.
library;

import 'dart:math' as math;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'plan.dart';

/// The camera: the world point at the canvas's top-left and pixels per
/// world unit (the floor's `useFloorViewport`).
class BuilderViewport extends ChangeNotifier {
  double x = 0, y = 0, zoom = 1;

  /// The canvas in pixels (the web starts at 900 × 600 until measured).
  Size size = const Size(900, 600);
  bool _measured = false;
  List<PieceBox>? _fitPending;

  void layout(Size s) {
    if (s.width <= 0 || s.height <= 0 || !s.isFinite) return;
    final first = !_measured;
    _measured = true;
    size = s;
    final pending = _fitPending;
    _fitPending = null;
    if (first && pending != null) _fit(pending);
  }

  void _fit(List<PieceBox> boxes) {
    final b = boundsOf(boxes);
    zoom = clampZoom(
      math.min(
        size.width / (b.w + kFitPadding * 2),
        size.height / (b.h + kFitPadding * 2),
      ),
    );
    x = b.x + b.w / 2 - size.width / (2 * zoom);
    y = b.y + b.h / 2 - size.height / (2 * zoom);
  }

  /// Frames [boxes] (`fitTo`); nothing to frame is a no-op.
  void fitTo(List<PieceBox> boxes) {
    if (boxes.isEmpty) return;
    if (!_measured) _fitPending = boxes;
    _fit(boxes);
    notifyListeners();
  }

  /// Zooms by [factor] about the world point [anchor] (the view's centre by
  /// default, so buttons and keys hold the middle).
  void zoomBy(double factor, [Offset? anchor]) {
    final next = clampZoom(zoom * factor);
    if (next == zoom) return;
    final a =
        anchor ??
        Offset(x + size.width / (2 * zoom), y + size.height / (2 * zoom));
    x = a.dx - (a.dx - x) * (zoom / next);
    y = a.dy - (a.dy - y) * (zoom / next);
    zoom = next;
    notifyListeners();
  }

  void panBy(double dx, double dy) {
    if (dx == 0 && dy == 0) return;
    x += dx / zoom;
    y += dy / zoom;
    notifyListeners();
  }

  Offset toWorld(Offset local) => Offset(x + local.dx / zoom, y + local.dy / zoom);
  Offset toScreen(double wx, double wy) =>
      Offset((wx - x) * zoom, (wy - y) * zoom);

  /// The world rectangle the canvas shows.
  Rect get rect => Rect.fromLTWH(x, y, size.width / zoom, size.height / zoom);
}

enum PieceProblem { blocking, warning }

enum PresenceTone { online, offline, unclaimed }

/// What a card shows; built by the page, which knows the live state.
class PieceView {
  const PieceView({
    required this.box,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.detail,
    this.presence,
    this.badge,
    this.placeholder = false,
    this.problem,
  });

  final PieceBox box;
  final String icon;
  final String title;
  final String subtitle;
  final String? detail;
  final ({PresenceTone tone, String label})? presence;
  final String? badge;

  /// A slot no device fills yet is drawn dashed: a place, not a thing.
  final bool placeholder;
  final PieceProblem? problem;

  String get key => box.key;
}

/// Line style per kind: the dash pattern carries the meaning, colour only
/// helps (world units).
({bool primary, List<double>? dash, double width}) linkStyle(LinkKind k) =>
    switch (k) {
      LinkKind.shows => (primary: true, dash: null, width: 2),
      LinkKind.prints => (primary: true, dash: const [7, 5], width: 2),
      LinkKind.receipt => (primary: false, dash: null, width: 1.5),
      LinkKind.host => (primary: false, dash: const [2, 5], width: 1.5),
    };

typedef Curve = ({Offset p1, Offset c1, Offset c2, Offset p2, Offset mid});

/// Where a line leaves one card and meets the other: the facing sides, so a
/// printer under its till is joined bottom-to-top and a screen beside its
/// section side-to-side (`routeBetween`).
Curve routeBetween(PieceBox a, PieceBox b) {
  final dx = b.cx - a.cx, dy = b.cy - a.cy;
  final horizontal = dx.abs() * (a.h + b.h) >= dy.abs() * (a.w + b.w) * 0.5;
  Offset p1, p2, c1, c2;
  if (horizontal) {
    final s = dx == 0 ? 1.0 : dx.sign;
    p1 = Offset(a.cx + s * a.w / 2, a.cy);
    p2 = Offset(b.cx - s * b.w / 2, b.cy);
    final k = math.max(32.0, (p2.dx - p1.dx).abs() / 2);
    c1 = Offset(p1.dx + s * k, p1.dy);
    c2 = Offset(p2.dx - s * k, p2.dy);
  } else {
    final s = dy == 0 ? 1.0 : dy.sign;
    p1 = Offset(a.cx, a.cy + s * a.h / 2);
    p2 = Offset(b.cx, b.cy - s * b.h / 2);
    final k = math.max(24.0, (p2.dy - p1.dy).abs() / 2);
    c1 = Offset(p1.dx, p1.dy + s * k);
    c2 = Offset(p2.dx, p2.dy - s * k);
  }
  final mid = (p1 + c1 * 3 + c2 * 3 + p2) / 8;
  return (p1: p1, c1: c1, c2: c2, p2: p2, mid: mid);
}

Offset _bezier(Curve c, double t) {
  final u = 1 - t;
  return c.p1 * (u * u * u) +
      c.c1 * (3 * u * u * t) +
      c.c2 * (3 * u * t * t) +
      c.p2 * (t * t * t);
}

/// Distance from [p] to the curve (sampled), in world units.
double distanceToCurve(Curve c, Offset p) {
  var best = double.infinity;
  for (var i = 0; i <= 32; i++) {
    best = math.min(best, (_bezier(c, i / 32) - p).distance);
  }
  return best;
}

/// Screen pixels around a line that still take a press (the web's 14 px
/// invisible stroke).
const double kLineHit = 7;

/// The port's press radius in screen pixels (a 44 px target).
const double kPortHit = 22;
const double _portDot = 5.5;

sealed class _Gesture {}

class _Pan extends _Gesture {
  _Pan(this.last);
  Offset last;
}

class _Drag extends _Gesture {
  _Drag(this.from, this.origin);
  final Offset from;
  final Map<String, Offset> origin;
  bool moved = false;
}

class _Link extends _Gesture {
  _Link(this.from);
  final PieceRef from;
}

class BuilderCanvas extends StatefulWidget {
  const BuilderCanvas({
    required this.plan,
    required this.pieces,
    required this.editable,
    required this.viewport,
    required this.selection,
    required this.onSelectionChange,
    required this.selectedLink,
    required this.onSelectLink,
    required this.beginGesture,
    required this.onMove,
    required this.onLink,
    required this.onRemoveLink,
    required this.words,
    super.key,
  });

  final BuilderPlan plan;
  final List<PieceView> pieces;
  final bool editable;
  final BuilderViewport viewport;
  final Set<String> selection;
  final ValueChanged<Set<String>> onSelectionChange;
  final PlanLink? selectedLink;
  final ValueChanged<PlanLink?> onSelectLink;
  final VoidCallback beginGesture;
  final ValueChanged<Map<String, ({double x, double y})>> onMove;
  final void Function(PieceRef from, PieceRef to) onLink;
  final ValueChanged<PlanLink> onRemoveLink;

  /// `canvasAria`, each link kind's name, `removeLink`.
  final ({String canvas, String Function(LinkKind) link, String removeLink})
  words;

  @override
  State<BuilderCanvas> createState() => _BuilderCanvasState();
}

class _BuilderCanvasState extends State<BuilderCanvas> {
  _Gesture? _it;
  Offset? _pointer;
  PieceRef? _linking;
  String? _hoverKey;
  ({PlanLink link, Offset at})? _hoverLink;
  final Map<int, Offset> _touches = {};
  double? _pinchDist;
  Offset? _pinchMid;
  double _panZoomScale = 1;

  BuilderViewport get _v => widget.viewport;

  Map<String, PieceBox> get _boxes => {
    for (final p in widget.pieces) p.key: p.box,
  };

  String? _hitPiece(Offset world) {
    for (final p in widget.pieces.reversed) {
      if (p.box.contains(world.dx, world.dy)) return p.key;
    }
    return null;
  }

  String? _hitPort(Offset local) {
    if (!widget.editable) return null;
    for (final p in widget.pieces.reversed) {
      final c = _v.toScreen(p.box.x + p.box.w, p.box.cy);
      if ((c - local).distance <= kPortHit) return p.key;
    }
    return null;
  }

  PlanLink? _hitLine(Offset world) {
    final boxes = _boxes;
    PlanLink? best;
    var bestD = kLineHit / _v.zoom;
    for (final l in linksOf(widget.plan)) {
      final a = boxes[l.from.key], b = boxes[l.to.key];
      if (a == null || b == null) continue;
      final d = distanceToCurve(routeBetween(a, b), world);
      if (d <= bestD) {
        bestD = d;
        best = l;
      }
    }
    return best;
  }

  bool _accepts(String key) {
    final from = _linking;
    return from != null &&
        key != from.key &&
        linkKindFor(widget.plan, from, PieceRef.parse(key)) != null;
  }

  // ── Touch pinch ─────────────────────────────────────────────────────────

  bool _trackDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return false;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length != 2) return false;
    final [a, b] = _touches.values.toList();
    _pinchDist = (a - b).distance;
    _pinchMid = (a + b) / 2;
    _endLink();
    _it = null;
    return true;
  }

  bool _trackMove(PointerMoveEvent e) {
    if (e.kind != PointerDeviceKind.touch || !_touches.containsKey(e.pointer)) {
      return false;
    }
    _touches[e.pointer] = e.localPosition;
    final prev = _pinchDist, prevMid = _pinchMid;
    if (_touches.length != 2 || prev == null || prevMid == null) return false;
    final [a, b] = _touches.values.toList();
    final dist = (a - b).distance, mid = (a + b) / 2;
    _v
      ..panBy(prevMid.dx - mid.dx, prevMid.dy - mid.dy)
      ..zoomBy(prev > 0 && dist > 0 ? dist / prev : 1, _v.toWorld(mid));
    _pinchDist = dist;
    _pinchMid = mid;
    return true;
  }

  void _trackUp(PointerEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    _touches.remove(e.pointer);
    if (_touches.length < 2) _pinchDist = _pinchMid = null;
  }

  // ── Pointer handling ────────────────────────────────────────────────────

  void _down(PointerDownEvent e) {
    if (_trackDown(e)) return;
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryButton) {
      return;
    }
    final world = _v.toWorld(e.localPosition);
    final shift = HardwareKeyboard.instance.isShiftPressed;
    setState(() => _hoverLink = null);

    final port = _hitPort(e.localPosition);
    if (port != null) {
      final from = PieceRef.parse(port);
      _it = _Link(from);
      setState(() {
        _linking = from;
        _pointer = world;
      });
      return;
    }
    final key = _hitPiece(world);
    if (key != null) {
      widget.onSelectLink(null);
      if (shift) {
        final next = {...widget.selection};
        if (!next.remove(key)) next.add(key);
        widget.onSelectionChange(next);
        return;
      }
      var next = widget.selection;
      if (!next.contains(key)) {
        next = {key};
        widget.onSelectionChange(next);
      }
      if (!widget.editable) {
        _it = _Pan(e.localPosition);
        return;
      }
      final boxes = _boxes;
      _it = _Drag(world, {
        for (final k in next)
          if (boxes[k] case final b?) k: Offset(b.x, b.y),
      });
      return;
    }
    final line = _hitLine(world);
    if (line != null) {
      widget.onSelectionChange(const {});
      widget.onSelectLink(line);
      return;
    }
    if (!shift) {
      widget.onSelectionChange(const {});
      widget.onSelectLink(null);
    }
    _it = _Pan(e.localPosition);
  }

  void _move(PointerMoveEvent e) {
    if (_trackMove(e)) return;
    final it = _it;
    switch (it) {
      case null:
        return;
      case _Pan():
        final d = it.last - e.localPosition;
        it.last = e.localPosition;
        _v.panBy(d.dx, d.dy);
      case _Link():
        final world = _v.toWorld(e.localPosition);
        setState(() {
          _pointer = world;
          _hoverKey = _hitPiece(world);
        });
      case _Drag():
        if (!it.moved) widget.beginGesture();
        it.moved = true;
        final world = _v.toWorld(e.localPosition);
        final d = world - it.from;
        final on = !HardwareKeyboard.instance.isAltPressed;
        widget.onMove({
          for (final o in it.origin.entries)
            o.key: (x: snapTo(o.value.dx + d.dx, on), y: snapTo(o.value.dy + d.dy, on)),
        });
    }
  }

  void _up(PointerEvent e) {
    _trackUp(e);
    final it = _it;
    _it = null;
    if (it is _Link) {
      final target = _hitPiece(_v.toWorld(e.localPosition));
      if (target != null && target != it.from.key && e is PointerUpEvent) {
        widget.onLink(it.from, PieceRef.parse(target));
      }
      _endLink();
    }
  }

  void _endLink() {
    if (_linking == null) return;
    setState(() {
      _linking = null;
      _pointer = null;
      _hoverKey = null;
    });
  }

  void _hover(PointerHoverEvent e) {
    if (e.kind != PointerDeviceKind.mouse) return;
    final world = _v.toWorld(e.localPosition);
    final line = _hitPiece(world) == null ? _hitLine(world) : null;
    final next = line == null ? null : (link: line, at: e.localPosition);
    if (next?.link != _hoverLink?.link || next?.at != _hoverLink?.at) {
      setState(() => _hoverLink = next);
    }
  }

  /// Ctrl/⌘ + wheel (and a trackpad pinch, which arrives that way) zooms
  /// about the pointer; a plain scroll pans. Claimed, so the page never
  /// scrolls with it.
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
      if (kb.isControlPressed || kb.isMetaPressed) {
        _v.zoomBy(math.exp(-s.scrollDelta.dy * 0.01), at);
      } else {
        _v.panBy(s.scrollDelta.dx, s.scrollDelta.dy);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return ListenableBuilder(
      listenable: _v,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          _v.layout(box.biggest);
          final linking = _linking;
          final boxes = _boxes;
          PieceBox? to;
          if (linking != null && _pointer != null) {
            final hover = _hoverKey;
            to = hover != null && _accepts(hover)
                ? boxes[hover]
                : PieceBox('', _pointer!.dx, _pointer!.dy, 0, 0);
          }
          final selected = widget.selectedLink;
          return Semantics(
            container: true,
            label: widget.words.canvas,
            child: MouseRegion(
              cursor: linking != null
                  ? SystemMouseCursors.precise
                  : SystemMouseCursors.grab,
              onHover: _hover,
              onExit: (_) {
                if (_hoverLink != null) setState(() => _hoverLink = null);
              },
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
                          painter: _LinesPainter(
                            viewport: _v,
                            links: [
                              for (final l in linksOf(widget.plan))
                                if (boxes[l.from.key] case final a?)
                                  if (boxes[l.to.key] case final b?)
                                    (link: l, curve: routeBetween(a, b)),
                            ],
                            selected: selected,
                            faded: linking != null,
                            drawing: linking != null && to != null
                                ? (switch (boxes[linking.key]) {
                                    final a? => routeBetween(a, to),
                                    null => null,
                                  })
                                : null,
                            primary: c.accent,
                            muted: c.textMuted,
                            grid: c.border,
                          ),
                        ),
                        for (final p in widget.pieces) _card(p),
                        if (widget.editable)
                          for (final p in widget.pieces) _port(p),
                        if (selected != null) _pill(selected, boxes),
                        if (_hoverLink case final h?)
                          Positioned(
                            left: h.at.dx + Space.md,
                            top: h.at.dy + Space.md,
                            child: IgnorePointer(
                              child: _Chip(
                                text: widget.words.link(h.link.kind),
                              ),
                            ),
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

  Widget _card(PieceView p) {
    final b = p.box;
    final z = _v.zoom;
    final at = _v.toScreen(b.x, b.y);
    final isSelected = widget.selection.contains(p.key);
    final takes = _accepts(p.key);
    final linking = _linking;
    final faded = linking != null && !takes && p.key != linking.key;
    final label = [
      p.title,
      p.subtitle,
      ?p.detail,
      ?p.presence?.label,
    ].where((s) => s.isNotEmpty).join(', ');
    return Positioned(
      key: ValueKey('bb-card-${p.key}'),
      left: at.dx,
      top: at.dy,
      width: b.w * z,
      height: b.h * z,
      child: Focus(
        onFocusChange: (f) {
          if (f && !widget.selection.contains(p.key)) {
            widget.onSelectionChange({p.key});
          }
        },
        child: Semantics(
          button: true,
          selected: isSelected,
          label: label,
          excludeSemantics: true,
          child: Opacity(
            opacity: faded ? 0.4 : 1,
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: b.w,
                height: b.h,
                child: BuilderCard(
                  piece: p,
                  selected: isSelected,
                  ring: takes
                      ? (_hoverKey == p.key ? CardRing.strong : CardRing.soft)
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _port(PieceView p) {
    final c = context.madarColors;
    final at = _v.toScreen(p.box.x + p.box.w, p.box.cy);
    return Positioned(
      key: ValueKey('bb-port-${p.key}'),
      left: at.dx - kPortHit,
      top: at.dy - kPortHit,
      width: kPortHit * 2,
      height: kPortHit * 2,
      child: IgnorePointer(
        child: MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: Center(
            child: Container(
              width: _portDot * 2,
              height: _portDot * 2,
              decoration: BoxDecoration(
                color: c.card,
                shape: BoxShape.circle,
                border: Border.all(color: c.accent, width: 1.75),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(PlanLink link, Map<String, PieceBox> boxes) {
    final a = boxes[link.from.key], b = boxes[link.to.key];
    if (a == null || b == null) return const SizedBox.shrink();
    final mid = routeBetween(a, b).mid;
    final at = _v.toScreen(mid.dx, mid.dy);
    return Positioned(
      key: const ValueKey('bb-link-pill'),
      left: at.dx - 90,
      top: at.dy - 22,
      width: 180,
      height: 44,
      child: Center(
        child: _Chip(
          text: widget.words.link(link.kind),
          trailing: widget.editable
              ? DashIconButton(
                  icon: 'x',
                  semanticLabel: widget.words.removeLink,
                  variant: DashButtonVariant.ghost,
                  iconSize: 14,
                  onPressed: () => widget.onRemoveLink(link),
                )
              : null,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: EdgeInsetsDirectional.only(
        start: Space.md,
        end: trailing == null ? Space.md : 0,
      ),
      constraints: const BoxConstraints(minHeight: Space.xl + Space.xs),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.border),
        boxShadow: DashShadows.popover(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: DashType.smallMedium.copyWith(color: c.textPrimary)),
          ?trailing,
        ],
      ),
    );
  }
}

enum CardRing { soft, strong }

/// One card, drawn at its world size (216 × 76; a section 104 tall) and
/// scaled by the camera.
class BuilderCard extends StatelessWidget {
  const BuilderCard({
    required this.piece,
    required this.selected,
    this.ring,
    super.key,
  });

  final PieceView piece;
  final bool selected;
  final CardRing? ring;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final p = piece;
    final ringColor = switch (ring) {
      CardRing.strong => c.accent,
      CardRing.soft => c.ring,
      null => selected ? c.ring : null,
    };
    final ringWidth = ring == CardRing.strong ? 3.0 : 2.0;
    final problem = p.problem;
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.md),
        border: p.placeholder
            ? null
            : Border.all(color: selected ? c.accent : c.border),
        boxShadow: [
          if (ringColor != null)
            BoxShadow(color: ringColor, spreadRadius: ringWidth),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: [
          Row(
            spacing: Space.sm + 2,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.placeholder ? c.muted : c.accentBg,
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                child: MadarIcon(
                  p.icon,
                  size: 18,
                  tint: p.placeholder ? c.textMuted : c.accent,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashType.bodyStrong.copyWith(
                        color: c.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    Row(
                      spacing: Space.xs + 2,
                      children: [
                        Flexible(
                          child: Text(
                            p.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashType.small.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                        if (p.badge case final badge?)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.xs + 2,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: c.muted,
                              borderRadius: BorderRadius.circular(Radii.pill),
                            ),
                            child: Text(
                              badge,
                              style: DashType.smallMedium.copyWith(
                                fontSize: 10,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (problem != null)
                MadarIcon(
                  'triangle-alert',
                  size: 16,
                  tint: problem == PieceProblem.blocking ? c.danger : c.warning,
                ),
            ],
          ),
          if (p.detail != null || p.presence != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 46),
              child: Row(
                spacing: Space.sm,
                children: [
                  if (p.presence case final pr?) PresenceDot(tone: pr.tone, label: pr.label),
                  if (p.detail case final d?)
                    Flexible(
                      child: Text(
                        d,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (!p.placeholder) return body;
    return CustomPaint(
      foregroundPainter: DashedBorderPainter(
        color: selected ? c.accent : c.textMuted,
        radius: Radii.md,
      ),
      child: body,
    );
  }
}

/// A device's live state, in words as well as colour.
class PresenceDot extends StatelessWidget {
  const PresenceDot({required this.tone, required this.label, super.key});

  final PresenceTone tone;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final dot = SizedBox.square(
      dimension: 8,
      child: tone == PresenceTone.unclaimed
          ? CustomPaint(
              painter: DashedBorderPainter(
                color: c.textMuted,
                radius: 4,
                dash: 2,
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tone == PresenceTone.online
                    ? c.success
                    : c.textMuted.withValues(alpha: 0.6),
              ),
            ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        dot,
        Text(
          label,
          style: DashType.small.copyWith(
            color: tone == PresenceTone.online ? c.success : c.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// A dashed rounded outline (the web's `border-dashed`).
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    required this.radius,
    this.dash = 4,
  });

  final Color color;
  final double radius;
  final double dash;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.5),
      );
    canvas.drawPath(
      _dashed(path, [dash, dash]),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color || old.radius != radius || old.dash != dash;
}

Path _dashed(Path source, List<double> pattern) {
  final out = Path();
  for (final m in source.computeMetrics()) {
    var d = 0.0;
    var i = 0;
    while (d < m.length) {
      final len = pattern[i % pattern.length];
      if (i.isEven) out.addPath(m.extractPath(d, d + len), Offset.zero);
      d += len;
      i++;
    }
  }
  return out;
}

class _LinesPainter extends CustomPainter {
  _LinesPainter({
    required this.viewport,
    required this.links,
    required this.selected,
    required this.faded,
    required this.drawing,
    required this.primary,
    required this.muted,
    required this.grid,
  }) : z = viewport.zoom,
       vx = viewport.x,
       vy = viewport.y;

  final BuilderViewport viewport;
  final List<({PlanLink link, Curve curve})> links;
  final PlanLink? selected;
  final bool faded;
  final Curve? drawing;
  final Color primary, muted, grid;
  final double z, vx, vy;

  Offset _s(Offset w) => Offset((w.dx - vx) * z, (w.dy - vy) * z);

  Path _path(Curve c) {
    final p1 = _s(c.p1), c1 = _s(c.c1), c2 = _s(c.c2), p2 = _s(c.p2);
    return Path()
      ..moveTo(p1.dx, p1.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The grid: a line every 50 units, one pixel at any zoom.
    final step = kGrid * 5;
    final g = Paint()
      ..color = grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final x0 = (vx / step).floorToDouble() * step;
    final y0 = (vy / step).floorToDouble() * step;
    for (var x = x0; (x - vx) * z <= size.width; x += step) {
      final sx = (x - vx) * z;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), g);
    }
    for (var y = y0; (y - vy) * z <= size.height; y += step) {
      final sy = (y - vy) * z;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), g);
    }

    for (final (:link, :curve) in links) {
      final style = linkStyle(link.kind);
      final isSelected = link == selected;
      final worldWidth =
          (isSelected ? style.width + 1.5 : style.width) * math.max(1, 0.8 / z);
      final width = worldWidth * z;
      final color = (style.primary ? primary : muted).withValues(
        alpha: faded ? 0.35 : 1,
      );
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;
      var path = _path(curve);
      if (style.dash case final dash?) {
        path = _dashed(path, [for (final d in dash) d * z]);
      }
      canvas.drawPath(path, paint);
      // The arrowhead (`markerUnits="strokeWidth"`, 7 × the stroke).
      final tip = _s(curve.p2);
      var dir = tip - _s(curve.c2);
      if (dir.distance == 0) dir = tip - _s(curve.p1);
      if (dir.distance == 0) continue;
      final u = dir / dir.distance;
      final n = Offset(-u.dy, u.dx);
      final len = 6.3 * width, half = 2.8 * width;
      final base = tip - u * len;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo((base + n * half).dx, (base + n * half).dy)
          ..lineTo((base - n * half).dx, (base - n * half).dy)
          ..close(),
        Paint()..color = color,
      );
    }

    if (drawing case final d?) {
      canvas.drawPath(
        _dashed(_path(d), const [4, 4]),
        Paint()
          ..color = primary
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) => true;
}

/// The legend: what each kind of line means.
class LinkLegend extends StatelessWidget {
  const LinkLegend({required this.label, super.key});

  final String Function(LinkKind) label;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Wrap(
      spacing: Space.md,
      runSpacing: Space.xs,
      children: [
        for (final k in LinkKind.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs + 2,
            children: [
              SizedBox(
                width: 22,
                height: 8,
                child: CustomPaint(painter: _LegendLine(k, c.accent, c.textMuted)),
              ),
              Text(
                label(k),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ],
          ),
      ],
    );
  }
}

class _LegendLine extends CustomPainter {
  const _LegendLine(this.kind, this.primary, this.muted);

  final LinkKind kind;
  final Color primary, muted;

  @override
  void paint(Canvas canvas, Size size) {
    final s = linkStyle(kind);
    var path = Path()
      ..moveTo(1, size.height / 2)
      ..lineTo(size.width - 1, size.height / 2);
    if (s.dash case final d?) path = _dashed(path, d);
    canvas.drawPath(
      path,
      Paint()
        ..color = s.primary ? primary : muted
        ..strokeWidth = s.width
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_LegendLine old) => false;
}

