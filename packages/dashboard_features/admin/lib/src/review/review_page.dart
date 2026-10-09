/// `/access/review` Review (ADM-REV-001..017): offline acts the permission
/// check did not back and PINs tried at the wrong branch; "Show reviewed",
/// mark one reviewed, pick several and resolve them in bulk. No page gate on
/// the web: without `approvals.review` the read is refused and the table
/// shows its error state (ADM-REV-004). Web: `features/access/{review-page,
/// flag-detail}.tsx`.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, BulkReviewRequest, ReplayFlag;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../orgs/org_errors.dart' show orgErrorWords;
import '../shared/access_tabs.dart';
import '../shared/capability_catalog.dart';
import 'review_data.dart';

class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  static const String path = AccessPaths.review;

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  bool _showReviewed = false;

  /// Picks survive "Show reviewed" and paging; only those still open in the
  /// current list count (ADM-REV-017).
  Set<int> _picked = {};
  String _note = '';
  bool _bulkBusy = false;
  final Set<int> _reviewing = {};

  Future<void> _review(ReplayFlag f) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _reviewing.add(f.id));
    var ok = true;
    try {
      await api.authz.reviewFlag(id: f.id);
    } on Object catch (e) {
      // The server answers `{"reviewed": true}`, not the flag its spec names.
      ok = e is ApiException && e.code == 'decode' && e.status < 300;
      if (!ok && mounted) DashToast.error(context, orgErrorWords(e, t));
    }
    if (ok) bus.invalidate(const [reviewFlagsPath]);
    if (mounted) setState(() => _reviewing.remove(f.id));
  }

  Future<void> _bulk(List<ReplayFlag> chosen) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    final note = _note.trim();
    setState(() => _bulkBusy = true);
    try {
      final res = await api.authz.bulkReviewFlags(
        body: BulkReviewRequest(
          flagIds: [for (final f in chosen) f.id],
          note: note.isEmpty ? null : note,
        ),
      );
      bus.invalidate(const [reviewFlagsPath]);
      if (!mounted) return;
      final ok = res.resolved.length;
      if (res.pending.isNotEmpty) {
        DashToast.warning(
          context,
          t(
            'access.review.bulkPartial',
            args: {'ok': ok, 'failed': res.pending.length},
          ),
          description: [
            for (final p in res.pending) '#${p.id}: ${pendingWords(p.reason, t)}',
          ].join('\n'),
        );
      } else {
        DashToast.success(context, t('access.review.bulkDone', args: {'ok': ok}));
      }
      setState(() {
        _picked = {};
        _note = '';
      });
    } on Object catch (e) {
      if (mounted) DashToast.error(context, orgErrorWords(e, t));
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final lang = ref.watch(localeProvider);
    final canReview = ref.watch(
      authzProvider.select((a) => a.can(Cap.approvalsReview)),
    );
    final phone = DashBreakpoints.isPhone(context);
    final c = context.madarColors;

    final q = ref.watch(reviewFlagsProvider(_showReviewed));
    final rows = q.value ?? const <ReplayFlag>[];
    final open = [for (final f in rows) if (f.reviewedAt == null) f];
    final chosen = [for (final f in open) if (_picked.contains(f.id)) f];
    final allPicked = open.isNotEmpty && chosen.length == open.length;

    final toolbar = Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DashIntent(
          // The switch's press reads the other list: warm it.
          onIntent: () => ref.warm(reviewFlagsProvider(!_showReviewed)),
          child: _ToolbarBox(
            onTap: () => setState(() => _showReviewed = !_showReviewed),
            control: DashSwitch(
              key: const ValueKey('review-show-reviewed'),
              value: _showReviewed,
              semanticLabel: t('access.review.showReviewed'),
              onChanged: (v) => setState(() => _showReviewed = v),
            ),
            label: t('access.review.showReviewed'),
          ),
        ),
        // The web's header checkbox; the kit's table header takes no widget.
        if (canReview && !phone)
          _ToolbarBox(
            onTap: open.isEmpty
                ? null
                : () => setState(
                    () => _picked = allPicked ? {} : {for (final f in open) f.id},
                  ),
            control: DashCheckbox(
              key: const ValueKey('review-select-all'),
              value: allPicked,
              enabled: open.isNotEmpty,
              semanticLabel: t('access.review.selectAll'),
              onChanged: (v) => setState(
                () => _picked = v ? {for (final f in open) f.id} : {},
              ),
            ),
            label: t('access.review.selectAll'),
          ),
        if (canReview && chosen.isNotEmpty)
          Wrap(
            key: const ValueKey('review-bulk-bar'),
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                t('access.review.selectedCount', args: {'count': chosen.length}),
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
              SizedBox(
                width: _noteWidth,
                child: DashTextInput(
                  key: const ValueKey('review-bulk-note'),
                  value: _note,
                  placeholder: t('access.review.notePlaceholder'),
                  semanticLabel: t('access.review.notePlaceholder'),
                  onChanged: (v) => setState(() => _note = v),
                ),
              ),
              DashButton(
                key: const ValueKey('review-bulk-resolve'),
                size: DashButtonSize.compact,
                loading: _bulkBusy,
                label: t(
                  'access.review.bulkResolve',
                  args: {'count': chosen.length},
                ),
                onPressed: () => _bulk(chosen),
              ),
              DashButton(
                variant: DashButtonVariant.ghost,
                size: DashButtonSize.compact,
                label: t('access.review.clearSelection'),
                onPressed: () => setState(() => _picked = {}),
              ),
            ],
          ),
      ],
    );

    return DashPageScaffold(
      title: t('access.review.title'),
      subtitle: t('access.review.subtitle'),
      tabs: const AccessSectionTabs(),
      body: DashDataTable<ReplayFlag>(
        rows: rows,
        rowKey: (f) => f.id,
        loading: q.awaitingFirst,
        errorMessage: q.failedFirst ? orgErrorWords(q.error, t) : null,
        onRetry: () => ref.invalidate(reviewFlagsProvider(_showReviewed)),
        pageSize: 20,
        hideViewOptions: true,
        toolbar: toolbar,
        rowSemanticLabel: (f) => f.authorName ?? '—',
        empty: DashEmptyState(
          icon: 'shield-check',
          title: t('access.review.empty'),
          description: t('access.review.emptyHint'),
        ),
        rowActionsWidth: _actionsWidth,
        rowActions: !canReview && rows.every((f) => f.reviewedAt == null)
            ? null
            : (context, f) => f.reviewedAt != null
                  ? DashStatusPill(
                      label: t('access.review.reviewed'),
                      tone: DashTone.success,
                      small: true,
                    )
                  : canReview
                  ? DashButton(
                      key: ValueKey('review-mark-${f.id}'),
                      variant: DashButtonVariant.ghost,
                      size: DashButtonSize.compact,
                      loading: _reviewing.contains(f.id),
                      label: t('access.review.markReviewed'),
                      onPressed: () => _review(f),
                    )
                  : const SizedBox.shrink(),
        columns: [
          if (canReview)
            DashColumn<ReplayFlag>(
              id: 'pick',
              label: '',
              width: DashMetrics.target + Space.md,
              phone: DashPhoneRole.hidden,
              hideable: false,
              searchable: false,
              cell: (context, f) => f.reviewedAt != null
                  ? const SizedBox.shrink()
                  : DashCheckbox(
                      key: ValueKey('review-pick-${f.id}'),
                      value: _picked.contains(f.id),
                      semanticLabel: t('access.review.selectOne'),
                      onChanged: (_) => setState(
                        () => _picked = {..._picked}..toggle(f.id),
                      ),
                    ),
            ),
          DashColumn<ReplayFlag>(
            id: 'who',
            label: t('access.review.person'),
            phone: DashPhoneRole.title,
            flex: 2,
            minWidth: 140,
            text: (f) => f.authorName ?? '—',
            cell: (context, f) => MadarClippedText(
              f.authorName ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
          ),
          DashColumn<ReplayFlag>(
            id: 'reason',
            label: t('access.review.what'),
            flex: 4,
            minWidth: 220,
            text: (f) => _what(f, t).label,
            cell: (context, f) {
              final w = _what(f, t);
              return Align(
                alignment: AlignmentDirectional.centerStart,
                child: _ReasonPill(label: w.label, tone: w.tone),
              );
            },
          ),
          DashColumn<ReplayFlag>(
            id: 'capability',
            label: t('access.review.permission'),
            flex: 3,
            minWidth: 170,
            text: (f) => f.capability,
            cell: (context, f) {
              final read = readFlagCapability(f.capability);
              final meta = read.known == null
                  ? null
                  : capabilityMeta(read.capability);
              // Named the way the Roles screen names it; the key stays one
              // hover (or hold) away.
              if (meta != null) {
                return Tooltip(
                  message: f.capability,
                  child: Text(
                    bilingual(meta.en, meta.ar, lang),
                    style: DashType.body.copyWith(color: c.textPrimary),
                  ),
                );
              }
              return MadarClippedText(
                f.capability,
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.mono.copyWith(color: c.textSecondary),
              );
            },
          ),
          DashColumn<ReplayFlag>(
            id: 'when',
            label: t('access.review.when'),
            numeric: true,
            flex: 2,
            minWidth: 120,
            text: (f) => fmt.fmtStamp(f.occurredAt),
          ),
        ],
      ),
    );
  }

  /// Width of the bulk note box (`w-56`).
  static const double _noteWidth = Space.xxl * 7;

  /// Room for "Mark reviewed" (or the Reviewed pill) beside each row.
  static const double _actionsWidth = Space.xxl * 5;
}

/// The "What happened" cell: a known `capability:detail` says what happened
/// (the fixed reason would mislead); otherwise the reason's words, the raw
/// reason when unknown (ADM-REV-007, 008).
({String label, DashTone tone}) _what(ReplayFlag f, Translator t) {
  if (readFlagCapability(f.capability).known case final k?) {
    return (label: t(k.key), tone: k.tone);
  }
  final key = 'access.review.reasons.${f.reason}';
  return (
    label: t.exists(key) ? t(key) : f.reason,
    tone: reasonTone(f.reason),
  );
}

/// A bulk refusal's reason: the server's one sentence in our words; any other
/// server English stays off an Arabic screen (the core's rule).
String pendingWords(String reason, Translator t) {
  if (reason == 'no such open flag in this org') {
    return t('access.review.pendingNotOpen');
  }
  return t.isRtl && RegExp(r'^[\x00-\x7F]+$').hasMatch(reason)
      ? t('errors.unknown')
      : reason;
}

/// A status pill that wraps (the web's `h-auto whitespace-normal` pill for a
/// detail's sentence); the kit's pill is one line.
class _ReasonPill extends StatelessWidget {
  const _ReasonPill({required this.label, required this.tone});

  final String label;
  final DashTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final fg = tone.foreground(c);
    return Container(
      constraints: const BoxConstraints(minHeight: DashMetrics.pillSmall),
      padding: const EdgeInsetsDirectional.only(
        start: Space.xs + DashMetrics.hair,
        end: Space.sm,
        top: DashMetrics.hair,
        bottom: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        color: tone.wash(c),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          DashIcon(DashStatusPill.glyphFor(tone), size: 12, color: fg),
          Flexible(
            child: Text(
              label,
              style: DashType.tableHeader.copyWith(
                color: fg,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bordered toolbar control with its words beside it; the words press it
/// too (the web's `<Label>` around a switch).
class _ToolbarBox extends StatelessWidget {
  const _ToolbarBox({
    required this.control,
    required this.label,
    required this.onTap,
  });

  final Widget control;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      height: DashMetrics.target,
      padding: const EdgeInsetsDirectional.only(start: Space.xs, end: Space.md),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          control,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ExcludeSemantics(
              child: Text(
                label,
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension on Set<int> {
  void toggle(int id) {
    if (!remove(id)) add(id);
  }
}
