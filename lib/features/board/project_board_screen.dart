import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_error.dart';
import '../../core/config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../widgets/widgets.dart';
import '../projects/project_form_sheet.dart';
import 'activity_view.dart';
import 'analytics_view.dart';
import 'board_filters.dart';
import 'board_providers.dart';
import 'board_socket.dart';
import 'board_widgets.dart';
import 'export_sheet.dart';
import 'kanban_board.dart';
import 'new_task_sheet.dart';
import 'timeline_view.dart';

/// Project board dashboard (web `projects/[projectId]/board/page.jsx`):
/// header + Board | Overview | Timeline | Activity tabs.
class ProjectBoardScreen extends ConsumerStatefulWidget {
  const ProjectBoardScreen(
      {super.key, required this.slug, required this.projectId});
  final String slug;
  final String projectId;

  @override
  ConsumerState<ProjectBoardScreen> createState() => _ProjectBoardScreenState();
}

enum _MenuAction { edit, column, exportJson, exportReport, web, refresh }

class _ProjectBoardScreenState extends ConsumerState<ProjectBoardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this)
    ..addListener(_onTab);
  late final BoardKey _key = BoardKey(widget.slug, widget.projectId);
  String? _currentStatusId;
  bool _headerExpanded = true;

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    super.dispose();
  }

  void _onTab() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _openTask(String taskId) async {
    await context.push(
        '/orgs/${widget.slug}/projects/${widget.projectId}/tasks/$taskId');
    if (!mounted) return;
    ref.invalidate(boardTasksProvider);
    ref.invalidate(projectDetailProvider(_key));
    ref.invalidate(projectActivityProvider(_key));
    ref.invalidate(analyticsProvider(_key));
    ref.invalidate(timelineProvider(_key));
  }

  Future<void> _move(Task task, String statusId, String? beforeTaskId) async {
    try {
      await ref
          .read(boardControllerProvider(_key).notifier)
          .moveTask(task.id, statusId, beforeTaskId: beforeTaskId);
      if (!mounted) return;
      ref.invalidate(projectActivityProvider(_key));
      ref.invalidate(analyticsProvider(_key));
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _newTask([String? statusId]) => showNewTaskSheet(context, ref,
      slug: widget.slug,
      projectId: widget.projectId,
      statusId: statusId ?? _currentStatusId);

  Future<void> _refreshAll() async {
    refreshBoard(ref, _key);
    try {
      await ref.read(boardControllerProvider(_key).future);
    } catch (_) {}
  }

  Future<void> _editProject() async {
    final project = ref.read(projectDetailProvider(_key)).valueOrNull;
    if (project == null) return;
    final updated = await showProjectFormSheet(context, ref,
        slug: widget.slug, existing: project);
    if (updated != null && mounted) {
      ref.invalidate(projectDetailProvider(_key));
      showToast(context, 'Project updated');
    }
  }

  Future<void> _newColumn() async {
    final status = await showTFSheet<TaskStatus>(context,
        builder: (_) => _NewColumnSheet(boardKey: _key));
    if (status != null && mounted) {
      ref.invalidate(boardStatusesProvider(_key));
      showToast(context, 'Column “${status.name}” added');
    }
  }

  Future<void> _onMenu(_MenuAction a) async {
    switch (a) {
      case _MenuAction.edit:
        await _editProject();
      case _MenuAction.column:
        await _newColumn();
      case _MenuAction.exportJson:
        await showJsonExportSheet(context, _key);
      case _MenuAction.exportReport:
        await showReportExportSheet(context, _key);
      case _MenuAction.web:
        final uri = Uri.parse(
            '${AppConfig.webUrl}/orgs/${widget.slug}/projects/${widget.projectId}/board');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      case _MenuAction.refresh:
        await _refreshAll();
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectDetailProvider(_key));
    final live = ref.watch(boardSocketProvider(_key));
    final filters = ref.watch(boardFiltersProvider(_key));
    final onBoard = _tabs.index == 0;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('PROJECT', style: TFText.eyebrow(color: TF.brand)),
                const SizedBox(width: 8),
                _LiveDot(live: live),
              ]),
              const SizedBox(height: 2),
              Text(
                project.valueOrNull?.name ?? 'Loading…',
                overflow: TextOverflow.ellipsis,
                style: TFText.sans(
                    size: 17, weight: FontWeight.w600, letterSpacing: -0.2),
              ),
            ]),
        actions: [
          TFIconButton(
            icon: Icons.tune_rounded,
            size: 38,
            tooltip: 'Filter & search',
            badge: filters.activeCount,
            onPressed: () => showBoardFilters(context, ref, _key),
          ),
          PopupMenuButton<_MenuAction>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _onMenu,
            itemBuilder: (_) => [
              _menuItem(_MenuAction.edit, Icons.edit_outlined, 'Edit project'),
              _menuItem(
                  _MenuAction.column, Icons.view_column_outlined, 'New column'),
              const PopupMenuDivider(),
              _menuItem(_MenuAction.exportJson, Icons.data_object_rounded,
                  'Export JSON'),
              _menuItem(_MenuAction.exportReport, Icons.picture_as_pdf_outlined,
                  'Export PDF report'),
              const PopupMenuDivider(),
              _menuItem(
                  _MenuAction.web, Icons.open_in_new_rounded, 'Open on web'),
              _menuItem(_MenuAction.refresh, Icons.refresh_rounded, 'Refresh'),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        project.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          data: (p) => _ProjectHeader(
            project: p,
            boardKey: _key,
            expanded: _headerExpanded,
            onToggle: () => setState(() => _headerExpanded = !_headerExpanded),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Skeleton(height: 20, width: 170),
              SizedBox(height: 14),
              Skeleton(height: 6),
              SizedBox(height: 14),
              Skeleton(height: 16, width: 240),
            ]),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded,
                  size: 16, color: TF.danger),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Couldn’t load project details',
                      style: TFText.small(color: TF.danger))),
              TextButton(
                  onPressed: () => ref.invalidate(projectDetailProvider(_key)),
                  child: const Text('Retry')),
            ]),
          ),
        ),
        TabBar(
          controller: _tabs,
          labelPadding: EdgeInsets.zero,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(height: 42, text: 'Board'),
            Tab(height: 42, text: 'Overview'),
            Tab(height: 42, text: 'Timeline'),
            Tab(height: 42, text: 'Activity'),
          ],
        ),
        if (onBoard) ActiveFiltersBar(boardKey: _key),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            // Horizontal swipes belong to the Kanban pager.
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _BoardTab(
                boardKey: _key,
                onOpenTask: (t) => _openTask(t.id),
                onMove: _move,
                onAddTask: _newTask,
                onRefresh: _refreshAll,
                onAddColumn: _newColumn,
                onPageChanged: (id) => _currentStatusId = id,
              ),
              AnalyticsView(boardKey: _key),
              TimelineView(boardKey: _key, onOpenTask: _openTask),
              ActivityView(boardKey: _key, onOpenTask: _openTask),
            ],
          ),
        ),
      ]),
      floatingActionButton: AnimatedScale(
        scale: onBoard ? 1.0 : 0.0,
        duration: TF.dur,
        curve: onBoard ? TF.easeBounce : TF.ease,
        child: _NewTaskFab(onTap: onBoard ? () => _newTask() : null),
      ),
    );
  }

  PopupMenuItem<_MenuAction> _menuItem(
          _MenuAction value, IconData icon, String label) =>
      PopupMenuItem(
        value: value,
        height: 44,
        child: Row(children: [
          Icon(icon, size: 18, color: TF.textSecondary),
          const SizedBox(width: 12),
          Text(label, style: TFText.sans(size: 14)),
        ]),
      );
}

// ── Board tab ─────────────────────────────────────────────────────────────────

class _BoardTab extends ConsumerWidget {
  const _BoardTab({
    required this.boardKey,
    required this.onOpenTask,
    required this.onMove,
    required this.onAddTask,
    required this.onRefresh,
    required this.onAddColumn,
    required this.onPageChanged,
  });

  final BoardKey boardKey;
  final ValueChanged<Task> onOpenTask;
  final void Function(Task task, String statusId, String? beforeTaskId) onMove;
  final ValueChanged<String> onAddTask;
  final Future<void> Function() onRefresh;
  final VoidCallback onAddColumn;
  final ValueChanged<String?> onPageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statuses = ref.watch(boardStatusesProvider(boardKey));
    final tasks = ref.watch(boardControllerProvider(boardKey));

    return AsyncView<List<TaskStatus>>(
      value: statuses,
      onRetry: () => ref.invalidate(boardStatusesProvider(boardKey)),
      loading: const _BoardSkeleton(),
      data: (cols) {
        if (cols.isEmpty) {
          return EmptyState(
            icon: Icons.view_kanban_outlined,
            title: 'No columns yet',
            message:
                'Add your first workflow stage — e.g. To do, In progress, Done.',
            action: TFButton(
                label: 'Add column',
                icon: Icons.add_rounded,
                onPressed: onAddColumn),
          );
        }
        return AsyncView<List<Task>>(
          value: tasks,
          onRetry: () => ref.invalidate(boardTasksProvider),
          loading: const _BoardSkeleton(),
          data: (list) => Stack(children: [
            KanbanBoard(
              statuses: cols,
              tasks: list,
              onOpenTask: onOpenTask,
              onMove: onMove,
              onAddTask: onAddTask,
              onRefresh: onRefresh,
              onAddColumn: onAddColumn,
              onPageChanged: onPageChanged,
            ),
            // Thin progress line while re-fetching (e.g. filters changed).
            if (tasks.isLoading)
              const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 1.5)),
          ]),
        );
      },
    );
  }
}

class _BoardSkeleton extends StatelessWidget {
  const _BoardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var c = 0; c < 2; c++)
          Container(
            width: MediaQuery.sizeOf(context).width * 0.8,
            margin: const EdgeInsets.only(right: 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Skeleton(height: 18, width: 120),
              const SizedBox(height: 14),
              for (var i = 0; i < 4 - c; i++) ...[
                const Skeleton(height: 96, radius: TF.radiusLg),
                const SizedBox(height: 8),
              ],
            ]),
          ),
      ]),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

Color _projectStatusColor(String s) => switch (s) {
      'in_progress' => TF.brand,
      'completed' => TF.success,
      'on_hold' => TF.danger,
      _ => TF.info,
    };

class _ProjectHeader extends ConsumerWidget {
  const _ProjectHeader(
      {required this.project,
      required this.boardKey,
      required this.expanded,
      required this.onToggle});
  final Project project;
  final BoardKey boardKey;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statuses = ref.watch(boardStatusesProvider(boardKey)).valueOrNull ??
        const <TaskStatus>[];
    final progress = (project.progressPercent ?? 0).clamp(0, 100);
    final due = project.dueDate;
    final now = DateTime.now();
    final overdue = due != null &&
        project.status != 'completed' &&
        DateTime(due.year, due.month, due.day)
            .isBefore(DateTime(now.year, now.month, now.day));

    Color statusColor(String name) {
      for (final s in statuses) {
        if (s.name == name) return TF.hex(s.color);
      }
      return TF.textMuted;
    }

    final owner = project.owner;
    final ownerName = owner?.displayName ??
        (project.ownerEmail.isNotEmpty
            ? project.ownerEmail.split('@').first
            : null);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          TFBadge(project.status,
              color: _projectStatusColor(project.status), dot: true),
          const SizedBox(width: 6),
          TFBadge.priority(project.priority),
          if (project.archived) ...[
            const SizedBox(width: 6),
            const TFBadge('archived', color: TF.textMuted),
          ],
          const Spacer(),
          Text('$progress%',
              style: TFText.mono(
                  size: 13, weight: FontWeight.w600, color: TF.textPrimary)),
          const SizedBox(width: 2),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: expanded ? 'Collapse' : 'Expand',
            onPressed: onToggle,
            icon: AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: TF.dur,
              child: const Icon(Icons.expand_more_rounded,
                  size: 20, color: TF.textMuted),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        TFProgressBar(
            value: progress / 100,
            height: 4,
            color: project.status == 'completed' ? TF.success : null),
        AnimatedSize(
          duration: TF.durSlow,
          curve: TF.ease,
          alignment: Alignment.topCenter,
          child: !expanded
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (project.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      project.description.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TFText.small(color: TF.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (ownerName != null)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            TFAvatar(
                                name: ownerName,
                                imageUrl: owner?.avatarUrl,
                                size: 20),
                            const SizedBox(width: 6),
                            Text(ownerName,
                                style: TFText.small(color: TF.textSecondary)),
                          ]),
                        if (due != null)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.event_rounded,
                                size: 14,
                                color: overdue ? TF.danger : TF.textMuted),
                            const SizedBox(width: 5),
                            Text(
                              overdue
                                  ? 'Overdue · ${Fmt.short(due)}'
                                  : 'Due ${Fmt.short(due)}',
                              style: TFText.mono(
                                  size: 11.5,
                                  color: overdue ? TF.danger : TF.textMuted),
                            ),
                          ]),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.layers_outlined,
                              size: 14, color: TF.textMuted),
                          const SizedBox(width: 5),
                          Text('${project.taskCount} tasks',
                              style: TFText.mono(size: 11.5)),
                        ]),
                      ]),
                  if (project.statusCounts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 26,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final e in project.statusCounts.entries)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: TF.bgSurface,
                                borderRadius:
                                    BorderRadius.circular(TF.radiusSm),
                                border: Border.all(color: TF.borderSubtle),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ColorDot(statusColor(e.key), size: 6),
                                    const SizedBox(width: 6),
                                    Text(e.key,
                                        style: TFText.sans(
                                            size: 12, color: TF.textSecondary)),
                                    const SizedBox(width: 6),
                                    Text('${e.value}',
                                        style: TFText.mono(
                                            size: 11, color: TF.textPrimary)),
                                  ]),
                            ),
                        ],
                      ),
                    ),
                  ],
                ]),
        ),
      ]),
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.live});
  final bool live;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: TF.durSlow,
      opacity: live ? 1.0 : 0.0,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6,
          height: 6,
          decoration:
              const BoxDecoration(color: TF.success, shape: BoxShape.circle),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fade(begin: 1, end: 0.35, duration: 1100.ms),
        const SizedBox(width: 4),
        Text('LIVE',
            style: TFText.mono(
                size: 9.5,
                weight: FontWeight.w700,
                color: TF.success,
                letterSpacing: 1.4)),
      ]),
    );
  }
}

class _NewTaskFab extends StatelessWidget {
  const _NewTaskFab({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          gradient: TF.brandGradient,
          borderRadius: BorderRadius.circular(TF.radiusLg),
          boxShadow: [...TF.shadowMd, ...TF.shadowGlow],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.add_rounded, color: TF.onBrand, size: 20),
          const SizedBox(width: 8),
          Text('New task',
              style: TFText.sans(
                  size: 14.5, weight: FontWeight.w600, color: TF.onBrand)),
        ]),
      ),
    );
  }
}

// ── New column sheet ──────────────────────────────────────────────────────────

class _NewColumnSheet extends ConsumerStatefulWidget {
  const _NewColumnSheet({required this.boardKey});
  final BoardKey boardKey;

  @override
  ConsumerState<_NewColumnSheet> createState() => _NewColumnSheetState();
}

class _NewColumnSheetState extends ConsumerState<_NewColumnSheet> {
  static const _colors = [
    '#6366f1',
    '#f5a623',
    '#10b981',
    '#9bd9ff',
    '#ff6b6b',
    '#c4a7e7',
    '#7dd3c0',
    '#ffc880'
  ];
  final _name = TextEditingController();
  String _color = _colors.first;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name the column');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final s = await ref.read(repositoryProvider).createStatus(
          widget.boardKey.slug, widget.boardKey.projectId,
          name: name, color: _color);
      if (mounted) Navigator.of(context).pop(s);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(title: 'New column', eyebrow: 'Workflow'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TFTextField(
                      label: 'Name',
                      hint: 'e.g. In review',
                      controller: _name,
                      autofocus: true,
                      errorText: _error,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 18),
                    FieldBlock(
                      label: 'Colour',
                      child: Wrap(spacing: 10, runSpacing: 10, children: [
                        for (final c in _colors)
                          GestureDetector(
                            onTap: () => setState(() => _color = c),
                            child: AnimatedContainer(
                              duration: TF.dur,
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: TF.hex(c).withValues(alpha: 0.18),
                                borderRadius:
                                    BorderRadius.circular(TF.radiusMd),
                                border: Border.all(
                                    color: _color == c
                                        ? TF.hex(c)
                                        : TF.borderDefault,
                                    width: _color == c ? 1.5 : 1),
                              ),
                              child: ColorDot(TF.hex(c),
                                  size: _color == c ? 12 : 9,
                                  glow: _color == c),
                            ),
                          ),
                      ]),
                    ),
                  ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: TFButton(
                  label: 'Add column',
                  icon: Icons.add_rounded,
                  expand: true,
                  loading: _saving,
                  onPressed: _save),
            ),
          ]),
    );
  }
}
