/// Every scannable code the shop has, on one page: the codes section of
/// Settings › Links & QR codes (`features/qr/codes-section.tsx`).
///
/// One [QrKind] list drives one generator. Every kind is always visible; the
/// ones that need a scope say so instead of disappearing. The links page and
/// the menu without prices have their codes here too, the same codes the "QR
/// code" buttons beside their addresses open, so every code lives in one list
/// under one set of output switches ([QrOutputPanel]).
///
/// Each code is LIVE ([qrCodeProvider]): fetched when asked for, and
/// re-rendered whenever an output switch changes. A code belongs to the scope
/// it was made for: switching branches never leaves the previous branch's
/// code on screen, nor mints the new branch's unasked; switching back shows
/// it again.
///
/// Plans: the paid plan has every kind, the links page's only where the page
/// has an address (`public_url`). A Free shop has the menu without prices;
/// the ordering, booking and table codes are shown locked
/// ([PaidFeatureLock], `online`), and nothing behind the lock is fetched.
library;

import 'package:dashboard_api/dashboard_api.dart' show QrResponse;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../links/links_providers.dart' show linksPageProvider;
import 'live_qr_dialog.dart';
import 'qr_output.dart';
import 'qr_output_panel.dart';
import 'qr_providers.dart';
import 'qr_result.dart';
import 'table_codes.dart';

/// The in-mall fields' limits (the web's zod schema).
abstract final class QrInMallLimits {
  static const int place = 80;
  static const int floor = 40;
  static const int unit = 40;
}

/// [kind]'s icon, title and description.
(String, String, String) qrKindWords(
  QrKind kind,
  Translator t,
) => switch (kind) {
  QrKind.orgLinks => ('link-2', t('qr.links.title'), t('qr.links.description')),
  QrKind.orgMenuDisplay => (
    'book-open',
    t('qr.menuDisplay.title'),
    t('qr.menuDisplay.description'),
  ),
  QrKind.orgOrder => ('building-2', t('qr.org.title'), t('qr.org.description')),
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

class QrCodesSection extends ConsumerWidget {
  const QrCodesSection({required this.orgId, super.key});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
    final features = ref.watch(planFeaturesProvider);
    // The links page's code exists only where the page has an address: the
    // shop's own host, which takes custom branding and a slug on top of the
    // plan (the server answers 409 otherwise). The links editor offers its
    // code on the same condition, and so does this list. The read is the
    // editor's own; never on Free.
    final hasAddress =
        planHasFeature(features, 'branding') &&
        qrLinksHasAddress(ref.watch(linksPageProvider(orgId)).value);
    bool held(QrKind k) =>
        (k.feature == null || planHasFeature(features, k.feature!)) &&
        (k != QrKind.orgLinks || hasAddress);
    final online = planHasFeature(features, 'online');
    final locked = [
      for (final k in QrKind.values)
        if (!held(k) && k.feature != 'branding') k,
    ];
    final shopKinds = [
      for (final k in QrKind.values)
        if (k.scope != QrScope.branch && held(k)) k,
    ];
    final branchKinds = [
      for (final k in QrKind.values)
        if (k.scope == QrScope.branch && held(k)) k,
    ];

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

    Widget card(QrKind k) => QrKindCard(
      key: ValueKey('qr-kind-${k.name}'),
      kind: k,
      orgId: orgId,
      branchId: branchId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        QrOutputPanel(orgId: orgId),
        section(t('qr.section.org'), [for (final k in shopKinds) card(k)]),
        if (branchKinds.isNotEmpty)
          section(t('qr.section.branch'), [
            for (final k in branchKinds) card(k),
          ]),
        // Its own section: these are not ONE code but one per table, and a
        // room full of them is printed together rather than made one at a
        // time.
        if (online)
          section(t('qr.section.tables'), [
            QrTableCodes(orgId: orgId, branchId: branchId),
          ]),
        if (locked.isNotEmpty)
          PaidFeatureLock(
            feature: 'online',
            title: t('qr.locked.title'),
            preview: _LockedKinds(kinds: locked),
          ),
      ],
    );
  }
}

/// What a Free shop sees in place of the paid codes: their names, nothing
/// behind them.
class _LockedKinds extends ConsumerWidget {
  const _LockedKinds({required this.kinds});

  final List<QrKind> kinds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    Widget row(String icon, String title) => Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: c.border),
      ),
      child: Row(
        spacing: Space.sm,
        children: [
          DashIcon(icon, size: IconSize.xs, color: c.textPrimary),
          Expanded(
            child: Text(
              title,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
    return Column(
      key: const ValueKey('qr-locked-kinds'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        for (final k in kinds) row(qrKindWords(k, t).$1, qrKindWords(k, t).$2),
        row('qr-code', t('qr.tables.title')),
      ],
    );
  }
}

/// One code's card: icon + title, description, the "why it is unavailable"
/// line, the in-mall fields, Generate, the inline error, the result.
class QrKindCard extends ConsumerStatefulWidget {
  const QrKindCard({
    required this.kind,
    required this.orgId,
    required this.branchId,
    super.key,
  });

  final QrKind kind;
  final String orgId;

  /// The header's branch; null = All branches.
  final String? branchId;

  @override
  ConsumerState<QrKindCard> createState() => _QrKindCardState();
}

class _QrKindCardState extends ConsumerState<QrKindCard> {
  /// The scope the code was asked for in (`requestedFor`).
  String? _requestedFor;

  /// The in-mall fields as typed, and as last submitted.
  final _form = GlobalKey<FormState>();
  String _place = '';
  String _floor = '';
  String _unit = '';
  QrPlace? _submitted;

  final _hold = LiveQrHold<QrResponse>();

  QrKind get _kind => widget.kind;

  bool get _available => switch (_kind.scope) {
    QrScope.shop => true,
    QrScope.org => widget.branchId == null,
    QrScope.branch => widget.branchId != null,
  };

  String get _scopeKey =>
      _kind.scope == QrScope.branch ? (widget.branchId ?? '') : widget.orgId;

  QrCodeRef _code(QrPlace? place) =>
      (kind: _kind, orgId: widget.orgId, scopeId: _scopeKey, place: place);

  QrLiveKey _key(QrPlace? place) => (
    code: _code(place),
    params: qrRenderParams(ref.read(qrOutputProvider(widget.orgId))),
  );

  bool get _requested => _available && _requestedFor == _scopeKey;

  void _generate() {
    if (_requestedFor == _scopeKey) {
      // Asked again: the server draws it again (a Brand edit since).
      ref.invalidate(qrCodeProvider(_key(_submitted)));
    } else {
      setState(() => _requestedFor = _scopeKey);
    }
  }

  void _submitPlace() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final place = (placeName: _place, floor: _floor, unitNumber: _unit);
    if (_requested && place == _submitted) {
      ref.invalidate(qrCodeProvider(_key(place)));
      return;
    }
    setState(() {
      _submitted = place;
      _requestedFor = _scopeKey;
    });
  }

  /// Warms the read the press makes. Never the in-mall card: its GET creates
  /// a permanent short link per place, floor and unit, so a hover would mint
  /// links nobody asked for.
  void _warm() {
    if (_kind == QrKind.branchOrderInMall || !_available) return;
    ref.warm(qrCodeProvider(_key(null)));
  }

  String? _check(String v, int max) {
    final t = ref.read(tProvider);
    if (v.isEmpty) return t('common.requiredField');
    if (v.length > max) return t('common.atMostChars', args: {'n': max});
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final (icon, title, description) = qrKindWords(_kind, t);
    final o = ref.watch(qrOutputProvider(widget.orgId));
    final requested = _requested;
    final live = _hold.view(
      requested
          ? ref.watch(
              qrCodeProvider((
                code: _code(_submitted),
                params: qrRenderParams(o),
              )),
            )
          : null,
    );
    final result = live.data;
    final error = live.error;
    final busy = requested && live.busy;
    final beside = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;
    final inMall = _kind == QrKind.branchOrderInMall;

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        if (!_available)
          Text(
            _kind.scope == QrScope.org
                ? t('qr.needsAllBranches')
                : t('qr.needsBranch'),
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
        if (inMall) _placeForm(),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DashButton(
            key: ValueKey('qr-generate-${_kind.name}'),
            label: t('qr.generate'),
            icon: 'qr-code',
            loading: busy && result == null,
            onPressed: _available && !(busy && result == null)
                ? (inMall ? _submitPlace : _generate)
                : null,
            onIntent: _available && !inMall ? _warm : null,
          ),
        ),
        if (error != null)
          // Inline, not a toast: "bookings are switched off for this
          // branch" is something to go and fix, beside the button that
          // produced it.
          Semantics(
            liveRegion: true,
            child: Text(
              errorMessage(error, t),
              key: ValueKey('qr-error-${_kind.name}'),
              style: DashType.body.copyWith(color: c.errorText),
            ),
          ),
      ],
    );
    final shown = result == null
        ? null
        : QrResultCard(
            key: ValueKey('qr-result-${_kind.name}'),
            qr: result,
            title: title,
            shape: qrShape(o),
            busy: busy,
            onPreview: () => showLiveQrPreview(
              context,
              orgId: widget.orgId,
              title: title,
              watch: qrLiveWatch(_code(_submitted)),
            ),
          );

    return Opacity(
      opacity: _available ? 1 : 0.7,
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

  Widget _placeForm() {
    final t = ref.watch(tProvider);
    final enabled = _available;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final fields = [
      DashTextField(
        key: const ValueKey('qr-place'),
        label: t('qr.inMall.placeName'),
        value: _place,
        enabled: enabled,
        validator: (v) => _check(v, QrInMallLimits.place),
        onChanged: (v) => setState(() => _place = v),
        onSubmitted: (_) => _submitPlace(),
      ),
      DashTextField(
        key: const ValueKey('qr-floor'),
        label: t('qr.inMall.floor'),
        value: _floor,
        enabled: enabled,
        validator: (v) => _check(v, QrInMallLimits.floor),
        onChanged: (v) => setState(() => _floor = v),
        onSubmitted: (_) => _submitPlace(),
      ),
      DashTextField(
        key: const ValueKey('qr-unit'),
        label: t('qr.inMall.unitNumber'),
        value: _unit,
        enabled: enabled,
        validator: (v) => _check(v, QrInMallLimits.unit),
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
