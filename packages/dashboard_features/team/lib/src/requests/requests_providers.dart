/// The Requests unit's reads, keyed by exactly the params the request sends
/// (the web's Orval key).
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../approvals/approvals_providers.dart';
import '../shared/staff_query.dart';

/// `listRequests({status?, kind?})`: the page's two filters (null = all).
typedef RequestsQuery = ({String? status, String? kind});

/// `GET /staff/requests` with the page's filters.
final requestsListProvider = FutureProvider.autoDispose
    .family<List<StaffRequest>, RequestsQuery>((ref, k) {
      ref.webCache();
      watchStaffPath(ref, '/staff/requests');
      return ref
          .watch(apiProvider)
          .staff
          .listRequests(status: k.status, kind: k.kind);
    });

/// The read for [k]: the pending queue of every kind is the very request
/// Approvals makes (`{status: "pending"}`), so it shares that read.
FutureProvider<List<StaffRequest>> requestsReadFor(RequestsQuery k) =>
    k.status == 'pending' && k.kind == null
    ? approvalsRequestsProvider
    : requestsListProvider(k);
