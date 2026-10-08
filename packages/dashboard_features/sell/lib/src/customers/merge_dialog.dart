/// Merge a duplicate into the customer that stays (the web's
/// `features/customers/merge-dialog.tsx`, SELL-CUS-034 … 039). A loyalty
/// card decides the direction: when only the opened customer is a member
/// (or the server refuses with `CUSTOMER_MERGE_MEMBER_SURVIVES`) the merge
/// turns round, says why, and the same button confirms it.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'customers_data.dart';
import 'people_widgets.dart';
import 'person_surface.dart';

/// Opens the merge for [duplicate]; resolves with the customer that was
/// kept, or null when cancelled.
Future<CustomerDetail?> showMergeDialog(
  BuildContext context, {
  required Customer duplicate,
}) => showDashDialog<CustomerDetail>(
  context,
  builder: (context) => MergeDialog(duplicate: duplicate),
);

class MergeDialog extends ConsumerStatefulWidget {
  const MergeDialog({required this.duplicate, super.key});

  final Customer duplicate;

  @override
  ConsumerState<MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends ConsumerState<MergeDialog> {
  Customer? _into;

  /// The server said the member must stay, about a pick that did not look
  /// like one.
  bool _refused = false;
  bool _pending = false;

  Customer get _dup => widget.duplicate;

  bool get _reversed =>
      _into != null &&
      (_refused || (_dup.isMember == true && _into!.isMember != true));

  Customer get _from => _reversed ? _into! : _dup;

  Customer? get _kept => _reversed ? _dup : _into;

  bool get _bothMembers => _dup.isMember == true && _into?.isMember == true;

  Future<void> _submit() async {
    final kept = _kept;
    if (kept == null) return;
    final t = ref.read(tProvider);
    final reversed = _reversed;
    setState(() => _pending = true);
    try {
      final result = await ref
          .read(apiProvider)
          .customers
          .mergeCustomer(
            id: _from.id,
            body: MergeCustomerRequest(into: kept.id),
          );
      if (!mounted) return;
      DashToast.success(context, t('customers.merged'));
      invalidatePeople(ref);
      Navigator.of(context).pop(result);
    } on Object catch (e) {
      if (!mounted) return;
      // Not an error to show and forget: an offer to merge the other way
      // round, which the person confirms with the same button.
      if (isMemberMustSurvive(e) && !reversed) {
        setState(() => _refused = true);
        return;
      }
      DashToast.error(context, peopleErrorMessage(e, t));
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final into = _into;
    final kept = _kept;
    return DashSurface(
      title: t('customers.mergeTitle'),
      description: t('customers.mergeBody', args: {'name': _dup.name}),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          label: _reversed && kept != null
              ? t('customers.mergeReversed', args: {'name': kept.name})
              : t('customers.merge'),
          loading: _pending,
          onPressed: kept == null ? null : _submit,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              Text(
                t('customers.mergeWith'),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              _MergePicker(
                exclude: _dup.id,
                picked: into,
                onPick: (p) => setState(() {
                  _into = p;
                  _refused = false;
                }),
              ),
            ],
          ),
          if (into != null && kept != null)
            StatusNote(
              children: [
                if (_reversed)
                  NoteText(
                    t(
                      'customers.mergeMemberStays',
                      args: {'member': kept.name, 'other': _from.name},
                    ),
                    key: const ValueKey('merge-reversed'),
                  ),
                if (_bothMembers)
                  NoteText(
                    t(
                      'customers.mergeBothMembers',
                      args: {'from': _from.name, 'into': kept.name},
                    ),
                    key: const ValueKey('merge-both-members'),
                  ),
                NoteText(
                  t(
                    'customers.mergeConfirm',
                    args: {'from': _from.name, 'into': kept.name},
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The "Merge with" combobox: a trigger ("Search by name or phone…" until
/// picked) opening a server-searched list (300 ms, 20 results, the opened
/// customer left out) — a popover on a wide screen, a sheet on a phone.
class _MergePicker extends StatefulWidget {
  const _MergePicker({
    required this.exclude,
    required this.picked,
    required this.onPick,
  });

  final String exclude;
  final Customer? picked;
  final ValueChanged<Customer> onPick;

  @override
  State<_MergePicker> createState() => _MergePickerState();
}

class _MergePickerState extends State<_MergePicker> {
  final _popover = DashPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.translator;
    final picked = widget.picked;
    Widget trigger(VoidCallback onTap) => DashSelectTrigger(
      key: const ValueKey('merge-pick'),
      label: picked?.name ?? t('customers.mergePick'),
      placeholder: picked == null,
      chevron: 'chevrons-up-down',
      semanticLabel: t('customers.mergeWith'),
      onTap: onTap,
    );
    if (DashBreakpoints.isPhone(context)) {
      return trigger(() async {
        final p = await showDashPickerSheet<Customer>(
          context,
          title: t('customers.mergeWith'),
          fullHeight: true,
          builder: (sheet) => MergeOptions(
            exclude: widget.exclude,
            picked: picked,
            onPick: (c) => Navigator.of(sheet).pop(c),
          ),
        );
        if (p != null) widget.onPick(p);
      });
    }
    return DashPopover(
      controller: _popover,
      matchAnchorWidth: true,
      width: DashMetrics.popover,
      anchor: (context, c) => trigger(c.toggle),
      content: (context, c) => MergeOptions(
        exclude: widget.exclude,
        picked: picked,
        shrinkWrap: true,
        onPick: (p) {
          c.close();
          widget.onPick(p);
        },
      ),
    );
  }
}

/// The searchable list behind the merge picker.
class MergeOptions extends ConsumerStatefulWidget {
  const MergeOptions({
    required this.exclude,
    required this.picked,
    required this.onPick,
    this.shrinkWrap = false,
    super.key,
  });

  final String exclude;
  final Customer? picked;
  final ValueChanged<Customer> onPick;
  final bool shrinkWrap;

  @override
  ConsumerState<MergeOptions> createState() => _MergeOptionsState();
}

class _MergeOptionsState extends ConsumerState<MergeOptions> {
  String _search = '';
  String _q = '';
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _changed(String v) {
    setState(() => _search = v);
    _timer?.cancel();
    _timer = Timer(DashSearchInput.listDelay, () {
      if (mounted) setState(() => _q = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final list = ref.watch(
      customersListProvider((
        q: _q,
        member: null,
        source: null,
        limit: mergePickLimit,
      )),
    );
    final options = [
      for (final p in list.value ?? const <Customer>[])
        if (p.id != widget.exclude) p,
    ];
    final Widget items;
    if (options.isEmpty) {
      items = Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Text(
          list.isLoading ? t('common.loading') : t('common.noResults'),
          textAlign: TextAlign.center,
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
      );
    } else {
      items = ListView.builder(
        shrinkWrap: widget.shrinkWrap,
        padding: const EdgeInsets.all(Space.xs),
        itemCount: options.length,
        itemBuilder: (context, i) => _OptionRow(
          customer: options[i],
          selected: widget.picked?.id == options[i].id,
          onTap: () => widget.onPick(options[i]),
        ),
      );
    }
    return Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.sm,
            Space.sm,
            Space.sm,
            Space.xs,
          ),
          child: DashTextInput(
            key: const ValueKey('merge-search'),
            value: _search,
            autofocus: true,
            leadingIcon: 'search',
            placeholder: t('customers.searchPlaceholder'),
            semanticLabel: t('customers.searchPlaceholder'),
            onChanged: _changed,
          ),
        ),
        if (widget.shrinkWrap)
          Flexible(child: items)
        else
          Expanded(child: items),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.customer,
    required this.selected,
    required this.onTap,
  });

  final Customer customer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final phone = customer.phone;
    final member = customer.isMember == true;
    return DashPressable(
      onTap: onTap,
      selected: selected,
      pressScale: false,
      semanticLabel: member
          ? '${customer.name}, ${context.t('customers.member')}'
          : customer.name,
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        decoration: BoxDecoration(
          color: s.highlighted || s.focused ? c.hover : null,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Row(
          spacing: Space.sm,
          children: [
            SizedBox.square(
              dimension: IconSize.sm,
              child: selected
                  ? DashIcon('check', size: IconSize.sm, color: c.textPrimary)
                  : null,
            ),
            Flexible(
              child: MadarClippedText(
                customer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: autoDirection(customer.name),
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
            ),
            if (member)
              DashIcon('star', size: IconSize.xs, color: c.textSecondary),
            const Spacer(),
            if (phone != null && phone.isNotEmpty)
              PhoneText(
                phone,
                raw: true,
                style: DashType.mono.copyWith(
                  fontSize: 12,
                  color: c.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
