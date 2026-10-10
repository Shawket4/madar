/// Which menu items a customer may claim and what each costs, and — for a
/// stamp card — which items collect a stamp (the web's
/// `admin/rewards/{rewards-pane,earning-items-card}.tsx`, SET-LOY-035 … 051).
///
/// Both lists are copies of the server's: they re-seed when a refresh lands
/// until the person edits them, and after a save the server's answer
/// replaces them.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'loyalty_data.dart';
import 'loyalty_widgets.dart';

/// The add-an-item picker (`Combobox`) and its Add button: offerable items
/// not already listed, "name · base price".
class LoyaltyItemPicker extends ConsumerWidget {
  const LoyaltyItemPicker({
    required this.label,
    required this.menu,
    required this.taken,
    required this.picked,
    required this.onPicked,
    required this.onAdd,
    this.hint,
    super.key,
  });

  final String label;
  final String? hint;
  final List<MenuItem> menu;
  final Set<String> taken;
  final String? picked;
  final ValueChanged<String> onPicked;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final options = [
      for (final m in menu)
        if (menuItemOfferable(m) && !taken.contains(m.id))
          DashOption(
            value: m.id,
            label: '${m.name} · ${fmt.fmtMoney(m.basePrice)}',
          ),
    ];
    final small = DashType.small.copyWith(color: c.textSecondary);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: c.hairline.withValues(alpha: 0.6)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: Space.md,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.xs + DashMetrics.hair,
                children: [
                  Text(label, style: small),
                  DashSelect<String>(
                    options: options,
                    value: picked,
                    onChanged: onPicked,
                    placeholder: t('loyalty.pickItem'),
                    semanticLabel: label,
                    searchable: true,
                    searchPlaceholder: t('common.search'),
                    emptyText: t('common.noResults'),
                  ),
                  if (hint != null) Text(hint!, style: small),
                ],
              ),
            ),
            Padding(
              // The Add button lines up with the picker, not the hint.
              padding: EdgeInsets.only(
                bottom: hint == null ? 0 : Space.xl - DashMetrics.hair,
              ),
              child: DashButton(
                label: t('common.add'),
                icon: 'plus',
                variant: DashButtonVariant.outline,
                onPressed: picked == null ? null : onAdd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RewardsPane extends ConsumerStatefulWidget {
  const RewardsPane({required this.orgId, required this.branchId, super.key});

  final String orgId;
  final String? branchId;

  @override
  ConsumerState<RewardsPane> createState() => _RewardsPaneState();
}

class _RewardsPaneState extends ConsumerState<RewardsPane> {
  RewardCatalogue? _from;
  List<RewardRow> _rows = const [];
  bool _reseed = false;
  String? _picked;
  bool _saving = false;

  /// Each row's key, so a removed row takes its input with it.
  final List<int> _keys = [];
  int _nextKey = 0;

  void _seed(List<RewardRow> rows) {
    _rows = rows;
    _keys
      ..clear()
      ..addAll([for (final _ in rows) _nextKey++]);
  }

  void _sync(RewardCatalogue c) {
    if (identical(c, _from)) return;
    final edited = _from != null && rewardsChanged(_rows, _from!.items);
    if (_from == null || _reseed || !edited) _seed(rewardRowsFrom(c.items));
    _reseed = false;
    _from = c;
  }

  void _setCost(int i, String cost) => setState(() {
    final r = _rows[i];
    _rows = [..._rows]
      ..[i] = (menuItemId: r.menuItemId, name: r.name, cost: cost);
  });

  void _remove(int i) => setState(() {
    _rows = [..._rows]..removeAt(i);
    _keys.removeAt(i);
  });

  void _add(List<MenuItem> menu, LoyaltySettings settings) {
    final item = menu.where((m) => m.id == _picked).firstOrNull;
    if (item == null || !menuItemOfferable(item)) return;
    if (_rows.any((r) => r.menuItemId == item.id)) return;
    setState(() {
      _rows = [
        ..._rows,
        // The scope's default, which the admin can then price on its own.
        (
          menuItemId: item.id,
          name: item.name,
          cost: '${settings.defaultRewardCost}',
        ),
      ];
      _keys.add(_nextKey++);
      _picked = null;
    });
  }

  Future<void> _save(String mode, List<RewardProblem?> problems) async {
    final t = ref.read(tProvider);
    if (problems.any(rewardBlocking) ||
        _rows.any((r) => rewardCostOf(r.cost) == null)) {
      DashToast.error(context, t('loyalty.errors.rewardFixRows'));
      return;
    }
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _saving = true);
    try {
      await api.loyalty.putLoyaltyRewardItems(
        body: PutRewardItems(
          branchId: widget.branchId,
          items: rewardsToWire(_rows, mode),
          explicitNulls: const {'branch_id'},
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(context, loyaltyServerError(e, t).message);
        setState(() => _saving = false);
      }
      return;
    }
    bus.invalidate(const [LoyaltyPaths.rewardItems]);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _reseed = true;
    });
    DashToast.success(context, t('loyalty.rewardsSaved'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final branchId = widget.branchId;
    final catalogue = ref.watch(rewardItemsProvider(branchId));
    final settingsQ = ref.watch(loyaltySettingsProvider(branchId));
    final menuQ = widget.orgId.isEmpty
        ? null
        : ref.watch(loyaltyMenuProvider(widget.orgId));
    final canEdit = ref.watch(
      loyaltyAccessProvider.select((a) => a.canEditProgram),
    );

    if (catalogue.awaitingFirst || settingsQ.awaitingFirst) {
      return const DashSkeleton(
        key: ValueKey('loyalty-rewards-loading'),
        height: Space.xxl * 5,
        radius: Radii.card,
      );
    }
    final cat = catalogue.value;
    final settings = settingsQ.value;
    if (cat == null || settings == null) {
      final error = catalogue.hasError ? catalogue.error : settingsQ.error;
      return DashErrorState(
        title: t('loyalty.rewardsLoadFailed'),
        message: errorMessage(error, t),
        retryLabel: t('common.retry'),
        retrying: catalogue.isLoading || settingsQ.isLoading,
        onRetry: () {
          ref.invalidate(rewardItemsProvider(branchId));
          ref.invalidate(loyaltySettingsProvider(branchId));
        },
      );
    }
    _sync(cat);
    final mode = loyaltyModeOf(settings);
    final menu = menuQ?.value;
    final problems = rewardProblems(_rows, menu);
    final dirty = rewardsChanged(_rows, cat.items);
    final inherited = cat.inherited && branchId != null;
    final blocking = problems.any(rewardBlocking);

    String problemText(RewardProblem p) => switch (p) {
      RewardProblem.cost => t('loyalty.errors.rewardCost'),
      RewardProblem.duplicate => t('loyalty.errors.rewardDuplicate'),
      RewardProblem.unavailable => t('loyalty.errors.rewardUnavailable'),
      RewardProblem.inactive => t('loyalty.rewardInactive'),
    };

    final narrow = MediaQuery.sizeOf(context).width < DashBreakpoints.sm;
    Widget row(int i) {
      final r = _rows[i];
      final problem = problems[i];
      final unit = loyaltyUnit(t, mode, num.tryParse(r.cost.trim()));
      return Column(
        key: ValueKey('reward-row-${_keys[i]}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xs,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: Space.md,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: MadarClippedText(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                ),
              ),
              SizedBox(
                width: narrow ? Space.xxl * 3 : Space.xxl * 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.xs + DashMetrics.hair,
                  children: [
                    Text(
                      unit,
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                    DashTextInput(
                      key: ValueKey('reward-cost-${r.menuItemId}'),
                      value: r.cost,
                      onChanged: (v) => _setCost(i, v),
                      semanticLabel: '${r.name} · $unit',
                      mono: true,
                      enabled: canEdit,
                      invalid: problem == RewardProblem.cost,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      onSubmitted: canEdit
                          ? (_) => unawaited(_save(mode, problems))
                          : null,
                    ),
                  ],
                ),
              ),
              if (canEdit)
                DashIconButton(
                  icon: 'trash-2',
                  semanticLabel: t('common.remove'),
                  onPressed: () => _remove(i),
                ),
            ],
          ),
          if (problem != null)
            Semantics(
              liveRegion: true,
              child: Row(
                spacing: Space.xs,
                children: [
                  DashIcon(
                    'alert-triangle',
                    size: IconSize.xs,
                    color: rewardBlocking(problem)
                        ? c.errorText
                        : DashTone.warning.foreground(c),
                  ),
                  Expanded(
                    child: Text(
                      problemText(problem),
                      style: DashType.small.copyWith(
                        color: rewardBlocking(problem)
                            ? c.errorText
                            : DashTone.warning.foreground(c),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Column(
      key: const ValueKey('loyalty-rewards'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        if (inherited) LoyaltyNote(t('loyalty.rewardsInherited')),
        if (settings.rewardAnyItem == true)
          LoyaltyNote(
            t(
              'loyalty.rewardsAnyItemOn',
              args: {'cost': loyaltyCost(t, mode, settings.defaultRewardCost)},
            ),
            warning: true,
          ),
        LoyaltyCard(
          spacing: Space.md,
          children: [
            if (_rows.isEmpty)
              DashEmptyState(
                framed: false,
                title: t('loyalty.noRewards'),
                description: t('loyalty.noRewardsHint'),
              )
            else
              for (var i = 0; i < _rows.length; i++) row(i),
            if (canEdit)
              LoyaltyItemPicker(
                label: t('loyalty.addReward'),
                hint: t('loyalty.pickItemHint'),
                menu: menu ?? const [],
                taken: {for (final r in _rows) r.menuItemId},
                picked: _picked,
                onPicked: (id) => setState(() => _picked = id),
                onAdd: () => _add(menu ?? const [], settings),
              ),
          ],
        ),
        if (mode == 'visits')
          EarningItemsCard(
            orgId: widget.orgId,
            branchId: branchId,
            perLineItem: settings.stampPerLineItem == true,
          ),
        if (canEdit)
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              DashButton(
                key: const ValueKey('rewards-save'),
                label: t('common.save'),
                loading: _saving,
                onPressed: (!dirty && !inherited) || blocking
                    ? null
                    : () => _save(mode, problems),
              ),
              if (dirty)
                DashButton(
                  key: const ValueKey('rewards-discard'),
                  label: t('loyalty.discardChanges'),
                  variant: DashButtonVariant.ghost,
                  onPressed: () =>
                      setState(() => _seed(rewardRowsFrom(cat.items))),
                ),
            ],
          ),
      ],
    );
  }
}

/// The items that COLLECT a stamp (stamp cards only): empty means the whole
/// menu collects. A list that will not load reads as empty — the safe
/// reading — with no error panel of its own.
class EarningItemsCard extends ConsumerStatefulWidget {
  const EarningItemsCard({
    required this.orgId,
    required this.branchId,
    required this.perLineItem,
    super.key,
  });

  final String orgId;
  final String? branchId;

  /// Whether the programme counts per item. Off, the list is inert.
  final bool perLineItem;

  @override
  ConsumerState<EarningItemsCard> createState() => _EarningItemsCardState();
}

class _EarningItemsCardState extends ConsumerState<EarningItemsCard> {
  EarningItemList? _from;
  List<EarningRow> _rows = const [];
  bool _reseed = false;
  String? _picked;
  bool _saving = false;

  void _sync(EarningItemList l) {
    if (identical(l, _from)) return;
    final edited = _from != null && earningChanged(_rows, _from!.items);
    if (_from == null || _reseed || !edited) _rows = earningRowsFrom(l.items);
    _reseed = false;
    _from = l;
  }

  Future<void> _save() async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _saving = true);
    try {
      await api.loyalty.putLoyaltyEarningItems(
        body: PutEarningItems(
          branchId: widget.branchId,
          menuItemIds: earningToWire(_rows),
          explicitNulls: const {'branch_id'},
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(context, loyaltyServerError(e, t).message);
        setState(() => _saving = false);
      }
      return;
    }
    bus.invalidate(const [LoyaltyPaths.earningItems]);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _reseed = true;
    });
    DashToast.success(context, t('loyalty.earningSaved'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final q = ref.watch(earningItemsProvider(widget.branchId));
    final menu = widget.orgId.isEmpty
        ? null
        : ref.watch(loyaltyMenuProvider(widget.orgId)).value;
    final canEdit = ref.watch(
      loyaltyAccessProvider.select((a) => a.canEditProgram),
    );
    if (q.awaitingFirst) {
      return const DashSkeleton(
        key: ValueKey('loyalty-earning-loading'),
        height: Space.xxl * 4,
        radius: Radii.card,
      );
    }
    final list = q.value;
    if (list != null) _sync(list);
    final saved = list?.items ?? const <EarningItem>[];
    final dirty = earningChanged(_rows, saved);
    final inherited = list?.inherited == true && widget.branchId != null;

    return LoyaltyCard(
      key: const ValueKey('loyalty-earning'),
      spacing: Space.md,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('loyalty.earningItems'),
              style: DashType.bodyStrong.copyWith(color: c.textPrimary),
            ),
            Text(
              _rows.isEmpty
                  ? t('loyalty.earningItemsAll')
                  : t('loyalty.earningItemsSome'),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ],
        ),
        if (!widget.perLineItem) LoyaltyNote(t('loyalty.earningItemsInert')),
        if (inherited) LoyaltyNote(t('loyalty.earningItemsInherited')),
        for (var i = 0; i < _rows.length; i++)
          Row(
            key: ValueKey('earning-row-${_rows[i].menuItemId}'),
            spacing: Space.md,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: DashMetrics.target,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: MadarClippedText(
                      _rows[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashType.body.copyWith(color: c.textPrimary),
                    ),
                  ),
                ),
              ),
              if (canEdit)
                DashIconButton(
                  icon: 'trash-2',
                  semanticLabel: t('common.remove'),
                  onPressed: () =>
                      setState(() => _rows = [..._rows]..removeAt(i)),
                ),
            ],
          ),
        if (canEdit) ...[
          LoyaltyItemPicker(
            label: t('loyalty.addEarningItem'),
            menu: menu ?? const [],
            taken: {for (final r in _rows) r.menuItemId},
            picked: _picked,
            onPicked: (id) => setState(() => _picked = id),
            onAdd: () {
              final item = (menu ?? const <MenuItem>[])
                  .where((m) => m.id == _picked)
                  .firstOrNull;
              if (item == null || !menuItemOfferable(item)) return;
              if (_rows.any((r) => r.menuItemId == item.id)) return;
              setState(() {
                _rows = [..._rows, (menuItemId: item.id, name: item.name)];
                _picked = null;
              });
            },
          ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              DashButton(
                key: const ValueKey('earning-save'),
                label: t('common.save'),
                loading: _saving,
                onPressed: !dirty && !inherited ? null : _save,
              ),
              if (dirty)
                DashButton(
                  key: const ValueKey('earning-discard'),
                  label: t('loyalty.discardChanges'),
                  variant: DashButtonVariant.ghost,
                  onPressed: () =>
                      setState(() => _rows = earningRowsFrom(saved)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
