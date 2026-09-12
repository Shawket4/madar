/// One kitchen ticket as a 16px card: an age-tinted header where the table
/// label is the largest thing (as on the printed chit), the lines with their
/// check toggles, and one Bump all. Shared by the kitchen board and Queue's
/// Kitchen segment, so a cook and a cashier read the same card.
library;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_kds/src/kds_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Age escalation thresholds (minutes) — fresh teal → amber → red.
const int kdsAgeWarnMinutes = 5;
const int kdsAgeDangerMinutes = 10;

/// The check toggle's side. Sits between the 4-pt steps on purpose: it must
/// read from across a kitchen, and 20 does not.
const double _check = 22;

/// A line row's floor. Shorter than the kit's 64 row — a card with six lines
/// still has to fit a column — but never under the 44 touch floor.
const double _lineMinHeight = 48;

/// The tone a ticket's age (or readiness) paints its header with.
MadarTone kdsAgeTone(int ageMinutes, {required bool ready}) {
  if (ready) return MadarTone.success;
  if (ageMinutes >= kdsAgeDangerMinutes) return MadarTone.danger;
  if (ageMinutes >= kdsAgeWarnMinutes) return MadarTone.warning;
  return MadarTone.accent;
}

/// The card. Stateless over the [ticket] plus what the notifier says is in
/// flight; taps go back up through the callbacks.
class KdsTicketCard extends ConsumerWidget {
  const KdsTicketCard({
    required this.ticket,
    required this.ageMinutes,
    required this.onToggleLine,
    required this.onBumpAll,
    this.busyLineIds = const {},
    this.bumpingAll = false,
    super.key,
  });

  final KdsTicketView ticket;

  /// Already corrected for clock skew — the notifier's `ageMinutes`.
  final int ageMinutes;
  final void Function(KdsLineView line) onToggleLine;
  final VoidCallback onBumpAll;
  final Set<String> busyLineIds;
  final bool bumpingAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    // The server flips a ticket to `ready` once every line is bumped; the
    // pending-bump overlay may get there first. Either way the card is done.
    final ready =
        ticket.status == 'ready' || ticket.items.every((l) => l.bumped);
    final tone = kdsAgeTone(ageMinutes, ready: ready);
    return MadarCard(
      flush: true,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(ticket: ticket, ageMinutes: ageMinutes, tone: tone),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
              vertical: Space.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in ticket.items)
                  _LineRow(
                    key: ValueKey(line.id),
                    line: line,
                    busy: busyLineIds.contains(line.id),
                    onTap: () => onToggleLine(line),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: Space.lg,
              end: Space.lg,
              bottom: Space.lg,
              top: Space.xs,
            ),
            child: ready
                ? Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: MadarTag(
                      label: bridge.trOr(KdsKeys.ready),
                      tone: MadarTone.success,
                      glyph: MadarGlyph.check,
                    ),
                  )
                // Secondary, not primary: a wall of eight teal buttons is
                // noise, and the header's tint already says which card is
                // urgent. It is still the only button on the card.
                : MadarButton(
                    label: bridge.trOr(KdsKeys.bumpAll),
                    variant: MadarButtonVariant.secondary,
                    size: MadarButtonSize.compact,
                    glyph: MadarGlyph.checkCircle,
                    loading: bumpingAll,
                    onTap: onBumpAll,
                  ),
          ),
        ],
      ),
    );
  }
}

/// The age-tinted strip: table label (or the order's kitchen ref) at 22
/// bold, the round tag for a waiter's card, the age in mono at the end.
/// Fixed height, so every card's first line starts at the same y.
class _Header extends ConsumerWidget {
  const _Header({
    required this.ticket,
    required this.ageMinutes,
    required this.tone,
  });

  final KdsTicketView ticket;
  final int ageMinutes;
  final MadarTone tone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final colors = context.madarColors;
    final fg = tone.color(colors);
    final label = ticket.tableLabel ?? ticket.kitchenRef;
    final roundWord = bridge.trMaybe(KdsKeys.round);
    final unit = bridge.trMaybe(KdsKeys.ageMin);
    final fromWaiter = ticket.sourceType == 'open_ticket';
    return Container(
      height: Metrics.rowHeight,
      color: tone.tint(colors),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
      child: Row(
        spacing: Space.sm,
        children: [
          Flexible(
            child: Text(
              // A card with neither a table nor a kitchen ref (an old
              // teller order) is named by its round, the way it always was.
              label ?? '#${ticket.roundNumber}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.h2.copyWith(color: colors.textPrimary),
            ),
          ),
          if (fromWaiter && label != null)
            _RoundTag(word: roundWord, round: ticket.roundNumber, fg: fg),
          if (fromWaiter)
            MadarGlyphIcon(
              MadarGlyph.user,
              size: IconSize.md,
              color: fg,
              semanticLabel: bridge.tr(key: 'kds.waiter'),
            ),
          const Spacer(),
          if (unit == null)
            MadarGlyphIcon(MadarGlyph.clock, size: IconSize.md, color: fg),
          Text(
            unit == null ? '$ageMinutes' : '$ageMinutes$unit',
            // The figure is an LTR island in both scripts.
            textDirection: TextDirection.ltr,
            style: MadarType.moneyMd.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

/// "R3" once `kds.round` lands; "#3" until then — a symbol, not a word in
/// the wrong language.
class _RoundTag extends StatelessWidget {
  const _RoundTag({required this.word, required this.round, required this.fg});

  final String? word;
  final int round;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${word ?? '#'}$round',
      textDirection: TextDirection.ltr,
      style: MadarType.numMd.copyWith(color: fg),
    );
  }
}

/// One tappable line: the check toggle, qty × name (+ size), modifiers, an
/// optional kitchen note (warning-tinted), and the station label the expo
/// board needs. Bumped lines mute and strike through; a line in flight
/// spins where its check was.
class _LineRow extends StatefulWidget {
  const _LineRow({
    required this.line,
    required this.busy,
    required this.onTap,
    super.key,
  });

  final KdsLineView line;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
  // Bump each time the cook bumps the line (a recall plays nothing);
  // SweepCheck runs one sweep per increment and is the bare row while idle.
  int _play = 0;

  void _handleTap() {
    if (widget.busy) return;
    if (!widget.line.bumped) setState(() => _play++);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final colors = context.madarColors;
    final done = line.bumped;
    final textColor = done ? colors.textMuted : colors.textPrimary;
    final size = line.sizeLabel;
    final notes = line.notes?.trim();
    final station = line.stationName?.trim();
    return Semantics(
      button: true,
      toggled: done,
      child: TactileScale(
        onTap: _handleTap,
        child: SweepCheck(
          play: _play,
          borderRadius: BorderRadius.zero,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _lineMinHeight),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                vertical: Space.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.md,
                children: [
                  SizedBox.square(
                    dimension: _check,
                    child: widget.busy
                        ? Padding(
                            padding: const EdgeInsets.all(2),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: colors.accent,
                            ),
                          )
                        : MadarGlyphIcon(
                            done ? MadarGlyph.checkCircle : MadarGlyph.ring,
                            size: _check,
                            filled: done,
                            color: done ? colors.success : colors.textMuted,
                          ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              // The quantity is a mono LTR figure inside
                              // whichever script the name is in.
                              TextSpan(
                                text: '${line.qty}× ',
                                style: MadarType.numLg.copyWith(
                                  color: textColor,
                                ),
                              ),
                              TextSpan(text: line.name),
                              if (size != null) TextSpan(text: ' · $size'),
                            ],
                          ),
                          style: MadarType.title.copyWith(
                            color: textColor,
                            decoration: done
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            decorationColor: colors.textMuted,
                          ),
                        ),
                        if (line.modifiers.isNotEmpty)
                          Text(
                            line.modifiers.join(', '),
                            style: MadarType.bodySm.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        if (notes != null && notes.isNotEmpty)
                          Text(
                            notes,
                            style: MadarType.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.warning,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // The routing hint: which station makes this line. The
                  // expo (all-station) board lives on it; a bound station
                  // sees its own name, which is harmless.
                  if (station != null && station.isNotEmpty)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 2),
                      child: Text(
                        station.toUpperCase(),
                        style: MadarType.labelSm.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
