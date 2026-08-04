import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/widgets.dart';
import 'board_providers.dart';
import 'board_widgets.dart';

/// Overview tab (web `TaskDistributionChart` + `TeamVelocityChart`): stat
/// tiles, priority donut, weekly velocity and status breakdown.
class AnalyticsView extends ConsumerWidget {
  const AnalyticsView({super.key, required this.boardKey});
  final BoardKey boardKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider(boardKey));
    final project = ref.watch(projectDetailProvider(boardKey)).valueOrNull;
    final statuses = ref.watch(boardStatusesProvider(boardKey)).valueOrNull ??
        const <TaskStatus>[];
    final tasks = ref.watch(boardControllerProvider(boardKey)).valueOrNull ??
        const <Task>[];

    Future<void> refresh() async {
      ref.invalidate(analyticsProvider(boardKey));
      ref.invalidate(projectDetailProvider(boardKey));
      try {
        await ref.read(analyticsProvider(boardKey).future);
      } catch (_) {
        // The error state renders inside the view.
      }
    }

    return AsyncView<ProjectAnalytics>(
      value: analytics,
      onRetry: () => ref.invalidate(analyticsProvider(boardKey)),
      loading: const _AnalyticsSkeleton(),
      data: (a) {
        final overdue = tasks.where((t) => t.isOverdue).length;
        final now = DateTime.now();
        final weekEnd =
            DateTime(now.year, now.month, now.day).add(const Duration(days: 7));
        final dueSoon = tasks
            .where((t) =>
                t.dueDate != null &&
                !t.isOverdue &&
                t.dueDate!.isBefore(weekEnd))
            .length;
        final total = project?.taskCount ?? a.totalTasks;
        final progress = project?.progressPercent;

        final blocks = <Widget>[
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: [
              StatTile(
                  label: 'Total tasks',
                  value: '$total',
                  icon: Icons.layers_outlined),
              StatTile(
                label: 'Progress',
                value: progress == null ? '—' : '$progress%',
                icon: Icons.donut_large_rounded,
                accent: TF.success,
              ),
              StatTile(
                label: 'Done · 8 wks',
                value: '${a.completedInWindow}',
                icon: Icons.task_alt_rounded,
                accent: TF.info,
              ),
              StatTile(
                label: 'Overdue',
                value: '$overdue',
                icon: Icons.error_outline_rounded,
                accent: overdue > 0 ? TF.danger : TF.textMuted,
                caption: dueSoon > 0 ? '$dueSoon due this week' : null,
              ),
            ],
          ),
          _ChartCard(
            eyebrow: 'Distribution',
            title: 'Tasks by priority',
            child: _PriorityDonut(shares: a.distribution),
          ),
          _ChartCard(
            eyebrow: 'Velocity',
            title: 'Completed vs planned',
            subtitle: 'Last 8 weeks',
            child: _VelocityChart(points: a.velocity),
          ),
          if (project != null && project.statusCounts.isNotEmpty)
            _ChartCard(
              eyebrow: 'Workflow',
              title: 'Status breakdown',
              child: _StatusBreakdown(
                  counts: project.statusCounts, statuses: statuses),
            ),
        ];

        return RefreshIndicator(
          color: TF.brand,
          backgroundColor: TF.bgElevated,
          onRefresh: refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            itemCount: blocks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (_, i) => blocks[i]
                .animate()
                .fadeIn(delay: (i * 90).ms, duration: 380.ms, curve: TF.ease)
                .slideY(
                    begin: 0.06,
                    end: 0,
                    delay: (i * 90).ms,
                    duration: 380.ms,
                    curve: TF.ease),
          ),
        );
      },
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard(
      {required this.eyebrow,
      required this.title,
      required this.child,
      this.subtitle});
  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TFCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Eyebrow(eyebrow, color: TF.brand),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text(title, style: TFText.h3())),
          if (subtitle != null) Text(subtitle!, style: TFText.small()),
        ]),
        const SizedBox(height: 18),
        child,
      ]),
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.insights_rounded, color: TF.textDisabled, size: 26),
          const SizedBox(height: 8),
          Text(message, style: TFText.small()),
        ]),
      ),
    );
  }
}

// ── Priority donut ────────────────────────────────────────────────────────────

class _PriorityDonut extends StatefulWidget {
  const _PriorityDonut({required this.shares});
  final List<PriorityShare> shares;

  @override
  State<_PriorityDonut> createState() => _PriorityDonutState();
}

class _PriorityDonutState extends State<_PriorityDonut> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final shares = widget.shares;
    final total = shares.fold<int>(0, (a, b) => a + b.count);
    if (total == 0) return const _NoData('No tasks yet');

    final focused =
        _touched >= 0 && _touched < shares.length ? shares[_touched] : null;

    return Row(children: [
      SizedBox(
        width: 150,
        height: 150,
        child: Stack(alignment: Alignment.center, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: 2,
                centerSpaceRadius: 48,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    final idx =
                        response?.touchedSection?.touchedSectionIndex ?? -1;
                    if (!event.isInterestedForInteractions) {
                      if (_touched != -1) setState(() => _touched = -1);
                      return;
                    }
                    if (idx != _touched) setState(() => _touched = idx);
                  },
                ),
                sections: [
                  for (var i = 0; i < shares.length; i++)
                    PieChartSectionData(
                      value: math.max(shares[i].count.toDouble(), 0.0001) * t,
                      color: TF.priorityColor(shares[i].priority).withValues(
                          alpha: _touched == -1 || _touched == i ? 1.0 : 0.35),
                      radius: _touched == i ? 22 : 17,
                      showTitle: false,
                    ),
                  // Fills the rest of the ring while sweeping in.
                  if (t < 1)
                    PieChartSectionData(
                      value: total * (1 - t),
                      color: Colors.transparent,
                      radius: 17,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: TF.dur,
              child: Text(
                focused == null ? '$total' : '${focused.count}',
                key: ValueKey(focused?.priority ?? 'total'),
                style: TFText.mono(
                    size: 24, weight: FontWeight.w600, color: TF.textPrimary),
              ),
            ),
            Text(
              focused == null ? 'TASKS' : focused.priority.toUpperCase(),
              style: TFText.eyebrow(),
            ),
          ]),
        ]),
      ),
      const SizedBox(width: 18),
      Expanded(
        child: Column(children: [
          for (var i = 0; i < shares.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _touched = _touched == i ? -1 : i),
              child: AnimatedOpacity(
                duration: TF.dur,
                opacity: _touched == -1 || _touched == i ? 1.0 : 0.45,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        color: TF.priorityColor(shares[i].priority)),
                    const SizedBox(width: 9),
                    Expanded(
                        child: Text(Fmt.title(shares[i].priority),
                            style: TFText.sans(size: 13.5))),
                    Text('${shares[i].count}',
                        style: TFText.mono(size: 12.5, color: TF.textPrimary)),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${shares[i].percent.toStringAsFixed(shares[i].percent % 1 == 0 ? 0 : 1)}%',
                        textAlign: TextAlign.right,
                        style: TFText.mono(size: 11.5),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}

// ── Velocity ──────────────────────────────────────────────────────────────────

class _VelocityChart extends StatelessWidget {
  const _VelocityChart({required this.points});
  final List<VelocityPoint> points;

  static const _completed = TF.brand;
  static const _planned = TF.info;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const _NoData('No velocity data yet');
    final peak = points.fold<int>(
        0, (m, p) => math.max(m, math.max(p.completed, p.planned)));
    final maxY = peak <= 4 ? 4.0 : (peak * 1.2).ceilToDouble();
    final interval = math.max(1.0, (maxY / 4).ceilToDouble());

    return Column(children: [
      Row(children: [
        _legend(_completed, 'Completed'),
        const SizedBox(width: 16),
        _legend(_planned.withValues(alpha: 0.55), 'Planned (due)'),
      ]),
      const SizedBox(height: 16),
      SizedBox(
        height: 190,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            minY: 0,
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: interval,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: TF.borderSubtle, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  interval: interval,
                  getTitlesWidget: (value, meta) {
                    if (value != value.roundToDouble()) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text('${value.toInt()}',
                          textAlign: TextAlign.right,
                          style: TFText.mono(size: 10)),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= points.length) {
                      return const SizedBox.shrink();
                    }
                    final isCurrent = i == points.length - 1;
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        points[i].weekLabel,
                        style: TFText.mono(
                            size: 10,
                            color: isCurrent ? TF.brand : TF.textMuted),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => TF.bgOverlay,
                tooltipPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                tooltipMargin: 8,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final p = points[group.x.toInt().clamp(0, points.length - 1)];
                  return BarTooltipItem(
                    '${p.weekLabel}\n',
                    TFText.mono(size: 11, color: TF.textMuted),
                    children: [
                      TextSpan(
                        text: rodIndex == 0
                            ? '${p.completed} completed'
                            : '${p.planned} planned',
                        style: TFText.sans(
                            size: 12.5,
                            weight: FontWeight.w600,
                            color: TF.textPrimary),
                      ),
                    ],
                  );
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < points.length; i++)
                BarChartGroupData(
                  x: i,
                  barsSpace: 2,
                  barRods: [
                    BarChartRodData(
                      toY: points[i].completed.toDouble(),
                      color: _completed,
                      width: 8,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(2)),
                    ),
                    BarChartRodData(
                      toY: points[i].planned.toDouble(),
                      color: _planned.withValues(alpha: 0.55),
                      width: 8,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(2)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _legend(Color color, String text) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 6),
        Text(text, style: TFText.small(color: TF.textSecondary)),
      ]);
}

// ── Status breakdown ──────────────────────────────────────────────────────────

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.counts, required this.statuses});
  final Map<String, int> counts;
  final List<TaskStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const _NoData('No tasks yet');
    Color colorOf(String name) {
      for (final s in statuses) {
        if (s.name == name) return TF.hex(s.color);
      }
      return TF.textMuted;
    }

    final entries = counts.entries.toList();
    return Column(children: [
      // Stacked overview bar.
      ClipRRect(
        borderRadius: BorderRadius.circular(TF.radiusSm),
        child: SizedBox(
          height: 8,
          child: Row(children: [
            for (final (i, e) in entries.indexed)
              if (e.value > 0)
                Expanded(
                  flex: e.value,
                  child: Container(
                    margin:
                        EdgeInsets.only(right: i == entries.length - 1 ? 0 : 2),
                    color: colorOf(e.key),
                  ),
                ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ColorDot(colorOf(e.key)),
              const SizedBox(width: 8),
              Expanded(child: Text(e.key, style: TFText.sans(size: 13.5))),
              Text('${e.value}',
                  style: TFText.mono(size: 12.5, color: TF.textPrimary)),
              SizedBox(
                width: 46,
                child: Text(
                  '${(e.value * 100 / total).round()}%',
                  textAlign: TextAlign.right,
                  style: TFText.mono(size: 11.5),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            TFProgressBar(
                value: e.value / total, height: 3, color: colorOf(e.key)),
          ]),
        ),
    ]);
  }
}

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const Row(children: [
          Expanded(child: Skeleton(height: 92, radius: TF.radiusLg)),
          SizedBox(width: 10),
          Expanded(child: Skeleton(height: 92, radius: TF.radiusLg)),
        ]),
        const SizedBox(height: 10),
        const Row(children: [
          Expanded(child: Skeleton(height: 92, radius: TF.radiusLg)),
          SizedBox(width: 10),
          Expanded(child: Skeleton(height: 92, radius: TF.radiusLg)),
        ]),
        const SizedBox(height: 14),
        const Skeleton(height: 220, radius: TF.radiusLg),
        const SizedBox(height: 14),
        const Skeleton(height: 260, radius: TF.radiusLg),
      ],
    );
  }
}
