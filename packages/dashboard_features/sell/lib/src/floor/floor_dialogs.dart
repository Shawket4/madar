/// The floor's two forms: a new table (`add-table-dialog.tsx`, SELL-FLR-018
/// – 023) and a new or renamed area (`section-dialog.tsx`, SELL-FLR-012 –
/// 015). Errors show after the first Save, then follow the typing (the web's
/// react-hook-form); a failed write keeps the form open with the server's
/// words in a toast.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../orders/error_text.dart';
import '../shared/invalidate.dart';
import 'floor_util.dart';

Future<void> showAddTableDialog(
  BuildContext context, {
  required String branchId,
  required String? sectionId,
  required List<FloorSection> sections,
  required List<FloorTable> tables,
}) => showDashDialog<void>(
  context,
  width: DashMetrics.prose,
  builder: (_) => AddTableDialog(
    branchId: branchId,
    sectionId: sectionId,
    sections: sections,
    tables: tables,
  ),
);

/// Seats as zod's `coerce.number().int().min(0).max(99)` reads them: a
/// blank field is 0.
int? parseSeats(String raw) {
  final s = raw.trim();
  final n = s.isEmpty ? 0 : num.tryParse(s);
  if (n == null || n != n.roundToDouble() || n < 0 || n > 99) return null;
  return n.toInt();
}

class AddTableDialog extends ConsumerStatefulWidget {
  const AddTableDialog({
    required this.branchId,
    required this.sectionId,
    required this.sections,
    required this.tables,
    super.key,
  });

  final String branchId;

  /// The active area chip's section (null for All and Unassigned).
  final String? sectionId;
  final List<FloorSection> sections;

  /// Every table of the branch: the next label and a free spot.
  final List<FloorTable> tables;

  @override
  ConsumerState<AddTableDialog> createState() => _AddTableDialogState();
}

class _AddTableDialogState extends ConsumerState<AddTableDialog> {
  late String _label = suggestLabel(widget.tables.map((t) => t.label));
  String _seats = '2';
  String _shape = 'rect';
  late String? _section = widget.sectionId;
  bool _tried = false;
  bool _busy = false;

  Future<void> _submit() async {
    final seats = parseSeats(_seats);
    if (_label.isEmpty || seats == null) {
      setState(() => _tried = true);
      return;
    }
    if (_busy) return;
    final t = ref.read(tProvider);
    final size = defaultTableSize(_shape);
    final spot = spawnPosition([
      for (final tb in widget.tables)
        if (tb.sectionId == _section) (x: tb.posX, y: tb.posY, h: tb.height),
    ]);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .reservations
          .createFloorTable(
            body: CreateFloorTableRequest(
              branchId: widget.branchId,
              label: _label.trim(),
              seats: seats,
              shape: _shape,
              sectionId: _section,
              posX: spot.x,
              posY: spot.y,
              width: size.w,
              height: size.h,
              rotation: 0,
              explicitNulls: const {'section_id'},
            ),
          );
      bus.invalidate(SellInvalidate.floor);
      if (!mounted) return;
      DashToast.success(context, t('floor.tableCreated'));
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, ordersErrorText(e, t));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return DashSurface(
      title: t('floor.newTable'),
      description: t('floor.tableHint'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.lg,
        children: [
          DashTextField(
            key: const ValueKey('floor-add-label'),
            label: t('floor.tableLabel'),
            placeholder: 'T1',
            value: _label,
            autofocus: true,
            errorText: _tried && _label.isEmpty
                ? t('common.requiredField')
                : null,
            onChanged: (v) => setState(() => _label = v),
            onSubmitted: (_) => _submit(),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(
                child: DashTextField(
                  key: const ValueKey('floor-add-seats'),
                  label: t('floor.seats'),
                  value: _seats,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  errorText: _tried && parseSeats(_seats) == null
                      ? t('floor.errSeats')
                      : null,
                  onChanged: (v) => setState(() => _seats = v),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              Expanded(
                child: DashSelectField<String>(
                  key: const ValueKey('floor-add-shape'),
                  label: t('floor.shape'),
                  value: _shape,
                  options: [
                    DashOption(value: 'rect', label: t('floor.shapeRect')),
                    DashOption(value: 'circle', label: t('floor.shapeCircle')),
                  ],
                  onChanged: (v) => setState(() => _shape = v),
                ),
              ),
            ],
          ),
          DashSelectField<String>(
            key: const ValueKey('floor-add-section'),
            label: t('floor.section'),
            value: _section ?? '',
            options: [
              DashOption(value: '', label: t('floor.noSection')),
              for (final s in widget.sections)
                DashOption(value: s.id, label: s.name),
            ],
            onChanged: (v) => setState(() => _section = v.isEmpty ? null : v),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(
          label: t('floor.addTable'),
          loading: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Create an area ([section] null) or rename one; [onCreated] gets the new
/// area's id.
Future<void> showSectionDialog(
  BuildContext context, {
  required String branchId,
  required FloorSection? section,
  required int nextOrdering,
  required ValueChanged<String> onCreated,
}) => showDashDialog<void>(
  context,
  width: DashMetrics.prose,
  builder: (_) => SectionDialog(
    branchId: branchId,
    section: section,
    nextOrdering: nextOrdering,
    onCreated: onCreated,
  ),
);

class SectionDialog extends ConsumerStatefulWidget {
  const SectionDialog({
    required this.branchId,
    required this.section,
    required this.nextOrdering,
    required this.onCreated,
    super.key,
  });

  final String branchId;
  final FloorSection? section;

  /// A new area goes after the ones already there.
  final int nextOrdering;
  final ValueChanged<String> onCreated;

  @override
  ConsumerState<SectionDialog> createState() => _SectionDialogState();
}

class _SectionDialogState extends ConsumerState<SectionDialog> {
  late String _name = widget.section?.name ?? '';
  bool _tried = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (_name.isEmpty) {
      setState(() => _tried = true);
      return;
    }
    if (_busy) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).reservations;
    final section = widget.section;
    final bus = ref.read(realtimeBusProvider);
    setState(() => _busy = true);
    try {
      if (section != null) {
        await api.updateSection(
          id: section.id,
          body: UpdateSectionRequest(name: _name.trim()),
        );
        if (mounted) DashToast.success(context, t('floor.sectionUpdated'));
      } else {
        final created = await api.createSection(
          body: CreateSectionRequest(
            branchId: widget.branchId,
            name: _name.trim(),
            ordering: widget.nextOrdering,
          ),
        );
        if (mounted) DashToast.success(context, t('floor.sectionCreated'));
        widget.onCreated(created.id);
      }
      bus.invalidate(SellInvalidate.floor);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, ordersErrorText(e, t));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return DashSurface(
      title: t(
        widget.section == null ? 'floor.newSection' : 'floor.sectionSettings',
      ),
      description: t('floor.sectionHint'),
      body: DashTextField(
        key: const ValueKey('floor-section-name'),
        label: t('floor.sectionName'),
        placeholder: t('floor.sectionNamePlaceholder'),
        value: _name,
        autofocus: true,
        errorText: _tried && _name.isEmpty ? t('common.requiredField') : null,
        onChanged: (v) => setState(() => _name = v),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(label: t('common.save'), loading: _busy, onPressed: _submit),
      ],
    );
  }
}
