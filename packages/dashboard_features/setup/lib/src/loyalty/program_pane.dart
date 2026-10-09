/// The programme's rules, for the organisation or one branch (the web's
/// `admin/program/{program-pane,collecting-card,signup-card,passes-card,
/// wallet-status,birthday-preview}.tsx`, SET-LOY-008 … 034, 083).
///
/// The form is a copy of the scope's settings: it re-seeds when a refresh
/// lands until the person edits it, validates on Save and then live, and
/// saves the saved settings with the form on top ([programToWire]).
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/setup_note.dart';
import 'loyalty_data.dart';
import 'loyalty_widgets.dart';

class ProgramPane extends ConsumerStatefulWidget {
  const ProgramPane({required this.orgId, required this.branchId, super.key});

  final String orgId;

  /// null = the organisation's own row.
  final String? branchId;

  @override
  ConsumerState<ProgramPane> createState() => _ProgramPaneState();
}

class _ProgramPaneState extends ConsumerState<ProgramPane> {
  /// What the form was seeded from, and the values then (for "changed").
  LoyaltySettings? _from;
  ProgramValues? _seed;
  ProgramValues? _values;
  bool _submitted = false;
  bool _saving = false;

  bool get _dirty => _values != _seed;

  void _sync(LoyaltySettings s) {
    if (identical(s, _from)) return;
    // A refresh re-seeds until the person has edited the form.
    if (_values == null || !_dirty) {
      _seed = _values = programFromWire(s);
    }
    _from = s;
  }

  void _set(String key, Object value) =>
      setState(() => _values = _values!.set(key, value));

  Future<void> _save(LoyaltySettings saved) async {
    final t = ref.read(tProvider);
    setState(() => _submitted = true);
    if (validateProgram(_values!).isNotEmpty) return;
    final values = _values!;
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _saving = true);
    try {
      await api.loyalty.putLoyaltySettings(
        body: programToWire(
          values,
          orgId: widget.orgId,
          branchId: widget.branchId,
          saved: saved,
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(context, errorMessage(e, t));
        setState(() => _saving = false);
      }
      return;
    }
    // `await query.refetch()`: whatever became of the pane.
    bus.invalidate(const [LoyaltyPaths.settings]);
    if (!mounted) return;
    setState(() {
      _saving = false;
      // What is on screen is what was saved: not changed any more, and the
      // refetch re-seeds it with the server's own copy.
      _seed = values;
    });
    DashToast.success(context, t('loyalty.saved'));
  }

  Future<void> _revert() async {
    final t = ref.read(tProvider);
    final branchId = widget.branchId;
    if (branchId == null) return;
    final ok = await showDashConfirm(
      context,
      title: t('loyalty.revertTitle'),
      description: t('loyalty.revertBody'),
      confirmLabel: t('loyalty.revert'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    try {
      await api.loyalty.deleteLoyaltySettings(branchId: branchId);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
      return;
    }
    bus.invalidate(const [LoyaltyPaths.settings]);
    if (!mounted) return;
    // The organisation's programme replaces the branch's: the form follows.
    setState(() {
      _values = null;
      _seed = null;
      _from = null;
    });
    DashToast.success(context, t('loyalty.reverted'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final q = ref.watch(loyaltySettingsProvider(widget.branchId));
    final canEdit = ref.watch(
      loyaltyAccessProvider.select((a) => a.canEditProgram),
    );

    if (q.awaitingFirst) {
      return const Column(
        key: ValueKey('loyalty-program-loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          DashSkeleton(height: Space.xxl * 3 + Space.md, radius: Radii.card),
          DashSkeleton(height: Space.xxl * 6, radius: Radii.card),
        ],
      );
    }
    final saved = q.value;
    if (saved == null) {
      return DashErrorState(
        title: t('loyalty.loadFailed'),
        message: q.hasError ? errorMessage(q.error, t) : null,
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(loyaltySettingsProvider(widget.branchId)),
      );
    }
    _sync(saved);
    final v = _values!;
    final inherited = settingsInherited(saved, widget.branchId);
    final errors = _submitted ? validateProgram(v) : const <String, String>{};
    String? err(String key) => errors[key] == null ? null : t(errors[key]!);
    // A read-only viewer cannot half-edit a form they cannot save.
    ValueChanged<bool>? toggle(String key) =>
        canEdit ? (b) => _set(key, b) : null;
    void submit([String? _]) {
      if (canEdit && !_saving) unawaited(_save(saved));
    }

    LoyaltyField field(
      String key,
      String label, {
      String? hint,
      String? placeholder,
      bool rtl = false,
      bool mono = false,
      bool number = false,
    }) => LoyaltyField(
      key: ValueKey('loyalty-field-$key'),
      label: label,
      value: v.text(key),
      onChanged: (s) => _set(key, s),
      hint: hint,
      placeholder: placeholder,
      error: err(key),
      rtl: rtl,
      mono: mono,
      number: number,
      enabled: canEdit,
      onSubmitted: submit,
    );

    final c = context.madarColors;
    final mode = v.mode;
    final derivedCap = saved.effectiveBalanceCap;
    final geofenced = saved.geofencedBranches ?? 0;
    final platform = ref.watch(authzProvider.select((a) => a.platform));
    final preview = birthdayPreviewOf(v, saved);
    final small = DashType.small.copyWith(color: c.textSecondary);

    final head = LoyaltyCard(
      children: [
        LoyaltyToggle(
          label: t('loyalty.enabled'),
          hint: t('loyalty.enabledHint'),
          value: v.flag('enabled'),
          onChanged: toggle('enabled'),
        ),
        LoyaltyPair(
          first: field('program_name', t('loyalty.programName')),
          second: field(
            'program_name_ar',
            t('loyalty.programNameAr'),
            rtl: true,
          ),
        ),
      ],
    );

    final collecting = LoyaltyCard(
      key: const ValueKey('loyalty-collecting'),
      children: [
        LoyaltyGroup(
          title: t('loyalty.whatTheyCollect'),
          hint: t('loyalty.whatTheyCollectHint'),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashSegmentedControl<String>(
              key: const ValueKey('loyalty-mode'),
              semanticLabel: t('loyalty.whatTheyCollect'),
              enabled: canEdit,
              options: [
                DashOption(value: 'points', label: t('loyalty.modePoints')),
                DashOption(value: 'visits', label: t('loyalty.modeVisits')),
              ],
              value: mode,
              onChanged: (m) => _set('mode', m),
            ),
          ),
        ),
        if (mode == 'points')
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              field(
                'earn_egp_per_point',
                t('loyalty.earnRate'),
                mono: true,
                number: true,
              ),
              LoyaltyToggle(
                label: t('loyalty.onDiscounted'),
                subdued: true,
                value: v.flag('earn_on_discounted'),
                onChanged: toggle('earn_on_discounted'),
              ),
              LoyaltyToggle(
                label: t('loyalty.includeTax'),
                subdued: true,
                value: v.flag('earn_include_tax'),
                onChanged: toggle('earn_include_tax'),
              ),
              Text(t('loyalty.tipsNeverEarn'), style: small),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              LoyaltyToggle(
                label: t('loyalty.stampPerItem'),
                hint: v.flag('stamp_per_line_item')
                    ? t('loyalty.stampPerItemOn')
                    : t('loyalty.stampPerItemOff'),
                value: v.flag('stamp_per_line_item'),
                onChanged: toggle('stamp_per_line_item'),
              ),
              if (v.flag('stamp_per_line_item'))
                Text(t('loyalty.stampPerItemWhich'), style: small),
              Text(t('loyalty.stampFreeItemHint'), style: small),
            ],
          ),
        field(
          'default_reward_cost',
          '${t('loyalty.defaultCost')} (${loyaltyUnit(t, mode, num.tryParse(v.text('default_reward_cost').trim()) ?? 0)})',
          hint: t('loyalty.defaultCostHint'),
          mono: true,
          number: true,
        ),
        LoyaltyToggle(
          label: t('loyalty.anyItem'),
          hint: t('loyalty.anyItemHint'),
          value: v.flag('reward_any_item'),
          onChanged: toggle('reward_any_item'),
        ),
        LoyaltyGroup(
          title: t('loyalty.limits'),
          hint: t('loyalty.limitsHint'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              LoyaltyToggle(
                label: t('loyalty.capBalance'),
                hint: t('loyalty.capBalanceHint'),
                value: v.flag('balance_cap_enabled'),
                onChanged: toggle('balance_cap_enabled'),
              ),
              if (v.flag('balance_cap_enabled')) ...[
                field(
                  'balance_cap',
                  '${t('loyalty.capBalanceMax')} (${loyaltyUnit(t, mode, num.tryParse(v.text('balance_cap').trim()) ?? 0)})',
                  hint: t('loyalty.capBalanceMaxHint'),
                  mono: true,
                  number: true,
                ),
                if (v.text('balance_cap').isEmpty)
                  Text(
                    derivedCap != null
                        ? t(
                            'loyalty.capBalanceDerived',
                            args: {'amount': loyaltyCost(t, mode, derivedCap)},
                          )
                        : t('loyalty.capBalanceNoRewards'),
                    key: const ValueKey('loyalty-cap-derived'),
                    style: small,
                  ),
              ],
              field(
                'max_rewards_per_order',
                t('loyalty.maxRewardsPerOrder'),
                placeholder: t('loyalty.maxRewardsPerOrderNone'),
                hint: t('loyalty.maxRewardsPerOrderHint'),
                mono: true,
                number: true,
              ),
            ],
          ),
        ),
      ],
    );

    Widget block(List<Widget> children) => Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: c.hairline.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: children,
      ),
    );

    final signup = LoyaltyCard(
      key: const ValueKey('loyalty-signup'),
      children: [
        LoyaltyToggle(
          label: t('loyalty.requireOtp'),
          hint: t('loyalty.requireOtpHint'),
          value: v.flag('require_otp'),
          onChanged: toggle('require_otp'),
        ),
        LoyaltyToggle(
          label: t('loyalty.birthdays'),
          hint: t('loyalty.birthdaysHint'),
          value: v.flag('birthday_enabled'),
          onChanged: toggle('birthday_enabled'),
        ),
        if (v.flag('birthday_enabled'))
          block([
            field(
              'birthday_reward_amount',
              t('loyalty.birthdayGift'),
              placeholder: t('loyalty.birthdayGiftNone'),
              hint: t('loyalty.birthdayGiftHint'),
            ),
            field(
              'birthday_message',
              t('loyalty.birthdayMessage'),
              placeholder: t('loyalty.birthdayMessagePlaceholder'),
            ),
            field(
              'birthday_message_ar',
              t('loyalty.birthdayMessageAr'),
              placeholder: t('loyalty.birthdayMessageArPlaceholder'),
              rtl: true,
            ),
            if (preview != null) BirthdayPreviewPanel(settings: preview),
          ]),
        LoyaltyToggle(
          label: t('loyalty.winback'),
          hint: t('loyalty.winbackHint'),
          value: v.flag('winback_enabled'),
          onChanged: toggle('winback_enabled'),
        ),
        if (v.flag('winback_enabled'))
          block([
            field(
              'winback_reward_amount',
              t('loyalty.winbackGift'),
              placeholder: t('loyalty.winbackGiftNone'),
              hint: t('loyalty.winbackGiftHint'),
            ),
            field(
              'winback_message',
              t('loyalty.winbackMessage'),
              placeholder: t('loyalty.winbackMessagePlaceholder'),
              hint: t('loyalty.winbackMessageHint'),
            ),
          ]),
      ],
    );

    final passes = LoyaltyCard(
      key: const ValueKey('loyalty-passes'),
      children: [
        field('terms', t('loyalty.terms')),
        if (geofenced == 0)
          Container(
            key: const ValueKey('loyalty-no-geofence'),
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(Radii.xs),
              border: Border.all(color: c.hairline.withValues(alpha: 0.7)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.sm + DashMetrics.hair,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: DashMetrics.hair),
                  child: DashIcon(
                    'map-pin',
                    size: IconSize.sm,
                    color: c.textSecondary,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.xs,
                    children: [
                      Text(
                        t('loyalty.noGeofence'),
                        style: DashType.bodyMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      Text(t('loyalty.noGeofenceHint'), style: small),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (platform)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.hairline)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: Space.lg),
              child: WalletStatusPanel(branchId: widget.branchId),
            ),
          ),
      ],
    );

    return Column(
      key: const ValueKey('loyalty-program'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        if (!canEdit) SetupNote(t('loyalty.readOnly')),
        if (inherited) SetupNote(t('loyalty.inheritedHint')),
        head,
        collecting,
        signup,
        passes,
        if (canEdit)
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DashButton(
                key: const ValueKey('loyalty-save'),
                label: t('common.save'),
                loading: _saving,
                onPressed: !_dirty && !inherited ? null : submit,
              ),
              if (widget.branchId != null && !inherited)
                DashButton(
                  key: const ValueKey('loyalty-revert'),
                  label: t('loyalty.revert'),
                  icon: 'rotate-ccw',
                  variant: DashButtonVariant.outline,
                  onPressed: _revert,
                ),
              if (errors.isNotEmpty)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    t('loyalty.fixErrors'),
                    key: const ValueKey('loyalty-fix-errors'),
                    style: DashType.small.copyWith(color: c.errorText),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// The greeting exactly as it will be sent (`BirthdayPreview`): rendered by
/// the server from the EDITED values, 400 ms after they stop changing. A
/// preview that fails hides itself (no toast over a form being filled).
class BirthdayPreviewPanel extends ConsumerStatefulWidget {
  const BirthdayPreviewPanel({required this.settings, super.key});

  /// How long the fields must rest before the server is asked.
  static const Duration debounce = Duration(milliseconds: 400);

  final LoyaltySettings settings;

  @override
  ConsumerState<BirthdayPreviewPanel> createState() =>
      _BirthdayPreviewPanelState();
}

class _BirthdayPreviewPanelState extends ConsumerState<BirthdayPreviewPanel> {
  BirthdayPreview? _preview;
  Timer? _timer;
  String? _key;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(BirthdayPreviewPanel old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  void _schedule() {
    final key = birthdayPreviewKey(widget.settings);
    if (key == _key) return;
    _key = key;
    _timer?.cancel();
    _timer = Timer(BirthdayPreviewPanel.debounce, () async {
      final asked = key;
      try {
        final p = await ref
            .read(apiProvider)
            .loyalty
            .previewLoyaltyBirthdayMessage(body: widget.settings);
        if (mounted && asked == _key) setState(() => _preview = p);
      } on Object {
        if (mounted && asked == _key) setState(() => _preview = null);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    if (p == null) return const SizedBox.shrink();
    final c = context.madarColors;
    final style = DashType.body.copyWith(color: c.textPrimary);
    return Container(
      key: const ValueKey('loyalty-birthday-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          Text(
            context.t('loyalty.birthdayPreview'),
            style: DashType.smallMedium.copyWith(color: c.textSecondary),
          ),
          Text(p.en, textDirection: TextDirection.ltr, style: style),
          Text(p.ar, textDirection: TextDirection.rtl, style: style),
        ],
      ),
    );
  }
}

/// Why there is no "Add to Wallet" button (platform only): asked for, never
/// polled. A failure is a red line under the header (cleared by the next
/// Check); a previous result stays beside it.
class WalletStatusPanel extends ConsumerStatefulWidget {
  const WalletStatusPanel({required this.branchId, super.key});

  final String? branchId;

  @override
  ConsumerState<WalletStatusPanel> createState() => _WalletStatusPanelState();
}

class _WalletStatusPanelState extends ConsumerState<WalletStatusPanel> {
  WalletStatus? _status;
  String? _error;
  bool _busy = false;

  Future<void> _run() async {
    final t = ref.read(tProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await ref
          .read(apiProvider)
          .loyalty
          .getLoyaltyWalletStatus(branchId: widget.branchId);
      if (mounted) setState(() => _status = s);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final status = _status;
    final small = DashType.small.copyWith(color: c.textSecondary);

    Widget provider(String name, WalletProvider p) {
      // Configured is not the same as working: Google can refuse.
      final ok = p.configured && p.reachable != false;
      return Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(color: c.hairline.withValues(alpha: 0.7)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.sm + DashMetrics.hair,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: DashMetrics.hair),
              child: DashIcon(
                ok ? 'circle-check' : 'alert-circle',
                size: IconSize.sm,
                color: ok
                    ? DashTone.success.foreground(c)
                    : DashTone.warning.foreground(c),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.xs,
                children: [
                  Text(
                    name,
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  if (p.missing.isNotEmpty) ...[
                    Text(t('loyalty.walletMissing'), style: small),
                    for (final m in p.missing)
                      Text(
                        m,
                        textDirection: TextDirection.ltr,
                        style: DashType.mono.copyWith(
                          fontSize: 11,
                          color: c.textSecondary,
                        ),
                      ),
                  ],
                  if (p.detail case final d?) Text(d, style: small),
                  if (p.configured && p.detail == null)
                    Text(t('loyalty.walletReady'), style: small),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final tiles = status == null
        ? const <Widget>[]
        : [
            provider(t('loyalty.walletApple'), status.apple),
            provider(t('loyalty.walletApns'), status.apns),
            provider(t('loyalty.walletGoogle'), status.google),
          ];
    final twoColumns = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    return Column(
      key: const ValueKey('loyalty-wallet-status'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.sm,
                  children: [
                    DashIcon('wallet', size: IconSize.sm, color: c.textPrimary),
                    Text(
                      t('loyalty.walletStatus'),
                      style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
                Text(t('loyalty.walletStatusHint'), style: small),
              ],
            ),
            DashButton(
              key: const ValueKey('loyalty-wallet-check'),
              label: t('loyalty.walletCheck'),
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              loading: _busy,
              onPressed: _run,
            ),
          ],
        ),
        if (_error case final e?)
          Text(
            e,
            key: const ValueKey('loyalty-wallet-error'),
            style: DashType.small.copyWith(color: c.errorText),
          ),
        if (tiles.isNotEmpty)
          twoColumns
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.sm,
                  children: [
                    for (var i = 0; i < tiles.length; i += 2)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: Space.sm,
                          children: [
                            Expanded(child: tiles[i]),
                            Expanded(
                              child: i + 1 < tiles.length
                                  ? tiles[i + 1]
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.sm,
                  children: tiles,
                ),
      ],
    );
  }
}
