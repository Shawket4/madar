import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Native Bonjour (NWBrowser/NetService on Apple, NsdManager on Android) for
/// the LAN relay.
///
/// iOS blocks the core's raw mDNS multicast and UDP broadcast beacon without
/// Apple's restricted multicast entitlement, so an iPad never found a peer.
/// The system's own Bonjour needs only the `NSBonjourServices` +
/// `NSLocalNetworkUsageDescription` Info.plist keys the app already declares.
///
/// Advertises `_madar._tcp` with the same TXT keys the core's mDNS advert
/// carries, browses for peers, and hands each resolved peer to the core
/// (`lanNotePeer`), which filters by branch and skips this device. Resolved
/// peers are re-noted every [renoteEvery] so the core's TTL keeps them while
/// they are still advertised. Sequencing only; no decision lives here.
class LanBonjour {
  LanBonjour({required MadarBridge bridge}) : _bridge = bridge;

  static const serviceType = '_madar._tcp';

  /// Below the core's 12 s peer TTL.
  static const renoteEvery = Duration(seconds: 4);

  final MadarBridge _bridge;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  // Cancelled in _stopDiscovery.
  // ignore: cancel_subscriptions
  StreamSubscription<BonsoirDiscoveryEvent>? _events;
  Future<void> _serial = Future<void>.value();
  Timer? _renote;
  LanAdvertView? _advertised;

  /// Resolved peers by service name.
  final Map<String, BonsoirService> _peers = {};

  /// Start (or refresh) advertising and browsing for the running relay. Safe to
  /// call repeatedly: an unchanged advert is left alone.
  Future<void> ensure() => _serial = _serial.then((_) => _ensure());

  Future<void> _ensure() async {
    final LanAdvertView? advert;
    try {
      advert = _bridge.lanAdvert();
    } on Object {
      return;
    }
    if (advert == null) {
      await _stopAll();
      return;
    }
    if (advert != _advertised) await _advertise(advert);
    if (_discovery == null) await _browse();
  }

  Future<void> _advertise(LanAdvertView advert) async {
    await _stopBroadcast();
    _advertised = advert;
    // A name distinct from the core's own mDNS instance (`madar-<id>`), so the
    // two adverts on a desktop never collide and get renamed.
    final service = BonsoirService(
      name: 'madar-n-${advert.deviceId}',
      type: serviceType,
      port: advert.tcpPort,
      attributes: {
        'device_id': advert.deviceId,
        'branch_id': advert.branchId,
        'role': advert.role,
        'station_id': advert.stationId ?? '',
        'device_code': advert.deviceCode ?? '',
        'tcp_port': '${advert.tcpPort}',
      },
    );
    try {
      final broadcast = _broadcast = BonsoirBroadcast(
        service: service,
        printLogs: false,
      );
      await broadcast.initialize();
      await broadcast.start();
    } on Object {
      // No plugin (tests), or the OS refused: the core's other discovery
      // layers and a manual peer still work.
      _broadcast = null;
      _advertised = null;
    }
  }

  Future<void> _browse() async {
    try {
      final discovery = _discovery = BonsoirDiscovery(
        type: serviceType,
        printLogs: false,
      );
      await discovery.initialize();
      _events = discovery.eventStream?.listen(
        (event) => _onEvent(discovery, event),
      );
      await discovery.start();
      _renote ??= Timer.periodic(renoteEvery, (_) => _noteAll());
    } on Object {
      await _stopDiscovery();
    }
  }

  void _onEvent(BonsoirDiscovery discovery, BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent(:final service):
        unawaited(
          service.resolve(discovery.serviceResolver).catchError((Object _) {}),
        );
      case BonsoirDiscoveryServiceResolvedEvent(:final service):
      case BonsoirDiscoveryServiceUpdatedEvent(:final service):
        _peers[service.name] = service;
        _note(service);
      case BonsoirDiscoveryServiceLostEvent(:final service):
        // Stop re-noting; the core's TTL drops it within seconds.
        _peers.remove(service.name);
      default:
        break;
    }
  }

  void _noteAll() => _peers.values.toList().forEach(_note);

  void _note(BonsoirService service) {
    final txt = service.attributes;
    final host = pickHost(service.hostAddresses);
    final deviceId = txt['device_id'] ?? '';
    if (host == null || deviceId.isEmpty) return;
    final port = int.tryParse(txt['tcp_port'] ?? '') ?? service.port;
    try {
      _bridge.lanNotePeer(
        deviceId: deviceId,
        branchId: txt['branch_id'] ?? '',
        host: host,
        port: port,
        role: txt['role'] ?? '',
        stationId: txt['station_id'],
        deviceCode: txt['device_code'],
      );
    } on Object {
      // The relay stopped between events; the next ensure() restarts us.
    }
  }

  /// Prefer a routable IPv4 address; fall back to IPv6 (not link-local).
  static String? pickHost(List<String> addresses) {
    InternetAddress? v6;
    for (final raw in addresses) {
      final address = InternetAddress.tryParse(raw);
      if (address == null || address.isLoopback) continue;
      if (address.type == InternetAddressType.IPv4) return address.address;
      if (!address.isLinkLocal) v6 ??= address;
    }
    return v6?.address;
  }

  Future<void> stop() => _serial = _serial.then((_) => _stopAll());

  Future<void> _stopAll() async {
    await _stopBroadcast();
    await _stopDiscovery();
  }

  Future<void> _stopBroadcast() async {
    final broadcast = _broadcast;
    _broadcast = null;
    _advertised = null;
    try {
      await broadcast?.stop();
    } on Object {
      // Already gone.
    }
  }

  Future<void> _stopDiscovery() async {
    _renote?.cancel();
    _renote = null;
    _peers.clear();
    final events = _events;
    _events = null;
    final discovery = _discovery;
    _discovery = null;
    try {
      await events?.cancel();
      await discovery?.stop();
    } on Object {
      // Already gone.
    }
  }
}
