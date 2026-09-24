import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

enum _Step { phone, code, org, privacy }

/// Sign-in: WhatsApp number and code (RO-2), the business pick (RO-5), the
/// privacy notice (AT-5). On a tablet the shared brand panel stands beside
/// the form, as on the POS.
///
/// The notice is accepted per phone ON THE SERVER: a signed-in person whose
/// phone has not accepted it (a new phone, or a session restored after the
/// app was closed on the notice) opens straight at it, and the tabs open
/// only once the server has recorded "I agree".
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  _Step _step = _Step.phone;
  List<(String, String, String, bool)> _orgs = const [];
  String? _error;
  int _left = 300;
  bool _busy = false;
  Timer? _timer;

  DawamStore get _store => ref.read(dawamProvider);

  @override
  void initState() {
    super.initState();
    // Signed in already, the notice not accepted on this phone yet.
    if (ref.read(dawamProvider).me != null) _step = _Step.privacy;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Runs a sign-in step; a refusal shows as the server words it.
  Future<void> _step$(Future<void> Function() op) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await op();
    } on DawamError catch (e) {
      if (mounted) setState(() => _error = loc(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sendCode() => _step$(() async {
    await _store.requestCode(_phone.text.trim());
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) _back(tr('staff.the_code_expired_send_a_new'));
    });
    setState(() {
      _left = 300;
      _code.clear();
      _step = _Step.code;
    });
  });

  void _back([String? why]) {
    _timer?.cancel();
    setState(() {
      _step = _Step.phone;
      _error = why;
    });
  }

  // The server counts the tries and says how many are left (RO-2).
  void _verify() => _step$(() async {
    final orgs = await _store.verifyCode(_phone.text.trim(), _code.text.trim());
    _timer?.cancel(); // the code is deleted on use
    setState(() {
      _orgs = orgs ?? const [];
      _step = orgs != null ? _Step.org : _Step.privacy;
    });
    if (_step == _Step.privacy) await _privacyOrFinish();
  });

  void _pickOrg(String orgId) => _step$(() async {
    await _store.verifyCode(
      _phone.text.trim(),
      _code.text.trim(),
      orgId: orgId,
    );
    setState(() => _step = _Step.privacy);
    await _privacyOrFinish();
  });

  /// Signed in: load the picture. A phone that accepted the notice before
  /// goes straight in (the app opens on the server's record); any other
  /// stays on the notice.
  Future<void> _privacyOrFinish() => _store.enter();

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
  ];

  List<Widget> _codeStep(MadarColors c) => [
    _lede(
      tr('staff.enter_the_code'),
      tr('staff.sent_on_whatsapp_to', {'phone': _phone.text.trim()}),
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
      ],
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
    for (final (id, en, ar, active) in _orgs)
      MadarListRow.bill(
        title: isAr ? ar : en,
        status: active
            ? MadarStatus(tr('staff.active'), tone: MadarTone.success)
            : MadarStatus(tr('staff.suspended'), tone: MadarTone.danger),
        onTap: active
            ? () => _pickOrg(id)
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
      // After a failed attempt (shown in the banner above) it says so.
      label: _error == null ? tr('staff.i_agree') : tr('staff.try_again'),
      onTap: () => _step$(_store.acceptPrivacy),
    ),
    MadarButton(
      label: tr('staff.change_number'),
      variant: MadarButtonVariant.ghost,
      onTap: () {
        _store.signOut();
        _back();
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
