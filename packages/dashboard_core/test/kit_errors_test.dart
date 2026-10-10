// A failure a kit control catches reads as the host's words (the web's
// image-uploader now uses getErrorMessage), never "ApiException(500): …".
import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/rig.dart';

void main() {
  testWidgets('the image uploader shows a refusal as its sentence', (
    tester,
  ) async {
    await pumpCore(
      tester,
      CoreRig(),
      DashImageUploader(
        value: null,
        semanticLabel: 'Logo',
        onPick: () async => DashPickedFile(
          bytes: Uint8List(8),
          name: 'logo.png',
          mimeType: 'image/png',
        ),
        onUpload: (_) async => throw const ApiException(
          status: 500,
          message: 'The server is down',
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Logo').first);
    await tester.pumpAndSettle();
    expect(find.text('The server is down'), findsOneWidget);
    expect(find.textContaining('ApiException'), findsNothing);
  });
}
