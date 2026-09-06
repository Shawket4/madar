import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

/// A colour-coded chip for the five attendance statuses and the four request
/// statuses. The status string comes from the server verbatim; an unrecognised
/// one renders neutrally rather than throwing, so a future status added
/// backend-side degrades to "shown but uncoloured" instead of a crash.
class StatusChip extends ConsumerWidget {
  const StatusChip({required this.status, this.prefix = 'status', super.key});

  final String status;

  /// `status` for attendance, `req` for leave/advance requests.
  final String prefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final scheme = Theme.of(context).colorScheme;

    final color = switch (status) {
      'present' || 'approved' => scheme.primary,
      'late' || 'half_day' || 'pending' => scheme.tertiary,
      'absent' || 'rejected' => scheme.error,
      'on_leave' => scheme.secondary,
      _ => scheme.outline,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        t('$prefix.$status'),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
