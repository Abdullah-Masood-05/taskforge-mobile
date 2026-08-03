import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/widgets.dart';
import 'board_providers.dart';
import 'board_widgets.dart';

/// Opens the "New task" sheet (web `NewTaskModal`). Returns the created task
/// and adds it to the board optimistically.
Future<Task?> showNewTaskSheet(
  BuildContext context,
  WidgetRef ref, {
  required String slug,
  required String projectId,
  String? statusId,
}) async {
  final key = BoardKey(slug, projectId);
  final task = await showTFSheet<Task>(
    context,
    builder: (_) => _NewTaskSheet(boardKey: key, initialStatusId: statusId),
  );
  if (task != null && context.mounted) {
    ref.read(boardControllerProvider(key).notifier).addTask(task);
    ref.invalidate(projectDetailProvider(key));
    ref.invalidate(analyticsProvider(key));
    ref.invalidate(timelineProvider(key));
    ref.invalidate(projectActivityProvider(key));
    showToast(context, 'Task created');
  }
  return task;
}

class _NewTaskSheet extends ConsumerStatefulWidget {
  const _NewTaskSheet({required this.boardKey, this.initialStatusId});
  final BoardKey boardKey;
  final String? initialStatusId;

  @override
  ConsumerState<_NewTaskSheet> createState() => _NewTaskSheetState();
}

class _NewTaskSheetState extends ConsumerState<_NewTaskSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _priority = 'medium';
  String? _statusId;
  final _assignees = <String>{};
  final _labels = <String>{};
  DateTime? _start;
  DateTime? _due;
  bool _saving = false;
  String? _titleError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _statusId = widget.initialStatusId;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    setState(() {
      _titleError = title.isEmpty ? 'Give the task a title' : null;
      _formError = null;
    });
    if (title.isEmpty) return;
    if (_start != null && _due != null && _due!.isBefore(_start!)) {
      setState(() => _formError = 'Due date can’t be before the start date.');
      return;
    }

    setState(() => _saving = true);
    try {
      final k = widget.boardKey;
      final statuses = ref.read(boardStatusesProvider(k)).valueOrNull ??
          const <TaskStatus>[];
      final statusId =
          _statusId ?? (statuses.isNotEmpty ? statuses.first.id : null);
      final task =
          await ref.read(repositoryProvider).createTask(k.slug, k.projectId, {
        'title': title,
        if (_description.text.trim().isNotEmpty)
          'description': _description.text.trim(),
        'priority': _priority,
        if (statusId != null) 'status_id': statusId,
        if (_assignees.isNotEmpty) 'assignee_ids': _assignees.toList(),
        if (_labels.isNotEmpty) 'label_ids': _labels.toList(),
        if (_start != null) 'start_date': Fmt.apiDate(_start!),
        if (_due != null) 'due_date': Fmt.apiDate(_due!),
      });
      if (mounted) Navigator.of(context).pop(task);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _titleError = e is ApiError ? e.fieldError('title') : null;
        _formError = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.boardKey;
    final statuses =
        ref.watch(boardStatusesProvider(k)).valueOrNull ?? const <TaskStatus>[];
    final members = ref.watch(membersProvider(k.slug));
    final labels = ref.watch(labelsProvider(k)).valueOrNull ?? const <Label>[];

    // Default to the first column when none was given.
    final statusId =
        _statusId ?? (statuses.isNotEmpty ? statuses.first.id : null);

    final sections = <Widget>[
      TFTextField(
        label: 'Title',
        hint: 'What needs to be done?',
        controller: _title,
        autofocus: true,
        errorText: _titleError,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 14),
      TFTextField(
        label: 'Description',
        hint: 'Add context, acceptance criteria, links…',
        controller: _description,
        maxLines: 4,
        minLines: 2,
      ),
      const SizedBox(height: 20),
      FieldBlock(
        label: 'Priority',
        child: ChoiceChips<String>(
          options: kPriorities,
          value: _priority,
          onChanged: (v) => setState(() => _priority = v),
          labelOf: Fmt.title,
          colorOf: TF.priorityColor,
        ),
      ),
      if (statuses.isNotEmpty)
        FieldBlock(
          label: 'Column',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in statuses)
              ToggleChip(
                label: s.name,
                selected: s.id == statusId,
                color: TF.hex(s.color),
                leading: ColorDot(TF.hex(s.color)),
                onTap: () => setState(() => _statusId = s.id),
              ),
          ]),
        ),
      FieldBlock(
        label: 'Assignees',
        trailing: _assignees.isEmpty
            ? null
            : Text('${_assignees.length} SELECTED',
                style:
                    TFText.mono(size: 10, color: TF.brand, letterSpacing: 1)),
        child: members.when(
          skipLoadingOnRefresh: true,
          data: (list) => list.isEmpty
              ? Text('No members in this organization yet.',
                  style: TFText.small())
              : Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in list)
                    ToggleChip(
                      label: m.displayName,
                      selected: _assignees.contains(m.userId),
                      leading: TFAvatar(
                          name: m.displayName, imageUrl: m.avatar, size: 20),
                      onTap: () => setState(() {
                        if (!_assignees.remove(m.userId)) {
                          _assignees.add(m.userId);
                        }
                      }),
                    ),
                ]),
          loading: () => const Skeleton(height: 34, width: 220),
          error: (e, _) =>
              Text(errorMessage(e), style: TFText.small(color: TF.danger)),
        ),
      ),
      if (labels.isNotEmpty)
        FieldBlock(
          label: 'Labels',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final l in labels)
              ToggleChip(
                label: l.name,
                selected: _labels.contains(l.id),
                color: TF.hex(l.color),
                leading: ColorDot(TF.hex(l.color)),
                onTap: () => setState(() {
                  if (!_labels.remove(l.id)) _labels.add(l.id);
                }),
              ),
          ]),
        ),
      FieldBlock(
        label: 'Schedule',
        child: Row(children: [
          Expanded(
              child: DateField(
                  label: 'Start date',
                  value: _start,
                  onChanged: (d) => setState(() => _start = d))),
          const SizedBox(width: 10),
          Expanded(
            child: DateField(
              label: 'Due date',
              value: _due,
              firstDate: _start,
              onChanged: (d) => setState(() => _due = d),
            ),
          ),
        ]),
      ),
    ];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SheetHeader(title: 'New task', eyebrow: 'Create'),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              children: [
                for (final (i, w) in sections.indexed)
                  w
                      .animate()
                      .fadeIn(delay: (i * 35).ms, duration: 260.ms)
                      .slideY(begin: 0.06, end: 0),
              ],
            ),
          ),
          AnimatedSize(
            duration: TF.dur,
            child: _formError == null
                ? const SizedBox(width: double.infinity)
                : Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: TF.dangerLight,
                      borderRadius: BorderRadius.circular(TF.radiusMd),
                      border:
                          Border.all(color: TF.danger.withValues(alpha: 0.3)),
                    ),
                    child: Text(_formError!,
                        style: TFText.small(color: TF.danger)),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: TF.borderSubtle))),
            child: Row(children: [
              Expanded(
                child: TFButton(
                  label: 'Cancel',
                  variant: TFButtonVariant.secondary,
                  expand: true,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TFButton(
                  label: 'Create task',
                  icon: Icons.add_rounded,
                  expand: true,
                  loading: _saving,
                  onPressed: _submit,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
