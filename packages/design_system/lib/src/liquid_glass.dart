/// Whether this device may wear Apple's Liquid Glass, and nothing else.
///
/// The effect belongs to iOS 26. Drawn anywhere else it is not a nod to the
/// platform, it is a Flutter app pretending — and on Android, where the system
/// has its own material language, it reads as a skin somebody applied rather
/// than as the OS.
///
/// ## Why this is a gate and not the effect
///
/// The renderer package is a DEV PRELEASE (`0.2.0-dev.4`, last published ten
/// months ago) whose own README says it "should not be blindly added to
/// production apps". It needs Impeller, it is expensive enough that its own
/// guidance is to keep the glass area small and the animated shapes few, and
/// it carries a known memory spike from a Flutter texture-disposal bug.
///
/// This is a till. It runs all day on cheap tablets, it is the thing between a
/// queue of customers and their food, and a frame drop at the tender screen
/// costs a shop more than a finish is worth. So the decision of WHETHER to
/// render glass is separated from the rendering, and lives here, where it can
/// be answered once and turned off everywhere in one line.
///
/// Ask [LiquidGlass.isAvailable] before building a glass surface; build the
/// ordinary surface otherwise. Never let a screen exist only in its glass
/// form — every one of them has to be complete without it, because most of the
/// devices running this app will never see it.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// The platform test, answered once.
abstract final class LiquidGlass {
  /// The iOS version Liquid Glass arrived in.
  static const int _firstVersion = 26;

  /// Master switch. Set `false` to take the effect off every surface at once
  /// without touching a single screen — which is the point of having it.
  ///
  /// It is the reason a shop reporting jank can be answered in one build
  /// rather than by unpicking the finish from a dozen widgets.
  static bool enabled = true;

  static bool? _cached;

  /// `true` only on iOS 26 or newer, with the switch on.
  ///
  /// Cached: `Platform.operatingSystemVersion` parses a string, and this is
  /// asked on every build of every chrome surface.
  static bool get isAvailable {
    if (!enabled) return false;
    return _cached ??= _detect();
  }

  /// Force the cached answer, for tests that must ask the question for a
  /// device they are not running on.
  ///
  /// A method rather than a setter, and named for what it does: assigning to
  /// something called `available` would read as "this device has glass", when
  /// what it actually does is stop [isAvailable] ever asking the platform.
  @visibleForTesting
  // A setter would read as "this device has glass", which is not what this is.
  // ignore: use_setters_to_change_properties
  static void debugOverride({required bool? available}) => _cached = available;

  static bool _detect() {
    if (kIsWeb) return false;
    if (!Platform.isIOS) return false;
    return majorVersionOf(Platform.operatingSystemVersion) >= _firstVersion;
  }

  /// The major version in a `Platform.operatingSystemVersion` string.
  ///
  /// iOS reports something like `Version 26.0.1 (Build 23A344)`, but the shape
  /// is not contractual and has changed before. So this takes the FIRST run of
  /// digits it finds and nothing more, and answers `0` when there is none —
  /// which reads as "not iOS 26", the safe side of the only decision it feeds.
  @visibleForTesting
  static int majorVersionOf(String raw) {
    final match = RegExp(r'\d+').firstMatch(raw);
    if (match == null) return 0;
    return int.tryParse(match.group(0)!) ?? 0;
  }
}
