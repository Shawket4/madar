/// The period subtitle under a report's title (REP-ALL-008): a calendar
/// glyph and the scope preset's words ("Last 30 days", "Custom", …).
///
/// Used by Operations (and its Tables tab), Financial, Inventory reports,
/// Legal, Loyalty and Staff discipline (`ops:74-79`, `fin:173-178`,
/// `inv:127-132`, `leg:128-133`, `loy:129-134`, `stf:81-86`).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `CalendarRange` + `t('scope.preset.<preset>')`. A `custom` preset
/// without both dates reads as the default (the scope resolves it).
class ReportPeriodSubtitle extends ConsumerWidget {
  const ReportPeriodSubtitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final preset = ref.watch(currentScopeProvider.select((s) => s.preset));
    final c = context.madarColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        DashIcon('calendar-range', size: IconSize.xs, color: c.textSecondary),
        Flexible(
          child: Text(
            t(preset.labelKey, defaultValue: preset.fallback),
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}
