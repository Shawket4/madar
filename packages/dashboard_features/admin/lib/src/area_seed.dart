/// The admin area's own mock data, shared by its units so their numbers
/// agree, on top of the core seed (`package:dashboard_api/mock.dart`: Sabah
/// Coffee's four branches, its people, its five system roles):
///
/// - two more organizations for the platform admin's Organizations page and
///   the user dialog's organization select: Layali Bistro (a restaurant,
///   active, set-up not finished) and Qahwa Corner (a café, switched off),
///   each with one branch and an owner;
/// - Sabah's devices (every branch's `T1` "Counter 1" is the till the core
///   seed's orders were rung on), activation codes in every state, and the
///   clients the server has seen (Devices);
/// - flagged offline acts and wrong-branch PINs (Review);
/// - the org templates (the provision wizard) and the ask-a-manager policy
///   (Roles & Permissions);
/// - each person's branch assignments (Users ▸ Branch access).
///
/// [loadAdminSeed] puts it into a [MockDb] once; units read the tables by
/// [AdminTables] and may add rows in their own mock files.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import 'shared/capability_catalog.dart' show approvalCapabilities;

/// The tables this seed fills (beyond the core's `orgs`, `branches`,
/// `users`, `roles`).
abstract final class AdminTables {
  static const String devices = 'devices';
  static const String activationCodes = 'activation_codes';
  static const String clientVersions = 'client_versions';

  /// `ReplayFlag` rows; their `id` is an int, so find them with `where`.
  static const String flags = 'replay_flags';

  /// `OrgTemplate` rows keyed by `key` (no `id`).
  static const String templates = 'org_templates';

  /// `PolicyEntry` rows of Sabah (`{capability, ask_manager, org_id}`).
  static const String policy = 'authz_policy';

  /// `{id, user_id, branch_id}` rows: who may work at which branch.
  static const String userBranches = 'user_branches';
}

/// Stable ids and the rows themselves.
abstract final class AdminSeed {
  // ── more organizations ────────────────────────────────────────────────

  static final String layaliOrg = mockUuid('org:layali');
  static final String qahwaOrg = mockUuid('org:qahwa');
  static final String gardenCity = mockUuid('branch:layali-garden-city');
  static final String smouha = mockUuid('branch:qahwa-smouha');
  static final String layaliOwner = SeedIds.user('mona');
  static final String qahwaOwner = SeedIds.user('sherif');

  static final DateTime _now = MockClock.defaultNow;

  static DateTime _ago({int days = 0, int hours = 0, int minutes = 0}) =>
      _now.subtract(Duration(days: days, hours: hours, minutes: minutes));

  static List<Org> get orgs => [
    Org(
      id: layaliOrg,
      name: 'Layali Bistro',
      slug: 'layali-bistro',
      currencyCode: 'EGP',
      timezone: MockClock.timezone,
      taxRate: 0.14,
      taxInclusive: false,
      serviceChargeRate: 0.12,
      serviceChargeTaxable: true,
      requireTableForOrders: true,
      customBranding: false,
      isActive: true,
      modules: const ['pos', 'dawam'],
      receiptFooter: 'Shukran — we hope to see you again soon.',
      socialLinks: const {'instagram': 'https://instagram.com/layalibistro'},
    ),
    Org(
      id: qahwaOrg,
      name: 'Qahwa Corner',
      slug: 'qahwa-corner',
      currencyCode: 'EGP',
      timezone: MockClock.timezone,
      taxRate: 0.14,
      taxInclusive: true,
      serviceChargeRate: 0,
      serviceChargeTaxable: true,
      requireTableForOrders: false,
      customBranding: false,
      isActive: false,
      modules: const ['pos'],
      socialLinks: const {},
    ),
  ];

  static List<Branch> get branches => [
    Branch(
      id: gardenCity,
      orgId: layaliOrg,
      name: 'Garden City',
      code: 'GC',
      address: '12 Kasr El Nil St, Garden City, Cairo',
      phone: '+20 2 2794 5510',
      timezone: MockClock.timezone,
      isActive: true,
      oldBillHours: 4,
      standardFloat: 150000,
      createdAt: DateTime.utc(2026, 8, 1, 9),
      updatedAt: DateTime.utc(2026, 8, 1, 9),
    ),
    Branch(
      id: smouha,
      orgId: qahwaOrg,
      name: 'Smouha',
      code: 'SM',
      address: 'Victor Emmanuel Sq, Smouha, Alexandria',
      phone: '+20 3 4250 0187',
      timezone: MockClock.timezone,
      isActive: false,
      oldBillHours: 3,
      createdAt: DateTime.utc(2026, 3, 1, 9),
      updatedAt: DateTime.utc(2026, 7, 15, 9),
    ),
  ];

  static List<UserPublic> get owners => [
    UserPublic(
      id: layaliOwner,
      name: 'Mona Aziz',
      email: 'mona@layali.test',
      phone: '+201223334455',
      role: UserRole.orgAdmin,
      orgId: layaliOrg,
      isActive: true,
    ),
    UserPublic(
      id: qahwaOwner,
      name: 'Sherif Nassar',
      email: 'sherif@qahwa.test',
      phone: '+201224445566',
      role: UserRole.orgAdmin,
      orgId: qahwaOrg,
      isActive: false,
    ),
  ];

  // ── devices ───────────────────────────────────────────────────────────

  /// A device's id by branch key and code; `deviceId('zamalek', 'T1')` is
  /// the till the core seed's Zamalek orders carry.
  static String deviceId(String branchKey, String code) =>
      mockUuid('device:$branchKey:$code');

  static Device _device(
    String branchKey,
    String code, {
    required DeviceKind kind,
    String? label,
    String? platform,
    String? appVersion,
    required DateTime firstSeen,
    required DateTime lastSeen,
    DateTime? retiredAt,
    bool conflict = false,
    String? id,
  }) => Device(
    id: id ?? deviceId(branchKey, code),
    orgId: SeedIds.sabahOrg,
    branchId: MockSeed.branchIdOf(branchKey),
    code: code,
    codeConflict: conflict,
    kind: kind,
    label: label,
    platform: platform,
    appVersion: appVersion,
    firstSeenAt: firstSeen,
    lastSeenAt: lastSeen,
    retiredAt: retiredAt,
  );

  /// Sabah's devices: every branch's counter till, Zamalek's second till,
  /// kitchen screen and two waiter tablets, New Cairo's two tablets that
  /// ended up with the same code, and Maadi's retired iPad.
  static List<Device> get devices => [
    _device(
      'heliopolis',
      'T1',
      kind: DeviceKind.pos,
      label: 'Counter 1',
      platform: 'android',
      appVersion: '0.12.4',
      firstSeen: DateTime.utc(2025, 12, 6, 8),
      lastSeen: _ago(minutes: 12),
    ),
    _device(
      'heliopolis',
      'K1',
      kind: DeviceKind.kds,
      label: 'Kitchen screen',
      platform: 'linux',
      appVersion: '0.4.2',
      firstSeen: DateTime.utc(2026, 2, 2, 8),
      lastSeen: _ago(minutes: 3),
    ),
    _device(
      'maadi',
      'T1',
      kind: DeviceKind.pos,
      label: 'Counter 1',
      platform: 'ios',
      appVersion: '0.13.0',
      firstSeen: DateTime.utc(2026, 8, 20, 7),
      lastSeen: _ago(minutes: 8),
    ),
    _device(
      'maadi',
      'T9',
      kind: DeviceKind.pos,
      label: 'Old counter iPad',
      platform: 'ios',
      appVersion: '0.9.1',
      firstSeen: DateTime.utc(2026, 1, 15, 7),
      lastSeen: DateTime.utc(2026, 8, 19, 18, 40),
      retiredAt: DateTime.utc(2026, 8, 20, 6, 55),
    ),
    _device(
      'new-cairo',
      'T1',
      kind: DeviceKind.pos,
      label: 'Counter 1',
      platform: 'ios',
      appVersion: '0.13.0',
      firstSeen: DateTime.utc(2026, 3, 2, 8),
      lastSeen: _ago(minutes: 5),
    ),
    _device(
      'new-cairo',
      'T2',
      kind: DeviceKind.pos,
      label: 'Drive-through',
      platform: 'android',
      appVersion: '0.12.4',
      firstSeen: DateTime.utc(2026, 5, 11, 8),
      lastSeen: _ago(hours: 1, minutes: 20),
      conflict: true,
    ),
    _device(
      'new-cairo',
      'T2',
      id: deviceId('new-cairo', 'T2-b'),
      kind: DeviceKind.pos,
      label: 'Counter 2',
      platform: 'android',
      appVersion: '0.13.0',
      firstSeen: DateTime.utc(2026, 10, 6, 9),
      lastSeen: _ago(minutes: 40),
      conflict: true,
    ),
    _device(
      'zamalek',
      'T1',
      kind: DeviceKind.pos,
      label: 'Counter 1',
      platform: 'ios',
      appVersion: '0.13.0',
      firstSeen: DateTime.utc(2026, 3, 1, 8),
      lastSeen: _ago(minutes: 2),
    ),
    _device(
      'zamalek',
      'T2',
      kind: DeviceKind.pos,
      label: 'Counter 2',
      platform: 'android',
      appVersion: '0.13.0',
      firstSeen: DateTime.utc(2026, 4, 12, 8),
      lastSeen: _ago(minutes: 26),
    ),
    _device(
      'zamalek',
      'K1',
      kind: DeviceKind.kds,
      label: 'Kitchen screen',
      platform: 'linux',
      appVersion: '0.4.2',
      firstSeen: DateTime.utc(2026, 3, 2, 9),
      lastSeen: _ago(minutes: 1),
    ),
    _device(
      'zamalek',
      'W1',
      kind: DeviceKind.waiter,
      label: 'Floor tablet',
      platform: 'android',
      appVersion: '0.13.0',
      firstSeen: DateTime.utc(2026, 4, 1, 8),
      lastSeen: _ago(minutes: 15),
    ),
    _device(
      'zamalek',
      'W2',
      kind: DeviceKind.waiter,
      label: 'Terrace tablet',
      platform: 'ios',
      appVersion: '0.12.4',
      firstSeen: DateTime.utc(2026, 6, 10, 8),
      lastSeen: _ago(days: 1, hours: 2),
    ),
  ];

  // ── activation codes ──────────────────────────────────────────────────

  static ActivationCode _code(
    String branchKey,
    String code, {
    required DeviceKind kind,
    required ActivationCodeState state,
    required DateTime created,
    String? label,
    DateTime? usedAt,
    String? usedBy,
    DateTime? revokedAt,
  }) => ActivationCode(
    id: mockUuid('activation-code:$code'),
    branchId: MockSeed.branchIdOf(branchKey),
    code: code,
    kind: kind,
    label: label,
    state: state,
    createdAt: created,
    expiresAt: created.add(const Duration(hours: 24)),
    usedAt: usedAt,
    usedByDevice: usedBy,
    revokedAt: revokedAt,
  );

  /// Codes in every state: free (issued this morning), used, expired and
  /// withdrawn.
  static List<ActivationCode> get activationCodes => [
    _code(
      'zamalek',
      '40721958',
      kind: DeviceKind.waiter,
      label: 'Terrace tablet 2',
      state: ActivationCodeState.free,
      created: _ago(minutes: 35),
    ),
    _code(
      'zamalek',
      '18364052',
      kind: DeviceKind.kds,
      label: 'Kitchen screen',
      state: ActivationCodeState.used,
      created: DateTime.utc(2026, 3, 2, 8, 40),
      usedAt: DateTime.utc(2026, 3, 2, 9),
      usedBy: deviceId('zamalek', 'K1'),
    ),
    _code(
      'zamalek',
      '77219034',
      kind: DeviceKind.pos,
      state: ActivationCodeState.expired,
      created: DateTime.utc(2026, 9, 30, 8),
    ),
    _code(
      'zamalek',
      '55102846',
      kind: DeviceKind.pos,
      label: 'Front counter',
      state: ActivationCodeState.revoked,
      created: DateTime.utc(2026, 9, 20, 7, 10),
      revokedAt: DateTime.utc(2026, 9, 20, 7, 45),
    ),
    _code(
      'new-cairo',
      '63018245',
      kind: DeviceKind.pos,
      label: 'Counter 3',
      state: ActivationCodeState.free,
      created: _ago(hours: 3),
    ),
    _code(
      'new-cairo',
      '29475103',
      kind: DeviceKind.pos,
      label: 'Counter 2',
      state: ActivationCodeState.used,
      created: DateTime.utc(2026, 10, 6, 8, 30),
      usedAt: DateTime.utc(2026, 10, 6, 9),
      usedBy: deviceId('new-cairo', 'T2-b'),
    ),
    _code(
      'maadi',
      '84620197',
      kind: DeviceKind.pos,
      label: 'Counter 1',
      state: ActivationCodeState.used,
      created: DateTime.utc(2026, 8, 20, 6, 30),
      usedAt: DateTime.utc(2026, 8, 20, 7),
      usedBy: deviceId('maadi', 'T1'),
    ),
    _code(
      'heliopolis',
      '31958402',
      kind: DeviceKind.kds,
      state: ActivationCodeState.expired,
      created: DateTime.utc(2026, 9, 14, 9),
    ),
  ];

  // ── clients the server has seen ───────────────────────────────────────

  static const Map<String, String> _branchNames = {
    'heliopolis': 'Heliopolis',
    'maadi': 'Maadi',
    'new-cairo': 'New Cairo',
    'zamalek': 'Zamalek',
  };

  /// One row per signed-in device (older 0.12.x tablets still call a
  /// pre-rework path now and then) and two clients with no device.
  static List<ClientSeen> get clientVersions {
    ClientSeen of(
      Device d, {
      DateTime? legacyAt,
      List<String> kinds = const [],
    }) {
      final branchKey = _branchNames.keys.firstWhere(
        (k) => MockSeed.branchIdOf(k) == d.branchId,
      );
      final app = d.kind == DeviceKind.kds ? 'madar-kds' : 'madar-pos';
      return ClientSeen(
        deviceId: d.id,
        deviceCode: d.code,
        client: '$app/${d.appVersion} (${d.platform})',
        appVersion: d.appVersion,
        branchId: d.branchId,
        branchName: _branchNames[branchKey],
        firstSeenAt: d.firstSeenAt,
        lastSeenAt: d.lastSeenAt,
        lastLegacyAt: legacyAt,
        lastLegacyKind: kinds.isEmpty ? null : kinds.first,
        lastLegacyPath: kinds.isEmpty
            ? null
            : kinds.first == 'legacy_shifts_route'
            ? '/shifts/branches/${d.branchId}/open'
            : '/sync/replay',
        legacyKinds: kinds,
      );
    }

    final live = [
      for (final d in devices)
        if (d.retiredAt == null) d,
    ];
    return [
      for (final d in live)
        if (d.appVersion == '0.12.4')
          of(
            d,
            legacyAt: d.lastSeenAt.subtract(const Duration(hours: 2)),
            kinds: const ['legacy_shifts_route', 'replay_shift_id_field'],
          )
        else
          of(d),
      ClientSeen(
        client: 'madar-pos/0.9.1 (android)',
        appVersion: '0.9.1',
        branchId: SeedIds.heliopolis,
        branchName: 'Heliopolis',
        firstSeenAt: DateTime.utc(2026, 6, 2, 8),
        lastSeenAt: _ago(days: 41),
        lastLegacyAt: _ago(days: 41),
        lastLegacyKind: 'legacy_shifts_route',
        lastLegacyPath: '/shifts/branches/${SeedIds.heliopolis}/open',
        legacyKinds: const ['legacy_shifts_route'],
      ),
      ClientSeen(
        client: 'Dart/3.9 (dart:io)',
        firstSeenAt: _ago(days: 3),
        lastSeenAt: _ago(hours: 6),
        legacyKinds: const [],
      ),
    ];
  }

  // ── flagged acts (Review) ─────────────────────────────────────────────

  static ReplayFlag _flag(
    int id,
    String personKey,
    String name,
    String branchKey, {
    required String op,
    required String capability,
    required String reason,
    required DateTime occurred,
    Duration offline = const Duration(minutes: 20),
    DateTime? reviewedAt,
    String? reviewedBy,
  }) => ReplayFlag(
    id: id,
    authorId: SeedIds.user(personKey),
    authorName: name,
    branchId: MockSeed.branchIdOf(branchKey),
    op: op,
    capability: capability,
    reason: reason,
    occurredAt: occurred,
    createdAt: occurred.add(offline),
    reviewedAt: reviewedAt,
    reviewedBy: reviewedBy,
  );

  /// Six open flags (the default list) and two already reviewed (shown with
  /// "Show reviewed").
  static List<ReplayFlag> get flags => [
    _flag(
      1,
      'hana',
      'Hana Mostafa',
      'maadi',
      op: 'VoidOrder',
      capability: 'orders.void',
      reason: 'unauthorized_offline',
      occurred: _ago(hours: 1, minutes: 20),
    ),
    _flag(
      2,
      'mariam',
      'Mariam Fathy',
      'zamalek',
      op: 'CreateOrder',
      capability: 'orders.staff_drink.record:comp_mismatch',
      reason: 'stale_snapshot',
      occurred: _ago(days: 1, hours: 3),
    ),
    _flag(
      3,
      'youssef',
      'Youssef Samir',
      'zamalek',
      op: 'VoidOrder',
      capability: 'orders.void',
      reason: 'stale_snapshot',
      occurred: _ago(days: 1, hours: 5),
      offline: const Duration(hours: 2),
    ),
    _flag(
      4,
      'ziad',
      'Ziad Amr',
      'heliopolis',
      op: 'PinSignIn',
      capability: 'pos:sign_in',
      reason: 'pin_wrong_branch',
      occurred: _ago(days: 2, hours: 1),
      offline: Duration.zero,
    ),
    _flag(
      5,
      'ali',
      'Ali Hassan',
      'heliopolis',
      op: 'CreateOrder',
      capability: 'orders.staff_drink.record:overspent',
      reason: 'stale_snapshot',
      occurred: _ago(days: 3, hours: 4),
    ),
    _flag(
      6,
      'omar',
      'Omar Khaled',
      'new-cairo',
      op: 'CreateOrder',
      capability: 'orders.discount.manual_percent',
      reason: 'unauthorized_offline',
      occurred: _ago(days: 4, hours: 2),
      offline: const Duration(hours: 1, minutes: 10),
    ),
    _flag(
      7,
      'farida',
      'Farida Wael',
      'heliopolis',
      op: 'RefundOrder',
      capability: 'refunds.create',
      reason: 'stale_snapshot',
      occurred: DateTime.utc(2026, 9, 27, 15, 30),
      reviewedAt: DateTime.utc(2026, 9, 28, 8, 5),
      reviewedBy: SeedIds.user('rana'),
    ),
    _flag(
      8,
      'salma',
      'Salma Nabil',
      'new-cairo',
      op: 'CashMovement',
      capability: 'till.operate',
      reason: 'unauthorized_offline',
      occurred: DateTime.utc(2026, 10, 2, 17, 10),
      reviewedAt: DateTime.utc(2026, 10, 3, 7, 30),
      reviewedBy: SeedIds.owner,
    ),
  ];

  // ── templates and policy ──────────────────────────────────────────────

  /// The backend's two templates (`madar_authz::TEMPLATES`), by key.
  static const List<OrgTemplate> templates = [
    OrgTemplate(
      key: 'cafe',
      version: 1,
      nameEn: 'Café',
      nameAr: 'مقهى',
      roles: ['org_admin', 'branch_manager', 'teller', 'kitchen'],
    ),
    OrgTemplate(
      key: 'restaurant',
      version: 1,
      nameEn: 'Restaurant',
      nameAr: 'مطعم',
      roles: ['org_admin', 'branch_manager', 'teller', 'waiter', 'kitchen'],
    ),
  ];

  /// The approval capabilities Sabah lets people ask a manager for; every
  /// other approval capability is "Hidden".
  static const Set<String> askManager = {
    'orders.void',
    'refunds.create',
    'orders.discount.manual_percent',
  };

  /// Sabah's policy row per approval capability.
  static List<PolicyEntry> get policy => [
    for (final c in approvalCapabilities())
      PolicyEntry(capability: c.key, askManager: askManager.contains(c.key)),
  ];

  // ── branch assignments ────────────────────────────────────────────────

  /// Person key → the branches they may work at. Everyone works at their
  /// home branch; Omar also covers Heliopolis at weekends and Dina, New
  /// Cairo's manager, also looks after Maadi.
  static const Map<String, List<String>> assignments = {
    'karim': ['zamalek'],
    'dina': ['new-cairo', 'maadi'],
    'tarek': ['maadi'],
    'rana': ['heliopolis'],
    'mariam': ['zamalek'],
    'youssef': ['zamalek'],
    'salma': ['new-cairo'],
    'omar': ['new-cairo', 'heliopolis'],
    'hana': ['maadi'],
    'ziad': ['maadi'],
    'ali': ['heliopolis'],
    'farida': ['heliopolis'],
    'laila': ['zamalek'],
    'adham': ['zamalek'],
    'hassan': ['zamalek'],
  };

  static String assignmentId(String userId, String branchId) =>
      mockUuid('user-branch:$userId:$branchId');

  static List<Map<String, Object?>> get userBranches => [
    for (final e in assignments.entries)
      for (final b in e.value)
        {
          'id': assignmentId(SeedIds.user(e.key), MockSeed.branchIdOf(b)),
          'user_id': SeedIds.user(e.key),
          'branch_id': MockSeed.branchIdOf(b),
        },
  ];
}

/// Loads the admin seed into [db] (once: a second call does nothing).
void loadAdminSeed(MockDb db) {
  if (db.hasTable(AdminTables.devices)) return;
  db['orgs'].insertAll([for (final o in AdminSeed.orgs) o.toJson()]);
  db['branches'].insertAll([for (final b in AdminSeed.branches) b.toJson()]);
  db['users'].insertAll([for (final u in AdminSeed.owners) u.toJson()]);
  db[AdminTables.devices].insertAll([
    for (final d in AdminSeed.devices) d.toJson(),
  ]);
  db[AdminTables.activationCodes].insertAll([
    for (final c in AdminSeed.activationCodes) c.toJson(),
  ]);
  db[AdminTables.clientVersions].insertAll([
    for (final c in AdminSeed.clientVersions) c.toJson(),
  ]);
  db[AdminTables.flags].insertAll([
    for (final f in AdminSeed.flags) f.toJson(),
  ]);
  db[AdminTables.templates].insertAll([
    for (final t in AdminSeed.templates) t.toJson(),
  ]);
  db[AdminTables.policy].insertAll([
    for (final p in AdminSeed.policy)
      {...p.toJson(), 'org_id': SeedIds.sabahOrg},
  ]);
  db[AdminTables.userBranches].insertAll(AdminSeed.userBranches);
}
