/// The Flutter dashboard's contracts: UI text (the web's own tables, i18next
/// semantics), the session and what the person may do, the org/branch/period
/// scope, the formatting rules, the capability registry, the navigation and
/// the routes contract every area implements, and the gateways the app fills
/// in (files, exports, realtime, preferences, the transport).
///
/// Mock implementations for tests and mock mode: `package:dashboard_core/mock.dart`.
library;

export 'src/api_provider.dart';
export 'src/authz/authz.dart';
export 'src/authz/authz_providers.dart';
export 'src/authz/gates.dart';
export 'src/data/core_api.dart';
export 'src/data/models.dart';
export 'src/format/format.dart';
export 'src/format/tz.dart'
    show
        appTimezone,
        ensureTimeZones,
        inZone,
        isKnownTimezone,
        isoString,
        parseJsDate,
        wallClock;
export 'src/gateways/export.dart';
export 'src/gateways/files.dart';
export 'src/gateways/preferences.dart';
export 'src/gateways/realtime.dart';
export 'src/generated/capabilities.dart';
export 'src/generated/nav.dart';
export 'src/i18n/i18n_providers.dart';
export 'src/i18n/loader.dart';
export 'src/i18n/plural.dart';
export 'src/i18n/strings.dart';
export 'src/kit/kit_l10n.dart';
export 'src/providers.dart';
export 'src/routes/nav.dart';
export 'src/routes/route.dart';
export 'src/scope/period.dart';
export 'src/scope/scope.dart';
export 'src/session/session.dart';
