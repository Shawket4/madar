/// "Already on Foodics?" (web `features/menu-import`), the menu import page's
/// card: import the whole menu from the Foodics console's exports, or replace
/// the menu there is with them. The files are read on this device by madar-shared's
/// reader (the bridge, `rules.foodicsParse`); only the menu it builds goes to
/// `POST /menu/bulk`, which runs the same checks. The server answers a dry run
/// before anything is written, and a replace waits for the typed sentence.
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, BulkArchived, BulkMenuRequest, BulkMenuResponse;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

import '../shared/menu_queries.dart';

/// The most one export may weigh (madar-menu `MAX_FILE_BYTES`).
const int _maxFileBytes = 5 * 1024 * 1024;

/// A longer warning list is read in the export, not here.
const int _warningsShown = 50;

/// The Foodics exports, in the order the owner downloads them.
const List<String> _exports = [
  'categories',
  'products',
  'modifier_groups',
  'modifier_options',
  'product_modifiers',
];

typedef _Json = Map<String, Object?>;

/// The card: shown only to someone who holds what the server will ask for.
class FoodicsImportCard extends ConsumerWidget {
  const FoodicsImportCard({
    required this.orgId,
    required this.categories,
    required this.items,
    super.key,
  });

  final String orgId;

  /// What the menu holds: an empty menu adds, any other replaces.
  final int categories;
  final int items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final caps = ref.watch(
      authzProvider.select(
        (a) => (
          add:
              a.can(Cap.menuCategoriesCreate) &&
              a.can(Cap.menuItemsCreate) &&
              a.can(Cap.menuItemsEdit),
          remove: a.can(Cap.menuCategoriesDelete) && a.can(Cap.menuItemsDelete),
        ),
      ),
    );
    final replace = categories + items > 0;
    if (!caps.add || (replace && !caps.remove)) return const SizedBox.shrink();

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.xs,
      children: [
        Text(t('menuImport.cardTitle'), style: DashType.bodyStrong),
        Text(
          replace ? t('menuImport.cardReplace') : t('menuImport.cardAdd'),
          style: DashType.small.copyWith(color: c.textSecondary),
        ),
      ],
    );
    final button = DashButton(
      label: replace ? t('menuImport.cardReplaceCta') : t('menuImport.cardCta'),
      variant: DashButtonVariant.outline,
      onPressed: () async {
        // The Setup page's readiness reads the menu too.
        final bus = ref.read(realtimeBusProvider);
        await showDashDialog<void>(
          context,
          width: DashMetrics.dialogWide,
          builder: (_) => FoodicsImportDialog(
            orgId: orgId,
            replace: replace,
            canReplace: caps.remove,
          ),
        );
        bus.invalidate(['/orgs/$orgId/readiness']);
      },
    );
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.hairline),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final icon = DashIcon('file-spreadsheet', color: c.accent);
          if (box.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                Align(alignment: AlignmentDirectional.centerStart, child: icon),
                text,
                button,
              ],
            );
          }
          return Row(
            spacing: Space.md,
            children: [
              icon,
              Expanded(child: text),
              button,
            ],
          );
        },
      ),
    );
  }
}

sealed class _Check {
  const _Check();
}

class _Checking extends _Check {
  const _Checking();
}

class _Ready extends _Check {
  const _Ready(this.answer);
  final BulkMenuResponse answer;
}

class _Refused extends _Check {
  const _Refused(this.message, {required this.notEmpty});
  final String message;
  final bool notEmpty;
}

class FoodicsImportDialog extends ConsumerStatefulWidget {
  const FoodicsImportDialog({
    required this.orgId,
    required this.replace,
    required this.canReplace,
    super.key,
  });

  final String orgId;

  /// What the owner asked for: replace the menu (else add into an empty one).
  final bool replace;

  /// May the person replace (delete categories and items)?
  final bool canReplace;

  @override
  ConsumerState<FoodicsImportDialog> createState() =>
      _FoodicsImportDialogState();
}

class _FoodicsImportDialogState extends ConsumerState<FoodicsImportDialog> {
  late bool _replace = widget.replace;

  /// The reader's answer (`FoodicsParsed`): `menu`, `files`, `warnings`.
  _Json? _parsed;
  List<String> _names = const [];

  /// The same checks the server runs (`BulkSummary` or `BulkRefusal`).
  _Json? _refusal;
  String? _readError;
  bool _reading = false;
  _Check _check = const _Checking();
  String _typed = '';
  bool _writing = false;

  /// Drops a dry run answered after newer files or another mode.
  int _asked = 0;

  _Json get _menu => _parsed!['menu']! as _Json;

  Future<void> _pick() async {
    final t = ref.read(tProvider);
    final files = await ref
        .read(fileGatewayProvider)
        .pickFiles(extensions: const ['csv']);
    if (files.isEmpty || !mounted) return;
    final big = files.where((f) => f.bytes.length > _maxFileBytes).firstOrNull;
    if (big != null) {
      setState(() {
        _parsed = null;
        _readError = t('menuImport.errors.tooBig', args: {'name': big.name});
      });
      return;
    }
    setState(() => _reading = true);
    // `File.text()`: UTF-8; the reader drops a byte-order mark itself.
    final texts = [
      for (final f in files) utf8.decode(f.bytes, allowMalformed: true),
    ];
    final answer = jsonDecode(await rules.foodicsParse(files: texts)) as _Json;
    if (!mounted) return;
    final err = answer['Err'];
    if (err is _Json) {
      setState(() {
        _reading = false;
        _parsed = null;
        _readError = _fileError(err, files, t);
      });
      return;
    }
    final parsed = answer['Ok']! as _Json;
    final verdict =
        jsonDecode(rules.bulkValidate(menuJson: jsonEncode(parsed['menu'])))
            as _Json;
    setState(() {
      _reading = false;
      _readError = null;
      _parsed = parsed;
      _names = [for (final f in files) f.name];
      _refusal = verdict['Err'] as _Json?;
      _typed = '';
    });
    if (_refusal == null) _dryRun();
  }

  /// The server's verdict, nothing kept.
  Future<void> _dryRun() async {
    final asked = ++_asked;
    setState(() => _check = const _Checking());
    try {
      final answer = await ref
          .read(apiProvider)
          .menu
          .bulkMenu(dryRun: true, body: _body());
      if (mounted && asked == _asked) setState(() => _check = _Ready(answer));
    } on Object catch (e) {
      if (!mounted || asked != _asked) return;
      setState(
        () => _check = _Refused(
          _serverMessage(e),
          notEmpty: e is ApiException && e.code == 'MENU_NOT_EMPTY',
        ),
      );
    }
  }

  BulkMenuRequest _body([String? confirm]) => BulkMenuRequest.fromJson({
    'menu': _menu,
    'mode': _replace ? 'replace' : 'add',
    'confirm': ?confirm,
  });

  Future<void> _write() async {
    final t = ref.read(tProvider);
    final invalidate = ref.menuInvalidate;
    setState(() => _writing = true);
    try {
      final answer = await ref
          .read(apiProvider)
          .menu
          .bulkMenu(body: _body(_replace ? _typed : null));
      invalidate.catalog();
      if (!mounted) return;
      DashToast.success(
        context,
        t('menuImport.done', args: {'count': answer.summary.items}),
      );
      Navigator.of(context).maybePop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _writing = false);
      DashToast.error(context, _serverMessage(e));
    }
  }

  /// A refusal the shared checks name, in the person's language.
  String _serverMessage(Object e) {
    final t = ref.read(tProvider);
    if (e is ApiException && (e.code?.startsWith('BULK_MENU_') ?? false)) {
      final vars = (e.details as Map?)?['vars'];
      if (vars is _Json && vars['refusal'] != null) {
        return _refusalMessage(vars, t);
      }
    }
    return errorMessage(e, t);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final orgName = ref.watch(currentOrgProvider).value?.name ?? '';
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    final sentence = rules.replaceSentence(
      orgName: orgName,
      lang: arabic ? 'ar' : 'en',
    );
    final confirmed = rules.confirmsReplace(orgName: orgName, typed: _typed);
    final ready =
        _parsed != null && _refusal == null && _check is _Ready && !_writing;

    return DashSurface(
      title: _replace ? t('menuImport.replaceTitle') : t('menuImport.title'),
      description: t('menuImport.hint'),
      wrapActions: true,
      body: _parsed == null
          ? _PickStep(reading: _reading, error: _readError, onPick: _pick)
          : _Preview(
              parsed: _parsed!,
              names: _names,
              refusal: _refusal,
              check: _check,
              replace: _replace,
              canReplace: widget.canReplace,
              onReplace: () {
                setState(() => _replace = true);
                _dryRun();
              },
              onOther: _writing ? null : () => setState(() => _parsed = null),
              arabic: arabic,
              confirm: _replace && _check is _Ready
                  ? _Confirm(
                      archived: (_check as _Ready).answer.archived,
                      sentence: sentence,
                      typed: _typed,
                      ok: confirmed,
                      onChanged: (v) => setState(() => _typed = v),
                    )
                  : null,
            ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        if (_parsed != null)
          _replace
              ? DashButton(
                  label: t('menuImport.replace.run'),
                  variant: DashButtonVariant.destructive,
                  loading: _writing,
                  onPressed: ready && confirmed ? _write : null,
                )
              : DashButton(
                  label: t('menuImport.run'),
                  icon: 'upload',
                  loading: _writing,
                  onPressed: ready ? _write : null,
                ),
      ],
    );
  }
}

String _fileLabel(Object? kind, Translator t) =>
    t('menuImport.files.$kind', defaultValue: '$kind');

String _fileError(_Json e, List<PickedFile> files, Translator t) {
  String name(Object? i) => i is int && i < files.length ? files[i].name : '';
  return switch (e['error']) {
    'unknown_file' => t(
      'menuImport.errors.unknownFile',
      args: {'name': name(e['index'])},
    ),
    'duplicate_file' => t(
      'menuImport.errors.duplicateFile',
      args: {'file': _fileLabel(e['kind'], t)},
    ),
    'missing_products' => t('menuImport.errors.missingProducts'),
    'too_big' => t(
      'menuImport.errors.tooBig',
      args: {'name': name(e['index'])},
    ),
    _ => t(
      'menuImport.errors.badCsv',
      args: {'file': _fileLabel(e['kind'], t), 'line': e['line'] ?? ''},
    ),
  };
}

/// One warning the reader gave, as a sentence (`menuImport.issues.*`).
String _warningMessage(_Json w, Translator t) {
  final issue = w['issue']! as _Json;
  final args = <String, Object?>{...issue};
  if (issue['issue'] == 'missing_file') {
    args['file'] = _fileLabel(issue['kind'], t);
  }
  if (issue['value'] case final String v when v.isEmpty) args['value'] = '—';
  return t('menuImport.issues.${issue['issue']}', args: args);
}

/// Why the server (or the same checks here) refuses a menu
/// (`menuImport.refusals.*`).
String _refusalMessage(_Json r, Translator t) {
  final args = <String, Object?>{...r};
  if (r['what'] != null) args['what'] = t('menuImport.things.${r['what']}');
  return t('menuImport.refusals.${r['refusal']}', args: args);
}

class _PickStep extends ConsumerWidget {
  const _PickStep({
    required this.reading,
    required this.error,
    required this.onPick,
  });

  final bool reading;
  final String? error;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final steps = [
      t('menuImport.how1'),
      t('menuImport.how2'),
      t('menuImport.how3'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Text(t('menuImport.howTitle'), style: DashType.bodyMedium),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.xs,
          children: [
            for (final (i, s) in steps.indexed)
              Text(
                '${i + 1}. $s',
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
          ],
        ),
        Semantics(
          label: t('menuImport.filesLabel'),
          child: Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final f in _exports)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.xs,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Text(_fileLabel(f, t), style: DashType.small),
                ),
            ],
          ),
        ),
        DashFormField<void>(
          label: t('menuImport.choose'),
          builder: (context, _) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashButton(
              label: t('menuImport.chooseFiles'),
              icon: 'file-spreadsheet',
              variant: DashButtonVariant.outline,
              loading: reading,
              onPressed: reading ? null : onPick,
            ),
          ),
        ),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: _Line(
              icon: 'triangle-alert',
              tone: DashTone.danger,
              text: error!,
            ),
          ),
      ],
    );
  }
}

/// A sentence with its glyph, in a tone's text colour.
class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.tone, required this.text});

  final String icon;
  final DashTone tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final fg = tone.foreground(context.madarColors);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        DashIcon(icon, size: IconSize.sm, color: fg),
        Expanded(
          child: Text(text, style: DashType.body.copyWith(color: fg)),
        ),
      ],
    );
  }
}

class _Preview extends ConsumerWidget {
  const _Preview({
    required this.parsed,
    required this.names,
    required this.refusal,
    required this.check,
    required this.replace,
    required this.canReplace,
    required this.onReplace,
    required this.onOther,
    required this.arabic,
    required this.confirm,
  });

  final _Json parsed;
  final List<String> names;
  final _Json? refusal;
  final _Check check;
  final bool replace;
  final bool canReplace;
  final VoidCallback onReplace;
  final VoidCallback? onOther;
  final bool arabic;
  final Widget? confirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    List<_Json> list(_Json m, String k) =>
        ((m[k] as List?) ?? const []).cast<_Json>();
    final menu = parsed['menu']! as _Json;
    final items = list(menu, 'items');
    final groups = list(menu, 'groups');
    final warnings = list(parsed, 'warnings');
    final kinds = (parsed['files']! as List).cast<String>();
    final counts = <(String, int)>[
      (t('menuImport.count.categories'), list(menu, 'categories').length),
      (t('menuImport.count.items'), items.length),
      (
        t('menuImport.count.sizes'),
        items.fold(0, (n, i) => n + list(i, 'sizes').length),
      ),
      (t('menuImport.count.groups'), groups.length),
      (
        t('menuImport.count.options'),
        groups.fold(0, (n, g) => n + list(g, 'options').length),
      ),
    ];

    Widget verdict() {
      final r = refusal;
      if (r != null) {
        return _Line(
          icon: 'triangle-alert',
          tone: DashTone.danger,
          text: _refusalMessage(r, t),
        );
      }
      return switch (check) {
        _Checking() => Text(
          t('menuImport.checking'),
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
        _Ready() => _Line(
          icon: 'check-circle-2',
          tone: DashTone.success,
          text: t('menuImport.ready'),
        ),
        _Refused(:final message, :final notEmpty) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.sm,
          children: [
            _Line(icon: 'triangle-alert', tone: DashTone.danger, text: message),
            if (notEmpty && !replace && canReplace)
              DashButton(
                label: t('menuImport.switchToReplace'),
                variant: DashButtonVariant.outline,
                size: DashButtonSize.compact,
                onPressed: onReplace,
              ),
          ],
        ),
      };
    }

    final byCategory = [
      for (final cat in list(menu, 'categories'))
        (
          name: cat['name']! as String,
          items: [
            for (final i in items)
              if (i['category'] == cat['key']) i,
          ],
        ),
    ].where((x) => x.items.isNotEmpty);

    String priceOf(_Json item) {
      final sizes = list(item, 'sizes');
      if (sizes.isEmpty) return f.fmtMoney(item['price']! as num);
      return [
        for (final s in sizes)
          '${s['label']} ${f.fmtMoney(s['price']! as num)}',
      ].join(' · ');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth < 520 ? 3 : 5;
            final w = (box.maxWidth - Space.sm * (cols - 1)) / cols;
            return Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final (label, n) in counts)
                  Container(
                    width: w,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.sm,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: c.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MadarClippedText(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                        Text('$n', style: DashType.sectionTitle),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.xs,
          children: [
            // The kind, then the file's own name; a long pair wraps.
            for (final (i, kind) in kinds.indexed)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.sm,
                children: [
                  DashIcon(
                    'file-spreadsheet',
                    size: IconSize.sm,
                    color: c.textSecondary,
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: _fileLabel(kind, t),
                            style: DashType.bodyMedium,
                          ),
                          TextSpan(
                            text: '  ${i < names.length ? names[i] : ''}',
                            style: DashType.body.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            if (onOther != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: DashButton(
                  label: t('menuImport.other'),
                  variant: DashButtonVariant.ghost,
                  size: DashButtonSize.compact,
                  onPressed: onOther,
                ),
              ),
          ],
        ),
        Semantics(liveRegion: true, child: verdict()),
        ?confirm,
        if (warnings.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              Text(
                t('menuImport.warnings', args: {'count': warnings.length}),
                style: DashType.bodyMedium,
              ),
              for (final w in warnings.take(_warningsShown))
                _Line(
                  icon: 'triangle-alert',
                  tone: DashTone.warning,
                  text: [_warningMessage(w, t), ?_place(w, t)].join(' · '),
                ),
              if (warnings.length > _warningsShown)
                Text(
                  t(
                    'menuImport.moreWarnings',
                    args: {'count': warnings.length - _warningsShown},
                  ),
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
            ],
          ),
        Text(t('menuImport.preview'), style: DashType.bodyMedium),
        for (final cat in byCategory)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.xs,
            children: [
              Text(cat.name, style: DashType.bodyStrong),
              for (final item in cat.items)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.md,
                  children: [
                    Expanded(
                      child: Text(
                        _itemName(item, arabic),
                        style: DashType.body.copyWith(
                          color: item['is_active'] == false
                              ? c.textSecondary
                              : null,
                          decoration: item['is_active'] == false
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    Text(
                      priceOf(item),
                      style: DashType.body.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

/// The reader's language first, the other name after it.
String _itemName(_Json item, bool arabic) {
  final en = item['name']! as String;
  final ar = item['name_ar'] as String?;
  if (ar == null || ar.isEmpty) return en;
  return arabic ? '$ar · $en' : '$en · $ar';
}

/// Where a warning points: the file and the line, when it has them.
String? _place(_Json w, Translator t) {
  final file = w['file'];
  if (file == null) return null;
  final line = w['line'];
  return line == null
      ? _fileLabel(file, t)
      : t(
          'menuImport.place',
          args: {'file': _fileLabel(file, t), 'line': line},
        );
}

/// The replace confirmation: what is put away, and the sentence to type.
class _Confirm extends ConsumerWidget {
  const _Confirm({
    required this.archived,
    required this.sentence,
    required this.typed,
    required this.ok,
    required this.onChanged,
  });

  final BulkArchived? archived;
  final String sentence;
  final String typed;
  final bool ok;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          Text(
            t(
              'menuImport.replace.warn',
              args: {
                'categories': archived?.categories ?? 0,
                'items': archived?.items ?? 0,
              },
            ),
            style: DashType.body,
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${t('menuImport.replace.type')} '),
                TextSpan(
                  text: sentence,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            key: const ValueKey('replace-sentence'),
            style: DashType.bodyMedium,
          ),
          DashTextField(
            value: typed,
            onChanged: onChanged,
            placeholder: sentence,
            errorText: typed.isNotEmpty && !ok
                ? t('menuImport.replace.mismatch')
                : null,
          ),
        ],
      ),
    );
  }
}
