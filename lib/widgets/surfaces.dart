import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';
import 'buttons.dart';

/// Card with razor-thin border on the elevated surface (web `Card`).
class TFCard extends StatelessWidget {
  const TFCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.highlight = false,
    this.color,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool highlight;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: TF.dur,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? TF.bgSurface,
        borderRadius: BorderRadius.circular(TF.radiusLg),
        border:
            Border.all(color: highlight ? TF.borderBrand : TF.borderDefault),
        boxShadow: highlight ? TF.shadowGlow : null,
      ),
      child: child,
    );
    return onTap == null
        ? card
        : Pressable(onTap: onTap, scale: 0.985, child: card);
  }
}

/// Monospace uppercase section label (`.eyebrow`).
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text,
      {super.key, this.color = TF.textMuted, this.trailing});
  final String text;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = Text(text.toUpperCase(), style: TFText.eyebrow(color: color));
    if (trailing == null) return label;
    return Row(children: [Expanded(child: label), trailing!]);
  }
}

/// Small pill badge. Variants follow the web Badge (default/brand/success/
/// warning/danger/info) or any custom colour.
class TFBadge extends StatelessWidget {
  const TFBadge(this.label,
      {super.key,
      this.color = TF.textMuted,
      this.dot = false,
      this.mono = true});

  final String label;
  final Color color;
  final bool dot;
  final bool mono;

  factory TFBadge.priority(String priority, {Key? key}) =>
      TFBadge(priority, key: key, color: TF.priorityColor(priority), dot: true);

  factory TFBadge.role(String role, {Key? key}) =>
      TFBadge(role, key: key, color: TF.roleColor(role));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TF.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        Text(
          mono ? label.toUpperCase().replaceAll('_', ' ') : label,
          style: mono
              ? TFText.mono(
                  size: 10,
                  weight: FontWeight.w600,
                  color: color,
                  letterSpacing: 0.8)
              : TFText.sans(size: 12, weight: FontWeight.w500, color: color),
        ),
      ]),
    );
  }
}

/// Initials avatar with deterministic warm hue, or network image.
class TFAvatar extends StatelessWidget {
  const TFAvatar(
      {super.key, required this.name, this.imageUrl, this.size = 32});
  final String name;
  final String? imageUrl;
  final double size;

  static const _palette = [
    Color(0xFFF5A623),
    Color(0xFF10B981),
    Color(0xFF9BD9FF),
    Color(0xFFFF6B6B),
    Color(0xFFFFC880),
    Color(0xFFC4A7E7),
    Color(0xFF7DD3C0),
  ];

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'[\s@._-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = _palette[
        name.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(initials,
          style: TFText.sans(
              size: size * 0.38, weight: FontWeight.w600, color: color)),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

/// Overlapping avatar stack ("+N" overflow).
class AvatarStack extends StatelessWidget {
  const AvatarStack(
      {super.key,
      required this.names,
      this.urls = const [],
      this.size = 24,
      this.max = 3});
  final List<String> names;
  final List<String?> urls;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = names.take(max).toList();
    final extra = names.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    return SizedBox(
      height: size,
      width: size + (count - 1) * size * 0.65,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(
            left: i * size * 0.65,
            child: Container(
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: TF.bgSurface, width: 1.5)),
              child: TFAvatar(
                  name: shown[i],
                  imageUrl: i < urls.length ? urls[i] : null,
                  size: size - 3),
            ),
          ),
        if (extra > 0)
          Positioned(
            left: shown.length * size * 0.65,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: TF.bgOverlay,
                shape: BoxShape.circle,
                border: Border.all(color: TF.bgSurface, width: 1.5),
              ),
              child: Text('+$extra',
                  style:
                      TFText.mono(size: size * 0.36, color: TF.textSecondary)),
            ),
          ),
      ]),
    );
  }
}

/// Animated thin progress bar with brand gradient fill.
class TFProgressBar extends StatelessWidget {
  const TFProgressBar(
      {super.key, required this.value, this.height = 4, this.color});
  final double value; // 0..1
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: TF.borderDefault,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0, 1)),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => FractionallySizedBox(
            widthFactor: v,
            child: Container(
              decoration: BoxDecoration(
                gradient: color == null ? TF.brandGradient : null,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dotted-grid backdrop (`.dot-grid`) with optional warm radial glow
/// (`.auth-bg`).
class DotGridBackground extends StatelessWidget {
  const DotGridBackground({super.key, this.child, this.glow = false});
  final Widget? child;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DotGridPainter(glow: glow),
      child: child,
    );
  }
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter({required this.glow});
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = TF.bgBase);
    if (glow) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.6, -0.4),
            radius: 0.9,
            colors: [TF.brand.withValues(alpha: 0.10), Colors.transparent],
          ).createShader(Offset.zero & size),
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.6, 0.4),
            radius: 0.8,
            colors: [
              TF.brandSecondary.withValues(alpha: 0.08),
              Colors.transparent
            ],
          ).createShader(Offset.zero & size),
      );
    }
    final dot = Paint()..color = const Color(0x0DFFFFFF);
    const step = 24.0;
    for (double y = step / 2; y < size.height; y += step) {
      for (double x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter old) => old.glow != glow;
}

/// Section header: eyebrow + title + optional action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
      {super.key, required this.title, this.eyebrow, this.action});
  final String title;
  final String? eyebrow;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (eyebrow != null) ...[
            Eyebrow(eyebrow!),
            const SizedBox(height: 4)
          ],
          Text(title, style: TFText.h3()),
        ]),
      ),
      if (action != null) action!,
    ]);
  }
}

/// Small stat tile (label + big mono number), used on dashboards.
class StatTile extends StatelessWidget {
  const StatTile(
      {super.key,
      required this.label,
      required this.value,
      this.icon,
      this.accent = TF.brand,
      this.caption});
  final String label;
  final String value;
  final IconData? icon;
  final Color accent;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return TFCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 6)
          ],
          Expanded(
              child: Text(label.toUpperCase(),
                  style: TFText.eyebrow(), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 10),
        Text(value,
            style: TFText.mono(
                size: 24, weight: FontWeight.w600, color: TF.textPrimary)),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(caption!, style: TFText.small())
        ],
      ]),
    );
  }
}
