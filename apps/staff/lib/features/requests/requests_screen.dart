import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

import '../../app/providers.dart';
import '../../format.dart';
import '../../ui/kit.dart';
import '../home/home_screen.dart' show requestKindIcon, requestWindow;

/// Asking permission before the penalty.
///
/// Five things an employee can ask for, all of which suppress the deduction the
/// rules would otherwise charge that day: leave, arriving late, leaving early,
/// stepping out mid-shift, and a mission. The SERVER decides which fields each
/// kind needs and says so in its error, so this screen only collects them.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  String _kind = 'leave';
  DateTime _from = DateTime.now().add(const Duration(days: 1));
  DateTime? _to;
  TimeOfDay _fromTime = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _toTime = const TimeOfDay(hour: 14, minute: 0);
  final _note = TextEditingController();
  String? _leaveTypeId;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _isSpan => _kind == 'leave' || _kind == 'mission';
  bool get _needsFrom => _kind == 'early_departure' || _kind == 'excuse';
  bool get _needsTo => _kind == 'late_arrival' || _kind == 'excuse';

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    final t = ref.read(tProvider);
    if (_isSpan && _to == null) {
      setState(() => _error = t('req.needDates'));
      return;
    }
    final core = ref.read(coreProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await core.bridge.staffCreateRequest(
        kind: _kind,
        onDate: isoDate(_from),
        endDate: _isSpan ? isoDate(_to ?? _from) : null,
        fromTime: _needsFrom ? _hhmm(_fromTime) : null,
        toTime: _needsTo ? _hhmm(_toTime) : null,
        leaveTypeId: _kind == 'leave' ? _leaveTypeId : null,
        isHalfDay: false,
        title: _kind == 'mission' ? _note.text.trim() : null,
        reason: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      ref
        ..invalidate(requestsProvider)
        ..invalidate(leaveBalancesProvider);
      _note.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t('req.sent'))));
    } on MadarError catch (e) {
      // The server's message names exactly what is missing; show it verbatim.
      if (mounted) setState(() => _error = core.bridge.humanMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final balances = ref.watch(leaveBalancesProvider);
    final requests = ref.watch(requestsProvider);

    // The first balance is the default leave type — the app has no picker for
    // it, and a manager can change it when deciding.
    _leaveTypeId ??= balances.maybeWhen(
      data: (rows) => rows.isEmpty ? null : rows.first.leaveTypeId,
      orElse: () => null,
    );

    return StaffPage(
      title: t('req.title'),
      onRefresh: () async {
        ref
          ..invalidate(requestsProvider)
          ..invalidate(leaveBalancesProvider);
      },
      children: [
        balances.maybeWhen(
          data: (rows) => rows.isEmpty
              ? const SizedBox.shrink()
              : Row(
                  children: [
                    for (var i = 0; i < rows.length && i < 3; i++) ...[
                      Expanded(child: _BalanceCard(balance: rows[i])),
                      if (i < 2 && i < rows.length - 1)
                        const SizedBox(width: Space.sm),
                    ],
                  ],
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: Space.md),
        _Form(
          kind: _kind,
          onKind: (k) => setState(() {
            _kind = k;
            _error = null;
          }),
          isSpan: _isSpan,
          needsFrom: _needsFrom,
          needsTo: _needsTo,
          from: _from,
          to: _to,
          fromTime: _fromTime,
          toTime: _toTime,
          note: _note,
          error: _error,
          busy: _busy,
          onFrom: (d) => setState(() => _from = d),
          onTo: (d) => setState(() => _to = d),
          onFromTime: (v) => setState(() => _fromTime = v),
          onToTime: (v) => setState(() => _toTime = v),
          onSubmit: _submit,
        ),
        const SizedBox(height: Space.lg),
        FieldLabel(t('req.past')),
        const SizedBox(height: Space.sm),
        requests.when(
          loading: () => const SkeletonList(count: 3),
          error: (e, _) => ErrorState(
            message: '$e',
            retryLabel: t('common.retry'),
            onRetry: () => ref.invalidate(requestsProvider),
          ),
          data: (rows) => rows.isEmpty
              ? EmptyState(
                  icon: 'sun.max',
                  title: t('req.empty'),
                  message: t('req.emptyHint'),
                )
              : Column(
                  children: [
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: _RequestRow(request: r),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.balance});

  final LeaveBalanceView balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    // A type with no quota is unlimited, not exhausted — showing "0 left" for
    // sick leave would be a lie that stops people asking.
    final unlimited = balance.entitledCentidays == 0;

    return MadarCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 2,
      ),
      radius: Radii.sm + 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            balance.leaveTypeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MadarType.labelSm.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: 2),
          Num(
            unlimited ? '∞' : formatDays(balance.remainingCentidays),
            style: MadarType.numLg,
            color: colors.accent,
          ),
          if (!unlimited)
            Text(
              t('req.ofDays', {'days': formatDays(balance.entitledCentidays)}),
              style: MadarType.labelSm.copyWith(color: colors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({
    required this.kind,
    required this.onKind,
    required this.isSpan,
    required this.needsFrom,
    required this.needsTo,
    required this.from,
    required this.to,
    required this.fromTime,
    required this.toTime,
    required this.note,
    required this.error,
    required this.busy,
    required this.onFrom,
    required this.onTo,
    required this.onFromTime,
    required this.onToTime,
    required this.onSubmit,
  });

  final String kind;
  final ValueChanged<String> onKind;
  final bool isSpan;
  final bool needsFrom;
  final bool needsTo;
  final DateTime from;
  final DateTime? to;
  final TimeOfDay fromTime;
  final TimeOfDay toTime;
  final TextEditingController note;
  final String? error;
  final bool busy;
  final ValueChanged<DateTime> onFrom;
  final ValueChanged<DateTime> onTo;
  final ValueChanged<TimeOfDay> onFromTime;
  final ValueChanged<TimeOfDay> onToTime;
  final VoidCallback onSubmit;

  static const _kinds = [
    'leave',
    'late_arrival',
    'early_departure',
    'excuse',
    'mission',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;

    return MadarCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('req.newLeave'),
            style: MadarType.h3.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final k in _kinds)
                _KindChip(
                  label: t('kind.$k'),
                  selected: k == kind,
                  onTap: () => onKind(k),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: _Field(
                  label: isSpan ? t('req.from') : t('common.date'),
                  value: isoDate(from),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: from,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 30),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) onFrom(picked);
                  },
                ),
              ),
              if (isSpan) ...[
                const SizedBox(width: Space.sm),
                Expanded(
                  child: _Field(
                    label: t('req.to'),
                    value: to == null ? '—' : isoDate(to!),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: to ?? from,
                        firstDate: from,
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) onTo(picked);
                    },
                  ),
                ),
              ],
            ],
          ),
          if (needsFrom || needsTo) ...[
            const SizedBox(height: Space.sm),
            Row(
              children: [
                if (needsFrom)
                  Expanded(
                    child: _Field(
                      label: kind == 'early_departure'
                          ? t('req.leaveAt')
                          : t('req.from'),
                      value:
                          '${fromTime.hour.toString().padLeft(2, '0')}:'
                          '${fromTime.minute.toString().padLeft(2, '0')}',
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: fromTime,
                        );
                        if (picked != null) onFromTime(picked);
                      },
                    ),
                  ),
                if (needsFrom && needsTo) const SizedBox(width: Space.sm),
                if (needsTo)
                  Expanded(
                    child: _Field(
                      label: kind == 'late_arrival'
                          ? t('req.arriveBy')
                          : t('req.to'),
                      value:
                          '${toTime.hour.toString().padLeft(2, '0')}:'
                          '${toTime.minute.toString().padLeft(2, '0')}',
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: toTime,
                        );
                        if (picked != null) onToTime(picked);
                      },
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.sm),
          TextField(
            controller: note,
            minLines: 2,
            maxLines: 3,
            style: MadarType.body.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: t('req.note'),
              hintStyle: MadarType.body.copyWith(color: colors.textMuted),
              filled: true,
              fillColor: colors.surface,
              contentPadding: const EdgeInsets.all(Space.md),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.sm),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.sm),
                borderSide: BorderSide(color: colors.accent),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: Space.sm),
            NoticeBanner(
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
              text: error!,
            ),
          ],
          const SizedBox(height: Space.md),
          PrimaryButton(
            label: busy ? t('req.sending') : t('req.send'),
            icon: 'arrow.up.right',
            busy: busy,
            onPressed: busy ? null : onSubmit,
          ),
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: selected ? colors.accent : colors.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: MadarType.labelSm.copyWith(
            color: selected ? colors.textOnAccent : colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// A tappable read-only field — the handoff's 44px date/time input.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        const SizedBox(height: Space.xs),
        TactileScale(
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: colors.border),
            ),
            alignment: AlignmentDirectional.centerStart,
            child: Num(value),
          ),
        ),
      ],
    );
  }
}

class _RequestRow extends ConsumerWidget {
  const _RequestRow({required this.request});

  final StaffRequestView request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;

    return MadarCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 2,
      ),
      child: Row(
        children: [
          IconTile(
            icon: requestKindIcon(request.kind),
            background: colors.accentBg,
            tint: colors.accent,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t('kind.${request.kind}'),
                  style: MadarType.body.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Num(
                  requestWindow(request),
                  style: MadarType.num.copyWith(fontWeight: FontWeight.w500),
                  color: colors.textSecondary,
                ),
                if (request.decisionNote.isNotEmpty)
                  Text(
                    request.decisionNote,
                    style: MadarType.labelSm.copyWith(color: colors.textMuted),
                  ),
              ],
            ),
          ),
          StatusChip(
            label: t('req.${request.status}'),
            tone: switch (request.status) {
              'approved' => ChipTone.success,
              'rejected' => ChipTone.danger,
              'pending' => ChipTone.warning,
              _ => ChipTone.neutral,
            },
          ),
        ],
      ),
    );
  }
}
