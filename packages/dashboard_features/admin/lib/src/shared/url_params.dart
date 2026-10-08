/// Page state held in the URL, as the admin pages keep it on the web: the
/// editor a page has open (`?edit=<id>|new` on Organizations, Branches and
/// Users; `?branches=` / `?access=` on Users; `?role=` on Roles; `?view=`,
/// `?days=`, `?all=` on Devices), and the scope-only links of the Access
/// section tabs.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// The query keys that carry the scope (branch and period). Section tabs and
/// nav links keep only these and drop page params (ADM-APP-037, ADM-USR-001).
const Set<String> scopeQueryKeys = {'branchId', 'preset', 'from', 'to'};

/// [path] with only the scope params of [current] carried over.
String scopedLocation(String path, Uri current) {
  final q = {
    for (final e in current.queryParameters.entries)
      if (scopeQueryKeys.contains(e.key)) e.key: e.value,
  };
  return Uri(path: path, queryParameters: q.isEmpty ? null : q).toString();
}

/// [current] with [changes] applied: a null value removes that param.
Uri withQueryParams(Uri current, Map<String, String?> changes) {
  final q = Map<String, String>.of(current.queryParameters);
  changes.forEach((key, value) {
    if (value == null) {
      q.remove(key);
    } else {
      q[key] = value;
    }
  });
  return Uri(path: current.path, queryParameters: q.isEmpty ? null : q);
}

/// Reading and writing the current page's query params.
extension AdminUrlParams on BuildContext {
  /// The current location (path and query) of the page this context is in.
  Uri get pageUri => GoRouterState.of(this).uri;

  /// The query param [key] of the current page, if present.
  String? queryParam(String key) => pageUri.queryParameters[key];

  /// Applies [changes] to the current page's query (null removes a param)
  /// in place: opening an editor sets `?edit=<id>`, closing it removes it.
  void setQueryParams(Map<String, String?> changes) =>
      GoRouter.of(this).go(withQueryParams(pageUri, changes).toString());
}
