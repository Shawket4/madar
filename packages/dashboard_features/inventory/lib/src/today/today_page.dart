/// Today (`/inventory/today`, the INV-TOD rows; web
/// `src/features/inventory/today-page.tsx`): the morning briefing — the
/// first-run nudge, four KPIs, what is running low (with a purchase order a
/// tap away), what arrives today and what was thrown away today.
///
/// No in-page capability checks (INV-TOD-033): Create PO, Receive and Log
/// waste are offered to whoever reaches the page; a refusal comes back as
/// the server's words in the dialog's toast.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/no_org.dart';
import 'today_parts.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    if (orgId == null) {
      return InventoryNoOrgPage(title: t('inventory.today.title'));
    }
    final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
    final data = TodayData.watch(ref, orgId: orgId, branchId: branchId);
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;
    final arriving = TodayArrivingSection(data: data);
    final waste = TodayWasteSection(data: data);
    return DashPageScaffold(
      title: t('inventory.today.title'),
      subtitle: t('inventory.today.subtitle'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          if (data.firstRun) const TodayFirstRunCard(),
          TodayKpiStrip(data: data),
          TodayLowStockSection(data: data),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xl,
              children: [
                Expanded(child: arriving),
                Expanded(child: waste),
              ],
            )
          else ...[
            arriving,
            waste,
          ],
        ],
      ),
    );
  }
}
