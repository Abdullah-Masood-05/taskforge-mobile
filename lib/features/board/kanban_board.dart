import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/widgets.dart';
import 'board_providers.dart';
import 'board_widgets.dart';
import 'task_card.dart';

/// Mobile Kanban (web `KanbanBoard` + `KanbanColumn`): one column per page
/// with a peek of the neighbours. Long-press a card to drag it to another
/// column (the board pages automatically when dragging near the edges), or
/// use the card menu's "Move to…" sheet.
class KanbanBoard extends StatefulWidget {
  const KanbanBoard({
    super.key,
    required this.statuses,
    required this.tasks,
    required this.onOpenTask,
    required this.onMove,
    required this.onAddTask,
    required this.onRefresh,
    this.onAddColumn,
    this.onPageChanged,
  });

  final List<TaskStatus> statuses;
  final List<Task> tasks;
  final ValueChanged<Task> onOpenTask;

  /// Move [task] into [statusId], before [beforeTaskId] (null = end).
  final void Function(Task task, String statusId, String? beforeTaskId) onMove;
  final ValueChanged<String> onAddTask;
  final Future<void> Function() onRefresh;
  final VoidCallback? onAddColumn;

  /// Reports the status id of the column in view (null on the "add" page).
  final ValueChanged<String?>? onPageChanged;

  @override
  State<KanbanBoard> createState() => _KanbanBoardState();
}

class _KanbanBoardState extends State<KanbanBoard> {
  final _pages = PageController(viewportFraction: 0.86);
  final _chipScroll = ScrollController();
  int _page = 0;
  bool _dragging = false;
  String? _hoverStatus;
  Timer? _edgeTimer;
  int _edgeDir = 0;

  /// "statusId/taskId" pairs already rendered — new ones animate in.
  final _seen = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void didUpdateWidget(covariant KanbanBoard old) {
    super.didUpdateWidget(old);
    final max = widget.statuses.length; // last index is the add page
    if (_page > max) {
      _page = max;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pages.hasClients) _pages.jumpToPage(_page);
      });
    }
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
    _pages.dispose();
    _chipScroll.dispose();
    super.dispose();
  }

  void _report() {
    final cb = widget.onPageChanged;
    if (cb == null) return;
    cb(_page < widget.statuses.length ? widget.statuses[_page].id : null);
  }

  void _goTo(int page) {
    if (!_pages.hasClients) return;
    _pages.animateToPage(page, duration: TF.durSlow, curve: TF.ease);
  }

  // ── Drag helpers ────────────────────────────────────────────────────────────

  void _onPointerMove(PointerMoveEvent e) {
    if (!_dragging) return;
    final width = MediaQuery.sizeOf(context).width;
    final x = e.position.dx;
    const edge = 36.0;
    final dir = x < edge ? -1 : (x > width - edge ? 1 : 0);
    if (dir == _edgeDir) return;
    _edgeDir = dir;
    _edgeTimer?.cancel();
    _edgeTimer = null;
    if (dir != 0) {
      _edgeTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
        final target = _page + _edgeDir;
        if (target < 0 || target >= widget.statuses.length) return;
        HapticFeedback.selectionClick();
        _goTo(target);
      });
    }
  }

  void _endDrag() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _edgeDir = 0;
    if (mounted) {
      setState(() {
        _dragging = false;
        _hoverStatus = null;
      });
    }
  }

  void _setHover(String? statusId) {
    if (_hoverStatus != statusId) setState(() => _hoverStatus = statusId);
  }

  void _drop(Task task, String statusId, String? beforeTaskId) {
    HapticFeedback.mediumImpact();
    _endDrag();
    widget.onMove(task, statusId, beforeTaskId);
  }

  // ── Move-to sheet ───────────────────────────────────────────────────────────

  Future<void> _showCardMenu(Task task) async {
    final result = await showTFSheet<String>(
      context,
      builder: (ctx) => _CardMenuSheet(task: task, statuses: widget.statuses),
    );
    if (result == null || !mounted) return;
    if (result == '__open__') {
      widget.onOpenTask(task);
      return;
    }
    if (result == task.statusId) return;
    widget.onMove(task, result, null);
    final idx = widget.statuses.indexWhere((s) => s.id == result);
    if (idx >= 0) _goTo(idx);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final columns = <String, List<Task>>{
      for (final s in widget.statuses)
        s.id: BoardController.columnOf(widget.tasks, s.id),
    };
    final pageCount =
        widget.statuses.length + (widget.onAddColumn != null ? 1 : 0);

    // A Listener sees every move of the dragging pointer (even if the source
    // column scrolls away), which drives edge auto-paging.
    return Listener(
      onPointerMove: _onPointerMove,
      child: Column(children: [
        _ColumnStrip(
          statuses: widget.statuses,
          counts: {for (final e in columns.entries) e.key: e.value.length},
          current: _page,
          hover: _hoverStatus,
          controller: _chipScroll,
          onTap: _goTo,
        ),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: pageCount,
            padEnds: false,
            onPageChanged: (p) {
              setState(() => _page = p);
              _report();
            },
            itemBuilder: (context, i) {
              if (i >= widget.statuses.length) {
                return _AddColumnPage(onTap: widget.onAddColumn!);
              }
              final status = widget.statuses[i];
              return _KeepAlive(
                key: ValueKey('col-${status.id}'),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 6, 4, 6, 12),
                  child: _buildColumn(status, columns[status.id] ?? const []),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildColumn(TaskStatus status, List<Task> tasks) {
    final color = TF.hex(status.color);
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => true,
      onMove: (_) => _setHover(status.id),
      onLeave: (_) {
        if (_hoverStatus == status.id) _setHover(null);
      },
      onAcceptWithDetails: (d) => _drop(d.data, status.id, null),
      builder: (context, candidate, rejected) {
        final active =
            candidate.isNotEmpty || (_dragging && _hoverStatus == status.id);
        return AnimatedContainer(
          duration: TF.dur,
          curve: TF.ease,
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.05) : TF.bgBase,
            borderRadius: BorderRadius.circular(TF.radiusLg),
            border: Border.all(
                color:
                    active ? color.withValues(alpha: 0.55) : TF.borderSubtle),
          ),
          child: Column(children: [
            _ColumnHeader(
                status: status,
                count: tasks.length,
                onAdd: () => widget.onAddTask(status.id)),
            const Divider(height: 1),
            Expanded(
              child: tasks.isEmpty
                  ? _EmptyColumn(
                      dragging: _dragging,
                      color: color,
                      onAdd: () => widget.onAddTask(status.id))
                  : RefreshIndicator(
                      color: TF.brand,
                      backgroundColor: TF.bgElevated,
                      onRefresh: widget.onRefresh,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics()),
                        padding: EdgeInsets.fromLTRB(
                            10, 10, 10, _dragging ? 140 : 96),
                        itemCount: tasks.length,
                        itemBuilder: (context, idx) =>
                            _buildCard(status, tasks[idx], idx),
                      ),
                    ),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildCard(TaskStatus status, Task task, int index) {
    final seenKey = '${status.id}/${task.id}';
    final isNew = !_seen.contains(seenKey);
    _seen.add(seenKey);

    final card = KanbanCard(
      task: task,
      onTap: () => widget.onOpenTask(task),
      onMenu: () => _showCardMenu(task),
    );

    final dragSource = LayoutBuilder(
      builder: (context, constraints) => LongPressDraggable<Task>(
        data: task,
        delay: const Duration(milliseconds: 280),
        hapticFeedbackOnStart: true,
        onDragStarted: () => setState(() => _dragging = true),
        onDragEnd: (_) => _endDrag(),
        onDraggableCanceled: (_, __) => _endDrag(),
        feedback: SizedBox(
          width: constraints.maxWidth,
          child: Material(
            type: MaterialType.transparency,
            child: Transform.rotate(
              angle: 0.035,
              child: KanbanCard(task: task, heroEnabled: false, lifted: true),
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.25,
          child: KanbanCard(task: task, heroEnabled: false),
        ),
        child: card,
      ),
    );

    // Each card is also a drop target: dropping inserts above it.
    final draggable = DragTarget<Task>(
      onWillAcceptWithDetails: (d) => d.data.id != task.id,
      onMove: (_) => _setHover(status.id),
      onAcceptWithDetails: (d) => _drop(d.data, status.id, task.id),
      builder: (context, candidate, _) {
        final over = candidate.isNotEmpty;
        return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: TF.durFast,
                curve: TF.ease,
                height: over ? 44 : 0,
                margin: EdgeInsets.only(bottom: over ? 8 : 0),
                decoration: BoxDecoration(
                  color: TF.brandLight,
                  borderRadius: BorderRadius.circular(TF.radiusMd),
                  border: Border.all(
                      color: over ? TF.borderBrand : Colors.transparent),
                ),
              ),
              dragSource,
            ]);
      },
    );

    // Same widget structure for new and existing cards (so a rebuild during
    // a drag never remounts the draggable); only new cards animate in.
    final delay = index.clamp(0, 8) * 45;
    const dur = 320;
    return TweenAnimationBuilder<double>(
      key: ValueKey(seenKey),
      tween: Tween(begin: isNew ? 0.0 : 1.0, end: 1.0),
      duration: Duration(milliseconds: dur + delay),
      curve: Interval(delay / (dur + delay), 1, curve: TF.ease),
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child:
            Transform.translate(offset: Offset(0, (1 - v) * 16), child: child),
      ),
      child:
          Padding(padding: const EdgeInsets.only(bottom: 8), child: draggable),
    );
  }
}

/// Keeps every column mounted so drags and scroll offsets survive paging.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({super.key, required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ── Column pieces ─────────────────────────────────────────────────────────────

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader(
      {required this.status, required this.count, required this.onAdd});
  final TaskStatus status;
  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(children: [
        ColorDot(TF.hex(status.color), glow: true),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            status.name.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TFText.mono(
                size: 12,
                weight: FontWeight.w600,
                color: TF.textPrimary,
                letterSpacing: 1.4),
          ),
        ),
        const SizedBox(width: 8),
        AnimatedSwitcher(
          duration: TF.dur,
          transitionBuilder: (c, a) => ScaleTransition(
              scale: a, child: FadeTransition(opacity: a, child: c)),
          child: Container(
            key: ValueKey(count),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: TF.bgElevated,
              borderRadius: BorderRadius.circular(TF.radiusSm),
              border: Border.all(color: TF.borderDefault),
            ),
            child: Text('$count',
                style: TFText.mono(size: 11, color: TF.textSecondary)),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Add task',
          visualDensity: VisualDensity.compact,
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 19, color: TF.textMuted),
        ),
      ]),
    );
  }
}

class _EmptyColumn extends StatelessWidget {
  const _EmptyColumn(
      {required this.dragging, required this.color, required this.onAdd});
  final bool dragging;
  final Color color;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Pressable(
        onTap: dragging ? null : onAdd,
        child: AnimatedContainer(
          duration: TF.dur,
          height: 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TF.radiusLg),
            border: Border.all(
                color:
                    dragging ? color.withValues(alpha: 0.5) : TF.borderDefault),
            color:
                dragging ? color.withValues(alpha: 0.04) : Colors.transparent,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(dragging ? Icons.move_down_rounded : Icons.add_rounded,
                size: 20, color: TF.textMuted),
            const SizedBox(height: 6),
            Text(dragging ? 'Drop here' : 'No tasks yet',
                style: TFText.small()),
          ]),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _AddColumnPage extends StatelessWidget {
  const _AddColumnPage({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 16, 12),
      child: Align(
        alignment: Alignment.topCenter,
        child: Pressable(
          onTap: onTap,
          child: Container(
            height: 120,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TF.radiusLg),
              border: Border.all(color: TF.borderDefault),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.view_column_outlined, color: TF.brand, size: 22),
              const SizedBox(height: 8),
              Text('Add column',
                  style: TFText.sans(size: 14, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('New workflow stage', style: TFText.small()),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Horizontal strip of column chips synced with the page view.
class _ColumnStrip extends StatefulWidget {
  const _ColumnStrip({
    required this.statuses,
    required this.counts,
    required this.current,
    required this.hover,
    required this.controller,
    required this.onTap,
  });

  final List<TaskStatus> statuses;
  final Map<String, int> counts;
  final int current;
  final String? hover;
  final ScrollController controller;
  final ValueChanged<int> onTap;

  @override
  State<_ColumnStrip> createState() => _ColumnStripState();
}

class _ColumnStripState extends State<_ColumnStrip> {
  final _keys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(covariant _ColumnStrip old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current &&
        widget.current < widget.statuses.length) {
      final key = _keys[widget.statuses[widget.current].id];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = key?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              duration: TF.dur, curve: TF.ease, alignment: 0.5);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        controller: widget.controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        itemCount: widget.statuses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final s = widget.statuses[i];
          final selected = i == widget.current;
          final hovered = widget.hover == s.id;
          final color = TF.hex(s.color);
          return GestureDetector(
            key: _keys.putIfAbsent(s.id, () => GlobalKey()),
            onTap: () => widget.onTap(i),
            child: AnimatedContainer(
              duration: TF.dur,
              curve: TF.ease,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected || hovered
                    ? color.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(TF.radiusMd),
                border: Border.all(
                  color: hovered
                      ? color
                      : (selected
                          ? color.withValues(alpha: 0.45)
                          : TF.borderSubtle),
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ColorDot(color, size: 6),
                const SizedBox(width: 6),
                Text(
                  s.name,
                  style: TFText.sans(
                    size: 12.5,
                    weight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? TF.textPrimary : TF.textMuted,
                  ),
                ),
                const SizedBox(width: 6),
                Text('${widget.counts[s.id] ?? 0}',
                    style: TFText.mono(size: 10.5, color: TF.textMuted)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ── Card menu ─────────────────────────────────────────────────────────────────

class _CardMenuSheet extends StatelessWidget {
  const _CardMenuSheet({required this.task, required this.statuses});
  final Task task;
  final List<TaskStatus> statuses;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(task.referenceLabel ?? 'TASK',
                  style: TFText.eyebrow(color: TF.brand)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TFText.h3()),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_full_rounded, size: 19),
              title: Text('Open task', style: TFText.sans(size: 14.5)),
              onTap: () => Navigator.pop(context, '__open__'),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text('MOVE TO', style: TFText.eyebrow()),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final (i, s) in statuses.indexed)
                    ListTile(
                      leading: ColorDot(TF.hex(s.color),
                          size: 10, glow: s.id == task.statusId),
                      title: Text(s.name, style: TFText.sans(size: 14.5)),
                      trailing: s.id == task.statusId
                          ? Text('CURRENT',
                              style: TFText.mono(
                                  size: 10,
                                  color: TF.brand,
                                  letterSpacing: 1.2))
                          : const Icon(Icons.arrow_forward_rounded,
                              size: 16, color: TF.textMuted),
                      enabled: s.id != task.statusId,
                      onTap: () => Navigator.pop(context, s.id),
                    )
                        .animate()
                        .fadeIn(delay: (i * 30).ms, duration: 220.ms)
                        .slideX(begin: 0.04, end: 0),
                ],
              ),
            ),
          ]),
    );
  }
}
