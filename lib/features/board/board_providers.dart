import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/repository.dart';

/// Server-state for the project board dashboard (the Riverpod equivalents of
/// the web's `useProject`, `useStatuses`, `useTasks`, `useLabels`,
/// `useProjectAnalytics`, `useProjectTimeline` and `useProjectActivity`).

// ── Keys ──────────────────────────────────────────────────────────────────────

/// Identifies one project board: org slug + project id.
@immutable
class BoardKey {
  const BoardKey(this.slug, this.projectId);
  final String slug;
  final String projectId;

  @override
  bool operator ==(Object other) =>
      other is BoardKey && other.slug == slug && other.projectId == projectId;

  @override
  int get hashCode => Object.hash(slug, projectId);

  @override
  String toString() => 'BoardKey($slug, $projectId)';
}

const _unset = Object();

/// Board filters (web `BoardToolbar`): search, priority, assignee, label.
@immutable
class BoardFilters {
  const BoardFilters(
      {this.search = '', this.priority, this.assigneeId, this.labelId});

  final String search;
  final String? priority;

  /// User id (tasks are filtered by `assignees__id`).
  final String? assigneeId;
  final String? labelId;

  bool get isEmpty =>
      search.trim().isEmpty &&
      priority == null &&
      assigneeId == null &&
      labelId == null;

  int get activeCount =>
      (search.trim().isNotEmpty ? 1 : 0) +
      (priority != null ? 1 : 0) +
      (assigneeId != null ? 1 : 0) +
      (labelId != null ? 1 : 0);

  BoardFilters copyWith(
          {String? search,
          Object? priority = _unset,
          Object? assigneeId = _unset,
          Object? labelId = _unset}) =>
      BoardFilters(
        search: search ?? this.search,
        priority:
            identical(priority, _unset) ? this.priority : priority as String?,
        assigneeId: identical(assigneeId, _unset)
            ? this.assigneeId
            : assigneeId as String?,
        labelId: identical(labelId, _unset) ? this.labelId : labelId as String?,
      );

  Map<String, dynamic> toQuery() => {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (priority != null) 'priority': priority,
        if (assigneeId != null) 'assignee': assigneeId,
        if (labelId != null) 'label': labelId,
      };

  @override
  bool operator ==(Object other) =>
      other is BoardFilters &&
      other.search == search &&
      other.priority == priority &&
      other.assigneeId == assigneeId &&
      other.labelId == labelId;

  @override
  int get hashCode => Object.hash(search, priority, assigneeId, labelId);
}

/// Key for the tasks query: board + filters.
@immutable
class BoardQuery {
  const BoardQuery(this.key, this.filters);
  final BoardKey key;
  final BoardFilters filters;

  @override
  bool operator ==(Object other) =>
      other is BoardQuery && other.key == key && other.filters == filters;

  @override
  int get hashCode => Object.hash(key, filters);
}

// ── Simple fetchers ───────────────────────────────────────────────────────────

final projectDetailProvider =
    FutureProvider.autoDispose.family<Project, BoardKey>(
  (ref, k) => ref.watch(repositoryProvider).project(k.slug, k.projectId),
);

final boardStatusesProvider =
    FutureProvider.autoDispose.family<List<TaskStatus>, BoardKey>(
  (ref, k) => ref.watch(repositoryProvider).statuses(k.slug, k.projectId),
);

final labelsProvider = FutureProvider.autoDispose.family<List<Label>, BoardKey>(
  (ref, k) => ref.watch(repositoryProvider).labels(k.slug, k.projectId),
);

final boardFiltersProvider = StateProvider.autoDispose
    .family<BoardFilters, BoardKey>((ref, k) => const BoardFilters());

final boardTasksProvider =
    FutureProvider.autoDispose.family<List<Task>, BoardQuery>(
  (ref, q) => ref
      .watch(repositoryProvider)
      .tasks(q.key.slug, q.key.projectId, filters: q.filters.toQuery()),
);

final projectActivityProvider =
    FutureProvider.autoDispose.family<List<ActivityEntry>, BoardKey>(
  (ref, k) => ref
      .watch(repositoryProvider)
      .projectActivity(k.slug, k.projectId, limit: 50),
);

// ── Analytics ─────────────────────────────────────────────────────────────────

class VelocityPoint {
  VelocityPoint(
      {required this.weekLabel,
      this.weekStart,
      this.completed = 0,
      this.planned = 0});
  final String weekLabel;
  final DateTime? weekStart;
  final int completed;
  final int planned;
}

class PriorityShare {
  PriorityShare({required this.priority, this.count = 0, this.percent = 0});
  final String priority;
  final int count;
  final double percent;
}

class ProjectAnalytics {
  ProjectAnalytics({this.velocity = const [], this.distribution = const []});
  final List<VelocityPoint> velocity;
  final List<PriorityShare> distribution;

  int get totalTasks => distribution.fold(0, (a, b) => a + b.count);
  int get completedInWindow => velocity.fold(0, (a, b) => a + b.completed);

  static int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  factory ProjectAnalytics.fromJson(dynamic data) {
    if (data is! Map) return ProjectAnalytics();
    final vel = data['velocity'] is List ? data['velocity'] as List : const [];
    final dist =
        data['distribution'] is List ? data['distribution'] as List : const [];
    return ProjectAnalytics(
      velocity: [
        for (final v in vel.whereType<Map>())
          VelocityPoint(
            weekLabel: '${v['week_label'] ?? ''}',
            weekStart: v['week_start'] == null
                ? null
                : DateTime.tryParse('${v['week_start']}'),
            completed: _int(v['completed_count']),
            planned: _int(v['planned_count']),
          ),
      ],
      distribution: [
        for (final d in dist.whereType<Map>())
          PriorityShare(
            priority: '${d['priority'] ?? 'medium'}',
            count: _int(d['count']),
            percent: d['percent'] is num
                ? (d['percent'] as num).toDouble()
                : double.tryParse('${d['percent']}') ?? 0,
          ),
      ],
    );
  }
}

final analyticsProvider = FutureProvider.autoDispose
    .family<ProjectAnalytics, BoardKey>((ref, k) async {
  final data =
      await ref.watch(repositoryProvider).analytics(k.slug, k.projectId);
  return ProjectAnalytics.fromJson(data);
});

// ── Timeline ──────────────────────────────────────────────────────────────────

class TimelineItem {
  TimelineItem({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.referenceLabel,
    this.priority = 'medium',
    this.progressPercent = 0,
    this.statusName,
    this.statusColor,
    this.isTerminal = false,
    this.assignees = const [],
  });

  final String id;
  final String title;
  final String? referenceLabel;
  final DateTime start;
  final DateTime end;
  final String priority;
  final int progressPercent;
  final String? statusName;
  final String? statusColor;
  final bool isTerminal;
  final List<UserSummary> assignees;

  static DateTime? _date(dynamic v) {
    final d = v == null ? null : DateTime.tryParse('$v');
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  static TimelineItem? tryParse(Map<String, dynamic> j) {
    final start = _date(j['start_date']);
    final end = _date(j['end_date'] ?? j['due_date']);
    if (start == null || end == null) return null;
    final status = j['status'] is Map
        ? Map<String, dynamic>.from(j['status'] as Map)
        : null;
    final assignees = j['assignees'] is List
        ? (j['assignees'] as List)
            .whereType<Map>()
            .map((m) => UserSummary.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : <UserSummary>[];
    final p = j['progress_percent'];
    return TimelineItem(
      id: '${j['id']}',
      title: '${j['title'] ?? ''}',
      referenceLabel: j['reference_label']?.toString(),
      start: start,
      end: end.isBefore(start) ? start : end,
      priority: '${j['priority'] ?? 'medium'}',
      progressPercent: p is num ? p.toInt() : int.tryParse('$p') ?? 0,
      statusName: status?['name']?.toString(),
      statusColor: status?['color']?.toString(),
      isTerminal: status?['is_terminal'] == true,
      assignees: assignees,
    );
  }
}

final timelineProvider = FutureProvider.autoDispose
    .family<List<TimelineItem>, BoardKey>((ref, k) async {
  final data =
      await ref.watch(repositoryProvider).timeline(k.slug, k.projectId);
  final raw = data is Map && data['results'] is List
      ? data['results'] as List
      : (data is List ? data : const []);
  final out = <TimelineItem>[];
  for (final m in raw.whereType<Map>()) {
    final item = TimelineItem.tryParse(Map<String, dynamic>.from(m));
    if (item != null) out.add(item);
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
});

// ── Board state (optimistic moves) ────────────────────────────────────────────

/// Owns the board's task list. Re-fetches when filters change; supports
/// optimistic moves that revert on failure.
class BoardController
    extends AutoDisposeFamilyAsyncNotifier<List<Task>, BoardKey> {
  @override
  Future<List<Task>> build(BoardKey arg) async {
    final filters = ref.watch(boardFiltersProvider(arg));
    return ref.watch(boardTasksProvider(BoardQuery(arg, filters)).future);
  }

  TaskForgeRepository get _repo => ref.read(repositoryProvider);

  static int midOrder(int? before, int? after) {
    final lo = before ?? 0;
    final hi = after ?? lo + 2000;
    final mid = ((lo + hi) / 2).round();
    return mid < 0 ? 0 : mid;
  }

  /// Tasks of one column sorted by `order`.
  static List<Task> columnOf(List<Task> tasks, String statusId) =>
      tasks.where((t) => t.statusId == statusId).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  /// Moves [taskId] into [toStatusId], placed before [beforeTaskId] (or at
  /// the end when null). Optimistic: the UI updates immediately; on error the
  /// previous state is restored and the error rethrown.
  Future<void> moveTask(String taskId, String toStatusId,
      {String? beforeTaskId}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    Task? task;
    for (final t in current) {
      if (t.id == taskId) task = t;
    }
    if (task == null) return;

    final column =
        columnOf(current, toStatusId).where((t) => t.id != taskId).toList();
    var idx = beforeTaskId == null
        ? column.length
        : column.indexWhere((t) => t.id == beforeTaskId);
    if (idx < 0) idx = column.length;
    final before = idx > 0 ? column[idx - 1].order : null;
    final after = idx < column.length ? column[idx].order : null;
    final newOrder = midOrder(before, after);

    if (task.statusId == toStatusId) {
      // No-op when dropping onto the same slot.
      final sameCol = columnOf(current, toStatusId);
      final oldIdx = sameCol.indexWhere((t) => t.id == taskId);
      final nextId =
          oldIdx + 1 < sameCol.length ? sameCol[oldIdx + 1].id : null;
      if (nextId == beforeTaskId) return;
    }

    final previous = current;
    state = AsyncData([
      for (final t in current)
        t.id == taskId ? t.copyWith(statusId: toStatusId, order: newOrder) : t,
    ]);
    try {
      await _repo.moveTask(arg.slug, arg.projectId, taskId,
          statusId: toStatusId, order: newOrder);
      ref.invalidate(projectDetailProvider(arg));
    } catch (e) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  void addTask(Task task) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.any((t) => t.id == task.id)) return;
    state = AsyncData([...current, task]);
  }

  void upsertTask(Task task) {
    final current = state.valueOrNull;
    if (current == null) return;
    final exists = current.any((t) => t.id == task.id);
    state = AsyncData(exists
        ? [for (final t in current) t.id == task.id ? task : t]
        : [...current, task]);
  }

  void removeTask(String id) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.where((t) => t.id != id).toList());
  }

  /// Applies a realtime board event (`task.created|updated|moved|deleted`).
  /// Returns false when the event could not be applied locally (caller should
  /// re-fetch instead).
  bool applyRemote(String type, Map<String, dynamic>? json) {
    if (json == null) return false;
    final filtersActive = !ref.read(boardFiltersProvider(arg)).isEmpty;
    final task = Task.fromJson(json);
    switch (type) {
      case 'task.created':
        if (filtersActive) return false;
        addTask(task);
        return true;
      case 'task.updated':
      case 'task.moved':
        // Without the computed subtask pair we'd wipe the card's progress.
        if (filtersActive || !json.containsKey('subtask_total')) return false;
        upsertTask(task);
        return true;
      case 'task.deleted':
        removeTask(task.id);
        return true;
      default:
        return false;
    }
  }
}

final boardControllerProvider = AsyncNotifierProvider.autoDispose
    .family<BoardController, List<Task>, BoardKey>(BoardController.new);

/// Refreshes every board-related query (pull-to-refresh, after detail pops).
void refreshBoard(WidgetRef ref, BoardKey key) {
  ref.invalidate(projectDetailProvider(key));
  ref.invalidate(boardStatusesProvider(key));
  ref.invalidate(labelsProvider(key));
  ref.invalidate(boardTasksProvider);
  ref.invalidate(analyticsProvider(key));
  ref.invalidate(timelineProvider(key));
  ref.invalidate(projectActivityProvider(key));
}
