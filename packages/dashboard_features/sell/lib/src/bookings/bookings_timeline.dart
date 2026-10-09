/// The day by table (the web's `Timeline`, SELL-BKG-026 … 029, 075, 076):
/// one row per active table plus a "Needs a table" row, hour ticks across
/// the booking window, a block per active booking. It reads the start side
/// first, so in Arabic the hours run right to left (unlike the floor plan,
/// the web mirrors it).
library;

import 'package:dashboard_api/dashboard_api.dart' show BookingView, FloorTable;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'booking_errors.dart';
import 'bookings_parts.dart';
import 'bookings_providers.dart';
import 'bookings_util.dart';

class BookingsTimeline extends ConsumerWidget {
  const BookingsTimeline({
    required this.date,
    required this.bookings,
    required this.tablesQ,
    required this.listQ,
    required this.window,
    required this.now,
    required this.onOpen,
    required this.onRetryTables,
    required this.onRetryList,
    super.key,
  });

  final String date;

  /// The day's active bookings.
  final List<BookingView> bookings;
  final AsyncValue<List<FloorTable>> tablesQ;
  final AsyncValue<List<BookingView>> listQ;
  final DayWindow window;
  final DateTime now;
  final ValueChanged<BookingView> onOpen;
  final VoidCallback onRetryTables;
  final VoidCallback onRetryList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    // Divergence SELL-BKG-076: a loading or failed read is never drawn as
    // "no tables" or as an empty day.
    if (tablesQ.awaitingFirst || listQ.awaitingFirst) {
      return const DashSkeleton(height: BookingMetrics.timelineRow * 4);
    }
    // A failed refresh keeps the blocks drawn, as the web keeps its data.
    final failed = tablesQ.failedFirst
        ? tablesQ
        : (listQ.failedFirst ? listQ : null);
    if (failed != null) {
      return DashErrorState(
        message: bookingErrorText(failed.error, t),
        retryLabel: t('common.retry'),
        retrying: failed.isLoading,
        onRetry: identical(failed, tablesQ) ? onRetryTables : onRetryList,
      );
    }
    final tables = activeTablesByLabel(tablesQ.value);
    if (tables.isEmpty) {
      return DashEmptyState(
        icon: 'armchair',
        title: t('bookings.noTables'),
        description: t('bookings.noTablesHint'),
      );
    }
    final unassigned = [
      for (final b in bookings)
        if (b.tableIds.isEmpty) b,
    ];
    final rows = [
      for (final tb in tables)
        (
          key: tb.id,
          label: '${tb.label} · ${tb.seats}',
          items: [
            for (final b in bookings)
              if (b.tableIds.contains(tb.id)) b,
          ],
        ),
      if (unassigned.isNotEmpty)
        (key: '__none', label: t('bookings.needsTable'), items: unassigned),
    ];
    final ticks = hourTicks(window, fmt.fmtHour);
    final hairline = BorderSide(color: c.hairline);
    final muted = DashType.small.copyWith(color: c.textSecondary);

    Widget lane({required double height, required List<_At> children}) =>
        Expanded(
          // The end inset leaves the last hour's centred label room.
          child: Container(
            height: height,
            padding: const EdgeInsetsDirectional.only(
              end: BookingMetrics.timelineHour / 2,
            ),
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final a in children)
                    PositionedDirectional(
                      start: a.left / 100 * box.maxWidth,
                      top: a.top,
                      bottom: a.bottom,
                      width: a.width == null
                          ? null
                          : a.width! / 100 * box.maxWidth,
                      child: a.child,
                    ),
                ],
              ),
            ),
          ),
        );

    Widget labelCell(String text, {TextStyle? style, double? height}) =>
        Container(
          width: BookingMetrics.timelineLabel,
          height: height,
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          decoration: BoxDecoration(border: BorderDirectional(end: hairline)),
          child: MadarClippedText(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        );

    final rtl = Directionality.of(context) == TextDirection.rtl;
    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.4),
            border: Border(bottom: hairline),
          ),
          child: Row(
            children: [
              labelCell(
                t('bookings.table'),
                style: muted,
                height: BookingMetrics.timelineHeader,
              ),
              lane(
                height: BookingMetrics.timelineHeader,
                children: [
                  for (final tk in ticks)
                    (
                      left: tk.left,
                      width: null,
                      top: Space.xs + DashMetrics.hair,
                      bottom: null,
                      child: FractionalTranslation(
                        translation: Offset(rtl ? 0.5 : -0.5, 0),
                        child: Text(
                          tk.label,
                          textDirection: TextDirection.ltr,
                          style: DashType.mono.copyWith(
                            fontSize: DashType.small.fontSize,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        for (final (i, row) in rows.indexed)
          Container(
            key: ValueKey('timeline-row-${row.key}'),
            decoration: BoxDecoration(
              border: i == rows.length - 1 ? null : Border(bottom: hairline),
            ),
            child: Row(
              children: [
                labelCell(
                  row.label,
                  height: BookingMetrics.timelineRow,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                lane(
                  height: BookingMetrics.timelineRow,
                  children: [
                    for (final tk in ticks)
                      (
                        left: tk.left,
                        width: null,
                        top: 0,
                        bottom: 0,
                        child: ExcludeSemantics(
                          child: Container(
                            width: 1,
                            color: c.hairline.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    for (final b in row.items)
                      () {
                        final span = timelineSpan(
                          b.startsAt,
                          b.endsAt,
                          date,
                          window,
                          fmt.timezone,
                        );
                        return (
                          left: span.left,
                          width: span.width,
                          top: BookingMetrics.timelineBlockTop,
                          bottom: null,
                          child: _Block(
                            booking: b,
                            held: isHeldBooking(b, now),
                            tooltip:
                                '${b.guestName} · ${b.partySize} · '
                                '${fmt.fmtTime(b.startsAt)}–'
                                '${fmt.fmtTime(b.endsAt)}',
                            onTap: () => onOpen(b),
                          ),
                        );
                      }(),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
    return DashCard(
      key: const ValueKey('bookings-timeline'),
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, box) {
          // `min-w-[720px]`, and room for every hour's label.
          final w = [
            box.maxWidth,
            BookingMetrics.timelineMinWidth,
            BookingMetrics.timelineLabel +
                ticks.length * BookingMetrics.timelineHour,
          ].reduce((a, b) => a > b ? a : b);
          return ClipRRect(
            borderRadius: BorderRadius.circular(Radii.card),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: w, child: grid),
            ),
          );
        },
      ),
    );
  }
}

/// A child placed by percentages of its lane, from the start side.
typedef _At = ({
  double left,
  double? width,
  double? top,
  double? bottom,
  Widget child,
});

/// One booking on the timeline: seated (Armchair), held (CalendarClock,
/// warning) or waiting (neutral); "Guest · party"; the times on hover.
class _Block extends StatelessWidget {
  const _Block({
    required this.booking,
    required this.held,
    required this.tooltip,
    required this.onTap,
  });

  final BookingView booking;
  final bool held;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final seated = booking.status == 'seated';
    final (Color bg, Color border, Color fg, String? icon) = seated
        ? (
            c.surfaceAlt,
            c.textPrimary.withValues(alpha: 0.3),
            c.textPrimary,
            'armchair',
          )
        : held
        ? (
            DashTone.warning.wash(c),
            c.warning.withValues(alpha: 0.6),
            DashTone.warning.foreground(c),
            'calendar-clock',
          )
        : (c.accentBg, c.hairline, c.textPrimary, null);
    final label = '${booking.guestName} · ${booking.partySize}';
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: DashPressable(
        key: ValueKey('timeline-block-${booking.id}'),
        onTap: onTap,
        semanticLabel: tooltip,
        excludeChildSemantics: true,
        pressScale: false,
        builder: (context, s) => Container(
          height: BookingMetrics.timelineBlock,
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          alignment: AlignmentDirectional.centerStart,
          decoration: BoxDecoration(
            color: s.highlighted ? Color.lerp(bg, c.textPrimary, 0.05) : bg,
            borderRadius: BorderRadius.circular(Radii.xs - 2),
            border: Border.all(color: border),
          ),
          child: Row(
            spacing: Space.xs,
            children: [
              if (icon != null)
                DashIcon(icon, size: IconSize.xs - 2, color: fg),
              Flexible(
                child: MadarClippedText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.smallMedium.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
