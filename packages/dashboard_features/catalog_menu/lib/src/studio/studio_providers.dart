/// The Menu Studio's own reads (one provider per web hook, keyed by exactly
/// the request's arguments, each watching its API path so the web's prefix
/// invalidations refetch it):
///
/// | provider | web hook | request |
/// |---|---|---|
/// | [menuStudioProvider] | `useGetStudio` | `GET /menu-items/{id}/studio` |
/// | [recipeLinkProvider] | `useGetRecipeLink` | `GET /menu-items/{id}/recipe-link` |
/// | [studioMenuItemProvider] | `useGetMenuItem` (copies, meal) | `GET /menu-items/{id}` |
/// | [stepPresetsProvider] | `useListStepPresets` | `GET /recipes/step-presets` |
/// | [studioCombosProvider] | `useCombos({per_page: 200})` | `GET /combos?per_page=200` |
/// | [studioComboProvider] | `useCombo(id)` | `GET /combos/{id}` |
/// | [studioMenuOptionsProvider] | `useMenuOptions` items | `GET /menu-items?org_id&full=true` |
/// | [studioPreviewProvider] | `useMenuItemPreview` | `POST /menu-items/{id}/preview` |
/// | [stepAnimationProvider] | the step player's file | `GET <animation_url>` |
///
/// The ingredient catalog, categories, groups and bases are the area's shared
/// reads (`shared/menu_providers.dart`); the branches are the core's.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_queries.dart';

/// `GET /menu-items/{id}/studio`: the item aggregate (sizes with recipes and
/// costs, attached groups, item-only options, steps, availability, link).
final menuStudioProvider = FutureProvider.autoDispose
    .family<StudioAggregate, String>((ref, itemId) {
      ref.webCache();
      watchStudioPaths(ref, itemId);
      return ref.watch(apiProvider).menu.getStudio(id: itemId);
    });

/// `GET /menu-items/{id}/recipe-link`: only for a linked copy or a source
/// with copies.
final recipeLinkProvider = FutureProvider.autoDispose
    .family<RecipeLinkInfo, String>((ref, itemId) {
      ref.webCache();
      watchMenuPath(ref, MenuPaths.recipeLink(itemId));
      return ref.watch(apiProvider).menu.getRecipeLink(id: itemId);
    });

/// `GET /menu-items/{id}`: a linked copy's name, the meal section's target.
final studioMenuItemProvider = FutureProvider.autoDispose
    .family<MenuItemFull, String>((ref, id) {
      ref.webCache();
      watchMenuPath(ref, MenuPaths.menuItem(id));
      return ref.watch(apiProvider).menu.getMenuItem(id: id);
    });

/// `GET /recipes/step-presets`: the step library.
final stepPresetsProvider = FutureProvider.autoDispose<List<RecipeStepPreset>>((
  ref,
) {
  ref.webCache();
  watchMenuPath(ref, MenuPaths.stepPresets);
  return ref.watch(apiProvider).recipes.listStepPresets();
});

/// `GET /combos?per_page=200`.
final studioCombosProvider = FutureProvider.autoDispose<PaginatedCombos>((
  ref,
) {
  ref.webCache();
  watchMenuPath(ref, MenuPaths.combos);
  return ref.watch(apiProvider).menu.listCombos(perPage: 200);
});

/// `GET /combos/{id}`.
final studioComboProvider = FutureProvider.autoDispose.family<Combo, String>((
  ref,
  id,
) {
  ref.webCache();
  watchMenuPath(ref, '${MenuPaths.combos}/$id');
  return ref.watch(apiProvider).menu.getCombo(id: id);
});

/// `GET /menu-items?org_id&full=true`, raw `MenuItemFull`s (the generated
/// `listMenuItems` decodes `MenuItem`, which drops the sizes).
final studioMenuOptionsProvider = FutureProvider.autoDispose
    .family<List<MenuItemFull>, String>((ref, orgId) async {
      ref.webCache();
      watchMenuPath(ref, MenuPaths.menuItems);
      final res = await ref
          .watch(apiProvider)
          .transport
          .send(
            ApiRequest(
              method: 'GET',
              path: MenuPaths.menuItems,
              query: {
                'org_id': [orgId],
                'full': ['true'],
              },
            ),
          );
      // A non-2xx answer already threw an ApiException in the transport.
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
          if (e is Map) MenuItemFull.fromJson(e.cast<String, Object?>()),
      ];
    });

/// The preview's cache key: the item and the request body as JSON (the web's
/// `["/menu-items", id, "preview", body]`).
typedef PreviewKey = ({String itemId, String body});

PreviewKey previewKeyOf(String itemId, PreviewRequest body) =>
    (itemId: itemId, body: jsonEncode(body.toJson()));

/// `POST /menu-items/{id}/preview`, a dry run read as a query; under
/// `/menu-items` so every studio save refreshes it.
final studioPreviewProvider = FutureProvider.autoDispose
    .family<PreviewResponse, PreviewKey>((ref, k) {
      ref.webCache();
      watchMenuPath(ref, '${MenuPaths.menuItem(k.itemId)}/preview');
      return ref
          .watch(apiProvider)
          .menu
          .previewMenuItem(
            id: k.itemId,
            body: PreviewRequest.fromJson(
              (jsonDecode(k.body) as Map).cast<String, Object?>(),
            ),
          );
    });

/// A step's animation file (Lottie JSON) by its address, through the API
/// transport; null when it cannot be had (the row then shows its frame).
final stepAnimationProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, url) async {
      ref.webCache();
      final uri = Uri.parse(url);
      try {
        final res = await ref
            .watch(apiProvider)
            .transport
            .send(
              ApiRequest(
                method: 'GET',
                path: uri.path,
                query: uri.queryParametersAll,
              ),
            );
        return res.bodyBytes.isEmpty ? null : Uint8List.fromList(res.bodyBytes);
      } on ApiException {
        return null;
      }
    });
