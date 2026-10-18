import 'dart:io' show Platform;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Whether a page builds in stages ([DashDeferred], the table's rows a
/// chunk a frame). Off under `flutter test`: a widget test pumps one frame
/// and expects the whole page.
final bool dashStagedBuild = !Platform.environment.containsKey('FLUTTER_TEST');

/// Builds [child] [frames] frames after it is first mounted, holding
/// [placeholderHeight] until then.
///
/// For the parts of a page a first visit need not build in its first frame
/// (the sections below the fold): the page then spreads its first build over
/// a few frames instead of dropping several in one. The page fades in over
/// those frames ([DashEntrance]), so nothing is seen arriving; the deferred
/// part's own motion plays as it would, from when it is built.
class DashDeferred extends StatefulWidget {
  const DashDeferred({
    required this.child,
    this.frames = 1,
    this.placeholderHeight = 0,
    super.key,
  });

  final Widget child;

  /// How many frames after the first one [child] is built in.
  final int frames;
  final double placeholderHeight;

  @override
  State<DashDeferred> createState() => _DashDeferredState();
}

class _DashDeferredState extends State<DashDeferred> {
  late bool _ready = !dashStagedBuild || widget.frames <= 0;
  late int _left = widget.frames;

  @override
  void initState() {
    super.initState();
    if (!_ready) _wait();
  }

  void _wait() {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        if (--_left <= 0) {
          setState(() => _ready = true);
        } else {
          _wait();
        }
      })
      ..scheduleFrame();
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : SizedBox(height: widget.placeholderHeight);
}

/// How many of a list's items to build this frame, for a list of cards or
/// rows that is not lazy (it sits in the page's scroll): items arriving
/// where none were shown (a first visit, a load landing) are built [first]
/// at once and then [step] a frame, so a first visit does not build the
/// whole page in one frame; items replacing items (a refetch, another page)
/// are built at once, so nothing on screen ever blanks.
class DashStager {
  DashStager({this.first = 8, this.step = 6});

  final int first;
  final int step;

  int? _built;
  bool _shown = false;
  bool _scheduled = false;

  /// The count of [total] items to build; [showing] is false while the
  /// list shows a skeleton, an error or its empty state. When more are due,
  /// [grow] runs after this frame (from a mounted check of the caller's)
  /// and must rebuild the list.
  int count(
    int total, {
    required bool showing,
    required void Function(VoidCallback fn) grow,
    bool staged = true,
  }) {
    if (!showing || !staged) {
      _built = null;
    } else if (!_shown && dashStagedBuild) {
      _built = first;
    }
    _shown = showing;
    final built = _built;
    if (built == null || built >= total) {
      _built = null;
      return total;
    }
    if (!_scheduled) {
      _scheduled = true;
      SchedulerBinding.instance
        ..addPostFrameCallback((_) {
          _scheduled = false;
          grow(() {
            if (_built != null) _built = _built! + step;
          });
        })
        ..scheduleFrame();
    }
    return built;
  }
}
