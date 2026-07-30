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
import 'project_card.dart';

/// Opens the create/edit project sheet. Resolves to the saved [Project], or
/// null if dismissed. Invalidates `projectsProvider(slug)` on success.
Future<Project?> showProjectFormSheet(
  BuildContext context,
  WidgetRef ref, {
  required String slug,
  Project? existing,
}) {
  return showTFSheet<Project>(
    context,
    builder: (_) => _ProjectForm(slug: slug, existing: existing),
  );
}

class _ProjectForm extends ConsumerStatefulWidget {
  const _ProjectForm({required this.slug, this.existing});
  final String slug;
  final Project? existing;

  @override
  ConsumerState<_ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends ConsumerState<_ProjectForm> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _desc =
      TextEditingController(text: widget.existing?.description ?? '');
  late String _status = kProjectStatuses.contains(widget.existing?.status)
      ? widget.existing!.status
      : 'planning';
  late String _priority = kProjectPriorities.contains(widget.existing?.priority)
      ? widget.existing!.priority
      : 'medium';
  late DateTime? _due = widget.existing?.dueDate;

  bool _saving = false;
  String? _nameError;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _due ?? now;
    final first = DateTime(2000);
    final last = DateTime(now.year + 10, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first)
          ? first
          : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
      helpText: 'DUE DATE',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: TF.brand,
            onPrimary: TF.onBrand,
            surface: TF.bgSurface,
            onSurface: TF.textPrimary,
            secondary: TF.brandSecondary,
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: TF.bgSurface,
            surfaceTintColor: Colors.transparent,
            headerBackgroundColor: TF.bgElevated,
            headerForegroundColor: TF.textPrimary,
            dividerColor: TF.borderDefault,
            todayBorder: const BorderSide(color: TF.brand),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TF.radiusXl),
              side: const BorderSide(color: TF.borderDefault),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: TF.brand),
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null && mounted) setState(() => _due = picked);
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Project name is required');
      return;
    }
    setState(() {
      _saving = true;
      _nameError = null;
    });

    final data = <String, dynamic>{
      'name': name,
      'description': _desc.text.trim(),
      'status': _status,
      'priority': _priority,
      if (_due != null) 'due_date': Fmt.apiDate(_due!),
      if (_due == null && _isEdit) 'due_date': null,
    };

    try {
      final repo = ref.read(repositoryProvider);
      final saved = _isEdit
          ? await repo.updateProject(widget.slug, widget.existing!.id, data)
          : await repo.createProject(widget.slug, data);
      ref.invalidate(projectsProvider(widget.slug));
      if (!mounted) return;
      showToast(context, _isEdit ? 'Project updated' : 'Project created');
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _nameError = e is ApiError ? e.fieldError('name') : null;
      });
      showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Eyebrow(_isEdit ? 'Edit project' : 'New project', color: TF.brand),
      const SizedBox(height: 6),
      Text(_isEdit ? 'Update ${widget.existing!.name}' : 'Start a new project',
          style: TFText.h2()),
      const SizedBox(height: 22),
      TFTextField(
        label: 'Name',
        hint: 'My awesome project',
        controller: _name,
        autofocus: !_isEdit,
        errorText: _nameError,
        textInputAction: TextInputAction.next,
        onChanged: (_) {
          if (_nameError != null) setState(() => _nameError = null);
        },
      ),
      const SizedBox(height: 16),
      TFTextField(
        label: 'Description (optional)',
        hint: "What's this project about?",
        controller: _desc,
        maxLines: 4,
        minLines: 3,
        keyboardType: TextInputType.multiline,
      ),
      const SizedBox(height: 20),
      const Eyebrow('Status'),
      const SizedBox(height: 10),
      ChoiceChips<String>(
        options: kProjectStatuses,
        value: _status,
        labelOf: projectStatusLabel,
        colorOf: (s) => s == 'planning' ? TF.info : projectStatusColor(s),
        onChanged: (v) => setState(() => _status = v),
      ),
      const SizedBox(height: 20),
      const Eyebrow('Priority'),
      const SizedBox(height: 10),
      ChoiceChips<String>(
        options: kProjectPriorities,
        value: _priority,
        labelOf: Fmt.title,
        colorOf: TF.priorityColor,
        onChanged: (v) => setState(() => _priority = v),
      ),
      const SizedBox(height: 20),
      const Eyebrow('Due date'),
      const SizedBox(height: 10),
      _DueDateField(
        date: _due,
        onTap: _pickDate,
        onClear: _due == null ? null : () => setState(() => _due = null),
      ),
      const SizedBox(height: 28),
      Row(children: [
        Expanded(
          child: TFButton(
            label: 'Cancel',
            variant: TFButtonVariant.secondary,
            expand: true,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: TFButton(
            label: _isEdit ? 'Save changes' : 'Create project',
            icon: _isEdit ? Icons.check_rounded : Icons.add_rounded,
            expand: true,
            loading: _saving,
            onPressed: _submit,
          ),
        ),
      ]),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++)
            children[i]
                .animate()
                .fadeIn(duration: 260.ms, delay: (20 * i).ms)
                .slideY(
                    begin: 0.06,
                    end: 0,
                    duration: 260.ms,
                    delay: (20 * i).ms,
                    curve: TF.ease),
        ],
      ),
    );
  }
}

class _DueDateField extends StatelessWidget {
  const _DueDateField({required this.date, required this.onTap, this.onClear});
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final has = date != null;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: AnimatedContainer(
        duration: TF.dur,
        curve: TF.ease,
        height: 48,
        padding: const EdgeInsets.only(left: 14, right: 4),
        decoration: BoxDecoration(
          color: TF.bgElevated,
          borderRadius: BorderRadius.circular(TF.radiusMd),
          border: Border.all(color: has ? TF.borderBrand : TF.borderDefault),
        ),
        child: Row(children: [
          Icon(Icons.event_outlined,
              size: 18, color: has ? TF.brand : TF.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: TF.dur,
              child: Text(
                has ? Fmt.short(date) : 'No due date',
                key: ValueKey(has ? Fmt.apiDate(date!) : 'none'),
                style: has
                    ? TFText.mono(size: 13, color: TF.textPrimary)
                    : TFText.sans(size: 14, color: TF.textDisabled),
              ),
            ),
          ),
          if (onClear != null)
            IconButton(
              tooltip: 'Clear due date',
              icon: const Icon(Icons.close_rounded,
                  size: 18, color: TF.textMuted),
              onPressed: onClear,
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(Icons.chevron_right_rounded,
                  size: 18, color: TF.textMuted),
            ),
        ]),
      ),
    );
  }
}
