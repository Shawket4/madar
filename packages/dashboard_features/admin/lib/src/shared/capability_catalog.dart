/// The capability registry shaped for the permission screens (the web's
/// `features/access/catalog.ts`), shared by the person access sheet (users),
/// the Roles & Permissions page (roles) and the Review page (review).
///
/// - `legacy` capabilities are never shown (they exist only so older tablets
///   read the same permission grid);
/// - `core` capabilities are always on for their role kinds: shown locked as
///   "Always on", never a toggle;
/// - `advanced` capabilities sit behind a collapsed "Advanced" section.
library;

import 'package:dashboard_core/dashboard_core.dart';

/// One registry group in display order, split into the main list and the
/// advanced tier.
class CatalogGroup {
  const CatalogGroup({
    required this.key,
    required this.en,
    required this.ar,
    required this.main,
    required this.advanced,
  });

  final String key;
  final String en;
  final String ar;
  final List<CapabilityMeta> main;
  final List<CapabilityMeta> advanced;

  String label(String lang) => bilingual(en, ar, lang);

  /// The same group with only the capabilities [test] keeps.
  CatalogGroup where(bool Function(CapabilityMeta meta) test) => CatalogGroup(
    key: key,
    en: en,
    ar: ar,
    main: main.where(test).toList(),
    advanced: advanced.where(test).toList(),
  );

  bool get isEmpty => main.isEmpty && advanced.isEmpty;
}

final Map<String, CapabilityMeta> _byKey = {
  for (final c in capabilityRegistry) c.key: c,
};

/// The registry row of [key] (`metaOf`), if any.
CapabilityMeta? capabilityMeta(String key) => _byKey[key];

/// Whether [meta] is always on for role [kind] (`isCoreFor`).
bool isCoreFor(CapabilityMeta meta, String? kind) =>
    kind != null && kind.isNotEmpty && meta.core.contains(kind);

/// Groups in display order, legacy capabilities left out, empty groups
/// dropped (`catalogGroups`).
List<CatalogGroup> catalogGroups() => [
  for (final g in capabilityGroups)
    CatalogGroup(
      key: g.key,
      en: g.en,
      ar: g.ar,
      main: [
        for (final c in capabilityRegistry)
          if (c.group == g.key && c.tier != 'legacy' && c.tier != 'advanced') c,
      ],
      advanced: [
        for (final c in capabilityRegistry)
          if (c.group == g.key && c.tier == 'advanced') c,
      ],
    ),
].where((g) => !g.isEmpty).toList();

bool isArabic(String? lang) => (lang ?? '').startsWith('ar');

/// The registry's English or Arabic, by the active language.
String bilingual(String en, String ar, String? lang) =>
    isArabic(lang) ? ar : en;

/// The capabilities an owner may switch between "Hidden" and "Ask a
/// manager" (`approvalCapabilities`).
List<CapabilityMeta> approvalCapabilities() => [
  for (final c in capabilityRegistry)
    if (c.approval && c.tier != 'legacy') c,
];

/// A role's grant set as keys, with the core grants of its [kind] added
/// (they are not stored) (`roleHolds`).
Set<String> roleHolds(Iterable<String> grantedCapabilities, String kind) => {
  ...grantedCapabilities,
  for (final c in capabilityRegistry)
    if (isCoreFor(c, kind)) c.key,
};
