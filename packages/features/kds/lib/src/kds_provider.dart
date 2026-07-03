/// Kitchen-board state — the Riverpod spine behind the kitchen display
/// screen, keyed by the device's bound station (null = the all-station expo
/// board).
/// The screen triggers loads on mount / realtime tick / safety poll; bump
/// and recall never move `app_route()`, so no shell refresh is needed here.
library;

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Family TYPE annotations moved to the misc library in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Immutable board state: outstanding tickets + the station directory.
class KdsState {
  const KdsState({this.tickets = const [], this.stations = const []});

  /// Outstanding tickets for the bound station (or every station).
  final List<KdsTicketView> tickets;

  /// The branch's kitchen stations — resolves the header's station name.
  final List<KdsStationView> stations;

  /// The bound station's display name, or null when unknown (the header
  /// falls back to the localized board title).
  String? stationName(String? stationId) {
    if (stationId == null) return null;
    for (final station in stations) {
      if (station.id == stationId) return station.name;
    }
    return null;
  }

  /// Copy with the given fields replaced.
  KdsState copyWith({
    List<KdsTicketView>? tickets,
    List<KdsStationView>? stations,
  }) {
    return KdsState(
      tickets: tickets ?? this.tickets,
      stations: stations ?? this.stations,
    );
  }
}

/// The board controller, one per station id (the family arg).
class KdsNotifier extends Notifier<KdsState> {
  /// Creates the notifier for one family [arg].
  KdsNotifier(this.arg);

  /// The bound station id (null = the all-station expo board).
  final String? arg;

  MadarBridge get _bridge => ref.read(bridgeProvider);

  @override
  KdsState build() => const KdsState();

  /// Fetch the board. A failed fetch keeps the last good board on screen
  /// (the natives' runCatching — a blip never blanks a busy kitchen).
  Future<void> load() async {
    try {
      final tickets = await _bridge.kdsList(stationId: arg);
      state = state.copyWith(tickets: tickets);
    } on Object {
      // Keep the previous tickets.
    }
  }

  /// Fetch the station directory (names the header).
  Future<void> loadStations() async {
    try {
      final stations = await _bridge.kdsListStations();
      state = state.copyWith(stations: stations);
    } on Object {
      // Keep the previous directory.
    }
  }

  /// Toggle one line's done marker: bump ⇄ recall (kdsBump / kdsUnbump),
  /// then reload. Failures are silent — the next tick reconciles.
  Future<void> toggleLine(KdsLineView line) async {
    try {
      if (line.bumped) {
        await _bridge.kdsUnbump(itemId: line.id);
      } else {
        await _bridge.kdsBump(itemId: line.id);
      }
      await load();
    } on Object {
      // The board reloads on the next tick / poll.
    }
  }
}

/// The kitchen board's state provider, keyed by station id (null = expo).
final NotifierProviderFamily<KdsNotifier, KdsState, String?> kdsProvider =
    NotifierProvider.family<KdsNotifier, KdsState, String?>(KdsNotifier.new);
