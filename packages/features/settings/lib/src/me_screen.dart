/// Me — the waiter shell's third tab. Not a settings screen: who is signed
/// in, what of theirs is still waiting to reach the server (and what the
/// server refused), the connection, the printer, their open bills, language,
/// theme, sign out. That is the whole of "More" for a waiter.
///
/// A tab body, not a pushed route: no header, no back; the shell's status
/// strip sits above it.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_settings/src/labels.dart';
import 'package:feature_settings/src/settings_provider.dart';
import 'package:feature_settings/src/settings_screen.dart'
    show LanguageSegment, ThemeSegment;
import 'package:feature_settings/src/settings_sheets.dart';
import 'package:feature_settings/src/sync_provider.dart';
import 'package:feature_settings/src/sync_screen.dart';
import 'package:feature_settings/src/sync_section.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The two-column split on a tablet: the queue and bills take the wider
/// start column, the preferences the narrower end one.
const int _statusFlex = 6;
const int _prefsFlex = 5;

/// The signed-in waiter's open bills. MINE is a display-name match —
/// `TicketView` carries `waiterName`, not an `openedBy` id — which is the
/// same rule the Bills tab groups by.
class MeBillsNotifier extends Notifier<List<TicketView>> {
  @override
  List<TicketView> build() => const [];

  /// Re-read the open bills and keep the ones this person opened.
  Future<void> load() async {
    final bridge = ref.read(bridgeProvider);
    final me = ref.read(shellProvider).session?.displayName;
    try {
      final tickets = await bridge.listOpenTickets();
      state = tickets
          .where((t) => me != null && t.waiterName == me)
          .toList(growable: false);
    } on Exception catch (e) {
      // Best-effort: the tab must render offline with whatever it has.
      ref.read(connectivityRefreshProvider.notifier).reportError(e);
    }
  }
}

/// The Me tab's bills provider.
final meBillsProvider = NotifierProvider<MeBillsNotifier, List<TicketView>>(
  MeBillsNotifier.new,
);

/// The Me tab.
class MeScreen extends ConsumerStatefulWidget {
  /// Creates the Me tab body.
  const MeScreen({super.key});

  @override
  ConsumerState<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends ConsumerState<MeScreen> {
  @override
  void initState() {
    super.initState();
    // Post-frame: notifier writes during initState land mid-build (crash).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(settingsProvider.notifier).load());
      unawaited(ref.read(meBillsProvider.notifier).load());
    });
  }

  void _openSync() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SyncScreen()));
  }

  @override
  Widget build(BuildContext context) {
    // A round fired, bumped or settled anywhere in the branch — the bill
    // list re-reads on the tick, like the Bills tab.
    ref.listen(ticketTickProvider, (_, _) {
      unawaited(ref.read(meBillsProvider.notifier).load());
    });
    final layout = context.madarLayout;
    final status = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        SyncSection(compact: true, waiterOnly: true, onSeeAll: _openSync),
        const _PrinterRow(),
        const _MyBills(),
      ],
    );
    const prefs = _Preferences();
    return MadarPageScaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsetsDirectional.all(layout.gutter),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: layout.pick(
                  phone: Responsive.billMaxWidth,
                  tablet: Responsive.contentMaxWidth + Space.xxl,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.xl,
                children: [
                  const _Identity(),
                  if (layout.isTablet)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.xl,
                      children: [
                        Expanded(flex: _statusFlex, child: status),
                        const Expanded(flex: _prefsFlex, child: prefs),
                      ],
                    )
                  else ...[
                    status,
                    prefs,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Name, role · branch. The person the whole tab is about.
class _Identity extends ConsumerWidget {
  const _Identity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final session = ref.watch(shellProvider.select((s) => s.session));
    final branch =
        ref.watch(settingsProvider.select((s) => s.config.branchName)) ?? '';
    final online = ref.watch(
      syncProvider.select((s) => s.status?.online ?? false),
    );
    final name = session?.displayName ?? '—';
    final meta = [
      if (session != null) roleLabel(bridge, session.role),
      if (branch.isNotEmpty) branch,
    ].join(' · ');
    return Row(
      spacing: Space.lg,
      children: [
        MadarAvatar(
          person: MadarPerson(
            name: name,
            initial: name.isEmpty ? '?' : name[0].toUpperCase(),
            online: online,
          ),
          size: Metrics.glyphTileLarge,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.h1.copyWith(color: colors.textPrimary),
              ),
              if (meta.isNotEmpty)
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.body.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The kitchen printer this device prints chits on; opens the printer
/// sheet. A waiter does not own the printer, but "Not printed — no printer"
/// on a chit should be one tap from its cause.
class _PrinterRow extends ConsumerWidget {
  const _PrinterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final config = ref.watch(settingsProvider.select((s) => s.config));
    return MadarCard(
      flush: true,
      child: MadarRow(
        title: bridge.tr(key: 'settings.printer'),
        subtitle: printerSummary(bridge, config),
        glyph: MadarGlyph.printer,
        onTap: () => unawaited(showPrinterSheet(context)),
      ),
    );
  }
}

/// The waiter's open bills: name or ref, the latest round and when it
/// opened, the running SUBTOTAL — labelled so, because `TicketView` carries
/// no total.
class _MyBills extends ConsumerWidget {
  const _MyBills();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final bills = ref.watch(meBillsProvider);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(
          text: bridge.tr(key: 'me.my_bills'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.md,
            children: [
              SyncFigure('${bills.length}'),
              if (bills.isNotEmpty)
                Text(
                  bridge.tr(key: 'order.subtotal'),
                  style: MadarType.bodySm.copyWith(color: colors.textMuted),
                ),
            ],
          ),
        ),
        if (bills.isEmpty)
          MadarCard(
            child: Text(
              bridge.tr(key: 'me.no_bills'),
              style: MadarType.body.copyWith(color: colors.textSecondary),
            ),
          )
        else
          MadarCard(
            flush: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, bill) in bills.indexed) ...[
                  if (index > 0) const MadarHairline.row(),
                  _BillRow(bill: bill, currency: currency),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _BillRow extends ConsumerWidget {
  const _BillRow({required this.bill, required this.currency});

  final TicketView bill;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final ready = bill.status == 'ready';
    // The latest round is the highest round number on the bill; a bill with
    // no lines yet has no round.
    var round = 0;
    for (final line in bill.lines) {
      if (line.roundNumber > round) round = line.roundNumber;
    }
    final opened = bridge.formatTime(
      rfc3339: bill.openedAt,
      style: TimeStyle.time,
    );
    final subtitle = [
      if (round > 0) '${bridge.tr(key: 'tables.round')} $round',
      opened,
      if (bill.queuedOffline) bridge.tr(key: 'waiter.queued'),
    ].join(' · ');
    final title = bill.customerName ?? bill.ticketRef ?? bill.id;
    return MadarRow(
      title: title,
      subtitle: subtitle,
      bar: ready ? colors.success : (bill.queuedOffline ? colors.accent : null),
      value: MoneyText(
        bill.subtotalMinor,
        currency: currency,
        color: colors.textPrimary,
      ),
      trailing: ready
          ? MadarTag(
              label: bridge.tr(key: 'notif.ready'),
              tone: MadarTone.success,
              glyph: MadarGlyph.check,
            )
          : null,
    );
  }
}

/// Language, theme, sign out. The waiter has no drawer, so sign out is
/// never guarded here in practice; the notifier still checks.
class _Preferences extends ConsumerWidget {
  const _Preferences();

  /// No route to pop — the tab lives in the shell — so refresh the shell
  /// and let the route flip to Login.
  Future<void> _signOut(WidgetRef ref) async {
    final shell = ref.read(shellProvider.notifier);
    final ok = await ref.read(settingsProvider.notifier).signOut();
    if (!ok) return;
    shell.refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final error = ref.watch(settingsProvider.select((s) => s.error));
    final hasOpenShift = ref.watch(
      settingsProvider.select((s) => s.hasOpenShift),
    );
    return MadarCard.column(
      spacing: Space.lg,
      children: [
        if (error != null)
          NoticeBanner(text: error, icon: 'exclamationmark.circle'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            MadarSectionHeader(text: t('settings.language')),
            const LanguageSegment(),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            MadarSectionHeader(text: t('settings.theme')),
            const ThemeSegment(),
          ],
        ),
        MadarButton(
          label: t('settings.sign_out'),
          glyph: MadarGlyph.signOut,
          variant: MadarButtonVariant.secondary,
          enabled: !hasOpenShift,
          tooltip: hasOpenShift ? t('settings.sign_out_shift_open') : null,
          onTap: () => unawaited(_signOut(ref)),
        ),
        if (hasOpenShift)
          Text(
            t('settings.sign_out_shift_open'),
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
      ],
    );
  }
}
