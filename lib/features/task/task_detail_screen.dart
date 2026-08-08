import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../widgets/widgets.dart';
import 'activity_list.dart';
import 'attachments_list.dart';
import 'comments_section.dart';
import 'subtask_list.dart';
import 'task_fields.dart';
import 'task_providers.dart';

/// Full-screen task detail (web `TaskDetailModal` + `FileUpload` +
/// activity). Pops with `true` after the task is deleted.
class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen(
      {super.key,
      required this.slug,
      required this.projectId,
      required this.taskId});

  final String slug;
  final String projectId;
  final String taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _scroll = ScrollController();
  int _tab = 0;
  bool _deleting = false;

  TaskRef get _taskRef =>
      (slug: widget.slug, projectId: widget.projectId, taskId: widget.taskId);
  ProjectRef get _projectRef =>
      (slug: widget.slug, projectId: widget.projectId);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.index != _tab && mounted) setState(() => _tab = _tabs.index);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(taskCommentsProvider(_taskRef));
    ref.invalidate(taskActivityProvider(_taskRef));
    ref.invalidate(taskAttachmentsProvider(_taskRef));
    ref.invalidate(taskStatusOptionsProvider(_projectRef));
    ref.invalidate(taskLabelOptionsProvider(_projectRef));
    try {
      final _ = await ref.refresh(taskDetailProvider(_taskRef).future);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _delete(Task task) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete task?',
      message:
          '"${task.title}" and its subtasks, comments and attachments will be removed. This cannot be undone.',
      confirmLabel: 'Delete task',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref
          .read(repositoryProvider)
          .deleteTask(widget.slug, widget.projectId, widget.taskId);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showToast(context, 'Task deleted');
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showErrorToast(context, e);
    }
  }

  void _scrollToBottomSoon() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: TF.durSlow, curve: TF.ease);
    });
  }

  Future<void> _patch(
          Map<String, dynamic> data, Task Function(Task t) optimistic) =>
      runTaskMutation(
          context,
          () => ref
              .read(taskDetailProvider(_taskRef).notifier)
              .patch(data, optimistic: optimistic));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(taskDetailProvider(_taskRef));
    final task = async.valueOrNull;

    final Widget body;
    if (task != null) {
      body = _content(task);
    } else if (async.hasError) {
      body = ErrorState(
        error: async.error!,
        onRetry: () => ref.invalidate(taskDetailProvider(_taskRef)),
      );
    } else {
      body = _LoadingView(taskId: widget.taskId);
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Container(
              width: 6,
              height: 6,
              decoration:
                  const BoxDecoration(color: TF.brand, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(
            task?.referenceLabel ?? 'TASK',
            style: TFText.mono(
                size: 13,
                weight: FontWeight.w600,
                color: TF.textSecondary,
                letterSpacing: 1.2),
          ),
        ]),
        actions: [
          if (_deleting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (task != null)
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) {
                switch (v) {
                  case 'copy':
                    {
                      final label = task.referenceLabel ?? task.title;
                      Clipboard.setData(ClipboardData(text: label));
                      showToast(context, 'Copied $label', kind: ToastKind.info);
                    }
                  case 'refresh':
                    _refresh();
                  case 'delete':
                    _delete(task);
                }
              },
              itemBuilder: (_) => [
                _menuItem('copy', Icons.copy_rounded, 'Copy reference'),
                _menuItem('refresh', Icons.refresh_rounded, 'Refresh'),
                const PopupMenuDivider(height: 8),
                _menuItem('delete', Icons.delete_outline_rounded, 'Delete task',
                    color: TF.danger),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(top: false, bottom: false, child: body),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {Color color = TF.textPrimary}) {
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(label, style: TFText.sans(size: 14, color: color)),
      ]),
    );
  }

  Widget _content(Task task) {
    final commentCount =
        ref.watch(taskCommentsProvider(_taskRef)).valueOrNull?.length ??
            task.comments.length;
    final fileCount =
        ref.watch(taskAttachmentsProvider(_taskRef)).valueOrNull?.length;

    final Widget tabContent = switch (_tab) {
      0 => CommentsList(taskRef: _taskRef),
      1 => ActivityList(taskRef: _taskRef),
      _ => AttachmentsList(taskRef: _taskRef),
    };

    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          color: TF.brand,
          backgroundColor: TF.bgElevated,
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                sliver: SliverList.list(children: [
                  _Header(
                    task: task,
                    onRename: (title) => _patch(
                        {'title': title}, (t) => t.copyFull(title: title)),
                  ),
                  const SizedBox(height: 18),
                  TaskFields(task: task, taskRef: _taskRef)
                      .animate()
                      .fadeIn(duration: 300.ms, delay: 60.ms)
                      .slideY(begin: 0.04, end: 0, curve: TF.ease),
                  const SizedBox(height: 26),
                  DescriptionEditor(
                    description: task.description,
                    onSave: (v) => _patch(
                        {'description': v}, (t) => t.copyFull(description: v)),
                  ).animate().fadeIn(duration: 300.ms, delay: 120.ms),
                  const SizedBox(height: 28),
                  SubtaskList(taskRef: _taskRef, subtasks: task.subtasks)
                      .animate()
                      .fadeIn(duration: 300.ms, delay: 180.ms),
                  const SizedBox(height: 28),
                ]),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                    controller: _tabs,
                    commentCount: commentCount,
                    fileCount: fileCount),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                sliver: SliverToBoxAdapter(
                  child: AnimatedSwitcher(
                    duration: TF.dur,
                    switchInCurve: TF.ease,
                    switchOutCurve: TF.ease,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, if (current != null) current],
                    ),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(
                                begin: const Offset(0, 0.02), end: Offset.zero)
                            .animate(a),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(key: ValueKey(_tab), child: tabContent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      AnimatedSize(
        duration: TF.dur,
        curve: TF.ease,
        child: _tab == 0
            ? CommentComposer(taskRef: _taskRef, onSent: _scrollToBottomSoon)
            : const SizedBox(width: double.infinity),
      ),
    ]).animate().fadeIn(duration: 220.ms);
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.task, required this.onRename});
  final Task task;
  final ValueChanged<String> onRename;

  @override
  Widget build(BuildContext context) {
    final status = task.status;
    final meta = [
      if (task.createdAt != null) 'Created ${Fmt.short(task.createdAt)}',
      if (task.updatedAt != null) 'updated ${Fmt.relative(task.updatedAt)}',
    ].join(' · ');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (task.referenceLabel != null)
              TFBadge(task.referenceLabel!, color: TF.brand),
            AnimatedSwitcher(
              duration: TF.dur,
              child: status == null
                  ? const SizedBox.shrink(key: ValueKey('no-status'))
                  : TFBadge(status.name,
                      key: ValueKey(status.id),
                      color: TF.hex(status.color),
                      dot: true),
            ),
            AnimatedSwitcher(
              duration: TF.dur,
              child:
                  TFBadge.priority(task.priority, key: ValueKey(task.priority)),
            ),
            if (task.isOverdue) const TFBadge('Overdue', color: TF.danger),
          ]),
      const SizedBox(height: 12),
      InlineTitle(taskId: task.id, title: task.title, onSave: onRename),
      if (meta.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(meta, style: TFText.mono(size: 11)),
      ],
    ]);
  }
}

// ── Tabs ──────────────────────────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(
      {required this.controller,
      required this.commentCount,
      required this.fileCount});
  final TabController controller;
  final int commentCount;
  final int? fileCount;

  static const _height = 48.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  Widget _tab(String label, int? count) {
    return Tab(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (count != null && count > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: TF.brandLight,
              borderRadius: BorderRadius.circular(TF.radiusSm),
              border: Border.all(color: TF.borderBrand.withValues(alpha: 0.3)),
            ),
            child: Text('$count',
                style: TFText.mono(
                    size: 10, weight: FontWeight.w700, color: TF.brand)),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        color: TF.bgBase,
        boxShadow: overlapsContent || shrinkOffset > 0
            ? const [
                BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 10,
                    offset: Offset(0, 4))
              ]
            : null,
      ),
      child: TabBar(
        controller: controller,
        indicatorSize: TabBarIndicatorSize.tab,
        tabs: [
          _tab('Comments', commentCount),
          _tab('Activity', null),
          _tab('Files', fileCount),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate old) =>
      old.controller != controller ||
      old.commentCount != commentCount ||
      old.fileCount != fileCount;
}

// ── Loading ───────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.taskId});
  final String taskId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        const Row(children: [
          Skeleton(width: 72, height: 20),
          SizedBox(width: 6),
          Skeleton(width: 88, height: 20),
          SizedBox(width: 6),
          Skeleton(width: 64, height: 20),
        ]),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Hero(
            tag: 'task-$taskId',
            flightShuttleBuilder: taskHeroShuttle,
            child: const Material(
              type: MaterialType.transparency,
              child: Skeleton(width: 260, height: 26),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Skeleton(width: 160, height: 11),
        const SizedBox(height: 22),
        const Skeleton(height: 340, radius: TF.radiusLg),
        const SizedBox(height: 24),
        const Skeleton(height: 96, radius: TF.radiusLg),
        const SizedBox(height: 24),
        const Skeleton(height: 44),
        const SizedBox(height: 8),
        const Skeleton(height: 44),
      ],
    );
  }
}
