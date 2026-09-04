import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

import '../../app/providers.dart';
import '../../format.dart';
import '../../ui/kit.dart';

/// Who works here — searchable, with a profile behind each row.
class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key});

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  final _search = TextEditingController();
  String _query = '';
  EmployeeView? _open;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final currency = ref.watch(sessionProvider)?.currencyCode ?? '';

    if (_open case final employee?) {
      return _Profile(
        employee: employee,
        currency: currency,
        onBack: () => setState(() => _open = null),
      );
    }

    final roster = ref.watch(rosterProvider(_query));

    return StaffPage(
      title: t('roster.title'),
      onRefresh: () async => ref.invalidate(rosterProvider(_query)),
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              MadarIcon(
                'magnifyingglass',
                tint: colors.textMuted,
                size: IconSize.md,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  style: MadarType.body.copyWith(color: colors.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: t('roster.search'),
                    hintStyle: MadarType.body.copyWith(color: colors.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        roster.when(
          loading: () => const SkeletonList(count: 5),
          error: (e, _) => ErrorState(
            message: '$e',
            retryLabel: t('common.retry'),
            onRetry: () => ref.invalidate(rosterProvider(_query)),
          ),
          data: (rows) => rows.isEmpty
              ? EmptyState(icon: 'person', title: t('roster.noResults'))
              : MadarCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        _RosterRow(
                          employee: rows[i],
                          currency: currency,
                          last: i == rows.length - 1,
                          onTap: () => setState(() => _open = rows[i]),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _RosterRow extends ConsumerWidget {
  const _RosterRow({
    required this.employee,
    required this.currency,
    required this.last,
    required this.onTap,
  });

  final EmployeeView employee;
  final String currency;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm + 2,
        ),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: colors.borderLight)),
        ),
        child: Row(
          children: [
            InitialsTile(name: employee.name),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    employee.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.body.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    [
                      employee.jobTitle,
                      employee.departmentName,
                    ].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.labelSm.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            // Salary is only present when the caller may read payroll; when it
            // is not, the column is simply absent rather than showing zero.
            if (employee.baseSalaryMinor > 0)
              Num(formatAmount(employee.baseSalaryMinor)),
            const SizedBox(width: Space.sm),
            MadarIcon(
              'chevron.forward',
              tint: colors.textMuted,
              size: IconSize.md,
            ),
          ],
        ),
      ),
    );
  }
}

class _Profile extends ConsumerWidget {
  const _Profile({
    required this.employee,
    required this.currency,
    required this.onBack,
  });

  final EmployeeView employee;
  final String currency;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;

    return StaffPage(
      title: t('roster.profile'),
      titleTrailing: TactileScale(
        onTap: onBack,
        child: IconTile(icon: 'chevron.backward', size: 34),
      ),
      children: [
        MadarCard(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(
            children: [
              InitialsTile(name: employee.name, size: 54),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      employee.name,
                      style: MadarType.h3.copyWith(color: colors.textPrimary),
                    ),
                    Text(
                      [
                        employee.jobTitle,
                        employee.departmentName,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: MadarType.labelSm.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    if (employee.phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Num(employee.phone, color: colors.textSecondary),
                    ],
                  ],
                ),
              ),
              StatusChip(
                label: employee.employmentStatus,
                tone: employee.employmentStatus == 'active'
                    ? ChipTone.success
                    : ChipTone.neutral,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        MadarCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (employee.baseSalaryMinor > 0)
                _DetailLine(
                  label: t('roster.salary'),
                  value: '${formatAmount(employee.baseSalaryMinor)} $currency',
                ),
              if (employee.hireDate.isNotEmpty)
                _DetailLine(
                  label: t('roster.hireDate'),
                  value: employee.hireDate,
                ),
              if (employee.employeeNumber.isNotEmpty)
                _DetailLine(
                  label: t('roster.empId'),
                  value: employee.employeeNumber,
                  last: true,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: colors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(child: FieldLabel(label)),
          Num(value, style: MadarType.num.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
