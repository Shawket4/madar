/// One owner's allow-list (web `allow-list-editor.tsx`, SET-PAY-028..034,
/// -040): off = no restriction (inherits the wider scope); on = only the
/// ticked methods. Save is enabled once something changed; a restricted
/// list with nothing ticked is refused in place after a Save attempt
/// ("Pick at least one method, or allow all."), mirroring the server's
/// `EMPTY_ALLOW_LIST`. The editor goes back to the server's values whenever
/// the availability read answers again (a save, a live event, a refetch).
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' show AllowList;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A method an editor offers: its id and its name in the active language.
typedef PmChoice = ({String id, String name});

class AllowListEditor extends ConsumerStatefulWidget {
  const AllowListEditor({
    required this.title,
    required this.value,
    required this.source,
    required this.methods,
    required this.onSave,
    this.pending = false,
    this.mono = false,
    super.key,
  });

  final String title;

  /// The server's list for this owner.
  final AllowList value;

  /// The availability answer [value] came from: a new answer resets the
  /// editor to the server's values.
  final Object? source;
  final List<PmChoice> methods;
  final bool pending;
  final ValueChanged<AllowList> onSave;

  /// The title is a device code.
  final bool mono;

  @override
  ConsumerState<AllowListEditor> createState() => _AllowListEditorState();
}

class _AllowListEditorState extends ConsumerState<AllowListEditor> {
  late bool _restricted;
  late List<String> _ids;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _restricted = widget.value.restricted;
    _ids = [...widget.value.paymentMethodIds];
    _submitted = false;
  }

  @override
  void didUpdateWidget(AllowListEditor old) {
    super.didUpdateWidget(old);
    if (!identical(old.source, widget.source)) _reset();
  }

  bool get _dirty =>
      _restricted != widget.value.restricted ||
      !const ListEquality<String>().equals(_ids, widget.value.paymentMethodIds);

  bool get _invalid => _submitted && _restricted && _ids.isEmpty;

  void _save() {
    setState(() => _submitted = true);
    if (_restricted && _ids.isEmpty) return;
    widget.onSave(
      _restricted
          ? AllowList(restricted: true, paymentMethodIds: [..._ids])
          : const AllowList(restricted: false, paymentMethodIds: []),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final twoColumns = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final pad = twoColumns ? Space.card : Space.lg;
    final choices = [
      for (final m in widget.methods)
        _Choice(
          key: ValueKey('allow-choice-${m.id}'),
          name: m.name,
          checked: _ids.contains(m.id),
          onChanged: (on) => setState(() {
            _ids = on
                ? [..._ids, m.id]
                : [
                    for (final x in _ids)
                      if (x != m.id) x,
                  ];
          }),
        ),
    ];
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          Row(
            spacing: Space.sm,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MadarClippedText(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (widget.mono
                                  ? DashType.monoStrong
                                  : DashType.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ))
                              .copyWith(color: c.textPrimary),
                    ),
                    Text(
                      _restricted
                          ? t(
                              'paymentMethods.availability.selectedCount',
                              count: _ids.length,
                            )
                          : t('paymentMethods.availability.inherits'),
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              // The words are the switch's label: a tap on them toggles too.
              DashPressable(
                key: const ValueKey('allow-restrict'),
                onTap: () => setState(() => _restricted = !_restricted),
                isButton: false,
                checked: _restricted,
                semanticLabel: t('paymentMethods.availability.restrict'),
                excludeChildSemantics: true,
                pressScale: false,
                builder: (context, s) => Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.sm,
                  children: [
                    Text(
                      t(
                        _restricted
                            ? 'paymentMethods.availability.onlySelected'
                            : 'paymentMethods.availability.allMethods',
                      ),
                      style: DashType.body.copyWith(color: c.textSecondary),
                    ),
                    DashSwitch(
                      value: _restricted,
                      semanticLabel: t('paymentMethods.availability.restrict'),
                      onChanged: (v) => setState(() => _restricted = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_restricted)
            Container(
              padding: const EdgeInsets.only(top: Space.md),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: twoColumns
                  ? _TwoColumns(children: choices)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Space.sm,
                      children: choices,
                    ),
            ),
          if (_invalid)
            Semantics(
              liveRegion: true,
              child: Text(
                t('paymentMethods.availability.emptyList'),
                style: DashType.small.copyWith(color: c.danger),
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: DashButton(
              label: t('common.save'),
              size: DashButtonSize.compact,
              loading: widget.pending,
              onPressed: _dirty ? _save : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Two equal columns, filled row by row (`sm:grid-cols-2 gap-2`).
class _TwoColumns extends StatelessWidget {
  const _TwoColumns({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.sm,
    children: [
      for (var i = 0; i < children.length; i += 2)
        Row(
          spacing: Space.sm,
          children: [
            Expanded(child: children[i]),
            Expanded(
              child: i + 1 < children.length
                  ? children[i + 1]
                  : const SizedBox.shrink(),
            ),
          ],
        ),
    ],
  );
}

/// One method to tick: a bordered row, washed while ticked; the whole row
/// toggles.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.name,
    required this.checked,
    required this.onChanged,
    super.key,
  });

  final String name;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: () => onChanged(!checked),
      isButton: false,
      checked: checked,
      semanticLabel: name,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        padding: const EdgeInsetsDirectional.only(end: Space.md),
        decoration: BoxDecoration(
          color: checked || s.highlighted ? c.muted : null,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            DashCheckbox(
              value: checked,
              semanticLabel: name,
              onChanged: (v) => onChanged(v),
            ),
            Expanded(
              child: MadarClippedText(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
