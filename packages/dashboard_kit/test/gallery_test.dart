// The kit's gallery: every widget and state, at phone / tablet / desktop,
// in English light and Arabic dark. With FDASH_SHOTS set it writes PNGs to
// <FDASH_SHOTS>/kit/<board>--<size>-<lang>-<theme>.png (long boards in
// numbered parts); without, every board still lays out and fails on any
// exception.

import 'dart:typed_data';

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gallery_fixtures.dart';

final _today = DateTime(2026, 10, 8);

// ── Boards ───────────────────────────────────────────────────────────────

Widget _pageBoard(L l) => Builder(
  builder: (context) {
    final f = context.dashFormats;
    return DashPageScaffold(
      title: l.orders,
      subtitle: l.ordersSub,
      actions: [
        DashExportButton(onExport: () {}, onExportCsv: () {}),
        DashButton(label: l.add, icon: 'plus', onPressed: () {}),
      ],
      tabs: DashPageTabs<int>(
        value: 0,
        onChanged: (_) {},
        tabs: [
          DashTab(value: 0, label: l.all, count: 128),
          DashTab(value: 1, label: l.today, count: 12),
          DashTab(value: 2, label: l.week),
          DashTab(value: 3, label: l.history),
        ],
      ),
      filters: DashFilterBar(
        searchValue: '',
        onSearchChanged: (_) {},
        searchPlaceholder: l.searchOrders,
        onClear: () {},
        filters: [
          DashFilterSelect<int>(
            label: l.status,
            allLabel: l.allStatuses,
            value: 0,
            onChanged: (_) {},
            options: [
              for (var s = 0; s < 5; s++)
                DashOption(value: s, label: statusOf(l, s).$1),
            ],
          ),
          DashFilterSelect<String>(
            label: l.branch,
            allLabel: l.allBranches,
            value: null,
            onChanged: (_) {},
            options: [
              DashOption(value: 'hel', label: l.s('Heliopolis', 'مصر الجديدة')),
              DashOption(value: 'maa', label: l.s('Maadi', 'المعادي')),
            ],
          ),
          DashFilterToggle(label: l.flagged, value: true, onChanged: (_) {}),
          DashDateRangePicker(
            preset: 'last7',
            today: _today,
            presets: [
              DashPeriodPreset(value: 'today', label: l.today),
              DashPeriodPreset(
                value: 'last7',
                label: l.s('Last 7 days', 'آخر 7 أيام'),
              ),
            ],
            onSelectPreset: (_) {},
            onApplyCustom: (a, b) {},
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          DashLedgerStrip(
            items: [
              DashLedgerItem(
                key: 'sales',
                label: l.sales,
                value: 4528650,
                format: DashStatFormat.money,
                icon: 'banknote',
                trend: 0.124,
                hint: l.vsLast,
              ),
              DashLedgerItem(
                key: 'orders',
                label: l.ordersCount,
                value: 1284,
                icon: 'receipt',
                trend: -0.031,
                hint: l.vsLast,
              ),
              DashLedgerItem(
                key: 'avg',
                label: l.avgTicket,
                value: 35270,
                format: DashStatFormat.money,
                icon: 'coins',
              ),
              DashLedgerItem(
                key: 'voids',
                label: l.voids,
                value: 7,
                icon: 'ban',
                tone: DashTone.danger,
                hint: f.money(41500),
              ),
            ],
          ),
          DashDataTable<Order>(
            columns: orderColumns(context, l),
            rows: orders,
            rowKey: (o) => o.ref,
            onRowTap: (_) {},
            selectedRowKey: '1040',
            selectable: true,
            selectedKeys: const {'1041', '1037'},
            onSelectionChanged: (_) {},
            bulkActions: (context, sel, clear) => DashButton(
              label: l.approve,
              size: DashButtonSize.compact,
              onPressed: clear,
            ),
            rowActions: (context, o) => DashMenu(
              items: [
                DashMenuItem(
                  label: l.print,
                  icon: 'printer',
                  onSelected: () {},
                ),
                DashMenuItem(
                  label: l.void_,
                  icon: 'ban',
                  destructive: true,
                  onSelected: () {},
                ),
              ],
              builder: (context, c) => DashIconButton(
                icon: 'more-horizontal',
                semanticLabel: l.s('More', 'المزيد'),
                onPressed: c.toggle,
              ),
            ),
            initialSort: const DashSort('ref', descending: true),
          ),
        ],
      ),
    );
  },
);

Widget _tableStatesBoard(L l) => Builder(
  builder: (context) => DashPageScaffold(
    title: l.s('Table states', 'حالات الجدول'),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        DashSectionHeader(title: l.s('Loading', 'جارٍ التحميل')),
        DashDataTable<Order>(
          columns: orderColumns(context, l),
          rows: const [],
          rowKey: (o) => o.ref,
          loading: true,
          hideViewOptions: true,
        ),
        DashSectionHeader(title: l.s('Failed', 'فشل التحميل')),
        DashDataTable<Order>(
          columns: orderColumns(context, l),
          rows: const [],
          rowKey: (o) => o.ref,
          errorMessage: l.network,
          onRetry: () {},
        ),
        DashSectionHeader(title: l.s('Empty', 'فارغ')),
        DashDataTable<Order>(
          columns: orderColumns(context, l),
          rows: const [],
          rowKey: (o) => o.ref,
          hideViewOptions: true,
          empty: DashEmptyState(
            icon: 'receipt',
            title: l.noOrdersTitle,
            description: l.noOrders,
            action: DashButton(label: l.add, icon: 'plus', onPressed: () {}),
          ),
        ),
        DashSectionHeader(
          title: l.s('Expanded row, load more', 'صف موسّع وتحميل المزيد'),
        ),
        _ExpandedTable(l: l),
      ],
    ),
  ),
);

class _ExpandedTable extends StatelessWidget {
  const _ExpandedTable({required this.l});
  final L l;

  @override
  Widget build(BuildContext context) => DashDataTable<Order>(
    columns: orderColumns(context, l).take(4).toList(),
    rows: orders.take(3).toList(),
    rowKey: (o) => o.ref,
    hideViewOptions: true,
    expandedBuilder: (context, o) => Text(
      l.s(
        'Flat White ×2 · Croissant ×1 · paid by card',
        'فلات وايت ×2 · كرواسون ×1 · دفع بالبطاقة',
      ),
      style: DashType.body.copyWith(color: context.madarColors.textSecondary),
    ),
    loadMore: DashLoadMore(hasMore: true, onLoadMore: () {}),
  );
}

class _FormsBoard extends StatefulWidget {
  const _FormsBoard({required this.l});
  final L l;

  @override
  State<_FormsBoard> createState() => _FormsBoardState();
}

class _FormsBoardState extends State<_FormsBoard> {
  final _form = GlobalKey<FormState>();
  String _name = '';
  String _notes = 'Double shot, steamed whole milk.';
  double? _par = 12;
  int? _price = 6500;
  double? _discount = 0.125;
  String? _cat = 'hot';
  String? _cat2;
  Set<String> _stations = {'bar'};
  bool _active = true;
  bool _taxable = false;
  String _size = 'm';
  String _view = 'w';
  DateTime? _start = DateTime(2026, 10, 1);
  String _opens = '07:30';
  DateTime? _from = DateTime(2026, 9, 26);
  DateTime? _to = DateTime(2026, 10, 25);
  String? _tz = 'Africa/Cairo';
  String _en = 'Flat White';
  String _ar = 'فلات وايت';
  String _color = '#0F7A8A';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _form.currentState?.validate(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final c = context.madarColors;
    return DashPageScaffold(
      title: l.s('Forms', 'النماذج'),
      width: DashPageWidth.reading,
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.xl,
          children: [
            DashTextField(
              label: l.itemName,
              value: _name,
              requiredMark: true,
              onChanged: (v) => setState(() => _name = v),
              validator: (v) => v.trim().isEmpty ? l.required : null,
            ),
            DashTextAreaField(
              label: l.notes,
              value: _notes,
              onChanged: (v) => setState(() => _notes = v),
              description: l.nameHint,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(
                  child: DashMoneyField(
                    label: l.price,
                    value: _price,
                    onChanged: (v) => setState(() => _price = v),
                  ),
                ),
                Expanded(
                  child: DashPercentField(
                    label: l.discount,
                    value: _discount,
                    onChanged: (v) => setState(() => _discount = v),
                  ),
                ),
              ],
            ),
            DashNumberField(
              label: l.quantity,
              value: _par,
              stepper: true,
              max: 50,
              presets: const [6, 12, 24],
              onChanged: (v) => setState(() => _par = v),
            ),
            DashSelectField<String>(
              label: l.category,
              value: _cat,
              onChanged: (v) => setState(() => _cat = v),
              options: [
                DashOption(value: 'hot', label: l.hot),
                DashOption(value: 'cold', label: l.cold),
                DashOption(value: 'bakery', label: l.bakery),
              ],
            ),
            DashSelectField<String>(
              label: l.s('Supplier', 'المورّد'),
              value: _cat2,
              searchable: true,
              onChanged: (v) => setState(() => _cat2 = v),
              errorText: l.s(
                'Pick the supplier this item comes from.',
                'اختر المورّد الذي يأتي منه هذا الصنف.',
              ),
              options: [
                DashOption(value: 'a', label: l.s('Nile Dairy', 'ألبان النيل')),
              ],
            ),
            DashMultiSelectField<String>(
              label: l.tags,
              values: _stations,
              onChanged: (v) => setState(() => _stations = v),
              options: [
                DashOption(value: 'bar', label: l.bar),
                DashOption(value: 'kitchen', label: l.kitchen),
                DashOption(value: 'pastry', label: l.pastry),
              ],
            ),
            DashSwitchField(
              label: l.active,
              description: l.activeHint,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            DashCheckboxField(
              label: l.taxable,
              value: _taxable,
              onChanged: (v) => setState(() => _taxable = v),
            ),
            DashRadioGroup<String>(
              label: l.size,
              value: _size,
              horizontal: true,
              onChanged: (v) => setState(() => _size = v),
              options: [
                DashOption(value: 's', label: l.small),
                DashOption(value: 'm', label: l.medium),
                DashOption(value: 'l', label: l.large),
              ],
            ),
            DashFormField<String>(
              label: l.view,
              builder: (context, _) => Align(
                alignment: AlignmentDirectional.centerStart,
                child: DashSegmentedControl<String>(
                  value: _view,
                  onChanged: (v) => setState(() => _view = v),
                  options: [
                    DashOption(value: 'd', label: l.daily),
                    DashOption(value: 'w', label: l.weekly),
                    DashOption(value: 'm', label: l.monthly),
                  ],
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(
                  child: DashDateFormField(
                    label: l.startDate,
                    value: _start,
                    today: _today,
                    warnPast: true,
                    onChanged: (v) => setState(() => _start = v),
                  ),
                ),
                Expanded(
                  child: DashTimeFormField(
                    label: l.opensAt,
                    value: _opens,
                    clearable: true,
                    onChanged: (v) => setState(() => _opens = v),
                  ),
                ),
              ],
            ),
            DashFormField<void>(
              label: l.period,
              builder: (context, _) => DashDateRangeField(
                from: _from,
                to: _to,
                today: _today,
                periodStartDay: 26,
                onChanged: (a, b) => setState(() {
                  _from = a;
                  _to = b;
                }),
              ),
            ),
            DashTimezoneSelect(
              label: l.tz,
              zones: const ['Africa/Cairo', 'Asia/Riyadh', 'Asia/Dubai'],
              value: _tz,
              onChanged: (v) => setState(() => _tz = v),
            ),
            DashBilingualField(
              label: l.itemName,
              en: _en,
              ar: _ar,
              onEnChanged: (v) => setState(() => _en = v),
              onArChanged: (v) => setState(() => _ar = v),
            ),
            DashColorField(
              label: l.brandColor,
              value: _color,
              presets: const [
                '#0F7A8A',
                '#2563C9',
                '#178A4C',
                '#BF5F07',
                '#D0392C',
                '#735CC7',
              ],
              onChanged: (v) => setState(() => _color = v),
            ),
            DashFormField<void>(
              label: l.photo,
              builder: (context, _) => DashImageUploader(
                value: null,
                hint: l.photoHint,
                onPick: () async => DashPickedFile(
                  bytes: Uint8List(4),
                  name: 'a.png',
                  mimeType: 'image/png',
                ),
                onUpload: (_) async => null,
              ),
            ),
            Container(height: 1, color: c.hairline),
          ],
        ),
      ),
    );
  }
}

Widget _displayBoard(L l) => Builder(
  builder: (context) {
    final c = context.madarColors;
    final f = context.dashFormats;
    return DashPageScaffold(
      title: l.s('Display', 'العرض'),
      onBack: () {},
      tabs: DashSectionTabs(
        currentPath: '/settings/brand',
        onNavigate: (_) {},
        tabs: [
          DashSectionTab(path: '/settings', label: l.settings),
          DashSectionTab(path: '/settings/brand', label: l.brand),
          DashSectionTab(path: '/settings/payment-methods', label: l.payments),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              DashButton(label: l.s('Save', 'حفظ'), onPressed: () {}),
              DashButton(
                label: l.s('Cancel', 'إلغاء'),
                variant: DashButtonVariant.outline,
                onPressed: () {},
              ),
              DashButton(
                label: l.s('Secondary', 'ثانوي'),
                variant: DashButtonVariant.secondary,
                onPressed: () {},
              ),
              DashButton(
                label: l.s('Ghost', 'شفاف'),
                variant: DashButtonVariant.ghost,
                icon: 'pencil',
                onPressed: () {},
              ),
              DashButton(
                label: l.void_,
                variant: DashButtonVariant.destructive,
                icon: 'trash-2',
                onPressed: () {},
              ),
              DashButton(
                label: l.s('Saving…', 'جارٍ الحفظ…'),
                loading: true,
                onPressed: () {},
              ),
              DashButton(label: l.s('Disabled', 'معطّل'), onPressed: null),
              DashButton(
                label: l.s('Open recipes', 'فتح الوصفات'),
                variant: DashButtonVariant.link,
                onPressed: () {},
              ),
              DashIconButton(
                icon: 'refresh-cw',
                semanticLabel: l.s('Refresh', 'تحديث'),
                variant: DashButtonVariant.outline,
                onPressed: () {},
              ),
            ],
          ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final t in DashTone.values)
                DashStatusPill(
                  label: switch (t) {
                    DashTone.neutral => l.s('Draft', 'مسودة'),
                    DashTone.accent => l.open,
                    DashTone.success => l.paid,
                    DashTone.warning => l.pending,
                    DashTone.danger => l.voided,
                    DashTone.info => l.s('Scheduled', 'مجدول'),
                  },
                  tone: t,
                ),
              DashStatusPill(
                label: l.paid,
                tone: DashTone.success,
                small: true,
              ),
              DashBadge(l.s('3 selected', '3 محدد')),
              const DashFoodCostChip(ratio: 0.27),
              const DashFoodCostChip(ratio: 0.36),
              const DashFoodCostChip(ratio: 0.48),
            ],
          ),
          DashSectionHeader(
            title: l.section,
            description: l.sectionSub,
            icon: 'wallet',
            count: 4,
            countTone: DashTone.success,
            trailing: DashButton(
              label: l.s('View all', 'عرض الكل'),
              variant: DashButtonVariant.ghost,
              size: DashButtonSize.compact,
              onPressed: () {},
            ),
          ),
          DashListCard(
            children: [
              DashListRow(
                variant: DashListRowVariant.nav,
                icon: 'palette',
                title: l.brand,
                meta: l.s(
                  'Logo, colours, receipt footer',
                  'الشعار والألوان وتذييل الإيصال',
                ),
                value: l.s('Set', 'مضبوط'),
                onTap: () {},
              ),
              DashListRow(
                variant: DashListRowVariant.ledger,
                signIn: true,
                title: l.cashIn,
                meta: '08:00 AM · ${l.s('Sara', 'سارة')}',
                value: f.money(50000, signed: true),
                numericValue: true,
              ),
              DashListRow(
                variant: DashListRowVariant.ledger,
                signIn: false,
                title: l.payout,
                meta: '11:20 AM · ${l.s('Omar', 'عمر')}',
                value: f.money(-18000),
                numericValue: true,
              ),
              DashListRow(
                icon: 'users',
                title: l.members,
                meta: l.s('12 people · 3 branches', '12 شخصًا · 3 فروع'),
                trailing: DashStatusPill(
                  label: l.active,
                  tone: DashTone.success,
                  small: true,
                ),
                selected: true,
                onTap: () {},
              ),
            ],
          ),
          DashCard(
            child: Column(
              children: [
                DashSummaryLine(
                  label: l.subtotal,
                  value: f.money(171930, withCurrency: false),
                ),
                DashSummaryLine(
                  label: l.vat,
                  value: f.money(24070, withCurrency: false),
                  muted: true,
                ),
                Divider(height: 1, color: c.hairline),
                DashSummaryLine(
                  label: l.grand,
                  value: f.money(196000),
                  emphasis: true,
                ),
              ],
            ),
          ),
          DashCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                Text(
                  l.progress,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                DashProgressBar(value: 72, semanticLabel: l.progress),
                DashProgressBar(
                  value: 40,
                  semanticLabel: l.progress,
                  tone: DashTone.warning,
                ),
                DashProgressBar(
                  value: 95,
                  semanticLabel: l.progress,
                  tone: DashTone.success,
                ),
                Row(
                  spacing: Space.lg,
                  children: [
                    DashAnimatedFigure(
                      f.money(196000),
                      style: DashType.statFigure(
                        20,
                      ).copyWith(color: c.textPrimary),
                    ),
                    DashConciseValue(
                      full: f.money(452865000),
                      compact: f.moneyCompact(452865000),
                      forceCompact: true,
                      style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
                DashItemCostCell(
                  onFixMissing: () {},
                  skus: [
                    DashSkuCost(
                      sizeLabel: l.small,
                      cost: 1450,
                      foodCostRatio: 0.24,
                    ),
                    DashSkuCost(
                      sizeLabel: l.large,
                      cost: 2380,
                      foodCostRatio: 0.41,
                      costMissing: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          DashLedgerStrip(
            items: [
              DashLedgerItem(
                key: 'a',
                label: l.sales,
                value: 452865000,
                format: DashStatFormat.money,
                icon: 'banknote',
              ),
              DashLedgerItem(
                key: 'b',
                label: l.ordersCount,
                value: 1284,
                icon: 'receipt',
              ),
              DashLedgerItem(
                key: 'c',
                label: l.avgTicket,
                value: 0.184,
                format: DashStatFormat.percent,
                icon: 'percent',
                trend: 0.02,
              ),
              DashLedgerItem(
                key: 'd',
                label: l.voids,
                value: 3,
                icon: 'ban',
                tone: DashTone.warning,
              ),
              DashLedgerItem(
                key: 'e',
                label: l.s('Loading', 'جارٍ التحميل'),
                loading: true,
                icon: 'clock',
              ),
            ],
          ),
          DashEmptyState(
            icon: 'inbox',
            title: l.noOrdersTitle,
            description: l.noOrders,
          ),
          DashErrorState(message: l.network, onRetry: () {}),
          DashEditableCardGrid<Order>(
            rows: orders.take(4).toList(),
            rowKey: (o) => o.ref,
            searchText: (o) => o.customer,
            searchPlaceholder: l.searchOrders,
            onAdd: () {},
            onExport: () {},
            onPasteRows: (_) async {},
            bulkActions: (context, sel, clear) => const SizedBox.shrink(),
            actions: (o) => [DashMenuItem(label: l.print, onSelected: () {})],
            titleField: DashEditableField(
              key: 'customer',
              label: l.customer,
              getValue: (o) => customerOf(l, o),
            ),
            fields: [
              DashEditableField(
                key: 'total',
                label: l.total,
                type: DashEditableType.money,
                getValue: (o) => o.total,
              ),
              DashEditableField(
                key: 'ref',
                label: l.ref,
                getValue: (o) => '#${o.ref}',
              ),
              DashEditableField(
                key: 'active',
                label: l.active,
                type: DashEditableType.boolean,
                getValue: (o) => o.status == 0,
              ),
            ],
            onCommit: (row, patch) async {},
          ),
        ],
      ),
    );
  },
);

Widget _chartsBoard(L l) => Builder(
  builder: (context) {
    final f = context.dashFormats;
    final days = [
      for (var i = 0; i < 14; i++)
        '${25 + i > 30 ? i - 5 : 25 + i}/${25 + i > 30 ? 10 : 9}',
    ];
    String compact(double v) => f.moneyCompact(v.round());
    String money(double v) => f.money(v.round());
    return DashPageScaffold(
      title: l.s('Charts', 'الرسوم البيانية'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          DashChartCard(
            title: l.salesTrend,
            description: l.salesTrendSub,
            actions: [
              DashSegmentedControl<int>(
                value: 0,
                onChanged: (_) {},
                options: [
                  DashOption(value: 0, label: l.daily),
                  DashOption(value: 1, label: l.weekly),
                ],
              ),
            ],
            child: DashLineChart(
              labels: days,
              formatY: compact,
              formatValue: money,
              series: [
                DashSeries(label: l.thisWeek, values: salesByDay),
                DashSeries(label: l.lastWeek, values: salesLastWeek),
              ],
            ),
          ),
          DashChartCard(
            title: l.byChannel,
            child: DashBarChart(
              labels: days.take(7).toList(),
              stacked: true,
              formatY: (v) => f.number(v.round()),
              series: [
                DashSeries(
                  label: l.dineIn,
                  values: const [42, 51, 38, 60, 64, 72, 58],
                ),
                DashSeries(
                  label: l.takeaway,
                  values: const [30, 28, 35, 31, 40, 44, 39],
                ),
                DashSeries(
                  label: l.delivery,
                  values: const [12, 18, 15, 20, 26, 31, 22],
                ),
              ],
            ),
          ),
          DashChartCard(
            title: l.byBranch,
            child: DashBarChart(
              labels: [
                l.s('Heliopolis', 'مصر الجديدة'),
                l.s('Maadi', 'المعادي'),
                l.s('New Cairo', 'القاهرة الجديدة'),
                l.s('Zamalek', 'الزمالك'),
              ],
              formatY: compact,
              formatValue: money,
              series: [
                DashSeries(
                  label: l.thisWeek,
                  values: const [1840000, 1320000, 2210000, 980000],
                ),
                DashSeries(
                  label: l.lastWeek,
                  values: const [1700000, 1450000, 1980000, 1050000],
                ),
              ],
            ),
          ),
          DashChartCard(
            title: l.payMix,
            child: DashDonutChart(
              centerLabel: l.sales,
              centerValue: f.moneyCompact(4528650),
              formatValue: (v) => f.money(v.round()),
              slices: [
                DashSlice(label: l.cash, value: 2210000),
                DashSlice(label: l.card, value: 1520000),
                DashSlice(label: l.wallet, value: 560000),
                DashSlice(label: l.talabat, value: 238650),
              ],
            ),
          ),
          DashChartCard(
            title: l.s('Share by channel', 'الحصة حسب القناة'),
            child: DashDonutChart(
              pie: true,
              size: 160,
              slices: [
                DashSlice(label: l.dineIn, value: 46),
                DashSlice(label: l.takeaway, value: 31),
                DashSlice(label: l.delivery, value: 23),
              ],
            ),
          ),
          DashCard(
            child: Row(
              spacing: Space.lg,
              children: [
                Expanded(
                  child: DashStatCard(
                    label: l.sales,
                    value: 4528650,
                    format: DashStatFormat.money,
                    dense: true,
                  ),
                ),
                const SizedBox(
                  width: 120,
                  child: DashSparkline(values: salesByDay),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  },
);

// ── Overlay states ───────────────────────────────────────────────────────

class _OverlayHost extends StatelessWidget {
  const _OverlayHost({required this.l, required this.open});
  final L l;
  final Future<void> Function(BuildContext context) open;

  @override
  Widget build(BuildContext context) {
    return DashPageScaffold(
      title: l.orders,
      subtitle: l.ordersSub,
      body: Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DashButton(
                key: const ValueKey('open'),
                label: l.s('Open', 'فتح'),
                onPressed: () => open(context),
              ),
            ),
            DashDataTable<Order>(
              columns: orderColumns(context, l),
              rows: orders.take(5).toList(),
              rowKey: (o) => o.ref,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openDialog(BuildContext context, L l) async {
  var name = 'Flat White';
  await showDashDialog<void>(
    context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => DashSurface(
        title: l.editItem,
        description: l.editItemSub,
        actions: [
          DashButton(
            label: l.s('Cancel', 'إلغاء'),
            variant: DashButtonVariant.outline,
            onPressed: () => Navigator.pop(context),
          ),
          DashButton(
            label: l.s('Save changes', 'حفظ التغييرات'),
            onPressed: () {},
          ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            DashTextField(
              label: l.itemName,
              value: name,
              onChanged: (v) => set(() => name = v),
            ),
            DashMoneyField(label: l.price, value: 6500, onChanged: (_) {}),
            DashTextField(
              label: l.s('Barcode', 'الباركود'),
              value: '62210',
              onChanged: (_) {},
              errorText: l.s(
                'Another item already uses this barcode.',
                'هذا الباركود مستخدم لصنف آخر.',
              ),
            ),
            DashSwitchField(label: l.active, value: true, onChanged: (_) {}),
          ],
        ),
      ),
    ),
  );
}

Future<void> _openPanel(BuildContext context, L l) async {
  final f = context.dashFormats;
  await showDashSidePanel<void>(
    context,
    builder: (context) => DashSurface(
      title: l.orderTitle,
      description: l.orderSub,
      headerTrailing: DashStatusPill(label: l.paid, tone: DashTone.success),
      actions: [
        DashButton(
          label: l.print,
          icon: 'printer',
          variant: DashButtonVariant.outline,
          onPressed: () {},
        ),
        DashButton(
          label: l.void_,
          variant: DashButtonVariant.destructive,
          onPressed: () {},
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DashListCard(
            children: [
              DashListRow(
                title: l.s('Flat White ×2', 'فلات وايت ×2'),
                meta: l.medium,
                value: f.money(13000),
                numericValue: true,
              ),
              DashListRow(
                title: l.s('Croissant', 'كرواسون'),
                meta: l.bakery,
                value: f.money(4500),
                numericValue: true,
              ),
            ],
          ),
          DashSummaryLine(
            label: l.subtotal,
            value: f.money(17500, withCurrency: false),
          ),
          DashSummaryLine(
            label: l.grand,
            value: f.money(19950),
            emphasis: true,
          ),
        ],
      ),
    ),
  );
}

// ── Harness ──────────────────────────────────────────────────────────────

const _modes = [('en', false), ('ar', true)];

/// A gallery test: full error reports, and real (blurred) shadows for the
/// length of the body — the binding checks they are flat again at its end.
void _galleryTest(
  String name,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(name, (tester) async {
    _verbose();
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

String _tag(DashSize size, String lang, bool dark) =>
    '${size.name}-$lang-${dark ? 'dark' : 'light'}';

/// Prints every framework error in full (which widget, where) before the
/// test binding records it.
void _verbose() {
  final inner = FlutterError.onError;
  FlutterError.onError = (d) {
    FlutterError.dumpErrorToConsole(d, forceReport: true);
    inner?.call(d);
  };
}

void _clean(WidgetTester tester, String what) {
  final e = tester.takeException();
  if (e == null) return;
  // ignore: avoid_print
  print(e is FlutterError ? e.toStringDeep() : '$e');
  fail('$what did not lay out cleanly: $e');
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Shoots the board, then scrolls the page a viewport at a time and shoots
/// each further part.
Future<void> _shootScrolling(
  WidgetTester tester,
  String board,
  String tag,
) async {
  final dir = dashShotsDir;
  _clean(tester, '$board $tag');
  if (dir == null) return;
  await captureShot(tester, '$dir/kit/$board--$tag.png');
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) return;
  final state = tester.state<ScrollableState>(scrollables.first);
  final pos = state.position;
  var part = 2;
  while (pos.pixels < pos.maxScrollExtent - 1 && part <= 8) {
    pos.jumpTo(
      (pos.pixels + pos.viewportDimension * 0.85).clamp(0, pos.maxScrollExtent),
    );
    await _settle(tester);
    await captureShot(tester, '$dir/kit/$board-$part--$tag.png');
    part++;
  }
}

Future<void> _shoot(WidgetTester tester, String name, String tag) async {
  _clean(tester, '$name $tag');
  final dir = dashShotsDir;
  if (dir != null) await captureShot(tester, '$dir/kit/$name--$tag.png');
}

void main() {
  setUpAll(loadDashFonts);

  final boards = <String, Widget Function(L)>{
    'page': _pageBoard,
    'table-states': _tableStatesBoard,
    'forms': (l) => _FormsBoard(l: l),
    'display': _displayBoard,
    'charts': _chartsBoard,
  };

  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = _tag(size, lang, dark);
      final l = L(lang);
      for (final MapEntry(key: name, value: board) in boards.entries) {
        _galleryTest('$name · $tag', (tester) async {
          await pumpDashApp(
            tester,
            Scaffold(body: SafeArea(child: board(l))),
            size: size,
            lang: lang,
            dark: dark,
          );
          await _settle(tester);
          await _shootScrolling(tester, name, tag);
        });
      }

      Future<void> overlay(
        WidgetTester tester,
        String name,
        Future<void> Function(BuildContext) open,
      ) async {
        await pumpDashApp(
          tester,
          Scaffold(
            body: SafeArea(
              child: _OverlayHost(l: l, open: open),
            ),
          ),
          size: size,
          lang: lang,
          dark: dark,
        );
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('open')));
        await _settle(tester);
        await _shoot(tester, name, tag);
      }

      _galleryTest(
        'dialog · $tag',
        (tester) => overlay(tester, 'dialog', (c) => _openDialog(c, l)),
      );
      _galleryTest(
        'side-panel · $tag',
        (tester) => overlay(tester, 'side-panel', (c) => _openPanel(c, l)),
      );
      _galleryTest('confirm · $tag', (tester) async {
        await overlay(
          tester,
          'confirm',
          (c) => showDashConfirm(
            c,
            title: l.deleteBranch,
            description: l.deleteBranchSub,
            destructive: true,
            confirmLabel: l.s('Delete', 'حذف'),
          ),
        );
      });
      _galleryTest('toast · $tag', (tester) async {
        await overlay(tester, 'toast', (c) async {
          DashToast.success(c, l.saved);
          DashToast.error(
            c,
            l.failed,
            description: l.s(
              'Ask an owner to grant it.',
              'اطلب من المالك منحها.',
            ),
          );
        });
        DashToast.clear(tester.element(find.byType(Scaffold).first));
        await tester.pump();
      });
      _galleryTest('select-open · $tag', (tester) async {
        await pumpDashApp(
          tester,
          Scaffold(body: SafeArea(child: _pageBoard(l))),
          size: size,
          lang: lang,
          dark: dark,
        );
        await _settle(tester);
        await tester.tap(find.bySemanticsLabel(RegExp('^${l.status}:')).first);
        await _settle(tester);
        await _shoot(tester, 'select-open', tag);
      });
      _galleryTest('date-range-open · $tag', (tester) async {
        await pumpDashApp(
          tester,
          Scaffold(body: SafeArea(child: _pageBoard(l))),
          size: size,
          lang: lang,
          dark: dark,
        );
        await _settle(tester);
        await tester.tap(find.text(l.s('Last 7 days', 'آخر 7 أيام')));
        await _settle(tester);
        await _shoot(tester, 'date-range-open', tag);
      });
      _galleryTest('menu-open · $tag', (tester) async {
        await pumpDashApp(
          tester,
          Scaffold(body: SafeArea(child: _pageBoard(l))),
          size: size,
          lang: lang,
          dark: dark,
        );
        await _settle(tester);
        await tester.tap(find.bySemanticsLabel(l.s('More', 'المزيد')).first);
        await _settle(tester);
        await _shoot(tester, 'menu-open', tag);
      });
      _galleryTest('date-open · $tag', (tester) async {
        await pumpDashApp(
          tester,
          Scaffold(
            body: SafeArea(child: _FormsBoard(l: l)),
          ),
          size: size,
          lang: lang,
          dark: dark,
        );
        await _settle(tester);
        final target = find.bySemanticsLabel(RegExp('^${l.startDate}:'));
        await tester.ensureVisible(target.first);
        await _settle(tester);
        await tester.tap(target.first);
        await _settle(tester);
        await _shoot(tester, 'date-open', tag);
      });
    }
  }
}
