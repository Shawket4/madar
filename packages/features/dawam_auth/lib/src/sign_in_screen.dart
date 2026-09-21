import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

/// The demo's WhatsApp code. The real one is the core's OTP (RO-2).
const demoCode = '123456';

enum _Step { phone, code, org, privacy }

/// Sign-in: WhatsApp number and code (RO-2), the business pick (RO-5), the
/// privacy notice (AT-5). On a tablet the shared brand panel stands beside
/// the form, as on the POS.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  _Step _step = _Step.phone;
  late Emp _who;
  String? _error;
  int _attempts = 5;
  int _left = 300;
  bool _newPhone = false;
  Timer? _timer;

  DawamStore get _store => ref.read(dawamProvider);

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _sendCode() {
    final e = _store.byPhone(_phone.text.trim());
    if (e == null) {
      setState(() => _error = tr('staff.this_number_isn_t_registered_with'));
      return;
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) _back(tr('staff.the_code_expired_send_a_new'));
    });
    setState(() {
      _who = e;
      _error = null;
      _attempts = 5;
      _left = 300;
      _code.clear();
      _step = _Step.code;
    });
  }

  void _back([String? why]) {
    _timer?.cancel();
    setState(() {
      _step = _Step.phone;
      _error = why;
    });
  }

  void _verify() {
    if (_code.text.trim() != demoCode) {
      _attempts--;
      if (_attempts <= 0) return _back(tr('staff.too_many_tries_send_a_new'));
      setState(
        () =>
            _error = tr('staff.wrong_code_tries_left', {'attempts': _attempts}),
      );
      return;
    }
    _timer?.cancel(); // the code is deleted on use
    setState(() {
      _error = null;
      _step = _store.orgsFor(_who).length > 1 ? _Step.org : _Step.privacy;
    });
    if (_step == _Step.privacy) _privacyOrFinish();
  }

  void _privacyOrFinish() {
    if (_store.privacyAccepted.contains(_who.id)) _finish();
  }

  void _finish() => _store.signIn(_who.id, newPhone: _newPhone);

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final c = context.madarColors;
    return MadarPageScaffold(
      bodyInset: false,
      body: MadarBrandSplit(
        brand: MadarBrandPanel(
          headline: tr('staff.brand_headline'),
          tagline: tr('staff.brand_tagline'),
          arabic: isAr,
        ),
        compactHeader: const DawamMark(),
        form: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: MadarButton(
                label: isAr ? 'English' : 'العربية',
                variant: MadarButtonVariant.ghost,
                size: MadarButtonSize.compact,
                glyph: MadarGlyph.globe,
                onTap: () =>
                    ref.read(localeProvider.notifier).set(isAr ? 'en' : 'ar'),
              ),
            ),
            ...switch (_step) {
              _Step.phone => _phoneStep(c),
              _Step.code => _codeStep(c),
              _Step.org => _orgStep(c),
              _Step.privacy => _privacyStep(c),
            },
            if (_error != null && _error!.isNotEmpty)
              NoticeBanner(text: _error!, tone: ChipTone.danger),
          ],
        ),
      ),
    );
  }

  Widget _lede(String title, String body, MadarColors c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: Space.sm,
    children: [
      Text(title, style: MadarType.h1),
      Text(body, style: MadarType.body.copyWith(color: c.textSecondary)),
    ],
  );

  List<Widget> _phoneStep(MadarColors c) => [
    _lede(
      tr('staff.sign_in_with_your_whatsapp_number'),
      tr('staff.the_number_your_manager_registered_we'),
      c,
    ),
    MadarField(
      controller: _phone,
      placeholder: '01X XXXX XXXX',
      kind: MadarFieldKind.phone,
      glyph: MadarGlyph.phone,
      onSubmitted: (_) => _sendCode(),
    ),
    MadarButton(label: tr('staff.send_code'), onTap: _sendCode),
    const SizedBox(height: Space.sm),
    MadarSectionHeader(text: tr('staff.demo_accounts')),
    for (final (id, role) in [
      ('e1', tr('staff.employee')),
      ('e4', tr('staff.employee_evenings')),
      ('e2', tr('staff.branch_manager')),
      ('e3', tr('staff.owner')),
    ])
      MadarListRow.nav(
        title: name(_store.emp(id)),
        meta: role,
        onTap: () {
          _phone.text = _store.emp(id).phone;
          _sendCode();
        },
      ),
  ];

  List<Widget> _codeStep(MadarColors c) => [
    _lede(
      tr('staff.enter_the_code'),
      tr('staff.sent_on_whatsapp_to', {'phone': _who.phone}),
      c,
    ),
    MadarField(
      controller: _code,
      placeholder: '••••••',
      kind: MadarFieldKind.code,
      autofocus: true,
      onSubmitted: (_) => _verify(),
    ),
    Row(
      children: [
        Expanded(
          child: Text(
            tr('staff.expires_in', {
              'time':
                  '${_left ~/ 60}:${(_left % 60).toString().padLeft(2, '0')}',
            }),
            style: MadarType.bodySm.copyWith(color: c.textMuted),
          ),
        ),
        MadarTag(label: '${tr('staff.demo_code')}$demoCode'),
      ],
    ),
    MadarCard(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr('staff.demo_this_is_a_new_phone'),
              style: MadarType.bodySm,
            ),
          ),
          Switch.adaptive(
            value: _newPhone,
            onChanged: (v) => setState(() => _newPhone = v),
          ),
        ],
      ),
    ),
    MadarButton(label: tr('staff.verify'), onTap: _verify),
    MadarButton(
      label: tr('staff.change_number'),
      variant: MadarButtonVariant.ghost,
      onTap: _back,
    ),
  ];

  List<Widget> _orgStep(MadarColors c) => [
    _lede(
      tr('staff.which_business'),
      tr('staff.you_work_for_more_than_one'),
      c,
    ),
    for (final (en, ar, active) in _store.orgsFor(_who))
      MadarListRow.bill(
        title: isAr ? ar : en,
        status: active
            ? MadarStatus(tr('staff.active'), tone: MadarTone.success)
            : MadarStatus(tr('staff.suspended'), tone: MadarTone.danger),
        onTap: active
            ? () {
                setState(() => _step = _Step.privacy);
                _privacyOrFinish();
              }
            : () => setState(
                () => _error = tr('staff.is_suspended_sign_in_is_stopped', {
                  'name': isAr ? ar : en,
                }),
              ),
      ),
  ];

  List<Widget> _privacyStep(MadarColors c) => [
    _lede(tr('staff.before_you_start'), tr('staff.privacy_lede'), c),
    MadarCard.column(
      children: [
        for (final (g, line) in [
          (MadarGlyph.globe, tr('staff.privacy_pings')),
          (MadarGlyph.lock, tr('staff.privacy_off_shift')),
          (MadarGlyph.trash, tr('staff.privacy_wipe')),
        ])
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              MadarGlyphIcon(g, color: c.brand),
              Expanded(child: Text(line, style: MadarType.body)),
            ],
          ),
      ],
    ),
    MadarButton(
      label: tr('staff.i_agree'),
      onTap: () {
        _store.privacyAccepted.add(_who.id);
        _finish();
      },
    ),
  ];
}

/// Dawam's mark: the Madar symbol with the product name — "Dawam by Madar"
/// (PS-6) — for the phone layout and the app's chrome.
class DawamMark extends StatelessWidget {
  const DawamMark({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Row(
      spacing: Space.md,
      children: [
        const MadarSymbol(size: 44),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('staff.dawam'), style: MadarType.h2),
            Text(
              tr('staff.by_madar'),
              style: MadarType.bodySm.copyWith(color: c.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}
