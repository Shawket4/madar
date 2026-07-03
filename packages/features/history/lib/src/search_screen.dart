/// All-orders search — a history lookup ACROSS shifts (date range +
/// status + teller), paginated. Closes the "operators can't look up a
/// past-shift order" gap. Full-screen over the order screen; teller-only.
/// A pixel-and-behavior port of the Kotlin OrderSearchScreen.kt over the
/// shared Rust core; state lives in [searchProvider] (the teller query
/// stays widget-local in its text field); a result row opens the shared
/// [OrderDetailsSheet].
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/src/order_details_sheet.dart';
import 'package:feature_history/src/search_provider.dart';
import 'package:feature_history/src/widgets.dart';
import 'package:flutter/material.dart'
    show CircularProgressIndicator, Scaffold, Theme;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Result-row money size (natives: Type.money(17.sp)).
const double _rowMoneySize = 17;

/// Cross-shift order search (online) with filters + load-more pagination.
class OrderSearchScreen extends ConsumerStatefulWidget {
  /// Creates the search screen.
  const OrderSearchScreen({super.key});

  @override
  ConsumerState<OrderSearchScreen> createState() => _OrderSearchScreenState();
}

class _OrderSearchScreenState extends ConsumerState<OrderSearchScreen> {
  final TextEditingController _teller = TextEditingController();

  @override
  void dispose() {
    _teller.dispose();
    super.dispose();
  }

  /// Copy the current result page as CSV — spreadsheet-friendly export.
  Future<void> _export() async {
    final results = ref.read(searchProvider).results;
    final currency = ref.read(shellProvider).session?.currencyCode ?? '';
    await Clipboard.setData(
      ClipboardData(text: _ordersToCsv(results, currency)),
    );
    if (!mounted) return;
    ref
        .read(searchProvider.notifier)
        .showToast(
          ref.read(bridgeProvider).tr(key: 'search.exported'),
          tone: ChipTone.success,
          icon: 'checkmark.circle.fill',
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final total = ref.watch(searchProvider.select((s) => s.total));
    final hasResults = ref.watch(
      searchProvider.select((s) => s.results.isNotEmpty),
    );
    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              // Header — back + title, trailing result count + CSV export.
              MadarHeader(
                title: bridge.tr(key: 'search.title'),
                onBack: () => Navigator.maybePop(context),
                actions: [
                  if (total > 0)
                    Text(
                      '$total',
                      style: MadarType.title.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  if (hasResults)
                    MadarHeaderAction(
                      icon: 'square.and.arrow.up',
                      tint: colors.accent,
                      onTap: () => unawaited(_export()),
                    ),
                ],
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      _SearchFilters(teller: _teller),
                      const Hairline(),
                      Expanded(child: _SearchResults(teller: _teller)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const _SearchToastHost(),
        ],
      ),
    );
  }
}

/// The screen toast, driven by [OrderSearchState.toast].
class _SearchToastHost extends ConsumerWidget {
  const _SearchToastHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(searchProvider.select((s) => s.toast));
    return ToastHost(
      toast,
      onDismiss: (id) => ref.read(searchProvider.notifier).dismissToast(id),
    );
  }
}

// ── Filters — date range, status, and a teller lookup ────────────────────────
class _SearchFilters extends ConsumerWidget {
  const _SearchFilters({required this.teller});

  final TextEditingController teller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final notifier = ref.read(searchProvider.notifier);
    final days = ref.watch(searchProvider.select((s) => s.days));
    final status = ref.watch(searchProvider.select((s) => s.status));
    final searching = ref.watch(searchProvider.select((s) => s.searching));
    String t(String key) => bridge.tr(key: key);

    Widget dateChip(String label, int value) {
      return SelectChip(
        label: label,
        selected: days == value,
        onTap: () => notifier.setDays(value, teller: teller.text),
      );
    }

    Widget statusChip(String label, String? value, {ChipTone? tone}) {
      return SelectChip(
        label: label,
        selected: status == value,
        tone: tone ?? ChipTone.accent,
        onTap: () => notifier.setStatus(value, teller: teller.text),
      );
    }

    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                dateChip(t('search.date_24h'), 1),
                dateChip(t('search.date_7d'), 7),
                dateChip(t('search.date_30d'), 30),
                dateChip(t('order.all'), 0),
              ],
            ),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                statusChip(t('order.all'), null),
                statusChip(
                  t('history.completed'),
                  'completed',
                  tone: ChipTone.success,
                ),
                statusChip(
                  t('history.voided'),
                  'voided',
                  tone: ChipTone.danger,
                ),
              ],
            ),
            Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: HistoryTextField(
                    controller: teller,
                    placeholder: t('search.teller_hint'),
                    icon: 'person',
                  ),
                ),
                HistoryButton(
                  label: t('search.title'),
                  icon: 'magnifyingglass',
                  loading: searching,
                  expand: false,
                  onTap: () => unawaited(
                    notifier.run(reset: true, teller: teller.text),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Results ──────────────────────────────────────────────────────────────────
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.teller});

  final TextEditingController teller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final results = ref.watch(searchProvider.select((s) => s.results));
    final hasMore = ref.watch(searchProvider.select((s) => s.hasMore));
    final searching = ref.watch(searchProvider.select((s) => s.searching));
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    String t(String key) => bridge.tr(key: key);

    /// Status → the localized history chip label (falls back to the raw
    /// status for anything unmapped, like the natives).
    String statusLabel(String status) => switch (status) {
      'completed' => t('history.completed'),
      'voided' => t('history.voided'),
      'failed' => t('history.failed'),
      'queued' => t('history.queued'),
      _ => status,
    };

    if (searching && results.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (results.isEmpty) {
      return EmptyState(icon: 'magnifyingglass', title: t('history.no_match'));
    }
    return ListView.separated(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      itemCount: results.length + (hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, index) {
        if (index >= results.length) {
          return HistoryButton(
            label: t('search.load_more'),
            variant: HistoryButtonVariant.outline,
            icon: 'arrow.down.circle',
            loading: searching,
            onTap: () => unawaited(
              ref
                  .read(searchProvider.notifier)
                  .run(reset: false, teller: teller.text),
            ),
          );
        }
        final o = results[index];
        return _SearchResultRow(
          order: o,
          timestamp: bridge.formatTime(
            rfc3339: o.createdAt,
            style: TimeStyle.dateTime,
          ),
          currency: currency,
          statusLabel: statusLabel(o.status),
          onTap: () => unawaited(
            // A result row's full line breakdown — the shared details sheet.
            showMadarSheet<void>(
              context,
              size: SheetSize.hug,
              builder: (_) => OrderDetailsSheet(order: o),
            ),
          ),
        );
      },
    );
  }
}

/// Spreadsheet-friendly export of the current result page. RFC-4180
/// quoting so a payment label or status containing a comma can't shift
/// columns.
String _ordersToCsv(List<OrderSummaryView> orders, String currency) {
  String esc(String s) => '"${s.replaceAll('"', '""')}"';
  final sb = StringBuffer('Order,Date,Total,Payment,Status\n');
  for (final o in orders) {
    sb
      ..write('#${o.orderNumber ?? ''},')
      ..write(esc(o.createdAt))
      ..write(',')
      ..write(esc(Money.format(o.totalMinor, currency: currency)))
      ..write(',')
      ..write(esc(o.paymentLabel))
      ..write(',')
      ..write(esc(o.status))
      ..write('\n');
  }
  return sb.toString();
}

/// One order result card: number + timestamp on the leading edge,
/// bold-teal money + a tone chip + payment label on the trailing edge.
class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.order,
    required this.timestamp,
    required this.currency,
    required this.statusLabel,
    required this.onTap,
  });

  final OrderSummaryView order;
  final String timestamp;
  final String currency;
  final String statusLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final o = order;
    // A voided / failed order is dead money — mute + strike its total so
    // the hero teal reads only on live orders (mirrors the history screen).
    final dead = o.status == 'voided' || o.status == 'failed';
    return Semantics(
      button: true,
      child: TactileScale(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: colors.borderLight),
            boxShadow: MadarElevation.card.shadows(
              colors,
              dark: Theme.of(context).brightness == Brightness.dark,
            ),
          ),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.xs,
                  children: [
                    Text(
                      '#${o.orderNumber ?? '—'}',
                      style: MadarType.h3.copyWith(color: colors.textPrimary),
                    ),
                    Text(
                      timestamp,
                      style: MadarType.bodySm.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: Space.sm,
                children: [
                  // Money is the hero — bold teal; struck + muted once dead.
                  Text(
                    Money.format(o.totalMinor, currency: currency),
                    textDirection: TextDirection.ltr,
                    style: MadarType.money.copyWith(
                      fontSize: _rowMoneySize,
                      color: dead ? colors.textMuted : colors.accent,
                      decoration: dead ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Row(
                    spacing: Space.sm,
                    children: [
                      Text(
                        o.paymentLabel,
                        style: MadarType.labelSm.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      StatusChip(
                        label: statusLabel,
                        tone: statusToneOf(o.status),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
