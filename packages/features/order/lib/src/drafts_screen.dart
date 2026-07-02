/// Held orders (drafts) — parked carts the teller can restore later. A
/// pixel-and-behavior port of the Kotlin DraftsScreen.kt: the confident
/// board header (back chevron + teal tray tile + bold title), the
/// parked-cart cards (teal tray tile, name + item count, bold teal money,
/// danger discard tile), and the tray empty state. Tapping a card restores
/// the draft into the cart (replacing the current one) and closes the
/// screen; the trash tile discards it after a confirm. All state + rules
/// live in the core (cart::hold/restore_draft).
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/order_controller.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (DraftsScreen.kt) that fall between the 4-pt Space steps —
// kept verbatim so the Flutter chrome measures identically.

/// Draft card width cap (natives: widthIn(max = 560.dp)).
const double _cardMaxWidth = 560;

/// Header back chevron (natives: 17.dp) and title size (natives: 20.sp
/// Black).
const double _headerIconSize = 17;
const double _headerTitleSize = 20;

/// Header/card vertical insets (natives: 14.dp).
const double _headerVPad = 14;
const double _cardVPad = 14;

/// Header tone tile (natives: 34.dp square, Radii.sm).
const double _headerTile = 34;

/// Card leading tray tile (natives: 44.dp) and discard tile (40.dp).
const double _trayTile = 44;
const double _discardTile = 40;

/// Draft name (natives: 16.sp Bold) and count line (12.sp Medium).
const double _nameSize = 16;
const double _countSize = 12;

/// Money — the hero figure (natives: 18.sp Black teal tabular).
const double _moneySize = 18;

/// The held-orders manager. Takes the shared screen contract ([core] +
/// [onStateChanged]); pass the live order screen's [model] so a restore
/// mutates the SHARED cart state (adopting the draft's createdAt as the
/// cart's start timestamp — the natives' single AppModel); without it a
/// screen-local controller drives the list.
class DraftsScreen extends StatefulWidget {
  /// Creates the held-orders screen.
  const DraftsScreen({
    required this.core,
    required this.onStateChanged,
    this.model,
    super.key,
  });

  /// The core handle every bridge call goes through.
  final MadarCore core;

  /// Invoked after a restore/discard (the order screen's cart moved).
  final void Function() onStateChanged;

  /// The live order controller when shown over the order screen (shared
  /// cart state); null constructs a screen-local one.
  final OrderController? model;

  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  /// Screen-local controller, created (and disposed) only when the shell
  /// didn't hand in the live order controller.
  OrderController? _owned;

  OrderController get _model =>
      widget.model ??
      (_owned ??= OrderController(
        core: widget.core,
        onStateChanged: widget.onStateChanged,
      ));

  @override
  void initState() {
    super.initState();
    unawaited(_model.loadDrafts());
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  /// Restore the draft into the cart (replacing the current one) and close
  /// the screen — the natives' whole-card tap (with its LongPress haptic).
  Future<void> _restore(DraftView draft) async {
    MadarHaptics.impact();
    await _model.restoreDraft(draft.id);
    widget.onStateChanged();
    if (!mounted) return;
    await Navigator.of(context).maybePop(true);
  }

  /// Discard after an explicit confirm (a parked cart is real work).
  Future<void> _discard(DraftView draft) async {
    final ok = await showMadarSheet<bool>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => _DiscardDraftSheet(model: _model, draft: draft),
    );
    if (ok ?? false) {
      MadarHaptics.impact();
      await _model.discardDraft(draft.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final colors = context.madarColors;
        // Scaffold: every screen owns its own Material ancestor in this app.
        return Scaffold(
          backgroundColor: colors.bg,
          body: SafeArea(
            child: Column(
              children: [
                _DraftsHeader(
                  title: _model.tr('drafts.title'),
                  onBack: () =>
                      unawaited(Navigator.of(context).maybePop(false)),
                ),
                Expanded(
                  child: _model.drafts.isEmpty
                      ? EmptyState(
                          icon: 'tray',
                          title: _model.tr('drafts.empty'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsetsDirectional.all(Space.lg),
                          itemCount: _model.drafts.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: Space.md),
                          itemBuilder: (context, index) {
                            final draft = _model.drafts[index];
                            return Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: _cardMaxWidth,
                                ),
                                child: _DraftCard(
                                  model: _model,
                                  draft: draft,
                                  onRestore: () => unawaited(_restore(draft)),
                                  onDiscard: () => unawaited(_discard(draft)),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Confident board header — back chevron, a leading teal tone-tile behind
/// the tray glyph, and the bold title on a surface bar with a hairline.
class _DraftsHeader extends StatelessWidget {
  const _DraftsHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: colors.surface,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
              vertical: _headerVPad,
            ),
            child: Row(
              spacing: Space.sm,
              children: [
                Semantics(
                  button: true,
                  child: TactileScale(
                    onTap: onBack,
                    child: MadarIcon(
                      'chevron.backward',
                      tint: colors.textPrimary,
                      size: _headerIconSize,
                    ),
                  ),
                ),
                Container(
                  width: _headerTile,
                  height: _headerTile,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accentBg,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: MadarIcon(
                    'tray.full',
                    tint: colors.accent,
                    size: IconSize.lg,
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.h3.copyWith(
                      fontSize: _headerTitleSize,
                      fontWeight: FontWeight.w900,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(height: 1, color: colors.border),
      ],
    );
  }
}

/// A parked-cart card — leading teal tray tile, name + item count, bold
/// teal money (the hero figure), and a danger discard tile. The whole card
/// restores the draft.
class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.model,
    required this.draft,
    required this.onRestore,
    required this.onDiscard,
  });

  final OrderController model;
  final DraftView draft;
  final VoidCallback onRestore;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
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
                    '${draft.itemCount} ${model.tr('chrome.orders')}',
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
              currency: model.currency,
              style: MadarType.money.copyWith(
                fontSize: _moneySize,
                fontWeight: FontWeight.w900,
              ),
            ),
            Semantics(
              button: true,
              label: model.tr('sync.discard'),
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
class _DiscardDraftSheet extends StatelessWidget {
  const _DiscardDraftSheet({required this.model, required this.draft});

  final OrderController model;
  final DraftView draft;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
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
                  model.tr('drafts.title'),
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
            '${model.tr('chrome.orders')}',
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: model.tr('common.cancel'),
                  variant: ActionVariant.outline,
                  onTap: () => unawaited(Navigator.of(context).maybePop()),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: ActionButton(
                  label: model.tr('sync.discard'),
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
