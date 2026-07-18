/// Plain data models parsed from the TaskForge REST API (same payloads the
/// web app consumes). Parsing is lenient: unknown/missing fields fall back to
/// sensible defaults so a backend addition never crashes the app.
library;

String _s(dynamic v, [String d = '']) => v == null ? d : v.toString();
String? _sn(dynamic v) =>
    v == null || v.toString().isEmpty ? null : v.toString();
int _i(dynamic v, [int d = 0]) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? d);
bool _b(dynamic v) => v == true || v == 'true';
DateTime? _d(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
List<Map<String, dynamic>> _l(dynamic v) => v is List
    ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : const [];

// ── Users ─────────────────────────────────────────────────────────────────────

class MembershipSummary {
  MembershipSummary(
      {required this.orgName,
      required this.orgSlug,
      required this.role,
      this.joinedAt});
  final String orgName;
  final String orgSlug;
  final String role;
  final DateTime? joinedAt;

  factory MembershipSummary.fromJson(Map<String, dynamic> j) =>
      MembershipSummary(
        orgName: _s(j['org_name']),
        orgSlug: _s(j['org_slug']),
        role: _s(j['role'], 'member'),
        joinedAt: _d(j['joined_at']),
      );
}

class User {
  User({
    required this.id,
    required this.email,
    this.firstName = '',
    this.lastName = '',
    this.fullName = '',
    this.avatarUrl,
    this.bio = '',
    this.timezone = 'UTC',
    this.isVerified = false,
    this.dateJoined,
    this.memberships = const [],
    this.raw = const {},
  });

  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String fullName;
  final String? avatarUrl;
  final String bio;
  final String timezone;
  final bool isVerified;
  final DateTime? dateJoined;
  final List<MembershipSummary> memberships;
  final Map<String, dynamic> raw;

  String get displayName =>
      fullName.trim().isNotEmpty ? fullName : email.split('@').first;

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: _s(j['id']),
        email: _s(j['email']),
        firstName: _s(j['first_name']),
        lastName: _s(j['last_name']),
        fullName: _s(j['full_name']),
        avatarUrl: _sn(j['avatar_url']) ?? _sn(j['avatar']),
        bio: _s(j['bio']),
        timezone: _s(j['timezone'], 'UTC'),
        isVerified: _b(j['is_verified']),
        dateJoined: _d(j['date_joined']),
        memberships:
            _l(j['memberships']).map(MembershipSummary.fromJson).toList(),
        raw: j,
      );
}

/// Compact user used inside tasks/projects (`UserSummarySerializer`).
class UserSummary {
  UserSummary(
      {required this.id,
      required this.email,
      this.fullName = '',
      this.avatarUrl});
  final String id;
  final String email;
  final String fullName;
  final String? avatarUrl;

  String get displayName =>
      fullName.trim().isNotEmpty ? fullName : email.split('@').first;

  factory UserSummary.fromJson(Map<String, dynamic> j) => UserSummary(
        id: _s(j['id']),
        email: _s(j['email']),
        fullName: _s(j['full_name']),
        avatarUrl: _sn(j['avatar_url']) ?? _sn(j['avatar']),
      );
}

// ── Organizations ─────────────────────────────────────────────────────────────

class Organization {
  Organization({
    required this.id,
    required this.name,
    required this.slug,
    this.description = '',
    this.website = '',
    this.logo,
    this.ownerEmail = '',
    this.plan = 'free',
    this.memberCount = 0,
    this.createdAt,
  });

  final String id;
  final String name;
  final String slug;
  final String description;
  final String website;
  final String? logo;
  final String ownerEmail;
  final String plan;
  final int memberCount;
  final DateTime? createdAt;

  factory Organization.fromJson(Map<String, dynamic> j) => Organization(
        id: _s(j['id']),
        name: _s(j['name']),
        slug: _s(j['slug']),
        description: _s(j['description']),
        website: _s(j['website']),
        logo: _sn(j['logo']),
        ownerEmail: _s(j['owner_email']),
        plan: _s(j['plan'], 'free'),
        memberCount: _i(j['member_count']),
        createdAt: _d(j['created_at']),
      );
}

class Member {
  Member({
    required this.id,
    required this.userId,
    required this.email,
    this.fullName = '',
    this.avatar,
    this.role = 'member',
    this.invitedByEmail,
    this.joinedAt,
  });

  final String id;
  final String userId;
  final String email;
  final String fullName;
  final String? avatar;
  final String role;
  final String? invitedByEmail;
  final DateTime? joinedAt;

  String get displayName =>
      fullName.trim().isNotEmpty ? fullName : email.split('@').first;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: _s(j['id']),
        userId: _s(j['user_id']),
        email: _s(j['user_email']),
        fullName: _s(j['user_full_name']),
        avatar: _sn(j['user_avatar']),
        role: _s(j['role'], 'member'),
        invitedByEmail: _sn(j['invited_by_email']),
        joinedAt: _d(j['joined_at']),
      );
}

class Invitation {
  Invitation(
      {required this.id,
      required this.email,
      required this.role,
      required this.status,
      this.expiresAt,
      this.createdAt});
  final String id;
  final String email;
  final String role;
  final String status;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  factory Invitation.fromJson(Map<String, dynamic> j) => Invitation(
        id: _s(j['id']),
        email: _s(j['email']),
        role: _s(j['role'], 'member'),
        status: _s(j['status'], 'pending'),
        expiresAt: _d(j['expires_at']),
        createdAt: _d(j['created_at']),
      );
}

class BillingStatus {
  BillingStatus(
      {required this.plan,
      this.subscriptionStatus,
      this.currentPeriodEnd,
      this.hasBillingAccount = false});
  final String plan;
  final String? subscriptionStatus;
  final DateTime? currentPeriodEnd;
  final bool hasBillingAccount;

  factory BillingStatus.fromJson(Map<String, dynamic> j) => BillingStatus(
        plan: _s(j['plan'], 'free'),
        subscriptionStatus: _sn(j['subscription_status']),
        currentPeriodEnd: _d(j['current_period_end']),
        hasBillingAccount: _b(j['has_billing_account']),
      );
}

// ── Projects ──────────────────────────────────────────────────────────────────

class Project {
  Project({
    required this.id,
    required this.name,
    this.description = '',
    this.archived = false,
    this.status = 'planning',
    this.priority = 'medium',
    this.dueDate,
    this.progressOverride,
    this.ownerEmail = '',
    this.owner,
    this.taskCount = 0,
    this.statusCount = 0,
    this.progressPercent,
    this.statusCounts = const {},
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final bool archived;

  /// planning | in_progress | on_hold | completed
  final String status;

  /// low | medium | high | urgent
  final String priority;
  final DateTime? dueDate;
  final int? progressOverride;
  final String ownerEmail;
  final UserSummary? owner;
  final int taskCount;
  final int statusCount;
  final int? progressPercent;

  /// `{status name: task count}` in column order (detail endpoint only).
  final Map<String, int> statusCounts;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: _s(j['id']),
        name: _s(j['name']),
        description: _s(j['description']),
        archived: _b(j['archived']),
        status: _s(j['status'], 'planning'),
        priority: _s(j['priority'], 'medium'),
        dueDate: _d(j['due_date']),
        progressOverride:
            j['progress_override'] == null ? null : _i(j['progress_override']),
        ownerEmail: _s(j['owner_email']),
        owner: j['owner'] is Map
            ? UserSummary.fromJson(Map<String, dynamic>.from(j['owner'] as Map))
            : null,
        taskCount: _i(j['task_count']),
        statusCount: _i(j['status_count']),
        progressPercent:
            j['progress_percent'] == null ? null : _i(j['progress_percent']),
        statusCounts: j['status_counts'] is Map
            ? (j['status_counts'] as Map)
                .map((k, v) => MapEntry(k.toString(), _i(v)))
            : const {},
        createdAt: _d(j['created_at']),
        updatedAt: _d(j['updated_at']),
      );
}

class TaskStatus {
  TaskStatus(
      {required this.id,
      required this.name,
      this.color = '#6366f1',
      this.order = 0,
      this.taskCount = 0});
  final String id;
  final String name;
  final String color;
  final int order;
  final int taskCount;

  factory TaskStatus.fromJson(Map<String, dynamic> j) => TaskStatus(
        id: _s(j['id']),
        name: _s(j['name']),
        color: _s(j['color'], '#6366f1'),
        order: _i(j['order']),
        taskCount: _i(j['task_count']),
      );
}

class Label {
  Label({required this.id, required this.name, this.color = '#6366f1'});
  final String id;
  final String name;
  final String color;

  factory Label.fromJson(Map<String, dynamic> j) => Label(
      id: _s(j['id']), name: _s(j['name']), color: _s(j['color'], '#6366f1'));
}

// ── Tasks ─────────────────────────────────────────────────────────────────────

class SubTask {
  SubTask(
      {required this.id,
      required this.title,
      this.completed = false,
      this.order = 0,
      this.createdAt});
  final String id;
  final String title;
  final bool completed;
  final int order;
  final DateTime? createdAt;

  SubTask copyWith({String? title, bool? completed}) => SubTask(
      id: id,
      title: title ?? this.title,
      completed: completed ?? this.completed,
      order: order,
      createdAt: createdAt);

  factory SubTask.fromJson(Map<String, dynamic> j) => SubTask(
        id: _s(j['id']),
        title: _s(j['title']),
        completed: _b(j['completed']),
        order: _i(j['order']),
        createdAt: _d(j['created_at']),
      );
}

class Comment {
  Comment(
      {required this.id,
      required this.body,
      this.author,
      this.isOwn = false,
      this.createdAt,
      this.updatedAt});
  final String id;
  final String body;
  final UserSummary? author;
  final bool isOwn;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: _s(j['id']),
        body: _s(j['body']),
        author: j['author'] is Map
            ? UserSummary.fromJson(
                Map<String, dynamic>.from(j['author'] as Map))
            : null,
        isOwn: _b(j['is_own']),
        createdAt: _d(j['created_at']),
        updatedAt: _d(j['updated_at']),
      );
}

class ActivityEntry {
  ActivityEntry(
      {required this.id,
      required this.verb,
      this.actor,
      this.oldValue,
      this.newValue,
      this.createdAt,
      this.raw = const {}});
  final String id;
  final String verb;
  final UserSummary? actor;
  final dynamic oldValue;
  final dynamic newValue;
  final DateTime? createdAt;

  /// Full payload — the project-wide feed adds task info (e.g. `task_title`).
  final Map<String, dynamic> raw;

  factory ActivityEntry.fromJson(Map<String, dynamic> j) => ActivityEntry(
        id: _s(j['id']),
        verb: _s(j['verb']),
        actor: j['actor'] is Map
            ? UserSummary.fromJson(Map<String, dynamic>.from(j['actor'] as Map))
            : null,
        oldValue: j['old_value'],
        newValue: j['new_value'],
        createdAt: _d(j['created_at']),
        raw: j,
      );
}

/// A task. List/board payloads omit description/subtasks/comments; the detail
/// endpoint fills them in.
class Task {
  Task({
    required this.id,
    required this.title,
    this.referenceLabel,
    this.description = '',
    this.priority = 'medium',
    this.statusId,
    this.status,
    this.assignees = const [],
    this.labels = const [],
    this.startDate,
    this.dueDate,
    this.progressPercent = 0,
    this.order = 0,
    this.subtaskTotal = 0,
    this.subtaskDone = 0,
    this.subtasks = const [],
    this.comments = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String? referenceLabel;
  final String description;
  final String priority;
  final String? statusId;
  final TaskStatus? status;
  final List<UserSummary> assignees;
  final List<Label> labels;
  final DateTime? startDate;
  final DateTime? dueDate;
  final int progressPercent;
  final int order;
  final int subtaskTotal;
  final int subtaskDone;
  final List<SubTask> subtasks;
  final List<Comment> comments;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOverdue {
    if (dueDate == null) return false;
    final now = DateTime.now();
    return DateTime(dueDate!.year, dueDate!.month, dueDate!.day)
        .isBefore(DateTime(now.year, now.month, now.day));
  }

  Task copyWith(
          {String? statusId, int? order, String? title, String? priority}) =>
      Task(
        id: id,
        title: title ?? this.title,
        referenceLabel: referenceLabel,
        description: description,
        priority: priority ?? this.priority,
        statusId: statusId ?? this.statusId,
        status: status,
        assignees: assignees,
        labels: labels,
        startDate: startDate,
        dueDate: dueDate,
        progressPercent: progressPercent,
        order: order ?? this.order,
        subtaskTotal: subtaskTotal,
        subtaskDone: subtaskDone,
        subtasks: subtasks,
        comments: comments,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  factory Task.fromJson(Map<String, dynamic> j) {
    final status = j['status'] is Map
        ? TaskStatus.fromJson(Map<String, dynamic>.from(j['status'] as Map))
        : null;
    final subtasks = _l(j['subtasks']).map(SubTask.fromJson).toList();
    return Task(
      id: _s(j['id']),
      title: _s(j['title']),
      referenceLabel: _sn(j['reference_label']),
      description: _s(j['description']),
      priority: _s(j['priority'], 'medium'),
      statusId: _sn(j['status_id']) ?? status?.id,
      status: status,
      assignees: _l(j['assignees']).map(UserSummary.fromJson).toList(),
      labels: _l(j['labels']).map(Label.fromJson).toList(),
      startDate: _d(j['start_date']),
      dueDate: _d(j['due_date']),
      progressPercent: _i(j['progress_percent']),
      order: _i(j['order']),
      subtaskTotal:
          j['subtask_total'] != null ? _i(j['subtask_total']) : subtasks.length,
      subtaskDone: j['subtask_done'] != null
          ? _i(j['subtask_done'])
          : subtasks.where((s) => s.completed).length,
      subtasks: subtasks,
      comments: _l(j['comments']).map(Comment.fromJson).toList(),
      createdAt: _d(j['created_at']),
      updatedAt: _d(j['updated_at']),
    );
  }
}

// ── Notifications / attachments / exports ─────────────────────────────────────

class AppNotification {
  AppNotification({
    required this.id,
    required this.verb,
    this.description = '',
    this.actorName,
    this.targetType,
    this.targetId,
    this.isRead = false,
    this.createdAt,
  });

  final String id;
  final String verb;
  final String description;
  final String? actorName;
  final String? targetType;
  final String? targetId;
  final bool isRead;
  final DateTime? createdAt;

  AppNotification markRead() => AppNotification(
        id: id,
        verb: verb,
        description: description,
        actorName: actorName,
        targetType: targetType,
        targetId: targetId,
        isRead: true,
        createdAt: createdAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final actor =
        j['actor'] is Map ? Map<String, dynamic>.from(j['actor'] as Map) : null;
    final name =
        actor == null ? null : (_sn(actor['full_name']) ?? _sn(actor['email']));
    return AppNotification(
      id: _s(j['id']),
      verb: _s(j['verb']),
      description: _s(j['description']),
      actorName: name,
      targetType: _sn(j['target_type']),
      targetId: _sn(j['target_id']),
      isRead: _b(j['is_read']),
      createdAt: _d(j['created_at']),
    );
  }
}

class Attachment {
  Attachment(
      {required this.id,
      required this.fileName,
      this.fileSize = 0,
      this.contentType = '',
      this.uploadedByName,
      this.downloadUrl,
      this.createdAt});
  final String id;
  final String fileName;
  final int fileSize;
  final String contentType;
  final String? uploadedByName;
  final String? downloadUrl;
  final DateTime? createdAt;

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        id: _s(j['id']),
        fileName: _s(j['file_name']),
        fileSize: _i(j['file_size']),
        contentType: _s(j['content_type']),
        uploadedByName: _sn(j['uploaded_by_name']),
        downloadUrl: _sn(j['download_url']),
        createdAt: _d(j['created_at']),
      );
}

/// Paginated response with cursor/page `next` URL.
class Page<T> {
  Page(this.items, {this.next, this.count});
  final List<T> items;
  final String? next;
  final int? count;
}
