/// `/floor` (the web's `features/floor/floor-page.tsx`, SELL-FLR rows): the
/// floor-plan editor — one canvas, always showing live status, with editing
/// behind a lock; area chips that filter the same plane; the inspector,
/// table history and transfer queue beside it.
///
/// A floor plan is PHYSICAL space: the canvas and every table are never
/// mirrored in Arabic (`Positioned`, never `PositionedDirectional`); the
/// table glyph shares its constants with the POS (`table_glyph.dart`,
/// `kTable*`). The chips, toolbar and panel follow the reading direction.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../orders/error_text.dart';
import '../shared/branch_required.dart';
import '../shared/invalidate.dart';
import '../shared/sheets.dart';
import 'floor_canvas.dart';
import 'floor_dialogs.dart';
import 'floor_geometry.dart';
import 'floor_inspector.dart';
import 'floor_providers.dart';
import 'floor_util.dart';
import 'table_glyph.dart';
import 'transfer_queue.dart';

/// The area chip of the tables without a section.
const String _unassigned = '__unassigned__';

/// The docked inspector's width (`xl:w-[320px]`).
const double _asideWidth = 320;

class FloorPage extends ConsumerWidget {
  const FloorPage({super.key});

  /// The route's builder (routes.dart points here).
  static Widget route(BuildContext context, GoRouterState state) =>
      const FloorPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchId = ref.watch(sellBranchIdProvider);
    if (branchId == null) {
      return DashPageScaffold(
        title: ref.watch(tProvider)('floor.title'),
        body: const BranchRequiredState(
          messageKey: 'floor.pickBranch',
          icon: 'armchair',
        ),
      );
    }
    // A branch switch starts the floor afresh (locked, All, nothing picked).
    return _FloorBody(key: ValueKey(branchId), branchId: branchId);
  }
}

class _FloorBody extends ConsumerStatefulWidget {
  const _FloorBody({required this.branchId, super.key});

  final String branchId;

  @override
  ConsumerState<_FloorBody> createState() => _FloorBodyState();
}

class _FloorBodyState extends ConsumerState<_FloorBody> {
  bool _editable = false;

  /// The area chip: null = All, [_unassigned], or a section id.
  String? _sectionKey;
  Set<String> _selection = {};
  late DateTime _now;
  Timer? _tick;
  final FloorViewport _viewport = FloorViewport();
  late final FloorGeometry _geometry;
  late final AppLifecycleListener _life;

  /// The view was framed for this area and table count.
  String? _framedFor;

  // What the last build saw, for the keyboard and the commands.
  List<FloorTable> _all = const [];
  List<FloorTable> _visible = const [];
  List<FloorTable> _selected = const [];
  List<FloorSection> _sections = const [];

  String get _branchId => widget.branchId;

  String? get _activeSectionId =>
      _sectionKey == null || _sectionKey == _unassigned ? null : _sectionKey;

  @override
  void initState() {
    super.initState();
    final clock = ref.read(clockProvider);
    _now = clock();
    // A booking's hold begins by the clock, not by an event.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = clock());
    });
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    _geometry = FloorGeometry(
      branchId: _branchId,
      save: (body) => api.reservations.saveLayout(body: body),
      onSaved: () => bus.invalidate(SellInvalidate.floor),
      onFailed: _saveFailed,
    )..addListener(_rebuild);
    HardwareKeyboard.instance.addHandler(_onKey);
    // The tab hidden or the app sent away saves what is pending (`pagehide`).
    _life = AppLifecycleListener(onHide: () => unawaited(_geometry.flush()));
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _tick?.cancel();
    _life.dispose();
    _geometry
      ..removeListener(_rebuild)
      ..dispose();
    _viewport.dispose();
    super.dispose();
  }

  Translator get _t => ref.read(tProvider);

  void _saveFailed(Object e, {required bool conflict}) {
    if (!mounted) return;
    final msg = ordersErrorText(e, _t);
    if (!conflict) {
      DashToast.error(context, msg);
      return;
    }
    final bus = ref.read(realtimeBusProvider);
    DashToast.show(
      context,
      msg,
      kind: DashToastKind.error,
      duration: const Duration(seconds: 12),
      actionLabel: _t('floor.reload'),
      onAction: () {
        _geometry.reload();
        bus.invalidate(SellInvalidate.floor);
      },
    );
  }

  void _setSelection(Set<String> next) => setState(() => _selection = next);

  // ── Geometry commands ───────────────────────────────────────────────────

  void _nudge(double dx, double dy, {required bool fine}) {
    if (!_editable || _selected.isEmpty) return;
    _geometry.beginGesture();
    final step = fine ? 1.0 : kFloorGrid;
    _geometry.setGeo([
      for (final tb in _selected)
        _geometry
            .geoOf(tb)
            .copyWith(
              x: _geometry.geoOf(tb).x + dx * step,
              y: _geometry.geoOf(tb).y + dy * step,
            ),
    ]);
  }

  void _align(FloorAlignment how) {
    final moved = alignItems(_selected.map(_geometry.geoOf).toList(), how);
    if (moved.isEmpty) return;
    _geometry
      ..beginGesture()
      ..setGeo(moved);
  }

  void _distribute() {
    final moved = distributeItems(_selected.map(_geometry.geoOf).toList());
    if (moved.isEmpty) return;
    _geometry
      ..beginGesture()
      ..setGeo(moved);
  }

  void _rotate(double deg) {
    _geometry
      ..beginGesture()
      ..setGeo([
        for (final tb in _selected)
          _geometry
              .geoOf(tb)
              .copyWith(rot: normalizeAngle(_geometry.geoOf(tb).rot + deg)),
      ]);
  }

  void _fit() => _viewport.fitTo(_visible.map(_geometry.geoOf));

  // ── Clipboard ───────────────────────────────────────────────────────────

  Future<void> _copy() async {
    final sel = _selected;
    if (sel.isEmpty) return;
    final payload = serializeTables([
      for (final tb in sel) (label: tb.label, seats: tb.seats, shape: tb.shape),
    ], sel.map(_geometry.geoOf).toList());
    try {
      await Clipboard.setData(ClipboardData(text: payload));
      if (mounted) {
        DashToast.success(context, _t('floor.copied', count: sel.length));
      }
    } on Object {
      if (mounted) DashToast.error(context, _t('floor.clipboardFailed'));
    }
  }

  Future<void> _paste() async {
    if (!_editable) return;
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Object {
      if (mounted) DashToast.error(context, _t('floor.clipboardFailed'));
      return;
    }
    final items = parseClipboard(text);
    if (items == null || !mounted) return;
    final taken = {for (final tb in _all) tb.label};
    // Land the paste in the middle of what is on screen.
    final v = _viewport.view;
    final ox = snapTo(v.x + _viewport.size.width / v.zoom / 2, true);
    final oy = snapTo(v.y + _viewport.size.height / v.zoom / 2, true);
    final api = ref.read(apiProvider).reservations;
    final bus = ref.read(realtimeBusProvider);
    try {
      final created = <String>[];
      for (final it in items) {
        final label = uniqueLabel(it.label, taken);
        taken.add(label);
        final row = await api.createFloorTable(
          body: CreateFloorTableRequest(
            branchId: _branchId,
            label: label,
            seats: it.seats,
            shape: it.shape,
            sectionId: _activeSectionId,
            posX: ox + it.dx + kPasteOffset,
            posY: oy + it.dy + kPasteOffset,
            width: it.w,
            height: it.h,
            rotation: it.rot,
            explicitNulls: const {'section_id'},
          ),
        );
        created.add(row.id);
      }
      bus.invalidate(SellInvalidate.floor);
      if (mounted) _setSelection(created.toSet());
    } on Object catch (e) {
      if (mounted) DashToast.error(context, ordersErrorText(e, _t));
    }
  }

  // ── Deletes ─────────────────────────────────────────────────────────────

  Future<void> _deleteSelection() async {
    final sel = _selected;
    if (!_editable || sel.isEmpty) return;
    final t = _t;
    final ok = await showDashConfirm(
      context,
      title: t('floor.deleteTitle', args: {'count': sel.length}),
      description: t('floor.deleteBody'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider).reservations;
    final bus = ref.read(realtimeBusProvider);
    try {
      for (final tb in sel) {
        await api.deleteFloorTable(id: tb.id);
      }
      if (mounted) _setSelection({});
    } on Object catch (e) {
      if (mounted) DashToast.error(context, ordersErrorText(e, t));
    }
    // Tables removed before a failure are gone either way: show the truth.
    bus.invalidate(SellInvalidate.floor);
  }

  Future<void> _removeSection(FloorSection section) async {
    final t = _t;
    // Its tables are NOT deleted: they move to Unassigned.
    final held = _all.where((tb) => tb.sectionId == section.id).length;
    final ok = await showDashConfirm(
      context,
      title: t('floor.deleteSectionTitle', args: {'name': section.name}),
      description: held > 0
          ? t('floor.deleteSectionBodyTables', args: {'count': held})
          : t('floor.deleteSectionBody'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final bus = ref.read(realtimeBusProvider);
    try {
      await ref.read(apiProvider).reservations.deleteSection(id: section.id);
      bus.invalidate(SellInvalidate.floor);
      if (mounted) setState(() => _sectionKey = null);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, ordersErrorText(e, t));
    }
  }

  void _addTable() => showAddTableDialog(
    context,
    branchId: _branchId,
    sectionId: _activeSectionId,
    sections: _sections,
    tables: _all,
  );

  void _editSection(FloorSection? section) => showSectionDialog(
    context,
    branchId: _branchId,
    section: section,
    nextOrdering: _sections.length,
    // Select what was just made, so its tables are added there.
    onCreated: (id) {
      if (mounted) setState(() => _sectionKey = id);
    },
  );

  // ── Keyboard (the web's window keydown) ──────────────────────────────────

  /// Never steal a keystroke from a text field.
  bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    if (!mounted || ModalRoute.of(context)?.isCurrent == false || _typing()) {
      return false;
    }
    final kb = HardwareKeyboard.instance;
    final mod = kb.isMetaPressed || kb.isControlPressed;
    final k = e.logicalKey;
    if (mod) {
      if (k == LogicalKeyboardKey.keyE) {
        setState(() => _editable = !_editable);
        return true;
      }
      if (k == LogicalKeyboardKey.keyZ) {
        kb.isShiftPressed ? _geometry.redo() : _geometry.undo();
        return true;
      }
      if (k == LogicalKeyboardKey.keyY) {
        _geometry.redo();
        return true;
      }
      if (k == LogicalKeyboardKey.keyC) {
        unawaited(_copy());
        return true;
      }
      if (k == LogicalKeyboardKey.keyV) {
        unawaited(_paste());
        return true;
      }
      if (k == LogicalKeyboardKey.keyA) {
        _setSelection({for (final tb in _visible) tb.id});
        return true;
      }
    }
    if ({
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.add,
      LogicalKeyboardKey.numpadAdd,
    }.contains(k)) {
      _viewport.zoomBy(kZoomStep);
      return true;
    }
    if ({
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.underscore,
      LogicalKeyboardKey.numpadSubtract,
    }.contains(k)) {
      _viewport.zoomBy(1 / kZoomStep);
      return true;
    }
    if (k == LogicalKeyboardKey.digit0 || k == LogicalKeyboardKey.numpad0) {
      _fit();
      return true;
    }
    if (k == LogicalKeyboardKey.escape) {
      _setSelection({});
      return false;
    }
    final arrow = switch (k) {
      LogicalKeyboardKey.arrowLeft => (-1.0, 0.0),
      LogicalKeyboardKey.arrowRight => (1.0, 0.0),
      LogicalKeyboardKey.arrowUp => (0.0, -1.0),
      LogicalKeyboardKey.arrowDown => (0.0, 1.0),
      _ => null,
    };
    if (arrow != null) {
      _nudge(arrow.$1, arrow.$2, fine: kb.isShiftPressed);
      return true;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      unawaited(_deleteSelection());
      return true;
    }
    return false;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final id = _branchId;
    final sectionsQ = ref.watch(floorSectionsProvider(id));
    final tablesQ = ref.watch(floorTablesProvider(id));
    final transfersQ = ref.watch(floorTransfersProvider(id));
    final ticketsQ = ref.watch(floorOpenTicketsProvider(id));
    final customers = customerSheetControl(context, ref);

    final sections = [...?sectionsQ.value]
      ..sort((a, b) {
        final o = a.ordering.compareTo(b.ordering);
        return o != 0
            ? o
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final all = tablesQ.value ?? const <FloorTable>[];
    _geometry.syncTables(all);
    final key = _sectionKey;
    final visible = [
      for (final tb in all)
        if (tb.isActive &&
            (key == null || tb.sectionId == (key == _unassigned ? null : key)))
          tb,
    ];

    // Who sits where: the NAME on the table, from the live bills.
    final tickets = ticketsQ.value ?? const <OpenTicketView>[];
    bool live(OpenTicketView tk) => tk.status == 'open' || tk.status == 'ready';
    final occupants = <String, String>{
      for (final tk in tickets)
        if (tk.tableId != null && live(tk))
          tk.tableId!: tk.ticketRef ?? tk.customerName ?? '#',
    };
    final reservations = <String, FloorReservation>{
      for (final tb in all)
        if (tb.nextBooking case final nb? when nb.status == 'confirmed')
          tb.id: (
            label: '${nb.guestName} · ${fmt.fmtTime(nb.startsAt)}',
            held: isHeldNow(
              status: nb.status,
              heldFrom: nb.heldFrom,
              now: _now,
            ),
          ),
    };
    final cap = capacityOf([
      for (final tb in visible)
        (seats: tb.seats, status: tb.status, occupant: occupants[tb.id]),
    ]);
    final selected = [
      for (final tb in visible)
        if (_selection.contains(tb.id)) tb,
    ];
    final sitting = selected.length == 1
        ? tickets
              .where((tk) => tk.tableId == selected.single.id && live(tk))
              .firstOrNull
        : null;
    _all = all;
    _visible = visible;
    _selected = selected;
    _sections = sections;

    // Frame the room once known, and again when the area (or its table
    // count) changes — never on a refetch, so panning is not fought.
    final frame = '${key ?? 'all'}:${visible.length}';
    if (visible.isNotEmpty && _framedFor != frame) {
      _framedFor = frame;
      _viewport.fitTo(visible.map(_geometry.geoOf), notify: false);
    }

    final activeSection = _activeSectionId == null
        ? null
        : sections.where((s) => s.id == _activeSectionId).firstOrNull;
    final phone = DashBreakpoints.isPhone(context);
    final loading = tablesQ.awaitingFirst || sectionsQ.awaitingFirst;

    final canvas = Stack(
      children: [
        Positioned.fill(
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(Space.md),
                  child: DashSkeleton(height: double.infinity),
                )
              : visible.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(Space.xl),
                    child: DashEmptyState(
                      framed: false,
                      icon: 'armchair',
                      title: t(
                        _editable ? 'floor.emptyEditing' : 'floor.empty',
                      ),
                      action: _editable
                          ? DashButton(
                              label: t('floor.addTable'),
                              icon: 'plus',
                              onPressed: _addTable,
                            )
                          : null,
                    ),
                  ),
                )
              : FloorCanvas(
                  tables: visible,
                  geoOf: _geometry.geoOf,
                  occupants: occupants,
                  reservations: reservations,
                  selection: _selection,
                  onSelectionChange: _setSelection,
                  editable: _editable,
                  viewport: _viewport,
                  beginGesture: _geometry.beginGesture,
                  onGeoChange: _geometry.setGeo,
                  onTableIntent: (id) =>
                      ref.warm(floorTableHistoryProvider(id)),
                ),
        ),
        PositionedDirectional(
          start: Space.md,
          end: Space.md,
          bottom: Space.md,
          child: IgnorePointer(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                _Overlay(child: _StatusLegend(t: t)),
                _Overlay(
                  child: Text(
                    t(
                          'floor.capacity',
                          args: {
                            'free': fmt.fmtNumber(cap.free),
                            'seats': fmt.fmtNumber(cap.seats),
                          },
                        ) +
                        (cap.dirty > 0
                            ? ' · ${t('floor.needsClearingCount', count: cap.dirty)}'
                            : ''),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final aside = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FloorInspector(
          tables: selected,
          sections: sections,
          editable: _editable,
          geoOf: _geometry.geoOf,
          onRotate: _rotate,
          customers: customers,
          adoptToken: _geometry.adoptToken,
          sittingNow: sitting,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.hairline)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: TransferQueue(
              transfers: transfersQ.value?.transfers ?? const <TransferView>[],
              tables: all,
              sections: sections,
            ),
          ),
        ),
      ],
    );

    final toolbar = _editable ? _toolbar(t, c) : null;
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.xxl),
        border: Border.all(color: c.hairline),
      ),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?toolbar,
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.45,
                  child: canvas,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.hairline)),
                  ),
                  child: aside,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?toolbar,
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: canvas),
                      Container(
                        width: _asideWidth,
                        decoration: BoxDecoration(
                          border: BorderDirectional(
                            start: BorderSide(color: c.hairline),
                          ),
                        ),
                        child: SingleChildScrollView(child: aside),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );

    return DashPageScaffold(
      title: t('floor.title'),
      fillBody: !phone,
      actions: [
        if (_editable && _geometry.saveState != FloorSaveState.idle)
          _SaveIndicator(state: _geometry.saveState, t: t),
        DashIconButton(
          icon: 'minus',
          semanticLabel: t('floor.zoomOut'),
          onPressed: () => _viewport.zoomBy(1 / kZoomStep),
        ),
        DashIconButton(
          icon: 'maximize-2',
          semanticLabel: t('floor.fit'),
          onPressed: _fit,
        ),
        DashIconButton(
          icon: 'plus',
          semanticLabel: t('floor.zoomIn'),
          onPressed: () => _viewport.zoomBy(kZoomStep),
        ),
        Semantics(
          toggled: _editable,
          child: DashButton(
            key: const ValueKey('floor-lock'),
            label: t(_editable ? 'floor.editing' : 'floor.locked'),
            icon: _editable ? 'lock-open' : 'lock',
            variant: _editable
                ? DashButtonVariant.primary
                : DashButtonVariant.outline,
            onPressed: () => setState(() => _editable = !_editable),
          ),
        ),
      ],
      filters: _chips(t, sections, all, activeSection),
      body: card,
    );
  }

  /// The area chips: All, each section, Unassigned when a table has none;
  /// editing adds "+ Area" and the selected area's menu.
  Widget _chips(
    Translator t,
    List<FloorSection> sections,
    List<FloorTable> all,
    FloorSection? active,
  ) => Wrap(
    spacing: Space.xs + 2,
    runSpacing: Space.xs + 2,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      _AreaChip(
        label: t('floor.allAreas'),
        active: _sectionKey == null,
        onTap: () => setState(() => _sectionKey = null),
      ),
      for (final s in sections)
        _AreaChip(
          label: s.name,
          active: _sectionKey == s.id,
          onTap: () => setState(() => _sectionKey = s.id),
        ),
      if (all.any((tb) => tb.sectionId == null))
        _AreaChip(
          label: t('floor.unassigned'),
          active: _sectionKey == _unassigned,
          onTap: () => setState(() => _sectionKey = _unassigned),
        ),
      if (_editable)
        _AreaChip(
          label: t('floor.addSection'),
          icon: 'plus',
          active: false,
          onTap: () => _editSection(null),
        ),
      if (_editable && active != null)
        DashMenu(
          align: DashPopoverAlign.start,
          items: [
            DashMenuItem(
              label: t('floor.renameSection'),
              icon: 'pencil',
              onSelected: () => _editSection(active),
            ),
            DashMenuItem(
              label: t('common.delete'),
              icon: 'trash-2',
              destructive: true,
              onSelected: () => _removeSection(active),
            ),
          ],
          builder: (context, m) => DashIconButton(
            icon: 'chevron-down',
            semanticLabel: t('floor.sectionActions'),
            iconSize: IconSize.xs,
            onPressed: m.toggle,
          ),
        ),
    ],
  );

  Widget _toolbar(Translator t, MadarColors c) {
    final n = _selection.length;
    Widget divider() => Container(
      width: 1,
      height: Space.lg,
      margin: const EdgeInsets.symmetric(horizontal: Space.xs),
      color: c.border,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs + 2,
      ),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.xs,
              children: [
                DashButton(
                  label: t('floor.addTable'),
                  icon: 'plus',
                  size: DashButtonSize.compact,
                  variant: DashButtonVariant.ghost,
                  onPressed: _addTable,
                ),
                divider(),
                DashIconButton(
                  icon: 'undo-2',
                  semanticLabel: t('floor.undo'),
                  onPressed: _geometry.canUndo ? _geometry.undo : null,
                ),
                DashIconButton(
                  icon: 'redo-2',
                  semanticLabel: t('floor.redo'),
                  onPressed: _geometry.canRedo ? _geometry.redo : null,
                ),
                divider(),
                DashIconButton(
                  icon: 'align-horizontal-justify-center',
                  semanticLabel: t('floor.alignH'),
                  onPressed: n < 2
                      ? null
                      : () => _align(FloorAlignment.hcenter),
                ),
                DashIconButton(
                  icon: 'align-vertical-justify-center',
                  semanticLabel: t('floor.alignV'),
                  onPressed: n < 2
                      ? null
                      : () => _align(FloorAlignment.vcenter),
                ),
                // The web's face is the character "⇹", which the app's
                // fonts lack: the same arrows as a glyph.
                DashIconButton(
                  icon: 'arrow-left-right',
                  semanticLabel: t('floor.spaceH'),
                  onPressed: n < 3 ? null : _distribute,
                ),
                divider(),
                DashIconButton(
                  icon: 'copy',
                  semanticLabel: t('floor.copy'),
                  onPressed: n == 0 ? null : () => unawaited(_copy()),
                ),
                DashIconButton(
                  icon: 'trash-2',
                  semanticLabel: t('common.delete'),
                  onPressed: n == 0
                      ? null
                      : () => unawaited(_deleteSelection()),
                ),
              ],
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= DashBreakpoints.lg)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Space.sm),
              child: Text(
                t('floor.hint'),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// An area chip: filled when it is the active filter (`aria-current`).
class _AreaChip extends StatelessWidget {
  const _AreaChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      selected: active,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) {
        final fg = active
            ? c.textOnAccent
            : (s.highlighted ? c.textPrimary : c.textSecondary);
        return Container(
          height: DashMetrics.target,
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          foregroundDecoration: dashFocusRing(
            context,
            s,
            BorderRadius.circular(Radii.pill),
          ),
          decoration: BoxDecoration(
            color: active ? c.accent : (s.highlighted ? c.hover : c.card),
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: active ? c.accent : c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              if (icon != null) DashIcon(icon!, size: IconSize.xs, color: fg),
              Text(label, style: DashType.bodyMedium.copyWith(color: fg)),
            ],
          ),
        );
      },
    );
  }
}

/// A card over the canvas's bottom edge (the legend, the capacity).
class _Overlay extends StatelessWidget {
  const _Overlay({required this.child});

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
        border: Border.all(color: c.hairline),
      ),
      child: child,
    );
  }
}

/// Available, Reserved, Seated, Needs clearing — each with its ring and
/// glyph, never colour alone (`status-legend.tsx`).
class _StatusLegend extends StatelessWidget {
  const _StatusLegend({required this.t});

  final Translator t;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Wrap(
      spacing: Space.lg,
      runSpacing: Space.xs,
      children: [
        for (final tone in TableTone.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs + 2,
            children: [
              Container(
                width: Space.md,
                height: Space.md,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: toneColor(c, tone).withValues(alpha: 0.18),
                  border: Border.all(color: toneColor(c, tone), width: 2),
                ),
              ),
              if (toneIcon(tone) case final icon?)
                DashIcon(icon, size: Space.md, color: toneColor(c, tone)),
              Text(
                t('floor.tone_${tone.name}'),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ],
          ),
      ],
    );
  }
}

/// Autosave's answer to "did that save?" (`SaveIndicator`, a status line):
/// the words hide on a phone, the glyph stays.
class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.state, required this.t});

  final FloorSaveState state;
  final Translator t;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final failed =
        state == FloorSaveState.conflict || state == FloorSaveState.error;
    final (text, tone) = switch (state) {
      FloorSaveState.pending ||
      FloorSaveState.saving => (t('floor.saving'), c.textSecondary),
      FloorSaveState.saved => (t('floor.saved'), c.textSecondary),
      _ => (t('floor.notSaved'), c.danger),
    };
    final busy =
        state == FloorSaveState.pending || state == FloorSaveState.saving;
    final narrow = MediaQuery.sizeOf(context).width < DashBreakpoints.sm;
    return Semantics(
      liveRegion: true,
      label: text,
      child: SizedBox(
        height: DashMetrics.target,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            if (busy)
              MadarSpinner(size: Space.md, color: tone)
            else
              DashIcon(
                failed ? 'cloud-off' : 'check',
                size: Space.md,
                color: tone,
              ),
            if (!narrow)
              ExcludeSemantics(
                child: Text(text, style: DashType.small.copyWith(color: tone)),
              ),
          ],
        ),
      ),
    );
  }
}
