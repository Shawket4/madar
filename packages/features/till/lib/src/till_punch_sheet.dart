/// Dawam at the till (Madar orgs, CL-13): a dead or forgotten phone clocks in
/// or out here with the person's own till PIN. The server decides who it is
/// and whether it is in or out; the core words the answer. Needs a
/// connection: a PIN is never queued.
library;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Opens the PIN sheet; resolves with what the punch did, or null.
Future<TillPunchView?> showTillPunch(BuildContext context) {
  return showMadarSheet<TillPunchView>(
    context,
    size: SheetSize.hug,
    maxWidth: 420,
    builder: (_) => const TillPunchSheet(),
  );
}

/// The PIN field and the one button.
class TillPunchSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const TillPunchSheet({super.key});

  @override
  ConsumerState<TillPunchSheet> createState() => _TillPunchSheetState();
}

class _TillPunchSheetState extends ConsumerState<TillPunchSheet> {
  final TextEditingController _pin = TextEditingController();
  bool _busy = false;
  UiText? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy || _pin.text.trim().length < 4) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(bridgeProvider).tillPunch(pin: _pin.text);
      if (mounted) await Navigator.of(context).maybePop(res);
    } on MadarError catch (e) {
      MadarHaptics.warning();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is MadarError_Offline
              ? const UiText.key('staff.till_punch_needs_connection')
              : UiText.error(e);
          _pin.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(
            t('staff.till_punch'),
            style: MadarType.h3.copyWith(color: colors.textPrimary),
          ),
          Text(
            t('staff.till_punch_hint'),
            style: MadarType.body.copyWith(color: colors.textSecondary),
          ),
          MadarField(
            controller: _pin,
            placeholder: t('approval.pin'),
            kind: MadarFieldKind.pin,
            maxLength: 6,
            icon: 'lock',
            autofocus: true,
            enabled: !_busy,
            onSubmitted: (_) => _go(),
          ),
          if (_error != null)
            NoticeBanner(
              text: _error!.of(bridge),
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
          MadarButton(
            label: t('staff.till_punch'),
            onTap: _go,
            loading: _busy,
            icon: 'clock',
          ),
        ],
      ),
    );
  }
}
