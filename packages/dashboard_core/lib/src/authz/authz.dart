/// What the signed-in person may do (`src/data/authz/use-authz.ts`): their
/// effective capabilities from `GET /authz/me`. Every nav entry, page and
/// button asks this, never the role name. The server still enforces
/// everything.
library;

import 'package:dashboard_api/dashboard_api.dart' show LimitsView, MyAuthz;
import 'package:dashboard_core/src/generated/capabilities.dart';

/// The checker built from an answer (`authzFrom`). Pure, so it is tested
/// directly.
class Authz {
  const Authz._({
    required this.ready,
    required this.platform,
    required this.owner,
    required this.roleKinds,
    required Set<String> held,
    required Set<String> ask,
    required Set<String>? everywhere,
    required Map<String, LimitsView> limits,
    this.error,
    this.source,
  }) : _held = held,
       _ask = ask,
       _everywhere = everywhere,
       _limits = limits;

  /// From an `/authz/me` answer; null = nothing known yet (holds nothing).
  factory Authz.from(MyAuthz? me, {Object? error}) {
    final platform = me?.platform ?? false;
    return Authz._(
      ready: me != null,
      platform: platform,
      owner: (me?.owner ?? false) || platform,
      roleKinds: me?.roleKinds ?? const [],
      held: {...?me?.capabilities},
      ask: {...?me?.askManager},
      everywhere: me?.everywhere == null ? null : {...me!.everywhere!},
      limits: me?.limits ?? const {},
      error: error,
      source: me,
    );
  }

  /// A platform (super) admin: holds everything; nothing is fetched.
  factory Authz.platformAdmin() => const Authz._(
    ready: true,
    platform: true,
    owner: true,
    roleKinds: ['org_admin'],
    held: {},
    ask: {},
    everywhere: null,
    limits: {},
  );

  /// Signed out / not known: holds nothing.
  static final Authz none = Authz.from(null);

  /// True once a real (or remembered) answer is in hand.
  final bool ready;
  final bool platform;
  final bool owner;
  final List<String> roleKinds;
  final Set<String> _held;
  final Set<String> _ask;
  final Set<String>? _everywhere;
  final Map<String, LimitsView> _limits;

  /// The last load's failure, when there is no answer to show.
  final Object? error;

  /// The answer this was built from (null for platform / none).
  final MyAuthz? source;

  bool can(String cap) => platform || _held.contains(cap);

  /// Any of [caps] (`canAny(...caps)`); an empty list is false.
  bool canAny(Iterable<String> caps) => caps.any(can);

  /// Held at EVERY branch (what an org-wide act needs). A backend that does
  /// not send the list falls back to [can].
  bool canEverywhere(String cap) =>
      platform || (_everywhere != null ? _everywhere.contains(cap) : can(cap));

  /// Not held, but the owner lets this person ask a manager.
  bool canAsk(String cap) => !can(cap) && _ask.contains(cap);

  LimitsView? limitsOf(String cap) => platform ? null : _limits[cap];

  /// Every capability held (empty for platform, which holds all).
  Set<String> get held => Set.unmodifiable(_held);
}

/// What a role kind held by default, for a backend that predates
/// `/authz/me` (`defaultsFor`).
MyAuthz? defaultsFor(String? role, [String userId = '']) {
  if (role == null || role.isEmpty) return null;
  final caps = [
    for (final c in capabilityRegistry)
      if (c.tier != 'legacy' && c.defaults.contains(role)) c.key,
  ];
  return MyAuthz(
    userId: userId,
    epoch: 0,
    specVersion: 0,
    owner: role == RoleKind.orgAdmin,
    platform: false,
    roleKinds: [role],
    capabilities: caps,
    askManager: const [],
    limits: const {},
  );
}
