import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

/// Identifies one task (family key for every task-detail provider).
typedef TaskRef = ({String slug, String projectId, String taskId});

/// Identifies one project inside an org.
typedef ProjectRef = ({String slug, String projectId});

/// Temp ids for optimistic rows that the server has not confirmed yet.
const _tmpPrefix = 'tmp-';
String _tmpId() => '$_tmpPrefix${DateTime.now().microsecondsSinceEpoch}';
bool isPendingId(String id) => id.startsWith(_tmpPrefix);
int _insertAt(int index, int length) =>
    index < 0 || index > length ? length : index;

/// Full copy of a [Task] (the model's own `copyWith` only covers board
/// fields). Nullable fields take a thunk so they can be explicitly cleared:
/// `copyFull(dueDate: () => null)`.
extension TaskCopyX on Task {
  Task copyFull({
    String? title,
    String? description,
    String? priority,
    String? Function()? statusId,
    TaskStatus? Function()? status,
    List<UserSummary>? assignees,
    List<Label>? labels,
    DateTime? Function()? startDate,
    DateTime? Function()? dueDate,
    int? progressPercent,
    List<SubTask>? subtasks,
  }) {
    final subs = subtasks ?? this.subtasks;
    return Task(
      id: id,
      title: title ?? this.title,
      referenceLabel: referenceLabel,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      statusId: statusId != null ? statusId() : this.statusId,
      status: status != null ? status() : this.status,
      assignees: assignees ?? this.assignees,
      labels: labels ?? this.labels,
      startDate: startDate != null ? startDate() : this.startDate,
      dueDate: dueDate != null ? dueDate() : this.dueDate,
      progressPercent: progressPercent ?? this.progressPercent,
      order: order,
      subtaskTotal: subtasks != null ? subs.length : subtaskTotal,
      subtaskDone: subtasks != null
          ? subs.where((s) => s.completed).length
          : subtaskDone,
      subtasks: subs,
      comments: comments,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

// ── Task detail ───────────────────────────────────────────────────────────────

/// Full task (detail serializer: description, subtasks, comments) with
/// optimistic mutations. Every mutation applies locally first, then reverts
/// and rethrows if the server rejects it — callers show the toast.
class TaskDetailNotifier extends AutoDisposeFamilyAsyncNotifier<Task, TaskRef> {
  bool _alive = true;
  int _mutation = 0;

  TaskForgeRepository get _repo => ref.read(repositoryProvider);

  @override
  Future<Task> build(TaskRef arg) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    return ref
        .watch(repositoryProvider)
        .task(arg.slug, arg.projectId, arg.taskId);
  }

  Task? get _current => state.valueOrNull;

  void _set(Task t) {
    if (_alive) state = AsyncData(t);
  }

  void _touchActivity() {
    if (_alive) ref.invalidate(taskActivityProvider(arg));
  }

  /// PATCHes [data]; [optimistic] produces the locally-updated task.
  Future<void> patch(Map<String, dynamic> data,
      {Task Function(Task t)? optimistic}) async {
    final before = _current;
    if (before == null) return;
    final id = ++_mutation;
    if (optimistic != null) _set(optimistic(before));
    try {
      final updated =
          await _repo.updateTask(arg.slug, arg.projectId, arg.taskId, data);
      // Only adopt the server copy if no newer edit started meanwhile; keep
      // the local subtask list (it may contain in-flight optimistic rows).
      if (id == _mutation) {
        final local = _current;
        _set(local == null
            ? updated
            : updated.copyFull(subtasks: local.subtasks));
      }
      _touchActivity();
    } catch (_) {
      if (id == _mutation) _set(before);
      rethrow;
    }
  }

  // Subtasks ------------------------------------------------------------------

  void _mapSubtasks(List<SubTask> Function(List<SubTask> list) f) {
    final t = _current;
    if (t == null) return;
    _set(t.copyFull(subtasks: f(List<SubTask>.of(t.subtasks))));
  }

  Future<void> addSubtask(String title) async {
    final temp = SubTask(
        id: _tmpId(), title: title, order: 1 << 30, createdAt: DateTime.now());
    _mapSubtasks((l) => l..add(temp));
    try {
      final created = await _repo.createSubtask(arg.slug, arg.taskId, title);
      _mapSubtasks((l) => l.map((s) => s.id == temp.id ? created : s).toList());
    } catch (_) {
      _mapSubtasks((l) => l..removeWhere((s) => s.id == temp.id));
      rethrow;
    }
  }

  Future<void> toggleSubtask(SubTask sub) async {
    if (isPendingId(sub.id)) return;
    final next = !sub.completed;
    _mapSubtasks((l) => l
        .map((s) => s.id == sub.id ? s.copyWith(completed: next) : s)
        .toList());
    try {
      await _repo
          .updateSubtask(arg.slug, arg.taskId, sub.id, {'completed': next});
    } catch (_) {
      _mapSubtasks((l) => l
          .map((s) => s.id == sub.id ? s.copyWith(completed: !next) : s)
          .toList());
      rethrow;
    }
  }

  Future<void> renameSubtask(SubTask sub, String title) async {
    if (isPendingId(sub.id) || title == sub.title) return;
    final old = sub.title;
    _mapSubtasks((l) =>
        l.map((s) => s.id == sub.id ? s.copyWith(title: title) : s).toList());
    try {
      await _repo.updateSubtask(arg.slug, arg.taskId, sub.id, {'title': title});
    } catch (_) {
      _mapSubtasks((l) =>
          l.map((s) => s.id == sub.id ? s.copyWith(title: old) : s).toList());
      rethrow;
    }
  }

  /// Removes synchronously (so a `Dismissible` can leave the tree), then
  /// re-inserts at the original index if the request fails.
  Future<void> deleteSubtask(SubTask sub) async {
    if (isPendingId(sub.id)) return;
    final index = _current?.subtasks.indexWhere((s) => s.id == sub.id) ?? -1;
    _mapSubtasks((l) => l..removeWhere((s) => s.id == sub.id));
    try {
      await _repo.deleteSubtask(arg.slug, arg.taskId, sub.id);
    } catch (_) {
      _mapSubtasks((l) {
        if (l.any((s) => s.id == sub.id)) return l;
        return l..insert(_insertAt(index, l.length), sub);
      });
      rethrow;
    }
  }
}

final taskDetailProvider = AsyncNotifierProvider.autoDispose
    .family<TaskDetailNotifier, Task, TaskRef>(TaskDetailNotifier.new);

// ── Comments ──────────────────────────────────────────────────────────────────

class TaskCommentsNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<Comment>, TaskRef> {
  bool _alive = true;

  TaskForgeRepository get _repo => ref.read(repositoryProvider);

  @override
  Future<List<Comment>> build(TaskRef arg) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    return ref.watch(repositoryProvider).comments(arg.slug, arg.taskId);
  }

  void _map(List<Comment> Function(List<Comment> list) f) {
    final list = state.valueOrNull;
    if (list == null || !_alive) return;
    state = AsyncData(f(List<Comment>.of(list)));
  }

  Future<void> add(String body) async {
    final me = ref.read(authProvider).user;
    final temp = Comment(
      id: _tmpId(),
      body: body,
      isOwn: true,
      createdAt: DateTime.now(),
      author: me == null
          ? null
          : UserSummary(
              id: me.id,
              email: me.email,
              fullName: me.fullName,
              avatarUrl: me.avatarUrl),
    );
    _map((l) => l..add(temp));
    try {
      final created = await _repo.addComment(arg.slug, arg.taskId, body);
      _map((l) => l.map((c) => c.id == temp.id ? created : c).toList());
    } catch (_) {
      _map((l) => l..removeWhere((c) => c.id == temp.id));
      rethrow;
    }
  }

  Future<void> delete(Comment comment) async {
    if (isPendingId(comment.id)) return;
    final index =
        state.valueOrNull?.indexWhere((c) => c.id == comment.id) ?? -1;
    _map((l) => l..removeWhere((c) => c.id == comment.id));
    try {
      await _repo.deleteComment(arg.slug, arg.taskId, comment.id);
    } catch (_) {
      _map((l) => l..insert(_insertAt(index, l.length), comment));
      rethrow;
    }
  }
}

final taskCommentsProvider = AsyncNotifierProvider.autoDispose
    .family<TaskCommentsNotifier, List<Comment>, TaskRef>(
        TaskCommentsNotifier.new);

// ── Activity ──────────────────────────────────────────────────────────────────

/// Newest first (backend orders by `-created_at`).
final taskActivityProvider =
    FutureProvider.autoDispose.family<List<ActivityEntry>, TaskRef>(
  (ref, r) => ref.watch(repositoryProvider).taskActivity(r.slug, r.taskId),
);

// ── Attachments ───────────────────────────────────────────────────────────────

class TaskAttachmentsNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<Attachment>, TaskRef> {
  bool _alive = true;

  @override
  Future<List<Attachment>> build(TaskRef arg) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    return ref.watch(repositoryProvider).attachments(arg.slug, arg.taskId);
  }

  Future<void> delete(Attachment a) async {
    final list = state.valueOrNull;
    if (list == null) return;
    final index = list.indexWhere((x) => x.id == a.id);
    state =
        AsyncData(List<Attachment>.of(list)..removeWhere((x) => x.id == a.id));
    try {
      await ref
          .read(repositoryProvider)
          .deleteAttachment(arg.slug, arg.taskId, a.id);
    } catch (_) {
      final now = state.valueOrNull;
      if (_alive && now != null && !now.any((x) => x.id == a.id)) {
        state = AsyncData(
            List<Attachment>.of(now)..insert(_insertAt(index, now.length), a));
      }
      rethrow;
    }
  }
}

final taskAttachmentsProvider = AsyncNotifierProvider.autoDispose
    .family<TaskAttachmentsNotifier, List<Attachment>, TaskRef>(
        TaskAttachmentsNotifier.new);

// ── Project lookups used by the pickers ───────────────────────────────────────

/// Kanban columns (sorted by order) for the status selector.
final taskStatusOptionsProvider =
    FutureProvider.autoDispose.family<List<TaskStatus>, ProjectRef>(
  (ref, p) => ref.watch(repositoryProvider).statuses(p.slug, p.projectId),
);

/// Project labels for the label picker.
final taskLabelOptionsProvider =
    FutureProvider.autoDispose.family<List<Label>, ProjectRef>(
  (ref, p) => ref.watch(repositoryProvider).labels(p.slug, p.projectId),
);
