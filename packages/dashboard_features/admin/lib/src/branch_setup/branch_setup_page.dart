/// `/branch-setup` Branch setup, the branch builder (ADM-BSU-001…088). Web:
/// `routes/_app/branch-setup.tsx`, `features/branch-builder/builder-page.tsx`.
///
/// The owner draws the branch (its POS devices, printers, kitchen screens
/// and sections) and how they talk: one canvas in a card, an edit toolbar
/// while unlocked, an inspector docked beside it from 1280 px (under it
/// below). Edits collect in a draft with undo and are reviewed before they
/// are saved, whole, in one request. No route guard and nothing gated inside
/// the page: the server refuses what the person may not read or change.
library;

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'branch_setup_providers.dart';
import 'builder_canvas.dart';
import 'dialogs.dart';
import 'inspector.dart';
import 'plan.dart';
import 'plan_draft.dart';
import 'vocabulary.dart';

/// One editor per branch: a draft and its undo steps never follow the scope
/// bar onto another branch, where Save would write them. Switching branch
/// with unsaved changes asks first; Cancel puts the scope back.
class BranchSetupPage extends ConsumerStatefulWidget {
  const BranchSetupPage({super.key});

  static const String path = '/branch-setup';

  @override
  ConsumerState<BranchSetupPage> createState() => _BranchSetupPageState();
}

class _BranchSetupPageState extends ConsumerState<BranchSetupPage> {
  late String? _shown = ref.read(currentScopeProvider).branchId;
  final ValueNotifier<bool> _dirty = ValueNotifier(false);
  bool _asking = false;

  @override
  void dispose() {
    _dirty.dispose();
    super.dispose();
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty.value) return true;
    final t = ref.read(tProvider);
    return showDashConfirm(
      context,
      title: t('builder.leaveTitle'),
      description: t('builder.leaveBody'),
      confirmLabel: t('builder.leave'),
      cancelLabel: t('common.cancel'),
      destructive: true,
    );
  }

  Future<void> _onScope(String? next) async {
    if (next == _shown || _asking) return;
    if (!_dirty.value) {
      setState(() => _shown = next);
      return;
    }
    _asking = true;
    final leave = await _confirmLeave();
    _asking = false;
    if (!mounted) return;
    if (leave) {
      _dirty.value = false;
      setState(() => _shown = next);
    } else {
      // The scope (and its header and stored choice) goes back to the branch
      // still being edited.
      unawaited(ref.read(scopeProvider.notifier).setBranch(_shown));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      currentScopeProvider.select((s) => s.branchId),
      (_, next) => _onScope(next),
    );
    final t = ref.watch(tProvider);
    final shown = _shown;
    if (shown == null) {
      return DashPageScaffold(
        title: t('builder.title'),
        body: DashEmptyState(
          key: const ValueKey('bb-pick-branch'),
          icon: 'network',
          title: t('builder.pickBranch'),
        ),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: _dirty,
      builder: (context, dirty, child) => PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = Navigator.of(context);
          if (await _confirmLeave()) {
            _dirty.value = false;
            nav.maybePop();
          }
        },
        child: child!,
      ),
      child: BranchBuilder(
        key: ValueKey(shown),
        branchId: shown,
        dirty: _dirty,
        confirmLeave: _confirmLeave,
      ),
    );
  }
}

class BranchBuilder extends ConsumerStatefulWidget {
  const BranchBuilder({
    required this.branchId,
    required this.dirty,
    required this.confirmLeave,
    super.key,
  });

  final String branchId;

  /// Tells the page whether there is a draft to lose.
  final ValueNotifier<bool> dirty;
  final Future<bool> Function() confirmLeave;

  @override
  ConsumerState<BranchBuilder> createState() => _BranchBuilderState();
}

class _BranchBuilderState extends ConsumerState<BranchBuilder> {
  final PlanDraft _draft = PlanDraft();
  final BuilderViewport _viewport = BuilderViewport();
  final ValueNotifier<bool> _saving = ValueNotifier(false);
  final DashPopoverController _historyMenu = DashPopoverController();
  final DashPopoverController _addMenu = DashPopoverController();
  final FocusNode _pageFocus = FocusNode(
    debugLabel: 'branch-builder',
    skipTraversal: true,
  );
  bool _editable = false;
  Set<String> _selection = const {};
  PlanLink? _selectedLink;
  String? _framedFor;
  BuildContext? _review;
  Object? _lastView;
  String? _lastLang;
  late DateTime _now = ref.read(clockProvider)();
  Timer? _ticker;

  String get _branch => widget.branchId;

  @override
  void initState() {
    super.initState();
    _draft.addListener(_onDraft);
    // "Seen 4 min ago" ages by the clock, not by a refetch.
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() => _now = ref.read(clockProvider)());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pageFocus.dispose();
    _draft.dispose();
    _viewport.dispose();
    _saving.dispose();
    _historyMenu.dispose();
    _addMenu.dispose();
    super.dispose();
  }

  void _onDraft() {
    if (!mounted) return;
    setState(() {});
    widget.dirty.value = _draft.dirty;
  }

  BuilderPlan get _plan => _draft.plan ?? BuilderPlan.empty;

  // ── Edits ───────────────────────────────────────────────────────────────

  void _select(PieceRef? ref) => setState(() {
    _selectedLink = null;
    _selection = ref == null ? const {} : {ref.key};
  });

  /// Somewhere free near the middle of the view, so a new piece lands in
  /// sight.
  ({double x, double y}) _freeSpot(double h) {
    final boxes = boxesOf(_plan);
    final r = _viewport.rect;
    final x = snapTo(r.left + r.width / 2 - kNodeW / 2, true);
    var y = snapTo(r.top + r.height / 2 - h / 2, true);
    bool overlaps(double yy) => boxes.any(
      (b) =>
          x < b.x + b.w && x + kNodeW > b.x && yy < b.y + b.h && yy + h > b.y,
    );
    for (var i = 0; i < 40 && overlaps(y); i++) {
      y += 20;
    }
    return (x: x, y: y);
  }

  void _addDevice(String kind, Translator t) {
    final id = newPieceId();
    final n = _plan.devices.where((d) => d.kind == kind).length + 1;
    final at = _freeSpot(kNodeH);
    _draft.change(
      (p) => p.copyWith(
        devices: [
          ...p.devices,
          BuilderDevice(
            id: id,
            kind: kind,
            name: '${deviceKindLabel(t, kind)} $n',
            x: at.x,
            y: at.y,
          ),
        ],
      ),
    );
    _select(PieceRef(PieceKind.device, id));
  }

  void _addPrinter(String role, Translator t) {
    final id = newPieceId();
    final n = _plan.printers.where((p) => p.role == role).length + 1;
    final at = _freeSpot(kNodeH);
    _draft.change(
      (p) => p.copyWith(
        printers: [
          ...p.printers,
          BuilderPrinter(
            id: id,
            role: role,
            name: '${printerRoleLabel(t, role)} $n',
            connection: 'network',
            port: 9100,
            paperMm: 80,
            x: at.x,
            y: at.y,
          ),
        ],
      ),
    );
    _select(PieceRef(PieceKind.printer, id));
  }

  void _addSection(Translator t) {
    final id = newPieceId();
    final n = _plan.sections.length + 1;
    final at = _freeSpot(kSectionH);
    _draft.change(
      (p) => p.copyWith(
        sections: [
          ...p.sections,
          BuilderSection(
            id: id,
            name: '${t('builder.kind.section')} $n',
            isDefault: p.sections.isEmpty,
            x: at.x,
            y: at.y,
          ),
        ],
      ),
    );
    _select(PieceRef(PieceKind.section, id));
  }

  void _remove(Set<String> keys) {
    if (!_editable || keys.isEmpty) return;
    _draft.change((p) => removePieces(p, keys));
    setState(() => _selection = const {});
  }

  void _removeSelected() {
    final link = _selectedLink;
    if (link != null) {
      _draft.change((p) => removeLink(p, link));
      setState(() => _selectedLink = null);
    } else {
      _remove(_selection);
    }
  }

  void _pickSetup(Setup setup, BranchPlanView view, Translator t) {
    final names = (
      till: '${deviceKindLabel(t, 'pos')} 1',
      receiptPrinter: printerRoleLabel(t, 'receipt'),
      kitchen: t('builder.names.kitchen'),
      kitchenPrinter: printerRoleLabel(t, 'kitchen'),
      kitchenScreen: deviceKindLabel(t, 'kitchen'),
      sectionA: t('builder.names.hot'),
      sectionB: t('builder.names.cold'),
      screenA: t('builder.names.hotScreen'),
      screenB: t('builder.names.coldScreen'),
    );
    _draft.replace(
      planForSetup(setup, names, [
        for (final c in view.categories) c.id,
      ], newPieceId),
    );
    setState(() {
      _editable = true;
      _framedFor = null;
    });
  }

  void _loadVersion(PlanVersionView v, BranchPlanView view) {
    final earlier = fromWire(v.plan);
    final registered = {for (final d in view.devices) d.id};
    final live = {for (final c in view.categories) c.id};
    // A device retired since can't fill a place again, nor can a deleted
    // category be routed.
    _draft.replace(
      earlier.copyWith(
        devices: [
          for (final d in earlier.devices)
            d.deviceId != null && !registered.contains(d.deviceId)
                ? d.copyWith(deviceId: () => null)
                : d,
        ],
        sections: [
          for (final s in earlier.sections)
            s.copyWith(
              categoryIds: [
                for (final c in s.categoryIds)
                  if (live.contains(c)) c,
              ],
            ),
        ],
      ),
    );
    setState(() => _editable = true);
  }

  void _frame() => _viewport.fitTo(boxesOf(_plan));

  // ── Saving ──────────────────────────────────────────────────────────────

  Future<void> _openReview(BranchPlanView view, BuilderPlan saved) async {
    final openItems = {for (final c in view.openItems) c.sectionId: c.count};
    await showDashDialog<void>(
      context,
      builder: (ctx) {
        _review = ctx;
        return ListenableBuilder(
          listenable: _draft,
          builder: (context, _) => ReviewDialog(
            before: saved,
            after: _plan,
            firstSave: !view.saved,
            routingNow: view.routingMode,
            openItems: openItems,
            saving: _saving,
            onConfirm: _save,
          ),
        );
      },
    );
    _review = null;
  }

  void _closeReview() {
    final r = _review;
    if (r != null && r.mounted) Navigator.of(r).pop();
  }

  Future<void> _save() async {
    final base = _draft.baseVersion;
    if (base == null) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    // Captured before the await: the page may close mid-save.
    final bus = ref.read(realtimeBusProvider);
    final cache = ref.read(branchPlanProvider(_branch).notifier);
    final plan = _plan;
    _saving.value = true;
    try {
      final view = await api.branchPlan.savePlan(
        body: SavePlanRequest(
          branchId: _branch,
          expectedVersion: base,
          plan: toWire(plan),
        ),
      );
      cache.write(view);
      // Sections are kitchen stations and categories their routes: the
      // kitchen pages read the same rows.
      bus.invalidate(const [BranchPlanPaths.versions, BranchPlanPaths.kitchen]);
      if (!mounted) return;
      _draft.adopt(fromWire(view.plan), view.version);
      _closeReview();
      DashToast.success(context, t('builder.saved'));
    } on Object catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.status == 409 && e.code == 'PLAN_CHANGED') {
        _closeReview();
        DashToast.show(
          context,
          builderErrorText(e, t),
          kind: DashToastKind.error,
          duration: const Duration(seconds: 12),
          actionLabel: t('builder.reloadTheirs'),
          onAction: () {
            if (!mounted) return;
            _draft.discard();
            ref.invalidate(branchPlanProvider(_branch));
          },
        );
      } else {
        DashToast.error(context, builderErrorText(e, t));
      }
    } finally {
      _saving.value = false;
    }
  }

  Future<void> _toItemRouting() async {
    final router = GoRouter.of(context);
    if (await widget.confirmLeave()) {
      widget.dirty.value = false;
      router.go(BranchPlanPaths.kitchenRouting);
    }
  }

  // ── Keyboard ────────────────────────────────────────────────────────────

  /// The canvas's shortcuts, anywhere outside text fields, the inspector,
  /// dialogs and menus.
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || !mounted) return KeyEventResult.ignored;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return KeyEventResult.ignored;
    final f = FocusManager.instance.primaryFocus?.context;
    if (f != null &&
        (f.widget is EditableText ||
            f.findAncestorWidgetOfExactType<EditableText>() != null ||
            InspectorScope.contains(f) ||
            f.findAncestorWidgetOfExactType<DashPopover>() != null)) {
      return KeyEventResult.ignored;
    }
    final q = ref.read(branchPlanProvider(_branch));
    final view = q.value;
    final kb = HardwareKeyboard.instance;
    final mod = kb.isMetaPressed || kb.isControlPressed;
    final k = e.logicalKey;
    final repeat = e is KeyRepeatEvent;
    if (mod && k == LogicalKeyboardKey.keyE) {
      if (!repeat) setState(() => _editable = !_editable);
      return KeyEventResult.handled;
    }
    if (mod && k == LogicalKeyboardKey.keyZ) {
      if (_editable) kb.isShiftPressed ? _draft.redo() : _draft.undo();
      return KeyEventResult.handled;
    }
    if (mod && k == LogicalKeyboardKey.keyY) {
      if (_editable) _draft.redo();
      return KeyEventResult.handled;
    }
    if (mod && k == LogicalKeyboardKey.keyS) {
      final blocking = checkPlan(_plan).where((p) => p.blocking).length;
      if (!repeat && view != null && _draft.dirty && blocking == 0) {
        unawaited(_openReview(view, _savedOf(view)));
      }
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch == '+' ||
        ch == '=' ||
        k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.numpadAdd) {
      _viewport.zoomBy(kZoomStep);
      return KeyEventResult.handled;
    }
    if (ch == '-' ||
        ch == '_' ||
        k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      _viewport.zoomBy(1 / kZoomStep);
      return KeyEventResult.handled;
    }
    if (ch == '0' ||
        k == LogicalKeyboardKey.digit0 ||
        k == LogicalKeyboardKey.numpad0) {
      _frame();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      setState(() {
        _selection = const {};
        _selectedLink = null;
      });
      return KeyEventResult.ignored;
    }
    final delta = switch (k) {
      LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight => const Offset(1, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -1),
      LogicalKeyboardKey.arrowDown => const Offset(0, 1),
      _ => null,
    };
    // Arrows never move focus between cards here (no directional focus on
    // the web); they nudge the selection while editing.
    if (delta != null && (!_editable || _selection.isEmpty)) {
      return KeyEventResult.handled;
    }
    if (!_editable) return KeyEventResult.ignored;
    if (delta != null) {
      final step = kb.isShiftPressed ? 1.0 : 10.0;
      _draft.change(
        (p) => movePieces(p, {
          for (final b in boxesOf(_plan))
            if (_selection.contains(b.key))
              b.key: (x: b.x + delta.dx * step, y: b.y + delta.dy * step),
        }),
      );
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      _removeSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Render ──────────────────────────────────────────────────────────────

  BuilderPlan _savedOf(BranchPlanView view) {
    final t = ref.read(tProvider);
    final plan = localizeServerNames(
      fromWire(view.plan),
      t('builder.kind.receiptPrinter'),
      (section) =>
          t('builder.names.sectionPrinter', args: {'section': section}),
    );
    // A slot still naming a device retired since shows "Not set up"; it is
    // let go here too, or every save would be refused (web bug ADM-BSU-084).
    final live = {for (final d in view.devices) d.id};
    if (plan.devices.every(
      (d) => d.deviceId == null || live.contains(d.deviceId),
    )) {
      return plan;
    }
    return plan.mapDevices(
      (d) => d.deviceId == null || live.contains(d.deviceId)
          ? d
          : d.copyWith(deviceId: () => null),
    );
  }

  List<PieceView> _pieces(
    BuilderPlan plan,
    List<Problem> problems,
    BranchPlanView? view,
    Translator t,
    DashFormat fmt,
  ) {
    final registered = <String, PlanRegisteredDevice>{
      for (final d in view?.devices ?? const <PlanRegisteredDevice>[]) d.id: d,
    };
    final openItems = {
      for (final c in view?.openItems ?? const <SectionCount>[])
        c.sectionId: c.count,
    };
    final boxes = {for (final b in boxesOf(plan)) b.key: b};
    PieceProblem? problemOf(String key) {
      final mine = problems.where((p) => p.piece?.key == key);
      if (mine.any((p) => p.blocking)) return PieceProblem.blocking;
      return mine.isEmpty ? null : PieceProblem.warning;
    }

    final unnamed = t('builder.unnamed');
    return [
      for (final d in plan.devices)
        () {
          final key = pieceKey(PieceKind.device, d.id);
          final (:presence, :seen) = presenceOf(d.deviceId, registered, _now);
          final shows = [
            for (final s in plan.sections)
              if (s.screenIds.contains(d.id)) s.name,
          ];
          return PieceView(
            box: boxes[key]!,
            icon: deviceIcon[d.kind] ?? 'monitor',
            title: d.name.isEmpty ? unnamed : d.name,
            subtitle: d.kind == 'kitchen' && shows.isNotEmpty
                ? shows.join(' · ')
                : deviceKindLabel(t, d.kind),
            presence: switch (presence) {
              Presence.unclaimed => (
                tone: PresenceTone.unclaimed,
                label: t('builder.notSetUpShort'),
              ),
              Presence.online => (
                tone: PresenceTone.online,
                label: t('builder.online'),
              ),
              Presence.offline => (
                tone: PresenceTone.offline,
                label: t(
                  'builder.seenAt',
                  args: {
                    'when': fmt.fmtStamp(
                      seen?.lastSeenAt.toIso8601String(),
                      _now,
                    ),
                  },
                ),
              ),
            },
            placeholder: presence == Presence.unclaimed,
            problem: problemOf(key),
          );
        }(),
      for (final p in plan.printers)
        () {
          final key = pieceKey(PieceKind.printer, p.id);
          final host = plan.device(p.hostDeviceId);
          final ip = p.ip ?? '';
          return PieceView(
            box: boxes[key]!,
            icon: printerIcon[p.role] ?? 'printer',
            title: p.name.isEmpty ? unnamed : p.name,
            subtitle: printerRoleLabel(t, p.role),
            detail: p.network
                ? (ip.isEmpty ? t('builder.noAddress') : ip)
                : host != null
                ? '${connectionLabel(t, p.connection)} · ${host.name}'
                : connectionLabel(t, p.connection),
            problem: problemOf(key),
          );
        }(),
      for (final s in plan.sections)
        () {
          final key = pieceKey(PieceKind.section, s.id);
          final cooking = openItems[s.id] ?? 0;
          return PieceView(
            box: boxes[key]!,
            icon: sectionIcon,
            title: s.name.isEmpty ? unnamed : s.name,
            badge: s.isDefault ? t('builder.defaultBadge') : null,
            subtitle: t('builder.categoriesCount', count: s.categoryIds.length),
            detail: cooking > 0
                ? t('builder.cookingCount', count: cooking)
                : null,
            problem: problemOf(key),
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = ref.watch(branchPlanProvider(_branch));
    final view = q.value;
    final saved = view == null ? null : _savedOf(view);
    if (view != null && (!identical(view, _lastView) || lang != _lastLang)) {
      _lastView = view;
      _lastLang = lang;
      _draft.receive(saved!, view.version);
      widget.dirty.value = _draft.dirty;
    }
    final plan = _plan;
    final problems = checkPlan(plan);
    final blocking = problems.where((p) => p.blocking).length;
    final pieces = _pieces(plan, problems, view, t, fmt);
    final empty = _draft.plan != null && pieces.isEmpty;
    final dirty = _draft.dirty;

    // Frame the branch once it is known, and again when a setup fills an
    // empty plan.
    if (_draft.plan != null) {
      final key = '$_branch:${pieces.isNotEmpty}';
      if (_framedFor != key) {
        _framedFor = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _frame();
        });
      }
    }

    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    final docked = width >= DashBreakpoints.xl;

    final actions = _actions(t, fmt, view, saved, dirty, blocking, width);

    Widget canvasArea() {
      final Widget main;
      if (q.awaitingFirst) {
        main = const Padding(
          padding: EdgeInsets.all(Space.md),
          child: DashSkeleton(
            key: ValueKey('bb-skeleton'),
            height: double.infinity,
          ),
        );
      } else if (q.failedFirst) {
        main = Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: DashErrorState(
              key: const ValueKey('bb-error'),
              framed: false,
              title: t('common.loadFailed'),
              message: builderErrorText(q.error, t),
              retryLabel: t('common.retry'),
              retrying: q.isLoading,
              onRetry: () => ref.invalidate(branchPlanProvider(_branch)),
            ),
          ),
        );
      } else if (empty) {
        main = SetupPicker(onPick: (s) => _pickSetup(s, view!, t));
      } else {
        main = BuilderCanvas(
          key: const ValueKey('bb-canvas'),
          plan: plan,
          pieces: pieces,
          editable: _editable,
          viewport: _viewport,
          selection: _selection,
          onSelectionChange: (s) => setState(() {
            _selection = s;
            if (s.isNotEmpty) _selectedLink = null;
          }),
          selectedLink: _selectedLink,
          onSelectLink: (l) => setState(() => _selectedLink = l),
          beginGesture: _draft.beginGesture,
          onMove: (moves) => _draft.live((p) => movePieces(p, moves)),
          onLink: (from, to) {
            // The same plan comes back only when the two can't be linked;
            // redrawing a line or swapping a receipt printer is still one.
            if (identical(addLink(plan, from, to), plan)) {
              DashToast.show(context, t('builder.cantLink'));
              return;
            }
            _draft.change((p) => addLink(p, from, to));
          },
          onRemoveLink: (l) {
            _draft.change((p) => removeLink(p, l));
            setState(() => _selectedLink = null);
          },
          words: (
            canvas: t('builder.canvasAria'),
            link: (k) => linkLabel(t, k),
            removeLink: t('builder.removeLink'),
          ),
        );
      }
      return Stack(
        children: [
          // A press on the canvas brings the keys back to the page.
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                if (!_pageFocus.hasPrimaryFocus) _pageFocus.requestFocus();
              },
              child: main,
            ),
          ),
          if (!empty && q.hasValue)
            PositionedDirectional(
              start: Space.md,
              end: Space.md,
              bottom: Space.md,
              child: IgnorePointer(
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  runSpacing: Space.sm,
                  spacing: Space.sm,
                  children: [
                    _Floating(child: LinkLegend(label: (k) => linkLabel(t, k))),
                    _Floating(
                      child: Text(
                        t(
                          'builder.counts',
                          args: {
                            'devices': plan.devices.length,
                            'printers': plan.printers.length,
                            'sections': plan.sections.length,
                          },
                        ),
                        key: const ValueKey('bb-counts'),
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    final inspector = view != null && !q.failedFirst
        ? BuilderInspector(
            key: const ValueKey('bb-inspector'),
            props: InspectorProps(
              branchId: _branch,
              plan: plan,
              selection: _selection,
              editable: _editable,
              change: _draft.change,
              onSelect: _select,
              onRemove: _remove,
              problems: problems,
              categories: view.categories,
              registered: view.devices,
              savedSlots: view.saved
                  ? {for (final d in saved!.devices) d.id}
                  : const {},
              openItems: {for (final x in view.openItems) x.sectionId: x.count},
              itemOverrides: {
                for (final x in view.itemOverrides) x.sectionId: x.count,
              },
              now: _now,
              onItemRouting: _toItemRouting,
            ),
          )
        : null;

    final toolbar = _editable && !empty ? _toolbar(t, width) : null;

    final card = Container(
      key: const ValueKey('bb-card'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.border),
      ),
      child: docked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?toolbar,
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: canvasArea()),
                      Container(
                        width: 340,
                        decoration: BoxDecoration(
                          border: BorderDirectional(
                            start: BorderSide(color: c.border),
                          ),
                        ),
                        child: inspector == null
                            ? null
                            : SingleChildScrollView(child: inspector),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?toolbar,
                SizedBox(height: height * 0.45, child: canvasArea()),
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: inspector,
                ),
              ],
            ),
    );

    final banner = _draft.overtaken
        ? Semantics(
            liveRegion: true,
            child: Container(
              key: const ValueKey('bb-overtaken'),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm + 2,
              ),
              decoration: BoxDecoration(
                color: c.warningBg,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: c.warning.withValues(alpha: 0.4)),
              ),
              child: Wrap(
                spacing: Space.md,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MadarIcon('triangle-alert', size: 16, tint: c.warning),
                  Text(
                    t('builder.overtaken'),
                    style: DashType.body.copyWith(color: c.textPrimary),
                  ),
                  DashButton(
                    key: const ValueKey('bb-load-theirs'),
                    label: t('builder.reloadTheirs'),
                    variant: DashButtonVariant.outline,
                    size: DashButtonSize.compact,
                    onPressed: _draft.discard,
                  ),
                ],
              ),
            ),
          )
        : null;

    // The canvas's shortcuts: anywhere in the page (the web listens on the
    // window), the page holding focus from the start.
    return Focus(
      focusNode: _pageFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: DashPageScaffold(
        title: t('builder.title'),
        subtitle: t('builder.subtitle'),
        actions: [actions],
        fillBody: docked,
        width: DashPageWidth.full,
        body: docked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.lg,
                children: [
                  ?banner,
                  Expanded(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: height * 0.6),
                      child: card,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.lg,
                children: [?banner, card],
              ),
      ),
    );
  }

  Widget _actions(
    Translator t,
    DashFormat fmt,
    BranchPlanView? view,
    BuilderPlan? saved,
    bool dirty,
    int blocking,
    double width,
  ) {
    final c = context.madarColors;
    final historyEnabled = view?.saved ?? false;
    final save = DashButton(
      key: const ValueKey('bb-save'),
      label: t('builder.saveEllipsis'),
      onPressed: blocking > 0 || _saving.value || view == null
          ? null
          : () => _openReview(view, saved!),
    );
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (dirty)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: Space.xs),
              child: Row(
                key: const ValueKey('bb-unsaved'),
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs + 2,
                children: [
                  MadarIcon('circle-dot', size: 12, tint: c.accent),
                  Text(
                    t('builder.unsaved'),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        DashIconButton(
          key: const ValueKey('bb-zoom-out'),
          icon: 'minus',
          semanticLabel: t('floor.zoomOut'),
          variant: DashButtonVariant.ghost,
          onPressed: () => _viewport.zoomBy(1 / kZoomStep),
        ),
        DashIconButton(
          key: const ValueKey('bb-fit'),
          icon: 'maximize-2',
          semanticLabel: t('floor.fit'),
          variant: DashButtonVariant.ghost,
          onPressed: _frame,
        ),
        DashIconButton(
          key: const ValueKey('bb-zoom-in'),
          icon: 'plus',
          semanticLabel: t('floor.zoomIn'),
          variant: DashButtonVariant.ghost,
          onPressed: () => _viewport.zoomBy(kZoomStep),
        ),
        DashPopover(
          controller: _historyMenu,
          align: DashPopoverAlign.end,
          width: 288,
          anchor: (context, ctl) {
            void open() => ctl.toggle();
            void warm() => ref.warm(planVersionsProvider(_branch));
            return width >= DashBreakpoints.sm
                ? DashButton(
                    key: const ValueKey('bb-history'),
                    label: t('builder.history'),
                    icon: 'history',
                    variant: DashButtonVariant.ghost,
                    onIntent: historyEnabled ? warm : null,
                    onPressed: historyEnabled ? open : null,
                  )
                : DashIconButton(
                    key: const ValueKey('bb-history'),
                    icon: 'history',
                    semanticLabel: t('builder.history'),
                    variant: DashButtonVariant.ghost,
                    onIntent: historyEnabled ? warm : null,
                    onPressed: historyEnabled ? open : null,
                  );
          },
          content: (context, ctl) => _HistoryMenu(
            branchId: _branch,
            currentVersion: view?.version,
            onPick: (v) {
              ctl.close();
              if (view != null) _loadVersion(v, view);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: Space.xs),
          child: Semantics(
            toggled: _editable,
            child: DashButton(
              key: const ValueKey('bb-lock'),
              label: _editable ? t('floor.editing') : t('floor.locked'),
              icon: _editable ? 'lock-open' : 'lock',
              variant: _editable
                  ? DashButtonVariant.primary
                  : DashButtonVariant.outline,
              onPressed: () => setState(() => _editable = !_editable),
            ),
          ),
        ),
        if (dirty) ...[
          ValueListenableBuilder<bool>(
            valueListenable: _saving,
            builder: (context, saving, _) => DashButton(
              key: const ValueKey('bb-discard'),
              label: t('builder.discard'),
              variant: DashButtonVariant.ghost,
              onPressed: saving ? null : _draft.discard,
            ),
          ),
          if (blocking > 0)
            Tooltip(
              key: const ValueKey('bb-fix-first'),
              message: t('builder.fixFirst'),
              child: Focus(child: save),
            )
          else
            save,
        ],
      ],
    );
  }

  Widget _toolbar(Translator t, double width) {
    final c = context.madarColors;
    Widget divider() => Container(
      width: 1,
      height: Space.lg,
      margin: const EdgeInsets.symmetric(horizontal: Space.xs),
      color: c.border,
    );
    return Container(
      key: const ValueKey('bb-toolbar'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs + 2,
      ),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          DashPopover(
            controller: _addMenu,
            width: 232,
            anchor: (context, ctl) => DashButton(
              key: const ValueKey('bb-add'),
              label: t('builder.add'),
              icon: 'plus',
              trailingIcon: 'chevron-down',
              variant: DashButtonVariant.ghost,
              size: DashButtonSize.compact,
              onPressed: ctl.toggle,
            ),
            content: (context, ctl) {
              Widget item(String icon, String label, VoidCallback onTap) =>
                  _MenuRow(
                    icon: icon,
                    label: label,
                    onTap: () {
                      ctl.close();
                      onTap();
                    },
                  );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MenuLabel(t('builder.frontOfHouse')),
                  for (final k in const ['pos', 'waiter'])
                    item(
                      deviceIcon[k]!,
                      deviceKindLabel(t, k),
                      () => _addDevice(k, t),
                    ),
                  item(
                    printerIcon['receipt']!,
                    printerRoleLabel(t, 'receipt'),
                    () => _addPrinter('receipt', t),
                  ),
                  Divider(height: Space.sm + 1, color: c.border),
                  _MenuLabel(t('builder.kitchenSide')),
                  item(
                    sectionIcon,
                    t('builder.kind.section'),
                    () => _addSection(t),
                  ),
                  item(
                    deviceIcon['kitchen']!,
                    deviceKindLabel(t, 'kitchen'),
                    () => _addDevice('kitchen', t),
                  ),
                  item(
                    printerIcon['kitchen']!,
                    printerRoleLabel(t, 'kitchen'),
                    () => _addPrinter('kitchen', t),
                  ),
                ],
              );
            },
          ),
          divider(),
          DashIconButton(
            key: const ValueKey('bb-undo'),
            icon: 'undo-2',
            semanticLabel: t('floor.undo'),
            variant: DashButtonVariant.ghost,
            onPressed: _draft.canUndo ? _draft.undo : null,
          ),
          DashIconButton(
            key: const ValueKey('bb-redo'),
            icon: 'redo-2',
            semanticLabel: t('floor.redo'),
            variant: DashButtonVariant.ghost,
            onPressed: _draft.canRedo ? _draft.redo : null,
          ),
          divider(),
          DashIconButton(
            key: const ValueKey('bb-remove-tool'),
            icon: 'trash-2',
            semanticLabel: t('builder.removePiece'),
            variant: DashButtonVariant.ghost,
            onPressed: _selection.isEmpty && _selectedLink == null
                ? null
                : _removeSelected,
          ),
          const Spacer(),
          if (width >= DashBreakpoints.lg)
            Flexible(
              flex: 8,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: Space.sm),
                child: MadarClippedText(
                  t('builder.hint'),
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Floating extends StatelessWidget {
  const _Floating({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm + 2,
        vertical: Space.xs + 2,
      ),
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Space.sm,
      vertical: Space.xs + 2,
    ),
    child: Text(
      text,
      style: DashType.smallMedium.copyWith(
        color: context.madarColors.textSecondary,
      ),
    ),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.onTap,
    this.icon,
    this.sub,
    this.enabled = true,
    super.key,
  });

  final String? icon;
  final String label;
  final String? sub;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final fg = enabled ? c.textPrimary : c.textMuted;
    return DashPressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      semanticLabel: sub == null ? label : '$label, $sub',
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
          spacing: Space.sm,
          children: [
            if (icon != null) MadarIcon(icon, size: 16, tint: fg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Text(label, style: DashType.body.copyWith(color: fg)),
                  if (sub != null)
                    Text(
                      sub!,
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The History menu: read only while it is open.
class _HistoryMenu extends ConsumerWidget {
  const _HistoryMenu({
    required this.branchId,
    required this.currentVersion,
    required this.onPick,
  });

  final String branchId;
  final int? currentVersion;
  final ValueChanged<PlanVersionView> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = ref.watch(planVersionsProvider(branchId));
    return Column(
      key: const ValueKey('bb-history-menu'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MenuLabel(t('builder.historyHint')),
        Divider(height: Space.sm + 1, color: c.border),
        for (final v in q.value ?? const <PlanVersionView>[])
          _MenuRow(
            key: ValueKey('bb-version-${v.version}'),
            label: [
              t('builder.versionN', args: {'n': v.version}),
              if (v.version == currentVersion) t('builder.current'),
            ].join(' · '),
            sub: [
              fmt.fmtStamp(v.savedAt.toIso8601String()),
              ?v.savedByName,
            ].whereNot((s) => s.isEmpty).join(' · '),
            enabled: v.version != currentVersion,
            onTap: () => onPick(v),
          ),
        if (q.awaitingFirst)
          _MenuRow(label: t('common.loading'), enabled: false, onTap: () {}),
      ],
    );
  }
}
