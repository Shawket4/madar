/// `/bookings` (the web's `features/bookings/bookings-page.tsx`, SELL-BKG
/// rows): the host's day — a list for working the phone and a timeline by
/// table — with create/edit, seat, complete, no-show and cancel in reach.
///
/// No in-page gate (SELL-BKG-074): every control shows to whoever reaches
/// the page and the server refuses what the person may not do.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart'
    show BookingView, CancelBookingRequest, SeatBookingRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../customers/customers_data.dart' show apiWithHeaders;
import '../shared/booking_status.dart';
import '../shared/branch_required.dart';
import '../shared/customer_link.dart';
import '../shared/invalidate.dart';
import '../shared/phone.dart';
import '../shared/sheets.dart';
import '../floor/floor_providers.dart' show floorTablesProvider;
import 'booking_dialog.dart';
import 'booking_settings_dialog.dart';
import 'bookings_parts.dart';
import 'bookings_providers.dart';
import 'bookings_timeline.dart';
import 'bookings_util.dart';
import '../shared/error_text.dart';
import '../shared/export_logo.dart';

class BookingsPage extends ConsumerStatefulWidget {
  const BookingsPage({this.date, this.bookingId, super.key});

  /// The route's builder (routes.dart points here).
  static Widget route(BuildContext context, GoRouterState state) {
    final q = state.uri.queryParameters;
    final date = q['date'];
    return BookingsPage(
      date: isBookingYmd(date) ? date : null,
      bookingId: q['booking'],
    );
  }

  /// `?date=YYYY-MM-DD` (validated): that day (SELL-BKG-030).
  final String? date;

  /// `?booking=`: that booking's dialog once the day loads (SELL-BKG-031).
  final String? bookingId;

  @override
  ConsumerState<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends ConsumerState<BookingsPage> {
  late String _date = widget.date ?? _today();
  String _view = 'list';
  String _filter = 'active';
  bool _exporting = false;
  late DateTime _now = ref.read(clockProvider)();
  Timer? _tick;
  AppLifecycleListener? _lifecycle;

  /// The `?booking=` link already followed.
  String? _followed;

  String _today() => serviceToday(
    ref.read(clockProvider)(),
    ref.read(formatProvider).timezone,
  );

  BookingDayKey? get _dayKey {
    final b = ref.read(sellBranchIdProvider);
    return b == null ? null : (branchId: b, date: _date);
  }

  /// The day list's `refetchInterval` / `refetchOnWindowFocus` (SELL-BKG-004).
  void _refetchDay() {
    final key = _dayKey;
    if (key != null) ref.invalidate(bookingDayProvider(key));
  }

  @override
  void initState() {
    super.initState();
    // Late / Due flip by the clock, not by an event (SELL-BKG-035).
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = ref.read(clockProvider)());
      _refetchDay();
    });
    _lifecycle = AppLifecycleListener(onResume: _refetchDay);
  }

  @override
  void didUpdateWidget(BookingsPage old) {
    super.didUpdateWidget(old);
    // Only a change of the link moves the day; the picker is free after.
    final d = widget.date;
    if (d != null && d != old.date) _date = d;
  }

  @override
  void dispose() {
    _tick?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Follows `?booking=` once that day's list has loaded: the filter goes to
  /// All and the booking's edit dialog opens (any status, SELL-BKG-077); the
  /// link's `date` and `booking` leave the URL whether or not it was found.
  void _followLink(AsyncValue<List<BookingView>> listQ) {
    final id = widget.bookingId;
    if (id == null || id == _followed || !listQ.hasValue || listQ.hasError) {
      return;
    }
    if (widget.date != null && widget.date != _date) return;
    _followed = id;
    final linked = listQ.value!.where((b) => b.id == id).firstOrNull;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uri = GoRouterState.of(context).uri;
      final q = Map<String, String>.of(uri.queryParameters)
        ..remove('date')
        ..remove('booking');
      GoRouter.of(context).go(
        Uri(path: uri.path, queryParameters: q.isEmpty ? null : q).toString(),
      );
      if (linked == null) return;
      setState(() => _filter = 'all');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openDialog(linked);
      });
    });
  }

  void _openDialog(BookingView? booking) {
    final branchId = ref.read(sellBranchIdProvider);
    if (branchId == null) return;
    showBookingDialog(
      context,
      branchId: branchId,
      date: _date,
      booking: booking,
    );
  }

  /// Intent on a control opening the dialog on [booking] (null: a new one).
  void _warmDialog(BookingView? booking) {
    final branchId = ref.read(sellBranchIdProvider);
    if (branchId == null) return;
    warmBookingDialog(ref, branchId: branchId, date: _date, booking: booking);
  }

  /// Seat / complete / no-show / cancel: a toast, then bookings and the
  /// floor refetch; a failure toasts the server's words.
  Future<void> _act(String done, Future<Object?> Function() call) async {
    final t = ref.read(tProvider);
    // Captured now: the refresh runs even if the page closes mid-request.
    final bus = ref.read(realtimeBusProvider);
    try {
      await call();
      bus.invalidate(SellInvalidate.bookings);
      if (!mounted) return;
      DashToast.success(context, done);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, sellErrorText(e, t));
    }
  }

  Future<void> _seat(BookingView b) {
    final t = ref.read(tProvider);
    return _act(
      t('bookings.seated'),
      () => ref
          .read(apiProvider)
          .bookings
          .seatBooking(id: b.id, body: const SeatBookingRequest()),
    );
  }

  Future<void> _complete(BookingView b) {
    final t = ref.read(tProvider);
    return _act(
      t('bookings.completed'),
      () => ref.read(apiProvider).bookings.completeBooking(id: b.id),
    );
  }

  Future<void> _noShow(BookingView b) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('bookings.noShowTitle', args: {'name': b.guestName}),
      description: t('bookings.noShowBody'),
      confirmLabel: t('bookings.noShow'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _act(
      t('bookings.noShowDone'),
      () => ref.read(apiProvider).bookings.noShowBooking(id: b.id),
    );
  }

  Future<void> _cancel(BookingView b) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('bookings.cancelTitle', args: {'name': b.guestName}),
      description: t('bookings.cancelBody'),
      confirmLabel: t('bookings.cancelBooking'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _act(
      t('bookings.cancelled'),
      () => ref
          .read(apiProvider)
          .bookings
          .cancelBooking(
            id: b.id,
            body: const CancelBookingRequest(
              notifyGuest: true,
              explicitNulls: {'reason'},
            ),
          ),
    );
  }

  /// Re-reads the day (declaring the export), applies the page's filter and
  /// writes `Madar-Bookings-<date>-<today>.xlsx` (SELL-BKG-033/034).
  Future<void> _export(String branchId) async {
    final t = ref.read(tProvider);
    final brand = ref.read(publicBrandProvider).value;
    final exporter = ref.read(exporterProvider);
    final filter = _filter;
    final date = _date;
    setState(() => _exporting = true);
    try {
      final day = await apiWithHeaders(
        ref.read(transportProvider),
        exportRequestHeaders,
      ).bookings.listBookings(branchId: branchId, date: date);
      if (!mounted) return;
      final toast = DashToast.loading(context, t('excel.generating'));
      final outcome = await exporter.exportToExcel(
        ExcelConfig(
          filename: 'Madar-Bookings-$date',
          logoUrl: exportLogoOf(brand),
          meta: date,
          sheets: [
            ExcelSheet<BookingView>(
              name: t('bookings.title'),
              title: t('bookings.title'),
              subtitle: bookingFilterLabel(t, filter),
              rows: filterBookings(day, filter),
              columns: bookingExportColumns(t),
            ),
          ],
        ),
      );
      toast.update(
        outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
        outcome.message(t),
      );
    } on Object catch (e) {
      if (mounted) DashToast.error(context, sellErrorText(e, t));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final branchId = ref.watch(sellBranchIdProvider);
    if (branchId == null) {
      return DashPageScaffold(
        title: t('bookings.title'),
        body: const BranchRequiredState(
          messageKey: 'bookings.pickBranch',
          icon: 'calendar-clock',
        ),
      );
    }
    ref.watch(publicBrandProvider);
    final fmt = ref.watch(formatProvider);
    final settingsQ = ref.watch(bookingSettingsProvider(branchId));
    final tablesQ = ref.watch(floorTablesProvider(branchId));
    final dayKey = (branchId: branchId, date: _date);
    final listQ = ref.watch(bookingDayProvider(dayKey));
    _followLink(listQ);
    final all = listQ.value ?? const <BookingView>[];
    final totals = DayTotals.of(all);
    final needsTable = [
      for (final b in all)
        if (b.needsTable) b,
    ];
    final today = serviceToday(ref.read(clockProvider)(), fmt.timezone);
    final width = MediaQuery.sizeOf(context).width;
    final loading = listQ.awaitingFirst;
    final settings = settingsQ.value;

    final stats = [
      DashStatCard(
        dense: true,
        label: t('bookings.statBookings'),
        value: totals.total,
        format: DashStatFormat.number,
        icon: 'calendar-days',
        loading: loading,
      ),
      DashStatCard(
        dense: true,
        label: t('bookings.statCovers'),
        value: totals.covers,
        format: DashStatFormat.number,
        icon: 'users',
        loading: loading,
      ),
      DashStatCard(
        dense: true,
        label: t('bookings.statSeated'),
        value: totals.seated,
        format: DashStatFormat.number,
        icon: 'armchair',
        loading: loading,
      ),
      DashStatCard(
        dense: true,
        label: t('bookings.statNoShow'),
        value: totals.noShow,
        format: DashStatFormat.number,
        icon: 'user-x',
        tone: totals.noShow > 0 ? DashTone.danger : DashTone.neutral,
        loading: loading,
      ),
    ];

    return DashPageScaffold(
      title: t('bookings.title'),
      subtitle: t('bookings.description'),
      actions: [
        DashExportButton(
          key: const ValueKey('bookings-export'),
          onExport: () => _export(branchId),
          loading: _exporting,
          enabled: all.isNotEmpty,
        ),
        DashButton(
          key: const ValueKey('bookings-settings'),
          label: t('bookings.settings'),
          icon: 'settings-2',
          variant: DashButtonVariant.outline,
          onPressed: () =>
              showBookingSettingsDialog(context, branchId: branchId),
          onIntent: () => ref.warm(bookingSettingsProvider(branchId)),
        ),
        DashButton(
          key: const ValueKey('bookings-new'),
          label: t('bookings.new'),
          icon: 'plus',
          onPressed: () => _openDialog(null),
          onIntent: () => _warmDialog(null),
        ),
      ],
      filters: _DayBar(
        date: _date,
        today: today,
        view: _view,
        onDate: (d) => setState(() => _date = d),
        onDateIntent: (d) =>
            ref.warm(bookingDayProvider((branchId: branchId, date: d))),
        onView: (v) => setState(() => _view = v),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          if (settings != null && !settings.enabled)
            BookingNotice(
              key: const ValueKey('bookings-online-off'),
              icon: 'calendar-clock',
              title: t('bookings.onlineOffTitle'),
              body: Text(
                t('bookings.onlineOffBody'),
                style: DashType.body.copyWith(
                  color: context.madarColors.textSecondary,
                ),
              ),
            ),
          BookingGrid(
            columns: width >= DashBreakpoints.lg
                ? 4
                : width >= DashBreakpoints.sm
                ? 2
                : 1,
            spacing: Space.md,
            children: stats,
          ),
          if (needsTable.isNotEmpty)
            BookingNotice(
              key: const ValueKey('bookings-needs-table'),
              icon: 'alert-triangle',
              tone: DashTone.warning,
              title: t(
                'bookings.needsTableTitle',
                args: {'count': needsTable.length},
              ),
              body: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final b in needsTable)
                    DashButton(
                      key: ValueKey('needs-table-${b.id}'),
                      label:
                          '${ltr(fmt.fmtTime(b.startsAt))} · ${b.guestName} · '
                          '${b.partySize}',
                      variant: DashButtonVariant.outline,
                      size: DashButtonSize.compact,
                      onPressed: () => _openDialog(b),
                      onIntent: () => _warmDialog(b),
                    ),
                ],
              ),
            ),
          if (_view == 'list')
            _BookingsList(
              all: all,
              filter: _filter,
              now: _now,
              listQ: listQ,
              onFilter: (f) => setState(() => _filter = f),
              onRetry: () => ref.invalidate(bookingDayProvider(dayKey)),
              onNew: () => _openDialog(null),
              onEdit: _openDialog,
              onEditIntent: _warmDialog,
              onSeat: _seat,
              onComplete: _complete,
              onNoShow: _noShow,
              onCancel: _cancel,
            )
          else
            BookingsTimeline(
              date: _date,
              bookings: [
                for (final b in all)
                  if (isActiveBooking(b.status)) b,
              ],
              tablesQ: tablesQ,
              listQ: listQ,
              window: dayWindow(settings, _date),
              now: _now,
              onOpen: _openDialog,
              onOpenIntent: _warmDialog,
              onRetryTables: () =>
                  ref.invalidate(floorTablesProvider(branchId)),
              onRetryList: () => ref.invalidate(bookingDayProvider(dayKey)),
            ),
        ],
      ),
    );
  }
}

/// Previous day · the date · next day · Today, and the List/Timeline switch
/// (the header's `below`, SELL-BKG-005/006).
class _DayBar extends ConsumerWidget {
  const _DayBar({
    required this.date,
    required this.today,
    required this.view,
    required this.onDate,
    required this.onDateIntent,
    required this.onView,
  });

  final String date;
  final String today;
  final String view;
  final ValueChanged<String> onDate;

  /// About to move to that day: warm its list.
  final ValueChanged<String> onDateIntent;
  final ValueChanged<String> onView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            DashIconButton(
              key: const ValueKey('bookings-prev-day'),
              icon: DashIcon.backward(context),
              semanticLabel: t('common.previous'),
              variant: DashButtonVariant.outline,
              onPressed: () => onDate(addBookingDays(date, -1)),
              onIntent: () => onDateIntent(addBookingDays(date, -1)),
            ),
            SizedBox(
              width: BookingMetrics.datePicker,
              child: DashDateField(
                key: const ValueKey('bookings-date'),
                value: dashParseYmd(date),
                today: dashParseYmd(today),
                semanticLabel: t('bookings.date'),
                onChanged: (d) => onDate(dashYmd(d)),
              ),
            ),
            DashIconButton(
              key: const ValueKey('bookings-next-day'),
              icon: DashIcon.forward(context),
              semanticLabel: t('common.next'),
              variant: DashButtonVariant.outline,
              onPressed: () => onDate(addBookingDays(date, 1)),
              onIntent: () => onDateIntent(addBookingDays(date, 1)),
            ),
            if (date != today)
              DashButton(
                key: const ValueKey('bookings-today'),
                label: t('bookings.today'),
                variant: DashButtonVariant.ghost,
                size: DashButtonSize.compact,
                onPressed: () => onDate(today),
                onIntent: () => onDateIntent(today),
              ),
          ],
        ),
        DashSegmentedControl<String>(
          key: const ValueKey('bookings-view'),
          value: view,
          onChanged: onView,
          options: [
            DashOption(value: 'list', label: t('bookings.viewList')),
            DashOption(value: 'timeline', label: t('bookings.viewTimeline')),
          ],
        ),
      ],
    );
  }
}

/// The status filter and the day's table (SELL-BKG-010 … 025).
class _BookingsList extends ConsumerWidget {
  const _BookingsList({
    required this.all,
    required this.filter,
    required this.now,
    required this.listQ,
    required this.onFilter,
    required this.onRetry,
    required this.onNew,
    required this.onEdit,
    required this.onEditIntent,
    required this.onSeat,
    required this.onComplete,
    required this.onNoShow,
    required this.onCancel,
  });

  final List<BookingView> all;
  final String filter;
  final DateTime now;
  final AsyncValue<List<BookingView>> listQ;
  final ValueChanged<String> onFilter;
  final VoidCallback onRetry;
  final VoidCallback onNew;
  final ValueChanged<BookingView> onEdit;

  /// About to open the dialog on that booking (null: a new one).
  final ValueChanged<BookingView?> onEditIntent;
  final ValueChanged<BookingView> onSeat;
  final ValueChanged<BookingView> onComplete;
  final ValueChanged<BookingView> onNoShow;
  final ValueChanged<BookingView> onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final link = customerSheetControl(context, ref);
    final rows = filterBookings(all, filter);
    // The web's `error={listQ.error}`: set once the retries are spent.
    final error = listQ.hasError && !listQ.retrying ? listQ.error : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DashSegmentedControl<String>(
            key: const ValueKey('bookings-filter'),
            value: filter,
            onChanged: onFilter,
            options: [
              for (final f in bookingFilters)
                DashOption(value: f, label: bookingFilterLabel(t, f)),
            ],
          ),
        ),
        DashDataTable<BookingView>(
          key: const ValueKey('bookings-table'),
          rows: rows,
          rowKey: (b) => b.id,
          loading: listQ.awaitingFirst,
          errorMessage: error == null ? null : sellErrorText(error, t),
          onRetry: onRetry,
          retrying: listQ.isLoading,
          onRowTap: (b) {
            if (isActiveBooking(b.status)) onEdit(b);
          },
          onRowIntent: (b) {
            if (isActiveBooking(b.status)) onEditIntent(b);
          },
          rowSemanticLabel: (b) => b.guestName,
          pageSize: 50,
          hideViewOptions: true,
          empty: all.isEmpty
              ? DashEmptyState(
                  icon: 'calendar-clock',
                  title: t('bookings.emptyDay'),
                  description: t('bookings.emptyHint'),
                  action: DashButton(
                    label: t('bookings.new'),
                    icon: 'plus',
                    onPressed: onNew,
                    onIntent: () => onEditIntent(null),
                  ),
                )
              : DashEmptyState(
                  icon: 'calendar-clock',
                  title: t('bookings.emptyFilter'),
                ),
          rowActions: (context, b) => _RowMenu(
            booking: b,
            onEdit: onEdit,
            onEditIntent: onEditIntent,
            onSeat: onSeat,
            onComplete: onComplete,
            onNoShow: onNoShow,
            onCancel: onCancel,
          ),
          columns: [
            DashColumn<BookingView>(
              id: 'time',
              label: t('bookings.time'),
              numeric: true,
              align: DashAlign.start,
              flex: 1,
              minWidth: 120,
              text: (b) => fmt.fmtTime(b.startsAt),
              cell: (context, b) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fmt.fmtTime(b.startsAt),
                    style: DashType.monoMedium.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    t('bookings.until', args: {'time': fmt.fmtTime(b.endsAt)}),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            DashColumn<BookingView>(
              id: 'guest',
              label: t('bookings.guest'),
              phone: DashPhoneRole.title,
              flex: 3,
              minWidth: 240,
              text: (b) => b.guestName,
              cell: (context, b) =>
                  BookingGuestCell(booking: b, now: now, link: link),
            ),
            DashColumn<BookingView>(
              id: 'party',
              label: t('bookings.party'),
              numeric: true,
              flex: 1,
              minWidth: 80,
              text: (b) => '${b.partySize}',
            ),
            DashColumn<BookingView>(
              id: 'tables',
              label: t('bookings.tables'),
              flex: 2,
              minWidth: 120,
              text: (b) => bookingTablesText(t, b),
              cell: (context, b) => b.needsTable
                  ? DashStatusPill(
                      label: t('bookings.needsTable'),
                      tone: DashTone.warning,
                      small: true,
                    )
                  : MadarClippedText(
                      bookingTablesText(t, b),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashType.body.copyWith(color: c.textPrimary),
                    ),
            ),
            DashColumn<BookingView>(
              id: 'status',
              label: t('common.status'),
              flex: 1,
              minWidth: 120,
              text: (b) => bookingStatusLabel(t, b.status),
              cell: (context, b) => BookingStatusPill(status: b.status),
            ),
          ],
        ),
      ],
    );
  }
}

/// The row's "…" menu (SELL-BKG-016).
class _RowMenu extends ConsumerWidget {
  const _RowMenu({
    required this.booking,
    required this.onEdit,
    required this.onEditIntent,
    required this.onSeat,
    required this.onComplete,
    required this.onNoShow,
    required this.onCancel,
  });

  final BookingView booking;
  final ValueChanged<BookingView> onEdit;
  final ValueChanged<BookingView?> onEditIntent;
  final ValueChanged<BookingView> onSeat;
  final ValueChanged<BookingView> onComplete;
  final ValueChanged<BookingView> onNoShow;
  final ValueChanged<BookingView> onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final b = booking;
    final active = isActiveBooking(b.status);
    return DashMenu(
      items: [
        if (active)
          DashMenuItem(
            label: t('common.edit'),
            icon: 'pencil',
            onSelected: () => onEdit(b),
            onIntent: () => onEditIntent(b),
          ),
        if (b.status == 'confirmed')
          DashMenuItem(
            label: t('bookings.seat'),
            icon: 'armchair',
            onSelected: () => onSeat(b),
          ),
        if (b.status == 'seated')
          DashMenuItem(
            label: t('bookings.complete'),
            icon: 'check',
            onSelected: () => onComplete(b),
          ),
        if (b.status == 'confirmed')
          DashMenuItem(
            label: t('bookings.noShow'),
            icon: 'user-x',
            onSelected: () => onNoShow(b),
          ),
        if (active) ...[
          const DashMenuItem.divider(),
          DashMenuItem(
            label: t('bookings.cancelBooking'),
            icon: 'x-circle',
            destructive: true,
            onSelected: () => onCancel(b),
          ),
        ],
        if (!active)
          DashMenuItem(label: bookingStatusLabel(t, b.status), enabled: false),
      ],
      builder: (context, c) => DashIconButton(
        key: ValueKey('booking-actions-${b.id}'),
        icon: 'more-horizontal',
        semanticLabel: t('common.actions'),
        onPressed: c.toggle,
      ),
    );
  }
}

/// The Guest cell (SELL-BKG-012): the name as a customer link, Online, Late
/// or Due, and the phone with the notes under it.
class BookingGuestCell extends ConsumerWidget {
  const BookingGuestCell({
    required this.booking,
    required this.now,
    required this.link,
    super.key,
  });

  final BookingView booking;
  final DateTime now;
  final CustomerLinkControl link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final b = booking;
    final muted = DashType.small.copyWith(color: c.textSecondary);
    final notes = b.notes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CustomerLink(
              name: b.guestName,
              customerId: b.customerId,
              control: link,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            if (b.source == 'public')
              DashBadge(t('bookings.online'), outline: true),
            if (isLateBooking(b, now))
              DashStatusPill(
                label: t('bookings.late'),
                tone: DashTone.warning,
                small: true,
              )
            else if (isHeldBooking(b, now))
              DashStatusPill(
                label: t('bookings.dueNow'),
                tone: DashTone.warning,
                icon: 'calendar-clock',
                small: true,
              ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            DashIcon('phone', size: IconSize.xs - 2, color: c.textSecondary),
            Text(
              formatPhoneDisplay(b.guestPhone),
              textDirection: TextDirection.ltr,
              style: DashType.mono.copyWith(
                fontSize: DashType.small.fontSize,
                color: c.textSecondary,
              ),
            ),
            if (notes != null && notes.isNotEmpty)
              Flexible(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: Space.xs),
                  child: Tooltip(
                    message: notes,
                    child: MadarClippedText(
                      '· $notes',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
