/// The role dialog (ADM-ROL-017, 018, 024; web
/// `features/access/role-dialog.tsx`): "New role" (names, what it works
/// like, what it starts from) or "Rename role" (names only). A dialog on a
/// wide screen, a full-screen sheet on a phone.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show CreateRoleRequest, RenameRoleRequest, RoleView;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/org_errors.dart' show orgErrorWords;
import 'roles_data.dart';

/// "Start from": the usual defaults.
const String _defaults = 'none';

/// Opens the dialog: [role] null = "New role", else "Rename role".
/// [onSaved] runs with the saved role even when the dialog was closed while
/// the call ran (the web's `onSaved` selects it either way).
Future<void> showRoleDialog(
  BuildContext context, {
  required ValueChanged<RoleView> onSaved,
  RoleView? role,
}) => showDashDialog<void>(
  context,
  builder: (_) => RoleDialog(role: role, onSaved: onSaved),
);

class RoleDialog extends ConsumerStatefulWidget {
  const RoleDialog({required this.onSaved, this.role, super.key});

  /// The role being renamed; null creates one.
  final RoleView? role;
  final ValueChanged<RoleView> onSaved;

  @override
  ConsumerState<RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends ConsumerState<RoleDialog> {
  final _form = GlobalKey<FormState>();
  bool _busy = false;

  /// Typed into since it opened: a background refresh no longer re-seeds.
  bool _edited = false;

  late String _nameEn = widget.role?.nameEn ?? '';
  late String _nameAr = widget.role?.nameAr ?? '';
  String _kind = RoleKind.teller;
  String _copyFrom = _defaults;

  bool get _renaming => widget.role != null;

  String? _nameError(String v) {
    final key = roleNameProblem(v);
    return key == null ? null : ref.read(tProvider)(key);
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).authz;
    // Kept before the call: the dialog may close while it runs.
    final bus = ref.read(realtimeBusProvider);
    final onSaved = widget.onSaved;
    final role = widget.role;
    setState(() => _busy = true);
    final RoleView saved;
    try {
      saved = role != null
          ? await api.renameRole(
              id: role.id,
              body: RenameRoleRequest(
                nameEn: _nameEn.trim(),
                nameAr: _nameAr.trim(),
              ),
            )
          : await api.createRole(
              body: CreateRoleRequest(
                nameEn: _nameEn.trim(),
                nameAr: _nameAr.trim(),
                kind: _kind,
                copyFrom: _copyFrom == _defaults ? null : _copyFrom,
                explicitNulls: const {'copy_from'},
              ),
            );
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(context, orgErrorWords(e, t));
        setState(() => _busy = false);
      }
      return;
    }
    bus.invalidate(rolesKey);
    if (mounted) Navigator.of(context).pop();
    onSaved(saved);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final roles = ref.watch(accessRolesProvider).value ?? const <RoleView>[];
    // A rename re-seeds from a background refresh until it is typed into.
    final fresh = roles.firstWhereOrNull((r) => r.id == widget.role?.id);
    if (fresh != null && !_edited) {
      _nameEn = fresh.nameEn;
      _nameAr = fresh.nameAr;
    }

    return DashSurface(
      title: t(_renaming ? 'access.renameRole' : 'access.newRole'),
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            DashTextField(
              key: const ValueKey('role-name-en'),
              label: t('access.nameEn'),
              value: _nameEn,
              textDirection: TextDirection.ltr,
              validator: _nameError,
              onChanged: (v) => setState(() {
                _edited = true;
                _nameEn = v;
              }),
              onSubmitted: (_) => _submit(),
            ),
            DashTextField(
              key: const ValueKey('role-name-ar'),
              label: t('access.nameAr'),
              value: _nameAr,
              textDirection: TextDirection.rtl,
              validator: _nameError,
              onChanged: (v) => setState(() {
                _edited = true;
                _nameAr = v;
              }),
              onSubmitted: (_) => _submit(),
            ),
            if (!_renaming) ...[
              DashSelectField<String>(
                key: const ValueKey('role-kind'),
                label: t('access.kind'),
                value: _kind,
                options: [
                  for (final k in creatableKinds)
                    DashOption(value: k, label: kindLabel(k, lang)),
                ],
                onChanged: (v) => setState(() {
                  // A role of another kind no longer applies (the web keeps
                  // it, blank, and still sends it: see the divergence log).
                  final from = roles.firstWhereOrNull((r) => r.id == _copyFrom);
                  if (from != null && from.kind != v) _copyFrom = _defaults;
                  _kind = v;
                }),
              ),
              DashSelectField<String>(
                key: const ValueKey('role-copy-from'),
                label: t('access.copyFrom'),
                value: _copyFrom,
                options: [
                  DashOption(value: _defaults, label: t('access.copyDefaults')),
                  for (final r in roles)
                    if (r.kind == _kind)
                      DashOption(value: r.id, label: roleName(r, lang)),
                ],
                onChanged: (v) => setState(() => _copyFrom = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          // The web keeps Cancel enabled while saving.
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(
          key: const ValueKey('role-submit'),
          label: t('common.save'),
          // Disabled while it saves, no spinner (ADM-ROL-024).
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
