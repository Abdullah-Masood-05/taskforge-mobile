import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/widgets.dart';

/// Small helpers shared by the board feature (filters, new-task sheet, ...).

/// Colour dot used for status columns and labels.
class ColorDot extends StatelessWidget {
  const ColorDot(this.color, {super.key, this.size = 8, this.glow = false});
  final Color color;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: glow
            ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 6)]
            : null,
      ),
    );
  }
}

/// Multi/single-select chip with an optional leading widget.
class ToggleChip extends StatelessWidget {
  const ToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = TF.brand,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: TF.dur,
        curve: TF.ease,
        padding: EdgeInsets.fromLTRB(leading == null ? 12 : 6, 7, 12, 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : TF.bgElevated,
          borderRadius: BorderRadius.circular(TF.radiusMd),
          border: Border.all(
              color:
                  selected ? color.withValues(alpha: 0.6) : TF.borderDefault),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (leading != null) ...[leading!, const SizedBox(width: 7)],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TFText.sans(
                size: 13,
                weight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? TF.textPrimary : TF.textSecondary,
              ),
            ),
          ),
          AnimatedSize(
            duration: TF.dur,
            curve: TF.ease,
            child: selected
                ? Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.check_rounded, size: 14, color: color),
                  )
                : const SizedBox.shrink(),
          ),
        ]),
      ),
    );
  }
}

/// Labelled field block used in sheets: eyebrow label + child.
class FieldBlock extends StatelessWidget {
  const FieldBlock(
      {super.key, required this.label, required this.child, this.trailing});
  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Eyebrow(label, trailing: trailing),
            const SizedBox(height: 8),
            child,
          ]),
    );
  }
}

/// Tappable date field that opens a themed date picker.
class DateField extends StatelessWidget {
  const DateField(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged,
      this.firstDate});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final first = firstDate ?? DateTime(now.year - 5);
    var initial = value ?? now;
    if (initial.isBefore(first)) initial = first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(now.year + 10),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
              surface: TF.bgSurface, primary: TF.brand, onPrimary: TF.onBrand),
          datePickerTheme: const DatePickerThemeData(
              backgroundColor: TF.bgSurface,
              surfaceTintColor: Colors.transparent),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final has = value != null;
    return Pressable(
      onTap: () => _pick(context),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: TF.bgElevated,
          borderRadius: BorderRadius.circular(TF.radiusMd),
          border: Border.all(color: has ? TF.borderStrong : TF.borderDefault),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_rounded,
              size: 15, color: has ? TF.brand : TF.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              has ? Fmt.short(value) : label,
              overflow: TextOverflow.ellipsis,
              style: TFText.sans(
                  size: 14, color: has ? TF.textPrimary : TF.textDisabled),
            ),
          ),
          if (has)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(null),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 15, color: TF.textMuted),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Sheet header: title + optional subtitle eyebrow.
class SheetHeader extends StatelessWidget {
  const SheetHeader(
      {super.key, required this.title, this.eyebrow, this.trailing});
  final String title;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (eyebrow != null) ...[
              Eyebrow(eyebrow!, color: TF.brand),
              const SizedBox(height: 4)
            ],
            Text(title, style: TFText.h2()),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

const kPriorities = ['urgent', 'high', 'medium', 'low'];
