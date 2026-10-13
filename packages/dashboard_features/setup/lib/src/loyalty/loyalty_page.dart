/// `/settings/loyalty` Loyalty (`features/loyalty/admin/loyalty-page.tsx`,
/// SET-LOY rows): the scope card with the sign-up code, then Program,
/// Rewards, Members and (with `loyalty.members.list`) Overview.
///
/// The scope is the header's — org from `orgIdProvider`, branch from the
/// header picker (null = the organisation's own row) — shown here, never
/// chosen here. Program, Rewards and Overview are keyed on the branch, so a
/// branch change rebuilds them for the new scope; Members keeps its search
/// and window (SET-LOY-082). No page guard: the rail hides the pane, a typed
/// URL renders and the reads refuse (SET-LOY-080).
library;

import 'package:dashboard_api/dashboard_api.dart' show Branch, QrResponse;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/qr_preview_dialog.dart';
import 'loyalty_data.dart';
import 'members_pane.dart';
import 'overview_pane.dart';
import 'program_pane.dart';
import 'rewards_pane.dart';

/// The page's tabs (local state, not in the URL).
enum LoyaltyTab { program, rewards, members, overview }

class LoyaltyPage extends ConsumerStatefulWidget {
  const LoyaltyPage({super.key});

  @override
  ConsumerState<LoyaltyPage> createState() => _LoyaltyPageState();
}

class _LoyaltyPageState extends ConsumerState<LoyaltyPage>
    with DashRememberedState {
  LoyaltyTab _tab = LoyaltyTab.program;

  // ── memory: the tab comes back with the page (`DashRememberedState`). ──

  @override
  String get memoryKey => 'setup.loyalty';

  @override
  Map<String, Object?> get rememberedValues => {'tab': _tab.name};

  @override
  void restoreRemembered(DashMemo m) =>
      _tab = m.enumOr('tab', LoyaltyTab.values, LoyaltyTab.program);

  /// Warms what [tab] reads on mount, with the exact keys it uses.
  void _warm(LoyaltyTab tab, String orgId, String? branchId) {
    final access = ref.read(loyaltyAccessProvider);
    switch (tab) {
      case LoyaltyTab.program:
        ref.warm(loyaltySettingsProvider(branchId));
      case LoyaltyTab.rewards:
        ref
          ..warm(rewardItemsProvider(branchId))
          ..warm(loyaltySettingsProvider(branchId));
        if (orgId.isNotEmpty) ref.warm(loyaltyMenuProvider(orgId));
        // The earning card mounts only for a stamps programme.
        final settings = ref.read(loyaltySettingsProvider(branchId)).value;
        if (settings != null && loyaltyModeOf(settings) == 'visits') {
          ref.warm(earningItemsProvider(branchId));
        }
      case LoyaltyTab.members:
        switch (membersSourceOf(access)) {
          case MembersSource.customers:
            ref.warm(
              memberCustomersProvider((
                q: '',
                source: null,
                limit: membersPageSize,
              )),
            );
            if (access.canReadProgram) {
              ref.warm(loyaltySettingsProvider(branchId));
            }
          case MembersSource.members:
            ref.warm(
              loyaltyMembersProvider((
                branchId: branchId,
                q: '',
                limit: membersPageSize,
              )),
            );
          case null:
        }
      case LoyaltyTab.overview:
        ref
          ..warm(overviewAnalyticsProvider(branchId))
          ..warm(overviewMembersProvider(branchId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider) ?? '';
    final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
    final canListMembers = ref.watch(
      loyaltyAccessProvider.select((a) => a.canListMembers),
    );
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    // Looked up among ACTIVE branches (SET-LOY-081).
    final branchName = branches
        .where((b) => b.isActive && b.id == branchId)
        .firstOrNull
        ?.name;
    final tab = _tab == LoyaltyTab.overview && !canListMembers ? null : _tab;
    final scopeKey = ValueKey('${tab?.name}-${branchId ?? 'org'}');

    final pane = switch (tab) {
      LoyaltyTab.program => ProgramPane(
        key: scopeKey,
        orgId: orgId,
        branchId: branchId,
      ),
      LoyaltyTab.rewards => RewardsPane(
        key: scopeKey,
        orgId: orgId,
        branchId: branchId,
      ),
      LoyaltyTab.members => MembersPane(branchId: branchId),
      LoyaltyTab.overview => OverviewPane(key: scopeKey, branchId: branchId),
      null => const SizedBox.shrink(),
    };

    return DashPageScaffold(
      title: t('nav.loyalty'),
      subtitle: t('loyalty.subtitle'),
      width: DashPageWidth.reading,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          SignUpCode(orgId: orgId, branchId: branchId, branchName: branchName),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashSegmentedControl<LoyaltyTab>(
              key: const ValueKey('loyalty-tabs'),
              semanticLabel: t('nav.loyalty'),
              options: [
                DashOption(
                  value: LoyaltyTab.program,
                  label: t('loyalty.tabProgram'),
                ),
                DashOption(
                  value: LoyaltyTab.rewards,
                  label: t('loyalty.tabRewards'),
                ),
                DashOption(
                  value: LoyaltyTab.members,
                  label: t('loyalty.tabMembers'),
                ),
                if (canListMembers)
                  DashOption(
                    value: LoyaltyTab.overview,
                    label: t('loyalty.tabOverview'),
                  ),
              ],
              value: _tab,
              onChanged: (v) => setState(() => _tab = v),
              onIntent: (v) => _warm(v, orgId, branchId),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: pane,
          ),
        ],
      ),
    );
  }
}

/// Which programme the page edits, and the code that signs people up for it
/// (`sign-up-code.tsx`): a locked label reporting the header scope, why the
/// scope matters, and the code button.
class SignUpCode extends ConsumerStatefulWidget {
  const SignUpCode({
    required this.orgId,
    required this.branchId,
    required this.branchName,
    super.key,
  });

  final String orgId;

  /// The header scope's branch (the button follows it).
  final String? branchId;

  /// The scoped branch's name among the active ones; null = the whole shop.
  final String? branchName;

  @override
  ConsumerState<SignUpCode> createState() => _SignUpCodeState();
}

class _SignUpCodeState extends ConsumerState<SignUpCode> {
  bool _busy = false;

  LoyaltyQrKey get _key => (orgId: widget.orgId, branchId: widget.branchId);

  Future<void> _show() async {
    final t = ref.read(tProvider);
    final read = loyaltyQrProvider(_key);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    QrResponse? qr;
    try {
      qr = await container.read(read.future);
    } on Object catch (e) {
      // A refusal is not kept: the next press asks again.
      container.invalidate(read);
      // "We run no programme here", worth saying rather than swallowing.
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (qr == null || !mounted) return;
    await showQrPreview(context, qr: qr, title: t('loyalty.joinQr'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final name = widget.branchName;

    final label = Tooltip(
      message: t('loyalty.scopeLocked'),
      child: Container(
        key: const ValueKey('loyalty-scope'),
        width: wide ? Space.xxl * 8 : double.infinity,
        constraints: const BoxConstraints(minHeight: DashMetrics.control),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(color: c.hairline),
        ),
        child: Row(
          spacing: Space.sm,
          children: [
            DashIcon('lock', size: IconSize.xs, color: c.textSecondary),
            Expanded(
              child: MadarClippedText(
                name ?? t('loyalty.wholeOrg'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
    final hint = Text(
      name != null ? t('loyalty.qrPerBranch') : t('loyalty.qrOrgTip'),
      style: DashType.small.copyWith(color: c.textSecondary),
    );
    final button = DashButton(
      key: const ValueKey('loyalty-code'),
      label: widget.branchId != null
          ? t('loyalty.counterQr')
          : t('loyalty.orgQr'),
      icon: 'qr-code',
      variant: DashButtonVariant.outline,
      loading: _busy,
      onPressed: widget.orgId.isEmpty ? null : _show,
      onIntent: widget.orgId.isEmpty
          ? null
          : () => ref.warm(loyaltyQrProvider(_key)),
    );

    return DashCard(
      key: const ValueKey('loyalty-signup-code'),
      padding: const EdgeInsets.all(Space.lg),
      child: wide
          ? Row(
              spacing: Space.md,
              children: [
                // The web's w-64 label gives way only once the hint has no
                // room left (flex-shrink), so a 1024 window never overflows.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Row(
                      spacing: Space.md,
                      children: [
                        SizedBox(
                          width: (box.maxWidth - Space.md)
                              .clamp(0.0, Space.xxl * 8)
                              .toDouble(),
                          child: label,
                        ),
                        Expanded(child: hint),
                      ],
                    ),
                  ),
                ),
                button,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                label,
                hint,
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: button,
                ),
              ],
            ),
    );
  }
}
