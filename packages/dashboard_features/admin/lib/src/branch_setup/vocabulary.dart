/// The builder's words and glyphs (the web's `vocabulary.ts`), so the
/// canvas, the inspector and the checks call each piece the same thing.
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'plan.dart';

const Map<String, String> deviceIcon = {
  'pos': 'monitor',
  'waiter': 'tablet-smartphone',
  'kitchen': 'layout-grid',
};

const Map<String, String> printerIcon = {
  'receipt': 'receipt-text',
  'kitchen': 'printer',
};

const String sectionIcon = 'chef-hat';

String deviceKindLabel(Translator t, String kind) => switch (kind) {
  'waiter' => t('builder.kind.waiter'),
  'kitchen' => t('builder.kind.kitchen'),
  _ => t('builder.kind.pos'),
};

String printerRoleLabel(Translator t, String role) => role == 'receipt'
    ? t('builder.kind.receiptPrinter')
    : t('builder.kind.kitchenPrinter');

String connectionLabel(Translator t, String c) => switch (c) {
  'network' || 'usb' || 'bluetooth' => t('builder.connection.$c'),
  _ => c,
};

String linkLabel(Translator t, LinkKind kind) => t('builder.link.${kind.name}');

const Map<Setup, String> _setupKey = {
  Setup.till: 'till',
  Setup.tillPrinter: 'tillPrinter',
  Setup.tillScreen: 'tillScreen',
  Setup.sections: 'sections',
};

({String title, String body}) setupLabel(Translator t, Setup s) => (
  title: t('builder.setup.${_setupKey[s]}'),
  body: t('builder.setup.${_setupKey[s]}Body'),
);

const Map<Setup, String> setupIcon = {
  Setup.till: 'receipt-text',
  Setup.tillPrinter: 'printer',
  Setup.tillScreen: 'layout-grid',
  Setup.sections: 'split',
};

/// A piece's name as the plan holds it (trimmed), for sentences about it.
String pieceName(BuilderPlan plan, PieceRef? ref) {
  if (ref == null) return '';
  final name = switch (ref.kind) {
    PieceKind.device => plan.device(ref.id)?.name,
    PieceKind.printer => plan.printer(ref.id)?.name,
    PieceKind.section => plan.section(ref.id)?.name,
  };
  return name?.trim() ?? '';
}

String problemText(Translator t, BuilderPlan plan, Problem p) {
  final n = pieceName(plan, p.piece);
  final name = n.isEmpty ? t('builder.unnamed') : n;
  final args = {'name': name};
  return switch (p.code) {
    ProblemCode.sectionNoOutput => t(
      'builder.problem.sectionNoOutput',
      args: args,
    ),
    ProblemCode.sectionNoName => t('builder.problem.sectionNoName'),
    ProblemCode.sectionDuplicateName => t(
      'builder.problem.sectionDuplicate',
      args: args,
    ),
    ProblemCode.noDefaultSection => t('builder.problem.noDefault'),
    ProblemCode.printerNoHost => t('builder.problem.printerNoHost', args: args),
    ProblemCode.printerNoAddress => t(
      'builder.problem.printerNoAddress',
      args: args,
    ),
    ProblemCode.pieceNoName => t('builder.problem.pieceNoName'),
    ProblemCode.posNoReceiptPrinter => t(
      'builder.problem.posNoReceipt',
      args: args,
    ),
    ProblemCode.screenNoSection => t(
      'builder.problem.screenNoSection',
      args: args,
    ),
    ProblemCode.kitchenPrinterUnused => t(
      'builder.problem.printerUnused',
      args: args,
    ),
    ProblemCode.noPos => t('builder.problem.noPos'),
  };
}

/// The kitchen routing mode in words (the review's "Kitchen" row).
String routingText(Translator t, String mode) =>
    const {'off', 'till', 'kds', 'both'}.contains(mode)
    ? t('builder.routing.$mode')
    : mode;
