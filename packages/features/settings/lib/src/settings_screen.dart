/// Settings — reached from the name sheet. Language and theme are one tap
/// each (they used to be three, deep in a rail footer); the rest is a list
/// of rows that open their own sheet: Printer, Station, Device, Diagnostics,
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
import 'package:feature_settings/src/metrics_screen.dart';
import 'package:feature_settings/src/settings_provider.dart';
import 'package:feature_settings/src/settings_sheets.dart';
import 'package:feature_settings/src/sync_provider.dart';
import 'package:feature_settings/src/sync_screen.dart';
import 'package:feature_settings/src/sync_section.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The settings screen. All state flows from [settingsProvider] (plus the
/// Signing a till out mid-service. Queued sales survive on the device and go
/// when the next person signs in, so nothing is lost — but nobody can ring up
/// until then, which is worth saying out loud on a shop floor.
///
/// The notifier already refuses outright while a till is open; this is the
/// question for the case it allows.
Future<bool> confirmSignOut(BuildContext context, WidgetRef ref) {
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
    unawaited(MadarPages.push<void>(context, (_) => const SyncScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    // Pushed as its own route, so it re-derives direction from the locale
    // provider — the live en↔ar switch below re-flips it in place.
    final locale = ref.watch(localeProvider);
    final sync = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
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
    return Directionality(
      textDirection: locale.rtl ? TextDirection.rtl : TextDirection.ltr,
      child: MadarPageScaffold(
        title: bridge.tr(key: 'settings.title'),
        subtitle: bridge.tr(key: 'settings.subtitle'),
        width: MadarContentWidth.reading,
        body: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.xl,
            children: [const _Preferences(), sync],
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
    if (!await confirmSignOut(context, ref)) return;
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
    // The till is the shell's — the one owner — not a copy loaded here.
    final hasOpenTill = ref.watch(shellProvider.select((s) => s.tillOpen));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        if (error != null)
          NoticeBanner(
            text: error.of(ref.bridge),
            icon: 'exclamationmark.circle',
          ),
        if (ref.watch(settingsProvider.select((s) => s.writeError))
            case final writeError?)
          NoticeBanner(
            text: writeError.of(ref.bridge),
            tone: ChipTone.danger,
            icon: 'exclamationmark.triangle',
            onTap: ref.read(settingsProvider.notifier).clearWriteError,
          ),
        const ProfileCard(),
        // How this till looks and behaves first, as the design has it; the
        // device's hardware and diagnostics under it.
        const SellLayoutSection(),
        const AppearanceCard(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            MadarSectionHeader(text: t('settings.this_device')),
            const _RowList(),
          ],
        ),
        MadarButton(
          label: t('settings.sign_out'),
          glyph: MadarGlyph.signOut,
          variant: MadarButtonVariant.danger,
          enabled: !hasOpenTill,
          tooltip: hasOpenTill ? t('settings.sign_out_shift_open') : null,
          onTap: () => unawaited(_signOut(context, ref)),
        ),
        if (hasOpenTill)
          Text(
            t('settings.sign_out_shift_open'),
            textAlign: TextAlign.center,
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
      ],
    );
  }
}

/// Who is signed in, where: avatar initial, name, role · branch. The profile
/// card on Settings and Me alike.
class ProfileCard extends ConsumerWidget {
  /// Creates the card.
  const ProfileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final session = ref.watch(shellProvider.select((s) => s.session));
    final tellerName = ref.watch(
      shellProvider.select((s) => s.till?.tellerName),
    );
    final branch =
        ref.watch(settingsProvider.select((s) => s.config.branchName)) ?? '';
    final online = ref.watch(
      syncProvider.select((s) => s.status?.online ?? false),
    );
    // The session names the person; the till is the fallback for a till
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
    return MadarLanguagePicker(
      value: ref.watch(localeProvider.select((s) => s.locale)),
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
    // Light · Dark · Auto — the third cell follows the device and, because
    // the choice is persisted by name, still does after a relaunch.
    return MadarThemePicker(
      value: ref.watch(themeChoiceProvider),
      onChanged: ref.read(themeChoiceProvider.notifier).set,
      light: bridge.tr(key: 'settings.theme_light'),
      dark: bridge.tr(key: 'settings.theme_dark'),
      system: bridge.tr(key: 'settings.theme_system'),
    );
  }
}

/// Animations: Full · Reduced · System. Reduced tones feedback down (a
/// pulse at the cart instead of a flight, no loops) rather than removing it;
/// System follows the device's reduced-motion flag. Shared with the Me tab.
class MotionSegment extends ConsumerWidget {
  const MotionSegment({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    return MadarSegmented<MotionChoice>(
      items: [
        MadarSegmentItem(
          MotionChoice.full,
          bridge.tr(key: 'settings.motion_full'),
        ),
        MadarSegmentItem(
          MotionChoice.reduced,
          bridge.tr(key: 'settings.motion_reduced'),
        ),
        MadarSegmentItem(
          MotionChoice.system,
          bridge.tr(key: 'settings.motion_system'),
        ),
      ],
      value: ref.watch(motionChoiceProvider),
      onChanged: ref.read(motionChoiceProvider.notifier).set,
    );
  }
}

/// Theme, language and animations as one card of rows, the label at the
/// start and its control at the end (stacked when the card is narrow) — the
/// design's Preferences card. Shared with the Me tab.
class AppearanceCard extends ConsumerWidget {
  const AppearanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final rows = [
      (t('settings.theme'), const ThemeSegment()),
      (t('settings.language'), const LanguageSegment()),
      (t('settings.motion'), const MotionSegment()),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(text: t('settings.appearance')),
        MadarCard(
          flush: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, (label, control)) in rows.indexed) ...[
                if (index > 0) const MadarHairline.row(),
                _Preference(label: label, control: control),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One preference in the card: a kit row with its control at the end, or —
/// in a card too narrow for both — the label over the control.
class _Preference extends StatelessWidget {
  const _Preference({required this.label, required this.control});

  final String label;
  final Widget control;

  /// Under this the control goes under its label instead of beside it.
  static const double _sideBySide = 520;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= _sideBySide) {
          return MadarListRow.nav(
            title: label,
            trailing: SizedBox(width: c.maxWidth * 0.55, child: control),
          );
        }
        return Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.card,
            vertical: Space.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              Text(
                label,
                style: MadarType.title.copyWith(
                  color: context.madarColors.textPrimary,
                ),
              ),
              control,
            ],
          ),
        );
      },
    );
  }
}

/// The Sell screen's layout on this tablet, as the design draws it: a card
/// with what the choice is about and that it is this till's alone, then the
/// two layouts side by side as radio cards — each a small picture of the
/// screen, its name and one line on what it changes — and, while Fast mode
/// is on, a note saying so. Any teller may switch it (no permission); the
/// choice stays on this device. Nothing at all on a phone, which always sells
/// the standard way. Shared with the Me tab.
class SellLayoutSection extends ConsumerWidget {
  const SellLayoutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!MadarLayout.of(context).isTablet) return const SizedBox.shrink();
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final value = ref.watch(sellLayoutProvider);
    final notifier = ref.read(sellLayoutProvider.notifier);
    final options = [
      (
        SellLayout.standard,
        t('settings.sell_layout_standard'),
        t('settings.sell_layout_standard_desc'),
      ),
      (
        SellLayout.fast,
        t('settings.sell_layout_fast'),
        t('settings.sell_layout_fast_desc'),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(
          text: t('settings.sell_layout'),
          trailing: MadarTag(label: t('settings.this_till_only')),
        ),
        MadarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.lg,
            children: [
              Text(
                t('settings.sell_layout_body'),
                style: MadarType.bodySm.copyWith(color: colors.textSecondary),
              ),
              Semantics(
                key: const ValueKey('sell-layout'),
                container: true,
                label: t('settings.sell_layout'),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.lg,
                  children: [
                    for (final (layout, name, desc) in options)
                      Expanded(
                        child: _LayoutOption(
                          key: ValueKey('sell-layout-${layout.name}'),
                          layout: layout,
                          name: name,
                          description: desc,
                          selected: value == layout,
                          onTap: () => notifier.set(layout),
                        ),
                      ),
                  ],
                ),
              ),
              if (value == SellLayout.fast)
                NoticeBanner(
                  text: t('settings.sell_layout_hint'),
                  tone: ChipTone.info,
                  icon: 'exclamationmark.circle',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One layout as a radio card: the screen in miniature, a radio, its name
/// and what it changes.
class _LayoutOption extends StatelessWidget {
  const _LayoutOption({
    required this.layout,
    required this.name,
    required this.description,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final SellLayout layout;
  final String name;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: name,
      child: TactileScale(
        onTap: () {
          MadarHaptics.selection();
          onTap();
        },
        child: AnimatedContainer(
          duration: MotionSpec.gentleDuration,
          curve: MotionSpec.gentleCurve,
          padding: const EdgeInsetsDirectional.all(Space.md),
          decoration: BoxDecoration(
            color: selected
                ? colors.accent.withValues(alpha: 0.08)
                : colors.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(
              color: selected ? colors.accent : colors.borderLight,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              ExcludeSemantics(child: _LayoutPreview(layout: layout)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.md,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 2),
                    child: _Radio(on: selected),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          name,
                          style: MadarType.title.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          description,
                          style: MadarType.bodySm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: on ? colors.accent : colors.border, width: 2),
      ),
      child: AnimatedScale(
        scale: on ? 1 : 0,
        duration: MotionSpec.gentleDuration,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// The Sell screen in miniature: the rail, the top bar, the cart column and
/// the menu. Standard puts the menu first; Fast mode the cart first, over
/// category boxes. Follows the reading direction like the real screen.
class _LayoutPreview extends StatelessWidget {
  const _LayoutPreview({required this.layout});

  final SellLayout layout;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fast = layout == SellLayout.fast;
    Widget bar(double widthFactor, Color color, double height) =>
        FractionallySizedBox(
          widthFactor: widthFactor,
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
    final cart = Expanded(
      flex: 34,
      child: Container(
        padding: const EdgeInsetsDirectional.all(6),
        decoration: BoxDecoration(
          color: colors.surface,
          border: BorderDirectional(
            start: BorderSide(color: colors.borderLight),
            end: BorderSide(color: colors.borderLight),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: [
            bar(0.55, colors.textPrimary, 6),
            for (var i = 0; i < 3; i++) bar(1, colors.surfaceAlt, 10),
            const Spacer(),
            bar(1, colors.accent, 14),
          ],
        ),
      ),
    );
    final menu = Expanded(
      flex: 66,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(6),
        child: GridView.count(
          crossAxisCount: fast ? 3 : 4,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: fast ? 1.3 : 1,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < (fast ? 6 : 12); i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: fast && i.isEven
                      ? colors.accent.withValues(alpha: 0.12)
                      : colors.surface,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: colors.borderLight),
                ),
              ),
          ],
        ),
      ),
    );
    return Container(
      height: 150,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: colors.borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 12, color: colors.textPrimary),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 10, color: colors.textPrimary),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: fast ? [cart, menu] : [menu, cart],
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

/// The rows that open a sheet: Printer, Station, Device,
/// Diagnostics, Legal. Each carries its one-line summary.
class _RowList extends ConsumerWidget {
  const _RowList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final config = ref.watch(settingsProvider.select((s) => s.config));
    final stations = ref.watch(settingsProvider.select((s) => s.stations));
    ref.watch(shellProvider.select((s) => s.session?.userId));
    final isKitchen = isKitchenOnly((c) => bridge.can(cap: c));
    final floorAuthored = ref.watch(
      settingsProvider.select((s) => s.floorAuthored),
    );
    final warnings = ref.watch(
      settingsProvider.select((s) => s.diagnostics.length),
    );
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
    final diagnosticsMeta = MadarFormat.ltr('v${bridge.version()} · $server');
    final rows = <Widget>[
      if (bridge.can(cap: Cap.reportsPosMetrics))
        MadarListRow.nav(
          title: t('metrics.title'),
          glyph: MadarGlyph.list,
          onTap: () => unawaited(
            MadarPages.push<void>(context, (_) => const MetricsScreen()),
          ),
        ),
      MadarListRow.nav(
        title: t('settings.printer'),
        meta: printerSummary(bridge, config),
        glyph: MadarGlyph.printer,
        onTap: () => unawaited(showPrinterSheet(context)),
      ),
      if (isKitchen && stations.isNotEmpty)
        MadarListRow.nav(
          title: t('setup.choose_station'),
          meta: stationName,
          glyph: MadarGlyph.flame,
          onTap: () => unawaited(showStationSheet(context)),
        ),
      MadarListRow.nav(
        title: t('settings.device'),
        meta: deviceMeta.isEmpty ? null : deviceMeta,
        glyph: MadarGlyph.tag,
        onTap: () => unawaited(showDeviceSheet(context)),
      ),
      MadarListRow.nav(
        title: t('settings.diagnostics'),
        meta: diagnosticsMeta,
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
      MadarListRow.nav(
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
