import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// TaskForge mark (the amber anvil/forge glyph) + optional wordmark.
class BrandLogo extends StatelessWidget {
  const BrandLogo(
      {super.key, this.size = 32, this.showWordmark = true, this.glow = false});
  final double size;
  final bool showWordmark;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      decoration: glow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.2),
              boxShadow: TF.shadowGlow)
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2),
        child: SvgPicture.asset('assets/images/logo.svg',
            width: size, height: size),
      ),
    );
    if (!showWordmark) return mark;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      mark,
      SizedBox(width: size * 0.32),
      Text('TaskForge',
          style: TFText.sans(
              size: size * 0.56, weight: FontWeight.w700, letterSpacing: -0.4)),
    ]);
  }
}

/// Small helpers for date formatting shared across screens.
class Fmt {
  Fmt._();

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  /// "just now", "3 min ago", "2 hr ago", "yesterday", "4 days ago", "Mar 14"
  static String relative(DateTime? t) {
    if (t == null) return '';
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 45) return 'just now';
    final m = (s / 60).round();
    if (m < 60) return '$m min ago';
    final h = (m / 60).round();
    if (h < 24) return '$h hr ago';
    final d = (h / 24).round();
    if (d == 1) return 'yesterday';
    if (d < 7) return '$d days ago';
    return short(t);
  }

  /// "Mar 14" (adds year when not current: "Mar 14, 2025")
  static String short(DateTime? t) {
    if (t == null) return '';
    final base = '${_months[t.month - 1]} ${t.day}';
    return t.year == DateTime.now().year ? base : '$base, ${t.year}';
  }

  /// yyyy-MM-dd for API date fields.
  static String apiDate(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  static String fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String title(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
