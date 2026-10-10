/// The combo editor's reads: the combo (`GET /combos/{id}`, no branch) and
/// the live price check (`POST /combos/economics`, nothing saved). The pick
/// lists are the area's (`menu_options.dart`).
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart'
    show Combo, ComboEconomics, ComboEconomicsRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_options.dart';
import '../shared/offers_cache.dart';

/// E1 `GET /combos/{id}` (the web's key `["/combos/{id}", {}]`).
final comboProvider = FutureProvider.autoDispose.family<Combo, String>((
  ref,
  id,
) {
  ref.webCache();
  ref.watch(realtimeEpochProvider('${OffersPaths.combos}/$id'));
  return ref.watch(apiProvider).menu.getCombo(id: id);
});

/// What the editor at [id] reads on mount (`new` reads no combo), warmed
/// from whatever opens it (a list row, its pencil, New combo).
void warmComboEditor(WidgetRef ref, String id) {
  if (id != 'new') ref.warm(comboProvider(id));
  ref.warm(offersMenuItemsProvider);
  ref.warm(offersCategoriesProvider);
}

/// The price check's request path (its epoch follows `invalidateCombos`).
const String comboEconomicsPath = '${OffersPaths.combos}/economics';

/// E5 `POST /combos/economics`, keyed by the request body's JSON (the web's
/// key `["/combos/economics", body]`): the same body is never asked twice.
/// Never retried (`retry: false`).
final comboEconomicsProvider = FutureProvider.autoDispose
    .family<ComboEconomics, String>((ref, body) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(comboEconomicsPath));
      return ref
          .watch(apiProvider)
          .menu
          .comboEconomics(
            body: ComboEconomicsRequest.fromJson(
              jsonDecode(body) as Map<String, Object?>,
            ),
          );
    }, retry: (_, _) => null);

/// The price check's key: [body] (from `ComboDraft.economicsBody`) with the
/// scope's branch (null = organisation prices).
String comboEconomicsKey(Map<String, Object?> body, String? branchId) =>
    jsonEncode({...body, 'branch_id': branchId});
