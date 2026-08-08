import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/widgets.dart';
import 'task_providers.dart';

/// One piece of an activity sentence; [strong] pieces are highlighted values.
class ActivityPart {
  const ActivityPart(this.text, {this.strong = false});
  final String text;
  final bool strong;
}

/// Unwraps backend activity values: `{"value": "..."}` for field changes,
/// `{"title": "..."}` for creation, or a raw scalar.
String? _value(dynamic v) {
  if (v == null) return null;
  if (v is Map) {
    final inner = v['value'] ?? v['title'];
    return inner?.toString();
  }
  final s = v.toString();
  return s.isEmpty || s == 'None' ? null : s;
}

String? _date(String? raw) {
  if (raw == null) return null;
  final d = DateTime.tryParse(raw);
  return d == null ? raw : Fmt.short(d);
}

List<ActivityPart> _change(String field, String? from, String? to) {
  if (from == null && to != null) {
    return [ActivityPart('set the $field to '), ActivityPart(to, strong: true)];
  }
  if (from != null && to == null) {
    return [
      ActivityPart('cleared the $field (was '),
      ActivityPart(from, strong: true),
      const ActivityPart(')')
    ];
  }
  return [
    ActivityPart('changed the $field from '),
    ActivityPart(from ?? 'none', strong: true),
    const ActivityPart(' to '),
    ActivityPart(to ?? 'none', strong: true),
  ];
}

String _emails(dynamic v) {
  if (v is List) {
    return v.map((e) => e.toString().split('@').first).join(', ');
  }
  return v?.toString() ?? '';
}

/// Turns an [ActivityEntry] into a human-readable sentence (minus the actor),
/// including old → new values. Status ids are resolved against [statuses].
List<ActivityPart> describeActivity(ActivityEntry e,
    {List<TaskStatus> statuses = const []}) {
  final from = _value(e.oldValue);
  final to = _value(e.newValue);

  String statusName(String? id) {
    if (id == null) return 'no status';
    for (final s in statuses) {
      if (s.id == id) return s.name;
    }
    return 'a removed column';
  }

  switch (e.verb) {
    case 'created':
      return const [ActivityPart('created this task')];
    case 'status_changed':
      return [
        const ActivityPart('moved this task from '),
        ActivityPart(statusName(from), strong: true),
        const ActivityPart(' to '),
        ActivityPart(statusName(to), strong: true),
      ];
    case 'priority_changed':
      return _change('priority', from == null ? null : Fmt.title(from),
          to == null ? null : Fmt.title(to));
    case 'title_changed':
      return [
        const ActivityPart('renamed this task from '),
        ActivityPart('"${from ?? ''}"', strong: true),
        const ActivityPart(' to '),
        ActivityPart('"${to ?? ''}"', strong: true),
      ];
    case 'due_date_changed':
      return _change('due date', _date(from), _date(to));
    case 'start_date_changed':
      return _change('start date', _date(from), _date(to));
    case 'progress_changed':
      return _change('progress', from == null ? null : '$from%',
          to == null ? null : '$to%');
    case 'assignees_changed':
      {
        final nv = e.newValue;
        if (nv is Map) {
          if (nv['cleared'] == true) {
            return const [ActivityPart('removed all assignees')];
          }
          if (nv['added'] != null) {
            return [
              const ActivityPart('assigned '),
              ActivityPart(_emails(nv['added']), strong: true)
            ];
          }
          if (nv['removed'] != null) {
            return [
              const ActivityPart('unassigned '),
              ActivityPart(_emails(nv['removed']), strong: true)
            ];
          }
        }
        return const [ActivityPart('changed the assignees')];
      }
    case 'assignee_changed':
      return const [ActivityPart('changed the assignee')];
    default:
      return [ActivityPart(e.verb.replaceAll('_', ' '))];
  }
}

IconData _iconFor(String verb) => switch (verb) {
      'created' => Icons.add_circle_outline_rounded,
      'status_changed' => Icons.view_column_outlined,
      'priority_changed' => Icons.flag_outlined,
      'title_changed' => Icons.edit_outlined,
      'due_date_changed' || 'start_date_changed' => Icons.event_outlined,
      'progress_changed' => Icons.show_chart_rounded,
      'assignees_changed' ||
      'assignee_changed' =>
        Icons.person_add_alt_outlined,
      _ => Icons.bolt_outlined,
    };

/// Task activity timeline (newest first).
class ActivityList extends ConsumerWidget {
  const ActivityList({super.key, required this.taskRef});
  final TaskRef taskRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(taskActivityProvider(taskRef));
    final statuses = ref
            .watch(taskStatusOptionsProvider(
                (slug: taskRef.slug, projectId: taskRef.projectId)))
            .valueOrNull ??
        const [];

    return activity.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const _ActivitySkeleton(),
      error: (e, _) => _InlineError(
          error: e,
          onRetry: () => ref.invalidate(taskActivityProvider(taskRef))),
      data: (items) {
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child:
                Center(child: Text('No activity yet.', style: TFText.small())),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++)
              _ActivityRow(
                      entry: items[i],
                      statuses: statuses,
                      last: i == items.length - 1)
                  .animate(
                      key: ValueKey(items[i].id),
                      delay: (30 * (i > 10 ? 10 : i)).ms)
                  .fadeIn(duration: 260.ms)
                  .slideX(begin: 0.04, end: 0, curve: TF.ease),
          ],
        );
      },
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(
      {required this.entry, required this.statuses, required this.last});
  final ActivityEntry entry;
  final List<TaskStatus> statuses;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final actor = entry.actor?.displayName ?? 'System';
    final parts = describeActivity(entry, statuses: statuses);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Timeline rail: dot + hairline.
        SizedBox(
          width: 28,
          child: Column(children: [
            const SizedBox(height: 4),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: TF.bgElevated,
                shape: BoxShape.circle,
                border: Border.all(color: TF.borderDefault),
              ),
              child: Icon(_iconFor(entry.verb), size: 12, color: TF.brand),
            ),
            if (!last)
              Expanded(child: Container(width: 1, color: TF.borderDefault)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(
                  style: TFText.sans(
                      size: 13.5, color: TF.textSecondary, height: 1.45),
                  children: [
                    TextSpan(
                        text: actor,
                        style: TFText.sans(
                            size: 13.5,
                            weight: FontWeight.w600,
                            color: TF.textPrimary)),
                    const TextSpan(text: ' '),
                    for (final p in parts)
                      TextSpan(
                        text: p.text,
                        style: p.strong
                            ? TFText.sans(
                                size: 13.5,
                                weight: FontWeight.w600,
                                color: TF.brandSecondary)
                            : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(Fmt.relative(entry.createdAt),
                  style: TFText.mono(size: 10.5)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var i = 0; i < 4; i++)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Row(children: [
            Skeleton(width: 22, height: 22, radius: 11),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(height: 11),
                    SizedBox(height: 6),
                    Skeleton(height: 9, width: 70),
                  ]),
            ),
          ]),
        ),
    ]);
  }
}

/// Compact error row with retry used inside the detail tabs.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        Text('Could not load activity.', style: TFText.small(color: TF.danger)),
        const SizedBox(height: 10),
        TFButton(
          label: 'Retry',
          icon: Icons.refresh_rounded,
          size: TFButtonSize.sm,
          variant: TFButtonVariant.secondary,
          onPressed: onRetry,
        ),
      ]),
    );
  }
}
