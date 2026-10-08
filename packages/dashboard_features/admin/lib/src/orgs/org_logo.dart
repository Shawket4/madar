/// An organization's mark in the table (ADM-ORG-006): its logo in a 32 px
/// rounded square, or the first two letters of its name on a muted tile
/// when it has none (or the picture cannot be loaded).
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Draws an image address: a `data:` URI from its own bytes (what the mock's
/// asset worker hands back), anything else over the network; [fallback]
/// when it cannot be drawn.
Widget orgImage(
  String url, {
  BoxFit fit = BoxFit.cover,
  required WidgetBuilder fallback,
}) {
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

/// The first two letters of [name], upper-cased (`name.slice(0, 2)`).
String orgInitials(String name) =>
    (name.length > 2 ? name.substring(0, 2) : name).toUpperCase();

class OrgLogoTile extends StatelessWidget {
  const OrgLogoTile({
    required this.name,
    required this.logoUrl,
    this.size = Space.xxl,
    super.key,
  });

  final String name;
  final String? logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    Widget initials(BuildContext context) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Text(
        orgInitials(name),
        maxLines: 1,
        style: DashType.small.copyWith(
          color: c.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final url = logoUrl?.trim();
    if (url == null || url.isEmpty) return ExcludeSemantics(child: initials(context));
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.xs),
        child: SizedBox.square(
          dimension: size,
          child: orgImage(url, fallback: initials),
        ),
      ),
    );
  }
}
