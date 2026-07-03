import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Device-class-aware screen-orientation lock.
///
/// Tablets/desktop lock to ONE landscape at a time — never auto-rotating —
/// and the user flips between the two with a button. Phones lock to normal
/// portrait with no flip. App-global platform state, so it's a singleton
/// (it must be the same instance across the app's separate provider
/// containers — see the ready-scope split in main.dart).
class OrientationController extends ChangeNotifier {
  OrientationController._();

  /// The one instance every screen reads.
  static final OrientationController instance = OrientationController._();

  /// Tablet-class breakpoint on the shortest side (Material's tablet cutoff).
  static const double tabletShortestSide = 600;

  bool _isTablet = true;
  bool _landscapeRight = false;
  bool _applied = false;

  /// Tablet/desktop → landscape with a flip; phone → portrait, no flip.
  bool get isTablet => _isTablet;

  /// Which of the two landscape locks is active (tablet only).
  bool get landscapeRight => _landscapeRight;

  /// The flip is only meaningful on a tablet (phones are portrait-locked).
  bool get canFlip => _isTablet;

  /// Set the device class (from the platform view at launch, then confirmed
  /// from MediaQuery on the first frame) and apply the lock. Applies once
  /// per distinct class; safe to call every build.
  void setDeviceClass({required bool isTablet}) {
    if (_applied && isTablet == _isTablet) return;
    _isTablet = isTablet;
    _apply();
    // Deferred so a MediaQuery-time caller (MaterialApp.builder) never
    // notifies listeners mid-build.
    scheduleMicrotask(notifyListeners);
  }

  /// Toggle between the two landscape locks (tablet only). No-op on phones.
  void flip() {
    if (!_isTablet) return;
    _landscapeRight = !_landscapeRight;
    _apply();
    notifyListeners();
  }

  void _apply() {
    _applied = true;
    final orientations = <DeviceOrientation>[
      if (!_isTablet)
        DeviceOrientation.portraitUp
      else if (_landscapeRight)
        DeviceOrientation.landscapeRight
      else
        DeviceOrientation.landscapeLeft,
    ];
    unawaited(SystemChrome.setPreferredOrientations(orientations));
  }
}

/// A `MaterialApp.builder` that confirms the device class from MediaQuery
/// (reliable once a frame exists) and re-applies the orientation lock. Use
/// on every MaterialApp so the lock is correct regardless of which one is
/// mounted (splash vs the ready shell).
Widget orientationProbe(BuildContext context, Widget? child) {
  OrientationController.instance.setDeviceClass(
    isTablet:
        MediaQuery.sizeOf(context).shortestSide >=
        OrientationController.tabletShortestSide,
  );
  return child ?? const SizedBox.shrink();
}
