/// The wizard's reads, one provider per endpoint (the web's React Query keys):
///
/// - `GET /orgs/{id}/onboarding` ([onbStatusProvider]) — every step's done /
///   count / required, `can_complete`, `recipe_coverage`;
/// - `GET /orgs/{id}` ([onbOrgProvider]) — the café's name, currency, logo;
/// - `GET /categories?org_id=` ([onbCategoriesProvider]) and
///   `GET /menu-items?org_id=` ([onbMenuItemsProvider]) for the menu-items
///   and recipes steps;
/// - the dialogs' own reads (the add-on view, the modifier groups, the
///   ingredient catalog and its categories).
///
/// After a change, [refreshOnboarding] asks the checklist again (the web's
/// `invalidateQueries(['/orgs/{id}/onboarding'])`); a dialog that saved
/// invalidates its own lists first ([invalidateOnbCatalog]).
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'onboarding_config.dart';

/// `GET /orgs/{id}/onboarding`.
final onbStatusProvider = FutureProvider.autoDispose
    .family<OnboardingStatus, String>((ref, orgId) {
      ref.webCache();
      return ref.watch(apiProvider).orgs.getOnboarding(id: orgId);
    });

/// `GET /orgs/{id}`.
final onbOrgProvider = FutureProvider.autoDispose.family<Org, String>((
  ref,
  orgId,
) {
  ref.webCache();
  return ref.watch(apiProvider).orgs.getOrg(id: orgId);
});

/// `GET /categories?org_id=`.
final onbCategoriesProvider = FutureProvider.autoDispose
    .family<List<Category>, String>((ref, orgId) {
      ref.webCache();
      return ref.watch(apiProvider).menu.listCategories(orgId: orgId);
    });

/// `GET /menu-items?org_id=`.
final onbMenuItemsProvider = FutureProvider.autoDispose
    .family<List<MenuItem>, String>((ref, orgId) {
      ref.webCache();
      return ref.watch(apiProvider).menu.listMenuItems(orgId: orgId);
    });

/// `GET /addon-items?org_id=` (the item dialog's add-on picker).
final onbAddonItemsProvider = FutureProvider.autoDispose
    .family<List<AddonItem>, String>((ref, orgId) {
      ref.webCache();
      return ref.watch(apiProvider).menu.listAddonItems(orgId: orgId);
    });

/// `GET /modifier-groups?org_id=` (the add-on dialog's groups, the item
/// dialog's attachments).
final onbGroupsProvider = FutureProvider.autoDispose
    .family<List<GroupOut>, String>((ref, orgId) {
      ref.webCache();
      return ref.watch(apiProvider).menu.listGroups(orgId: orgId);
    });

/// `GET /inventory/orgs/{org_id}/catalog` (the recipe builder).
final onbCatalogProvider = FutureProvider.autoDispose
    .family<List<OrgIngredient>, String>((ref, orgId) {
      ref.webCache();
      return ref.watch(apiProvider).inventory.listCatalog(orgId: orgId);
    });

/// `GET /inventory/orgs/{org_id}/categories` (the ingredient dialog).
final onbIngredientCategoriesProvider = FutureProvider.autoDispose
    .family<List<IngredientCategory>, String>((ref, orgId) {
      ref.webCache();
      return ref
          .watch(apiProvider)
          .inventory
          .listIngredientCategories(orgId: orgId);
    });

/// Asks the checklist again (closing a step's dialog, saving the café, a new
/// logo).
void refreshOnboarding(WidgetRef ref, String orgId) =>
    ref.invalidate(onbStatusProvider(orgId));

/// What the web's `invalidateCatalog()` / `invalidateRecipes()` refresh here:
/// the categories, the items, the add-ons and groups, the ingredients.
void invalidateOnbCatalog(WidgetRef ref, String orgId) {
  ref
    ..invalidate(onbCategoriesProvider(orgId))
    ..invalidate(onbMenuItemsProvider(orgId))
    ..invalidate(onbAddonItemsProvider(orgId))
    ..invalidate(onbGroupsProvider(orgId))
    ..invalidate(onbCatalogProvider(orgId))
    ..invalidate(onbIngredientCategoriesProvider(orgId));
}

/// The org changed (name, currency, logo): this page's read and the shell's
/// (the org read the scope keeps, the brand the sidebar and footer draw).
void invalidateOnbOrg(WidgetRef ref, String orgId) {
  ref
    ..invalidate(onbOrgProvider(orgId))
    ..invalidate(currentOrgProvider)
    ..invalidate(publicBrandProvider);
}

/// The server's steps by key.
Map<String, OnboardingStep> stepsByKey(OnboardingStatus? status) => {
  for (final s in status?.steps ?? const <OnboardingStep>[]) s.key: s,
};

/// The step the wizard opens on: the first whose server status is not done
/// (the finale when all are).
OnbStep firstIncomplete(Map<String, OnboardingStep> byKey) {
  for (final s in OnbStep.values) {
    final key = s.statusKey;
    if (key != null && !(byKey[key]?.done ?? false)) return s;
  }
  return OnbStep.goLive;
}

/// `round(required done ÷ required × 100)`, 0 with no required step.
int readyPercent(OnboardingStatus? status) {
  final steps = status?.steps ?? const <OnboardingStep>[];
  final required = steps.where((s) => s.required_).length;
  if (required == 0) return 0;
  final done = steps.where((s) => s.required_ && s.done).length;
  return (done / required * 100).round();
}

/// The cheer beside the percentage.
String cheerKey(int pct) => pct >= 100
    ? 'onboarding.cheer.done'
    : pct >= 75
    ? 'onboarding.cheer.most'
    : pct >= 50
    ? 'onboarding.cheer.half'
    : pct > 0
    ? 'onboarding.cheer.start'
    : 'onboarding.cheer.go';

/// The Arabic name when the language is Arabic and one exists
/// (`getTranslatedName`).
String translatedName(
  String name,
  Map<String, Object?>? translations,
  String lang,
) {
  final ar = translations?['ar'];
  if (lang.startsWith('ar') && ar is String) return ar;
  return name;
}

/// The Arabic text of a translations map (`arOf`), '' without one.
String arOf(Object? translations) {
  if (translations is Map) {
    final ar = translations['ar'];
    if (ar is String) return ar;
  }
  return '';
}
