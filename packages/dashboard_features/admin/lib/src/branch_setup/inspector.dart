/// The inspector (the web's `inspector.tsx`): what is selected and
/// everything about it that can change. It is also the way to do anything
/// the canvas does by dragging: every line can be made or removed here with
/// a checkbox or a select. Nothing selected shows the branch itself.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashRoutePrefetch;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'branch_setup_providers.dart';
import 'builder_canvas.dart' show PresenceDot, PresenceTone;
import 'plan.dart';
import 'vocabulary.dart';

/// Marks the inspector, so the canvas's shortcuts leave keys typed here
/// alone (the web's `stopPropagation` on the panel).
class InspectorScope extends StatelessWidget {
  const InspectorScope({required this.child, super.key});

  final Widget child;

  static bool contains(BuildContext? context) =>
      context != null &&
      context.findAncestorWidgetOfExactType<InspectorScope>() != null;

  @override
  Widget build(BuildContext context) => child;
}

const String _none = '__none__';

/// `getTranslatedName`.
String categoryName(PlanCategory c, String lang) {
  final tr = c.nameTranslations;
  if (lang.startsWith('ar') && tr is Map && tr['ar'] is String) {
    return tr['ar']! as String;
  }
  return c.name;
}

class InspectorProps {
  const InspectorProps({
    required this.branchId,
    required this.plan,
    required this.selection,
    required this.editable,
    required this.change,
    required this.onSelect,
    required this.onRemove,
    required this.problems,
    required this.categories,
    required this.registered,
    required this.savedSlots,
    required this.openItems,
    required this.itemOverrides,
    required this.now,
    required this.onItemRouting,
  });

  final String branchId;
  final BuilderPlan plan;
  final Set<String> selection;
  final bool editable;
  final void Function(BuilderPlan Function(BuilderPlan)) change;
  final ValueChanged<PieceRef?> onSelect;
  final ValueChanged<Set<String>> onRemove;
  final List<Problem> problems;
  final List<PlanCategory> categories;
  final List<PlanRegisteredDevice> registered;

  /// Slots that exist on the server, i.e. that a setup code can name.
  final Set<String> savedSlots;
  final Map<String, int> openItems;
  final Map<String, int> itemOverrides;
  final DateTime now;

  /// The "Item routing" link (the page's leave guard applies).
  final VoidCallback onItemRouting;
}

class BuilderInspector extends StatelessWidget {
  const BuilderInspector({required this.props, super.key});

  final InspectorProps props;

  @override
  Widget build(BuildContext context) {
    final p = props;
    final keys = p.selection.toList();
    final Widget panel;
    if (keys.isEmpty) {
      panel = _BranchSummary(p);
    } else if (keys.length > 1) {
      panel = _ManySelected(p);
    } else {
      final ref = PieceRef.parse(keys.single);
      panel = switch (ref.kind) {
        PieceKind.device => switch (p.plan.device(ref.id)) {
          final d? => _DeviceInspector(
            p,
            d,
            key: ValueKey('bb-device-${d.id}'),
          ),
          null => const SizedBox.shrink(),
        },
        PieceKind.printer => switch (p.plan.printer(ref.id)) {
          final x? => _PrinterInspector(
            p,
            x,
            key: ValueKey('bb-printer-${x.id}'),
          ),
          null => const SizedBox.shrink(),
        },
        PieceKind.section => switch (p.plan.section(ref.id)) {
          final s? => _SectionInspector(
            p,
            s,
            key: ValueKey('bb-section-${s.id}'),
          ),
          null => const SizedBox.shrink(),
        },
      };
    }
    return InspectorScope(
      child: Padding(padding: const EdgeInsets.all(Space.lg), child: panel),
    );
  }
}

// ── Building blocks ───────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  const _Panel(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.lg + Space.xs,
    children: children,
  );
}

class _Heading extends StatelessWidget {
  const _Heading({required this.kind, required this.title});

  final String kind;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          kind,
          style: DashType.smallMedium.copyWith(color: c.textSecondary),
        ),
        Semantics(
          header: true,
          child: MadarClippedText(
            title.isEmpty ? '—' : title,
            maxLines: 1,
            style: DashType.sectionTitle.copyWith(color: c.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.label, this.hint, required this.children});

  final String label;
  final String? hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Semantics(
      container: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          Text(
            label.toUpperCase(),
            style: DashType.smallStrong.copyWith(
              color: c.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          if (hint != null)
            Text(hint!, style: DashType.small.copyWith(color: c.textSecondary)),
          ...children,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: DashType.small.copyWith(color: context.madarColors.textSecondary),
  );
}

/// A text field that commits on blur or Enter, so one rename is one undo
/// step.
class CommitField extends StatefulWidget {
  const CommitField({
    required this.label,
    required this.value,
    required this.onCommit,
    this.enabled = true,
    this.placeholder,
    this.keyboardType,
    super.key,
  });

  final String label;
  final String value;
  final bool enabled;
  final String? placeholder;

  /// A numeric keypad, which also reads left to right.
  final TextInputType? keyboardType;
  final ValueChanged<String> onCommit;

  @override
  State<CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<CommitField> {
  late String _text = widget.value;

  /// What Enter committed: the blur that follows must not commit it again
  /// before the new value arrives.
  String? _committed;

  @override
  void didUpdateWidget(CommitField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _text = widget.value;
      _committed = null;
    }
  }

  void _commit() {
    if (_text == widget.value || _text == _committed) return;
    _committed = _text;
    widget.onCommit(_text);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.xs + 2,
    children: [
      _FieldLabel(widget.label),
      DashTextInput(
        value: _text,
        enabled: widget.enabled,
        placeholder: widget.placeholder,
        semanticLabel: widget.label,
        keyboardType: widget.keyboardType,
        textDirection: widget.keyboardType == null ? null : TextDirection.ltr,
        onChanged: (v) => setState(() => _text = v),
        onSubmitted: (_) => _commit(),
        onFocusChange: (focused) {
          if (!focused) _commit();
        },
      ),
    ],
  );
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.checked,
    required this.enabled,
    required this.onChanged,
    required this.label,
    this.hint,
    this.strong = false,
    super.key,
  });

  /// null = some (the dash).
  final bool? checked;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? hint;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Opacity(
      opacity: enabled ? 1 : 0.7,
      child: DashPressable(
        onTap: enabled ? () => onChanged(checked != true) : null,
        enabled: enabled,
        semanticLabel: label,
        checked: checked,
        excludeChildSemantics: true,
        pressScale: false,
        builder: (context, s) => Container(
          constraints: const BoxConstraints(minHeight: DashMetrics.target),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: Space.xs + 2,
          ),
          decoration: BoxDecoration(
            color: s.hovered && enabled ? c.hover : null,
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
          child: Row(
            spacing: Space.sm + 2,
            children: [
              ExcludeSemantics(
                child: DashCheckbox(
                  value: checked,
                  enabled: enabled,
                  semanticLabel: label,
                  onChanged: enabled ? onChanged : null,
                ),
              ),
              Expanded(
                child: MadarClippedText(
                  label,
                  maxLines: 1,
                  style: (strong ? DashType.bodyMedium : DashType.body)
                      .copyWith(color: c.textPrimary),
                ),
              ),
              if (hint != null)
                Text(
                  hint!,
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return CustomPaint(
      foregroundPainter: _Dashed(c.border),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm + 2,
        ),
        child: Text(
          text,
          style: DashType.small.copyWith(color: c.textSecondary),
        ),
      ),
    );
  }
}

class _Dashed extends CustomPainter {
  const _Dashed(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(Radii.xs),
        ).deflate(0.5),
      );
    final out = Path();
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 8) {
        out.addPath(m.extractPath(d, d + 4), Offset.zero);
      }
    }
    canvas.drawPath(
      out,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color;
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DashButton(
    key: const ValueKey('bb-remove'),
    label: label,
    icon: 'trash-2',
    variant: DashButtonVariant.outlineDanger,
    expand: true,
    onPressed: onPressed,
  );
}

// ── Nothing selected: the branch ──────────────────────────────────────────

class _BranchSummary extends ConsumerWidget {
  const _BranchSummary(this.p);

  final InspectorProps p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final plan = p.plan;
    final setup = setupOf(plan);
    final unrouted = unroutedCategories(plan, [
      for (final x in p.categories) x.id,
    ]);
    final fallback = plan.sections.firstWhereOrNull((s) => s.isDefault);
    final chitsHint = plan.sections.isEmpty
        ? t('builder.tillPrintsKitchenHint')
        : t('builder.tillPrintsKitchenHintSections');
    void toggleChits(bool v) =>
        p.change((x) => x.copyWith(tillPrintsKitchen: v));
    return _Panel([
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          _Heading(
            kind: t('builder.thisBranch'),
            title: setup == null
                ? t('builder.noSetup')
                : setupLabel(t, setup).title,
          ),
          if (setup != null)
            Text(
              setupLabel(t, setup).body,
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
        ],
      ),
      if (plan.devices.any((d) => d.kind == 'pos'))
        _Group(
          label: t('builder.kitchenChits'),
          children: [
            // The web's <label>: the words toggle too, and the hint is the
            // switch's description.
            MergeSemantics(
              child: GestureDetector(
                key: const ValueKey('bb-till-chits-row'),
                behavior: HitTestBehavior.opaque,
                onTap: p.editable ? () => toggleChits(!plan.tillPrintsKitchen) : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.md,
                  children: [
                    DashSwitch(
                      key: const ValueKey('bb-till-chits'),
                      value: plan.tillPrintsKitchen,
                      enabled: p.editable,
                      semanticLabel: t('builder.tillPrintsKitchen'),
                      onChanged: p.editable ? toggleChits : null,
                    ),
                    Expanded(
                      child: Semantics(
                        hint: chitsHint,
                        child: ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 2,
                            children: [
                              Text(
                                t('builder.tillPrintsKitchen'),
                                style: DashType.bodyMedium.copyWith(
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                chitsHint,
                                style: DashType.small.copyWith(
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      _Group(
        label: t('builder.checks'),
        children: [
          if (p.problems.isEmpty)
            Row(
              spacing: Space.sm,
              children: [
                MadarIcon('circle-check', size: 16, tint: c.success),
                Expanded(
                  child: Text(
                    t('builder.allGood'),
                    style: DashType.body.copyWith(color: c.success),
                  ),
                ),
              ],
            )
          else
            for (final (i, x) in p.problems.indexed)
              _ProblemRow(
                key: ValueKey('bb-problem-$i'),
                problem: x,
                text: problemText(t, plan, x),
                prefix: x.blocking
                    ? t('builder.mustFix')
                    : t('builder.worthChecking'),
                onTap: x.piece == null ? null : () => p.onSelect(x.piece),
              ),
        ],
      ),
      if (plan.sections.isNotEmpty && unrouted.isNotEmpty)
        _Group(
          label: t('builder.unrouted'),
          hint: t(
            'builder.unroutedHint',
            args: {'name': fallback?.name ?? '—'},
          ),
          children: [
            Wrap(
              spacing: Space.xs + 2,
              runSpacing: Space.xs + 2,
              children: [
                for (final id in unrouted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.sm + 2,
                      vertical: Space.xs,
                    ),
                    decoration: BoxDecoration(
                      color: c.muted,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(switch (p.categories.firstWhereOrNull(
                      (x) => x.id == id,
                    )) {
                      final cat? => categoryName(cat, lang),
                      null => '',
                    }, style: DashType.small.copyWith(color: c.textPrimary)),
                  ),
              ],
            ),
          ],
        ),
      if (!p.editable)
        Text(
          t('builder.lockedHint'),
          style: DashType.small.copyWith(color: c.textSecondary),
        ),
    ]);
  }
}

class _ProblemRow extends StatelessWidget {
  const _ProblemRow({
    required this.problem,
    required this.text,
    required this.prefix,
    required this.onTap,
    super.key,
  });

  final Problem problem;
  final String text;
  final String prefix;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      enabled: onTap != null,
      semanticLabel: '$prefix $text',
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.xs + 2,
        ),
        decoration: BoxDecoration(
          color: s.hovered && onTap != null ? c.hover : null,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.sm,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: MadarIcon(
                'triangle-alert',
                size: 16,
                tint: problem.blocking ? c.danger : c.warning,
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManySelected extends ConsumerWidget {
  const _ManySelected(this.p);

  final InspectorProps p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return _Panel([
      _Heading(
        kind: t('builder.selection'),
        title: t('builder.piecesSelected', count: p.selection.length),
      ),
      Text(
        t('builder.manyHint'),
        style: DashType.small.copyWith(
          color: context.madarColors.textSecondary,
        ),
      ),
      if (p.editable)
        _RemoveButton(
          label: t('builder.removePieces'),
          onPressed: () => p.onRemove(p.selection),
        ),
    ]);
  }
}

// ── A device ──────────────────────────────────────────────────────────────

class _DeviceInspector extends ConsumerWidget {
  const _DeviceInspector(this.p, this.device, {super.key});

  final InspectorProps p;
  final BuilderDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final plan = p.plan;
    final d = device;
    final receiptPrinters = [
      for (final x in plan.printers)
        if (x.role == 'receipt') x,
    ];
    final takenBy = {
      for (final x in plan.devices)
        if (x.deviceId != null && x.id != d.id) x.deviceId!: x.name,
    };
    final compatible = [
      for (final r in p.registered)
        if (r.kind == installKindFor(d.kind)) r,
    ];
    final (:presence, :seen) = presenceOf(d.deviceId, {
      for (final r in p.registered) r.id: r,
    }, p.now);
    final code = seen == null
        ? ''
        : ((seen.label ?? '').isNotEmpty ? seen.label! : seen.code);
    final status = switch (presence) {
      Presence.unclaimed => t('builder.notSetUp'),
      Presence.online => t('builder.onlineAs', args: {'code': code}),
      Presence.offline => t(
        'builder.lastSeen',
        args: {
          'code': code,
          'when': fmt.fmtStamp(seen?.lastSeenAt.toIso8601String(), p.now),
        },
      ),
    };
    void setDevice(BuilderDevice Function(BuilderDevice) f) =>
        p.change((x) => x.mapDevices((y) => y.id == d.id ? f(y) : y));

    return _Panel([
      _Heading(kind: deviceKindLabel(t, d.kind), title: d.name),
      CommitField(
        key: const ValueKey('bb-name'),
        label: t('builder.name'),
        value: d.name,
        enabled: p.editable,
        onCommit: (name) => setDevice((y) => y.copyWith(name: name)),
      ),
      if (d.kind == 'pos' || d.kind == 'waiter')
        _Group(
          label: t('builder.receipts'),
          children: [
            if (receiptPrinters.isEmpty)
              _Empty(t('builder.noReceiptPrinters'))
            else
              DashSelect<String>(
                key: const ValueKey('bb-receipt-select'),
                value: d.receiptPrinterId ?? _none,
                enabled: p.editable,
                expand: true,
                semanticLabel: t('builder.receipts'),
                options: [
                  DashOption(value: _none, label: t('builder.noPrinter')),
                  for (final x in receiptPrinters)
                    DashOption(value: x.id, label: x.name),
                ],
                onChanged: (v) => p.change(
                  (x) => v == _none
                      ? x.mapDevices(
                          (y) => y.id == d.id
                              ? y.copyWith(receiptPrinterId: () => null)
                              : y,
                        )
                      : addLink(
                          x,
                          PieceRef(PieceKind.device, d.id),
                          PieceRef(PieceKind.printer, v),
                        ),
                ),
              ),
          ],
        ),
      if (d.kind == 'kitchen')
        _Group(
          label: t('builder.showsSections'),
          children: [
            if (plan.sections.isEmpty)
              _Empty(t('builder.noSections'))
            else
              for (final s in plan.sections)
                _CheckRow(
                  checked: s.screenIds.contains(d.id),
                  enabled: p.editable,
                  label: s.name,
                  onChanged: (on) => p.change(
                    (x) => on
                        ? addLink(
                            x,
                            PieceRef(PieceKind.section, s.id),
                            PieceRef(PieceKind.device, d.id),
                          )
                        : removeLink(
                            x,
                            PlanLink(
                              LinkKind.shows,
                              PieceRef(PieceKind.section, s.id),
                              PieceRef(PieceKind.device, d.id),
                            ),
                          ),
                  ),
                ),
          ],
        ),
      _Group(
        label: t('builder.theDevice'),
        hint: t('builder.theDeviceHint'),
        children: [
          PresenceDot(
            tone: switch (presence) {
              Presence.online => PresenceTone.online,
              Presence.offline => PresenceTone.offline,
              Presence.unclaimed => PresenceTone.unclaimed,
            },
            label: status,
          ),
          if (compatible.isNotEmpty)
            DashSelect<String>(
              key: const ValueKey('bb-device-select'),
              value: d.deviceId ?? _none,
              enabled: p.editable,
              expand: true,
              // A current install the list no longer has shows blank, as the web's.
              placeholder: '',
              semanticLabel: t('builder.assignDevice'),
              options: [
                DashOption(value: _none, label: t('builder.noDevice')),
                for (final r in compatible)
                  DashOption(
                    value: r.id,
                    label: [
                      (r.label ?? '').isNotEmpty ? r.label! : r.code,
                      if (takenBy[r.id] case final name?)
                        t('builder.inPlace', args: {'name': name}),
                    ].join(' · '),
                  ),
              ],
              onChanged: (v) => p.change(
                (x) => x.mapDevices((y) {
                  if (y.id == d.id) {
                    return y.copyWith(deviceId: () => v == _none ? null : v);
                  }
                  // One install fills one place: take it from wherever it was.
                  return v != _none && y.deviceId == v
                      ? y.copyWith(deviceId: () => null)
                      : y;
                }),
              ),
            ),
          SetupCode(
            key: ValueKey('bb-code-${d.id}'),
            branchId: p.branchId,
            slotId: d.id,
            saved: p.savedSlots.contains(d.id),
          ),
        ],
      ),
      if (p.editable)
        _RemoveButton(
          label: t('builder.removePiece'),
          onPressed: () => p.onRemove({pieceKey(PieceKind.device, d.id)}),
        ),
    ]);
  }
}

/// An 8-digit code the device types to take this place.
class SetupCode extends ConsumerStatefulWidget {
  const SetupCode({
    required this.branchId,
    required this.slotId,
    required this.saved,
    super.key,
  });

  final String branchId;
  final String slotId;
  final bool saved;

  @override
  ConsumerState<SetupCode> createState() => _SetupCodeState();
}

class _SetupCodeState extends ConsumerState<SetupCode> {
  bool _pending = false;
  ActivationCode? _code;

  Future<void> _issue() async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _pending = true);
    try {
      final code = await api.devices.createCode(
        body: CreateActivationCodeRequest(
          branchId: widget.branchId,
          slotId: widget.slotId,
        ),
      );
      bus.invalidate(const [BranchPlanPaths.devices]);
      if (mounted) setState(() => _code = code);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, builderErrorText(e, t));
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    if (!widget.saved) return _Empty(t('builder.saveForCode'));
    final code = _code;
    if (code != null) {
      return Container(
        key: const ValueKey('bb-slot-code'),
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.xs,
          children: [
            Text(
              t('builder.codeFor'),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                code.code,
                style: DashType.monoStrong.copyWith(
                  fontSize: 24,
                  letterSpacing: 4.8,
                  color: c.textPrimary,
                ),
              ),
            ),
            Text(
              t(
                'builder.codeExpires',
                args: {'when': fmt.fmtStamp(code.expiresAt.toIso8601String())},
              ),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      );
    }
    return DashButton(
      key: const ValueKey('bb-get-code'),
      label: t('builder.getCode'),
      icon: 'key-round',
      variant: DashButtonVariant.outline,
      expand: true,
      loading: _pending,
      onPressed: _pending ? null : _issue,
    );
  }
}

// ── A printer ─────────────────────────────────────────────────────────────

class _PrinterInspector extends ConsumerWidget {
  const _PrinterInspector(this.p, this.printer, {super.key});

  final InspectorProps p;
  final BuilderPrinter printer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final plan = p.plan;
    final pr = printer;
    void set(BuilderPrinter Function(BuilderPrinter) f) =>
        p.change((x) => x.mapPrinters((y) => y.id == pr.id ? f(y) : y));
    return _Panel([
      _Heading(kind: printerRoleLabel(t, pr.role), title: pr.name),
      CommitField(
        key: const ValueKey('bb-name'),
        label: t('builder.name'),
        value: pr.name,
        enabled: p.editable,
        onCommit: (name) => set((y) => y.copyWith(name: name)),
      ),
      _Group(
        label: t('builder.connectsBy'),
        children: [
          DashSegmentedControl<String>(
            key: const ValueKey('bb-connection'),
            value: pr.connection,
            enabled: p.editable,
            expand: true,
            semanticLabel: t('builder.connectsBy'),
            options: [
              for (final k in const ['network', 'usb', 'bluetooth'])
                DashOption(value: k, label: connectionLabel(t, k)),
            ],
            onChanged: (k) => set(
              (y) => y.copyWith(
                connection: k,
                port: () => k == 'network' ? pr.port ?? 9100 : null,
              ),
            ),
          ),
          if (pr.network)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.sm,
              children: [
                Expanded(
                  child: CommitField(
                    key: const ValueKey('bb-ip'),
                    label: t('builder.ip'),
                    value: pr.ip ?? '',
                    placeholder: '192.168.1.40',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: p.editable,
                    onCommit: (ip) => set(
                      (y) => y.copyWith(
                        ip: () => ip.trim().isEmpty ? null : ip.trim(),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: CommitField(
                    key: const ValueKey('bb-port'),
                    label: t('builder.port'),
                    value: '${pr.port ?? 9100}',
                    keyboardType: TextInputType.number,
                    enabled: p.editable,
                    onCommit: (v) {
                      final n = parsePort(v);
                      set((y) => y.copyWith(port: () => n));
                    },
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xs + 2,
              children: [
                _FieldLabel(t('builder.pluggedInto')),
                DashSelect<String>(
                  key: const ValueKey('bb-host-select'),
                  value: pr.hostDeviceId ?? _none,
                  enabled: p.editable,
                  expand: true,
                  semanticLabel: t('builder.pluggedInto'),
                  options: [
                    DashOption(value: _none, label: t('builder.pickDevice')),
                    for (final d in plan.devices)
                      DashOption(value: d.id, label: d.name),
                  ],
                  onChanged: (v) => set(
                    (y) =>
                        y.copyWith(hostDeviceId: () => v == _none ? null : v),
                  ),
                ),
              ],
            ),
        ],
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xs + 2,
              children: [
                _FieldLabel(t('builder.brand')),
                DashSelect<String>(
                  key: const ValueKey('bb-brand'),
                  value: pr.brand ?? _none,
                  enabled: p.editable,
                  expand: true,
                  semanticLabel: t('builder.brand'),
                  options: [
                    DashOption(value: _none, label: t('builder.brandOther')),
                    const DashOption(value: 'epson', label: 'Epson'),
                    const DashOption(value: 'star', label: 'Star'),
                  ],
                  onChanged: (v) => set(
                    (y) => y.copyWith(brand: () => v == _none ? null : v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xs + 2,
              children: [
                _FieldLabel(t('builder.paper')),
                DashSegmentedControl<int>(
                  key: const ValueKey('bb-paper'),
                  value: pr.paperMm,
                  enabled: p.editable,
                  expand: true,
                  semanticLabel: t('builder.paper'),
                  options: [
                    for (final n in const [58, 80])
                      DashOption(
                        value: n,
                        label: t('builder.mm', args: {'n': n}),
                      ),
                  ],
                  onChanged: (n) => set((y) => y.copyWith(paperMm: n)),
                ),
              ],
            ),
          ),
        ],
      ),
      if (pr.role == 'kitchen')
        _Group(
          label: t('builder.printsSections'),
          children: [
            if (plan.sections.isEmpty)
              _Empty(t('builder.noSections'))
            else
              for (final s in plan.sections)
                _CheckRow(
                  checked: s.printerIds.contains(pr.id),
                  enabled: p.editable,
                  label: s.name,
                  onChanged: (on) => p.change(
                    (x) => on
                        ? addLink(
                            x,
                            PieceRef(PieceKind.section, s.id),
                            PieceRef(PieceKind.printer, pr.id),
                          )
                        : removeLink(
                            x,
                            PlanLink(
                              LinkKind.prints,
                              PieceRef(PieceKind.section, s.id),
                              PieceRef(PieceKind.printer, pr.id),
                            ),
                          ),
                  ),
                ),
          ],
        )
      else
        _Group(
          label: t('builder.printsFor'),
          children: [
            for (final d in plan.devices)
              if (d.kind == 'pos' || d.kind == 'waiter')
                _CheckRow(
                  checked: d.receiptPrinterId == pr.id,
                  enabled: p.editable,
                  label: d.name,
                  onChanged: (on) => p.change(
                    (x) => on
                        ? addLink(
                            x,
                            PieceRef(PieceKind.device, d.id),
                            PieceRef(PieceKind.printer, pr.id),
                          )
                        : x.mapDevices(
                            (y) => y.id == d.id
                                ? y.copyWith(receiptPrinterId: () => null)
                                : y,
                          ),
                  ),
                ),
          ],
        ),
      if (p.editable)
        _RemoveButton(
          label: t('builder.removePiece'),
          onPressed: () => p.onRemove({pieceKey(PieceKind.printer, pr.id)}),
        ),
    ]);
  }
}

/// The port field: anything that is not a whole number 1–65535 is 9100
/// (`Number.parseInt` reads a leading number, "9100abc" → 9100).
int parsePort(String v) {
  final m = RegExp(r'^\s*[+-]?\d+').firstMatch(v);
  final n = m == null ? null : int.tryParse(m.group(0)!.trim());
  return n != null && n >= 1 && n <= 65535 ? n : 9100;
}

// ── A section ─────────────────────────────────────────────────────────────

class _SectionInspector extends ConsumerWidget {
  const _SectionInspector(this.p, this.section, {super.key});

  final InspectorProps p;
  final BuilderSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final plan = p.plan;
    final s = section;
    final screens = [
      for (final d in plan.devices)
        if (d.kind == 'kitchen') d,
    ];
    final kitchenPrinters = [
      for (final x in plan.printers)
        if (x.role == 'kitchen') x,
    ];
    final owner = <String, String>{};
    for (final x in plan.sections) {
      for (final cat in x.categoryIds) {
        owner[cat] = x.name;
      }
    }
    final cooking = p.openItems[s.id] ?? 0;
    final overrides = p.itemOverrides[s.id] ?? 0;
    final here = p.categories
        .where((cat) => s.categoryIds.contains(cat.id))
        .length;
    final all = here == p.categories.length;
    PieceRef me() => PieceRef(PieceKind.section, s.id);

    return _Panel([
      _Heading(kind: t('builder.kind.section'), title: s.name),
      CommitField(
        key: const ValueKey('bb-name'),
        label: t('builder.name'),
        value: s.name,
        enabled: p.editable,
        onCommit: (name) => p.change(
          (x) =>
              x.mapSections((y) => y.id == s.id ? y.copyWith(name: name) : y),
        ),
      ),
      if (cooking > 0)
        Container(
          key: const ValueKey('bb-cooking'),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            color: c.warningBg,
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.sm,
            children: [
              MadarIcon('triangle-alert', size: 14, tint: c.warning),
              Expanded(
                child: Text(
                  t('builder.cookingNow', count: cooking),
                  style: DashType.small.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
        ),
      // Exactly one section is the catch-all: a choice to MOVE the role
      // here, never a switch that could turn it off everywhere.
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm + 2,
        ),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.xs + 2,
          children: [
            if (s.isDefault)
              Row(
                spacing: Space.sm,
                children: [
                  MadarIcon('circle-check', size: 16, tint: c.accent),
                  Text(
                    t('builder.default'),
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                ],
              )
            else if (p.editable)
              DashButton(
                key: const ValueKey('bb-make-default'),
                label: t('builder.makeDefault'),
                variant: DashButtonVariant.outline,
                size: DashButtonSize.compact,
                onPressed: () => p.change((x) => setDefaultSection(x, s.id)),
              ),
            Text(
              t('builder.defaultHint'),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
      _Group(
        label: t('builder.outputs'),
        children: [
          if (screens.isEmpty && kitchenPrinters.isEmpty)
            _Empty(t('builder.noOutputs')),
          for (final d in screens)
            _CheckRow(
              checked: s.screenIds.contains(d.id),
              enabled: p.editable,
              label: d.name,
              hint: t('builder.kind.kitchen'),
              onChanged: (on) => p.change(
                (x) => on
                    ? addLink(x, me(), PieceRef(PieceKind.device, d.id))
                    : removeLink(
                        x,
                        PlanLink(
                          LinkKind.shows,
                          me(),
                          PieceRef(PieceKind.device, d.id),
                        ),
                      ),
              ),
            ),
          for (final pr in kitchenPrinters)
            _CheckRow(
              checked: s.printerIds.contains(pr.id),
              enabled: p.editable,
              label: pr.name,
              hint: t('builder.kind.kitchenPrinter'),
              onChanged: (on) => p.change(
                (x) => on
                    ? addLink(x, me(), PieceRef(PieceKind.printer, pr.id))
                    : removeLink(
                        x,
                        PlanLink(
                          LinkKind.prints,
                          me(),
                          PieceRef(PieceKind.printer, pr.id),
                        ),
                      ),
              ),
            ),
        ],
      ),
      _Group(
        label: t('builder.categories'),
        hint: t('builder.categoriesHint'),
        children: [
          if (p.categories.isEmpty)
            _Empty(t('builder.noCategories'))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 288),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.border)),
                      ),
                      child: _CheckRow(
                        key: const ValueKey('bb-select-all'),
                        checked: all ? true : (here > 0 ? null : false),
                        enabled: p.editable,
                        strong: true,
                        label: t('builder.selectAll'),
                        hint: t(
                          'builder.categoriesHere',
                          args: {'here': here, 'total': p.categories.length},
                        ),
                        // Some or none ticked → take them all; all ticked →
                        // clear this section.
                        onChanged: (_) => p.change(
                          (x) => routeCategories(x, [
                            for (final cat in p.categories) cat.id,
                          ], all ? null : s.id),
                        ),
                      ),
                    ),
                    for (final cat in p.categories)
                      _CheckRow(
                        checked: s.categoryIds.contains(cat.id),
                        enabled: p.editable,
                        label: categoryName(cat, lang),
                        hint:
                            !s.categoryIds.contains(cat.id) &&
                                owner[cat.id] != null
                            ? t(
                                'builder.inSection',
                                args: {'name': owner[cat.id]},
                              )
                            : null,
                        onChanged: (on) => p.change(
                          (x) => routeCategory(x, cat.id, on ? s.id : null),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (overrides > 0)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.xs,
              children: [
                Text(
                  t('builder.itemOverrides', count: overrides),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
                DashButton(
                  key: const ValueKey('bb-item-routing'),
                  label: t('builder.itemOverridesLink'),
                  variant: DashButtonVariant.link,
                  size: DashButtonSize.compact,
                  onIntent: () =>
                      ref.prefetchRoute(BranchPlanPaths.kitchenRouting),
                  onPressed: p.onItemRouting,
                ),
              ],
            ),
        ],
      ),
      if (p.editable)
        _RemoveButton(
          label: t('builder.removePiece'),
          onPressed: () => p.onRemove({pieceKey(PieceKind.section, s.id)}),
        ),
    ]);
  }
}

/// A failure in words, as the web's `getErrorMessage` picks them: a coded
/// refusal the tables word; an uncoded 403 a missing right; else the
/// server's sentence (kind prefix stripped), which an Arabic screen does not
/// show in English (it reads the status's words instead).
String builderErrorText(Object? error, Translator t) {
  if (error is ApiException) {
    final code = error.code;
    if (code != null && t.exists('errors.codes.$code')) {
      final details = error.details;
      final vars = details is Map && details['vars'] is Map
          ? Map<String, Object?>.from(details['vars']! as Map)
          : null;
      return t('errors.codes.$code', args: vars);
    }
    if (error.status == 429 && code == null) return t('errors.tooManyRequests');
    if (error.status == 403 && code == null) return t('errors.unauthorized');
    final said = error.message.replaceFirst(_serverKind, '').trim();
    final arabicUi = t.lang.startsWith('ar');
    if (said.isNotEmpty && !(arabicUi && !_arabicLetter.hasMatch(said))) {
      return said;
    }
    switch (error.status) {
      case 0:
        return t('errors.networkError');
      case 401:
        return t('errors.sessionExpired');
      case 404:
        return t('errors.notFound');
      case 409:
        return t('errors.conflict');
      case 400 || 422:
        return t('errors.validation');
    }
    if (error.status >= 500) return t('errors.server');
  }
  return errorMessage(error, t);
}

final RegExp _serverKind = RegExp(
  r'^(Unauthorized|Forbidden|Not found|Bad request|Conflict|Service unavailable|Database error): ',
);
final RegExp _arabicLetter = RegExp('[؀-ۿ]');
