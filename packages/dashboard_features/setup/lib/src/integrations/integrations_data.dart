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

/// The org's credentials, newest first (`GET /integrations/credentials`),
/// keyed by the org in scope so a platform admin's org switch reloads.
final integrationCredentialsProvider = FutureProvider.autoDispose
    .family<List<CredentialSummary>, String>(
      (ref, orgId) => ref.watch(apiProvider).integrations.listCredentials(),
      retry: (_, _) => null,
    );

/// After a create, rotate or revoke: every credentials read loads again.
void invalidateCredentials(WidgetRef ref) =>
    ref.invalidate(integrationCredentialsProvider);

/// A revoked credential is a permanent audit record (`isRevoked`).
bool isRevoked(CredentialSummary c) => c.revokedAt != null;
