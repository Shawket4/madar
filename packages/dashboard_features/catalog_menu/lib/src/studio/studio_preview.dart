/// Studio section 7, the preview (the web's `preview/preview-panel.tsx`): a
/// dry run of the SAVED item on the server: pick a size and choices, see the
/// price, what is deducted, the cost and any issues. Asked 300 ms after the
/// last change; the previous answer stays on screen while a new one loads.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart'
    show PreviewRequest, PreviewResponse, StudioAggregate;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_text.dart';
import 'preview_model.dart';
import 'studio_providers.dart';
import 'studio_widgets.dart';

const Duration _debounce = Duration(milliseconds: 300);

class StudioPreviewPanel extends ConsumerStatefulWidget {
  const StudioPreviewPanel({required this.studio, super.key});

  final StudioAggregate studio;

  @override
  ConsumerState<StudioPreviewPanel> createState() => _StudioPreviewPanelState();
}

class _StudioPreviewPanelState extends ConsumerState<StudioPreviewPanel> {
  PreviewSelection _sel = const PreviewSelection();
  Map<String, String> _defaults = const {};
  PreviewKey? _key;
  Timer? _timer;

  /// The last answer, kept while a new one loads (`placeholderData`).
  PreviewResponse? _last;

  @override
  void initState() {
    super.initState();
    _key = previewKeyOf(widget.studio.id, _body());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<PreviewGroup> get _groups => toPreviewGroups(widget.studio);

  PreviewRequest _body() => toPreviewBody(_sel, _groups, _defaults);

  void _change(PreviewSelection next) {
    setState(() => _sel = next);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (!mounted) return;
      final k = previewKeyOf(widget.studio.id, _body());
      if (k != _key) setState(() => _key = k);
    });
  }

  @override
  void didUpdateWidget(StudioPreviewPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.studio, widget.studio)) _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = ref.watch(studioPreviewProvider(_key!));
    final fresh = q.value;
    if (fresh != null) _last = fresh;
    final data = fresh ?? _last;
    if (fresh != null) {
      final d = fresh.defaults;
      if (!_sameMap(d, _defaults)) {
        // The server's defaults change what the body says; ask again.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _defaults = d);
          _schedule();
        });
      }
    }
    final fetching = q.isLoading;
    String plain(num p) => fmt.fmtMoney(p, currency: false, fractionDigits: 0);
    // "+25" as one unit, so the sign stays before the figure in Arabic.
    String plus(num p) =>
        fmt.fmtMoney(p, currency: false, fractionDigits: 0, signed: true);
    final groups = _groups;
    final sizes = [
      for (final s in widget.studio.sizes)
        if (s.isActive) s,
    ]..sort((a, b) => a.sort - b.sort);
    final optionals = [
      for (final o in widget.studio.options)
        if (o.isActive) o,
    ];
    final wide = MediaQuery.sizeOf(context).width >= StudioMetrics.sm;
    final labelWidth = Space.xxl * 3.5;

    Widget label(String text, {bool required = false}) => Text.rich(
      TextSpan(
        text: text,
        children: [
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(color: c.errorText),
            ),
        ],
      ),
      style: DashType.smallMedium.copyWith(color: c.textSecondary),
    );

    Widget row(String name, List<Widget> chips, {bool required = false}) {
      final wrap = Wrap(
        spacing: Space.xs + DashMetrics.hair,
        runSpacing: Space.xs + DashMetrics.hair,
        children: chips,
      );
      return wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(top: Space.md),
                    child: label(name, required: required),
                  ),
                ),
                Expanded(child: wrap),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xs,
              children: [
                label(name, required: required),
                wrap,
              ],
            );
    }

    Widget resultRow(String name, Widget value) => wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: labelWidth, child: label(name)),
              Expanded(child: value),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xs,
            children: [label(name), value],
          );

    final picker = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        if (sizes.isNotEmpty)
          row(t('modeling.preview.size'), [
            for (final s in sizes)
              DashChoiceChip(
                label: s.label,
                selected: (_sel.size ?? data?.sizeLabel) == s.label,
                onTap: () => _change(_sel.copyWith(size: s.label)),
              ),
          ]),
        for (final g in groups)
          row(g.name, required: g.required, [
            for (final o in g.options)
              DashChoiceChip(
                label: [
                  o.name,
                  if (o.price != 0) plus(o.price),
                  if (_defaults[g.id] == o.id) t('modeling.preview.default'),
                ].join(' '),
                selected: pickedIn(_sel, g.id, _defaults).contains(o.id),
                onTap: () => _change(togglePick(_sel, g, o.id, _defaults)),
              ),
          ]),
        if (optionals.isNotEmpty)
          row(t('modeling.preview.itemOptions'), [
            for (final o in optionals)
              DashChoiceChip(
                label: o.price != 0 ? '${o.name} ${plus(o.price)}' : o.name,
                selected: _sel.optionals.contains(o.id),
                onTap: () => _change(toggleOptional(_sel, o.id)),
              ),
          ]),
        row(t('modeling.preview.service'), [
          DashChoiceChip(
            label: t('modeling.preview.takeaway'),
            selected: _sel.service == 'takeaway',
            onTap: () => _change(_sel.copyWith(service: 'takeaway')),
          ),
          DashChoiceChip(
            label: t('modeling.preview.dineIn'),
            selected: _sel.service == 'dine_in',
            onTap: () => _change(_sel.copyWith(service: 'dine_in')),
          ),
        ]),
        row(t('modeling.preview.quantity'), [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              DashIconButton(
                icon: 'minus',
                semanticLabel: t('modeling.preview.decrease'),
                variant: DashButtonVariant.outline,
                onPressed: _sel.quantity <= 1
                    ? null
                    : () => _change(_sel.copyWith(quantity: _sel.quantity - 1)),
              ),
              SizedBox(
                width: Space.xl,
                child: Text(
                  '${_sel.quantity}',
                  textAlign: TextAlign.center,
                  style: DashType.mono.copyWith(color: c.textPrimary),
                ),
              ),
              DashIconButton(
                icon: 'plus',
                semanticLabel: t('modeling.preview.increase'),
                variant: DashButtonVariant.outline,
                onPressed: () =>
                    _change(_sel.copyWith(quantity: _sel.quantity + 1)),
              ),
            ],
          ),
        ]),
      ],
    );

    final Widget result;
    if (q.failedFirst && data == null) {
      result = Semantics(
        liveRegion: true,
        child: Text(
          t(
            'modeling.preview.error',
            args: {'error': errorMessage(q.error, t)},
          ),
          style: DashType.body.copyWith(color: c.errorText),
        ),
      );
    } else if (data == null) {
      result = const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.sm,
        children: [
          DashSkeleton(width: Space.xxl * 6, height: Space.lg + Space.xs),
          DashSkeleton(height: Space.xxl * 2),
        ],
      );
    } else {
      result = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          resultRow(
            t('modeling.preview.price'),
            Row(
              spacing: Space.sm,
              children: [
                Flexible(
                  child: Text(
                    ltr(priceLine(data.price, data.quantity, plain)),
                    key: const ValueKey('preview-price-line'),
                    style: DashType.monoMedium.copyWith(color: c.textPrimary),
                  ),
                ),
                if (fetching)
                  SizedBox.square(
                    dimension: IconSize.xs,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          resultRow(
            t('modeling.preview.deducts'),
            data.deductions.isEmpty
                ? Text(
                    t('modeling.preview.noDeductions'),
                    style: DashType.body.copyWith(color: c.textSecondary),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.xs,
                    children: [
                      for (final d in data.deductions)
                        Wrap(
                          spacing: Space.sm,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          children: [
                            Text(
                              '${d.name} · ${ltr(fmt.fmtNumber(d.quantity))} '
                              '${unitWord(t, d.unit)}',
                              style: DashType.body.copyWith(
                                color: d.skipped
                                    ? c.textSecondary
                                    : c.textPrimary,
                                decoration: d.skipped
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            Text(
                              '${t('modeling.preview.source.${d.source}', defaultValue: d.source)}'
                              '${d.note == null || d.note!.isEmpty ? '' : ' · ${d.note}'}',
                              style: DashType.small.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
          resultRow(
            t('modeling.preview.cost'),
            Text(
              '${fmt.fmtMoney(data.cost.total)}'
              '${data.cost.costMissing ? ' (${t('modeling.preview.costPartial')})' : ''}'
              '${data.cost.marginPct == null ? '' : ' · ${t('modeling.preview.margin', args: {'pct': fmt.fmtPercent(data.cost.marginPct!)})}'}',
              style: DashType.body.copyWith(color: c.textPrimary),
            ),
          ),
          if (data.warnings.isEmpty)
            StudioHint(t('modeling.preview.noIssues'))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xs + DashMetrics.hair,
              children: [
                for (final w in data.warnings)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.sm,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: DashMetrics.hair),
                        child: DashIcon(
                          'alert-triangle',
                          size: IconSize.xs,
                          color: DashTone.warning.foreground(c),
                        ),
                      ),
                      DashBadge(w.rule, mono: true, tone: DashTone.warning),
                      Expanded(
                        child: Text(
                          w.message,
                          style: DashType.body.copyWith(
                            color: DashTone.warning.foreground(c),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          picker,
          Padding(
            padding: const EdgeInsets.only(top: Space.lg),
            child: Container(
              padding: const EdgeInsets.only(top: Space.lg),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: result,
            ),
          ),
        ],
      ),
    );
  }
}

bool _sameMap(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
