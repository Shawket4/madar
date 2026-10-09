/// `/settings/delivery` Delivery settings (SET-DLV-001..022; web
/// `features/delivery/settings-page.tsx`): the header branch's four
/// channels (in-mall, outside, umbrella, pickup) with their hours, fees and
/// discounts, OTP, prep time, and Save (`PUT /delivery/settings`).
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane. No client gate: the rail hides the
/// pane without `delivery.settings.read`; by URL the read's 403 lands in the
/// error state, a save's in a toast.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show BranchDeliverySettings, Discount;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'delivery_data.dart';

class DeliverySettingsPage extends ConsumerWidget {
  const DeliverySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
    return DashPageScaffold(
      title: t('delivery.settingsTitle'),
      subtitle: t('delivery.settingsSubtitle'),
      width: DashPageWidth.reading,
      body: branchId == null
          ? DashEmptyState(icon: 'store', title: t('delivery.pickBranch'))
          // A new branch is a new form (the web's `key={branchId}`).
          : DeliverySettingsForm(key: ValueKey(branchId), branchId: branchId),
    );
  }
}

/// The branch's settings: skeleton, error with Retry, or the form.
class DeliverySettingsForm extends ConsumerStatefulWidget {
  const DeliverySettingsForm({required this.branchId, super.key});

  final String branchId;

  @override
  ConsumerState<DeliverySettingsForm> createState() =>
      _DeliverySettingsFormState();
}

/// One channel card's words and glyph (`fee` null: the outside channel,
/// whose price is its zones).
typedef _Channel = ({
  DeliveryChannel channel,
  String key,
  String icon,
  String label,
  String hint,
  String? fee,
});

const List<_Channel> _channels = [
  (
    channel: DeliveryChannel.inMall,
    key: 'in-mall',
    icon: 'store',
    label: 'delivery.inMall',
    hint: 'delivery.inMallHint',
    fee: 'delivery.inMallFee',
  ),
  (
    channel: DeliveryChannel.outside,
    key: 'outside',
    icon: 'bike',
    label: 'delivery.outside',
    hint: 'delivery.outsideHint',
    fee: null,
  ),
  (
    channel: DeliveryChannel.umbrella,
    key: 'umbrella',
    icon: 'umbrella',
    label: 'delivery.umbrella',
    hint: 'delivery.umbrellaHint',
    fee: 'delivery.umbrellaFee',
  ),
  (
    channel: DeliveryChannel.pickup,
    key: 'pickup',
    icon: 'shopping-bag',
    label: 'delivery.pickup',
    hint: 'delivery.pickupHint',
    fee: 'delivery.pickupFee',
  ),
];

/// The skeleton bars' height (`h-[72px]`) and the prep field's width
/// (`w-40`).
const double _skeletonBar = 72;
const double _prepWidth = 160;

class _DeliverySettingsFormState extends ConsumerState<DeliverySettingsForm> {
  final _formKey = GlobalKey<FormState>();
  DeliveryForm? _form;

  /// The answer [_form] was filled from, and whether the person changed it
  /// since: until then a refreshed answer refills the form.
  BranchDeliverySettings? _from;
  bool _edited = false;
  bool _busy = false;

  void _follow(BranchDeliverySettings s) {
    if (identical(s, _from) || (_edited && _form != null)) return;
    _from = s;
    _form = DeliveryForm.from(s);
  }

  void _edit(VoidCallback change) => setState(() {
    _edited = true;
    change();
  });

  /// A wrong value inside a switched-off channel: the web blocks Save with
  /// its message hidden; here it says why.
  String? _hiddenProblem(Translator t) {
    final f = _form!;
    for (final c in DeliveryChannel.values) {
      if (!f[c].enabled && !DeliveryForm.feeOk(f[c].fee)) {
        return t('delivery.errFeeNonNeg');
      }
    }
    if (!f[DeliveryChannel.outside].enabled && !f.distanceOk) {
      return t('delivery.errDistancePositive');
    }
    return null;
  }

  Future<void> _save() async {
    final f = _form;
    if (_busy || f == null) return;
    final t = ref.read(tProvider);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final hidden = _hiddenProblem(t);
    if (hidden != null) {
      DashToast.error(context, hidden);
      return;
    }
    final api = ref.read(apiProvider).delivery;
    final bus = ref.read(realtimeBusProvider);
    final read = ref.read(deliverySettingsProvider(widget.branchId)).value;
    setState(() => _busy = true);
    try {
      await api.putBranchSettings(body: f.toInput(widget.branchId));
    } on Object catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        DashToast.error(context, errorMessage(e, t));
      }
      return;
    }
    invalidateBranchSettings(bus);
    if (!mounted) return;
    // The refetch the save asked for refills the form with what was saved.
    setState(() {
      _busy = false;
      _edited = false;
      _from = read;
    });
    DashToast.success(context, t('delivery.branchSettingsSaved'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final q = ref.watch(deliverySettingsProvider(widget.branchId));
    if (q.failed) {
      return DashErrorState(
        title: t('delivery.settingsLoadFailed'),
        message: errorMessage(q.error, t),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () =>
            ref.invalidate(deliverySettingsProvider(widget.branchId)),
      );
    }
    final s = q.value;
    if (s == null) {
      return Semantics(
        key: const ValueKey('dlv-loading'),
        label: t('common.loading'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            for (var i = 0; i < 4; i++)
              const DashSkeleton(height: _skeletonBar, radius: Radii.card),
          ],
        ),
      );
    }
    _follow(s);
    final f = _form!;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          for (final c in _channels) _channelCard(t, f, c, wide),
          _card(
            wide,
            _SwitchRow(
              key: const ValueKey('dlv-otp'),
              icon: 'shield-check',
              label: t('delivery.otpRequired'),
              hint: t('delivery.otpRequiredHint'),
              value: f.otpRequired,
              onChanged: (v) => _edit(() => f.otpRequired = v),
            ),
          ),
          _card(
            wide,
            DashFormField<double?>(
              label: t('delivery.prepTime'),
              description: t('delivery.prepTimeHint'),
              value: f.prepMinutes,
              validator: (v) =>
                  DeliveryForm.prepOk(v) ? null : t('delivery.errPrepNonNeg'),
              builder: (context, invalid) => Align(
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(
                  width: _prepWidth,
                  child: DashNumberInput(
                    key: const ValueKey('dlv-prep'),
                    value: f.prepMinutes,
                    decimals: 0,
                    allowEmpty: true,
                    invalid: invalid,
                    semanticLabel: t('delivery.prepTime'),
                    onChanged: (v) => _edit(() => f.prepMinutes = v),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: DashButton(
                key: const ValueKey('dlv-save'),
                label: t('common.save'),
                loading: _busy,
                onPressed: _save,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `rounded-2xl border bg-card p-4 sm:p-5`.
  Widget _card(bool wide, Widget child) => DashCard(
    padding: EdgeInsets.all(wide ? Space.card : Space.lg),
    child: child,
  );

  /// Two fields side by side from 640, stacked below (`sm:grid-cols-2`).
  Widget _pair(bool wide, Widget a, Widget b) => wide
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.md,
          children: [
            Expanded(child: a),
            Expanded(child: b),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [a, b],
        );

  Widget _channelCard(Translator t, DeliveryForm f, _Channel c, bool wide) {
    final ch = f[c.channel];
    final k = c.key;
    final children = <Widget>[
      _SwitchRow(
        key: ValueKey('dlv-$k'),
        icon: c.icon,
        label: t(c.label),
        hint: t(c.hint),
        value: ch.enabled,
        onChanged: (v) => _edit(() => ch.enabled = v),
      ),
    ];
    if (ch.enabled) {
      children.add(
        _pair(
          wide,
          DashTimeFormField(
            key: ValueKey('dlv-$k-open'),
            label: t('delivery.openTime'),
            value: ch.open,
            clearable: true,
            onChanged: (v) => _edit(() => ch.open = timeFromField(v)),
          ),
          DashTimeFormField(
            key: ValueKey('dlv-$k-close'),
            label: t('delivery.closeTime'),
            value: ch.close,
            clearable: true,
            onChanged: (v) => _edit(() => ch.close = timeFromField(v)),
          ),
        ),
      );
      final discount = _discountField(t, ch, k);
      final feeKey = c.fee;
      if (feeKey == null) {
        children
          ..add(
            DashNumberField(
              key: const ValueKey('dlv-distance'),
              label: t('delivery.maxRoadDistance'),
              value: f.maxDistance,
              decimals: 0,
              allowEmpty: true,
              validator: (_) =>
                  f.distanceOk ? null : t('delivery.errDistancePositive'),
              onChanged: (v) => _edit(() {
                f.maxDistance = v;
                f.maxDistanceEdited = true;
              }),
            ),
          )
          ..add(discount);
      } else {
        children.add(
          _pair(
            wide,
            DashNumberField(
              key: ValueKey('dlv-$k-fee'),
              label: t(feeKey),
              value: ch.fee,
              decimals: 2,
              allowEmpty: true,
              description: c.channel == DeliveryChannel.pickup
                  ? t('delivery.pickupFeeHint')
                  : null,
              validator: (v) =>
                  DeliveryForm.feeOk(v) ? null : t('delivery.errFeeNonNeg'),
              onChanged: (v) => _edit(() => ch.fee = v),
            ),
            discount,
          ),
        );
      }
      if (c.channel == DeliveryChannel.inMall) {
        children.add(
          _SwitchRow(
            key: const ValueKey('dlv-location'),
            icon: 'map-pin',
            label: t('delivery.inMallRequireLocation'),
            hint: t('delivery.inMallRequireLocationHint'),
            value: f.requireLocation,
            inset: true,
            onChanged: (v) => _edit(() => f.requireLocation = v),
          ),
        );
      }
    }
    return _card(
      wide,
      Column(
        key: ValueKey('dlv-card-$k'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: children,
      ),
    );
  }

  /// The channel's discount: "No discount", then every discount of the org
  /// (none while they load or when they fail). A saved discount missing from
  /// the list shows an empty trigger and is sent back as it is.
  Widget _discountField(Translator t, ChannelForm ch, String k) {
    final orgId = ref.watch(orgIdProvider);
    final lang = ref.watch(localeProvider);
    final fmt = ref.watch(formatProvider);
    final discounts = orgId == null
        ? const <Discount>[]
        : ref.watch(deliveryDiscountsProvider(orgId)).value ??
              const <Discount>[];
    return DashSelectField<String>(
      key: ValueKey('dlv-$k-discount'),
      label: t('delivery.channelDiscount'),
      description: t('delivery.channelDiscountHint'),
      value: ch.discountId ?? '',
      placeholder: '',
      options: [
        DashOption(value: '', label: t('delivery.noDiscount')),
        for (final d in discounts)
          DashOption(value: d.id, label: discountLabel(d, lang, fmt)),
      ],
      onChanged: (v) => _edit(() => ch.discountId = v.isEmpty ? null : v),
    );
  }
}

/// A switch with its glyph, label and hint (a channel's head, OTP, the
/// in-mall GPS row on its `bg-secondary/60` inset). A tap anywhere on the
/// words toggles it, as the web's label does.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.inset = false,
    super.key,
  });

  final String icon;
  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final row = Row(
      spacing: Space.md,
      children: [
        DashIcon(icon, size: IconSize.sm, color: c.textSecondary),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!value),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DashMetrics.hair,
              children: [
                Text(
                  label,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                Text(
                  hint,
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ),
        DashSwitch(value: value, semanticLabel: label, onChanged: onChanged),
      ],
    );
    if (!inset) return row;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.md,
        Space.xs,
        Space.xs,
        Space.xs,
      ),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: row,
    );
  }
}
