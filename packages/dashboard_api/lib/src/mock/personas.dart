/// Who is signed in to the mock: five people whose capabilities come from the
/// web's registry (`MadarDashboard/src/generated/capabilities.ts`, generated
/// into `mock_capabilities.dart`). Plain strings: this package does not depend
/// on dashboard_core.
library;

import '../generated/mock_capabilities.dart';
import 'seed_ids.dart';

/// Read-only access to a few pages: the `limited` persona's capabilities.
const List<String> limitedCapabilities = [
  'branches.read',
  'orders.read',
  'menu.categories.read',
  'menu.items.read',
  'menu.addons.read',
  'customers.view',
  'reports.read',
  'till.read',
];

enum Persona {
  /// Nour El-Sayed: Sabah Coffee's owner (org admin), every capability, both
  /// modules, every branch.
  owner,

  /// Karim Adel: Zamalek's branch manager with the registry's manager defaults.
  manager,

  /// Hana Mostafa: a Maadi cashier who may only read a few pages.
  limited,

  /// Madar Support: a platform (super) admin, every capability, any org.
  platform,

  /// Yasmin Ghali: owner of Nakhla Bakery, an org with only the Dawam module.
  dawamOnly;

  String get userId => switch (this) {
    owner => SeedIds.owner,
    manager => SeedIds.manager,
    limited => SeedIds.limited,
    platform => SeedIds.platform,
    dawamOnly => SeedIds.dawamOwner,
  };

  String get displayName => switch (this) {
    owner => 'Nour El-Sayed',
    manager => 'Karim Adel',
    limited => 'Hana Mostafa',
    platform => 'Madar Support',
    dawamOnly => 'Yasmin Ghali',
  };

  /// The sign-in email (every persona's password is [password]).
  String get email => switch (this) {
    owner => 'nour@sabah.test',
    manager => 'karim@sabah.test',
    limited => 'hana@sabah.test',
    platform => 'support@madar.test',
    dawamOnly => 'yasmin@nakhla.test',
  };

  /// Test-only password of every persona.
  static const String password = 'SabahDemo2026!';

  /// The backend `UserRole` wire value.
  String get role => switch (this) {
    owner || dawamOnly => 'org_admin',
    manager => 'branch_manager',
    limited => 'teller',
    platform => 'super_admin',
  };

  /// The role kinds `/authz/me` reports.
  List<String> get roleKinds => switch (this) {
    owner || dawamOnly || platform => const ['org_admin'],
    manager => const ['branch_manager'],
    limited => const ['teller'],
  };

  bool get isPlatform => this == platform;

  bool get isOwner => this == owner || this == dawamOnly || this == platform;

  /// The persona's org (null for the platform admin, who picks one).
  String? get orgId => switch (this) {
    owner || manager || limited => SeedIds.sabahOrg,
    dawamOnly => SeedIds.nakhlaOrg,
    platform => null,
  };

  /// The branches this persona is assigned to; null means every branch of
  /// the org.
  List<String>? get branchIds => switch (this) {
    manager => [SeedIds.zamalek],
    limited => [SeedIds.maadi],
    owner || dawamOnly || platform => null,
  };

  /// The user's home branch (`UserPublic.branch_id`).
  String? get homeBranchId => branchIds?.first;

  /// The org's switched-on modules.
  List<String> get modules =>
      this == dawamOnly ? const ['dawam'] : const ['pos', 'dawam'];

  /// Effective capability keys.
  Set<String> get capabilities =>
      _caps[this] ??= Set.unmodifiable(_compute(this));

  bool can(String capability) =>
      isPlatform || capabilities.contains(capability);

  bool seesBranch(String branchId) =>
      branchIds == null || branchIds!.contains(branchId);

  /// The persona that signs in with [email], if any.
  static Persona? byEmail(String email) {
    final e = email.trim().toLowerCase();
    for (final p in values) {
      if (p.email == e) return p;
    }
    return null;
  }

  /// The persona whose user id is [userId], if any.
  static Persona? byUserId(String userId) {
    for (final p in values) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  /// The mock bearer token of this persona.
  String get token => 'mock.$name.token';

  static final Map<Persona, Set<String>> _caps = {};

  static Iterable<String> _compute(Persona p) => switch (p) {
    owner || dawamOnly => [
      for (final c in mockCapabilities)
        if (!c.key.startsWith('platform.')) c.key,
    ],
    platform => [for (final c in mockCapabilities) c.key],
    manager => [
      for (final c in mockCapabilities)
        if (c.tier != 'legacy' && c.defaults.contains('branch_manager')) c.key,
    ],
    limited => limitedCapabilities,
  };
}
