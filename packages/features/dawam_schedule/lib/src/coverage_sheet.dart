/// The weekly coverage grid (SC-13): how many people each hour band needs,
/// per weekday. Suggestions fill the gaps against it. Typed here for a
/// Dawam-only business; a Madar business sees what its sales suggest until
/// it types its own.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

/// Server weekday (0 = Sunday) from a Dart one (1 = Monday … 7 = Sunday).
int _dow(int weekday) => weekday % 7;

/// Saturday first, as the week is.
const _week = [6, 7, 1, 2, 3, 4, 5];

String _hh(int h) => '${h.toString().padLeft(2, '0')}:00';

class CoverageSheet extends ConsumerStatefulWidget {
  const CoverageSheet({required this.branch, super.key});

  final String branch;

  @override
  ConsumerState<CoverageSheet> createState() => _CoverageSheetState();
}

class _CoverageSheetState extends ConsumerState<CoverageSheet> {
  late List<J> _needs = [
    for (final n in _list('needs')) Map<String, dynamic>.of(n),
  ];
  int _day = 6;
  int _from = 12;
  int _to = 15;
  int _staff = 2;

  List<J> _list(String k) =>
      ((ref.read(dawamProvider).coverage[widget.branch]?[k]
                  as List<dynamic>?) ??
              const [])
          .cast<J>();

  int _hour(Object? t) => int.parse('$t'.split(':').first);

  void _save(List<J> needs) {
    setState(() => _needs = needs);
    ref.read(dawamProvider).setCoverage(widget.branch, needs);
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(dawamProvider).coverage[widget.branch] ?? const {};
    final source = view['source'] as String? ?? 'pattern';
    final derived = _list('derived');
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarStatusPill.of(switch (source) {
          'grid' => tr('staff.coverage_typed'),
          'pos' => tr('staff.coverage_from_sales', {
            'n': (view['orders_per_staff'] as Object?) ?? 12,
          }),
          _ => tr('staff.coverage_from_pattern'),
        }),
        for (final w in _week)
          if (_needs.any((n) => n['day_of_week'] == _dow(w)) ||
              (_needs.isEmpty &&
                  derived.any((n) => n['day_of_week'] == _dow(w))))
            DawamSection(
              weekday(w),
              children: [
                for (final n in _needs.where(
                  (n) => n['day_of_week'] == _dow(w),
                ))
                  MadarListRow.nav(
                    title:
                        '${_hh(_hour(n['band_start']))} – ${_hh(_hour(n['band_end']) == 23 && '${n['band_end']}'.startsWith('23:59') ? 24 : _hour(n['band_end']))}',
                    valueText: '${n['staff']}',
                    glyph: MadarGlyph.close,
                    onTap: () => _save([..._needs]..remove(n)),
                  ),
                if (_needs.isEmpty)
                  for (final n in derived.where(
                    (n) => n['day_of_week'] == _dow(w),
                  ))
                    MadarListRow.nav(
                      title:
                          '${_hh(_hour(n['band_start']))} – ${_hh(_hour(n['band_start']) + 1)}',
                      valueText: '${n['staff']}',
                    ),
              ],
            ),
        DawamSection(
          tr('staff.people_needed'),
          children: [
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final w in _week)
                  MadarChip(
                    label: weekday(w),
                    selected: _day == w,
                    onTap: () => setState(() => _day = w),
                  ),
              ],
            ),
            Wrap(
              spacing: Space.md,
              runSpacing: Space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_hh(_from), style: MadarType.title),
                MadarStepper(
                  value: _from,
                  max: 23,
                  onChanged: (v) => setState(() {
                    _from = v;
                    if (_to <= v) _to = v + 1;
                  }),
                ),
                Text(_hh(_to), style: MadarType.title),
                MadarStepper(
                  value: _to,
                  min: 1,
                  max: 24,
                  onChanged: (v) => setState(() {
                    _to = v;
                    if (_from >= v) _from = v - 1;
                  }),
                ),
              ],
            ),
            Row(
              spacing: Space.md,
              children: [
                Expanded(
                  child: Text(
                    tr('staff.people_needed'),
                    style: MadarType.body.copyWith(color: c.textSecondary),
                  ),
                ),
                Text('$_staff', style: MadarType.title),
                MadarStepper(
                  value: _staff,
                  max: 50,
                  onChanged: (v) => setState(() => _staff = v),
                ),
              ],
            ),
            MadarButton(
              label: tr('common.save'),
              glyph: MadarGlyph.check,
              onTap: () => _save([
                ..._needs.where(
                  (n) =>
                      !(n['day_of_week'] == _dow(_day) &&
                          _hour(n['band_start']) == _from),
                ),
                {
                  'day_of_week': _dow(_day),
                  'band_start': '${_hh(_from)}:00',
                  'band_end': _to == 24 ? '23:59:59' : '${_hh(_to)}:00',
                  'staff': _staff,
                },
              ]),
            ),
          ],
        ),
      ],
    );
  }
}
