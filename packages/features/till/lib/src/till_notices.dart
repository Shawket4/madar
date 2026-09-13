/// The notices around opening a till: the person's till is still open on
/// another device (blocking, with a manager's force close), and bills left
/// open at the branch since the last till closed (informing, never blocking).
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// "Your till is open on another device — close it on 36B first." Opening
/// here stays off while this shows. A manager gets Force close it, behind a
/// confirm (it ends that person's till on a device they may still hold).
class TillElsewherePanel extends ConsumerWidget {
  /// Creates the panel.
  const TillElsewherePanel({
    required this.elsewhere,
    required this.canForceClose,
    required this.forceClosing,
    required this.onForceClose,
    super.key,
  });

  /// Where the till is open.
  final TillElsewhereView elsewhere;

  /// The signed-in person is a manager.
  final bool canForceClose;

  /// A force close is running.
  final bool forceClosing;

  /// Force close it, with the reason for the record.
  final ValueChanged<String> onForceClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final device =
        elsewhere.deviceLabel ?? elsewhere.deviceCode ?? t('till.z_device');
    final since = bridge.formatStamp(rfc3339: elsewhere.openedAt);
    final deviceWords = [
      MadarFormat.isolate(device),
      if (elsewhere.deviceLabel != null && elsewhere.deviceCode != null)
        MadarFormat.ltr(elsewhere.deviceCode!),
    ].join(' · ');

    Future<void> confirm() async {
      final yes = await showMadarConfirm(
        context,
        title: t('till.force_close_elsewhere'),
        body: t('till.open_elsewhere_title'),
        confirmLabel: t('till.force_close_elsewhere'),
        cancelLabel: t('common.cancel'),
      );
      if (yes) onForceClose(t('till.open_elsewhere_title'));
    }

    return MadarCard.column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.md,
          children: [
            MadarGlyphIcon(
              MadarGlyph.alertTriangle,
              size: IconSize.xl,
              color: colors.warning,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.xs,
                children: [
                  Text(
                    t('till.open_elsewhere_title'),
                    style: MadarType.title.copyWith(color: colors.textPrimary),
                  ),
                  Text(
                    t(
                      'till.open_elsewhere_body',
                    ).replaceAll('{device}', deviceWords),
                    style: MadarType.body.copyWith(color: colors.textSecondary),
                  ),
                  Text(
                    '${t('till.open_since')} ${MadarFormat.isolate(since)}',
                    style: MadarType.bodySm.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (canForceClose)
          MadarButton(
            label: t('till.force_close_elsewhere'),
            glyph: MadarGlyph.lock,
            variant: MadarButtonVariant.danger,
            loading: forceClosing,
            onTap: () => unawaited(confirm()),
          ),
      ],
    );
  }
}

/// "3 bills left open since 23:10 · 1 older than 3h". Bills belong to the
/// branch and outlive a till; the next person to open one is told, and the
/// old ones are called out in the warning tone.
class OpenBillsNoticeBanner extends ConsumerWidget {
  /// Creates the banner.
  const OpenBillsNoticeBanner({required this.notice, super.key});

  /// The branch's open bills.
  final OpenBillsNoticeView notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final at = notice.since ?? notice.oldestOpenedAt;
    final since = at == null
        ? '—'
        : MadarFormat.isolate(bridge.formatStamp(rfc3339: at));
    final words = [
      t('till.open_bills_notice')
          .replaceAll('{count}', MadarFormat.ltr('${notice.openBillsCount}'))
          .replaceAll('{since}', since),
      if (notice.oldBillsCount > 0)
        t('till.old_bills')
            .replaceAll('{count}', MadarFormat.ltr('${notice.oldBillsCount}'))
            .replaceAll('{hours}', MadarFormat.ltr('${notice.oldBillHours}')),
    ].join(' · ');
    return NoticeBanner(
      text: words,
      tone: notice.oldBillsCount > 0 ? ChipTone.warning : ChipTone.info,
      icon: 'doc.text',
    );
  }
}
