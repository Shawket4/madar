/// `/settings/qr` QR codes (`features/qr/qr-page.tsx`, SET-QR rows).
///
/// Every scannable code the product makes, on one page: one render-options
/// bar (branded card, DPI) for every org and branch code; the org codes
/// (need "All branches"); the branch codes (need a branch), the in-mall one
/// with its three fields; the per-table sheet ([QrTableCodes]).
///
/// Generated codes live in the page's state only (SET-QR-026), per card.
/// A branch card's code and error are dropped when the header branch moves
/// (the web keeps them, SET-QR-027: a divergence), every card's when the org
/// does.
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane.
library;

import 'package:dashboard_api/dashboard_api.dart' show QrResponse;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'qr_providers.dart';
import 'qr_result.dart';
import 'table_codes.dart';

class QrPage extends ConsumerStatefulWidget {
  const QrPage({super.key});

  /// The in-mall fields' limits (the web's zod schema).
  static const int placeMax = 80;
  static const int floorMax = 40;
  static const int unitMax = 40;

  /// The DPI choices; 600 is the default.
  static const List<int> dpis = [150, 300, 600];

  @override
  ConsumerState<QrPage> createState() => _QrPageState();
}

class _QrPageState extends ConsumerState<QrPage> {
  bool _card = true;
  int _dpi = 600;
  final Map<QrKind, QrResponse> _results = {};
  final Map<QrKind, String> _errors = {};
  QrKind? _busy;

  final _form = GlobalKey<FormState>();
  String _place = '';
  String _floor = '';
  String _unit = '';

  String? _check(String v, int max) {
    final t = ref.read(tProvider);
    if (v.isEmpty) return t('common.requiredField');
    if (v.length > max) return t('common.atMostChars', args: {'n': max});
    return null;
  }

  bool get _placeValid =>
      _check(_place, QrPage.placeMax) == null &&
      _check(_floor, QrPage.floorMax) == null &&
      _check(_unit, QrPage.unitMax) == null;

  /// The read [kind] makes now, or null when the scope cannot make it.
  QrKey? _keyFor(QrKind kind) {
    final orgId = ref.read(orgIdProvider);
    final branchId = ref.read(scopeProvider.select((s) => s.branchId));
    final id = kind.org ? orgId : branchId;
    if (orgId == null || id == null) return null;
    return (
      kind: kind,
      id: id,
      card: _card,
      dpi: _dpi,
      place: kind == QrKind.branchOrderInMall
          ? (placeName: _place, floor: _floor, unitNumber: _unit)
          : null,
    );
  }

  Future<void> _generate(QrKind kind) async {
    final key = _keyFor(kind);
    if (key == null) return;
    final t = ref.read(tProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final read = qrCodeProvider(key);
    setState(() {
      _busy = kind;
      _results.remove(kind);
      _errors.remove(kind);
    });
    try {
      final qr = await container.read(read.future);
      // The scope moved while it was being made: not this scope's code.
      if (mounted && _keyFor(kind)?.id == key.id) {
        setState(() => _results[kind] = qr);
      }
    } on Object catch (e) {
      container.invalidate(read);
      // Inline, not a toast: "bookings are switched off" is something to go
      // and fix, and it belongs beside the button that produced it.
      if (mounted && _keyFor(kind)?.id == key.id) {
        setState(() => _errors[kind] = errorMessage(e, t));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _submitPlace() {
    if (_form.currentState?.validate() ?? false) {
      _generate(QrKind.branchOrderInMall);
    }
  }

  void _warm(QrKind kind) {
    if (kind == QrKind.branchOrderInMall && !_placeValid) return;
    final key = _keyFor(kind);
    if (key != null) ref.warm(qrCodeProvider(key));
  }

  /// No setState: the scope it follows is watched, so build runs next.
  void _drop(bool Function(QrKind k) which) {
    _results.removeWhere((k, _) => which(k));
    _errors.removeWhere((k, _) => which(k));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
    ref
      ..listen(orgIdProvider, (_, _) => _drop((_) => true))
      ..listen(
        scopeProvider.select((s) => s.branchId),
        (_, _) => _drop((k) => !k.org),
      );

    if (orgId == null) {
      return DashPageScaffold(
        title: t('qr.title'),
        body: DashEmptyState(icon: 'qr-code', title: t('branches.pickOrg')),
      );
    }

    Widget section(String title, List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSectionHeader(title: title),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: children,
        ),
      ],
    );

    Widget kind(QrKind k) => _KindCard(
      key: ValueKey('qr-kind-${k.name}'),
      kind: k,
      available: k.org ? branchId == null : branchId != null,
      busy: _busy == k,
      result: _results[k],
      error: _errors[k],
      onGenerate: k == QrKind.branchOrderInMall
          ? _submitPlace
          : () => _generate(k),
      onIntent: () => _warm(k),
      form: k == QrKind.branchOrderInMall ? _placeForm(branchId != null) : null,
    );

    return DashPageScaffold(
      title: t('qr.title'),
      subtitle: t('qr.subtitle'),
      width: DashPageWidth.reading,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          _OptionsBar(
            card: _card,
            dpi: _dpi,
            onCard: (v) => setState(() => _card = v),
            onDpi: (v) => setState(() => _dpi = v),
          ),
          section(t('qr.section.org'), [
            for (final k in QrKind.values)
              if (k.org) kind(k),
          ]),
          section(t('qr.section.branch'), [
            for (final k in QrKind.values)
              if (!k.org) kind(k),
          ]),
          section(t('qr.section.tables'), [QrTableCodes(branchId: branchId)]),
        ],
      ),
    );
  }

  Widget _placeForm(bool enabled) {
    final t = ref.watch(tProvider);
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final fields = [
      DashTextField(
        key: const ValueKey('qr-place'),
        label: t('qr.inMall.placeName'),
        value: _place,
        enabled: enabled,
        validator: (v) => _check(v, QrPage.placeMax),
        onChanged: (v) => setState(() => _place = v),
        onSubmitted: (_) => _submitPlace(),
      ),
      DashTextField(
        key: const ValueKey('qr-floor'),
        label: t('qr.inMall.floor'),
        value: _floor,
        enabled: enabled,
        validator: (v) => _check(v, QrPage.floorMax),
        onChanged: (v) => setState(() => _floor = v),
        onSubmitted: (_) => _submitPlace(),
      ),
      DashTextField(
        key: const ValueKey('qr-unit'),
        label: t('qr.inMall.unitNumber'),
        value: _unit,
        enabled: enabled,
        validator: (v) => _check(v, QrPage.unitMax),
        onChanged: (v) => setState(() => _unit = v),
        onSubmitted: (_) => _submitPlace(),
      ),
    ];
    return Form(
      key: _form,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [for (final f in fields) Expanded(child: f)],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: fields,
            ),
    );
  }
}

/// "Branded card" + "DPI" (only for a card) + "Applies to every code on
/// this page." (SET-QR-003).
class _OptionsBar extends ConsumerWidget {
  const _OptionsBar({
    required this.card,
    required this.dpi,
    required this.onCard,
    required this.onDpi,
  });

  final bool card;
  final int dpi;
  final ValueChanged<bool> onCard;
  final ValueChanged<int> onDpi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Container(
      key: const ValueKey('qr-options'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Wrap(
        spacing: Space.xl,
        runSpacing: Space.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              DashSwitch(
                key: const ValueKey('qr-card'),
                value: card,
                onChanged: onCard,
                semanticLabel: t('qr.opts.brandedCard'),
              ),
              ExcludeSemantics(
                child: GestureDetector(
                  onTap: () => onCard(!card),
                  child: Text(
                    t('qr.opts.brandedCard'),
                    style: DashType.body.copyWith(color: c.textPrimary),
                  ),
                ),
              ),
            ],
          ),
          if (card)
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.sm,
              children: [
                Text(
                  t('qr.opts.dpiLabel'),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
                DashSelect<int>(
                  key: const ValueKey('qr-dpi'),
                  options: [
                    for (final d in QrPage.dpis)
                      DashOption(value: d, label: '$d'),
                  ],
                  value: dpi,
                  onChanged: onDpi,
                  semanticLabel: t('qr.opts.dpiLabel'),
                  width: Space.xxl * 2.5, // the web's w-20
                  expand: false,
                ),
              ],
            ),
          Text(
            t('qr.opts.hint'),
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// One code's card: icon + title, description, the "why it is unavailable"
/// line, the in-mall fields, Generate, the inline error, the result.
class _KindCard extends ConsumerWidget {
  const _KindCard({
    required this.kind,
    required this.available,
    required this.busy,
    required this.result,
    required this.error,
    required this.onGenerate,
    required this.onIntent,
    this.form,
    super.key,
  });

  final QrKind kind;
  final bool available;
  final bool busy;
  final QrResponse? result;
  final String? error;
  final VoidCallback onGenerate;
  final VoidCallback onIntent;
  final Widget? form;

  static (String, String, String) words(QrKind k, Translator t) => switch (k) {
    QrKind.orgOrder => (
      'building-2',
      t('qr.org.title'),
      t('qr.org.description'),
    ),
    QrKind.orgBooking => (
      'calendar-check',
      t('qr.orgBooking.title'),
      t('qr.orgBooking.description'),
    ),
    QrKind.branchOrder => (
      'store',
      t('qr.standard.title'),
      t('qr.standard.description'),
    ),
    QrKind.branchBooking => (
      'calendar-check',
      t('qr.branchBooking.title'),
      t('qr.branchBooking.description'),
    ),
    QrKind.branchOrderInMall => (
      'utensils-crossed',
      t('qr.inMall.title'),
      t('qr.inMall.description'),
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final (icon, title, description) = words(kind, t);
    final beside = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        if (!available)
          Text(
            kind.org ? t('qr.needsAllBranches') : t('qr.needsBranch'),
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
        ?form,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DashButton(
            key: ValueKey('qr-generate-${kind.name}'),
            label: t('qr.generate'),
            icon: 'qr-code',
            loading: busy,
            onPressed: available && !busy ? onGenerate : null,
            onIntent: available ? onIntent : null,
          ),
        ),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              key: ValueKey('qr-error-${kind.name}'),
              style: DashType.body.copyWith(color: c.errorText),
            ),
          ),
      ],
    );
    final shown = result == null
        ? null
        : QrResultCard(
            key: ValueKey('qr-result-${kind.name}'),
            qr: result!,
            title: title,
          );

    return Opacity(
      opacity: available ? 1 : 0.7,
      child: DashCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.xl,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xs + DashMetrics.hair,
              children: [
                Row(
                  spacing: Space.sm,
                  children: [
                    DashIcon(icon, size: IconSize.xs, color: c.textPrimary),
                    Expanded(
                      child: Text(
                        title,
                        style: DashType.sectionTitle.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  description,
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
              ],
            ),
            if (shown != null && beside)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.lg,
                children: [
                  Expanded(child: controls),
                  SizedBox(width: Space.xxl * 8, child: shown),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.lg,
                children: [controls, ?shown],
              ),
          ],
        ),
      ),
    );
  }
}
