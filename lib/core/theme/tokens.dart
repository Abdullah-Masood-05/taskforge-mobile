import 'package:flutter/material.dart';

/// Design tokens mirrored from the web app's `globals.css`.
/// "Terminal" theme: warm near-black canvas, amber accent, razor-thin
/// borders, sharp corners, editorial mono labels.
class TF {
  TF._();

  // Canvas
  static const bgBase = Color(0xFF0D0F10);
  static const bgSurface = Color(0xFF16130D);
  static const bgElevated = Color(0xFF1C1A14);
  static const bgOverlay = Color(0xFF251E16);
  static const surfaceHover = Color(0x0FFFFFFF);

  // Brand
  static const brand = Color(0xFFF5A623);
  static const brandHover = Color(0xFFFFB955);
  static const brandLight = Color(0x1FF5A623);
  static const brandSecondary = Color(0xFFFFC880);
  static const onBrand = Color(0xFF291800);
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand, brandSecondary],
  );

  // Text
  static const textPrimary = Color(0xFFEEE0D2);
  static const textSecondary = Color(0xFFD7C3AE);
  static const textMuted = Color(0xFF9F8E7A);
  static const textDisabled = Color(0xFF524534);

  // Borders
  static const borderSubtle = Color(0x0DFFFFFF);
  static const borderDefault = Color(0x17FFFFFF);
  static const borderStrong = Color(0x29FFFFFF);
  static const borderBrand = Color(0x66F5A623);

  // Status
  static const success = Color(0xFF10B981);
  static const successLight = Color(0x1F10B981);
  static const warning = Color(0xFFF5A623);
  static const warningLight = Color(0x1FF5A623);
  static const danger = Color(0xFFFF6B6B);
  static const dangerLight = Color(0x1FFF6B6B);
  static const info = Color(0xFF9BD9FF);
  static const infoLight = Color(0x1F9BD9FF);

  // Roles
  static const roleAdmin = brand;
  static const roleMember = success;
  static const roleViewer = textMuted;

  // Radii — sharp "razor" corners
  static const radiusSm = 2.0;
  static const radiusMd = 3.0;
  static const radiusLg = 4.0;
  static const radiusXl = 6.0;

  // Motion
  static const durFast = Duration(milliseconds: 120);
  static const dur = Duration(milliseconds: 200);
  static const durSlow = Duration(milliseconds: 350);
  static const ease = Cubic(0.4, 0, 0.2, 1);
  static const easeBounce = Cubic(0.34, 1.56, 0.64, 1);

  // Shadows
  static const shadowGlow = [
    BoxShadow(color: Color(0x38F5A623), blurRadius: 24),
  ];
  static const shadowMd = [
    BoxShadow(color: Color(0x8C000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const shadowLg = [
    BoxShadow(color: Color(0xA6000000), blurRadius: 32, offset: Offset(0, 8)),
  ];

  /// Priority → colour (matches web Badge variants).
  static Color priorityColor(String? p) => switch (p) {
        'urgent' => danger,
        'high' => brand,
        'medium' => info,
        'low' => textMuted,
        _ => textMuted,
      };

  static Color roleColor(String? r) => switch (r) {
        'admin' => roleAdmin,
        'member' => roleMember,
        _ => roleViewer,
      };

  /// Parses "#rrggbb" hex strings from the API (status/label colours).
  static Color hex(String? value, {Color fallback = brand}) {
    if (value == null || value.isEmpty) return fallback;
    var v = value.replaceFirst('#', '');
    if (v.length == 3) v = v.split('').map((c) => '$c$c').join();
    if (v.length != 6) return fallback;
    final n = int.tryParse(v, radix: 16);
    return n == null ? fallback : Color(0xFF000000 | n);
  }
}
