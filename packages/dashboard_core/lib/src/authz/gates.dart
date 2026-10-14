/// The gates a page sits behind: `components/app/restricted.tsx`,
/// `components/app/module-gate.tsx`, and a capability gate for actions.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/src/authz/authz_providers.dart';
import 'package:dashboard_core/src/authz/plan_gate.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/routes/nav.dart';
import 'package:dashboard_core/src/shell/shell_prefs.dart'
    show linkOpenerProvider;
import 'package:dashboard_kit/dashboard_kit.dart'
    show DashButton, DashErrorState;
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The words for a failure: an [ApiException]'s own (already human, in the
/// active language), else `errors.unknown`.
String errorMessage(Object? error, Translator t) {
  if (error is ApiException && error.message.isNotEmpty) return error.message;
  return t('errors.unknown', defaultValue: 'An unexpected error occurred.');
}

/// Refusals that mean the screen is stale: someone else decided, claimed or
/// handled it first (`STALE_CODES`, `data/api/errors.ts`). The page toasts
/// the words AND refreshes so the list says what is true.
const Set<String> staleRefusalCodes = {
  'REQUEST_ALREADY_DECIDED', 'ALREADY_DECIDED', 'FLAG_HANDLED', //
  'ALREADY_CLAIMED', 'CLAIM_ALREADY_DECIDED', 'NO_PENDING_CLAIM',
  'SWAP_STALE', 'SUGGESTION_STALE',
  // Nothing waiting any more: decided, withdrawn, filled or cancelled.
  'NO_CLAIM_WAITING', 'NO_SWAP_WAITING', 'NO_SWAP_TO_CANCEL',
  'OPEN_SHIFT_CLOSED', 'NO_COVER_WAITING', 'NO_OVERTIME_WAITING',
  'PAYSLIP_ALREADY_PAID',
  // A stock transfer moved on under this person (another side acted first).
  'TRANSFER_CHANGED', 'TRANSFER_STEP_NOT_OPEN',
};

/// Whether [error] is a stale refusal (`isStaleRefusal`).
bool isStaleRefusal(Object? error) =>
    error is ApiException && staleRefusalCodes.contains(error.code);

/// A page somebody reached that is not theirs to use (`<Restricted>`): the
/// page's title and a calm "not available on this account". The backend
/// refuses these routes regardless; this exists so nobody is shown a door
/// that will not open.
class Restricted extends ConsumerWidget {
  const Restricted({required this.title, this.who, super.key});

  final String title;

  /// Who it is for, instead of the default body.
  final String? who;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final state = EmptyState(
      icon: 'lock',
      title: t(
        'common.restrictedTitle',
        defaultValue: 'Not available on this account',
      ),
      message:
          who ??
          t(
            'common.restrictedBody',
            defaultValue:
                'This is managed by Madar. Get in touch if you need a change here.',
          ),
    );
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: LayoutBuilder(
          builder: (context, box) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: box.hasBoundedHeight
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: MadarType.h2.copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(height: Space.lg),
              // Fills the page when there is one; in a scroll view it sits
              // under the title.
              if (box.hasBoundedHeight) Expanded(child: state) else state,
            ],
          ),
        ),
      ),
    );
  }
}

/// Route-level module gating (PS-2, PS-3): a page of a module the org has
/// switched off is not reachable by its path, not just hidden from the nav.
/// The module of a path comes from the nav (`moduleOfPath`), the org's
/// modules from the server.
class ModuleGate extends ConsumerWidget {
  const ModuleGate({required this.path, required this.child, super.key});

  /// The current location's path.
  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Every page, module or not: with the permissions unread every action
    // would hide with no reason given (the web's `useAuthzLoadError`, SH-10).
    if (ref.watch(authzProvider.select((a) => !a.ready && a.error != null))) {
      return const AuthzLoadError();
    }
    // The plan first: a page of a feature the plan does not have is not
    // reachable by its path either, whatever the modules say.
    final features = ref.watch(planFeaturesProvider);
    if (!planHasPath(features, path)) {
      return PlanLocked(feature: featureOfPath(path));
    }
    final needs = moduleOfPath(path);
    if (needs == null) return child;
    final mods = ref.watch(orgModulesProvider);
    final t = ref.watch(tProvider);
    if (!mods.known && mods.error != null) {
      // Say so: a blank page (or every module on a guess) is worse.
      return Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: ErrorState(
          message:
              '${t('dawam.modulesLoadError', defaultValue: "Couldn't check what this business has switched on")}\n'
              '${errorMessage(mods.error, t)}',
          retryLabel: t('common.retry', defaultValue: 'Retry'),
          onRetry: () => retryOrgModules(ref),
        ),
      );
    }
    if (!mods.known) return const SizedBox.shrink();
    if (!mods.has(needs)) {
      return Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: EmptyState(
          icon: 'layers',
          title: t(
            'dawam.moduleOffTitle',
            defaultValue: "Not part of this business's plan",
          ),
          message: needs == 'dawam'
              ? t(
                  'dawam.moduleDawamOff',
                  defaultValue:
                      'Dawam by Madar is switched off for this business. Ask Madar to switch it on.',
                )
              : t(
                  'dawam.modulePosOff',
                  defaultValue:
                      'Madar POS is switched off for this business. Ask Madar to switch it on.',
                ),
        ),
      );
    }
    return child;
  }
}

/// Madar's number, where "Contact Madar" opens WhatsApp (the web's
/// `MADAR_PHONE_E164`, `config/contact.ts`).
const String madarWhatsAppNumber = '201211116899';

/// WhatsApp click-to-chat to Madar with [text] prefilled.
Uri madarWhatsAppUri(String text) =>
    Uri.https('wa.me', '/$madarWhatsAppNumber', {'text': text});

/// A page the organisation's plan does not have: "`feature` is on the paid
/// plan" and a way to contact Madar (the web's upgrade page). Nothing is
/// lost by upgrading: the body says so.
class PlanLocked extends ConsumerWidget {
  const PlanLocked({required this.feature, super.key});

  /// The `madar_plan::Feature` word, or null for a page with no name for it.
  final String? feature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final name = feature == null ? null : t('plan.features.$feature');
    final title = name == null
        ? t('plan.upgrade.hint', defaultValue: 'On the paid plan')
        : t('plan.upgrade.title', args: {'feature': name});
    final message = name == null
        ? t(
            'plan.upgrade.messageGeneric',
            defaultValue:
                'Hello Madar, I would like to move my shop to the paid plan.',
          )
        : t('plan.upgrade.message', args: {'feature': name});
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyState(
            icon: 'lock',
            title: title,
            message: t('plan.upgrade.body'),
          ),
          const SizedBox(height: Space.lg),
          DashButton(
            key: const ValueKey('plan-contact'),
            label: t('plan.upgrade.cta'),
            icon: 'message-circle',
            onPressed: () => unawaited(
              ref.read(linkOpenerProvider)(madarWhatsAppUri(message)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The person's permissions could not be read and nothing is remembered:
/// the shell's `shell.accessLoadError`, the failure's words and Retry.
class AuthzLoadError extends ConsumerWidget {
  const AuthzLoadError({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: DashErrorState(
        title: t('shell.accessLoadError'),
        message: errorMessage(ref.watch(authzProvider).error, t),
        retryLabel: t('common.retry'),
        onRetry: () => ref.read(authzProvider.notifier).refresh(),
      ),
    );
  }
}

/// Shows [child] when the person holds ANY of [anyOf] (the web's
/// `authz.canAny(...)` around a control), else [fallback] (nothing by
/// default). An empty [anyOf] always shows.
class CapGate extends ConsumerWidget {
  const CapGate({
    required this.anyOf,
    required this.child,
    this.fallback = const SizedBox.shrink(),
    super.key,
  });

  final List<String> anyOf;
  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (anyOf.isEmpty) return child;
    final ok = ref.watch(authzProvider.select((a) => a.canAny(anyOf)));
    return ok ? child : fallback;
  }
}
