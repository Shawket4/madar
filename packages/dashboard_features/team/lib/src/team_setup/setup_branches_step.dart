/// Set-up step 1, "Where is each branch?" (`dawam/setup-steps.tsx`
/// `BranchesStep` / `BranchPin`, TEAM-SET-013…023): one expandable row per
/// branch, open one at a time, the first unpinned one open to start. A pin
/// comes from the device's location or a pasted Maps link, with a radius
/// around it, and saves with the branch's own `PATCH /branches/{id}`.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show linkOpenerProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'geo.dart';
import 'setup_location.dart';

/// The radius a branch starts with (`DEFAULT_RADIUS`).
const int defaultPinRadius = 200;

/// The radius field's width cap (the web's `max-w-xs`).
const double _radiusFieldWidth = 320;

/// A branch a phone can be checked against: a pin and a radius
/// (`branchPinned`).
bool isBranchPinned(Branch b) =>
    b.latitude != null && b.longitude != null && (b.geoRadiusMeters ?? 0) > 0;

class SetupBranchesStep extends ConsumerStatefulWidget {
  const SetupBranchesStep({
    required this.branches,
    required this.canEdit,
    super.key,
  });

  final List<Branch> branches;

  /// `branches.edit`: without it every pin control is disabled.
  final bool canEdit;

  @override
  ConsumerState<SetupBranchesStep> createState() => _SetupBranchesStepState();
}

class _SetupBranchesStepState extends ConsumerState<SetupBranchesStep> {
  // `useState(firstOpen)`: the first unpinned branch, chosen once.
  late String? _open = widget.branches
      .where((b) => !isBranchPinned(b))
      .map((b) => b.id)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final branches = widget.branches;
    if (branches.isEmpty) {
      return DashEmptyState(
        key: const ValueKey('setup-no-branches'),
        icon: 'map-pin',
        title: t('dawam.setupNoBranches'),
        description: t('dawam.setupNoBranchesHint'),
        framed: false,
        action: DashButton(
          label: t('dawam.setupAddBranch'),
          icon: 'plus',
          // The admin Branches page opens its new-branch editor from this.
          onPressed: () => context.go('/branches?edit=new'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        if (!widget.canEdit)
          Semantics(
            container: true,
            key: const ValueKey('setup-pin-no-access'),
            child: Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.sm,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: DashMetrics.hair),
                    child: DashIcon('triangle-alert', color: c.textPrimary),
                  ),
                  Expanded(
                    child: Text(
                      t('dawam.setupPinNoAccess'),
                      style: DashType.body.copyWith(color: c.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (final b in branches)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.xs),
              border: Border.all(color: c.hairline),
            ),
            child: _BranchPin(
              key: ValueKey('setup-pin-${b.id}'),
              branch: b,
              canEdit: widget.canEdit,
              open: _open == b.id,
              onToggle: () =>
                  setState(() => _open = _open == b.id ? null : b.id),
              onSaved: () => setState(
                () => _open = branches
                    .where((x) => x.id != b.id && !isBranchPinned(x))
                    .map((x) => x.id)
                    .firstOrNull,
              ),
            ),
          ),
      ],
    );
  }
}

/// Where "Use my location" stands.
sealed class _Locating {
  const _Locating();
}

class _Idle extends _Locating {
  const _Idle();
}

class _Busy extends _Locating {
  const _Busy();
}

class _Failed extends _Locating {
  const _Failed(this.failure);
  final LocationFailure failure;
}

class _Done extends _Locating {
  const _Done(this.accuracy);

  /// Metres, rounded.
  final int accuracy;
}

class _BranchPin extends ConsumerStatefulWidget {
  const _BranchPin({
    required this.branch,
    required this.canEdit,
    required this.open,
    required this.onToggle,
    required this.onSaved,
    super.key,
  });

  final Branch branch;
  final bool canEdit;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onSaved;

  @override
  ConsumerState<_BranchPin> createState() => _BranchPinState();
}

class _BranchPinState extends ConsumerState<_BranchPin> {
  LatLng? get _saved {
    final b = widget.branch;
    return b.latitude != null && b.longitude != null
        ? LatLng(b.latitude!, b.longitude!)
        : null;
  }

  // Seeded once from the branch, as the web's `useState(saved)`.
  late LatLng? _pin = _saved;
  late double? _radius = (widget.branch.geoRadiusMeters ?? 0) > 0
      ? widget.branch.geoRadiusMeters!.toDouble()
      : defaultPinRadius.toDouble();
  String _paste = '';
  _Locating _locating = const _Idle();
  bool _busy = false;

  PinParse? get _pasted => _paste.trim().isEmpty ? null : parsePin(_paste);

  String? _pasteError(Translator t) => switch (_pasted?.problem) {
    null => null,
    PinProblem.shortLink => t('dawam.pinShortLink'),
    PinProblem.outOfRange => t('dawam.pinOutOfRange'),
    PinProblem.none => t('dawam.pinNone'),
  };

  void _onPaste(String text) {
    setState(() {
      _paste = text;
      final r = text.trim().isEmpty ? null : parsePin(text);
      if (r != null && r.ok) _pin = r.pin;
    });
  }

  Future<void> _locate() async {
    setState(() => _locating = const _Busy());
    final r = await ref
        .read(setupLocatorProvider)
        .locate(timeout: locateTimeout);
    if (!mounted) return;
    setState(() {
      final at = r.at;
      if (at != null) {
        _pin = LatLng(round6(at.lat), round6(at.lng));
        _locating = _Done((r.accuracyMeters ?? 0).round());
      } else {
        _locating = _Failed(r.failure ?? LocationFailure.unavailable);
      }
    });
  }

  bool get _changed {
    final saved = _saved;
    final pin = _pin;
    return saved == null ||
        pin == null ||
        pin.lat != saved.lat ||
        pin.lng != saved.lng ||
        _radius != widget.branch.geoRadiusMeters?.toDouble();
  }

  bool get _radiusOk {
    final r = _radius;
    return r != null && r.isFinite && r >= 10 && r <= 5000;
  }

  bool get _canSave => widget.canEdit && _pin != null && _radiusOk && _changed;

  Future<void> _save() async {
    final pin = _pin;
    final radius = _radius;
    if (pin == null || !_radiusOk || radius == null) return;
    final t = ref.read(tProvider);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .branches
          .patchBranch(
            id: widget.branch.id,
            body: UpdateBranchRequest(
              latitude: pin.lat,
              longitude: pin.lng,
              geoRadiusMeters: radius.round(),
            ),
          );
      if (!mounted) return;
      DashToast.success(
        context,
        t('dawam.pinSaved', args: {'name': widget.branch.name}),
      );
      // `invalidateBranches()`: the checklist, the sidebar and the scope bar
      // all read this list.
      ref.invalidate(branchesProvider);
      widget.onSaved();
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
    final b = widget.branch;
    final pinned = isBranchPinned(b);
    final trailing = widget.open
        ? t('common.close')
        : pinned
        ? t('common.edit')
        : t('dawam.pinIt');
    final status = pinned
        ? t('dawam.pinnedSummary', args: {'radius': b.geoRadiusMeters})
        : t('dawam.notPinned');
    final header = DashPressable(
      key: ValueKey('setup-pin-toggle-${b.id}'),
      onTap: widget.onToggle,
      expanded: widget.open,
      semanticLabel: '${b.name}, $status, $trailing',
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        padding: const EdgeInsets.all(Space.md),
        foregroundDecoration: dashFocusRing(
          context,
          s,
          BorderRadius.circular(Radii.xs),
        ),
        decoration: BoxDecoration(
          color: s.highlighted ? c.hover.withValues(alpha: 0.5) : null,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Row(
          spacing: Space.md,
          children: [
            DashIcon(
              pinned ? 'check-circle-2' : 'map-pin',
              size: IconSize.lg,
              color: pinned ? c.success : c.textSecondary,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    b.name,
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    status,
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              trailing,
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
    if (!widget.open) return header;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.hairline)),
          ),
          child: _editor(context, t),
        ),
      ],
    );
  }

  Widget _editor(BuildContext context, Translator t) {
    final c = context.madarColors;
    final b = widget.branch;
    final phone = DashBreakpoints.isPhone(context);
    final pasteError = _pasteError(t);

    final locate = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        Text(
          t('dawam.pinHere'),
          style: DashType.bodyMedium.copyWith(color: c.textPrimary),
        ),
        DashButton(
          key: ValueKey('setup-locate-${b.id}'),
          label: t('dawam.useMyLocation'),
          icon: 'locate-fixed',
          variant: DashButtonVariant.outline,
          loading: _locating is _Busy,
          onPressed: widget.canEdit ? _locate : null,
        ),
      ],
    );

    final paste = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        Text(
          t('dawam.pastePin'),
          style: DashType.bodyMedium.copyWith(
            color: pasteError == null ? c.textPrimary : c.errorText,
          ),
        ),
        // The link reads left to right in both languages, so the field and
        // its paste glyph sit on the physical left.
        Directionality(
          textDirection: TextDirection.ltr,
          child: DashTextInput(
            key: ValueKey('setup-paste-${b.id}'),
            value: _paste,
            onChanged: _onPaste,
            enabled: widget.canEdit,
            invalid: pasteError != null,
            leadingIcon: 'clipboard-paste',
            semanticLabel: t('dawam.pastePin'),
            placeholder: 'https://www.google.com/maps/… · 30.0444, 31.2357',
            keyboardType: TextInputType.url,
          ),
        ),
        if (pasteError != null) _alert(context, pasteError),
      ],
    );

    final pin = _pin;
    final locating = _locating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        if (phone)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              Align(alignment: AlignmentDirectional.centerStart, child: locate),
              paste,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              locate,
              Expanded(child: paste),
            ],
          ),
        if (locating is _Failed)
          _alert(context, switch (locating.failure) {
            LocationFailure.unsupported => t('dawam.pinNoGeo'),
            LocationFailure.denied => t('dawam.pinDenied'),
            LocationFailure.unavailable => t('dawam.pinUnavailable'),
          }),
        if (locating is _Done && locating.accuracy > 100)
          _warning(
            context,
            t('dawam.pinRough', args: {'m': locating.accuracy}),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs + DashMetrics.hair,
          children: [
            Text(
              t('dawam.radius'),
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _radiusFieldWidth),
              child: DashNumberInput(
                key: ValueKey('setup-radius-${b.id}'),
                value: _radius,
                onChanged: (v) => setState(() => _radius = v),
                min: 10,
                max: 5000,
                step: 50,
                suffix: t('dawam.metres'),
                unitWord: t('dawam.metres'),
                presets: const [100, 200, 300, 500],
                presetLabel: (n) => '${jsNumber(n)} ${t('dawam.metres')}',
                enabled: widget.canEdit,
                hint: t('dawam.radiusHint'),
                semanticLabel: t('dawam.radius'),
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.md,
            runSpacing: Space.md,
            children: [
              if (pin != null)
                _pinSummary(context, t, pin)
              else
                Text(
                  t('dawam.pinNone2'),
                  key: const ValueKey('setup-pin-none'),
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
              DashButton(
                key: ValueKey('setup-save-pin-${b.id}'),
                label: isBranchPinned(b)
                    ? t('dawam.savePin')
                    : t('dawam.pinBranch', args: {'name': b.name}),
                loading: _busy,
                onPressed: _canSave ? _save : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pinSummary(BuildContext context, Translator t, LatLng pin) {
    final c = context.madarColors;
    final open = ref.read(linkOpenerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${t('dawam.pinAt')} ',
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
            Text(
              fmtLatLng(pin),
              key: const ValueKey('setup-pin-at'),
              textDirection: TextDirection.ltr,
              style: DashType.mono.copyWith(color: c.textPrimary),
            ),
            Text(' · ', style: DashType.body.copyWith(color: c.textPrimary)),
            DashButton(
              key: const ValueKey('setup-check-maps'),
              label: t('dawam.checkOnMaps'),
              variant: DashButtonVariant.link,
              size: DashButtonSize.compact,
              trailingIcon: 'external-link',
              onPressed: () => open(mapsLink(pin)),
            ),
          ],
        ),
        if (!inEgypt(pin)) _warning(context, t('dawam.pinNotEgypt')),
      ],
    );
  }

  /// `role="alert"`: an error the field or the locator raised.
  Widget _alert(BuildContext context, String text) => Semantics(
    liveRegion: true,
    container: true,
    child: Text(
      text,
      style: DashType.small.copyWith(color: context.madarColors.errorText),
    ),
  );

  /// A warning that never blocks (`warnTextClass`).
  Widget _warning(BuildContext context, String text) => Semantics(
    liveRegion: true,
    container: true,
    child: Text(
      text,
      style: DashType.small.copyWith(
        color: DashTone.warning.foreground(context.madarColors),
      ),
    ),
  );
}
