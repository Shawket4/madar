// Renders the v2 kit to PNG so a change to it can be LOOKED at.
//
// There is no simulator on the machines this repo is usually worked on, and a
// button is not a thing you can review by reading its widget tree. Set
// MADAR_RENDER=true and the test writes `build/render/*.png`: the kit board in
// both themes, the tablet shell at the iPad's 1194 × 834 in both themes, and
// the phone shell at 390 × 844 in Arabic, mirrored. Left unset it still builds
// every board and fails on any layout exception, which is the part CI cares
// about.
//
// The strings in here are fixture text, not app strings; the app's own words
// come through `bridge.tr`.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

/// The iPad, landscape — the primary target.
const Size _ipad = Size(1194, 834);

/// A phone — the real fallback.
const Size _phone = Size(390, 844);

// ── The kit board ──────────────────────────────────────────────────────

Widget _section(String label, Widget child) => Padding(
  padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MadarSectionHeader(text: label),
      const SizedBox(height: Space.md),
      child,
    ],
  ),
);

Widget _wrap(List<Widget> children) => Wrap(
  spacing: Space.md,
  runSpacing: Space.md,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: children,
);

class _KitBoard extends StatefulWidget {
  const _KitBoard();

  @override
  State<_KitBoard> createState() => _KitBoardState();
}

class _KitBoardState extends State<_KitBoard> {
  final _name = TextEditingController(text: 'Sara');
  final _search = TextEditingController();
  final _focused = TextEditingController(text: 'Omar');
  final _focus = FocusNode();
  var _segment = 'plan';
  var _qty = 2;

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    _focused.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    void noop() {}
    return ColoredBox(
      color: colors.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(Space.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Madar POS · system v2',
              style: MadarType.h1.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: Space.xl),
            _section(
              'Buttons — 56 regular · 44 small · 64 money bar',
              _wrap([
                MadarButton(label: 'Primary', onTap: noop),
                MadarButton(
                  label: 'Secondary',
                  variant: MadarButtonVariant.secondary,
                  onTap: noop,
                ),
                MadarButton(
                  label: 'Ghost',
                  variant: MadarButtonVariant.ghost,
                  onTap: noop,
                ),
                MadarButton(
                  label: 'Danger',
                  variant: MadarButtonVariant.danger,
                  onTap: noop,
                ),
                MadarButton(
                  label: 'Ink',
                  variant: MadarButtonVariant.ink,
                  onTap: noop,
                ),
                MadarButton(
                  label: 'Print',
                  glyph: MadarGlyph.printer,
                  variant: MadarButtonVariant.secondary,
                  onTap: noop,
                ),
                MadarButton(label: 'Working', loading: true, onTap: noop),
                MadarButton(label: 'Disabled', enabled: false, onTap: noop),
                MadarButton(
                  label: 'Accept',
                  size: MadarButtonSize.compact,
                  onTap: noop,
                ),
                MadarButton(
                  label: 'Decline',
                  size: MadarButtonSize.compact,
                  variant: MadarButtonVariant.secondary,
                  onTap: noop,
                ),
                MadarButton(
                  label: '',
                  glyph: MadarGlyph.more,
                  size: MadarButtonSize.compact,
                  variant: MadarButtonVariant.secondary,
                  onTap: noop,
                ),
                MadarGlyphTile(glyph: MadarGlyph.close, onTap: noop),
                MadarGlyphTile(
                  glyph: MadarGlyph.chevronBack,
                  size: MadarButtonSize.regular,
                  onTap: noop,
                ),
              ]),
            ),
            _section(
              'Money bar',
              Row(
                spacing: Space.md,
                children: [
                  SizedBox(
                    width: 560,
                    child: MadarMoneyBar(
                      label: 'Charge',
                      amountMinor: 19600,
                      currency: 'EGP',
                      onTap: noop,
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: MadarMoneyBar(
                      label: 'Charge',
                      amountMinor: 19600,
                      currency: 'EGP',
                      enabled: false,
                      reason: 'Open the shift first',
                      onTap: noop,
                    ),
                  ),
                ],
              ),
            ),
            _section(
              'Chips, segments, fields',
              _wrap([
                MadarChip(label: 'All', selected: true, onTap: noop),
                MadarChip(label: 'Hot', onTap: noop),
                MadarChip(
                  label: 'Parked',
                  glyph: MadarGlyph.bag,
                  count: 2,
                  onTap: noop,
                ),
                SizedBox(
                  width: 240,
                  child: MadarSegmented<String>(
                    items: const [
                      MadarSegmentItem('plan', 'Plan'),
                      MadarSegmentItem('list', 'List'),
                    ],
                    value: _segment,
                    onChanged: (v) => setState(() => _segment = v),
                  ),
                ),
                SizedBox(
                  width: 380,
                  child: MadarSegmented<int>(
                    items: const [
                      MadarSegmentItem(0, 'Bills', count: 3),
                      MadarSegmentItem(1, 'Online', count: 2),
                      MadarSegmentItem(2, 'Kitchen'),
                    ],
                    value: 0,
                    onChanged: (_) {},
                  ),
                ),
                MadarChip.tile(label: '15', onTap: noop),
                MadarChip.tile(label: '20', selected: true, onTap: noop),
                MadarChip.tile(label: '30', onTap: noop),
                MadarStepper(
                  value: _qty,
                  onChanged: (v) => setState(() => _qty = v),
                ),
                SizedBox(
                  width: 260,
                  child: MadarField(
                    controller: _search,
                    placeholder: 'Search',
                    glyph: MadarGlyph.search,
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: MadarField(
                    controller: _name,
                    placeholder: 'Guest name',
                    glyph: MadarGlyph.user,
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: MadarField(
                    controller: _focused,
                    placeholder: 'Guest name',
                    glyph: MadarGlyph.user,
                    focusNode: _focus,
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: MadarAmountField(
                    amountMinor: 85000,
                    currencyCode: 'egp',
                    onAmountMinor: (_) {},
                  ),
                ),
              ]),
            ),
            _section(
              'State — the outbox pill, tags, badges, the person',
              _wrap([
                const MadarOutboxPill(
                  state: OutboxState.synced,
                  label: 'Synced',
                ),
                const MadarOutboxPill(
                  state: OutboxState.queued,
                  count: 3,
                  label: 'queued',
                ),
                const MadarOutboxPill(
                  state: OutboxState.offline,
                  count: 3,
                  label: 'Offline',
                ),
                const MadarOutboxPill(
                  state: OutboxState.stuck,
                  count: 1,
                  label: 'stuck',
                ),
                const SizedBox(width: Space.md),
                const MadarTag(
                  label: 'New',
                  tone: MadarTone.accent,
                  glyph: MadarGlyph.full,
                ),
                const MadarTag(
                  label: 'Ready',
                  tone: MadarTone.success,
                  glyph: MadarGlyph.check,
                ),
                const MadarTag(
                  label: 'Queued',
                  tone: MadarTone.warning,
                  glyph: MadarGlyph.half,
                ),
                const MadarTag(
                  label: 'Voided',
                  tone: MadarTone.danger,
                  glyph: MadarGlyph.close,
                ),
                const MadarTag(label: 'Parked'),
                const SizedBox(width: Space.md),
                const MadarBadge(count: 2),
                const MadarBadge(count: 14),
                const MadarAvatar(
                  person: MadarPerson(name: 'Sara', initial: 'S'),
                ),
                const MadarAvatar(
                  person: MadarPerson(
                    name: 'Sara',
                    initial: 'S',
                    online: false,
                  ),
                ),
              ]),
            ),
            _section(
              'Card and rows — 64px, the state bar carries the colour',
              MadarCard(
                flush: true,
                child: Column(
                  children: [
                    MadarRow(
                      title: 'T5 · Bill T-0412',
                      subtitle: '4 covers · Sara · 42m',
                      bar: colors.success,
                      value: const MoneyText(19600, currency: 'EGP'),
                      onTap: noop,
                    ),
                    const MadarHairline.row(),
                    MadarRow(
                      title: 'T2 · Round 3 queued',
                      subtitle: '18m',
                      bar: colors.warning,
                      trailing: const MadarTag(
                        label: 'Queued',
                        tone: MadarTone.warning,
                        glyph: MadarGlyph.half,
                      ),
                      onTap: noop,
                    ),
                    const MadarHairline.row(),
                    MadarRow(
                      title: 'Charge T-0410 · 19:12',
                      subtitle: 'Ticket is already settled',
                      bar: colors.danger,
                      trailing: Row(
                        spacing: Space.sm,
                        children: [
                          MadarButton(
                            label: 'Retry',
                            size: MadarButtonSize.compact,
                            variant: MadarButtonVariant.secondary,
                            onTap: noop,
                          ),
                          MadarButton(
                            label: 'Discard',
                            size: MadarButtonSize.compact,
                            variant: MadarButtonVariant.danger,
                            onTap: noop,
                          ),
                        ],
                      ),
                    ),
                    const MadarHairline.row(),
                    MadarRow(
                      title: 'Pay out',
                      subtitle: 'Supplier · Sara 19:40',
                      glyph: MadarGlyph.arrowDownStart,
                      value: MoneyText(
                        -6000,
                        currency: 'EGP',
                        color: colors.danger,
                      ),
                    ),
                    const MadarHairline.row(),
                    MadarRow(
                      title: 'Language',
                      glyph: MadarGlyph.globe,
                      value: Text(
                        'English',
                        style: MadarType.body.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      onTap: noop,
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),
            _section(
              'Glyphs — 24 grid, 2.5 stroke · outline, then filled',
              Wrap(
                spacing: Space.md,
                runSpacing: Space.md,
                children: [
                  for (final g in MadarGlyph.values)
                    SizedBox(
                      width: 88,
                      child: Column(
                        spacing: Space.xs,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: Space.sm,
                            children: [
                              MadarGlyphIcon(g, size: IconSize.xxl),
                              MadarGlyphIcon(
                                g,
                                size: IconSize.xxl,
                                filled: true,
                                color: colors.accent,
                              ),
                            ],
                          ),
                          Text(
                            g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MadarType.labelSm.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
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

// ── The shells ─────────────────────────────────────────────────────────

const _tellerTabs = [
  MadarTab(label: 'Sell', glyph: MadarGlyph.bag),
  MadarTab(label: 'Floor', glyph: MadarGlyph.grid),
  MadarTab(label: 'Queue', glyph: MadarGlyph.inbox, badge: 2),
  MadarTab(label: 'Till', glyph: MadarGlyph.wallet),
];

const _waiterTabsAr = [
  MadarTab(label: 'الصالة', glyph: MadarGlyph.grid),
  MadarTab(label: 'الفواتير', glyph: MadarGlyph.receipt, badge: 2),
  MadarTab(label: 'أنا', glyph: MadarGlyph.user),
];

/// A Sell page in the shape of the canvas's: header, chips, a tile grid,
/// and the cart column with the money bar.
class _SellBody extends StatelessWidget {
  const _SellBody();

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final search = TextEditingController();
    final tiles = [
      ('Espresso', 3500, 0),
      ('Flat white', 5000, 1),
      ('Latte', 4500, 0),
      ('Cheesecake', 6000, 0),
      ('Croissant', 3000, 0),
      ('Iced tea', 4000, 0),
      ('Mocha', 5500, 0),
      ('Water', 1500, 0),
    ];
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MadarHeader(
                  title: 'Takeaway',
                  actions: [
                    SizedBox(
                      width: 320,
                      child: MadarField(
                        controller: search,
                        placeholder: 'Search the menu',
                        glyph: MadarGlyph.search,
                      ),
                    ),
                    MadarChip(
                      label: 'Parked',
                      glyph: MadarGlyph.bag,
                      count: 2,
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                Row(
                  spacing: Space.sm,
                  children: [
                    for (final c in ['All', 'Hot', 'Cold', 'Food', 'Bakery'])
                      MadarChip(label: c, selected: c == 'All', onTap: () {}),
                  ],
                ),
                const SizedBox(height: Space.lg),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 4,
                    mainAxisSpacing: Grid.gutter,
                    crossAxisSpacing: Grid.gutter,
                    childAspectRatio: 190 / 120,
                    children: [
                      for (final (name, price, inCart) in tiles)
                        MadarCard(
                          selected: inCart > 0,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            16,
                            14,
                            16,
                            14,
                          ),
                          onTap: () {},
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                name,
                                style: MadarType.title.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                              MoneyText(price, style: MadarType.money),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          width: Responsive.cartColumnWidth,
          decoration: BoxDecoration(
            color: colors.surface,
            border: BorderDirectional(
              start: BorderSide(color: colors.borderLight),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 8),
                child: Text(
                  'Round',
                  style: MadarType.h3.copyWith(color: colors.textPrimary),
                ),
              ),
              MadarRow(
                title: 'Flat white',
                subtitle: 'Oat milk',
                value: const MoneyText(5000),
                trailing: MadarStepper(value: 1, onChanged: (_) {}),
              ),
              const MadarHairline.row(inset: Space.card),
              MadarRow(
                title: 'Cheesecake',
                value: const MoneyText(6000),
                trailing: MadarStepper(value: 1, onChanged: (_) {}),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsetsDirectional.all(Space.card),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.md,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Total',
                          style: MadarType.title.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        MoneyText(
                          11000,
                          currency: 'EGP',
                          style: MadarType.moneyLg,
                          color: colors.textPrimary,
                        ),
                      ],
                    ),
                    MadarMoneyBar(
                      label: 'Charge',
                      amountMinor: 11000,
                      currency: 'EGP',
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The waiter's Floor list on a phone, in Arabic.
class _FloorListAr extends StatelessWidget {
  const _FloorListAr();

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MadarHeader(
            title: 'الصالة',
            actions: [
              MadarHeaderAction(glyph: MadarGlyph.calendar, onTap: () {}),
            ],
          ),
          const SizedBox(height: Space.md),
          MadarSegmented<String>(
            items: const [
              MadarSegmentItem('list', 'قائمة'),
              MadarSegmentItem('plan', 'مخطط'),
            ],
            value: 'list',
            onChanged: (_) {},
          ),
          const SizedBox(height: Space.lg),
          MadarCard(
            flush: true,
            child: Column(
              children: [
                MadarRow(
                  title: 'T5 · فاتورة T-0412',
                  subtitle: '4 أشخاص · سارة · 42 د',
                  bar: colors.success,
                  value: const MoneyText(19600),
                  onTap: () {},
                ),
                const MadarHairline.row(),
                MadarRow(
                  title: 'T2 · الجولة 3 بالانتظار',
                  subtitle: '18 د',
                  bar: colors.warning,
                  trailing: const MadarTag(
                    label: 'بالانتظار',
                    tone: MadarTone.warning,
                    glyph: MadarGlyph.half,
                  ),
                  onTap: () {},
                ),
                const MadarHairline.row(),
                MadarRow(
                  title: 'T7 · تحتاج تنظيف',
                  bar: colors.danger,
                  onTap: () {},
                ),
                const MadarHairline.row(),
                MadarRow(title: 'T1 · شاغرة', bar: colors.border, onTap: () {}),
              ],
            ),
          ),
          const Spacer(),
          MadarButton(
            label: 'فاتورة جديدة',
            glyph: MadarGlyph.plus,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

// ── Harness ────────────────────────────────────────────────────────────

Future<void> _shot(
  WidgetTester tester, {
  required Widget child,
  required ThemeData theme,
  required Size size,
  required String name,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        theme: theme,
        home: Directionality(
          textDirection: direction,
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
  // NOT pumpAndSettle: the loading button spins forever, which is the point
  // of it. Two frames is enough to lay out and paint.
  await tester.pump();
  await tester.pump(MotionSpec.standardDuration);
  // A board pumped over a previous one (light, then dark) keeps its
  // AnimatedContainers, which are still mid-transition at exactly the
  // duration; one more frame lands them.
  await tester.pump(MotionSpec.gentleDuration);
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  await _capture(tester, name);
}

/// Writes the current frame to `build/render/<name>.png` when rendering.
Future<void> _capture(WidgetTester tester, String name) async {
  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  // `toImage` completes on the real event loop; inside the binding's fake
  // async zone a later `pump` can wedge behind it. `runAsync` is the door.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/render')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _shell(List<MadarTab> tabs, Widget body, {MadarPerson? person}) =>
    MadarShellScaffold(
      tabs: tabs,
      selectedIndex: 0,
      onSelect: (_) {},
      person: person ?? const MadarPerson(name: 'Sara', initial: 'S'),
      topBar: const MadarTopBar(
        title: 'Rue Zamalek',
        subtitle: 'Till 1',
        pill: MadarOutboxPill(
          state: OutboxState.queued,
          count: 3,
          label: 'queued',
        ),
      ),
      body: body,
    );

/// Loads the package's Plex faces so the boards render real type. Without
/// this the test binding substitutes its block font and nothing about the
/// scale, the figures, or the Arabic can be judged from the picture. The
/// family name carries the package prefix because the styles do.
Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File('assets/fonts/$family-$cut.ttf');
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('the kit board lays out in light', (tester) async {
    await _shot(
      tester,
      child: const _KitBoard(),
      theme: MadarTheme.light(),
      size: const Size(1194, 1700),
      name: 'kit-light',
    );
    // The third guest-name field is focused, so the ring is in the picture.
    final focused = tester.widget<MadarField>(
      find.byWidgetPredicate(
        (w) => w is MadarField && w.controller.text == 'Omar',
      ),
    );
    focused.focusNode!.requestFocus();
    await tester.pump(MotionSpec.standardDuration);
    expect(focused.focusNode!.hasFocus, isTrue);
    await _capture(tester, 'kit-light');
  });

  testWidgets('the kit board lays out in dark', (tester) async {
    await _shot(
      tester,
      child: const _KitBoard(),
      theme: MadarTheme.dark(),
      size: const Size(1194, 1700),
      name: 'kit-dark',
    );
  });

  testWidgets('the teller shell fills an iPad, light and dark', (tester) async {
    await _shot(
      tester,
      child: _shell(_tellerTabs, const _SellBody()),
      theme: MadarTheme.light(),
      size: _ipad,
      name: 'shell-ipad-light',
    );
    expect(find.byType(MadarRail), findsOneWidget);
    expect(find.byType(MadarTabBar), findsNothing);
    await _shot(
      tester,
      child: _shell(_tellerTabs, const _SellBody()),
      theme: MadarTheme.dark(),
      size: _ipad,
      name: 'shell-ipad-dark',
    );
  });

  testWidgets('the waiter shell fits a phone in Arabic and mirrors', (
    tester,
  ) async {
    await _shot(
      tester,
      child: _shell(
        _waiterTabsAr,
        const _FloorListAr(),
        person: const MadarPerson(name: 'أحمد', initial: 'أ', online: false),
      ),
      theme: MadarTheme.light(),
      size: _phone,
      name: 'shell-phone-ar',
      direction: TextDirection.rtl,
    );
    expect(find.byType(MadarTabBar), findsOneWidget);
    expect(find.byType(MadarRail), findsNothing);
    // The back/forward chevrons flip; the rows' disclosure points at the
    // end edge, which is the LEFT in Arabic.
    final chevron = find.byWidgetPredicate(
      (w) => w is MadarGlyphIcon && w.glyph == MadarGlyph.chevronForward,
    );
    expect(chevron, findsWidgets);
    expect(
      find.descendant(of: chevron.first, matching: find.byType(Transform)),
      findsOneWidget,
    );
  });

  test('MadarLayout is decided by the shortest side', () {
    expect(MadarLayout.fromSize(const Size(1194, 834)), MadarLayout.tablet);
    expect(MadarLayout.fromSize(const Size(834, 1194)), MadarLayout.tablet);
    expect(MadarLayout.fromSize(const Size(390, 844)), MadarLayout.phone);
    // A phone turned sideways is still a phone.
    expect(MadarLayout.fromSize(const Size(844, 390)), MadarLayout.phone);
  });

  test('every glyph parses and stays on the 24 grid', () {
    for (final g in MadarGlyph.values) {
      final bounds = glyphBounds(g);
      expect(bounds.left, greaterThanOrEqualTo(0), reason: g.name);
      expect(bounds.top, greaterThanOrEqualTo(0), reason: g.name);
      expect(bounds.right, lessThanOrEqualTo(glyphGrid), reason: g.name);
      expect(bounds.bottom, lessThanOrEqualTo(glyphGrid), reason: g.name);
      expect(bounds.width, greaterThan(0), reason: '${g.name} draws nothing');
    }
  });

  test('the path interpreter handles the commands the set uses', () {
    // Implicit lineto repeats after a relative moveto, arcs, closes.
    final p = parseSvgPath('m9 18 6-6-6-6');
    expect(p.getBounds(), const Rect.fromLTRB(9, 6, 15, 18));
    final arc = parseSvgPath('M3.5 12a8.5 8.5 0 1 0 17 0a8.5 8.5 0 1 0 -17 0z');
    expect(arc.getBounds().width, closeTo(17, 0.01));
    expect(() => parseSvgPath('M0 0 T 1 1'), throwsFormatException);
  });

  testWidgets('the old SF-Symbol names route to the v2 set', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MadarTheme.light(),
        home: const Scaffold(
          body: Row(
            children: [
              MadarIcon('printer', tint: Colors.black),
              MadarIcon('chevron.forward', tint: Colors.black),
              // Not in the set: still Lucide, still draws.
              MadarIcon('cat.matcha', tint: Colors.black),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(MadarGlyphIcon), findsNWidgets(2));
    expect(find.byType(Icon), findsOneWidget);
  });

  testWidgets('a button survives an unbounded width', (tester) async {
    // A Flexible under unbounded width is illegal, and the assertion blanks
    // the whole subtree, not just the button.
    await tester.pumpWidget(
      MaterialApp(
        theme: MadarTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                MadarButton(label: 'Charge', onTap: () {}),
                MadarButton(
                  label: 'Void',
                  variant: MadarButtonVariant.danger,
                  onTap: () {},
                ),
                MadarMoneyBar(label: 'Charge', amountMinor: 100, onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a compact button with a glyph and no label stays square', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MadarTheme.light(),
        home: Scaffold(
          body: Center(
            child: MadarButton(
              label: '',
              glyph: MadarGlyph.more,
              size: MadarButtonSize.compact,
              variant: MadarButtonVariant.secondary,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(MadarButton));
    expect(size.width, Metrics.buttonSmallHeight);
    expect(size.height, Metrics.buttonSmallHeight);
  });

  test('minor units round-trip through the amount field helpers', () {
    expect(minorToText(1200), '12');
    expect(minorToText(1250), '12.50');
    expect(textToMinor('12.50'), 1250);
    expect(textToMinor('12'), 1200);
    expect(textToMinor('1,234.5'), 123450);
    expect(textToMinor('EGP 12.50'), 1250);
    expect(textToMinor(''), 0);
  });
}
