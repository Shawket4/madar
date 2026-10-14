// The plan gate: a Free organisation's nav, settings panes and routes lose
// the paid features; an unknown plan hides nothing; Free keeps selling.
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Free's features: none.
const Set<String> _free = <String>{};
const Set<String> _paid = <String>{
  'basira',
  'bookings',
  'branding',
  'dawam',
  'floor',
  'inventory',
  'kitchen',
  'loyalty',
  'online',
};

List<String> _shown(Set<String>? features) => [
  for (final l in navLeaves())
    if (leafVisible(
      l,
      Authz.platformAdmin(),
      modules: OrgModule.all,
      features: features,
    ))
      l.to,
];

void main() {
  test('a path belongs to the longest listed feature prefix', () {
    expect(featureOfPath('/inventory/counts'), 'inventory');
    expect(featureOfPath('/reports/inventory'), 'inventory');
    expect(featureOfPath('/settings/delivery-zones'), 'online');
    expect(featureOfPath('/settings/brand'), 'branding');
    expect(featureOfPath('/floor/'), 'floor');
    // On every plan.
    for (final p in [
      '/',
      '/orders',
      '/tills',
      '/customers',
      '/menu/items',
      '/menu/pricing',
      '/discounts',
      '/reports/financial',
      '/reports/operations',
      '/settings',
      '/settings/payment-methods',
      '/access/users',
    ]) {
      expect(featureOfPath(p), isNull, reason: p);
    }
  });

  test('Free loses the paid pages and keeps selling', () {
    final free = _shown(_free);
    for (final gone in [
      '/floor',
      '/bookings',
      '/basira',
      '/inventory/today',
      '/inventory/counts',
      '/inventory/purchasing',
      '/reports/inventory',
      '/staff/team',
      '/settings/loyalty',
      '/settings/delivery',
      '/settings/brand',
      '/settings/links',
      '/settings/bookings',
      '/settings/kitchen-stations',
    ]) {
      expect(free, isNot(contains(gone)), reason: gone);
    }
    for (final kept in [
      '/',
      '/orders',
      '/tills',
      '/customers',
      '/menu/items',
      '/discounts',
      '/reports/financial',
      '/reports/operations',
    ]) {
      expect(free, contains(kept), reason: kept);
    }
  });

  test('a paid plan, and an unknown one, lose nothing', () {
    final everything = _shown(null);
    expect(_shown(_paid), everything);
    expect(everything, contains('/inventory/today'));
    expect(everything, contains('/floor'));
  });

  test('the settings panes follow the plan the same way', () {
    List<String> panes(Set<String>? f) => [
      for (final g in visibleSettings(
        Authz.platformAdmin(),
        OrgModule.all,
        features: f,
      ))
        for (final i in g.items) i.to,
    ];
    final free = panes(_free);
    for (final gone in [
      '/settings/brand',
      '/settings/links',
      '/settings/delivery',
      '/settings/bookings',
      '/settings/qr',
      '/settings/loyalty',
      '/settings/kitchen-stations',
      '/settings/kitchen-routing',
    ]) {
      expect(free, isNot(contains(gone)), reason: gone);
    }
    expect(free, contains('/settings/payment-methods'));
    expect(panes(_paid), panes(null));
  });

  test('the plan check answers for a path, unknown meaning yes', () {
    expect(planHasPath(null, '/inventory/today'), isTrue);
    expect(planHasPath(_free, '/inventory/today'), isFalse);
    expect(planHasPath(_free, '/orders'), isTrue);
    expect(planHasPath(_paid, '/inventory/today'), isTrue);
  });

  test('Contact Madar opens WhatsApp with the message', () {
    final u = madarWhatsAppUri('Hello Madar');
    expect(u.host, 'wa.me');
    expect(u.path, '/$madarWhatsAppNumber');
    expect(u.queryParameters['text'], 'Hello Madar');
  });
}
