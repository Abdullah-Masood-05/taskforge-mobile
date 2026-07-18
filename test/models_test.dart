import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskforge_mobile/core/api/api_client.dart';
import 'package:taskforge_mobile/core/theme/tokens.dart';
import 'package:taskforge_mobile/data/models.dart';
import 'package:taskforge_mobile/widgets/brand.dart';

void main() {
  group('Task.fromJson', () {
    test('parses a board payload', () {
      final task = Task.fromJson({
        'id': 't1',
        'reference_label': 'TASK-12',
        'title': 'Ship mobile app',
        'priority': 'high',
        'status_id': 's1',
        'assignees': [
          {'id': 'u1', 'email': 'ada@example.com', 'full_name': 'Ada Lovelace'},
        ],
        'labels': [
          {'id': 'l1', 'name': 'mobile', 'color': '#f5a623'},
        ],
        'due_date': '2020-01-01',
        'subtask_total': 4,
        'subtask_done': 1,
      });

      expect(task.referenceLabel, 'TASK-12');
      expect(task.statusId, 's1');
      expect(task.assignees.single.displayName, 'Ada Lovelace');
      expect(task.labels.single.name, 'mobile');
      expect(task.subtaskTotal, 4);
      expect(task.isOverdue, isTrue);
    });

    test('derives status id and subtask counts from detail payload', () {
      final task = Task.fromJson({
        'id': 't2',
        'title': 'Detail',
        'status': {'id': 's9', 'name': 'Done', 'color': '#10b981', 'order': 3},
        'subtasks': [
          {'id': 'a', 'title': 'one', 'completed': true},
          {'id': 'b', 'title': 'two', 'completed': false},
        ],
      });

      expect(task.statusId, 's9');
      expect(task.subtaskTotal, 2);
      expect(task.subtaskDone, 1);
    });

    test('tolerates missing fields', () {
      final task = Task.fromJson({'id': 'x', 'title': 'Bare'});
      expect(task.priority, 'medium');
      expect(task.assignees, isEmpty);
      expect(task.isOverdue, isFalse);
    });
  });

  test('Project.fromJson reads status counts', () {
    final p = Project.fromJson({
      'id': 'p1',
      'name': 'Platform Relaunch',
      'status_counts': {'To Do': 5, 'Done': 2},
      'progress_percent': 40,
    });
    expect(p.statusCounts['To Do'], 5);
    expect(p.progressPercent, 40);
  });

  test('User display name falls back to email', () {
    expect(User.fromJson({'id': '1', 'email': 'sam@taskforge.dev'}).displayName,
        'sam');
  });

  test('unwrapList handles paginated and bare lists', () {
    expect(
        unwrapList({
          'results': [
            {'id': 1}
          ]
        }).length,
        1);
    expect(
        unwrapList([
          {'id': 1},
          {'id': 2}
        ]).length,
        2);
    expect(unwrapList(null), isEmpty);
  });

  test('TF.hex parses API colours', () {
    expect(TF.hex('#10b981'), const Color(0xFF10B981));
    expect(TF.hex('fff'), const Color(0xFFFFFFFF));
    expect(TF.hex('bogus'), TF.brand);
  });

  test('Fmt helpers', () {
    expect(Fmt.apiDate(DateTime(2026, 7, 5)), '2026-07-05');
    expect(Fmt.fileSize(2048), '2.0 KB');
    expect(Fmt.title('in_progress'), 'In Progress');
    expect(Fmt.relative(DateTime.now()), 'just now');
  });
}
