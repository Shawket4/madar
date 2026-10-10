/// The Refresh button in every Dawam page header (`dawam/refresh-button.tsx`,
/// TEAM-ALL-008): an outline icon button whose tooltip and label read
/// "Refresh", or "Refreshing…" while any of the page's reads is fetching; the
/// glyph spins meanwhile (reduced motion: it dims instead). A tap refetches
/// the page's mounted reads under its prefixes (default `/staff`, segment
/// bounded) and stays tappable while busy: a tap then joins the fetch in
/// flight rather than starting over.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'staff_query.dart';

class DawamRefreshButton extends ConsumerStatefulWidget {
  const DawamRefreshButton({
    this.busy = false,
    this.prefixes = const [dawamKeyPrefix],
    this.onRefresh,
    super.key,
  });

  /// Whether any of the page's reads is fetching (`anyFetching(...)`).
  final bool busy;

  /// Key prefixes the page reads; Set-up adds `/branches`.
  final List<String> prefixes;

  /// Called after the refetch is asked for: reads the team revisions do not
  /// reach (Set-up invalidates the core's `branchesProvider`).
  final VoidCallback? onRefresh;

  @override
  ConsumerState<DawamRefreshButton> createState() => _DawamRefreshButtonState();
}

class _DawamRefreshButtonState extends ConsumerState<DawamRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _refresh() {
    // A tap while busy joins the fetch in flight (`cancelRefetch: false`).
    if (widget.busy) return;
    ref.read(staffRevisionsProvider.notifier).refetch(widget.prefixes);
    widget.onRefresh?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final busy = widget.busy;
    if (busy && !reduce) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin
        ..stop()
        ..value = 0;
    }
    final label = busy ? t('common.refreshing') : t('common.refresh');
    final radius = BorderRadius.circular(Radii.sm);
    return DashPressable(
      onTap: _refresh,
      semanticLabel: label,
      tooltip: label,
      excludeChildSemantics: true,
      builder: (context, s) {
        final colors = dashButtonColors(
          context,
          DashButtonVariant.outline,
          s,
          enabled: true,
        );
        Widget glyph = DashIcon('refresh-cw', color: colors.fg);
        if (busy) {
          glyph = reduce
              ? Opacity(opacity: 0.5, child: glyph)
              : RotationTransition(turns: _spin, child: glyph);
        }
        return Container(
          width: DashMetrics.target,
          height: DashMetrics.target,
          alignment: Alignment.center,
          foregroundDecoration: dashFocusRing(context, s, radius),
          decoration: BoxDecoration(
            color: colors.fill,
            borderRadius: radius,
            border: colors.edge == null
                ? null
                : Border.all(color: colors.edge!),
          ),
          child: glyph,
        );
      },
    );
  }
}
