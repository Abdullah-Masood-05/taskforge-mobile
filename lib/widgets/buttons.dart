import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

enum TFButtonVariant { primary, secondary, ghost, danger }

enum TFButtonSize { sm, md, lg }

/// Button matching the web `Button` component: amber gradient primary with
/// glow, elevated secondary, ghost and danger. Presses scale down slightly.
class TFButton extends StatelessWidget {
  const TFButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = TFButtonVariant.primary,
    this.size = TFButtonSize.md,
    this.icon,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final TFButtonVariant variant;
  final TFButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final (height, hPad, fontSize) = switch (size) {
      TFButtonSize.sm => (34.0, 12.0, 13.0),
      TFButtonSize.md => (44.0, 16.0, 14.0),
      TFButtonSize.lg => (52.0, 20.0, 15.0),
    };

    final (
      Color fg,
      Gradient? gradient,
      Color? bg,
      Color border,
      List<BoxShadow>? shadow
    ) = switch (variant) {
      TFButtonVariant.primary => (
          TF.onBrand,
          TF.brandGradient,
          null,
          Colors.transparent,
          disabled
              ? null
              : const [
                  BoxShadow(
                      color: Color(0x47F5A623),
                      blurRadius: 8,
                      offset: Offset(0, 2))
                ],
        ),
      TFButtonVariant.secondary => (
          TF.textPrimary,
          null,
          TF.bgElevated,
          TF.borderDefault,
          null
        ),
      TFButtonVariant.ghost => (
          TF.textSecondary,
          null,
          Colors.transparent,
          Colors.transparent,
          null
        ),
      TFButtonVariant.danger => (
          TF.danger,
          null,
          TF.dangerLight,
          const Color(0x40FF6B6B),
          null
        ),
    };

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: fontSize + 3, color: fg),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TFText.sans(
              size: fontSize,
              weight: variant == TFButtonVariant.primary
                  ? FontWeight.w600
                  : FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ],
    );

    return Pressable(
      onTap: disabled ? null : onPressed,
      child: AnimatedOpacity(
        duration: TF.durFast,
        opacity: disabled && !loading ? 0.45 : 1,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: hPad),
          decoration: BoxDecoration(
            gradient: gradient,
            color: bg,
            borderRadius: BorderRadius.circular(TF.radiusMd),
            border: Border.all(color: border),
            boxShadow: shadow,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Wraps any child with a subtle press-scale + haptic, the mobile analogue of
/// the web's `:active { transform: translateY(1px) }`.
class Pressable extends StatefulWidget {
  const Pressable(
      {super.key,
      required this.child,
      this.onTap,
      this.onLongPress,
      this.scale = 0.97,
      this.haptic = true});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: TF.durFast,
        curve: TF.ease,
        child: widget.child,
      ),
    );
  }
}

/// Square icon button with hairline border (topbar actions on the web).
class TFIconButton extends StatelessWidget {
  const TFIconButton(
      {super.key,
      required this.icon,
      this.onPressed,
      this.tooltip,
      this.badge,
      this.size = 40});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final int? badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget btn = Pressable(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: TF.bgElevated,
          borderRadius: BorderRadius.circular(TF.radiusMd),
          border: Border.all(color: TF.borderDefault),
        ),
        child: Icon(icon, size: 19, color: TF.textSecondary),
      ),
    );
    if (badge != null && badge! > 0) {
      btn = Stack(clipBehavior: Clip.none, children: [
        btn,
        Positioned(
          right: -4,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 18),
            decoration: BoxDecoration(
              color: TF.brand,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: TF.bgBase, width: 2),
            ),
            child: Text(
              badge! > 99 ? '99+' : '$badge',
              textAlign: TextAlign.center,
              style: TFText.mono(
                  size: 10, weight: FontWeight.w700, color: TF.onBrand),
            ),
          ),
        ),
      ]);
    }
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
