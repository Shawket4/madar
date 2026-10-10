/// The studio preview's selection model (the web's
/// `features/menu/studio/preview/preview-model.ts`) and its price line.
library;

import 'package:dashboard_api/dashboard_api.dart';

/// One offered, active option of an attached group.
typedef PreviewOption = ({String id, String name, int price});

/// An attached group as the preview offers it.
class PreviewGroup {
  const PreviewGroup({
    required this.id,
    required this.name,
    required this.single,
    required this.required,
    required this.options,
    this.max,
  });

  final String id;
  final String name;

  /// Radio-like: picking one replaces the previous pick.
  final bool single;
  final bool required;
  final int? max;
  final List<PreviewOption> options;
}

/// `takeaway` (the default) or `dine_in`.
typedef ServiceMode = String;

class PreviewSelection {
  const PreviewSelection({
    this.size,
    this.picks = const {},
    this.optionals = const [],
    this.service = 'takeaway',
    this.quantity = 1,
  });

  /// A size label; null = the server's default.
  final String? size;

  /// Group id → picked option ids. Absent = untouched (the default applies).
  final Map<String, List<String>> picks;

  /// Item-only option ids.
  final List<String> optionals;
  final ServiceMode service;
  final int quantity;

  PreviewSelection copyWith({
    String? size,
    Map<String, List<String>>? picks,
    List<String>? optionals,
    ServiceMode? service,
    int? quantity,
  }) => PreviewSelection(
    size: size ?? this.size,
    picks: picks ?? this.picks,
    optionals: optionals ?? this.optionals,
    service: service ?? this.service,
    quantity: quantity ?? this.quantity,
  );
}

/// `toPreviewGroups`: attached groups by sort, offered active options only,
/// groups with none dropped.
List<PreviewGroup> toPreviewGroups(StudioAggregate s) {
  final ordered = s.modifierGroups.indexed.toList()
    ..sort((a, b) {
      final c = a.$2.sort - b.$2.sort;
      return c != 0 ? c : a.$1 - b.$1;
    });
  return [
    for (final (_, g) in ordered)
      if (g.options.any((o) => o.included && o.isActive))
        PreviewGroup(
          id: g.groupId,
          name: g.name,
          single: g.selectionType == 'single' || g.max == 1,
          required: g.isRequired || g.min > 0,
          max: g.max,
          options: [
            for (final o in g.options)
              if (o.included && o.isActive)
                (id: o.id, name: o.name, price: o.price),
          ],
        ),
  ];
}

/// The ids chosen in a group: explicit picks, else the recipe default.
List<String> pickedIn(
  PreviewSelection sel,
  String groupId,
  Map<String, String> defaults,
) =>
    sel.picks[groupId] ??
    (defaults[groupId] == null ? const [] : [defaults[groupId]!]);

PreviewSelection togglePick(
  PreviewSelection sel,
  PreviewGroup group,
  String optionId,
  Map<String, String> defaults,
) {
  final current = pickedIn(sel, group.id, defaults);
  final on = current.contains(optionId);
  final List<String> next;
  if (group.single) {
    next = on ? (group.required ? current : const []) : [optionId];
  } else if (on) {
    next = [
      for (final id in current)
        if (id != optionId) id,
    ];
  } else {
    next = group.max != null && current.length >= group.max!
        ? current
        : [...current, optionId];
  }
  return sel.copyWith(picks: {...sel.picks, group.id: next});
}

PreviewSelection toggleOptional(PreviewSelection sel, String id) =>
    sel.copyWith(
      optionals: sel.optionals.contains(id)
          ? [
              for (final x in sel.optionals)
                if (x != id) x,
            ]
          : [...sel.optionals, id],
    );

/// The request body (`toPreviewBody`).
PreviewRequest toPreviewBody(
  PreviewSelection sel,
  List<PreviewGroup> groups,
  Map<String, String> defaults,
) => PreviewRequest(
  sizeLabel: sel.size,
  optionIds: [
    for (final g in groups) ...pickedIn(sel, g.id, defaults),
    ...sel.optionals,
  ],
  quantity: sel.quantity < 1 ? 1 : sel.quantity,
  serviceMode: sel.service,
);

/// "150 + 55 + 30 = 235", with "(…) × q" when q > 1; zero deltas left out.
/// [plain] formats piastres as a bare figure.
String priceLine(
  PreviewPrice price,
  int quantity,
  String Function(num piastres) plain,
) {
  final parts = [
    price.base,
    for (final o in price.options)
      if (o.priceDelta != 0) o.priceDelta,
  ].map(plain);
  final sum = parts.join(' + ');
  final lhs = quantity > 1 ? '($sum) × $quantity' : sum;
  return '$lhs = ${plain(price.total)}';
}
