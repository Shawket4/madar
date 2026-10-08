/// The gates a page sits behind: `components/app/restricted.tsx`,
/// `components/app/module-gate.tsx`, and a capability gate for actions.
library;

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/src/authz/authz_providers.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/routes/nav.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The words for a failure: an [ApiException]'s own (already human, in the
/// active language), else `errors.unknown`.
String errorMessage(Object? error, Translator t) {
  if (error is ApiException && error.message.isNotEmpty) return error.message;
  return t('errors.unknown', defaultValue: 'An unexpected error occurred.');
}

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
