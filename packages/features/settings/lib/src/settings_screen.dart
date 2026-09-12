/// Settings — reached from the name sheet. Language and theme are one tap
/// each (they used to be three, deep in a rail footer); the rest is a list
/// of rows that open their own sheet: Printer, Till, Device, Diagnostics,
/// Legal. Sync is a SECTION of this screen, not a rail entry: on a tablet it
/// is the start column beside the preferences, on a phone it leads the
/// list, because what is queued matters more than which paper the printer
/// takes. Sign out is disabled with its reason while a drawer is open.
///
/// Pushed as its own route over the shell; the header's back pops it.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_settings/src/labels.dart';
import 'package:feature_settings/src/settings_provider.dart';
import 'package:feature_settings/src/settings_sheets.dart';
import 'package:feature_settings/src/sync_provider.dart';
import 'package:feature_settings/src/sync_screen.dart';
import 'package:feature_settings/src/sync_section.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two-column split on a tablet: Sync takes the narrower start column.
const int _syncFlex = 5;
const int _prefsFlex = 6;

/// The settings screen. All state flows from [settingsProvider] (plus the
/// Signing a till out mid-service. Queued sales survive on the device and go
/// when the next person signs in, so nothing is lost — but nobody can ring up
/// until then, which is worth saying out loud on a shop floor.
///
/// The notifier already refuses outright while a shift is open; this is the
/// question for the case it allows.
Future<bool> _confirmSignOut(BuildContext context, WidgetRef ref) {
  final bridge = ref.read(bridgeProvider);
  return showMadarConfirm(
    context,
    title: bridge.tr(key: 'settings.sign_out_title'),
    body: bridge.tr(key: 'settings.sign_out_body'),
    confirmLabel: bridge.tr(key: 'home.sign_out'),
    cancelLabel: bridge.tr(key: 'common.cancel'),
  );
}

/// app-core locale / dark-mode providers) and `syncProvider`.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Post-frame: notifier writes during initState land mid-build (crash).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(settingsProvider.notifier).load());
    });
  }

  void _openSync() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SyncScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    final layout = context.madarLayout;
    // Pushed as its own route, so it re-derives direction from the locale
    // provider — the live en↔ar switch below re-flips it in place.
    final locale = ref.watch(localeProvider);
    final sync = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        MadarSectionHeader(
          text: bridge.tr(key: 'sync.title'),
          trailing: MadarButton(
            label: bridge.tr(key: 'sync.see_all'),
            variant: MadarButtonVariant.ghost,
            size: MadarButtonSize.compact,
            onTap: _openSync,
          ),
        ),
        SyncSection(compact: true, onSeeAll: _openSync),
      ],
    );
    const prefs = _Preferences();
    return Directionality(
      textDirection: locale.rtl ? TextDirection.rtl : TextDirection.ltr,
      child: MadarPageScaffold(
        title: bridge.tr(key: 'settings.title'),
        onBack: () => Navigator.of(context).maybePop(),
        body: SafeArea(
          top: false,
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
                child: layout.isTablet
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.xl,
                        children: [
                          Expanded(flex: _syncFlex, child: sync),
                          const Expanded(flex: _prefsFlex, child: prefs),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: Space.xl,
                        children: [sync, prefs],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Account, language, theme, the row list, sign out.
class _Preferences extends ConsumerWidget {
  const _Preferences();

  /// Sign-out (guarded in the notifier): pop first, then refresh the shell
  /// so the route flip lands on the shell subtree, not this overlay.
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    if (!await _confirmSignOut(context, ref)) return;
    if (!context.mounted) return;
    final shell = ref.read(shellProvider.notifier);
    final ok = await ref.read(settingsProvider.notifier).signOut();
    if (!ok || !context.mounted) return;
    await Navigator.of(context).maybePop();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        if (error != null)
          NoticeBanner(text: error, icon: 'exclamationmark.circle'),
        const _AccountCard(),
        MadarSectionHeader(text: t('settings.language')),
        const LanguageSegment(),
        MadarSectionHeader(text: t('settings.theme')),
        const ThemeSegment(),
        const _RowList(),
        MadarButton(
          label: t('settings.sign_out'),
          glyph: MadarGlyph.signOut,
          variant: MadarButtonVariant.danger,
          enabled: !hasOpenShift,
          tooltip: hasOpenShift ? t('settings.sign_out_shift_open') : null,
          onTap: () => unawaited(_signOut(context, ref)),
        ),
        if (hasOpenShift)
          Text(
            t('settings.sign_out_shift_open'),
            textAlign: TextAlign.center,
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
      ],
    );
  }
}

/// Who is signed in, where: avatar initial, name, role · branch.
class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final session = ref.watch(shellProvider.select((s) => s.session));
    final tellerName = ref.watch(
      settingsProvider.select((s) => s.shift?.tellerName),
    );
    final branch =
        ref.watch(settingsProvider.select((s) => s.config.branchName)) ?? '';
    final online = ref.watch(
      syncProvider.select((s) => s.status?.online ?? false),
    );
    // The session names the person; the shift is the fallback for a till
    // whose session snapshot is missing (unlocked offline before a login).
    final name = session?.displayName ?? tellerName ?? '—';
    final role = session?.role ?? '';
    final meta = [
      if (role.isNotEmpty) roleLabel(bridge, role),
      if (branch.isNotEmpty) branch,
    ].join(' · ');
    return MadarCard(
      child: Row(
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
                  style: MadarType.h3.copyWith(color: colors.textPrimary),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live en / ar switch — strings + RTL re-resolve in place through
/// `localeProvider`. Labels are each language's own name, never translated.
/// Shared with the Me tab.
class LanguageSegment extends ConsumerWidget {
  const LanguageSegment({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider.select((s) => s.locale));
    return MadarSegmented<String>(
      items: const [
        MadarSegmentItem('en', 'English'),
        MadarSegmentItem('ar', 'العربية'),
      ],
      value: locale.startsWith('ar') ? 'ar' : 'en',
      onChanged: ref.read(localeProvider.notifier).set,
    );
  }
}

/// Light / dark — drives `darkModeProvider` (the host persists). "Auto" is
/// not offered: the app-core preference is a boolean and a segment that
/// forgets itself on the next launch would lie. Shared with the Me tab.
class ThemeSegment extends ConsumerWidget {
  const ThemeSegment({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final choice = ref.watch(themeChoiceProvider);
    // Light · Dark · Auto — the third cell follows the device and, because
    // the choice is persisted by name, still does after a relaunch.
    return MadarSegmented<ThemeChoice>(
      items: [
        MadarSegmentItem(
          ThemeChoice.light,
          bridge.tr(key: 'settings.theme_light'),
        ),
        MadarSegmentItem(
          ThemeChoice.dark,
          bridge.tr(key: 'settings.theme_dark'),
        ),
        MadarSegmentItem(
          ThemeChoice.system,
          bridge.tr(key: 'settings.theme_system'),
        ),
      ],
      value: choice,
      onChanged: ref.read(themeChoiceProvider.notifier).set,
    );
  }
}

/// The rows that open a sheet: Printer, Till / Station, Device,
/// Diagnostics, Legal. Each carries its one-line summary.
class _RowList extends ConsumerWidget {
  const _RowList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final config = ref.watch(settingsProvider.select((s) => s.config));
    final tills = ref.watch(settingsProvider.select((s) => s.tills));
    final stations = ref.watch(settingsProvider.select((s) => s.stations));
    final isKitchen = ref.watch(
      shellProvider.select((s) => s.session?.role == 'kitchen'),
    );
    final floorAuthored = ref.watch(
      settingsProvider.select((s) => s.floorAuthored),
    );
    final warnings = ref.watch(
      settingsProvider.select((s) => s.diagnostics.length),
    );
    final tillName = config.tillId == null
        ? t('settings.till_default')
        : tills
              .where((till) => till.id == config.tillId)
              .map((till) => till.name)
              .firstOrNull;
    final stationName = stations
        .where((station) => station.id == config.stationId)
        .map((station) => station.name)
        .firstOrNull;
    final deviceCode = bridge.deviceCode();
    final deviceMeta = [
      if (deviceCode.isNotEmpty) deviceCode,
      if ((config.branchName ?? '').isNotEmpty) config.branchName!,
    ].join(' · ');
    final server = Uri.tryParse(bridge.baseUrl())?.host ?? bridge.baseUrl();
    final diagnosticsMeta = 'v${bridge.version()} · $server';
    final rows = <Widget>[
      MadarRow(
        title: t('settings.printer'),
        subtitle: printerSummary(bridge, config),
        glyph: MadarGlyph.printer,
        onTap: () => unawaited(showPrinterSheet(context)),
      ),
      if (!isKitchen && tills.isNotEmpty)
        MadarRow(
          title: t('settings.till'),
          subtitle: tillName,
          glyph: MadarGlyph.wallet,
          onTap: () => unawaited(showTillSheet(context)),
        ),
      if (isKitchen && stations.isNotEmpty)
        MadarRow(
          title: t('setup.choose_station'),
          subtitle: stationName,
          glyph: MadarGlyph.flame,
          onTap: () => unawaited(showStationSheet(context)),
        ),
      MadarRow(
        title: t('settings.device'),
        subtitle: deviceMeta.isEmpty ? null : deviceMeta,
        glyph: MadarGlyph.tag,
        onTap: () => unawaited(showDeviceSheet(context)),
      ),
      MadarRow(
        title: t('settings.diagnostics'),
        subtitle: diagnosticsMeta,
        glyph: MadarGlyph.alertCircle,
        // A shop that expected a Floor tab and has none, or a feed with
        // warnings in it, gets a mark on the row so the answer is one tap
        // away — without opening the sheet on every visit to find out.
        trailing: (!floorAuthored || warnings > 0)
            ? MadarTag(
                label: '${warnings + (floorAuthored ? 0 : 1)}',
                tone: MadarTone.warning,
              )
            : null,
        onTap: () => unawaited(showDiagnosticsSheet(context)),
      ),
      MadarRow(
        title: t('settings.legal'),
        glyph: MadarGlyph.note,
        onTap: () => unawaited(showLegalSheet(context)),
      ),
    ];
    return MadarCard(
      flush: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, row) in rows.indexed) ...[
            if (index > 0) const MadarHairline.row(),
            row,
          ],
        ],
      ),
    );
  }
}
