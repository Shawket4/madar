/// Draws an image address the server hands back (the web's `AssetImage`
/// with a `legacyUrl`): a `data:` URI from its own bytes (what the mock's
/// asset worker answers), anything else over the network, a muted glyph when
/// it cannot be drawn.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

Widget brandImage(String url, {BoxFit fit = BoxFit.cover}) {
  Widget fallback(BuildContext context) => Center(
    child: DashIcon(
      'image',
      size: IconSize.lg,
      color: context.madarColors.textMuted,
    ),
  );
  if (url.startsWith('data:')) {
    final data = Uri.tryParse(url)?.data;
    if (data == null) return Builder(builder: fallback);
    return Image.memory(
      data.contentAsBytes(),
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (context, e, s) => fallback(context),
    );
  }
  return Image.network(
    url,
    fit: fit,
    errorBuilder: (context, e, s) => fallback(context),
  );
}
