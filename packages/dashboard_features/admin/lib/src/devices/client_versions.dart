/// Client versions (web `devices-page.tsx` `ClientVersionsView` /
/// `ClientVersionsTable`, ADM-DEV-021..027): who still talks to the server
/// through pre-rework paths. Works with a branch or org-wide (then with a
/// Branch column); the window and the legacy-only switch live in the URL.
library;

import 'package:dashboard_api/dashboard_api.dart' show ClientSeen;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'devices_data.dart';
import 'devices_table.dart';

class ClientVersionsView extends ConsumerWidget {
  const ClientVersionsView({
    required this.branchId,
    required this.days,
    required this.legacyOnly,
    required this.onDays,
    required this.onLegacyOnly,
    super.key,
  });

  final String? branchId;
  final int days;
  final bool legacyOnly;
  final ValueChanged<int> onDays;
  final ValueChanged<bool> onLegacyOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final key = (branchId: branchId, legacyOnly: legacyOnly, days: days);
    final q = ref.watch(clientVersionsProvider(key));
    final rows = q.value ?? const <ClientSeen>[];
    final loading = q.firstLoad;
    final legacy = rows.where((r) => r.lastLegacyAt != null).length;
    final versions = {
      for (final r in rows)
        if (r.appVersion != null && r.appVersion!.isNotEmpty) r.appVersion,
    }.length;
    final error = q.shownError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        DashLedgerStrip(
          key: const ValueKey('clients-kpis'),
          items: [
            DashLedgerItem(
              key: 'clients',
              label: t('devices.clients.seen'),
              value: rows.length,
              format: DashStatFormat.number,
              loading: loading,
            ),
            DashLedgerItem(
              key: 'legacy',
              label: t('devices.clients.onLegacy'),
              value: legacy,
              format: DashStatFormat.number,
              tone: legacy > 0 ? DashTone.warning : DashTone.success,
              loading: loading,
            ),
            DashLedgerItem(
              key: 'versions',
              label: t('devices.clients.versions'),
              value: versions,
              format: DashStatFormat.number,
              loading: loading,
            ),
          ],
        ),
        ClientVersionsTable(
          rows: rows,
          loading: loading,
          errorMessage: error == null ? null : devicesErrorText(error, t),
          onRetry: () => ref.invalidate(clientVersionsProvider(key)),
          showBranch: branchId == null,
          days: days,
          legacyOnly: legacyOnly,
          toolbar: _Toolbar(
            days: days,
            legacyOnly: legacyOnly,
            onDays: onDays,
            onLegacyOnly: onLegacyOnly,
          ),
        ),
      ],
    );
  }
}

/// The window select and the legacy-only switch.
class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.days,
    required this.legacyOnly,
    required this.onDays,
    required this.onLegacyOnly,
  });

  final int days;
  final bool legacyOnly;
  final ValueChanged<int> onDays;
  final ValueChanged<bool> onLegacyOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DashSelect<int>(
          key: const ValueKey('clients-window'),
          value: days,
          expand: false,
          minWidth: DashMetrics.target * 3,
          semanticLabel: t('devices.clients.window'),
          options: [
            for (final d in clientWindowDays)
              DashOption(
                value: d,
                label: t('devices.clients.lastDays', count: d),
              ),
          ],
          onChanged: onDays,
        ),
        // The label wraps the switch: a tap anywhere on it toggles.
        DashPressable(
          key: const ValueKey('clients-legacy-only'),
          onTap: () => onLegacyOnly(!legacyOnly),
          isButton: false,
          checked: legacyOnly,
          semanticLabel: t('devices.clients.legacyOnly'),
          excludeChildSemantics: true,
          pressScale: false,
          builder: (context, s) => Container(
            height: DashMetrics.control,
            padding: const EdgeInsetsDirectional.only(end: Space.md),
            decoration: BoxDecoration(
              color: s.highlighted ? c.hover : c.card,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DashSwitch(
                  value: legacyOnly,
                  semanticLabel: t('devices.clients.legacyOnly'),
                  onChanged: onLegacyOnly,
                ),
                Text(
                  t('devices.clients.legacyOnly'),
                  style: DashType.body.copyWith(color: c.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ClientVersionsTable extends ConsumerWidget {
  const ClientVersionsTable({
    required this.rows,
    required this.days,
    required this.legacyOnly,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.showBranch = false,
    this.toolbar,
    super.key,
  });

  final List<ClientSeen> rows;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final bool showBranch;
  final int days;
  final bool legacyOnly;
  final Widget? toolbar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final mutedSmall = DashType.small.copyWith(color: c.textSecondary);
    final monoSmall = DashType.mono.copyWith(
      fontSize: DashType.small.fontSize,
      color: c.textSecondary,
    );
    return DashDataTable<ClientSeen>(
      key: const ValueKey('clients-table'),
      rows: rows,
      rowKey: (r) =>
          '${r.deviceId ?? ''}|${r.client ?? ''}|${r.firstSeenAt.toIso8601String()}',
      loading: loading,
      errorMessage: errorMessage,
      onRetry: onRetry,
      hideViewOptions: true,
      pageSize: 20,
      toolbar: toolbar,
      empty: legacyOnly
          ? DashEmptyState(
              icon: 'check-circle-2',
              title: t('devices.clients.noLegacy'),
              description: t('devices.clients.noLegacyHint', count: days),
            )
          : DashEmptyState(
              icon: 'history',
              title: t('devices.clients.none'),
              description: t('devices.clients.noneHint', count: days),
            ),
      columns: [
        DashColumn<ClientSeen>(
          id: 'device',
          label: t('devices.clients.device'),
          phone: DashPhoneRole.title,
          flex: 2,
          minWidth: 200,
          text: (r) => r.deviceCode ?? t('devices.clients.unregistered'),
          cell: (context, r) => Column(
            key: ValueKey('client-row-${r.deviceId ?? r.client}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r.deviceCode != null)
                Text(
                  r.deviceCode!,
                  style: DashType.monoStrong.copyWith(color: c.textPrimary),
                )
              else
                MadarClippedText(
                  t('devices.clients.unregistered'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                ),
              _LtrLine(text: r.client ?? '—', style: mutedSmall),
            ],
          ),
        ),
        if (showBranch)
          DashColumn<ClientSeen>(
            id: 'branch',
            label: t('tills.branch'),
            text: (r) => r.branchName ?? '—',
          ),
        DashColumn<ClientSeen>(
          id: 'app_version',
          label: t('devices.clients.version'),
          text: (r) => r.appVersion ?? '',
          cell: (context, r) => r.appVersion == null
              ? const DevicesDash()
              : Text(
                  r.appVersion!,
                  textDirection: TextDirection.ltr,
                  style: DashType.mono.copyWith(color: c.textPrimary),
                ),
        ),
        DashColumn<ClientSeen>(
          id: 'last_seen_at',
          label: t('devices.lastSeen'),
          numeric: true,
          text: (r) => fmt.fmtStamp(r.lastSeenAt),
        ),
        DashColumn<ClientSeen>(
          id: 'legacy',
          label: t('devices.clients.lastLegacy'),
          flex: 2,
          minWidth: 200,
          text: (r) => r.lastLegacyAt == null
              ? t('devices.clients.upToDate')
              : t('devices.clients.legacy'),
          cell: (context, r) {
            if (r.lastLegacyAt == null) {
              return DashStatusPill(
                label: t('devices.clients.upToDate'),
                tone: DashTone.success,
                small: true,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DashStatusPill(
                      label: t('devices.clients.legacy'),
                      tone: DashTone.warning,
                      small: true,
                    ),
                    Text(
                      dashFigure(fmt.fmtStamp(r.lastLegacyAt)),
                      style: DashType.mono.copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
                if (r.lastLegacyKind != null)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: dashFigure(r.lastLegacyKind!),
                          style: DashType.monoMedium.copyWith(
                            fontSize: DashType.small.fontSize,
                            color: c.textPrimary,
                          ),
                        ),
                        if (r.legacyKinds.length > 1)
                          TextSpan(
                            text: '  +${r.legacyKinds.length - 1}',
                            style: mutedSmall,
                          ),
                      ],
                    ),
                  ),
                if (r.lastLegacyPath != null)
                  _LtrLine(text: r.lastLegacyPath!, style: monoSmall),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A left-to-right line (a client string, a path) cut to one line; when it
/// is cut, a resting pointer or a hold shows the whole (`title=`).
class _LtrLine extends StatelessWidget {
  const _LtrLine({required this.text, required this.style});

  final String text;
  final TextStyle style;

  /// The web's `max-w-xs`.
  static const double maxWidth = DashMetrics.prose - Space.xxl * 2;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1,
        child: MadarClippedText(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr,
          // `text-left rtl:text-right`.
          textAlign: rtl ? TextAlign.right : TextAlign.left,
          style: style,
        ),
      ),
    );
  }
}
