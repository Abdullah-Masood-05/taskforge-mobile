import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/widgets.dart';

/// Bottom sheet with a single text field. Returns the trimmed text, or null
/// when dismissed / unchanged-empty.
Future<String?> promptTextSheet(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String action = 'Save',
}) {
  return showTFSheet<String>(
    context,
    builder: (_) => _TextPromptSheet(
        title: title, initial: initial, hint: hint, action: action),
  );
}

class _TextPromptSheet extends StatefulWidget {
  const _TextPromptSheet(
      {required this.title,
      required this.initial,
      required this.hint,
      required this.action});
  final String title;
  final String initial;
  final String hint;
  final String action;

  @override
  State<_TextPromptSheet> createState() => _TextPromptSheetState();
}

class _TextPromptSheetState extends State<_TextPromptSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: TFText.h3()),
            const SizedBox(height: 14),
            TFTextField(
              controller: _controller,
              hint: widget.hint,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            TFButton(label: widget.action, expand: true, onPressed: _submit),
          ]),
    );
  }
}

/// Multi-select of org members. Returns the selected user ids, or null if
/// dismissed.
Future<Set<String>?> pickAssigneesSheet(
  BuildContext context, {
  required List<Member> members,
  required Set<String> selected,
}) {
  return showTFSheet<Set<String>>(
    context,
    builder: (_) => _MultiPickSheet<Member>(
      title: 'Assignees',
      eyebrow: 'Assign members',
      items: members,
      idOf: (m) => m.userId,
      initial: selected,
      emptyText: 'No members in this organization yet.',
      leadingOf: (m) =>
          TFAvatar(name: m.displayName, imageUrl: m.avatar, size: 30),
      titleOf: (m) => m.displayName,
      subtitleOf: (m) => m.email,
      accentOf: (_) => TF.brand,
    ),
  );
}

/// Multi-select of project labels. Returns the selected label ids, or null.
Future<Set<String>?> pickLabelsSheet(
  BuildContext context, {
  required List<Label> labels,
  required Set<String> selected,
}) {
  return showTFSheet<Set<String>>(
    context,
    builder: (_) => _MultiPickSheet<Label>(
      title: 'Labels',
      eyebrow: 'Tag this task',
      items: labels,
      idOf: (l) => l.id,
      initial: selected,
      emptyText:
          'This project has no labels yet. Create them from the web board.',
      leadingOf: (l) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
            color: TF.hex(l.color),
            borderRadius: BorderRadius.circular(TF.radiusSm)),
      ),
      titleOf: (l) => l.name,
      subtitleOf: (_) => null,
      accentOf: (l) => TF.hex(l.color),
    ),
  );
}

class _MultiPickSheet<T> extends StatefulWidget {
  const _MultiPickSheet({
    required this.title,
    required this.eyebrow,
    required this.items,
    required this.idOf,
    required this.initial,
    required this.emptyText,
    required this.leadingOf,
    required this.titleOf,
    required this.subtitleOf,
    required this.accentOf,
  });

  final String title;
  final String eyebrow;
  final List<T> items;
  final String Function(T) idOf;
  final Set<String> initial;
  final String emptyText;
  final Widget Function(T) leadingOf;
  final String Function(T) titleOf;
  final String? Function(T) subtitleOf;
  final Color Function(T) accentOf;

  @override
  State<_MultiPickSheet<T>> createState() => _MultiPickSheetState<T>();
}

class _MultiPickSheetState<T> extends State<_MultiPickSheet<T>> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.6;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Eyebrow(widget.eyebrow),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Text(widget.title, style: TFText.h3())),
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: Text('Clear',
                      style: TFText.sans(size: 13, color: TF.textMuted)),
                ),
            ]),
            const SizedBox(height: 10),
            if (widget.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(widget.emptyText,
                    style: TFText.small(), textAlign: TextAlign.center),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final item = widget.items[i];
                    final id = widget.idOf(item);
                    final on = _selected.contains(id);
                    final accent = widget.accentOf(item);
                    final sub = widget.subtitleOf(item);
                    return Pressable(
                      scale: 0.985,
                      onTap: () => setState(
                          () => on ? _selected.remove(id) : _selected.add(id)),
                      child: AnimatedContainer(
                        duration: TF.dur,
                        curve: TF.ease,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: on
                              ? accent.withValues(alpha: 0.10)
                              : TF.bgElevated,
                          borderRadius: BorderRadius.circular(TF.radiusMd),
                          border: Border.all(
                              color: on
                                  ? accent.withValues(alpha: 0.55)
                                  : TF.borderDefault),
                        ),
                        child: Row(children: [
                          widget.leadingOf(item),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(widget.titleOf(item),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TFText.sans(
                                          size: 14,
                                          weight: FontWeight.w500,
                                          color: TF.textPrimary)),
                                  if (sub != null && sub.isNotEmpty)
                                    Text(sub,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TFText.small()),
                                ]),
                          ),
                          AnimatedContainer(
                            duration: TF.dur,
                            curve: TF.ease,
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: on ? accent : Colors.transparent,
                              borderRadius: BorderRadius.circular(TF.radiusSm),
                              border: Border.all(
                                  color: on ? accent : TF.borderStrong,
                                  width: 1.2),
                            ),
                            child: AnimatedScale(
                              scale: on ? 1 : 0,
                              duration: TF.dur,
                              curve: TF.easeBounce,
                              child: const Icon(Icons.check_rounded,
                                  size: 14, color: TF.bgBase),
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            TFButton(
              label: _selected.isEmpty
                  ? 'Save (none)'
                  : 'Save (${_selected.length})',
              expand: true,
              onPressed: () =>
                  Navigator.of(context).pop<Set<String>>({..._selected}),
            ),
          ]),
    );
  }
}
