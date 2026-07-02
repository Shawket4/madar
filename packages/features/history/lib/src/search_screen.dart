/// All-orders search — a history lookup ACROSS shifts (date range +
/// status + teller), paginated. Closes the "operators can't look up a
/// past-shift order" gap. Full-screen over the order screen; teller-only.
/// A pixel-and-behavior port of the Kotlin OrderSearchScreen.kt over the
/// shared Rust core; a result row opens the shared [OrderDetailsSheet].
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_history/src/order_details_sheet.dart';
import 'package:feature_history/src/widgets.dart';
import 'package:flutter/material.dart'
    show CircularProgressIndicator, Scaffold, Theme;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Result-row money size (natives: Type.money(17.sp)).
const double _rowMoneySize = 17;

/// RFC3339 timestamp [days] ago (UTC) — the natives' `isoDaysAgo`.
String _isoDaysAgo(int days) =>
    DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();

/// Cross-shift order search (online) with filters + load-more pagination.
class OrderSearchScreen extends StatefulWidget {
  /// Creates the search screen.
  const OrderSearchScreen({
    required this.core,
    required this.onStateChanged,
    super.key,
  });

  /// The core handle every bridge call goes through.
  final MadarCore core;

  /// Screen-contract shell callback (searching moves no app state, so
  /// this is only threaded through to the details sheet).
  final void Function() onStateChanged;

  @override
  State<OrderSearchScreen> createState() => _OrderSearchScreenState();
}

class _OrderSearchScreenState extends State<OrderSearchScreen> {
  MadarBridge get _bridge => widget.core.bridge;

  String? _status; // null = all
  final TextEditingController _teller = TextEditingController();
  int _days = 7; // 0 = all time

  List<OrderSummaryView> _results = const [];
  int _total = 0;
  bool _hasMore = false;
  bool _searching = false;
  int _page = 1;

  /// Request-sequence guard: bumped per `_run`; stale completions bail so a
  /// slow response can't clobber a newer query or double-advance `_page`.
  int _querySeq = 0;

  ToastData? _toast;
  int _toastSeq = 0;

  String _t(String key) => _bridge.tr(key: key);

  String get _currency => _bridge.currentSession()?.currencyCode ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_run(reset: true));
  }

  @override
  void dispose() {
    _teller.dispose();
    super.dispose();
  }

  void _showToast(String text, {required ChipTone tone, String? icon}) {
    _toastSeq += 1;
    setState(() {
      _toast = ToastData(id: _toastSeq, text: text, tone: tone, icon: icon);
    });
  }

  /// Run / page the all-orders search. [reset] starts a fresh query at
  /// page 1; otherwise it appends the next page (load-more).
  Future<void> _run({required bool reset}) async {
    final seq = ++_querySeq;
    setState(() {
      if (reset) {
        _page = 1;
        _results = const [];
      }
      _searching = true;
    });
    try {
      final teller = _teller.text.trim();
      final pg = await _bridge.searchOrders(
        status: _status,
        tellerName: teller.isEmpty ? null : teller,
        from: _days > 0 ? _isoDaysAgo(_days) : null,
        page: _page,
      );
      if (seq != _querySeq || !mounted) return;
      setState(() {
        _results = reset ? pg.orders : [..._results, ...pg.orders];
        _total = pg.total;
        _hasMore = pg.hasMore;
        _page += 1;
        _searching = false;
      });
    } on MadarError catch (e) {
      if (seq != _querySeq || !mounted) return;
      setState(() => _searching = false);
      _showToast(
        _bridge.humanMessage(e),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
    }
  }

  /// Copy the current result page as CSV — spreadsheet-friendly export.
  Future<void> _export() async {
    await Clipboard.setData(
      ClipboardData(text: _ordersToCsv(_results, _currency)),
    );
    if (!mounted) return;
    _showToast(
      _t('search.exported'),
      tone: ChipTone.success,
      icon: 'checkmark.circle.fill',
    );
  }

  /// A result row's full line breakdown — the shared details sheet.
  Future<void> _openDetails(OrderSummaryView o) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      builder: (_) => OrderDetailsSheet(
        core: widget.core,
        onStateChanged: widget.onStateChanged,
        order: o,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              // Header — back + title, trailing result count + CSV export.
              HistoryHeaderBar(
                title: _t('search.title'),
                onBack: () => unawaited(Navigator.of(context).maybePop()),
                trailing: [
                  if (_total > 0)
                    Text(
                      '$_total',
                      style: MadarType.title.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  if (_results.isNotEmpty)
                    Semantics(
                      button: true,
                      child: TactileScale(
                        onTap: () => unawaited(_export()),
                        child: Container(
                          width: Metrics.closeButton,
                          height: Metrics.closeButton,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.accentBg,
                            borderRadius: BorderRadius.circular(Radii.sm),
                          ),
                          child: MadarIcon(
                            'square.and.arrow.up',
                            tint: colors.accent,
                            size: IconSize.lg,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              _buildFilters(colors),
              const Hairline(),
              Expanded(child: _buildResults(colors)),
            ],
          ),
          ToastHost(
            _toast,
            onDismiss: (id) {
              if (_toast?.id == id) setState(() => _toast = null);
            },
          ),
        ],
      ),
    );
  }

  // ── Filters — date range, status, and a teller lookup ─────────────────────
  Widget _buildFilters(MadarColors colors) {
    Widget dateChip(String label, int days) {
      return SelectChip(
        label: label,
        selected: _days == days,
        onTap: () {
          setState(() => _days = days);
          unawaited(_run(reset: true));
        },
      );
    }

    Widget statusChip(String label, String? status, {ChipTone? tone}) {
      return SelectChip(
        label: label,
        selected: _status == status,
        tone: tone ?? ChipTone.accent,
        onTap: () {
          setState(() => _status = status);
          unawaited(_run(reset: true));
        },
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
                dateChip(_t('search.date_24h'), 1),
                dateChip(_t('search.date_7d'), 7),
                dateChip(_t('search.date_30d'), 30),
                dateChip(_t('order.all'), 0),
              ],
            ),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                statusChip(_t('order.all'), null),
                statusChip(
                  _t('history.completed'),
                  'completed',
                  tone: ChipTone.success,
                ),
                statusChip(
                  _t('history.voided'),
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
                    controller: _teller,
                    placeholder: _t('search.teller_hint'),
                    icon: 'person',
                  ),
                ),
                HistoryButton(
                  label: _t('search.title'),
                  icon: 'magnifyingglass',
                  loading: _searching,
                  expand: false,
                  onTap: () => unawaited(_run(reset: true)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Results ────────────────────────────────────────────────────────────────
  Widget _buildResults(MadarColors colors) {
    if (_searching && _results.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_results.isEmpty) {
      return EmptyState(icon: 'magnifyingglass', title: _t('history.no_match'));
    }
    return ListView.separated(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      itemCount: _results.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, index) {
        if (index >= _results.length) {
          return HistoryButton(
            label: _t('search.load_more'),
            variant: HistoryButtonVariant.outline,
            icon: 'arrow.down.circle',
            loading: _searching,
            onTap: () => unawaited(_run(reset: false)),
          );
        }
        final o = _results[index];
        return _SearchResultRow(
          order: o,
          timestamp: _bridge.formatTime(
            rfc3339: o.createdAt,
            style: TimeStyle.dateTime,
          ),
          currency: _currency,
          statusLabel: _statusLabel(o.status),
          onTap: () => unawaited(_openDetails(o)),
        );
      },
    );
  }

  /// Status → the localized history chip label (falls back to the raw
  /// status for anything unmapped, like the natives).
  String _statusLabel(String status) => switch (status) {
    'completed' => _t('history.completed'),
    'voided' => _t('history.voided'),
    'failed' => _t('history.failed'),
    'queued' => _t('history.queued'),
    _ => status,
  };
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
