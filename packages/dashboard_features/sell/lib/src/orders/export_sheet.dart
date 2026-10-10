/// The Orders export sheet (the web's `features/orders/order-export-dialog.tsx`,
/// SELL-ORD-070 … SELL-ORD-080, SELL-ORD-089, SELL-ALL-013/018).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../customers/customers_list.dart' show runExcelExport;
import 'export_data.dart';
import 'orders_providers.dart';

/// The sheet's width from `sm` (`sm:max-w-lg`).
const double ordersExportWidth = 512;

Future<void> showOrdersExport(
  BuildContext context, {
  required OrdersExportFilters filters,
  required OrdersKey listKey,
}) => showDashSidePanel<void>(
  context,
  width: ordersExportWidth,
  builder: (_) => OrdersExportSheet(filters: filters, listKey: listKey),
);

class OrdersExportSheet extends ConsumerStatefulWidget {
  const OrdersExportSheet({
    required this.filters,
    required this.listKey,
    super.key,
  });

  final OrdersExportFilters filters;

  /// The list's read: its total is the estimate, live (it ignores the
  /// preset, SELL-ORD-089).
  final OrdersKey listKey;

  @override
  ConsumerState<OrdersExportSheet> createState() => _OrdersExportSheetState();
}

class _OrdersExportSheetState extends ConsumerState<OrdersExportSheet> {
  // Every open starts here (SELL-ORD-071): a new sheet is a new state.
  ExportPreset _preset = exportPresets.first;
  Set<ExportGrain> _grains = {ExportGrain.order};
  String _filename = '';
  bool _busy = false;
  bool _customize = false;

  void _pick(ExportPreset p) => setState(() {
    _preset = p;
    _grains = p.grains.toSet();
  });

  Future<void> _export(String branchName, String defaultName) async {
    final t = ref.read(tProvider);
    final f = widget.filters;
    if (f.branchId == null) {
      DashToast.error(context, t('ordersExport.selectBranchError'));
      return;
    }
    if (_grains.isEmpty) {
      DashToast.error(context, t('ordersExport.noGrainsSelected'));
      return;
    }
    setState(() => _busy = true);
    try {
      final m = f.merged(_preset);
      final api = apiWithHeaders(
        ref.read(transportProvider),
        exportRequestHeaders,
      );
      final res = await api.orders.exportOrders(
        branchId: m.branchId,
        tillId: m.till,
        tellerName: m.teller,
        waiterName: m.waiter,
        paymentMethod: m.payment,
        status: m.status,
        from: m.from == null ? null : DateTime.parse(m.from!),
        to: m.to == null ? null : DateTime.parse(m.to!),
      );
      if (!mounted) return;
      if (res.data.isEmpty) {
        DashToast.error(context, t('ordersExport.noOrders'));
        return;
      }
      final fmt = ref.read(formatProvider);
      final brand = await ref.read(publicBrandProvider.future);
      if (!mounted) return;
      final sheets = buildExportSheets(
        orders: res.data,
        grains: {
          for (final g in ExportGrain.values)
            if (_grains.contains(g)) g,
        },
        t: t,
        fmt: fmt,
        lang: ref.read(localeProvider),
      );
      await runExcelExport(
        context,
        ref.read(exporterProvider),
        t,
        ExcelConfig(
          filename: _filename.isEmpty ? defaultName : _filename,
          sheets: sheets,
          meta: exportMeta(t: t, fmt: fmt, branchName: branchName, f: m),
          logoUrl: exportLogoUrl(brand),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final f = widget.filters;
    final branchId = f.branchId;
    final branch = watchIfOrders(
      ref,
      branchId != null,
      () => ordersExportBranchProvider(branchId!),
    ).value;
    final branchName = branch?.name ?? '';
    final m = f.merged(_preset);
    final defaultName = exportFilename(
      presetId: _preset.id,
      branchSlug: branchSlug(branchName),
      from: m.from,
      to: m.to,
      now: ref.watch(clockProvider)(),
    );
    final phone = DashBreakpoints.isPhone(context);
    String or(String key, String raw) => t.exists(key) ? t(key) : raw;
    final heading = DashType.smallStrong.copyWith(
      color: c.textSecondary,
      letterSpacing: 0.6,
    );

    Widget twoUp(List<Widget> items) {
      if (phone || MediaQuery.sizeOf(context).width < DashBreakpoints.sm) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: items,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          for (var i = 0; i < items.length; i += 2)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.md,
                children: [
                  Expanded(child: items[i]),
                  Expanded(
                    child: i + 1 < items.length
                        ? items[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    final presets = twoUp([
      for (final p in exportPresets)
        _PresetCard(
          key: ValueKey('preset-${p.id}'),
          icon: p.icon,
          label: t('ordersExport.presets.${p.key}.label'),
          description: t('ordersExport.presets.${p.key}.desc'),
          selected: p.id == _preset.id,
          onTap: () => _pick(p),
        ),
    ]);

    final custom = _preset.id == 'custom';
    final grains = Container(
      key: const ValueKey('export-grains'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          twoUp([
            for (final g in ExportGrain.values)
              Opacity(
                opacity: custom ? 1 : 0.7,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(Radii.control),
                    border: Border.all(color: c.hairline),
                  ),
                  child: DashCheckboxField(
                    key: ValueKey('grain-${g.wire}'),
                    label: t('ordersExport.grains.${g.wire}'),
                    value: _grains.contains(g),
                    enabled: custom,
                    onChanged: (v) => setState(() {
                      _grains = {..._grains};
                      if (v) {
                        _grains.add(g);
                      } else {
                        _grains.remove(g);
                      }
                    }),
                  ),
                ),
              ),
          ]),
          if (!custom)
            Row(
              spacing: Space.xs,
              children: [
                DashIcon('alert-triangle', size: IconSize.xs, color: c.warning),
                Expanded(
                  child: Text(
                    t('ordersExport.lockedGrainsHint'),
                    style: DashType.small.copyWith(color: c.warning),
                  ),
                ),
              ],
            ),
        ],
      ),
    );

    final snapshot = Container(
      key: const ValueKey('export-snapshot'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(t('ordersExport.filtersSummary').toUpperCase(), style: heading),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.lg,
              children: [
                Expanded(
                  child: _SummaryItem(
                    label: t('orders.branch'),
                    value: branchName.isEmpty ? '—' : branchName,
                  ),
                ),
                Expanded(
                  child: _SummaryItem(
                    label: t('common.date'),
                    value: m.from != null && m.to != null
                        ? ltr(
                            '${m.from!.substring(0, 10)} → ${m.to!.substring(0, 10)}',
                          )
                        : t('orders.allTime'),
                  ),
                ),
              ],
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.lg,
              children: [
                Expanded(
                  child: _SummaryItem(
                    label: t('orders.payment'),
                    value: m.payment == null
                        ? t('orders.allPayments')
                        : or('payments.${m.payment}', m.payment!),
                  ),
                ),
                Expanded(
                  child: _SummaryItem(
                    label: t('common.status'),
                    value: m.status == null
                        ? t('orders.allStatuses')
                        : or('orderStatus.${m.status}', m.status!),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Text(t('ordersExport.presets.title').toUpperCase(), style: heading),
            presets,
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DashButton(
                key: const ValueKey('export-customize'),
                label: t('ordersExport.customizeBtn'),
                variant: DashButtonVariant.link,
                trailingIcon: _customize ? 'chevron-up' : 'chevron-down',
                onPressed: () => setState(() => _customize = !_customize),
              ),
            ),
            if (_customize) grains,
          ],
        ),
        snapshot,
        DashTextField(
          key: const ValueKey('export-filename'),
          label: t('ordersExport.filename'),
          placeholder: defaultName,
          value: _filename,
          enabled: !_busy,
          description: t('ordersExport.filenameHint'),
          onChanged: (v) => setState(() => _filename = v),
        ),
      ],
    );

    return PopScope(
      // Escape and a tap outside do nothing while the file is being built.
      canPop: !_busy,
      child: DashSurface(
        title: t('ordersExport.title'),
        description: t('ordersExport.subtitle'),
        showClose: false,
        headerTrailing: DashIconButton(
          icon: 'x',
          semanticLabel: t('common.close'),
          color: c.textSecondary,
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        ),
        body: body,
        actions: [
          _Footer(
            estimate: t(
              'ordersExport.rowEstimate',
              args: {
                'count':
                    ref
                        .watch(ordersListProvider(widget.listKey))
                        .value
                        ?.total ??
                    0,
              },
            ),
            cancel: DashButton(
              label: t('common.cancel'),
              variant: DashButtonVariant.outline,
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            ),
            run: DashButton(
              key: const ValueKey('export-run'),
              label: t('ordersExport.exportButton'),
              loading: _busy,
              onPressed: _grains.isEmpty || branchId == null
                  ? null
                  : () => _export(branchName, defaultName),
            ),
          ),
        ],
      ),
    );
  }
}

/// The estimate and the two buttons (`order-export-dialog.tsx:280-289`):
/// below `sm` the estimate on its own line above Cancel and Export side by
/// side; from `sm` the estimate at the start, the buttons at the end.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.estimate,
    required this.cancel,
    required this.run,
  });

  final String estimate;
  final Widget cancel;
  final Widget run;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      estimate,
      style: DashType.small.copyWith(color: context.madarColors.textSecondary),
    );
    if (MediaQuery.sizeOf(context).width < DashBreakpoints.sm) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          text,
          Row(
            spacing: Space.sm,
            children: [
              Expanded(child: cancel),
              Expanded(child: run),
            ],
          ),
        ],
      );
    }
    return Row(
      spacing: Space.sm,
      children: [
        Expanded(child: text),
        cancel,
        run,
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      pressScale: false,
      builder: (context, s) => Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: selected
              ? c.accent.withValues(alpha: 0.06)
              : (s.highlighted ? c.hover.withValues(alpha: 0.5) : c.card),
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(
            color: selected ? c.accent : c.hairline,
            width: selected ? DashMetrics.hair : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.md,
          children: [
            Container(
              width: Space.xxl + Space.xs,
              height: Space.xxl + Space.xs,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? c.accent.withValues(alpha: 0.1) : c.muted,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: DashIcon(
                icon,
                size: IconSize.xs,
                color: selected ? c.accent : c.textSecondary,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DashMetrics.hair,
                children: [
                  Text(
                    label,
                    style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    description,
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.xs,
      children: [
        Text(label, style: DashType.small.copyWith(color: c.textSecondary)),
        Text(value, style: DashType.smallStrong.copyWith(color: c.textPrimary)),
      ],
    );
  }
}
