/// The wizard's step tree (web `features/onboarding/config.ts`): the steps in
/// dependency order, the navigator's stages, each step's glyph and i18n stem.
/// Progress itself (done / count / required) is always the server's
/// `GET /orgs/{id}/onboarding`; this file only carries presentation.
library;

/// A wizard step. `goLive` is the synthetic finale (no server status).
enum OnbStep {
  orgProfile('org_profile', OnbStage.cafe, 'store'),
  branch('branch', OnbStage.branch, 'building-2'),
  paymentMethods('payment_methods', OnbStage.pay, 'credit-card'),
  ingredients('ingredients', OnbStage.menu, 'sprout'),
  categories('categories', OnbStage.menu, 'tags'),
  menuItems('menu_items', OnbStage.menu, 'coffee'),
  addons('addons', OnbStage.menu, 'plus-circle'),
  recipes('recipes', OnbStage.menu, 'scroll-text'),
  team('team', OnbStage.team, 'users'),
  goLive('go_live', OnbStage.live, 'rocket');

  const OnbStep(this.key, this.stage, this.icon);

  /// The i18n stem (`onboarding.steps.<key>.*`) and, except for [goLive],
  /// the server step's `key`.
  final String key;
  final OnbStage stage;

  /// The glyph the navigator draws while the step is neither done nor locked.
  final String icon;

  /// The `GET /orgs/{id}/onboarding` step this maps to (null for the finale).
  String? get statusKey => this == goLive ? null : key;

  String get titleKey => 'onboarding.steps.$key.title';
  String get descKey => 'onboarding.steps.$key.desc';
}

/// The navigator's groupings, in order (`STAGES`).
enum OnbStage {
  cafe('store'),
  branch('building-2'),
  pay('credit-card'),
  menu('coffee'),
  team('users'),
  live('rocket');

  const OnbStage(this.icon);

  final String icon;

  String get labelKey => 'onboarding.stages.$name';

  /// The steps of this stage, in wizard order.
  List<OnbStep> get steps => [
    for (final s in OnbStep.values)
      if (s.stage == this) s,
  ];
}

/// The colour family of a mirror tile's glyph chip (the web's `StatAccent`).
enum MirrorAccent { primary, info, brand, success, warning }

/// One tile of the live mirror (`TILES`): the status it reads, its label,
/// its glyph and chip colour.
class MirrorTileSpec {
  const MirrorTileSpec(this.statusKey, this.labelKey, this.icon, this.accent);

  final String statusKey;
  final String labelKey;
  final String icon;
  final MirrorAccent accent;
}

/// The mirror tiles, in display order.
const List<MirrorTileSpec> mirrorTiles = [
  MirrorTileSpec(
    'branch',
    'onboarding.mirror.branches',
    'building-2',
    MirrorAccent.primary,
  ),
  MirrorTileSpec(
    'payment_methods',
    'onboarding.mirror.payments',
    'credit-card',
    MirrorAccent.info,
  ),
  MirrorTileSpec(
    'categories',
    'onboarding.mirror.categories',
    'tags',
    MirrorAccent.brand,
  ),
  MirrorTileSpec(
    'menu_items',
    'onboarding.mirror.items',
    'coffee',
    MirrorAccent.brand,
  ),
  MirrorTileSpec(
    'ingredients',
    'onboarding.mirror.ingredients',
    'sprout',
    MirrorAccent.success,
  ),
  MirrorTileSpec(
    'addons',
    'onboarding.mirror.addons',
    'plus-circle',
    MirrorAccent.warning,
  ),
  MirrorTileSpec('team', 'onboarding.mirror.team', 'users', MirrorAccent.info),
];

/// The currencies the café identity step offers (`CURRENCIES`); literal codes
/// in both languages.
const List<String> onboardingCurrencies = [
  'EGP',
  'USD',
  'SAR',
  'AED',
  'GBP',
  'EUR',
];

/// How long the celebration shows before the dashboard opens (1.8 s).
const Duration celebrationHold = Duration(milliseconds: 1800);

/// The mirror's count-up (`COUNT_ANIM_MS`).
const Duration countAnimation = Duration(milliseconds: 1100);
