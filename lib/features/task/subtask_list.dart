import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/widgets.dart';
import 'task_providers.dart';
import 'task_sheets.dart';

/// Subtask checklist: progress bar, animated checkboxes, tap to toggle,
/// long-press to rename, swipe left to delete, inline add field.
class SubtaskList extends ConsumerStatefulWidget {
  const SubtaskList({super.key, required this.taskRef, required this.subtasks});
  final TaskRef taskRef;
  final List<SubTask> subtasks;

  @override
  ConsumerState<SubtaskList> createState() => _SubtaskListState();
}

class _SubtaskListState extends ConsumerState<SubtaskList> {
  final _addController = TextEditingController();
  final _addFocus = FocusNode();
  bool _canAdd = false;

  TaskDetailNotifier get _notifier =>
      ref.read(taskDetailProvider(widget.taskRef).notifier);

  @override
  void initState() {
    super.initState();
    _addController.addListener(() {
      final v = _addController.text.trim().isNotEmpty;
      if (v != _canAdd) setState(() => _canAdd = v);
    });
  }

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  void _add() {
    final title = _addController.text.trim();
    if (title.isEmpty) return;
    _addController.clear();
    _addFocus.requestFocus();
    _guard(() => _notifier.addSubtask(title));
  }

  Future<void> _rename(SubTask s) async {
    final title = await promptTextSheet(context,
        title: 'Rename subtask', initial: s.title, hint: 'Subtask title');
    if (title == null || title == s.title) return;
    await _guard(() => _notifier.renameSubtask(s, title));
  }

  @override
  Widget build(BuildContext context) {
    final subs = widget.subtasks;
    final done = subs.where((s) => s.completed).length;
    final total = subs.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Eyebrow(
        'Subtasks',
        trailing: total == 0
            ? null
            : AnimatedSwitcher(
                duration: TF.dur,
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position:
                        Tween(begin: const Offset(0, 0.4), end: Offset.zero)
                            .animate(a),
                    child: c,
                  ),
                ),
                child: Text(
                  '$done/$total',
                  key: ValueKey('$done/$total'),
                  style: TFText.mono(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: done == total ? TF.success : TF.textSecondary),
                ),
              ),
      ),
      if (total > 0) ...[
        const SizedBox(height: 10),
        TFProgressBar(
            value: done / total,
            height: 3,
            color: done == total ? TF.success : null),
      ],
      const SizedBox(height: 10),
      for (final s in subs)
        _SubtaskRow(
          key: ValueKey(s.id),
          subtask: s,
          onToggle: () {
            HapticFeedback.lightImpact();
            _guard(() => _notifier.toggleSubtask(s));
          },
          onRename: () => _rename(s),
          onDelete: () => _guard(() => _notifier.deleteSubtask(s)),
        ),
      if (total > 1)
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Text('Swipe left to delete · long-press to rename',
              style: TFText.mono(size: 10, color: TF.textDisabled)),
        ),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _addController,
            focusNode: _addFocus,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _add(),
            style: TFText.sans(size: 14),
            decoration: const InputDecoration(
              hintText: 'Add a subtask…',
              prefixIcon:
                  Icon(Icons.add_rounded, size: 18, color: TF.textMuted),
            ),
          ),
        ),
        const SizedBox(width: 8),
        TFButton(
          label: 'Add',
          size: TFButtonSize.md,
          variant: TFButtonVariant.secondary,
          onPressed: _canAdd ? _add : null,
        ),
      ]),
    ]);
  }
}

class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow(
      {super.key,
      required this.subtask,
      required this.onToggle,
      required this.onRename,
      required this.onDelete});
  final SubTask subtask;
  final VoidCallback onToggle;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = subtask;
    final pending = isPendingId(s.id);
    final row = Pressable(
      scale: 0.985,
      onTap: pending ? null : onToggle,
      onLongPress: pending ? null : onRename,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: TF.bgSurface,
          borderRadius: BorderRadius.circular(TF.radiusMd),
          border: Border.all(color: TF.borderSubtle),
        ),
        child: Row(children: [
          _AnimatedCheck(checked: s.completed, pending: pending),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: TF.dur,
              curve: TF.ease,
              style: TFText.sans(
                size: 14,
                color: s.completed ? TF.textMuted : TF.textPrimary,
              ).copyWith(
                decoration: s.completed
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                decorationColor: TF.textMuted,
              ),
              child: Text(s.title),
            ),
          ),
        ]),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: pending
          ? Opacity(opacity: 0.6, child: row)
          : Dismissible(
              key: ValueKey('dismiss-${s.id}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) {
                HapticFeedback.mediumImpact();
                onDelete();
              },
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: TF.dangerLight,
                  borderRadius: BorderRadius.circular(TF.radiusMd),
                  border: Border.all(color: TF.danger.withValues(alpha: 0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('DELETE', style: TFText.eyebrow(color: TF.danger)),
                  const SizedBox(width: 8),
                  const Icon(Icons.delete_outline_rounded,
                      color: TF.danger, size: 18),
                ]),
              ),
              child: row,
            ),
    )
        .animate()
        .fadeIn(duration: 240.ms)
        .slideX(begin: 0.05, end: 0, curve: TF.ease);
  }
}

/// Square checkbox that fills amber and pops the check mark in.
class _AnimatedCheck extends StatelessWidget {
  const _AnimatedCheck({required this.checked, required this.pending});
  final bool checked;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: TF.dur,
      curve: TF.ease,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: checked ? TF.brand : Colors.transparent,
        borderRadius: BorderRadius.circular(TF.radiusSm),
        border:
            Border.all(color: checked ? TF.brand : TF.borderStrong, width: 1.3),
        boxShadow: checked
            ? const [BoxShadow(color: Color(0x40F5A623), blurRadius: 8)]
            : null,
      ),
      child: pending
          ? const Padding(
              padding: EdgeInsets.all(4),
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: TF.textMuted),
            )
          : AnimatedScale(
              scale: checked ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              curve: TF.easeBounce,
              child:
                  const Icon(Icons.check_rounded, size: 15, color: TF.onBrand),
            ),
    );
  }
}
