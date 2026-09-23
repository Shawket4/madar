import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/src/data.dart';
import 'package:staff_core/src/format.dart';
import 'package:staff_core/src/providers.dart';

/// Runs a core call and WAITS for the server's answer (B1). A refusal
/// (geofence, window, cap, "needs a connection"…) comes back as a toast in
/// the core's words and `false`, so the sheet that asked stays open with what
/// was typed; [ok] confirms a success only once the server has accepted it.
Future<bool> attempt(
  WidgetRef ref,
  Future<void> Function() call, {
  String? ok,
}) async {
  final toast = ref.read(toastProvider.notifier);
  try {
    await runZoned(call, zoneValues: {DawamStore.awaitAnswerKey: true});
    if (ok != null) toast.show(ok, tone: ChipTone.success);
    return true;
  } on DawamError catch (e) {
    toast.show(loc(e), tone: ChipTone.danger);
    return false;
  }
}

/// The kit's sheet with a title and a close tile, following the core while
/// it is open so what it shows never goes stale.
Future<T?> showDawamSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext, WidgetRef, DawamStore) builder,
  SheetSize size = SheetSize.hug,
}) => showMadarSheet<T>(
  context,
  size: size,
  builder: (_) => Consumer(
    builder: (ctx, ref, _) {
      final store = ref.watch(dawamProvider);
      return SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: MadarType.h3)),
                MadarGlyphTile(
                  glyph: MadarGlyph.close,
                  semanticLabel: tr('common.close'),
                  onTap: () => Navigator.of(ctx).maybePop(),
                ),
              ],
            ),
            builder(ctx, ref, store),
          ],
        ),
      );
    },
  ),
);

/// A tab's page: the kit's content frame (gutters, a readable width on a
/// tablet) around a scrolling column with the kit's section rhythm.
class DawamPage extends StatelessWidget {
  const DawamPage({
    required this.children,
    this.width = MadarContentWidth.reading,
    super.key,
  });

  final List<Widget> children;
  final MadarContentWidth width;

  @override
  Widget build(BuildContext context) => MadarContentFrame(
    width: width,
    child: ListView(
      padding: const EdgeInsetsDirectional.only(
        top: Space.lg,
        bottom: Space.xxl,
      ),
      children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) const SizedBox(height: Space.xl),
          c,
        ],
      ],
    ),
  );
}

/// A labelled group of rows in one flush card — the POS settings pattern.
class DawamSection extends StatelessWidget {
  const DawamSection(
    this.title, {
    required this.children,
    this.trailing,
    this.empty,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  /// Shown instead of the card when there is nothing to list.
  final String? empty;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.sm,
    children: [
      MadarSectionHeader(text: title, trailing: trailing),
      if (children.isEmpty)
        MadarCard(
          child: Text(
            empty ?? tr('staff.nothing_here'),
            style: MadarType.bodySm.copyWith(
              color: context.madarColors.textMuted,
            ),
          ),
        )
      else
        MadarCard.column(
          flush: true,
          clip: true,
          spacing: 0,
          children: [
            for (final (i, c) in children.indexed) ...[
              if (i > 0) const MadarHairline.row(),
              c,
            ],
          ],
        ),
    ],
  );
}

/// A tappable "label · value" line that opens a picker.
class DawamPickField extends StatelessWidget {
  const DawamPickField({
    required this.label,
    required this.value,
    required this.onTap,
    this.glyph = MadarGlyph.calendar,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final MadarGlyph glyph;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return MadarCard(
      onTap: onTap,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Row(
        spacing: Space.md,
        children: [
          MadarGlyphIcon(glyph, color: c.textSecondary),
          Expanded(
            child: Text(
              label,
              style: MadarType.bodySm.copyWith(color: c.textSecondary),
            ),
          ),
          Text(value, style: timeStyle),
        ],
      ),
    );
  }
}

/// Requests and approvals need a connection and say so (APP-8).
class OfflineNotice extends ConsumerWidget {
  const OfflineNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(dawamProvider).offline
      ? NoticeBanner(text: tr('staff.you_re_offline_requests_and_approvals'))
      : const SizedBox.shrink();
}

/// Times carry ص/م in Arabic, which the mono figure face lacks: the sans
/// face with tabular figures.
final TextStyle timeStyle = MadarType.title.copyWith(
  fontFeatures: const [FontFeature.tabularFigures()],
);

Widget personAvatar(Emp e, {double size = 40}) => MadarAvatar(
  person: MadarPerson(name: name(e), initial: initialOf(name(e))),
  size: size,
);

String name(Emp e) => loc(e);
String firstName(Emp e) => name(e).split(' ').first;
String branchName(DawamStore store, String id) {
  final b = store.branches[id];
  return b == null ? '—' : loc(b);
}

String tplName(Tpl p) => loc(p);
String shiftWindow(Shift s) => '${hm(s.startAt)} – ${hm(s.endAt)}';

String kindLabel(ReqKind k) => switch (k) {
  ReqKind.leave => tr('staff.kind_leave'),
  ReqKind.lateArrival => tr('staff.kind_late_arrival'),
  ReqKind.earlyDeparture => tr('staff.kind_early_departure'),
  ReqKind.excuse => tr('staff.kind_excuse'),
  ReqKind.mission => tr('staff.kind_mission'),
  ReqKind.correction => tr('staff.kind_correction'),
  ReqKind.salaryAdvance => tr('staff.kind_salary_advance'),
  ReqKind.cover => tr('staff.kind_cover'),
  ReqKind.swap => tr('staff.kind_swap'),
  ReqKind.openShift => tr('staff.kind_open_shift'),
  ReqKind.overtime => tr('staff.kind_overtime'),
};

MadarStatus statusOf(ReqStatus s) => switch (s) {
  ReqStatus.awaitingPeer => MadarStatus(
    tr('staff.waiting_for_colleague'),
    tone: MadarTone.warning,
  ),
  ReqStatus.pending => MadarStatus(
    tr('staff.pending'),
    tone: MadarTone.warning,
  ),
  ReqStatus.approved => MadarStatus(
    tr('staff.approved'),
    tone: MadarTone.success,
  ),
  ReqStatus.rejected => MadarStatus(
    tr('staff.declined'),
    tone: MadarTone.danger,
  ),
  ReqStatus.cancelled => MadarStatus(tr('staff.cancelled')),
};

String methodLabel(Method m) => switch (m) {
  Method.app => tr('staff.app'),
  Method.offline => tr('staff.app_offline'),
  Method.manager => tr('staff.by_manager'),
  Method.till => tr('staff.till'),
  Method.kiosk => tr('staff.kiosk'),
  Method.auto => tr('staff.auto_closed'),
  Method.correction => tr('staff.correction'),
  Method.cover => tr('staff.cover_tag'),
};

({String label, MadarTone tone, MadarGlyph glyph}) flagInfo(FlagKind k) =>
    switch (k) {
      FlagKind.leftMidShift => (
        label: tr('staff.left_mid_shift'),
        tone: MadarTone.danger,
        glyph: MadarGlyph.signOut,
      ),
      FlagKind.suspicious => (
        label: tr('staff.location_suspicious'),
        tone: MadarTone.danger,
        glyph: MadarGlyph.globe,
      ),
      FlagKind.trackingOff => (
        label: tr('staff.tracking_off'),
        tone: MadarTone.warning,
        glyph: MadarGlyph.wifiOff,
      ),
      FlagKind.timeUnverified => (
        label: tr('staff.time_unverified'),
        tone: MadarTone.warning,
        glyph: MadarGlyph.clock,
      ),
      FlagKind.newPhone => (
        label: tr('staff.new_phone'),
        tone: MadarTone.neutral,
        glyph: MadarGlyph.phone,
      ),
      FlagKind.cover => (
        label: tr('staff.cover_tag'),
        tone: MadarTone.accent,
        glyph: MadarGlyph.users,
      ),
      FlagKind.phoneDied => (
        label: tr('staff.phone_died'),
        tone: MadarTone.neutral,
        glyph: MadarGlyph.phone,
      ),
    };

String payMethod(PayMethod m) => switch (m) {
  PayMethod.cash => tr('staff.cash'),
  PayMethod.bank => tr('staff.bank'),
  PayMethod.wallet => tr('staff.wallet'),
};

/// A money field's pounds as piastres; null when empty or not positive.
int? readMoney(TextEditingController c) {
  final v = double.tryParse(c.text.trim().replaceAll(',', ''));
  return v == null || v <= 0 ? null : (v * 100).round();
}

Future<DateTime?> pickDate(
  BuildContext context,
  DawamStore store, {
  DateTime? initial,
  DateTime? first,
}) => showDatePicker(
  context: context,
  initialDate: initial ?? store.today,
  firstDate: first ?? store.period.start,
  lastDate: store.today.add(const Duration(days: 60)),
);

Future<int?> pickTime(BuildContext context, int initial) async {
  final r = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
  );
  return r == null ? null : r.hour * 60 + r.minute;
}

/// The first letter of a name for an avatar; an empty name never crashes.
String initialOf(String name) {
  final n = name.trim().characters;
  return n.isEmpty ? '·' : n.first;
}
