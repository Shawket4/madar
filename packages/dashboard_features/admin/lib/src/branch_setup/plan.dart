/// The branch plan: what hardware a branch has and how it talks (the web's
/// `features/branch-builder/plan.ts`).
///
/// Pure data and pure functions. The page edits a [BuilderPlan] locally
/// (with undo), checks it with [checkPlan] and saves it whole, because a plan
/// is only coherent as a whole. Pieces carry their own canvas position in the
/// floor's unbounded plane.
library;

import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' show BranchPlan;

typedef Nullable<T> = T? Function();

/// A slot: a POS (`pos`), a waiter tablet (`waiter`) or a kitchen screen
/// (`kitchen`).
class BuilderDevice {
  const BuilderDevice({
    required this.id,
    required this.kind,
    required this.name,
    this.receiptPrinterId,
    this.deviceId,
    required this.x,
    required this.y,
  });

  factory BuilderDevice.fromJson(Map<String, Object?> j) => BuilderDevice(
    id: j['id']! as String,
    kind: j['kind']! as String,
    name: j['name']! as String,
    receiptPrinterId: j['receipt_printer_id'] as String?,
    deviceId: j['device_id'] as String?,
    x: (j['x']! as num).toDouble(),
    y: (j['y']! as num).toDouble(),
  );

  final String id;
  final String kind;
  final String name;

  /// For a POS or waiter device: where its receipts print.
  final String? receiptPrinterId;

  /// The registered install that fills this slot.
  final String? deviceId;
  final double x;
  final double y;

  BuilderDevice copyWith({
    String? name,
    Nullable<String>? receiptPrinterId,
    Nullable<String>? deviceId,
    double? x,
    double? y,
  }) => BuilderDevice(
    id: id,
    kind: kind,
    name: name ?? this.name,
    receiptPrinterId: receiptPrinterId == null
        ? this.receiptPrinterId
        : receiptPrinterId(),
    deviceId: deviceId == null ? this.deviceId : deviceId(),
    x: x ?? this.x,
    y: y ?? this.y,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'name': name,
    'receipt_printer_id': receiptPrinterId,
    'device_id': deviceId,
    'x': x,
    'y': y,
  };
}

/// A receipt or kitchen printer, on the network or plugged into a device.
class BuilderPrinter {
  const BuilderPrinter({
    required this.id,
    required this.role,
    required this.name,
    required this.connection,
    this.brand,
    this.ip,
    this.port,
    required this.paperMm,
    this.hostDeviceId,
    required this.x,
    required this.y,
  });

  factory BuilderPrinter.fromJson(Map<String, Object?> j) => BuilderPrinter(
    id: j['id']! as String,
    role: j['role']! as String,
    name: j['name']! as String,
    connection: j['connection']! as String,
    brand: j['brand'] as String?,
    ip: j['ip'] as String?,
    port: (j['port'] as num?)?.toInt(),
    paperMm: (j['paper_mm']! as num).toInt(),
    hostDeviceId: j['host_device_id'] as String?,
    x: (j['x']! as num).toDouble(),
    y: (j['y']! as num).toDouble(),
  );

  final String id;
  final String role;
  final String name;
  final String connection;
  final String? brand;
  final String? ip;
  final int? port;
  final int paperMm;

  /// For a USB or Bluetooth printer: the device it is plugged into.
  final String? hostDeviceId;
  final double x;
  final double y;

  bool get network => connection == 'network';

  BuilderPrinter copyWith({
    String? name,
    String? connection,
    Nullable<String>? brand,
    Nullable<String>? ip,
    Nullable<int>? port,
    int? paperMm,
    Nullable<String>? hostDeviceId,
    double? x,
    double? y,
  }) => BuilderPrinter(
    id: id,
    role: role,
    name: name ?? this.name,
    connection: connection ?? this.connection,
    brand: brand == null ? this.brand : brand(),
    ip: ip == null ? this.ip : ip(),
    port: port == null ? this.port : port(),
    paperMm: paperMm ?? this.paperMm,
    hostDeviceId: hostDeviceId == null ? this.hostDeviceId : hostDeviceId(),
    x: x ?? this.x,
    y: y ?? this.y,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role,
    'name': name,
    'connection': connection,
    'brand': brand,
    'ip': ip,
    'port': port,
    'paper_mm': paperMm,
    'host_device_id': hostDeviceId,
    'x': x,
    'y': y,
  };
}

/// A kitchen section (a kitchen station on the server).
class BuilderSection {
  const BuilderSection({
    required this.id,
    required this.name,
    required this.isDefault,
    this.categoryIds = const [],
    this.screenIds = const [],
    this.printerIds = const [],
    required this.x,
    required this.y,
  });

  factory BuilderSection.fromJson(Map<String, Object?> j) => BuilderSection(
    id: j['id']! as String,
    name: j['name']! as String,
    isDefault: j['is_default']! as bool,
    categoryIds: [...?(j['category_ids'] as List?)?.cast<String>()],
    screenIds: [...?(j['screen_ids'] as List?)?.cast<String>()],
    printerIds: [...?(j['printer_ids'] as List?)?.cast<String>()],
    x: (j['x']! as num).toDouble(),
    y: (j['y']! as num).toDouble(),
  );

  final String id;
  final String name;
  final bool isDefault;
  final List<String> categoryIds;

  /// Kitchen screens this section's items show on.
  final List<String> screenIds;

  /// Kitchen printers this section's items print on.
  final List<String> printerIds;
  final double x;
  final double y;

  BuilderSection copyWith({
    String? name,
    bool? isDefault,
    List<String>? categoryIds,
    List<String>? screenIds,
    List<String>? printerIds,
    double? x,
    double? y,
  }) => BuilderSection(
    id: id,
    name: name ?? this.name,
    isDefault: isDefault ?? this.isDefault,
    categoryIds: categoryIds ?? this.categoryIds,
    screenIds: screenIds ?? this.screenIds,
    printerIds: printerIds ?? this.printerIds,
    x: x ?? this.x,
    y: y ?? this.y,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'is_default': isDefault,
    'category_ids': categoryIds,
    'screen_ids': screenIds,
    'printer_ids': printerIds,
    'x': x,
    'y': y,
  };
}

class BuilderPlan {
  const BuilderPlan({
    this.devices = const [],
    this.printers = const [],
    this.sections = const [],
    this.tillPrintsKitchen = false,
  });

  factory BuilderPlan.fromJson(Map<String, Object?> j) => BuilderPlan(
    devices: [
      for (final d in (j['devices'] as List?) ?? const [])
        BuilderDevice.fromJson((d as Map).cast()),
    ],
    printers: [
      for (final p in (j['printers'] as List?) ?? const [])
        BuilderPrinter.fromJson((p as Map).cast()),
    ],
    sections: [
      for (final s in (j['sections'] as List?) ?? const [])
        BuilderSection.fromJson((s as Map).cast()),
    ],
    tillPrintsKitchen: (j['till_prints_kitchen'] as bool?) ?? false,
  );

  static const BuilderPlan empty = BuilderPlan();

  final List<BuilderDevice> devices;
  final List<BuilderPrinter> printers;
  final List<BuilderSection> sections;

  /// Case 1: the till's receipt printer also prints kitchen chits.
  final bool tillPrintsKitchen;

  bool get isEmpty => devices.isEmpty && printers.isEmpty && sections.isEmpty;

  BuilderDevice? device(String? id) =>
      devices.firstWhereOrNull((d) => d.id == id);
  BuilderPrinter? printer(String? id) =>
      printers.firstWhereOrNull((p) => p.id == id);
  BuilderSection? section(String? id) =>
      sections.firstWhereOrNull((s) => s.id == id);

  BuilderPlan copyWith({
    List<BuilderDevice>? devices,
    List<BuilderPrinter>? printers,
    List<BuilderSection>? sections,
    bool? tillPrintsKitchen,
  }) => BuilderPlan(
    devices: devices ?? this.devices,
    printers: printers ?? this.printers,
    sections: sections ?? this.sections,
    tillPrintsKitchen: tillPrintsKitchen ?? this.tillPrintsKitchen,
  );

  BuilderPlan mapDevices(BuilderDevice Function(BuilderDevice d) f) =>
      copyWith(devices: [for (final d in devices) f(d)]);
  BuilderPlan mapPrinters(BuilderPrinter Function(BuilderPrinter p) f) =>
      copyWith(printers: [for (final p in printers) f(p)]);
  BuilderPlan mapSections(BuilderSection Function(BuilderSection s) f) =>
      copyWith(sections: [for (final s in sections) f(s)]);

  Map<String, Object?> toJson() => {
    'devices': [for (final d in devices) d.toJson()],
    'printers': [for (final p in printers) p.toJson()],
    'sections': [for (final s in sections) s.toJson()],
    'till_prints_kitchen': tillPrintsKitchen,
  };
}

const _eq = DeepCollectionEquality();

/// `samePlan`: equal in everything, a moved card included.
bool samePlan(BuilderPlan a, BuilderPlan b) =>
    identical(a, b) || _eq.equals(a.toJson(), b.toJson());

// ── Wire ──────────────────────────────────────────────────────────────────

BuilderPlan fromWire(BranchPlan p) => BuilderPlan.fromJson(p.toJson());

/// The wire shape is the plan itself; names are trimmed on the way out, a
/// network printer sends its trimmed IP (or none) and its port (9100 when
/// unset) and no host; a plugged-in one no IP and no port.
BranchPlan toWire(BuilderPlan plan) => BranchPlan.fromJson({
  'devices': [
    for (final d in plan.devices) {...d.toJson(), 'name': d.name.trim()},
  ],
  'printers': [
    for (final p in plan.printers)
      {
        ...p.toJson(),
        'name': p.name.trim(),
        'ip': p.network
            ? ((p.ip ?? '').trim().isEmpty ? null : p.ip!.trim())
            : null,
        'port': p.network ? p.port ?? 9100 : null,
        'host_device_id': p.network ? null : p.hostDeviceId,
      },
  ],
  'sections': [
    for (final s in plan.sections) {...s.toJson(), 'name': s.name.trim()},
  ],
  'till_prints_kitchen': plan.tillPrintsKitchen,
});

// ── Geometry ──────────────────────────────────────────────────────────────

/// Footprint of a piece, in canvas units.
const double kNodeW = 216;
const double kNodeH = 76;
const double kSectionH = 104;

/// The floor's grid and camera (`features/floor/util.ts`).
const double kGrid = 10;
const double kZoomMin = 0.1;
const double kZoomMax = 4;
const double kZoomStep = 1.25;
const double kFitPadding = 80;
const int kHistoryLimit = 100;

enum PieceKind { device, printer, section }

class PieceRef {
  const PieceRef(this.kind, this.id);

  factory PieceRef.parse(String key) {
    final i = key.indexOf(':');
    return PieceRef(
      PieceKind.values.byName(key.substring(0, i)),
      key.substring(i + 1),
    );
  }

  final PieceKind kind;
  final String id;

  String get key => '${kind.name}:$id';

  @override
  bool operator ==(Object other) =>
      other is PieceRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => key;
}

String pieceKey(PieceKind kind, String id) => '${kind.name}:$id';

class PieceBox {
  const PieceBox(this.key, this.x, this.y, this.w, this.h);

  final String key;
  final double x;
  final double y;
  final double w;
  final double h;

  double get cx => x + w / 2;
  double get cy => y + h / 2;
  bool contains(double px, double py) =>
      px >= x && px <= x + w && py >= y && py <= y + h;
}

List<PieceBox> boxesOf(BuilderPlan plan) => [
  for (final d in plan.devices)
    PieceBox(pieceKey(PieceKind.device, d.id), d.x, d.y, kNodeW, kNodeH),
  for (final p in plan.printers)
    PieceBox(pieceKey(PieceKind.printer, p.id), p.x, p.y, kNodeW, kNodeH),
  for (final s in plan.sections)
    PieceBox(pieceKey(PieceKind.section, s.id), s.x, s.y, kNodeW, kSectionH),
];

/// Moves pieces by key; unknown keys are ignored.
BuilderPlan movePieces(BuilderPlan plan, Map<String, ({double x, double y})> m) {
  ({double x, double y})? at(PieceKind k, String id) => m[pieceKey(k, id)];
  return plan.copyWith(
    devices: [
      for (final d in plan.devices)
        if (at(PieceKind.device, d.id) case final p?)
          d.copyWith(x: p.x, y: p.y)
        else
          d,
    ],
    printers: [
      for (final d in plan.printers)
        if (at(PieceKind.printer, d.id) case final p?)
          d.copyWith(x: p.x, y: p.y)
        else
          d,
    ],
    sections: [
      for (final d in plan.sections)
        if (at(PieceKind.section, d.id) case final p?)
          d.copyWith(x: p.x, y: p.y)
        else
          d,
    ],
  );
}

/// `snapTo`: to the grid when [on], else to a whole unit (JS `Math.round`).
double snapTo(double v, bool on, [double pitch = kGrid]) => on
    ? ((v / pitch) + 0.5).floorToDouble() * pitch
    : (v + 0.5).floorToDouble();

/// The world box a set of pieces occupies; each contributes the circle its
/// diagonal describes, as the floor's `boundsOf` does.
({double x, double y, double w, double h}) boundsOf(Iterable<PieceBox> items) {
  if (items.isEmpty) return (x: 0, y: 0, w: 1000, h: 700);
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final it in items) {
    final r = math.sqrt(it.w * it.w + it.h * it.h) / 2;
    minX = math.min(minX, it.cx - r);
    minY = math.min(minY, it.cy - r);
    maxX = math.max(maxX, it.cx + r);
    maxY = math.max(maxY, it.cy + r);
  }
  return (x: minX, y: minY, w: maxX - minX, h: maxY - minY);
}

double clampZoom(double z) => math.min(kZoomMax, math.max(kZoomMin, z));

// ── Links ─────────────────────────────────────────────────────────────────

enum LinkKind { shows, prints, receipt, host }

class PlanLink {
  const PlanLink(this.kind, this.from, this.to);

  final LinkKind kind;

  /// The piece the line starts at.
  final PieceRef from;
  final PieceRef to;

  @override
  bool operator ==(Object other) =>
      other is PlanLink &&
      other.kind == kind &&
      other.from.id == from.id &&
      other.to.id == to.id;

  @override
  int get hashCode => Object.hash(kind, from.id, to.id);
}

/// Every line the canvas draws.
List<PlanLink> linksOf(BuilderPlan plan) => [
  for (final d in plan.devices)
    if (d.receiptPrinterId != null)
      PlanLink(
        LinkKind.receipt,
        PieceRef(PieceKind.device, d.id),
        PieceRef(PieceKind.printer, d.receiptPrinterId!),
      ),
  for (final p in plan.printers)
    if (!p.network && p.hostDeviceId != null)
      PlanLink(
        LinkKind.host,
        PieceRef(PieceKind.printer, p.id),
        PieceRef(PieceKind.device, p.hostDeviceId!),
      ),
  for (final s in plan.sections) ...[
    for (final id in s.screenIds)
      PlanLink(
        LinkKind.shows,
        PieceRef(PieceKind.section, s.id),
        PieceRef(PieceKind.device, id),
      ),
    for (final id in s.printerIds)
      PlanLink(
        LinkKind.prints,
        PieceRef(PieceKind.section, s.id),
        PieceRef(PieceKind.printer, id),
      ),
  ],
];

bool _front(String kind) => kind == 'pos' || kind == 'waiter';

/// What a line dragged from [from] onto [to] would mean; null when the pair
/// makes no sense.
LinkKind? linkKindFor(BuilderPlan plan, PieceRef from, PieceRef to) {
  switch (from.kind) {
    case PieceKind.section:
      if (to.kind == PieceKind.device && plan.device(to.id)?.kind == 'kitchen') {
        return LinkKind.shows;
      }
      if (to.kind == PieceKind.printer &&
          plan.printer(to.id)?.role == 'kitchen') {
        return LinkKind.prints;
      }
      return null;
    case PieceKind.device:
      final d = plan.device(from.id);
      if (d == null) return null;
      if (_front(d.kind) &&
          to.kind == PieceKind.printer &&
          plan.printer(to.id)?.role == 'receipt') {
        return LinkKind.receipt;
      }
      if (d.kind == 'kitchen' && to.kind == PieceKind.section) {
        return LinkKind.shows;
      }
      return null;
    case PieceKind.printer:
      final p = plan.printer(from.id);
      if (p == null) return null;
      if (to.kind == PieceKind.device && !p.network) return LinkKind.host;
      if (to.kind == PieceKind.section && p.role == 'kitchen') {
        return LinkKind.prints;
      }
      if (to.kind == PieceKind.device && p.role == 'receipt') {
        final d = plan.device(to.id);
        if (d != null && _front(d.kind)) return LinkKind.receipt;
      }
      return null;
  }
}

/// Adds a link (idempotent; a receipt or host link replaces the previous
/// one). The same plan comes back only when the two can't be linked.
BuilderPlan addLink(BuilderPlan plan, PieceRef from, PieceRef to) {
  final kind = linkKindFor(plan, from, to);
  if (kind == null) return plan;
  String? idOf(PieceKind k) => from.kind == k
      ? from.id
      : to.kind == k
      ? to.id
      : null;
  final sectionId = idOf(PieceKind.section);
  final deviceId = idOf(PieceKind.device);
  final printerId = idOf(PieceKind.printer);
  return switch (kind) {
    LinkKind.shows => plan.mapSections(
      (s) =>
          s.id == sectionId &&
              deviceId != null &&
              !s.screenIds.contains(deviceId)
          ? s.copyWith(screenIds: [...s.screenIds, deviceId])
          : s,
    ),
    LinkKind.prints => plan.mapSections(
      (s) =>
          s.id == sectionId &&
              printerId != null &&
              !s.printerIds.contains(printerId)
          ? s.copyWith(printerIds: [...s.printerIds, printerId])
          : s,
    ),
    LinkKind.receipt => plan.mapDevices(
      (d) => d.id == deviceId ? d.copyWith(receiptPrinterId: () => printerId) : d,
    ),
    LinkKind.host => plan.mapPrinters(
      (p) => p.id == printerId ? p.copyWith(hostDeviceId: () => deviceId) : p,
    ),
  };
}

BuilderPlan removeLink(BuilderPlan plan, PlanLink link) => switch (link.kind) {
  LinkKind.shows => plan.mapSections(
    (s) => s.id == link.from.id
        ? s.copyWith(screenIds: [...s.screenIds]..remove(link.to.id))
        : s,
  ),
  LinkKind.prints => plan.mapSections(
    (s) => s.id == link.from.id
        ? s.copyWith(printerIds: [...s.printerIds]..remove(link.to.id))
        : s,
  ),
  LinkKind.receipt => plan.mapDevices(
    (d) => d.id == link.from.id ? d.copyWith(receiptPrinterId: () => null) : d,
  ),
  LinkKind.host => plan.mapPrinters(
    (p) => p.id == link.from.id ? p.copyWith(hostDeviceId: () => null) : p,
  ),
};

/// Removes pieces and every link that pointed at them; a removed catch-all
/// hands the role to the first remaining section.
BuilderPlan removePieces(BuilderPlan plan, Set<String> keys) {
  bool gone(PieceKind k, String? id) =>
      id != null && keys.contains(pieceKey(k, id));
  final sections = [
    for (final s in plan.sections)
      if (!gone(PieceKind.section, s.id)) s,
  ];
  if (sections.isNotEmpty && !sections.any((s) => s.isDefault)) {
    sections[0] = sections[0].copyWith(isDefault: true);
  }
  return BuilderPlan(
    tillPrintsKitchen: plan.tillPrintsKitchen,
    devices: [
      for (final d in plan.devices)
        if (!gone(PieceKind.device, d.id))
          gone(PieceKind.printer, d.receiptPrinterId)
              ? d.copyWith(receiptPrinterId: () => null)
              : d,
    ],
    printers: [
      for (final p in plan.printers)
        if (!gone(PieceKind.printer, p.id))
          gone(PieceKind.device, p.hostDeviceId)
              ? p.copyWith(hostDeviceId: () => null)
              : p,
    ],
    sections: [
      for (final s in sections)
        s.copyWith(
          screenIds: [
            for (final id in s.screenIds)
              if (!gone(PieceKind.device, id)) id,
          ],
          printerIds: [
            for (final id in s.printerIds)
              if (!gone(PieceKind.printer, id)) id,
          ],
        ),
    ],
  );
}

/// Gives a category to one section, taking it from any other ([sectionId]
/// null: to none).
BuilderPlan routeCategory(BuilderPlan plan, String categoryId, String? sectionId) =>
    routeCategories(plan, [categoryId], sectionId);

/// Gives many categories to one section at once (one undo step), or takes
/// them from it with null.
BuilderPlan routeCategories(
  BuilderPlan plan,
  List<String> categoryIds,
  String? sectionId,
) {
  final moving = categoryIds.toSet();
  return plan.mapSections((s) {
    final rest = [
      for (final c in s.categoryIds)
        if (!moving.contains(c)) c,
    ];
    return s.copyWith(
      categoryIds: s.id == sectionId ? [...rest, ...categoryIds] : rest,
    );
  });
}

BuilderPlan setDefaultSection(BuilderPlan plan, String sectionId) =>
    plan.mapSections((s) => s.copyWith(isDefault: s.id == sectionId));

// ── Setups ────────────────────────────────────────────────────────────────

enum Setup { till, tillPrinter, tillScreen, sections }

/// Which of the four cases a plan reads as; null for an empty plan.
Setup? setupOf(BuilderPlan plan) {
  if (plan.isEmpty) return null;
  if (plan.sections.isEmpty) return Setup.till;
  if (plan.sections.length > 1) return Setup.sections;
  final s = plan.sections.first;
  if (s.screenIds.isNotEmpty && s.printerIds.isEmpty) return Setup.tillScreen;
  if (s.printerIds.isNotEmpty && s.screenIds.isEmpty) {
    return Setup.tillPrinter;
  }
  return Setup.sections;
}

/// Canvas columns: front of house, kitchen sections, kitchen outputs.
const double _colFront = 0, _colSections = 340, _colOutputs = 680, _row = 120;

typedef SetupNames = ({
  String till,
  String receiptPrinter,
  String kitchen,
  String kitchenPrinter,
  String kitchenScreen,
  String sectionA,
  String sectionB,
  String screenA,
  String screenB,
});

/// A new plan for one of the four cases, named in the viewer's language.
BuilderPlan planForSetup(
  Setup setup,
  SetupNames names,
  List<String> categoryIds,
  String Function() newId,
) {
  final tillId = newId();
  final receiptId = newId();
  final devices = [
    BuilderDevice(
      id: tillId,
      kind: 'pos',
      name: names.till,
      receiptPrinterId: receiptId,
      x: _colFront,
      y: 0,
    ),
  ];
  final printers = [
    BuilderPrinter(
      id: receiptId,
      role: 'receipt',
      name: names.receiptPrinter,
      connection: 'usb',
      paperMm: 80,
      hostDeviceId: tillId,
      x: _colFront,
      y: _row * 1.5,
    ),
  ];
  if (setup == Setup.till) {
    return BuilderPlan(
      devices: devices,
      printers: printers,
      tillPrintsKitchen: true,
    );
  }
  if (setup == Setup.tillPrinter || setup == Setup.tillScreen) {
    final sectionId = newId();
    final outId = newId();
    if (setup == Setup.tillPrinter) {
      printers.add(
        BuilderPrinter(
          id: outId,
          role: 'kitchen',
          name: names.kitchenPrinter,
          connection: 'network',
          port: 9100,
          paperMm: 80,
          x: _colOutputs,
          y: 0,
        ),
      );
    } else {
      devices.add(
        BuilderDevice(
          id: outId,
          kind: 'kitchen',
          name: names.kitchenScreen,
          x: _colOutputs,
          y: 0,
        ),
      );
    }
    return BuilderPlan(
      devices: devices,
      printers: printers,
      sections: [
        BuilderSection(
          id: sectionId,
          name: names.kitchen,
          isDefault: true,
          categoryIds: [...categoryIds],
          screenIds: setup == Setup.tillScreen ? [outId] : const [],
          printerIds: setup == Setup.tillPrinter ? [outId] : const [],
          x: _colSections,
          y: 0,
        ),
      ],
    );
  }
  final a = newId(), b = newId(), sa = newId(), sb = newId();
  return BuilderPlan(
    devices: [
      ...devices,
      BuilderDevice(
        id: sa,
        kind: 'kitchen',
        name: names.screenA,
        x: _colOutputs,
        y: 0,
      ),
      BuilderDevice(
        id: sb,
        kind: 'kitchen',
        name: names.screenB,
        x: _colOutputs,
        y: _row * 1.5,
      ),
    ],
    printers: printers,
    sections: [
      BuilderSection(
        id: a,
        name: names.sectionA,
        isDefault: true,
        categoryIds: [...categoryIds],
        screenIds: [sa],
        x: _colSections,
        y: 0,
      ),
      BuilderSection(
        id: b,
        name: names.sectionB,
        isDefault: false,
        screenIds: [sb],
        x: _colSections,
        y: _row * 1.5,
      ),
    ],
  );
}

// ── Checks ────────────────────────────────────────────────────────────────

enum ProblemCode {
  sectionNoOutput,
  sectionNoName,
  sectionDuplicateName,
  noDefaultSection,
  printerNoHost,
  printerNoAddress,
  pieceNoName,
  posNoReceiptPrinter,
  screenNoSection,
  kitchenPrinterUnused,
  noPos,
}

class Problem {
  const Problem(this.code, this.blocking, this.piece);

  final ProblemCode code;

  /// Blocking problems would lose orders; saving waits for them.
  final bool blocking;
  final PieceRef? piece;
}

// No leading zeros ("192.168.1.05"): the server's parser refuses them.
final RegExp _ipv4 = RegExp(
  r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$',
);

bool isIpv4(String? s) => s != null && _ipv4.hasMatch(s.trim());

/// Every problem with a plan, blocking first (the server runs the same
/// blocking checks).
List<Problem> checkPlan(BuilderPlan plan) {
  final out = <Problem>[];
  void add(ProblemCode c, bool blocking, PieceRef? piece) =>
      out.add(Problem(c, blocking, piece));
  final names = <String, int>{};
  for (final s in plan.sections) {
    final n = s.name.trim().toLowerCase();
    if (n.isNotEmpty) names[n] = (names[n] ?? 0) + 1;
  }
  for (final s in plan.sections) {
    final ref = PieceRef(PieceKind.section, s.id);
    final n = s.name.trim().toLowerCase();
    if (n.isEmpty) {
      add(ProblemCode.sectionNoName, true, ref);
    } else if ((names[n] ?? 0) > 1) {
      add(ProblemCode.sectionDuplicateName, true, ref);
    }
    if (s.screenIds.isEmpty && s.printerIds.isEmpty) {
      add(ProblemCode.sectionNoOutput, true, ref);
    }
  }
  if (plan.sections.isNotEmpty &&
      plan.sections.where((s) => s.isDefault).length != 1) {
    add(ProblemCode.noDefaultSection, true, null);
  }
  for (final p in plan.printers) {
    final ref = PieceRef(PieceKind.printer, p.id);
    if (p.name.trim().isEmpty) add(ProblemCode.pieceNoName, true, ref);
    if (p.network && !isIpv4(p.ip)) {
      add(ProblemCode.printerNoAddress, true, ref);
    }
    if (!p.network && p.hostDeviceId == null) {
      add(ProblemCode.printerNoHost, true, ref);
    }
    if (p.role == 'kitchen' &&
        !plan.sections.any((s) => s.printerIds.contains(p.id))) {
      add(ProblemCode.kitchenPrinterUnused, false, ref);
    }
  }
  for (final d in plan.devices) {
    final ref = PieceRef(PieceKind.device, d.id);
    if (d.name.trim().isEmpty) add(ProblemCode.pieceNoName, true, ref);
    if (d.kind == 'pos' && d.receiptPrinterId == null) {
      add(ProblemCode.posNoReceiptPrinter, false, ref);
    }
    if (d.kind == 'kitchen' &&
        !plan.sections.any((s) => s.screenIds.contains(d.id))) {
      add(ProblemCode.screenNoSection, false, ref);
    }
  }
  if (!plan.devices.any((d) => d.kind == 'pos') &&
      (plan.printers.isNotEmpty || plan.sections.isNotEmpty)) {
    add(ProblemCode.noPos, false, null);
  }
  // A stable sort, blocking first (`Array.prototype.sort` is stable).
  return [...out.where((p) => p.blocking), ...out.where((p) => !p.blocking)];
}

/// Categories no section claims; they go to the catch-all.
List<String> unroutedCategories(BuilderPlan plan, List<String> categoryIds) {
  final routed = {for (final s in plan.sections) ...s.categoryIds};
  return [
    for (final c in categoryIds)
      if (!routed.contains(c)) c,
  ];
}

// ── Changes ───────────────────────────────────────────────────────────────

typedef PlanChange = ({
  List<PieceRef> added,
  List<PieceRef> removed,
  List<PieceRef> changed,
});

/// What saving [next] over [prev] adds, removes and changes; a move alone is
/// no change.
PlanChange diffPlans(BuilderPlan prev, BuilderPlan next) {
  final added = <PieceRef>[], removed = <PieceRef>[], changed = <PieceRef>[];
  void compare(
    PieceKind kind,
    Iterable<({String id, Map<String, Object?> json})> a,
    Iterable<({String id, Map<String, Object?> json})> b,
  ) {
    final before = {for (final it in a) it.id: it.json};
    final after = {for (final it in b) it.id: it.json};
    for (final e in after.entries) {
      final was = before[e.key];
      if (was == null) {
        added.add(PieceRef(kind, e.key));
      } else if (!_eq.equals(
        {...was, 'x': 0, 'y': 0},
        {...e.value, 'x': 0, 'y': 0},
      )) {
        changed.add(PieceRef(kind, e.key));
      }
    }
    for (final id in before.keys) {
      if (!after.containsKey(id)) removed.add(PieceRef(kind, id));
    }
  }

  Iterable<({String id, Map<String, Object?> json})> rows(
    Iterable<({String id, Map<String, Object?> Function() json})> it,
  ) => it.map((e) => (id: e.id, json: e.json()));
  compare(
    PieceKind.device,
    rows(prev.devices.map((d) => (id: d.id, json: d.toJson))),
    rows(next.devices.map((d) => (id: d.id, json: d.toJson))),
  );
  compare(
    PieceKind.printer,
    rows(prev.printers.map((d) => (id: d.id, json: d.toJson))),
    rows(next.printers.map((d) => (id: d.id, json: d.toJson))),
  );
  compare(
    PieceKind.section,
    rows(prev.sections.map((d) => (id: d.id, json: d.toJson))),
    rows(next.sections.map((d) => (id: d.id, json: d.toJson))),
  );
  return (added: added, removed: removed, changed: changed);
}

/// The kitchen routing mode a plan implies (the server's `routing_mode_for`).
String routingModeFor(BuilderPlan plan) {
  if (plan.sections.isEmpty) return plan.tillPrintsKitchen ? 'till' : 'off';
  if (!plan.sections.any((s) => s.screenIds.isNotEmpty)) return 'till';
  return plan.tillPrintsKitchen ? 'both' : 'kds';
}

/// The printers the server assembles come named in English ("Receipt
/// printer", "Grill printer"): those exact names read in the viewer's words;
/// a name someone typed stays.
BuilderPlan localizeServerNames(
  BuilderPlan plan,
  String receipt,
  String Function(String section) sectionPrinter,
) {
  final sectionOf = <String, String>{};
  for (final s in plan.sections) {
    for (final id in s.printerIds) {
      sectionOf.putIfAbsent(id, () => s.name);
    }
  }
  var changed = false;
  final printers = [
    for (final p in plan.printers)
      () {
        final section = sectionOf[p.id];
        final name = p.role == 'receipt' && p.name == 'Receipt printer'
            ? receipt
            : p.role == 'kitchen' &&
                  section != null &&
                  p.name == '$section printer'
            ? sectionPrinter(section)
            : p.name;
        if (name == p.name) return p;
        changed = true;
        return p.copyWith(name: name);
      }(),
  ];
  return changed ? plan.copyWith(printers: printers) : plan;
}

// ── Undo ──────────────────────────────────────────────────────────────────

/// Snapshots per gesture (`UndoHistory`).
class UndoHistory<T> {
  const UndoHistory({this.past = const [], this.future = const []});

  final List<T> past;
  final List<T> future;
}

UndoHistory<T> pushHistory<T>(UndoHistory<T> h, T snapshot) {
  final past = [...h.past, snapshot];
  return UndoHistory(
    past: past.length > kHistoryLimit
        ? past.sublist(past.length - kHistoryLimit)
        : past,
  );
}

({T value, UndoHistory<T> history})? applyUndo<T>(UndoHistory<T> h, T now) =>
    h.past.isEmpty
    ? null
    : (
        value: h.past.last,
        history: UndoHistory(
          past: h.past.sublist(0, h.past.length - 1),
          future: [now, ...h.future],
        ),
      );

({T value, UndoHistory<T> history})? applyRedo<T>(UndoHistory<T> h, T now) =>
    h.future.isEmpty
    ? null
    : (
        value: h.future.first,
        history: UndoHistory(
          past: [...h.past, now],
          future: h.future.sublist(1),
        ),
      );
