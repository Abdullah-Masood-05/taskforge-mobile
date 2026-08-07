import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/widgets.dart';
import 'task_providers.dart';
import 'task_sheets.dart';

const kPriorities = ['low', 'medium', 'high', 'urgent'];

/// Runs a task mutation and toasts on failure.
Future<void> runTaskMutation(
    BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) showErrorToast(context, e);
  }
}

// ── Inline title ──────────────────────────────────────────────────────────────

/// Task title that turns into a text field on tap; saves on submit/blur.
/// Wrapped in the same Hero tag the board card uses (`task-<id>`).
class InlineTitle extends StatefulWidget {
  const InlineTitle(
      {super.key,
      required this.taskId,
      required this.title,
      required this.onSave});
  final String taskId;
  final String title;
  final ValueChanged<String> onSave;

  @override
  State<InlineTitle> createState() => _InlineTitleState();
}

class _InlineTitleState extends State<InlineTitle> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.title);
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted && !_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant InlineTitle old) {
    super.didUpdateWidget(old);
    if (!_editing && old.title != widget.title) _controller.text = widget.title;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    _controller.text = widget.title;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _controller.selection =
          TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    });
  }

  void _commit() {
    final v = _controller.text.trim().replaceAll('\n', ' ');
    setState(() => _editing = false);
    if (v.isNotEmpty && v != widget.title) widget.onSave(v);
  }

  @override
  Widget build(BuildContext context) {
    final style = TFText.h2();
    return AnimatedSwitcher(
      duration: TF.durFast,
      child: _editing
          ? TextField(
              key: const ValueKey('edit'),
              controller: _controller,
              focusNode: _focus,
              style: style,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _focus.unfocus(),
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            )
          : GestureDetector(
              key: const ValueKey('view'),
              behavior: HitTestBehavior.opaque,
              onTap: _start,
              child: Hero(
                tag: 'task-${widget.taskId}',
                flightShuttleBuilder: taskHeroShuttle,
                child: Material(
                  type: MaterialType.transparency,
                  child: Text(widget.title, style: style),
                ),
              ),
            ),
    );
  }
}

/// Flies the source title (card on push, detail on pop) scaled to fit, so
/// differing text styles never overflow mid-flight.
Widget taskHeroShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final from = fromHeroContext.widget;
  final child = from is Hero ? from.child : const SizedBox.shrink();
  return Material(
    type: MaterialType.transparency,
    child: FittedBox(
        fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: child),
  );
}

// ── Field rows ────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: TF.textMuted),
          const SizedBox(width: 6)
        ],
        Text(text.toUpperCase(), style: TFText.eyebrow()),
      ]),
    );
  }
}

/// Status, priority, assignees, labels, dates and progress.
class TaskFields extends ConsumerWidget {
  const TaskFields({super.key, required this.task, required this.taskRef});
  final Task task;
  final TaskRef taskRef;

  ProjectRef get _projectRef =>
      (slug: taskRef.slug, projectId: taskRef.projectId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(taskDetailProvider(taskRef).notifier);
    final statuses = ref.watch(taskStatusOptionsProvider(_projectRef));
    final labels = ref.watch(taskLabelOptionsProvider(_projectRef));
    final members = ref.watch(membersProvider(taskRef.slug));

    void patch(Map<String, dynamic> data, Task Function(Task t) optimistic) {
      HapticFeedback.selectionClick();
      runTaskMutation(
          context, () => notifier.patch(data, optimistic: optimistic));
    }

    // Status ---------------------------------------------------------------
    Widget statusField() {
      final list = statuses.valueOrNull;
      if (list == null) {
        return statuses.hasError
            ? Text('Could not load columns.',
                style: TFText.small(color: TF.danger))
            : const Skeleton(height: 34, width: 220);
      }
      if (list.isEmpty) {
        return Text('No columns in this project.', style: TFText.small());
      }
      return ChoiceChips<String>(
        options: list.map((s) => s.id).toList(),
        value: task.statusId,
        labelOf: (id) => list.firstWhere((s) => s.id == id).name,
        colorOf: (id) => TF.hex(list.firstWhere((s) => s.id == id).color),
        onChanged: (id) {
          if (id == task.statusId) return;
          final st = list.firstWhere((s) => s.id == id);
          patch({'status_id': id},
              (t) => t.copyFull(statusId: () => id, status: () => st));
        },
      );
    }

    // Assignees --------------------------------------------------------------
    Future<void> editAssignees() async {
      final all = members.valueOrNull;
      if (all == null) {
        showToast(context,
            members.hasError ? 'Could not load members.' : 'Loading members…',
            kind: ToastKind.info);
        return;
      }
      final picked = await pickAssigneesSheet(
        context,
        members: all,
        selected: task.assignees.map((a) => a.id).toSet(),
      );
      if (picked == null || !context.mounted) return;
      final current = task.assignees.map((a) => a.id).toSet();
      if (picked.length == current.length && picked.containsAll(current)) {
        return;
      }
      final users = all
          .where((m) => picked.contains(m.userId))
          .map((m) => UserSummary(
              id: m.userId,
              email: m.email,
              fullName: m.fullName,
              avatarUrl: m.avatar))
          .toList();
      patch({'assignee_ids': picked.toList()},
          (t) => t.copyFull(assignees: users));
    }

    // Labels -------------------------------------------------------------------
    Future<void> editLabels() async {
      final all = labels.valueOrNull;
      if (all == null) {
        showToast(context,
            labels.hasError ? 'Could not load labels.' : 'Loading labels…',
            kind: ToastKind.info);
        return;
      }
      final picked = await pickLabelsSheet(context,
          labels: all, selected: task.labels.map((l) => l.id).toSet());
      if (picked == null || !context.mounted) return;
      final current = task.labels.map((l) => l.id).toSet();
      if (picked.length == current.length && picked.containsAll(current)) {
        return;
      }
      final chosen = all.where((l) => picked.contains(l.id)).toList();
      patch({'label_ids': picked.toList()}, (t) => t.copyFull(labels: chosen));
    }

    // Dates --------------------------------------------------------------------
    Future<void> pickDate({required bool due}) async {
      final current = due ? task.dueDate : task.startDate;
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: current ?? (due ? (task.startDate ?? now) : now),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: due ? 'DUE DATE' : 'START DATE',
      );
      if (picked == null || !context.mounted) return;
      final key = due ? 'due_date' : 'start_date';
      patch(
        {key: Fmt.apiDate(picked)},
        (t) => due
            ? t.copyFull(dueDate: () => picked)
            : t.copyFull(startDate: () => picked),
      );
    }

    void clearDate({required bool due}) {
      patch(
        {due ? 'due_date' : 'start_date': null},
        (t) => due
            ? t.copyFull(dueDate: () => null)
            : t.copyFull(startDate: () => null),
      );
    }

    return TFCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _FieldLabel('Status', icon: Icons.view_column_outlined),
        statusField(),
        const _Divider(),
        const _FieldLabel('Priority', icon: Icons.flag_outlined),
        ChoiceChips<String>(
          options: kPriorities,
          value: task.priority,
          labelOf: Fmt.title,
          colorOf: TF.priorityColor,
          onChanged: (p) {
            if (p == task.priority) return;
            patch({'priority': p}, (t) => t.copyFull(priority: p));
          },
        ),
        const _Divider(),
        const _FieldLabel('Assignees', icon: Icons.people_alt_outlined),
        _TapRow(
          onTap: editAssignees,
          child: task.assignees.isEmpty
              ? Text('Unassigned — tap to assign',
                  style: TFText.sans(size: 14, color: TF.textMuted))
              : Row(children: [
                  AvatarStack(
                    names: task.assignees.map((a) => a.displayName).toList(),
                    urls: task.assignees.map((a) => a.avatarUrl).toList(),
                    size: 26,
                    max: 4,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      task.assignees.map((a) => a.displayName).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TFText.sans(size: 14, color: TF.textSecondary),
                    ),
                  ),
                ]),
        ),
        const _Divider(),
        const _FieldLabel('Labels', icon: Icons.sell_outlined),
        _TapRow(
          onTap: editLabels,
          child: task.labels.isEmpty
              ? Text('No labels — tap to add',
                  style: TFText.sans(size: 14, color: TF.textMuted))
              : Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final l in task.labels)
                    TFBadge(l.name,
                        color: TF.hex(l.color), dot: true, mono: false),
                ]),
        ),
        const _Divider(),
        Row(children: [
          Expanded(
            child: _DateTile(
              label: 'Start',
              date: task.startDate,
              onTap: () => pickDate(due: false),
              onClear:
                  task.startDate == null ? null : () => clearDate(due: false),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DateTile(
              label: 'Due',
              date: task.dueDate,
              overdue: task.isOverdue,
              onTap: () => pickDate(due: true),
              onClear: task.dueDate == null ? null : () => clearDate(due: true),
            ),
          ),
        ]),
        const _Divider(),
        _ProgressEditor(
          value: task.progressPercent,
          onCommit: (v) => patch(
              {'progress_percent': v}, (t) => t.copyFull(progressPercent: v)),
        ),
      ]),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, color: TF.borderSubtle));
}

class _TapRow extends StatelessWidget {
  const _TapRow({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: 0.985,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: TF.bgElevated,
          borderRadius: BorderRadius.circular(TF.radiusMd),
          border: Border.all(color: TF.borderDefault),
        ),
        child: Row(children: [
          Expanded(child: child),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: TF.textMuted),
        ]),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile(
      {required this.label,
      required this.date,
      required this.onTap,
      this.onClear,
      this.overdue = false});
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final color =
        overdue ? TF.danger : (date == null ? TF.textMuted : TF.textPrimary);
    return Pressable(
      scale: 0.97,
      onTap: onTap,
      child: AnimatedContainer(
        duration: TF.dur,
        padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
        decoration: BoxDecoration(
          color: overdue ? TF.dangerLight : TF.bgElevated,
          borderRadius: BorderRadius.circular(TF.radiusMd),
          border: Border.all(
              color: overdue
                  ? TF.danger.withValues(alpha: 0.4)
                  : TF.borderDefault),
        ),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                overdue
                    ? '${label.toUpperCase()} · OVERDUE'
                    : label.toUpperCase(),
                style: TFText.eyebrow(color: overdue ? TF.danger : TF.textMuted)
                    .copyWith(fontSize: 10, letterSpacing: 1.6),
              ),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.event_outlined, size: 14, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    date == null ? 'Set date' : Fmt.short(date),
                    overflow: TextOverflow.ellipsis,
                    style: TFText.sans(
                        size: 14, weight: FontWeight.w500, color: color),
                  ),
                ),
              ]),
            ]),
          ),
          if (onClear != null)
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 16,
                tooltip: 'Clear $label date',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, color: TF.textMuted),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ProgressEditor extends StatefulWidget {
  const _ProgressEditor({required this.value, required this.onCommit});
  final int value;
  final ValueChanged<int> onCommit;

  @override
  State<_ProgressEditor> createState() => _ProgressEditorState();
}

class _ProgressEditorState extends State<_ProgressEditor> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final shown =
        (_drag ?? widget.value.toDouble()).clamp(0.0, 100.0).toDouble();
    final done = shown >= 100;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(
            child: _FieldLabel('Progress', icon: Icons.show_chart_rounded)),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${shown.round()}%',
            style: TFText.mono(
                size: 13,
                weight: FontWeight.w700,
                color: done ? TF.success : TF.brand),
          ),
        ),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: done ? TF.success : TF.brand,
          inactiveTrackColor: TF.borderDefault,
          thumbColor: done ? TF.success : TF.brand,
          overlayColor: TF.brand.withValues(alpha: 0.12),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          tickMarkShape: SliderTickMarkShape.noTickMark,
          trackShape: const RectangularSliderTrackShape(),
        ),
        child: Slider(
          value: shown,
          min: 0,
          max: 100,
          divisions: 20,
          onChanged: (v) {
            if (v.round() != shown.round()) HapticFeedback.selectionClick();
            setState(() => _drag = v);
          },
          onChangeEnd: (v) {
            setState(() => _drag = null);
            final next = v.round();
            if (next != widget.value) widget.onCommit(next);
          },
        ),
      ),
    ]);
  }
}

// ── Description ───────────────────────────────────────────────────────────────

/// Multiline description with an explicit Save / Discard bar that slides in
/// once the text differs from the server copy.
class DescriptionEditor extends StatefulWidget {
  const DescriptionEditor(
      {super.key, required this.description, required this.onSave});
  final String description;
  final Future<void> Function(String value) onSave;

  @override
  State<DescriptionEditor> createState() => _DescriptionEditorState();
}

class _DescriptionEditorState extends State<DescriptionEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.description);
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final d = _controller.text != widget.description;
      if (d != _dirty) setState(() => _dirty = d);
    });
  }

  @override
  void didUpdateWidget(covariant DescriptionEditor old) {
    super.didUpdateWidget(old);
    if (old.description != widget.description) {
      if (!_dirty) {
        _controller.text = widget.description;
      } else {
        final d = _controller.text != widget.description;
        if (d != _dirty) setState(() => _dirty = d);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSave(_controller.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = _controller.text != widget.description;
    });
    FocusScope.of(context).unfocus();
  }

  void _discard() {
    _controller.text = widget.description;
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Eyebrow('Description'),
      const SizedBox(height: 10),
      TextField(
        controller: _controller,
        minLines: 3,
        maxLines: 12,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        style: TFText.body(color: TF.textPrimary),
        decoration: const InputDecoration(hintText: 'Add a description…'),
      ),
      AnimatedSize(
        duration: TF.dur,
        curve: TF.ease,
        alignment: Alignment.topCenter,
        child: _dirty
            ? Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TFButton(
                    label: 'Discard',
                    size: TFButtonSize.sm,
                    variant: TFButtonVariant.ghost,
                    onPressed: _saving ? null : _discard,
                  ),
                  const SizedBox(width: 8),
                  TFButton(
                    label: 'Save',
                    icon: Icons.check_rounded,
                    size: TFButtonSize.sm,
                    loading: _saving,
                    onPressed: _save,
                  ),
                ]),
              )
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}
