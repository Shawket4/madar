/// The stable ids of the seed's people, orgs and branches, so personas, areas
/// and tests can name them without loading the seed.
library;

import 'mock_ids.dart';

abstract final class SeedIds {
  /// "Sabah Coffee": POS + Dawam, four Cairo branches.
  static final String sabahOrg = mockUuid('org:sabah');

  /// "Nakhla Bakery": an org with only the Dawam module.
  static final String nakhlaOrg = mockUuid('org:nakhla');

  static final String heliopolis = mockUuid('branch:heliopolis');
  static final String maadi = mockUuid('branch:maadi');
  static final String newCairo = mockUuid('branch:new-cairo');
  static final String zamalek = mockUuid('branch:zamalek');

  /// Sabah's branches in the order the web lists them (by name).
  static final List<String> sabahBranches = [
    heliopolis,
    maadi,
    newCairo,
    zamalek,
  ];

  static final String dokki = mockUuid('branch:nakhla-dokki');
  static final String nasrCity = mockUuid('branch:nakhla-nasr-city');

  static final List<String> nakhlaBranches = [dokki, nasrCity];

  /// Nour El-Sayed, Sabah's owner.
  static final String owner = user('nour');

  /// Karim Adel, Zamalek's branch manager.
  static final String manager = user('karim');

  /// Hana Mostafa, a Maadi cashier with read-only dashboard access.
  static final String limited = user('hana');

  /// Madar Support, the platform admin.
  static final String platform = user('madar-support');

  /// Yasmin Ghali, Nakhla Bakery's owner.
  static final String dawamOwner = user('yasmin');

  /// A person's user id by seed key (`user('karim')`).
  static String user(String key) => mockUuid('user:$key');

  /// The employee (Dawam) record of a person by seed key.
  static String employee(String key) => mockUuid('employee:$key');
}
