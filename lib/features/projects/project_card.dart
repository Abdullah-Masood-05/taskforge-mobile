import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/widgets.dart';

/// Project lifecycle statuses, in display order.
const kProjectStatuses = ['planning', 'in_progress', 'on_hold', 'completed'];

/// Project priorities, in display order.
const kProjectPriorities = ['low', 'medium', 'high', 'urgent'];

/// Status → colour (mirrors web `ProjectHeader.module.css` status pills).
Color projectStatusColor(String status) => switch (status) {
      'in_progress' => TF.brand,
      'completed' => TF.success,
      'on_hold' => TF.danger,
      _ => TF.textSecondary,
    };

/// Status → human label ("In Progress").
String projectStatusLabel(String status) => switch (status) {
      'planning' => 'Planning',
      'in_progress' => 'In Progress',
      'on_hold' => 'On Hold',
      'completed' => 'Completed',
      _ => Fmt.title(status),
    };

/// True when the project's due date is before today and it isn't completed.
bool projectIsOverdue(Project p) {
  final d = p.dueDate;
  if (d == null || p.status == 'completed') return false;
  final now = DateTime.now();
  return DateTime(d.year, d.month, d.day)
      .isBefore(DateTime(now.year, now.month, now.day));
}

enum ProjectAction { edit, archive, delete }

/// Reusable project card (web `ProjectCard` on the projects page): hue-tinted
/// initial tile, name/description, status + priority badges and a footer with
/// task count, due date (red when overdue) and owner.
class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    this.onTap,
    this.onLongPress,
    this.onEdit,
    this.onArchive,
    this.onDelete,
  });

  final Project project;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;

  bool get _hasMenu => onEdit != null || onArchive != null || onDelete != null;

  Color get _tileColor {
    final name = project.name.isEmpty ? '?' : project.name;
    final hue = ((name.codeUnitAt(0) * 37) % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.55, 0.25).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final p = project;
    final overdue = projectIsOverdue(p);
    final ownerName = p.owner?.displayName ??
        (p.ownerEmail.isNotEmpty ? p.ownerEmail.split('@').first : '');
    final initial = p.name.trim().isEmpty
        ? '?'
        : p.name.trim().substring(0, 1).toUpperCase();

    final card = Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
      decoration: BoxDecoration(
        color: TF.bgSurface,
        borderRadius: BorderRadius.circular(TF.radiusLg),
        border: Border.all(
            color:
                overdue ? TF.danger.withValues(alpha: 0.25) : TF.borderDefault),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Top row: tile, name, menu ──────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _tileColor,
              borderRadius: BorderRadius.circular(TF.radiusMd),
              border: Border.all(color: TF.borderStrong),
            ),
            child: Text(initial,
                style: TFText.sans(
                    size: 17, weight: FontWeight.w700, color: TF.textPrimary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TFText.sans(
                          size: 16,
                          weight: FontWeight.w600,
                          letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      p.createdAt == null
                          ? 'PROJECT'
                          : 'CREATED ${Fmt.short(p.createdAt).toUpperCase()}',
                      style: TFText.mono(size: 10, letterSpacing: 1.2),
                    ),
                  ]),
            ),
          ),
          if (_hasMenu) _menu(context) else const SizedBox(width: 8),
        ]),

        // ── Description ────────────────────────────────────────────────────
        if (p.description.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              p.description.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TFText.small(color: TF.textSecondary),
            ),
          ),
        ],

        // ── Badges ─────────────────────────────────────────────────────────
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          TFBadge(projectStatusLabel(p.status),
              color: projectStatusColor(p.status)),
          TFBadge.priority(p.priority),
          if (p.archived) const TFBadge('Archived', color: TF.textMuted),
        ]),

        // ── Footer ─────────────────────────────────────────────────────────
        const SizedBox(height: 12),
        Container(
            height: 1,
            color: TF.borderSubtle,
            margin: const EdgeInsets.only(right: 8)),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(children: [
            const Icon(Icons.checklist_rounded, size: 14, color: TF.textMuted),
            const SizedBox(width: 5),
            Text(
              '${p.taskCount} ${p.taskCount == 1 ? 'task' : 'tasks'}',
              style: TFText.mono(size: 11, color: TF.textSecondary),
            ),
            if (p.dueDate != null) ...[
              const SizedBox(width: 14),
              Icon(
                overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
                size: 14,
                color: overdue ? TF.danger : TF.textMuted,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  overdue
                      ? 'Overdue · ${Fmt.short(p.dueDate)}'
                      : 'Due ${Fmt.short(p.dueDate)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TFText.mono(
                    size: 11,
                    color: overdue ? TF.danger : TF.textSecondary,
                    weight: overdue ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (ownerName.isNotEmpty)
              Tooltip(
                message: p.ownerEmail.isNotEmpty ? p.ownerEmail : ownerName,
                child: TFAvatar(
                    name: ownerName, imageUrl: p.owner?.avatarUrl, size: 22),
              ),
          ]),
        ),
      ]),
    );

    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.985,
      child: AnimatedOpacity(
        duration: TF.dur,
        opacity: p.archived ? 0.65 : 1,
        child: card,
      ),
    );
  }

  Widget _menu(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: PopupMenuButton<ProjectAction>(
        tooltip: 'Project options',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        icon:
            const Icon(Icons.more_horiz_rounded, size: 18, color: TF.textMuted),
        onSelected: (a) {
          switch (a) {
            case ProjectAction.edit:
              onEdit?.call();
            case ProjectAction.archive:
              onArchive?.call();
            case ProjectAction.delete:
              onDelete?.call();
          }
        },
        itemBuilder: (_) => [
          if (onEdit != null)
            _item(ProjectAction.edit, Icons.edit_outlined, 'Edit',
                TF.textPrimary),
          if (onArchive != null)
            _item(
              ProjectAction.archive,
              project.archived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              project.archived ? 'Unarchive' : 'Archive',
              TF.textPrimary,
            ),
          if (onDelete != null)
            _item(ProjectAction.delete, Icons.delete_outline_rounded, 'Delete',
                TF.danger),
        ],
      ),
    );
  }

  PopupMenuItem<ProjectAction> _item(
      ProjectAction value, IconData icon, String label, Color color) {
    return PopupMenuItem<ProjectAction>(
      value: value,
      height: 40,
      child: Row(children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 10),
        Text(label, style: TFText.sans(size: 14, color: color)),
      ]),
    );
  }
}
