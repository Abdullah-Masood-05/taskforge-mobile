import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/widgets.dart';
import 'board_providers.dart';

/// Project activity feed (web `ActivityFeed`): who did what, newest first.
class ActivityView extends ConsumerWidget {
  const ActivityView(
      {super.key, required this.boardKey, required this.onOpenTask});
  final BoardKey boardKey;
  final ValueChanged<String> onOpenTask;

  static (IconData, Color) verbStyle(String verb) => switch (verb) {
        'created' => (Icons.add_circle_outline_rounded, TF.success),
        'status_changed' => (Icons.swap_horiz_rounded, TF.brand),
        'assignees_changed' => (Icons.person_add_alt_rounded, TF.info),
        'priority_changed' => (Icons.flag_outlined, TF.danger),
        'title_changed' => (Icons.edit_outlined, TF.textSecondary),
        'due_date_changed' || 'start_date_changed' => (
            Icons.event_outlined,
            TF.brandSecondary
          ),
        'progress_changed' => (Icons.trending_up_rounded, TF.success),
        _ => (Icons.bolt_rounded, TF.textMuted),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(projectActivityProvider(boardKey));

    Future<void> refresh() async {
      ref.invalidate(projectActivityProvider(boardKey));
      try {
        await ref.read(projectActivityProvider(boardKey).future);
      } catch (_) {}
    }

    return AsyncView<List<ActivityEntry>>(
      value: activity,
      onRetry: () => ref.invalidate(projectActivityProvider(boardKey)),
      loading: const SkeletonList(count: 7, itemHeight: 58),
      data: (entries) => RefreshIndicator(
        color: TF.brand,
        backgroundColor: TF.bgElevated,
        onRefresh: refresh,
        child: entries.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 40),
                  EmptyState(
                    icon: Icons.history_rounded,
                    title: 'No activity yet',
                    message:
                        'Task changes across this project will show up here.',
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                itemCount: entries.length,
                itemBuilder: (context, i) => _ActivityRow(
                  entry: entries[i],
                  isLast: i == entries.length - 1,
                  onOpenTask: onOpenTask,
                )
                    .animate()
                    .fadeIn(delay: (i.clamp(0, 12) * 35).ms, duration: 280.ms)
                    .slideX(begin: 0.04, end: 0),
              ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(
      {required this.entry, required this.isLast, required this.onOpenTask});
  final ActivityEntry entry;
  final bool isLast;
  final ValueChanged<String> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final actor = entry.actor;
    final actorName = actor?.fullName.trim().isNotEmpty == true
        ? actor!.fullName
        : (actor?.email ?? 'Someone');
    final message = (entry.raw['message'] ?? '').toString();
    final task = entry.raw['task'] is Map
        ? Map<String, dynamic>.from(entry.raw['task'] as Map)
        : const <String, dynamic>{};
    final taskId = task['id']?.toString();
    final taskTitle = task['title']?.toString();
    final taskRef = task['reference_label']?.toString();

    // The server message already starts with the actor's name; split it off
    // so the name can be emphasised.
    String rest = message.isEmpty ? Fmt.title(entry.verb) : message;
    var boldName = actorName;
    if (message.startsWith(actorName)) {
      rest = message.substring(actorName.length);
    } else if (actor != null && message.startsWith(actor.email)) {
      boldName = actor.email;
      rest = message.substring(actor.email.length);
    } else if (message.isNotEmpty) {
      boldName = '';
    }

    final (icon, color) = ActivityView.verbStyle(entry.verb);

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Avatar + connector rail.
        SizedBox(
          width: 36,
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              TFAvatar(
                  name: actor?.displayName ?? 'Someone',
                  imageUrl: actor?.avatarUrl,
                  size: 32),
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: TF.bgBase,
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.6)),
                  ),
                  child: Icon(icon, size: 10, color: color),
                ),
              ),
            ]),
            if (!isLast)
              Expanded(
                child: Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  color: TF.borderDefault,
                ),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: 2),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  if (boldName.isNotEmpty)
                    TextSpan(
                        text: boldName,
                        style: TFText.sans(
                            size: 13.5,
                            weight: FontWeight.w600,
                            color: TF.textPrimary)),
                  TextSpan(
                      text: rest,
                      style: TFText.sans(
                          size: 13.5, color: TF.textSecondary, height: 1.45)),
                ]),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Text(Fmt.relative(entry.createdAt),
                    style: TFText.mono(size: 10.5)),
                if (taskId != null && taskTitle != null) ...[
                  Text('  ·  ',
                      style: TFText.mono(size: 10.5, color: TF.textDisabled)),
                  Flexible(
                    child: GestureDetector(
                      onTap: () => onOpenTask(taskId),
                      child: Text(
                        taskRef == null ? taskTitle : '$taskRef  $taskTitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TFText.mono(size: 10.5, color: TF.brand),
                      ),
                    ),
                  ),
                ],
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
