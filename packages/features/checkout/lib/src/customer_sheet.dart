import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/checkout_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Pick (or add) the manual customer a counter sale is for.
///
/// Works offline: the list is the synced one, and a customer added here is
/// usable at once and reaches the server through the queue. The phone shows
/// only for `customers.view`; anyone else sees its last four digits.
class CustomerSheet extends ConsumerStatefulWidget {
  const CustomerSheet({super.key});

  @override
  ConsumerState<CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends ConsumerState<CustomerSheet> {
  final _query = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  /// Where the name field's return key goes.
  final _phoneFocus = FocusNode();
  List<CustomerView> _results = const [];
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _query.dispose();
    _name.dispose();
    _phone.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  void _search(String q) {
    final bridge = ref.read(bridgeProvider);
    try {
      setState(() => _results = bridge.searchCustomers(query: q));
    } on MadarError catch (e) {
      setState(() => _error = bridge.humanMessage(e));
    }
  }

  void _pick(CustomerView c) {
    ref.read(checkoutProvider.notifier).attachCustomer(c);
    MadarSheet.close<void>(context);
  }

  void _save() {
    final bridge = ref.read(bridgeProvider);
    final phone = _phone.text.trim();
    try {
      final c = bridge.createCustomer(
        name: _name.text,
        phone: phone.isEmpty ? null : phone,
      );
      _pick(c);
    } on MadarError catch (e) {
      setState(() => _error = bridge.humanMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    final colors = context.madarColors;
    String t(String k) => bridge.tr(key: k);
    final canCreate = bridge.can(cap: Cap.customersCreate);

    Widget field(
      TextEditingController c,
      String hint, {
      MadarFieldKind kind = MadarFieldKind.text,
      ValueChanged<String>? onChanged,
      bool autofocus = false,
      FocusNode? focusNode,
      FocusNode? nextFocus,
    }) => MadarField(
      controller: c,
      placeholder: hint,
      kind: kind,
      onChanged: onChanged,
      autofocus: autofocus,
      focusNode: focusNode,
      nextFocus: nextFocus,
    );

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(
            t('customers.sheet_title'),
            style: MadarType.h3.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          if (!_adding) ...[
            field(
              _query,
              t('customers.search_hint'),
              kind: MadarFieldKind.search,
              autofocus: true,
              onChanged: _search,
            ),
            if (_results.isEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  vertical: Space.md,
                ),
                child: Text(
                  t('customers.none_found'),
                  style: MadarType.body.copyWith(color: colors.textMuted),
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final c in _results.take(8))
                _CustomerTile(
                  customer: c,
                  pendingLabel: t('customers.pending'),
                  onTap: () => _pick(c),
                ),
            if (canCreate)
              MadarButton(
                label: t('customers.add_new'),
                variant: MadarButtonVariant.secondary,
                onTap: () => setState(() {
                  _adding = true;
                  _error = null;
                  final q = _query.text.trim();
                  final digits = q.replaceAll(RegExp('[^0-9]'), '');
                  if (digits.length >= 3 && digits.length * 2 >= q.length) {
                    _phone.text = q;
                  } else {
                    _name.text = q;
                  }
                }),
              ),
          ] else ...[
            // Name then phone, in that order, on a hardware keyboard too:
            // the name's return key moves to the phone instead of dropping
            // focus and putting the keyboard away mid-form.
            field(
              _name,
              t('customers.name'),
              kind: MadarFieldKind.name,
              autofocus: true,
              nextFocus: _phoneFocus,
            ),
            field(
              _phone,
              t('customers.phone'),
              kind: MadarFieldKind.phone,
              focusNode: _phoneFocus,
            ),
            MadarButton(label: t('customers.save'), onTap: _save),
          ],
          if (_error != null)
            Text(
              _error!,
              style: MadarType.bodySm.copyWith(color: colors.danger),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({
    required this.customer,
    required this.pendingLabel,
    required this.onTap,
  });

  final CustomerView customer;
  final String pendingLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final phone = customer.phone ?? customer.phoneHint;
    final sub = [
      if (phone != null) MadarFormat.ltr(phone),
      if (customer.pending) pendingLabel,
    ].join(' · ');
    return Semantics(
      button: true,
      label: customer.name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer.name,
                style: MadarType.body.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (sub.isNotEmpty)
                Text(
                  sub,
                  style: MadarType.bodySm.copyWith(color: colors.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
