import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/api_error.dart';
import 'models.dart';

/// Every endpoint the web app calls, typed for Dart. Org-scoped calls take the
/// org slug and send it as `X-Organization-Slug`, same as the web client.
class TaskForgeRepository {
  TaskForgeRepository(this._api);
  final ApiClient _api;

  // ── Auth ────────────────────────────────────────────────────────────────────

  /// Returns `{access, refresh, user}`.
  ///
  /// The sign-in form stays locked until this returns, so it gets a hard
  /// ceiling. Without one, a stalled connection keeps the form locked for
  /// minutes (receive timeout multiplied by retries).
  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await _api
        .post('/auth/login/',
            body: {'email': email, 'password': password},
            skipAuth: true,
            retry: true)
        .timeout(
          const Duration(seconds: 40),
          onTimeout: () => throw ApiError(
            status: 0,
            code: 'timeout',
            message:
                'The server did not answer in time. Check your connection and try again.',
          ),
        );
    return Map<String, dynamic>.from(data as Map);
  }

  /// Returns `{message, user, tokens: {access, refresh}}`.
  Future<Map<String, dynamic>> register({
    required String email,
    required String firstName,
    required String lastName,
    required String password,
    required String passwordConfirm,
  }) async =>
      Map<String, dynamic>.from(await _api.post('/auth/register/',
          body: {
            'email': email,
            'first_name': firstName,
            'last_name': lastName,
            'password': password,
            'password_confirm': passwordConfirm,
          },
          skipAuth: true) as Map);

  /// Blacklists [refresh] server-side. [access] is passed explicitly because
  /// sign out clears local tokens before this request is sent.
  Future<void> logout(String refresh, {String? access}) => _api.post(
        '/auth/logout/',
        body: {'refresh': refresh},
        headers: {if (access != null) 'Authorization': 'Bearer $access'},
      );

  Future<User> me() async => User.fromJson(
      Map<String, dynamic>.from(await _api.get('/auth/me/') as Map));

  Future<User> updateProfile(Map<String, dynamic> data) async =>
      User.fromJson(Map<String, dynamic>.from(
          await _api.put('/auth/me/', body: data) as Map));

  /// Returns new tokens (`{access, refresh}` possibly nested) on success.
  Future<Map<String, dynamic>> changePassword(
          {required String oldPassword,
          required String newPassword,
          required String confirm}) async =>
      Map<String, dynamic>.from(
          await _api.post('/auth/change-password/', body: {
                'old_password': oldPassword,
                'new_password': newPassword,
                'new_password_confirm': confirm,
              }) as Map? ??
              {});

  // ── Organizations ───────────────────────────────────────────────────────────

  Future<List<Organization>> orgs() async =>
      unwrapList(await _api.get('/organizations/'))
          .map(Organization.fromJson)
          .toList();

  Future<Organization> org(String slug) async =>
      Organization.fromJson(Map<String, dynamic>.from(
          await _api.get('/organizations/$slug/') as Map));

  Future<Organization> createOrg(
          {required String name,
          String description = '',
          String website = ''}) async =>
      Organization.fromJson(
          Map<String, dynamic>.from(await _api.post('/organizations/', body: {
        'name': name,
        if (description.isNotEmpty) 'description': description,
        if (website.isNotEmpty) 'website': website,
      }) as Map));

  Future<Organization> updateOrg(
          String slug, Map<String, dynamic> data) async =>
      Organization.fromJson(Map<String, dynamic>.from(
          await _api.patch('/organizations/$slug/', body: data) as Map));

  Future<void> deleteOrg(String slug) => _api.delete('/organizations/$slug/');

  Future<List<Member>> members(String slug) async =>
      unwrapList(await _api.get('/organizations/$slug/members/'))
          .map(Member.fromJson)
          .toList();

  Future<dynamic> inviteMember(String slug,
          {required String email, String role = 'member'}) =>
      _api.post('/organizations/$slug/members/',
          body: {'email': email, 'role': role});

  Future<dynamic> updateMemberRole(String slug, String memberId, String role) =>
      _api.patch('/organizations/$slug/members/$memberId/',
          body: {'role': role});

  Future<void> removeMember(String slug, String memberId) =>
      _api.delete('/organizations/$slug/members/$memberId/');

  Future<List<Invitation>> pendingInvitations(String slug) async => unwrapList(
          await _api.get('/organizations/$slug/members/pending-invitations/'))
      .map(Invitation.fromJson)
      .toList();

  // ── Billing ─────────────────────────────────────────────────────────────────

  Future<BillingStatus> billingStatus(String slug) async =>
      BillingStatus.fromJson(Map<String, dynamic>.from(
          await _api.get('/organizations/$slug/billing/status/') as Map));

  /// Returns a Stripe Checkout URL.
  Future<String?> createCheckout(String slug, String priceId) async =>
      (await _api.post('/organizations/$slug/billing/checkout/',
          body: {'price_id': priceId}) as Map?)?['url'] as String?;

  /// Returns a Stripe Customer Portal URL.
  Future<String?> openPortal(String slug) async =>
      (await _api.post('/organizations/$slug/billing/portal/') as Map?)?['url']
          as String?;

  // ── Projects ────────────────────────────────────────────────────────────────

  Future<List<Project>> projects(String org,
          {Map<String, dynamic>? query}) async =>
      unwrapList(await _api.get('/projects/',
              org: org, query: {'page_size': 100, ...?query}))
          .map(Project.fromJson)
          .toList();

  Future<Project> project(String org, String id) async =>
      Project.fromJson(Map<String, dynamic>.from(
          await _api.get('/projects/$id/', org: org) as Map));

  Future<Project> createProject(String org, Map<String, dynamic> data) async =>
      Project.fromJson(Map<String, dynamic>.from(
          await _api.post('/projects/', body: data, org: org) as Map));

  Future<Project> updateProject(
          String org, String id, Map<String, dynamic> data) async =>
      Project.fromJson(Map<String, dynamic>.from(
          await _api.patch('/projects/$id/', body: data, org: org) as Map));

  Future<void> deleteProject(String org, String id) =>
      _api.delete('/projects/$id/', org: org);

  Future<dynamic> archiveProject(String org, String id) =>
      _api.post('/projects/$id/archive/', org: org);

  /// Raw payload — see backend `ProjectTimelineView`.
  Future<dynamic> timeline(String org, String id) =>
      _api.get('/projects/$id/timeline/', org: org);

  /// Raw payload — weekly velocity + priority distribution.
  Future<dynamic> analytics(String org, String id) =>
      _api.get('/projects/$id/analytics/', org: org);

  Future<List<ActivityEntry>> projectActivity(String org, String id,
          {int limit = 20}) async =>
      unwrapList(await _api.get('/projects/$id/activity/',
              org: org, query: {'limit': limit}))
          .map(ActivityEntry.fromJson)
          .toList();

  Future<dynamic> exportProject(String org, String id) =>
      _api.get('/projects/$id/export/', org: org);

  // ── Statuses (Kanban columns) ───────────────────────────────────────────────

  Future<List<TaskStatus>> statuses(String org, String projectId) async =>
      (unwrapList(await _api.get('/projects/$projectId/statuses/', org: org))
          .map(TaskStatus.fromJson)
          .toList())
        ..sort((a, b) => a.order.compareTo(b.order));

  Future<TaskStatus> createStatus(String org, String projectId,
          {required String name, String? color}) async =>
      TaskStatus.fromJson(Map<String, dynamic>.from(await _api.post(
          '/projects/$projectId/statuses/',
          body: {'name': name, if (color != null) 'color': color},
          org: org) as Map));

  Future<dynamic> updateStatus(String org, String projectId, String statusId,
          Map<String, dynamic> data) =>
      _api.patch('/projects/$projectId/statuses/$statusId/',
          body: data, org: org);

  Future<void> deleteStatus(String org, String projectId, String statusId) =>
      _api.delete('/projects/$projectId/statuses/$statusId/', org: org);

  Future<dynamic> reorderStatuses(
          String org, String projectId, List<String> orderedIds) =>
      _api.post('/projects/$projectId/statuses/reorder/',
          body: {'ordered_ids': orderedIds}, org: org);

  // ── Labels ──────────────────────────────────────────────────────────────────

  Future<List<Label>> labels(String org, String projectId) async =>
      unwrapList(await _api.get('/projects/$projectId/labels/', org: org))
          .map(Label.fromJson)
          .toList();

  Future<Label> createLabel(String org, String projectId,
          {required String name, String? color}) async =>
      Label.fromJson(Map<String, dynamic>.from(await _api.post(
          '/projects/$projectId/labels/',
          body: {'name': name, if (color != null) 'color': color},
          org: org) as Map));

  Future<void> deleteLabel(String org, String projectId, String labelId) =>
      _api.delete('/projects/$projectId/labels/$labelId/', org: org);

  // ── Tasks ───────────────────────────────────────────────────────────────────

  /// Filters: status, assignee, priority, label, due_before, due_after, search.
  /// Follows pagination so the board has every task.
  Future<List<Task>> tasks(String org, String projectId,
      {Map<String, dynamic>? filters}) async {
    final out = <Task>[];
    dynamic data = await _api.get('/projects/$projectId/tasks/',
        org: org, query: {'page_size': 100, ...?filters});
    out.addAll(unwrapList(data).map(Task.fromJson));
    var guard = 0;
    while (data is Map && data['next'] is String && guard++ < 20) {
      data = await _api.get(data['next'] as String, org: org);
      out.addAll(unwrapList(data).map(Task.fromJson));
    }
    return out;
  }

  Future<Task> task(String org, String projectId, String taskId) async =>
      Task.fromJson(Map<String, dynamic>.from(await _api
          .get('/projects/$projectId/tasks/$taskId/', org: org) as Map));

  /// Writable: title, description, priority, status_id, assignee_ids,
  /// label_ids, start_date, due_date (yyyy-MM-dd), progress_percent.
  Future<Task> createTask(
          String org, String projectId, Map<String, dynamic> data) async =>
      Task.fromJson(Map<String, dynamic>.from(await _api
          .post('/projects/$projectId/tasks/', body: data, org: org) as Map));

  Future<Task> updateTask(String org, String projectId, String taskId,
          Map<String, dynamic> data) async =>
      Task.fromJson(Map<String, dynamic>.from(await _api.patch(
          '/projects/$projectId/tasks/$taskId/',
          body: data,
          org: org) as Map));

  Future<void> deleteTask(String org, String projectId, String taskId) =>
      _api.delete('/projects/$projectId/tasks/$taskId/', org: org);

  Future<dynamic> moveTask(String org, String projectId, String taskId,
          {required String? statusId, required int order}) =>
      _api.patch('/projects/$projectId/tasks/$taskId/move/',
          body: {'status_id': statusId, 'order': order}, org: org);

  // ── Subtasks / comments / activity ──────────────────────────────────────────

  Future<List<SubTask>> subtasks(String org, String taskId) async =>
      unwrapList(await _api.get('/tasks/$taskId/subtasks/', org: org))
          .map(SubTask.fromJson)
          .toList();

  Future<SubTask> createSubtask(
          String org, String taskId, String title) async =>
      SubTask.fromJson(Map<String, dynamic>.from(await _api.post(
          '/tasks/$taskId/subtasks/',
          body: {'title': title},
          org: org) as Map));

  Future<SubTask> updateSubtask(String org, String taskId, String subtaskId,
          Map<String, dynamic> data) async =>
      SubTask.fromJson(Map<String, dynamic>.from(await _api.patch(
          '/tasks/$taskId/subtasks/$subtaskId/',
          body: data,
          org: org) as Map));

  Future<void> deleteSubtask(String org, String taskId, String subtaskId) =>
      _api.delete('/tasks/$taskId/subtasks/$subtaskId/', org: org);

  Future<List<Comment>> comments(String org, String taskId) async =>
      unwrapList(await _api.get('/tasks/$taskId/comments/', org: org))
          .map(Comment.fromJson)
          .toList();

  Future<Comment> addComment(String org, String taskId, String body) async =>
      Comment.fromJson(Map<String, dynamic>.from(await _api.post(
          '/tasks/$taskId/comments/',
          body: {'body': body},
          org: org) as Map));

  Future<void> deleteComment(String org, String taskId, String commentId) =>
      _api.delete('/tasks/$taskId/comments/$commentId/', org: org);

  Future<List<ActivityEntry>> taskActivity(String org, String taskId) async =>
      unwrapList(await _api.get('/tasks/$taskId/activity/', org: org))
          .map(ActivityEntry.fromJson)
          .toList();

  // ── Attachments ─────────────────────────────────────────────────────────────

  Future<List<Attachment>> attachments(String org, String taskId) async =>
      unwrapList(await _api.get('/tasks/$taskId/attachments/', org: org))
          .map(Attachment.fromJson)
          .toList();

  Future<void> deleteAttachment(
          String org, String taskId, String attachmentId) =>
      _api.delete('/tasks/$taskId/attachments/$attachmentId/', org: org);

  Future<dynamic> uploadAttachmentLocal(
          String org, String taskId, MultipartFile file) =>
      _api.postForm('/tasks/$taskId/attachments/upload-local/',
          FormData.fromMap({'file': file}),
          org: org);

  // ── Notifications ───────────────────────────────────────────────────────────

  Future<Page<AppNotification>> notifications({String? cursorUrl}) async {
    final data = await _api.get(cursorUrl ?? '/notifications/');
    return Page(
      unwrapList(data).map(AppNotification.fromJson).toList(),
      next: data is Map ? data['next'] as String? : null,
    );
  }

  Future<int> unreadCount() async {
    final data = await _api.get('/notifications/unread-count/');
    return data is Map ? (data['count'] as num?)?.toInt() ?? 0 : 0;
  }

  Future<dynamic> markNotificationRead(String id) =>
      _api.post('/notifications/$id/read/');

  Future<dynamic> markAllNotificationsRead() =>
      _api.post('/notifications/mark-all-read/');

  // ── Reports ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createExport(String projectId) async =>
      Map<String, dynamic>.from(
          await _api.post('/reports/', body: {'project_id': projectId}) as Map);

  Future<Map<String, dynamic>> pollExport(String jobId) async =>
      Map<String, dynamic>.from(await _api.get('/reports/$jobId/') as Map);

  Future<String?> exportDownloadUrl(String jobId) async {
    final data = await _api.get('/reports/$jobId/download/');
    return data is Map
        ? (data['download_url'] ?? data['url']) as String?
        : null;
  }
}

final repositoryProvider = Provider<TaskForgeRepository>(
    (ref) => TaskForgeRepository(ref.watch(apiClientProvider)));
