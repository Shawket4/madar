/// Held orders (drafts) — parked carts the teller can restore later. A
/// pixel-and-behavior port of the Kotlin DraftsScreen.kt over the shared
/// Rust core: the shared MadarHeader, the parked-cart cards (teal tray
/// tile, name + item count, bold teal money, danger discard tile), and the
/// tray empty state. Tapping a card restores the draft into the cart
/// (replacing the current one) and closes the screen; the trash tile
/// discards it after a confirm. All state + rules live in the core
/// (cart::hold/restore_draft); the shared [orderProvider] means a restore
/// here mutates the SAME cart the order screen renders.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (DraftsScreen.kt) that fall between the 4-pt Space steps —
// kept verbatim so the Flutter chrome measures identically.

/// Draft card width cap (natives: widthIn(max = 560.dp)).
const double _cardMaxWidth = 560;

/// Card vertical insets (natives: 14.dp).
const double _cardVPad = 14;

/// Card leading tray tile (natives: 44.dp) and discard tile (40.dp).
const double _trayTile = 44;
const double _discardTile = 40;

/// Draft name (natives: 16.sp Bold) and count line (12.sp Medium).
const double _nameSize = 16;
const double _countSize = 12;

/// Money — the hero figure (natives: 18.sp Black teal tabular).
const double _moneySize = 18;

/// The held-orders manager, pushed over the order surface. Drives the
/// SHARED [orderProvider] so a restore mutates the same cart state the
/// order screen renders (adopting the draft's createdAt as the cart's start
/// timestamp — the natives' single AppModel).
class DraftsScreen extends ConsumerStatefulWidget {
  /// Creates the held-orders screen.
  const DraftsScreen({super.key});

  @override
  ConsumerState<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends ConsumerState<DraftsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(orderProvider.notifier).loadDrafts());
  }

  /// Restore the draft into the cart (replacing the current one) and close
  /// the screen — the natives' whole-card tap (with its LongPress haptic).
  Future<void> _restore(DraftView draft) async {
    MadarHaptics.impact();
    await ref.read(orderProvider.notifier).restoreDraft(draft.id);
    if (!mounted) return;
    await Navigator.of(context).maybePop(true);
  }

  /// Discard after an explicit confirm (a parked cart is real work).
  Future<void> _discard(DraftView draft) async {
    final ok = await showMadarSheet<bool>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => _DiscardDraftSheet(draft: draft),
    );
    if (ok ?? false) {
      MadarHaptics.impact();
      await ref.read(orderProvider.notifier).discardDraft(draft.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final drafts = ref.watch(orderProvider.select((s) => s.drafts));
    final currency = ref.watch(orderProvider.select((s) => s.currency));
    // Scaffold: every screen owns its own Material ancestor in this app.
    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          MadarHeader(
            title: bridge.tr(key: 'drafts.title'),
            onBack: () => Navigator.maybePop(context, false),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: drafts.isEmpty
                  ? EmptyState(
                      icon: 'tray',
                      title: bridge.tr(key: 'drafts.empty'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsetsDirectional.all(Space.lg),
                      itemCount: drafts.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: Space.md),
                      itemBuilder: (context, index) {
                        final draft = drafts[index];
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _cardMaxWidth,
                            ),
                            child: _DraftCard(
                              draft: draft,
                              currency: currency,
                              onRestore: () => unawaited(_restore(draft)),
                              onDiscard: () => unawaited(_discard(draft)),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A parked-cart card — leading teal tray tile, name + item count, bold
/// teal money (the hero figure), and a danger discard tile. The whole card
/// restores the draft.
class _DraftCard extends ConsumerWidget {
  const _DraftCard({
    required this.draft,
    required this.currency,
    required this.onRestore,
    required this.onDiscard,
  });

  final DraftView draft;
  final String currency;
  final VoidCallback onRestore;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bridge = ref.watch(bridgeProvider);
    return TactileScale(
      scale: 0.99,
      onTap: onRestore,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.md,
          vertical: _cardVPad,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.borderLight),
          boxShadow: MadarElevation.card.shadows(colors, dark: dark),
        ),
        child: Row(
          spacing: Space.md,
          children: [
            Container(
              width: _trayTile,
              height: _trayTile,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentBg,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: MadarIcon(
                'tray.full',
                tint: colors.accent,
                size: IconSize.xl,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(
                    draft.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.body.copyWith(
                      fontSize: _nameSize,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    '${draft.itemCount} ${bridge.tr(key: 'chrome.orders')}',
                    style: MadarType.label.copyWith(
                      fontSize: _countSize,
                      fontWeight: FontWeight.w500,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            // Money is the hero — heavy teal, tabular figures.
            MoneyText(
              draft.totalMinor,
              currency: currency,
              style: MadarType.money.copyWith(
                fontSize: _moneySize,
                fontWeight: FontWeight.w900,
              ),
            ),
            Semantics(
              button: true,
              label: bridge.tr(key: 'sync.discard'),
              child: TactileScale(
                onTap: onDiscard,
                child: Container(
                  width: _discardTile,
                  height: _discardTile,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.dangerBg,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: MadarIcon('trash', tint: colors.danger),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact discard confirmation — the parked cart's name + size, then a
/// Cancel / danger-Discard pair. Pops `true` on confirm.
class _DiscardDraftSheet extends ConsumerWidget {
  const _DiscardDraftSheet({required this.draft});

  final DraftView draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  bridge.tr(key: 'drafts.title'),
                  style: MadarType.h2.copyWith(color: colors.textPrimary),
                ),
              ),
              GestureDetector(
                onTap: () => unawaited(Navigator.of(context).maybePop()),
                behavior: HitTestBehavior.opaque,
                child: MadarIcon('xmark', tint: colors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${draft.name} · ${draft.itemCount} '
            '${bridge.tr(key: 'chrome.orders')}',
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: bridge.tr(key: 'common.cancel'),
                  variant: ActionVariant.outline,
                  onTap: () => unawaited(Navigator.of(context).maybePop()),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: ActionButton(
                  label: bridge.tr(key: 'sync.discard'),
                  variant: ActionVariant.danger,
                  icon: 'trash',
                  onTap: () => unawaited(Navigator.of(context).maybePop(true)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
