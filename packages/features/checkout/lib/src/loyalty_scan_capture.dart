import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Captures a member's identity, three ways, and hands the result to its caller.
///
/// **This widget captures bytes; it decides nothing.** Camera frames and USB
/// keystrokes are platform I/O — Rust cannot reach CameraX/AVFoundation without
/// re-implementing them and shipping every frame across the bridge — so capture
/// lives here. What a captured string MEANS is `classifyLoyaltyInput` in the
/// core, which knows a member token's shape. The only judgement left in Dart is
/// the in-flight guard, which is widget sequencing.
///
/// Three ways in, because one counter is not like another:
///  * **Camera** — where there is one. `mobile_scanner` covers Android, iOS and
///    macOS; the Windows tills this app also ships to have no plugin at all.
///  * **USB scanner** — a keyboard-wedge imager types the barcode. That is what
///    most counters have, and it needs nothing but a focused field.
///  * **Phone number** — for the customer whose battery is dead, which is the
///    commonest reason a card cannot be produced at all.
///
/// Shared by the two places a member is identified — applying a reward at
/// tender, and adding points after the sale — so the counter behaves the same
/// in both and there is one place to fix a scanner quirk.
class LoyaltyScanCapture extends ConsumerStatefulWidget {
  const LoyaltyScanCapture({
    required this.onCaptured,
    required this.busy,
    this.error,
    super.key,
  });

  /// Called with a complete token or phone number. Exactly one is non-null.
  final Future<void> Function({String? token, String? phone}) onCaptured;

  /// True while the caller is working — suppresses further captures.
  final bool busy;

  /// Why the last attempt failed, shown under the capture area.
  final String? error;

  @override
  ConsumerState<LoyaltyScanCapture> createState() => _LoyaltyScanCaptureState();
}

class _LoyaltyScanCaptureState extends ConsumerState<LoyaltyScanCapture> {
  /// The invisible sink a USB wedge types into. Kept focused for the life of the
  /// sheet — a wedge scan is just fast keystrokes, and they land nowhere if
  /// nothing has focus.
  final _wedge = TextEditingController();
  final _wedgeFocus = FocusNode();
  final _phone = TextEditingController();
  bool _phoneMode = false;
  MobileScannerController? _camera;

  /// The camera plugin exists on these platforms only. Checked once so a
  /// Windows till never constructs a controller that would throw.
  static final bool _cameraSupported =
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (_cameraSupported) {
      _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
      unawaited(_camera!.start());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_phoneMode) _wedgeFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(LoyaltyScanCapture old) {
    super.didUpdateWidget(old);
    // A failed attempt leaves the field ready for another go rather than making
    // the teller tap back into it.
    if (old.busy && !widget.busy && !_phoneMode) _wedgeFocus.requestFocus();
  }

  @override
  void dispose() {
    unawaited(_camera?.dispose());
    _wedge.dispose();
    _wedgeFocus.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Hand a captured string to the core and act on what it says it is.
  ///
  /// Called on every wedge keystroke as well as on Enter, which is what makes
  /// the cheap imagers work: the ones that never send Enter still fire the
  /// moment the buffer becomes a whole card.
  Future<void> _offer(String raw) async {
    if (widget.busy) return; // in-flight guard: sequencing, not domain logic
    final parsed = ref.read(bridgeProvider).classifyLoyaltyInput(raw: raw);
    switch (parsed.kind) {
      case 'token':
        _wedge.clear();
        await widget.onCaptured(token: parsed.value);
      case 'phone':
        await widget.onCaptured(phone: parsed.value);
      default:
        return; // still mid-scan, or not a card — keep collecting
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _phoneMode
              ? 'Look the customer up by the number they signed up with.'
              : 'Hold their wallet pass to the scanner, or point the camera at it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        if (_phoneMode) ...[
          TextField(
            controller: _phone,
            autofocus: true,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '01x xxxx xxxx',
            ),
            onSubmitted: (v) => unawaited(_offer(v)),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: widget.busy ? null : () => unawaited(_offer(_phone.text)),
            child: const Text('Look up'),
          ),
        ] else ...[
          if (_camera != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 220,
                child: MobileScanner(
                  controller: _camera,
                  onDetect: (capture) {
                    // The platform decoder gives us a string; the core says
                    // whether it is one of ours.
                    final code = capture.barcodes.firstOrNull?.rawValue;
                    if (code != null) unawaited(_offer(code));
                  },
                ),
              ),
            )
          else
            // No camera on this till. Say so plainly rather than showing a
            // black rectangle the teller will tap at.
            Container(
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Text(
                'Ready for the barcode scanner',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),

          // The wedge sink: zero-height, transparent, and focused, because a
          // USB imager's keystrokes have to land somewhere.
          SizedBox(
            height: 0,
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: _wedge,
                focusNode: _wedgeFocus,
                autofocus: true,
                // Every keystroke, not just Enter — see [_offer].
                onChanged: (v) => unawaited(_offer(v)),
                onSubmitted: (v) => unawaited(_offer(v)),
              ),
            ),
          ),
        ],

        if (widget.busy) ...[
          const SizedBox(height: 12),
          const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],

        if (widget.error != null) ...[
          const SizedBox(height: 12),
          Text(
            widget.error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ],

        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            setState(() => _phoneMode = !_phoneMode);
            if (!_phoneMode) _wedgeFocus.requestFocus();
          },
          child: Text(
            _phoneMode ? 'Scan a card instead' : 'No card? Use their phone number',
          ),
        ),
      ],
    );
  }
}
