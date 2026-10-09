/// A spreadsheet of people (`dawam/add-employees.tsx` `ImportPeopleDialog`,
/// TEAM-EMP-050…056, 075): read the sheet, show every row and what is wrong
/// with it, then — only when asked — one create per row, one at a time, and
/// say row by row who was added and who wasn't.
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart'
    show Branch, CreateEmployeeRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/attendance_errors.dart';
import 'employees_data.dart';
import 'employees_providers.dart';

/// Opens "Import from a spreadsheet".
Future<void> showImportPeopleDialog(BuildContext context) =>
    showDashDialog<void>(
      context,
      width: DashMetrics.dialogWide,
      builder: (_) => const ImportPeopleDialog(),
    );

/// The rows of an `.xlsx` (first sheet) or `.csv` (`readSheet`). A file that
/// is not a workbook is refused, as ExcelJS refuses it.
Future<List<List<Object?>>> readSheet(PickedFile file, ExportGateway x) async {
  if (file.name.toLowerCase().endsWith('.csv')) {
    // `File.text()`: UTF-8, a leading byte-order mark dropped.
    var text = utf8.decode(file.bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    return readCsv(text);
  }
  if (!looksLikeXlsx(file.bytes)) {
    throw const FormatException('Not a spreadsheet');
  }
  final sheets = await x.readXlsx(file.bytes);
  return sheets.isEmpty ? const [] : sheets.first.rows;
}

typedef _Outcome = ({bool ok, String? message});

class ImportPeopleDialog extends ConsumerStatefulWidget {
  const ImportPeopleDialog({super.key});

  @override
  ConsumerState<ImportPeopleDialog> createState() => _ImportPeopleDialogState();
}

class _ImportPeopleDialogState extends ConsumerState<ImportPeopleDialog> {
  ParsedPeople? _parsed;
  String? _fileName;
  Map<int, _Outcome> _outcomes = const {};
  bool _busy = false;

  Future<void> _pick(List<Branch> branches) async {
    final file = await ref
        .read(fileGatewayProvider)
        .pickFile(extensions: const ['xlsx', 'csv']);
    if (file == null) return;
    try {
      final rows = await readSheet(file, ref.read(exportGatewayProvider));
      if (!mounted) return;
      setState(() {
        _parsed = parsePeople(rows, [
          for (final b in branches) (id: b.id, name: b.name),
        ]);
        _fileName = file.name;
        _outcomes = const {};
      });
    } on Object catch (e) {
      if (!mounted) return;
      final t = ref.read(tProvider);
      DashToast.error(context, attendanceErrorText(e, t, ref.read(formatProvider)));
    }
  }

  /// One at a time: a sheet of 40 people is not worth 40 parallel requests
  /// racing for the same phone-number check.
  Future<void> _run(bool canSetSalary) async {
    final parsed = _parsed;
    if (parsed == null) return;
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final api = ref.read(apiProvider);
    final staff = staffInvalidator(ref);
    setState(() => _busy = true);
    final done = Map<int, _Outcome>.of(_outcomes);
    for (final p in parsed.people) {
      if (done[p.row]?.ok ?? false) continue;
      try {
        // A sheet row is a staff-app person: a name, a number, a branch.
        await api.staff.createEmployee(
          body: CreateEmployeeRequest(
            name: p.name,
            phone: p.phone,
            appAccess: true,
            branchIds: [p.branchId],
            baseSalaryPiastres: canSetSalary ? p.salaryPiastres : null,
          ),
        );
        done[p.row] = (ok: true, message: null);
      } on Object catch (e) {
        done[p.row] = (ok: false, message: attendanceErrorText(e, t, f));
      }
      if (mounted) setState(() => _outcomes = Map.of(done));
    }
    staff.invalidateStaff();
    if (!mounted) return;
    setState(() => _busy = false);
    final added = done.values.where((o) => o.ok).length;
    DashToast.success(
      context,
      t(
        'dawam.importDone',
        args: {'added': added, 'total': parsed.people.length},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    // The server keeps a salary only from someone who may set pay.
    final canSetSalary = ref.watch(
      authzProvider.select((a) => a.canEverywhere(Cap.hrPayrollEdit)),
    );
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final parsed = _parsed;
    final pending = parsed == null
        ? 0
        : parsed.people.where((p) => !(_outcomes[p.row]?.ok ?? false)).length;
    final salariesDropped =
        !canSetSalary &&
        (parsed?.people.any((p) => p.salaryPiastres != null) ?? false);

    return DashSurface(
      title: t('dawam.importTitle'),
      description: t('dawam.importHint'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DashFormField<String>(
            label: t('dawam.importFile'),
            builder: (context, _) => Row(
              spacing: Space.md,
              children: [
                // The browser's file input: its button and the file's name.
                DashButton(
                  label: t('teamEmployees.chooseFile'),
                  icon: 'file-spreadsheet',
                  variant: DashButtonVariant.outline,
                  onPressed: () => _pick(branches),
                ),
                Expanded(
                  child: MadarClippedText(
                    _fileName ?? t('teamEmployees.noFileChosen'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          if (salariesDropped)
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: c.hairline),
                ),
                child: Text(
                  t('dawam.importNoSalaryRight'),
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
              ),
            ),
          if (parsed != null)
            _Preview(
              parsed: parsed,
              outcomes: _outcomes,
              branches: branches,
              showSalary: canSetSalary,
            ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.close'),
          variant: DashButtonVariant.ghost,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          label: t('dawam.importRun', args: {'n': pending}),
          icon: 'upload',
          loading: _busy,
          onPressed: _busy || pending == 0 ? null : () => _run(canSetSalary),
        ),
      ],
    );
  }
}

/// One preview row: a person, or the problem that skips it.
typedef _Row = ({int row, NewPerson? person, RowError? error});

// The preview's column shares.
const int _name = 4, _phone = 4, _branch = 3, _salary = 4, _result = 5;

class _Preview extends ConsumerWidget {
  const _Preview({
    required this.parsed,
    required this.outcomes,
    required this.branches,
    required this.showSalary,
  });

  final ParsedPeople parsed;
  final Map<int, _Outcome> outcomes;
  final List<Branch> branches;
  final bool showSalary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final branchName = {for (final b in branches) b.id: b.name};
    final rows = <_Row>[
      for (final p in parsed.people) (row: p.row, person: p, error: null),
      for (final e in parsed.errors) (row: e.row, person: null, error: e),
    ]..sort((a, b) => a.row.compareTo(b.row));

    String problem(RowError e) =>
        t('dawam.${e.key}', args: {'value': e.value ?? ''});
    String salaryOf(NewPerson p) => !showSalary || p.salaryPiastres == null
        ? '—'
        : f.fmtMoney(p.salaryPiastres);

    Widget result(_Row r) {
      final out = outcomes[r.row];
      if (out != null && out.ok) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            DashIcon('check-circle-2', color: c.success),
            Text(
              t('dawam.importAdded'),
              style: DashType.body.copyWith(color: c.success),
            ),
          ],
        );
      }
      if (out != null) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            DashIcon('circle-alert', color: c.danger),
            Flexible(
              child: Text(
                out.message ?? '',
                style: DashType.body.copyWith(color: c.errorText),
              ),
            ),
          ],
        );
      }
      if (r.error != null) {
        return Text(
          t('dawam.importSkipped'),
          style: DashType.small.copyWith(color: c.textSecondary),
        );
      }
      return const SizedBox.shrink();
    }

    final body = DashType.body.copyWith(color: c.textPrimary);
    final mono = DashType.mono.copyWith(color: c.textPrimary);

    if (DashBreakpoints.isPhone(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          for (final r in rows)
            DashCard(
              key: ValueKey('import-row-${r.row}'),
              padding: const EdgeInsets.all(Space.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.md,
                children: [
                  Text(ltr('${r.row}'), style: mono),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.xs,
                      children: [
                        if (r.person case final p?) ...[
                          Text(p.name, style: DashType.bodyMedium),
                          Text(
                            phoneCell(p.phone),
                            textDirection: TextDirection.ltr,
                            style: mono,
                          ),
                          Text(branchName[p.branchId] ?? '', style: body),
                          Text(salaryOf(p), style: mono),
                        ] else
                          Text(
                            problem(r.error!),
                            style: DashType.body.copyWith(color: c.errorText),
                          ),
                        result(r),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    // The web's table, its problem rows spanning the four middle cells.
    Widget line(List<(int, Widget)> cells, {Key? key}) => Container(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        spacing: Space.md,
        children: [
          for (final (flex, w) in cells)
            flex == 0
                ? SizedBox(width: Space.xl, child: w)
                : Expanded(flex: flex, child: w),
        ],
      ),
    );
    Text head(String s, {bool end = false}) => Text(
      s,
      textAlign: end ? TextAlign.end : TextAlign.start,
      style: DashType.small.copyWith(color: c.textSecondary),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line([
          (0, head('#')),
          (_name, head(t('staff.name'))),
          (_phone, head(t('dawam.whatsapp'))),
          (_branch, head(t('dawam.branch'))),
          (_salary, head(t('dawam.salary'), end: true)),
          (_result, const SizedBox.shrink()),
        ]),
        for (final r in rows)
          line(key: ValueKey('import-row-${r.row}'), [
            (0, Text(ltr('${r.row}'), style: mono)),
            if (r.person case final p?) ...[
              (_name, Text(p.name, style: body)),
              (
                _phone,
                Text(
                  phoneCell(p.phone),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  style: mono,
                ),
              ),
              (_branch, Text(branchName[p.branchId] ?? '', style: body)),
              (
                _salary,
                Text(
                  salaryOf(p),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: mono,
                ),
              ),
            ] else
              (
                _name + _phone + _branch + _salary,
                Text(
                  problem(r.error!),
                  style: DashType.body.copyWith(color: c.errorText),
                ),
              ),
            (_result, result(r)),
          ]),
      ],
    );
  }
}
