/// `/settings/bookings` Bookings (SET-BKG-001 … 021; web
/// `features/settings/bookings-settings-pane.tsx`): pick a branch, then edit
/// its booking rules in the dialog (`booking_rules_dialog.dart`). Every
/// branch has its own rules; there is no organisation default.
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane. No in-page guard: the rail hides it
/// without `bookings.edit`, and by URL the dialog's read and Save let the
/// server refuse (SET-BKG-019).
library;

import 'package:dashboard_api/dashboard_api.dart' show Branch;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'booking_rules_dialog.dart';
import 'booking_settings_data.dart';

/// The branch select from 640 px (`sm:w-64`).
const double _selectWidth = Space.xxl * 8;

class BookingSettingsPage extends ConsumerStatefulWidget {
  const BookingSettingsPage({super.key});

  @override
  ConsumerState<BookingSettingsPage> createState() =>
      _BookingSettingsPageState();
}

class _BookingSettingsPageState extends ConsumerState<BookingSettingsPage> {
  /// The picked branch: page-local, independent of the header scope, lost
  /// on leaving the page (SET-BKG-021).
  String? _branchId;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    // `useListBranches({org_id})`, only with an org in scope; the scoped org
    // (a platform admin's pick), never the token's.
    final orgId = ref.watch(orgIdProvider);
    final branches = orgId == null
        ? const <Branch>[]
        : [...?ref.watch(branchesProvider).value?.where(isSelling)];
    final branchId = _branchId;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final select = DashSelect<String>(
      key: const ValueKey('bkg-branch'),
      value: branchId,
      placeholder: t('settings.pickBranch'),
      semanticLabel: t('settings.pickBranch'),
      onChanged: (v) => setState(() => _branchId = v),
      options: [
        for (final b in branches) DashOption(value: b.id, label: b.name),
      ],
    );
    return DashPageScaffold(
      title: t('nav.bookings'),
      subtitle: t('settings.bookingsDesc'),
      width: DashPageWidth.reading,
      body: DashCard(
        key: const ValueKey('bkg-card'),
        padding: const EdgeInsets.all(Space.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Wrap(
              key: const ValueKey('bkg-row'),
              spacing: Space.md,
              runSpacing: Space.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (wide)
                  SizedBox(width: _selectWidth, child: select)
                else
                  select,
                DashButton(
                  key: const ValueKey('bkg-edit'),
                  label: t('settings.editRules'),
                  onPressed: branchId == null
                      ? null
                      : () => showBookingRulesDialog(
                          context,
                          branchId: branchId,
                        ),
                  // The dialog reads the branch's rules on open: warm them.
                  onIntent: branchId == null
                      ? null
                      : () => ref.warm(bookingRulesProvider(branchId)),
                ),
              ],
            ),
            Text(
              t('settings.bookingsPerBranch'),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
