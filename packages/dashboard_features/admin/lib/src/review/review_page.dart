/// `/access/review` Review (ADM-REV-001..017): offline acts the permission
/// check did not back and PINs tried at the wrong branch; "Show reviewed",
/// mark one reviewed, pick several and resolve them in bulk. No page gate on
/// the web: without `approvals.review` the read is refused and the table
/// shows its error state (ADM-REV-004). Web: `features/access/{review-page,
/// flag-detail}.tsx`.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/access_tabs.dart';
import '../shared/pending_body.dart';

class ReviewPage extends ConsumerWidget {
  const ReviewPage({super.key});

  static const String path = AccessPaths.review;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DashPageScaffold(
    title: ref.t('access.review.title'),
    subtitle: ref.t('access.review.subtitle'),
    tabs: const AccessSectionTabs(),
    body: const AdminPendingBody(icon: 'shield-check'),
  );
}
