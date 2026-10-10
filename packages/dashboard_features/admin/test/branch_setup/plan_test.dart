// The plan's pure rules (the web's `plan.test.ts`), plus the draft.
import 'package:dashboard_admin/src/branch_setup/inspector.dart' show parsePort;
import 'package:dashboard_admin/src/branch_setup/plan.dart';
import 'package:dashboard_admin/src/branch_setup/plan_draft.dart';
import 'package:flutter_test/flutter_test.dart';

const SetupNames names = (
  till: 'Till 1',
  receiptPrinter: 'Receipt printer',
  kitchen: 'Kitchen',
  kitchenPrinter: 'Kitchen printer',
  kitchenScreen: 'Kitchen screen',
  sectionA: 'Hot',
  sectionB: 'Cold',
  screenA: 'Hot screen',
  screenB: 'Cold screen',
);

String Function() seq() {
  var n = 0;
  return () => 'id-${++n}';
}

PieceRef dev(String id) => PieceRef(PieceKind.device, id);
PieceRef prn(String id) => PieceRef(PieceKind.printer, id);
PieceRef sec(String id) => PieceRef(PieceKind.section, id);

void main() {
  group('the four setups', () {
    test('ADM-BSU-033 each starts with no blocking problem and reads back as '
        'itself', () {
      for (final setup in Setup.values) {
        final plan = planForSetup(setup, names, ['c1', 'c2'], seq());
        final blocking = [
          for (final p in checkPlan(plan))
            if (p.blocking) p.code,
        ];
        expect(
          blocking,
          setup == Setup.tillPrinter ? [ProblemCode.printerNoAddress] : isEmpty,
        );
        expect(setupOf(plan), setup);
      }
    });

    test('ADM-BSU-033 cases 2 and 3 are one section holding every category; '
        'till only prints chits', () {
      final plan = planForSetup(Setup.tillScreen, names, ['c1', 'c2'], seq());
      expect(plan.sections, hasLength(1));
      expect(plan.sections.single.categoryIds, ['c1', 'c2']);
      expect(plan.sections.single.isDefault, isTrue);
      expect(unroutedCategories(plan, ['c1', 'c2', 'c3']), ['c3']);
      final till = planForSetup(Setup.till, names, const [], seq());
      expect(till.tillPrintsKitchen, isTrue);
      expect(till.printers.single.connection, 'usb');
      expect(till.printers.single.hostDeviceId, till.devices.single.id);
      expect(till.printers.single.paperMm, 80);
    });

    test('ADM-BSU-046 an empty plan is no setup yet; the setup a plan reads '
        'as', () {
      expect(setupOf(BuilderPlan.empty), isNull);
      final sections = planForSetup(Setup.sections, names, const [], seq());
      expect(setupOf(sections), Setup.sections);
      final one = planForSetup(Setup.tillScreen, names, const [], seq());
      // One section with a screen and a printer reads as sections.
      final both = one.mapSections((s) => s.copyWith(printerIds: ['p']));
      expect(setupOf(both), Setup.sections);
    });
  });

  group('links', () {
    final plan = planForSetup(Setup.sections, names, const [], seq());
    final hot = plan.sections.first;
    final till = plan.devices.firstWhere((d) => d.kind == 'pos');
    final receipt = plan.printers.firstWhere((p) => p.role == 'receipt');
    final screen = plan.devices.firstWhere((d) => d.kind == 'kitchen');

    test('ADM-BSU-042 only connects pieces that make sense together', () {
      expect(linkKindFor(plan, sec(hot.id), dev(till.id)), isNull);
      expect(
        linkKindFor(plan, dev(till.id), prn(receipt.id)),
        LinkKind.receipt,
      );
      expect(linkKindFor(plan, dev(screen.id), sec(hot.id)), LinkKind.shows);
      // A USB receipt printer dragged onto a POS is "plugged into".
      expect(linkKindFor(plan, prn(receipt.id), dev(till.id)), LinkKind.host);
      expect(identical(addLink(plan, sec(hot.id), dev(till.id)), plan), isTrue);
    });

    test('ADM-BSU-043 removing a link drops every copy of it', () {
      final twice = plan.mapSections(
        (s) => s.id == hot.id
            ? s.copyWith(
                screenIds: [screen.id, screen.id],
                printerIds: ['p', 'p'],
              )
            : s,
      );
      var next = removeLink(
        twice,
        PlanLink(LinkKind.shows, sec(hot.id), dev(screen.id)),
      );
      next = removeLink(next, PlanLink(LinkKind.prints, sec(hot.id), prn('p')));
      expect(next.sections.first.screenIds, isEmpty);
      expect(next.sections.first.printerIds, isEmpty);
    });

    test('ADM-BSU-042 adding twice is one link; a receipt link replaces the '
        'previous', () {
      final withPrinter = plan.copyWith(
        printers: [
          ...plan.printers,
          const BuilderPrinter(
            id: 'kp',
            role: 'kitchen',
            name: 'KP',
            connection: 'network',
            ip: '10.0.0.9',
            paperMm: 80,
            x: 0,
            y: 0,
          ),
          const BuilderPrinter(
            id: 'rp2',
            role: 'receipt',
            name: 'R2',
            connection: 'network',
            ip: '10.0.0.8',
            paperMm: 80,
            x: 0,
            y: 0,
          ),
        ],
      );
      var next = addLink(withPrinter, sec(hot.id), prn('kp'));
      next = addLink(next, prn('kp'), sec(hot.id));
      expect(next.sections.first.printerIds, ['kp']);
      expect(
        linksOf(next).where((l) => l.kind == LinkKind.prints),
        hasLength(1),
      );
      next = addLink(next, dev(till.id), prn('rp2'));
      expect(next.device(till.id)!.receiptPrinterId, 'rp2');
    });

    test('ADM-BSU-030 removing a piece removes every line to it and keeps one '
        'catch-all', () {
      final next = removePieces(plan, {hot.key(), prn(receipt.id).key});
      expect(next.sections, hasLength(1));
      expect(next.sections.single.isDefault, isTrue);
      expect(next.device(till.id)!.receiptPrinterId, isNull);
      expect(
        linksOf(next).any((l) => l.to.id == hot.id || l.from.id == hot.id),
        isFalse,
      );
    });
  });

  group('checks', () {
    test('ADM-BSU-049 a section with nowhere to send orders blocks saving', () {
      final plan = planForSetup(
        Setup.tillScreen,
        names,
        const [],
        seq(),
      ).mapSections((s) => s.copyWith(screenIds: const []));
      final p = checkPlan(
        plan,
      ).firstWhere((p) => p.code == ProblemCode.sectionNoOutput);
      expect(p.blocking, isTrue);
    });

    test('ADM-BSU-049 a plugged-in printer with no device blocks; a POS with '
        'no receipt printer only warns', () {
      final plan = planForSetup(Setup.till, names, const [], seq())
          .mapPrinters((p) => p.copyWith(hostDeviceId: () => null))
          .mapDevices((d) => d.copyWith(receiptPrinterId: () => null));
      final codes = [for (final p in checkPlan(plan)) (p.code, p.blocking)];
      expect(codes, contains((ProblemCode.printerNoHost, true)));
      expect(codes, contains((ProblemCode.posNoReceiptPrinter, false)));
    });

    test('ADM-BSU-049 blocking problems first; names compared trimmed and '
        'case-blind', () {
      final plan = planForSetup(Setup.sections, names, const [], seq())
          .mapSections(
            (s) => s.isDefault
                ? s.copyWith(name: ' hot ')
                : s.copyWith(name: 'HOT', screenIds: const []),
          );
      final problems = checkPlan(plan);
      expect(problems.first.blocking, isTrue);
      expect(problems.last.blocking, isFalse);
      expect(
        problems.where((p) => p.code == ProblemCode.sectionDuplicateName),
        hasLength(2),
      );
    });

    test('ADM-BSU-049 takes a printer address the server takes, and no '
        'other', () {
      for (final ip in [
        '192.168.1.40',
        '10.0.0.0',
        '255.255.255.255',
        ' 172.16.5.9 ',
      ]) {
        expect(isIpv4(ip), isTrue, reason: ip);
      }
      for (final ip in [
        '192.168.1.05',
        '01.2.3.4',
        '256.1.1.1',
        '1.2.3',
        'printer.local',
        '',
      ]) {
        expect(isIpv4(ip), isFalse, reason: ip);
      }
    });

    test('ADM-BSU-062 a port that is not a whole number 1–65535 is 9100', () {
      expect(parsePort('9101'), 9101);
      expect(parsePort('9100abc'), 9100);
      expect(parsePort('81x'), 81);
      expect(parsePort('0'), 9100);
      expect(parsePort('70000'), 9100);
      expect(parsePort(''), 9100);
    });
  });

  group('routing and changes', () {
    test('ADM-BSU-069 a category lives in one section; select all takes them '
        'all and clears them again', () {
      final plan = planForSetup(Setup.sections, names, ['c1', 'c2'], seq());
      final [hot, cold] = plan.sections;
      final next = routeCategory(plan, 'c1', cold.id);
      expect(next.section(hot.id)!.categoryIds, ['c2']);
      expect(next.section(cold.id)!.categoryIds, ['c1']);
      final all = routeCategories(plan, ['c1', 'c2', 'c3'], cold.id);
      expect(all.section(cold.id)!.categoryIds, ['c1', 'c2', 'c3']);
      expect(all.section(hot.id)!.categoryIds, isEmpty);
      final none = routeCategories(all, ['c1', 'c2', 'c3'], null);
      expect(none.sections.every((s) => s.categoryIds.isEmpty), isTrue);
    });

    test('ADM-BSU-073 moving a piece is not a change worth reviewing; '
        'renaming one is', () {
      final plan = planForSetup(Setup.till, names, const [], seq());
      final moved = plan.mapDevices((d) => d.copyWith(x: 500));
      final diff = diffPlans(plan, moved);
      expect(diff.added, isEmpty);
      expect(diff.removed, isEmpty);
      expect(diff.changed, isEmpty);
      final renamed = plan.mapDevices((d) => d.copyWith(name: 'Front till'));
      expect(diffPlans(plan, renamed).changed, [dev(plan.devices.single.id)]);
    });

    test('ADM-BSU-075 the routing a plan implies', () {
      final till = planForSetup(Setup.till, names, const [], seq());
      expect(routingModeFor(till), 'till');
      expect(routingModeFor(till.copyWith(tillPrintsKitchen: false)), 'off');
      final printer = planForSetup(Setup.tillPrinter, names, const [], seq());
      expect(routingModeFor(printer), 'till');
      final screen = planForSetup(Setup.tillScreen, names, const [], seq());
      expect(routingModeFor(screen), 'kds');
      expect(routingModeFor(screen.copyWith(tillPrintsKitchen: true)), 'both');
    });
  });

  test('ADM-BSU-006/089 names the server gives read in the reader\'s words; '
      'only the server\'s own names change', () {
    final base = planForSetup(Setup.tillPrinter, names, const [], seq());
    final kp = base.printers.firstWhere((p) => p.role == 'kitchen');
    final hot = base.sections.single;
    final plan = base.mapPrinters(
      (p) => p.id == kp.id ? p.copyWith(name: '${hot.name} printer') : p,
    );
    final ar = localizeServerNames(plan, 'طابعة الإيصالات', (s) => 'طابعة $s');
    expect(
      ar.printers.firstWhere((p) => p.role == 'receipt').name,
      'طابعة الإيصالات',
    );
    expect(ar.printer(kp.id)!.name, 'طابعة ${hot.name}');
    expect(
      identical(
        localizeServerNames(plan, 'Receipt printer', (s) => '$s printer'),
        plan,
      ),
      isTrue,
    );
    final typed = plan.mapPrinters(
      (p) => p.role == 'receipt' ? p.copyWith(name: 'Front desk') : p,
    );
    expect(
      localizeServerNames(
        typed,
        'x',
        (s) => s,
      ).printers.firstWhere((p) => p.role == 'receipt').name,
      'Front desk',
    );
  });

  test('ADM-BSU-078 the wire: names trimmed, a network printer sends its '
      'trimmed IP and port, a plugged-in one neither', () {
    final plan = planForSetup(Setup.tillPrinter, names, const [], seq())
        .mapPrinters(
          (p) => p.role == 'kitchen'
              ? p.copyWith(
                  name: ' KP ',
                  ip: () => ' 10.0.0.9 ',
                  port: () => null,
                )
              : p.copyWith(ip: () => '1.2.3.4', port: () => 9100),
        );
    final wire = toWire(plan).toJson();
    final printers = (wire['printers']! as List).cast<Map<String, Object?>>();
    final kp = printers.firstWhere((p) => p['role'] == 'kitchen');
    expect(kp['name'], 'KP');
    expect(kp['ip'], '10.0.0.9');
    expect(kp['port'], 9100);
    final usb = printers.firstWhere((p) => p['role'] == 'receipt');
    expect(usb['ip'], isNull);
    expect(usb['port'], isNull);
    expect(usb['host_device_id'], isNotNull);
  });

  group('the draft', () {
    test('ADM-BSU-018/022/029 edits collect with undo; a clean draft follows '
        'a newer plan and drops its undo steps', () {
      final saved = planForSetup(Setup.till, names, const [], seq());
      final d = PlanDraft()..receive(saved, 1);
      expect(d.dirty, isFalse);
      d.change((p) => p.mapDevices((x) => x.copyWith(name: 'A')));
      expect(d.dirty, isTrue);
      expect(d.canUndo, isTrue);
      d.undo();
      expect(d.dirty, isFalse);
      expect(d.canRedo, isTrue);
      d.redo();
      expect(d.plan!.devices.single.name, 'A');
      d.undo();
      final newer = saved.mapDevices((x) => x.copyWith(name: 'B'));
      d.receive(newer, 2);
      expect(d.plan!.devices.single.name, 'B');
      expect(d.canUndo, isFalse);
      expect(d.canRedo, isFalse);
      expect(d.baseVersion, 2);
    });

    test('ADM-BSU-021 a dirty draft keeps its changes when overtaken, until '
        'discarded', () {
      final saved = planForSetup(Setup.till, names, const [], seq());
      final d = PlanDraft()..receive(saved, 1);
      d.change((p) => p.mapDevices((x) => x.copyWith(name: 'Mine')));
      d.receive(saved.mapDevices((x) => x.copyWith(name: 'Theirs')), 2);
      expect(d.overtaken, isTrue);
      expect(d.plan!.devices.single.name, 'Mine');
      expect(d.baseVersion, 1);
      d.discard();
      expect(d.plan!.devices.single.name, 'Theirs');
      expect(d.overtaken, isFalse);
      expect(d.baseVersion, 2);
    });

    test('ADM-BSU-029 at most 100 undo steps; a drag is one', () {
      final d = PlanDraft()
        ..receive(planForSetup(Setup.till, names, const [], seq()), 1);
      for (var i = 0; i < 120; i++) {
        d.change((p) => p.mapDevices((x) => x.copyWith(x: i.toDouble())));
      }
      var n = 0;
      while (d.canUndo) {
        d.undo();
        n++;
      }
      expect(n, kHistoryLimit);
      final g = PlanDraft()
        ..receive(planForSetup(Setup.till, names, const [], seq()), 1);
      g.beginGesture();
      for (var i = 0; i < 5; i++) {
        g.live((p) => p.mapDevices((x) => x.copyWith(x: i * 10.0)));
      }
      g.undo();
      expect(g.canUndo, isFalse);
      expect(g.plan!.devices.single.x, 0);
    });
  });
}

extension on BuilderSection {
  String key() => pieceKey(PieceKind.section, id);
}
