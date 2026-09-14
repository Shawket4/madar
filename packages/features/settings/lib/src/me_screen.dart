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
    show
        LanguageSegment,
        MotionSegment,
        ProfileCard,
        ThemeSegment,
        confirmSignOut;
import 'package:feature_settings/src/settings_sheets.dart';
import 'package:feature_settings/src/sync_screen.dart';
import 'package:feature_settings/src/sync_section.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

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
    unawaited(MadarPages.push<void>(context, (_) => const SyncScreen()));
  }

  @override
  Widget build(BuildContext context) {
    // A round fired, bumped or settled anywhere in the branch — the bill
    // list re-reads on the tick, like the Bills tab.
    ref.listen(ticketTickProvider, (_, _) {
      unawaited(ref.read(meBillsProvider.notifier).load());
    });
    // A tab body — the shell's top bar above it already paid the top inset.
    return MadarPageScaffold(
      safeTop: false,
      title: ref.bridge.tr(key: 'nav.me'),
      width: MadarContentWidth.reading,
      body: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.xl,
          children: [
            const ProfileCard(),
            const _MyBills(),
            SyncSection(compact: true, waiterOnly: true, onSeeAll: _openSync),
            const _Device(),
            const _Preferences(),
          ],
        ),
      ),
    );
  }
}

/// This device: the printer, the build and server, the legal notes — the
/// same nav rows as Settings.
class _Device extends ConsumerWidget {
  const _Device();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final config = ref.watch(settingsProvider.select((s) => s.config));
    final server = Uri.tryParse(bridge.baseUrl())?.host ?? bridge.baseUrl();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(text: t('settings.this_device')),
        MadarCard.column(
          flush: true,
          children: [
            MadarListRow.nav(
              title: t('settings.printer'),
              meta: printerSummary(bridge, config),
              glyph: MadarGlyph.printer,
              onTap: () => unawaited(showPrinterSheet(context)),
            ),
            const MadarHairline.row(),
            MadarListRow.nav(
              title: t('settings.diagnostics'),
              meta: MadarFormat.ltr('v${bridge.version()} · $server'),
              glyph: MadarGlyph.alertCircle,
              onTap: () => unawaited(showDiagnosticsSheet(context)),
            ),
            const MadarHairline.row(),
            MadarListRow.nav(
              title: t('settings.legal'),
              glyph: MadarGlyph.note,
              onTap: () => unawaited(showLegalSheet(context)),
            ),
          ],
        ),
      ],
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
            child: EmptyState(
              icon: 'receipt',
              title: bridge.tr(key: 'me.no_bills'),
              message: bridge.tr(key: 'me.no_bills_message'),
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
                  _Bill(bill: bill, currency: currency),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _Bill extends ConsumerWidget {
  const _Bill({required this.bill, required this.currency});

  final TicketView bill;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final ready = bill.status == 'ready';
    // The latest round is the highest round number on the bill.
    var round = 0;
    for (final line in bill.lines) {
      if (line.roundNumber > round) round = line.roundNumber;
    }
    return MadarListRow.bill(
      title: bill.customerName ?? bill.ticketRef ?? bill.id,
      meta: [
        if (round > 0) '${t('tables.round')} ${MadarFormat.ltr('$round')}',
        MadarFormat.isolate(bridge.formatStamp(rfc3339: bill.openedAt)),
      ].join(' · '),
      minor: bill.subtotalMinor,
      currency: currency,
      status: ready
          ? MadarStatus(t('notif.ready'), tone: MadarTone.success)
          : bill.queuedOffline
          ? MadarStatus(t('waiter.queued'), tone: MadarTone.warning)
          : null,
      rail: ready ? MadarTone.success : null,
      chevron: false,
    );
  }
}

/// Language, theme, sign out. The waiter has no drawer, so sign out is
/// never guarded here in practice; the notifier still checks.
class _Preferences extends ConsumerWidget {
  const _Preferences();

  /// No route to pop — the tab lives in the shell — so refresh the shell
  /// and let the route flip to Login.
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    if (!await confirmSignOut(context, ref)) return;
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
    final hasOpenTill = ref.watch(
      settingsProvider.select((s) => s.hasOpenTill),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        if (error != null)
          NoticeBanner(
            text: error.of(ref.bridge),
            icon: 'exclamationmark.circle',
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            MadarSectionHeader(text: t('settings.language')),
            const LanguageSegment(),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            MadarSectionHeader(text: t('settings.theme')),
            const ThemeSegment(),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            MadarSectionHeader(text: t('settings.motion')),
            const MotionSegment(),
          ],
        ),
        MadarButton(
          label: t('settings.sign_out'),
          glyph: MadarGlyph.signOut,
          variant: MadarButtonVariant.secondary,
          enabled: !hasOpenTill,
          tooltip: hasOpenTill ? t('settings.sign_out_shift_open') : null,
          onTap: () => unawaited(_signOut(context, ref)),
        ),
        if (hasOpenTill)
          Text(
            t('settings.sign_out_shift_open'),
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
      ],
    );
  }
}
