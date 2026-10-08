/// The till badges (`features/tills/till-badges.tsx`): status (SELL-TIL-017),
/// verification (SELL-TIL-018), the "opened while another till was open"
/// flag with its link to the other till (SELL-TIL-019) and the payment-check
/// mismatch count (SELL-TIL-020).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Till, TillStatus, TillVerification;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Open is success with a dot, closed neutral, force closed warning.
class TillStatusBadge extends StatelessWidget {
  const TillStatusBadge({required this.status, super.key});

  final TillStatus status;

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = switch (status.value) {
      'open' => (DashTone.success, 'circle-dot'),
      'force_closed' => (DashTone.warning, 'alert-triangle'),
      _ => (DashTone.neutral, 'circle'),
    };
    final t = context.translator;
    final key = 'tillStatus.${status.value}';
    return DashStatusPill(
      label: t.exists(key) ? t(key) : status.value.replaceFirst('_', ' '),
      tone: tone,
      icon: icon,
      small: true,
    );
  }
}

/// Only the non-default verifications earn a badge: server-verified (and a
/// pre-rework till) is the norm.
class VerificationBadge extends StatelessWidget {
  const VerificationBadge({required this.verification, super.key});

  final TillVerification verification;

  static bool shows(TillVerification v) =>
      v == TillVerification.unverified || v == TillVerification.lan;

  @override
  Widget build(BuildContext context) {
    if (!shows(verification)) return const SizedBox.shrink();
    final lan = verification == TillVerification.lan;
    return DashStatusPill(
      key: const ValueKey('verification-badge'),
      label: context.t(
        lan ? 'tills.verification.lan' : 'tills.verification.unverified',
      ),
      tone: lan ? DashTone.neutral : DashTone.warning,
      icon: lan ? 'wifi' : 'shield-question',
      small: true,
    );
  }
}

/// "Opened while another till was open", and — when the other till is known
/// and [onOpenOther] is given — an underlined "See the other till" that
/// opens that till's report without opening the row under it.
class FlagBadge extends StatelessWidget {
  const FlagBadge({required this.till, this.onOpenOther, super.key});

  final Till till;
  final ValueChanged<String>? onOpenOther;

  @override
  Widget build(BuildContext context) {
    if (!till.openedWhileAnotherOpen) return const SizedBox.shrink();
    final other = till.otherTillId;
    final open = onOpenOther;
    return Wrap(
      key: const ValueKey('flag-badge'),
      spacing: Space.xs + DashMetrics.hair,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DashStatusPill(
          label: context.t('tills.flagged'),
          tone: DashTone.warning,
          small: true,
        ),
        if (other != null && open != null)
          _FlagLink(
            label: context.t('tills.flaggedLink'),
            onTap: () => open(other),
          ),
      ],
    );
  }
}

class _FlagLink extends StatelessWidget {
  const _FlagLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        child: Align(
          widthFactor: 1,
          child: Text(
            label,
            style: DashType.smallMedium.copyWith(
              color: s.highlighted ? c.textPrimary : c.textSecondary,
              decoration: TextDecoration.underline,
              decorationColor: s.highlighted ? c.textPrimary : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// "{{count}} mismatches" when the payment check disagreed.
class DisagreementBadge extends StatelessWidget {
  const DisagreementBadge({required this.till, super.key});

  final Till till;

  static bool shows(Till t) =>
      t.reconciliationStatus == 'disagreed' && t.disagreementCount > 0;

  @override
  Widget build(BuildContext context) {
    if (!shows(till)) return const SizedBox.shrink();
    return DashStatusPill(
      key: const ValueKey('disagreement-badge'),
      label: context.t(
        'tills.reconciliation.disagreements',
        count: till.disagreementCount,
      ),
      tone: DashTone.danger,
      small: true,
    );
  }
}

/// Every badge a till earns, in the web's order.
List<Widget> tillBadges(
  Till till, {
  bool status = true,
  ValueChanged<String>? onOpenOther,
}) => [
  if (status) TillStatusBadge(status: till.status),
  if (VerificationBadge.shows(till.verification))
    VerificationBadge(verification: till.verification),
  if (till.openedWhileAnotherOpen)
    FlagBadge(till: till, onOpenOther: onOpenOther),
  if (DisagreementBadge.shows(till)) DisagreementBadge(till: till),
];
