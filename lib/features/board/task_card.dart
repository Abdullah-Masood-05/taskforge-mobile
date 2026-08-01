import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/widgets.dart';

/// Kanban card (web `KanbanCard`): reference, title, priority, labels, due
/// date, subtask progress and assignees.
///
/// The title is wrapped in a `Hero(tag: 'task-<id>')` so it flies into the
/// task detail screen. Drag feedback/ghost copies pass [heroEnabled] false to
/// avoid duplicate hero tags.
class KanbanCard extends StatelessWidget {
  const KanbanCard({
    super.key,
    required this.task,
    this.onTap,
    this.onMenu,
    this.heroEnabled = true,
    this.lifted = false,
  });

  final Task task;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;
  final bool heroEnabled;

  /// Rendered as the floating drag feedback (glow + brand border).
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      task.title,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TFText.sans(size: 14.5, weight: FontWeight.w500, height: 1.35),
    );

    final hasFooter = task.dueDate != null ||
        task.subtaskTotal > 0 ||
        task.assignees.isNotEmpty;

    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            if (task.referenceLabel != null)
              Text(task.referenceLabel!,
                  style: TFText.mono(
                      size: 10.5, weight: FontWeight.w600, letterSpacing: 0.6)),
            const Spacer(),
            TFBadge.priority(task.priority),
            if (onMenu != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onMenu,
                child: const Padding(
                  padding: EdgeInsets.only(left: 6, top: 2, bottom: 2),
                  child: Icon(Icons.more_horiz_rounded,
                      size: 18, color: TF.textMuted),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          heroEnabled
              ? Hero(
                  tag: 'task-${task.id}',
                  child:
                      Material(type: MaterialType.transparency, child: title),
                )
              : title,
          if (task.labels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 5, runSpacing: 5, children: [
              for (final l in task.labels.take(4)) _LabelChip(label: l),
              if (task.labels.length > 4)
                Text('+${task.labels.length - 4}',
                    style: TFText.mono(size: 10, color: TF.textMuted)),
            ]),
          ],
          if (hasFooter) ...[
            const SizedBox(height: 12),
            Row(children: [
              if (task.dueDate != null) ...[
                _DueChip(date: task.dueDate!, overdue: task.isOverdue),
                const SizedBox(width: 10),
              ],
              if (task.subtaskTotal > 0)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    Icons.check_box_outlined,
                    size: 13,
                    color: task.subtaskDone == task.subtaskTotal
                        ? TF.success
                        : TF.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${task.subtaskDone}/${task.subtaskTotal}',
                    style: TFText.mono(
                      size: 11,
                      color: task.subtaskDone == task.subtaskTotal
                          ? TF.success
                          : TF.textMuted,
                    ),
                  ),
                ]),
              const Spacer(),
              if (task.assignees.isNotEmpty)
                AvatarStack(
                  names: [for (final a in task.assignees) a.displayName],
                  urls: [for (final a in task.assignees) a.avatarUrl],
                  size: 22,
                ),
            ]),
          ],
          if (task.subtaskTotal > 0) ...[
            const SizedBox(height: 10),
            TFProgressBar(
              value: task.subtaskTotal == 0
                  ? 0
                  : task.subtaskDone / task.subtaskTotal,
              height: 2,
              color: task.subtaskDone == task.subtaskTotal ? TF.success : null,
            ),
          ],
        ]);

    final accent = TF.priorityColor(task.priority);
    final card = Container(
      decoration: BoxDecoration(
        color: lifted ? TF.bgElevated : TF.bgSurface,
        borderRadius: BorderRadius.circular(TF.radiusLg),
        border: Border.all(color: lifted ? TF.borderBrand : TF.borderDefault),
        boxShadow: lifted ? [...TF.shadowLg, ...TF.shadowGlow] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TF.radiusLg),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Priority accent rail.
            Container(
                width: 2,
                color: accent.withValues(
                    alpha: task.priority == 'low' ? 0.25 : 0.7)),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                    child: body)),
          ]),
        ),
      ),
    );

    if (onTap == null) return card;
    return Pressable(onTap: onTap, scale: 0.98, child: card);
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.label});
  final Label label;

  @override
  Widget build(BuildContext context) {
    final c = TF.hex(label.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TF.radiusSm),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(label.name,
          style: TFText.sans(size: 11, weight: FontWeight.w500, color: c)),
    );
  }
}

class _DueChip extends StatelessWidget {
  const _DueChip({required this.date, required this.overdue});
  final DateTime date;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final isToday = d == today;
    final color = overdue ? TF.danger : (isToday ? TF.brand : TF.textMuted);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(overdue ? Icons.error_outline_rounded : Icons.schedule_rounded,
          size: 13, color: color),
      const SizedBox(width: 4),
      Text(isToday ? 'Today' : Fmt.short(date),
          style: TFText.mono(size: 11, color: color)),
    ]);
  }
}
