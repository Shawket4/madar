/// The Google Wallet object for one member, verbatim — platform admins only
/// (the web's `features/loyalty/admin/members/google-object-dialog.tsx`,
/// SELL-CUS-015/048, SET-LOY-074/075): the one comparison that decides it
/// (branches we send against branches Google stored), then the raw JSON; and
/// "Send it again, and show me", which runs the real provisioning and reports
/// every request and Google's answer.
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'customers_data.dart';

/// `GET /loyalty/members/{id}/google-object`: a live read of Google, never
/// cached (`staleTime: 0, gcTime: 0`).
final googleObjectProvider = FutureProvider.autoDispose
    .family<GoogleObjectDump, String>((ref, id) {
      ref.webCache();
      return ref.watch(apiProvider).loyalty.getLoyaltyGoogleObject(id: id);
    });

/// Opens the dialog for [memberId]; closing it drops the report.
Future<void> showGoogleObjectDialog(
  BuildContext context, {
  required String memberId,
  required String memberName,
}) => showDashDialog<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (context) =>
      GoogleObjectDialog(memberId: memberId, memberName: memberName),
);

class GoogleObjectDialog extends ConsumerStatefulWidget {
  const GoogleObjectDialog({
    required this.memberId,
    required this.memberName,
    super.key,
  });

  final String memberId;
  final String memberName;

  @override
  ConsumerState<GoogleObjectDialog> createState() => _GoogleObjectDialogState();
}

class _GoogleObjectDialogState extends ConsumerState<GoogleObjectDialog> {
  GoogleRefreshReport? _report;
  Object? _refreshError;
  bool _refreshing = false;

  Future<void> _run() async {
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      final r = await ref
          .read(apiProvider)
          .loyalty
          .refreshLoyaltyGooglePass(id: widget.memberId);
      if (mounted) setState(() => _report = r);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _report = null;
          _refreshError = e;
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final q = ref.watch(googleObjectProvider(widget.memberId));
    final report = _report;
    final danger = DashTone.danger.foreground(c);

    Widget figures(List<(String, int, bool)> items) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Wrap(
        spacing: Space.lg,
        runSpacing: Space.xs,
        children: [
          for (final (label, n, bad) in items)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$label: '),
                  TextSpan(
                    text: '$n',
                    style: DashType.monoStrong.copyWith(fontSize: 14),
                  ),
                ],
              ),
              style: DashType.body.copyWith(
                color: bad ? danger : c.textPrimary,
                fontWeight: bad ? FontWeight.w500 : null,
              ),
            ),
        ],
      ),
    );

    Widget errorLine(String text) =>
        Text(text, style: DashType.body.copyWith(color: c.errorText));

    final body = <Widget>[
      Row(
        spacing: Space.md,
        children: [
          DashButton(
            label: t('loyalty.refreshFromGoogle'),
            icon: 'refresh-cw',
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            loading: _refreshing,
            onPressed: _run,
          ),
          Expanded(
            child: Text(
              t('loyalty.refreshHint'),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
      if (_refreshError != null)
        errorLine(peopleErrorMessage(_refreshError, t)),
      if (report != null) ...[
        figures([
          (t('loyalty.branchesSent'), report.sentLocations, false),
          (
            t('loyalty.branchesOnClass'),
            report.classLocations,
            report.classLocations != report.sentLocations,
          ),
          (
            t('loyalty.branchesOnObject'),
            report.objectLocations,
            report.objectLocations != report.sentLocations,
          ),
        ]),
        if (report.error case final e?) errorLine(e),
        for (final s in report.steps) _StepCard(step: s),
        if (report.class_ case final cls?)
          _Collapsible(title: t('loyalty.classNow'), json: cls),
      ],
      switch (q) {
        AsyncValue(:final value?) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Wrap(
                spacing: Space.lg,
                runSpacing: Space.xs,
                children: [
                  _figure(
                    t('loyalty.branchesExpected'),
                    value.expectedLocations,
                    c.textPrimary,
                  ),
                  _figure(
                    t('loyalty.branchesStored'),
                    value.storedLocations,
                    value.object != null &&
                            value.storedLocations == value.expectedLocations
                        ? DashTone.success.foreground(c)
                        : danger,
                  ),
                ],
              ),
            ),
            if (value.error case final e?) errorLine(e),
            if (value.object case final o?) _JsonBlock(json: o),
          ],
        ),
        AsyncValue(:final error?) => errorLine(peopleErrorMessage(error, t)),
        _ => const DashSkeleton(height: Space.xxl * 6),
      },
    ];

    return DashSurface(
      title: t('loyalty.googleObject'),
      description: t(
        'loyalty.googleObjectFor',
        args: {'name': widget.memberName},
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: body,
      ),
    );
  }

  Widget _figure(String label, int n, Color color) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '$label: '),
        TextSpan(text: '$n', style: DashType.monoStrong.copyWith(fontSize: 14)),
      ],
    ),
    style: DashType.body.copyWith(color: color),
  );
}

/// One provisioning step: its name, its HTTP status (red when not 2xx) and
/// Google's answer verbatim.
class _StepCard extends StatelessWidget {
  const _StepCard({required this.step});

  final WalletStep step;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final ok = step.status >= 200 && step.status < 300;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.xs + DashMetrics.hair,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.hairline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    step.step,
                    style: DashType.smallMedium.copyWith(color: c.textPrimary),
                  ),
                ),
                Text(
                  step.status == 0 ? '—' : '${step.status}',
                  style: DashType.mono.copyWith(
                    fontSize: 12,
                    color: ok ? c.textSecondary : c.errorText,
                    fontWeight: ok ? null : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: Space.xxl * 6),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              child: Text(
                step.body,
                textDirection: TextDirection.ltr,
                style: DashType.mono.copyWith(
                  fontSize: 11,
                  color: c.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Raw JSON, pretty-printed, scrolling within its box.
class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.json, this.maxHeight = Space.xxl * 12});

  final Object json;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.hairline),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.md),
        child: SelectableText(
          const JsonEncoder.withIndent('  ').convert(json),
          textDirection: TextDirection.ltr,
          style: DashType.mono.copyWith(fontSize: 12, color: c.textPrimary),
        ),
      ),
    );
  }
}

/// The web's `<details>`: a summary line that opens the JSON under it.
class _Collapsible extends StatefulWidget {
  const _Collapsible({required this.title, required this.json});

  final String title;
  final Object json;

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashPressable(
            onTap: () => setState(() => _open = !_open),
            semanticLabel: widget.title,
            excludeChildSemantics: true,
            pressScale: false,
            builder: (context, s) => ConstrainedBox(
              constraints: const BoxConstraints(minHeight: DashMetrics.target),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.md),
                child: Row(
                  spacing: Space.xs,
                  children: [
                    DashIcon(
                      _open ? 'chevron-down' : DashIcon.forward(context),
                      size: IconSize.xs,
                      color: c.textSecondary,
                    ),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: DashType.smallMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: _JsonBlock(json: widget.json, maxHeight: Space.xxl * 9),
            ),
        ],
      ),
    );
  }
}
