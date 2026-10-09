/// The user editor (ADM-USR-020..032, 053, 054; web `features/users/user-dialog.tsx`):
/// a dialog on a wide screen, a full-screen sheet on a phone.
///
/// CROSS-UNIT CONTRACT: the onboarding wizard's team step (ADM-ONB-020)
/// opens this same dialog in create mode, so keep [showUserDialog]'s
/// signature stable.
///
/// A PIN and an email + password are INDEPENDENT credentials: both are
/// offered to every role, the role only decides which one is required, and
/// both reach the API when filled in. On edit a blank credential means
/// "keep the current one".
library;

import 'package:dashboard_api/dashboard_api.dart'
    show CreateUserRequest, Org, UpdateUserRequest, UserPublic, UserRole;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../orgs/org_errors.dart' show orgErrorWords;
import '../orgs/orgs_providers.dart' show orgsListProvider;
import 'users_data.dart';
import 'users_page.dart' show roleLabel;

/// Opens the user dialog: [user] null = "New User" (create), else "Edit
/// User". Resolves true when a user was created or saved, false when the
/// dialog closed without one.
Future<bool> showUserDialog(BuildContext context, {UserPublic? user}) async {
  final saved = await showDashDialog<bool>(
    context,
    builder: (_) => UserDialog(user: user),
  );
  return saved ?? false;
}

/// zod's `.email()`, near enough: something @ something . something.
final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

class UserDialog extends ConsumerStatefulWidget {
  const UserDialog({this.user, super.key});

  /// The person being edited; null creates one.
  final UserPublic? user;

  @override
  ConsumerState<UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends ConsumerState<UserDialog> {
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  bool _suggesting = false;

  late String _name;
  late String _email;
  late String _phone;
  late UserRole _role;
  late String? _orgId;
  String _pin = '';
  String _password = '';
  late bool _active;

  UserPublic? get _user => widget.user;
  bool get _editing => _user != null;

  @override
  void initState() {
    super.initState();
    // The web's `form.reset(...)` on open: PIN and password always blank.
    final u = _user;
    _name = u?.name ?? '';
    _email = u?.email ?? '';
    _phone = u?.phone ?? '';
    _role = u?.role ?? UserRole.teller;
    _orgId = u?.orgId ?? ref.read(orgIdProvider);
    _active = u?.isActive ?? true;
  }

  bool get _platform => ref.read(currentSessionProvider)?.isPlatform ?? false;

  bool get _till => isTillRole(_role);

  // ── validation (the web's zod schema) ──────────────────────────────────

  String? _nameError(String v) =>
      v.isEmpty ? ref.read(tProvider)('common.requiredField') : null;

  String? _pinError(String v) {
    final t = ref.read(tProvider);
    if (v.isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(v)) {
      return t('users.pinError6');
    }
    if (_till && !_editing && v.isEmpty) return t('users.pinRequired');
    return null;
  }

  String? _emailError(String v) {
    final t = ref.read(tProvider);
    if (v.isNotEmpty && !_emailPattern.hasMatch(v)) return t('common.invalidEmail');
    if (_till ? (_password.isNotEmpty && v.isEmpty) : v.isEmpty) {
      return t('users.emailRequired');
    }
    return null;
  }

  String? _passwordError(String v) => !_till && !_editing && v.isEmpty
      ? ref.read(tProvider)('users.passwordRequired')
      : null;

  // ── actions ────────────────────────────────────────────────────────────

  /// The server picks a PIN nobody in the org is using; it is shown once,
  /// in the clear, because the admin has to read it out.
  Future<void> _generate() async {
    final t = ref.read(tProvider);
    setState(() => _suggesting = true);
    try {
      final s = await ref.read(apiProvider).users.suggestPin();
      if (mounted) setState(() => _pin = s.pin);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, orgErrorWords(e, t));
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).users;
    // Kept before the call: a Cancel while it runs closes the dialog, and the
    // list must still refresh when the call lands (the web's global
    // `invalidateUsers()`).
    final bus = ref.read(realtimeBusProvider);
    final email = _email.isEmpty ? null : _email;
    final phone = _phone.isEmpty ? null : _phone;
    final pin = _pin.isEmpty ? null : _pin;
    final password = _password.isEmpty ? null : _password;
    setState(() => _busy = true);
    try {
      final u = _user;
      if (u != null) {
        await api.updateUser(
          id: u.id,
          body: UpdateUserRequest(
            name: _name,
            email: email,
            phone: phone,
            role: _role,
            isActive: _active,
            pin: pin,
            password: password,
            explicitNulls: const {'email', 'phone'},
          ),
        );
      } else {
        final current = ref.read(orgIdProvider);
        final orgId = (_platform ? _orgId : current) ?? current;
        if (orgId == null) return;
        await api.createUser(
          body: CreateUserRequest(
            name: _name,
            role: _role,
            orgId: orgId,
            email: email,
            phone: phone,
            pin: pin,
            password: password,
            explicitNulls: const {'email', 'phone'},
          ),
        );
      }
      bus.invalidate(const ['/users']);
      if (!mounted) return;
      DashToast.success(
        context,
        t(_editing ? 'users.updatedToast' : 'users.createdToast'),
      );
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, orgErrorWords(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── the form ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final session = ref.watch(currentSessionProvider);
    final platform = session?.isPlatform ?? false;
    final pickOrg = platform && !_editing;
    final orgs = pickOrg
        ? ref.watch(orgsListProvider).value ?? const <Org>[]
        : const <Org>[];
    final roles = roleOptionsFor(platform ? 'super_admin' : session?.user.role);
    final wide =
        DashSurfaceScope.maybeOf(context) != DashSurfaceMode.fullScreen &&
        MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;

    Widget pair(Widget a, Widget b) => wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(child: a),
              Expanded(child: b),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.lg,
            children: [a, b],
          );

    final name = DashTextField(
      key: const ValueKey('user-name'),
      label: t('users.fullName'),
      value: _name,
      onChanged: (v) => setState(() => _name = v),
      validator: _nameError,
      onSubmitted: (_) => _submit(),
    );
    final role = DashSelectField<UserRole>(
      key: const ValueKey('user-role'),
      label: t('users.role'),
      // A role outside the viewer's options shows an empty select and is
      // sent back unchanged (ADM-USR-053).
      value: roles.contains(_role) ? _role : null,
      options: [
        for (final r in roles) DashOption(value: r, label: roleLabel(r, t)),
      ],
      onChanged: (v) => setState(() => _role = v),
    );
    final phone = DashTextField(
      key: const ValueKey('user-phone'),
      label: t('users.phone'),
      value: _phone,
      keyboardType: TextInputType.phone,
      // A number reads left to right in Arabic too (see the divergence log).
      textDirection: TextDirection.ltr,
      onChanged: (v) => setState(() => _phone = v),
      onSubmitted: (_) => _submit(),
    );
    final org = DashSelectField<String>(
      key: const ValueKey('user-org'),
      label: t('users.org'),
      value: _orgId,
      options: [for (final o in orgs) DashOption(value: o.id, label: o.name)],
      onChanged: (v) => setState(() => _orgId = v),
    );
    final pinLabel = t(_till ? 'users.pin6' : 'users.pinOptional');
    final pin = DashFormField<String>(
      key: const ValueKey('user-pin'),
      label: pinLabel,
      value: _pin,
      validator: _pinError,
      builder: (context, invalid) => Row(
        spacing: Space.sm,
        children: [
          Expanded(
            child: DashTextInput(
              value: _pin,
              semanticLabel: pinLabel,
              invalid: invalid,
              placeholder: _editing ? '••••••' : null,
              keyboardType: TextInputType.number,
              maxLength: 6,
              mono: true,
              textDirection: TextDirection.ltr,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) => setState(() => _pin = v),
              onSubmitted: (_) => _submit(),
            ),
          ),
          DashButton(
            key: const ValueKey('user-generate-pin'),
            label: t('users.generatePin'),
            variant: DashButtonVariant.outline,
            loading: _suggesting,
            onPressed: _generate,
          ),
        ],
      ),
    );
    final email = DashTextField(
      key: const ValueKey('user-email'),
      label: t(_till ? 'users.emailOptional' : 'auth.email'),
      value: _email,
      keyboardType: TextInputType.emailAddress,
      textDirection: TextDirection.ltr,
      onChanged: (v) => setState(() => _email = v),
      validator: _emailError,
      onSubmitted: (_) => _submit(),
    );
    final password = DashTextField(
      key: const ValueKey('user-password'),
      label: t(_till ? 'users.passwordOptional' : 'auth.password'),
      value: _password,
      obscure: true,
      placeholder: _editing ? t('users.leaveBlank') : null,
      onChanged: (v) => setState(() => _password = v),
      validator: _passwordError,
      onSubmitted: (_) => _submit(),
    );
    final hint = Text(
      t(_till ? 'users.posCredHint2' : 'users.dashCredHint2'),
      style: DashType.small.copyWith(color: c.textSecondary),
    );
    final active = _editing
        ? Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: c.muted,
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: DashSwitchField(
              key: const ValueKey('user-active'),
              label: t('users.activeAccount'),
              description: t('users.activeHint'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          )
        : null;

    return DashSurface(
      title: t(_editing ? 'users.editTitle' : 'users.newTitle'),
      description: t('users.subtitle'),
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            name,
            // Role first: it decides which credential the rest asks for.
            if (pickOrg) ...[pair(role, org), phone] else pair(role, phone),
            pin,
            pair(email, password),
            hint,
            ?active,
          ],
        ),
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          // The web keeps Cancel enabled while saving (ADM-USR-053).
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DashButton(
          key: const ValueKey('user-submit'),
          label: t(_editing ? 'common.saveChanges' : 'common.create'),
          loading: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
