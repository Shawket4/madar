/// What the Integrations pane reads (`useListCredentials`, SET-INT-005..009)
/// and the one invalidation every write ends with (`invalidateCredentials`:
/// every key under `/integrations/credentials`).
///
/// The secret a create or rotate returns is never cached here: it lives
/// only in the open handoff dialog's state and inside the encrypted file.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The request paths (the web's query keys).
abstract final class IntegrationsPaths {
  static const String credentials = '/integrations/credentials';
}

/// The org's credentials, newest first (`GET /integrations/credentials`).
/// The org rides the `X-Org-Id` header; `webCache` keys the read by it.
final integrationCredentialsProvider =
    FutureProvider.autoDispose<List<CredentialSummary>>((ref) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(IntegrationsPaths.credentials));
      return ref.watch(apiProvider).integrations.listCredentials();
    });

/// After a create, rotate or revoke: every credentials read loads again
/// (the web's predicate on keys starting `/integrations/credentials`).
void invalidateCredentials(RealtimeBus bus) =>
    bus.invalidate(const [IntegrationsPaths.credentials]);

/// A revoked credential is a permanent audit record (`isRevoked`).
bool isRevoked(CredentialSummary c) => c.revokedAt != null;

/// Whether the table searches the Last used column: TanStack decides a
/// column's search eligibility from the FIRST row's value, so a list whose
/// first credential was never used never searches it (SET-INT-007).
bool lastUsedSearchable(List<CredentialSummary> rows) =>
    rows.isNotEmpty && rows.first.lastUsedAt != null;
