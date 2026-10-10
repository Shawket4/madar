/// The quiet note several settings panes open with (`rounded-xl
/// bg-secondary/60 p-3 text-sm text-muted-foreground` on the web): the
/// read-only notice (Loyalty, Staff drinks, Combos) and the "this branch
/// follows the organisation" notice (Loyalty, Staff drinks).
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

class SetupNote extends StatelessWidget {
  const SetupNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Text(text, style: DashType.body.copyWith(color: c.textSecondary)),
    );
  }
}
