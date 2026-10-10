/// What the combo editor, the deal dialog and the lists' name columns pick
/// from (the web's `use-menu-options.ts`): the org's sellable items (never a
/// combo, never a deleted item) with their active sizes cheapest first, the
/// categories and the branches, each by its name in the active language.
///
/// The items come from `GET /menu-items?full=true`, whose `all_sizes` keeps a
/// single-price item's synthetic `one_size` row. The generated
/// `listMenuItems` decodes `MenuItem` (no sizes), so this reads the same
/// operation through the transport and decodes `MenuItemFull`.
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'offers_cache.dart';
import 'offers_format.dart';

/// One size of an item: its label and price (piastres).
@immutable
class SizeOption {
  const SizeOption(this.label, this.price);

  final String label;
  final int price;
}

/// One pickable item.
@immutable
class ItemOption {
  const ItemOption({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.isActive,
    required this.sizes,
  });

  final String id;

  /// In the active language.
  final String name;
  final String? categoryId;
  final bool isActive;

  /// Active sizes, cheapest first; a single-price item has one `one_size`.
  final List<SizeOption> sizes;

  /// The size a price covers when none is named: the cheapest.
  SizeOption? get cheapest => sizes.isEmpty ? null : sizes.first;
}

/// A category or a branch: its id and its name in the active language.
typedef NamedOption = ({String id, String name});

/// The pick lists and the lookups over them.
@immutable
class MenuOptions {
  MenuOptions({
    required this.items,
    required this.categories,
    required this.branches,
  }) : _items = {for (final i in items) i.id: i},
       _categories = {for (final c in categories) c.id: c.name},
       _branches = {for (final b in branches) b.id: b.name};

  /// Nothing loaded yet (or a list failed): every lookup misses.
  static final MenuOptions empty = MenuOptions(
    items: const [],
    categories: const [],
    branches: const [],
  );

  final List<ItemOption> items;
  final List<NamedOption> categories;
  final List<NamedOption> branches;
  final Map<String, ItemOption> _items;
  final Map<String, String> _categories;
  final Map<String, String> _branches;

  ItemOption? item(String? id) => id == null ? null : _items[id];
  String? itemName(String? id) => item(id)?.name;
  String? categoryName(String? id) => id == null ? null : _categories[id];
  String? branchName(String? id) => id == null ? null : _branches[id];

  List<ItemOption> itemsOfCategory(String id) => [
    for (final i in items)
      if (i.categoryId == id) i,
  ];

  /// Every size label an item of this category has (a category choice).
  List<String> categorySizeLabels(String id) {
    final out = <String>{};
    for (final i in itemsOfCategory(id)) {
      for (final s in i.sizes) {
        out.add(s.label);
      }
    }
    return out.toList();
  }
}

/// The pick lists' own `staleTime` on the web (`use-menu-options.ts`).
const Duration kPickListStaleTime = Duration(minutes: 5);

/// `GET /menu-items?org_id=…&full=true`, raw `MenuItemFull`s. Refetches
/// after `invalidateCombos` (which covers `/menu-items`) or a `resync`; kept
/// and refreshed like a web query (`ref.webCache()`, keyed by the org), fresh
/// for [kPickListStaleTime].
final offersMenuItemsProvider = FutureProvider.autoDispose<List<MenuItemFull>>((
  ref,
) async {
  ref.webCache(staleTime: kPickListStaleTime);
  ref.watch(realtimeEpochProvider(OffersPaths.menuItems));
  final orgId = ref.watch(orgIdProvider);
  if (orgId == null) return const [];
  final api = ref.watch(apiProvider);
  final res = await api.transport.send(
    ApiRequest(
      method: 'GET',
      path: OffersPaths.menuItems,
      query: {
        'org_id': [orgId],
        'full': ['true'],
      },
    ),
  );
  final body = res.bodyBytes.isEmpty
      ? const <Object?>[]
      : jsonDecode(utf8.decode(res.bodyBytes));
  if (body is! List) {
    throw ApiException(
      status: res.status,
      code: 'decode',
      message: 'Unexpected server data for list_menu_items.',
    );
  }
  return [
    for (final e in body)
      if (e is Map<String, Object?>) MenuItemFull.fromJson(e),
  ];
});

/// `GET /categories?org_id=…` (a web query: `ref.webCache()`, keyed by the
/// org, fresh for [kPickListStaleTime]).
final offersCategoriesProvider = FutureProvider.autoDispose<List<Category>>((
  ref,
) async {
  ref.webCache(staleTime: kPickListStaleTime);
  ref.watch(realtimeEpochProvider(OffersPaths.categories));
  final orgId = ref.watch(orgIdProvider);
  if (orgId == null) return const [];
  return ref.watch(apiProvider).menu.listCategories(orgId: orgId);
});

/// The pick lists in the active language. Each list loads on its own: one
/// still loading (or failed) leaves its lookups empty, as on the web.
final menuOptionsProvider = Provider.autoDispose<MenuOptions>((ref) {
  final lang = ref.watch(localeProvider);
  final full = ref.watch(offersMenuItemsProvider).value ?? const [];
  final cats = ref.watch(offersCategoriesProvider).value ?? const [];
  final branches = ref.watch(branchesProvider).value ?? const [];

  final items = <ItemOption>[
    for (final m in full)
      if (m.kind != 'combo' && m.deletedAt == null)
        ItemOption(
          id: m.id,
          name: translatedName(m.name, m.nameTranslations, lang),
          categoryId: m.categoryId,
          isActive: m.isActive,
          sizes: () {
            final rows = (m.allSizes?.isNotEmpty ?? false)
                ? m.allSizes!
                : m.sizes;
            final sizes = [
              for (final s in rows)
                if (s.isActive) SizeOption(s.label, s.priceOverride),
            ]..sort((a, b) => a.price.compareTo(b.price));
            return sizes.isEmpty ? [SizeOption(oneSize, m.basePrice)] : sizes;
          }(),
        ),
  ]..sort((a, b) => compareNames(a.name, b.name));

  return MenuOptions(
    items: items,
    categories: [
      for (final c in cats)
        (id: c.id, name: translatedName(c.name, c.nameTranslations, lang)),
    ],
    // The spec's `Branch` carries no translations: a branch reads its name.
    // A warehouse never sells (`use-menu-options.ts` `isSelling`).
    branches: [
      for (final b in branches)
        if (isSelling(b)) (id: b.id, name: b.name),
    ],
  );
});

/// Whether any pick list is still on its first load.
final menuOptionsLoadingProvider = Provider.autoDispose<bool>(
  (ref) =>
      ref.watch(offersMenuItemsProvider).isLoading ||
      ref.watch(offersCategoriesProvider).isLoading ||
      ref.watch(branchesProvider).isLoading,
);

/// Names in the order the web's `localeCompare` gives closely enough: case,
/// Latin accents, Arabic short vowels and the alef forms (آ أ إ ٱ → ا) are
/// folded first; a tie falls back to the plain order.
int compareNames(String a, String b) {
  final c = _fold(a).compareTo(_fold(b));
  return c != 0 ? c : a.compareTo(b);
}

String _fold(String s) {
  final out = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    if (r >= 0x064B && r <= 0x0652) continue; // tashkeel
    final ch = String.fromCharCode(r);
    out.write(_folds[ch] ?? ch);
  }
  return out.toString();
}

const Map<String, String> _folds = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ç': 'c', //
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', //
  'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', //
  'آ': 'ا', 'أ': 'ا', 'إ': 'ا', 'ٱ': 'ا',
};
