import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// Labelled text field (web `Input`): label above, hairline border, amber
/// focus ring, inline error.
class TFTextField extends StatefulWidget {
  const TFTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.errorText,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.validator,
    this.maxLines = 1,
    this.minLines,
    this.autofocus = false,
    this.prefixIcon,
    this.autofillHints,
    this.enabled = true,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? errorText;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final int maxLines;
  final int? minLines;
  final bool autofocus;
  final IconData? prefixIcon;
  final Iterable<String>? autofillHints;
  final bool enabled;

  @override
  State<TFTextField> createState() => _TFTextFieldState();
}

class _TFTextFieldState extends State<TFTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null) ...[
            Text(widget.label!,
                style: TFText.sans(
                    size: 13,
                    weight: FontWeight.w500,
                    color: TF.textSecondary)),
            const SizedBox(height: 6),
          ],
          TextFormField(
            controller: widget.controller,
            enabled: widget.enabled,
            obscureText: _hidden,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onFieldSubmitted: widget.onSubmitted,
            onChanged: widget.onChanged,
            validator: widget.validator,
            maxLines: widget.obscure ? 1 : widget.maxLines,
            minLines: widget.minLines,
            autofocus: widget.autofocus,
            autofillHints: widget.autofillHints,
            style: TFText.sans(size: 15),
            decoration: InputDecoration(
              hintText: widget.hint,
              errorText: widget.errorText,
              prefixIcon: widget.prefixIcon == null
                  ? null
                  : Icon(widget.prefixIcon, size: 18, color: TF.textMuted),
              suffixIcon: widget.obscure
                  ? IconButton(
                      icon: Icon(
                          _hidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                          color: TF.textMuted),
                      onPressed: () => setState(() => _hidden = !_hidden),
                    )
                  : null,
            ),
          ),
        ]);
  }
}

/// Segmented choice chips (e.g. priority picker).
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips(
      {super.key,
      required this.options,
      required this.value,
      required this.onChanged,
      required this.labelOf,
      this.colorOf});

  final List<T> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;
  final Color Function(T)? colorOf;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in options)
        _Chip(
          label: labelOf(o),
          selected: o == value,
          color: colorOf?.call(o) ?? TF.brand,
          onTap: () => onChanged(o),
        ),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label,
      required this.selected,
      required this.color,
      required this.onTap});
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: TF.dur,
        curve: TF.ease,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : TF.bgElevated,
          borderRadius: BorderRadius.circular(TF.radiusMd),
          border: Border.all(
              color:
                  selected ? color.withValues(alpha: 0.6) : TF.borderDefault),
        ),
        child: Text(
          label,
          style: TFText.sans(
              size: 13,
              weight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? color : TF.textSecondary),
        ),
      ),
    );
  }
}
