import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/widgets.dart';
import 'board_providers.dart';
import 'board_widgets.dart';

/// Gantt-style timeline (web `ProjectTimeline`): every task with both a start
/// and due date, drawn as a bar on a horizontally scrollable day grid.
class TimelineView extends ConsumerStatefulWidget {
  const TimelineView(
      {super.key, required this.boardKey, required this.onOpenTask});
  final BoardKey boardKey;
  final ValueChanged<String> onOpenTask;

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  static const _rowH = 46.0;
  static const _headerH = 44.0;
  static const _nameW = 132.0;

  final _hScroll = ScrollController();
  bool _compact = false;
  bool _didScrollToToday = false;

  double get _dayW => _compact ? 9 : 26;

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Whole days between two dates (DST-safe).
  static int _days(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;

  void _scrollToToday(DateTime rangeStart) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hScroll.hasClients) return;
      final todayX = _days(rangeStart, _day(DateTime.now())) * _dayW;
      final target =
          (todayX - 60).clamp(0.0, _hScroll.position.maxScrollExtent);
      _hScroll.animateTo(target, duration: TF.durSlow, curve: TF.ease);
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(timelineProvider(widget.boardKey));
    return AsyncView<List<TimelineItem>>(
      value: timeline,
      onRetry: () => ref.invalidate(timelineProvider(widget.boardKey)),
      loading: const SkeletonList(count: 6, itemHeight: 40),
      data: (items) {
        if (items.isEmpty) {
          return RefreshIndicator(
            color: TF.brand,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 40),
                EmptyState(
                  icon: Icons.view_timeline_outlined,
                  title: 'Nothing scheduled',
                  message:
                      'Tasks with both a start and a due date appear here as a timeline.',
                ),
              ],
            ),
          );
        }
        return _buildChart(items);
      },
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(timelineProvider(widget.boardKey));
    try {
      await ref.read(timelineProvider(widget.boardKey).future);
    } catch (_) {}
  }

  Widget _buildChart(List<TimelineItem> items) {
    final today = _day(DateTime.now());
    var minD =
        items.map((i) => i.start).reduce((a, b) => a.isBefore(b) ? a : b);
    var maxD = items.map((i) => i.end).reduce((a, b) => a.isAfter(b) ? a : b);
    if (today.isBefore(minD)) minD = today;
    if (today.isAfter(maxD)) maxD = today;
    // Breathing room, aligned to a Monday.
    minD = minD.subtract(Duration(days: 3 + (minD.weekday - 1)));
    maxD = maxD.add(const Duration(days: 10));
    final dayCount = _days(minD, maxD) + 1;
    final width = dayCount * _dayW;
    final height = _headerH + items.length * _rowH;

    if (!_didScrollToToday) {
      _didScrollToToday = true;
      _scrollToToday(minD);
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Row(children: [
          Expanded(
            child: Text('${items.length} SCHEDULED', style: TFText.eyebrow()),
          ),
          ToggleChip(
            label: 'Days',
            selected: !_compact,
            onTap: () {
              setState(() => _compact = false);
              _scrollToToday(minD);
            },
          ),
          const SizedBox(width: 6),
          ToggleChip(
            label: 'Weeks',
            selected: _compact,
            onTap: () {
              setState(() => _compact = true);
              _scrollToToday(minD);
            },
          ),
          const SizedBox(width: 6),
          TFIconButton(
              icon: Icons.today_rounded,
              size: 34,
              tooltip: 'Today',
              onPressed: () => _scrollToToday(minD)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: RefreshIndicator(
          color: TF.brand,
          backgroundColor: TF.bgElevated,
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 40),
            child: SizedBox(
              height: height,
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Fixed task-name column.
                Container(
                  width: _nameW,
                  decoration: const BoxDecoration(
                      border:
                          Border(right: BorderSide(color: TF.borderDefault))),
                  child: Column(children: [
                    Container(
                      height: _headerH,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 16),
                      decoration: const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: TF.borderSubtle))),
                      child: Text('TASK', style: TFText.eyebrow()),
                    ),
                    for (final (i, item) in items.indexed)
                      InkWell(
                        onTap: () => widget.onOpenTask(item.id),
                        child: Container(
                          height: _rowH,
                          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                          alignment: Alignment.centerLeft,
                          decoration: const BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(color: TF.borderSubtle))),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (item.referenceLabel != null)
                                Text(item.referenceLabel!,
                                    style: TFText.mono(
                                        size: 9.5, letterSpacing: 0.5)),
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TFText.sans(
                                    size: 12.5, weight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(
                          delay: (math.min(i, 12) * 30).ms, duration: 250.ms),
                  ]),
                ),
                // Scrollable chart.
                Expanded(
                  child: SingleChildScrollView(
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) {
                        final row =
                            ((d.localPosition.dy - _headerH) / _rowH).floor();
                        if (row >= 0 && row < items.length) {
                          widget.onOpenTask(items[row].id);
                        }
                      },
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(_compact),
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 750),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, _) => CustomPaint(
                          size: Size(width, height),
                          painter: _GanttPainter(
                            items: items,
                            start: minD,
                            dayCount: dayCount,
                            dayWidth: _dayW,
                            rowHeight: _rowH,
                            headerHeight: _headerH,
                            today: today,
                            progress: t,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _GanttPainter extends CustomPainter {
  _GanttPainter({
    required this.items,
    required this.start,
    required this.dayCount,
    required this.dayWidth,
    required this.rowHeight,
    required this.headerHeight,
    required this.today,
    required this.progress,
  });

  final List<TimelineItem> items;
  final DateTime start;
  final int dayCount;
  final double dayWidth;
  final double rowHeight;
  final double headerHeight;
  final DateTime today;
  final double progress;

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC'
  ];

  int _days(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;

  void _text(Canvas canvas, String s, Offset at,
      {Color color = TF.textMuted,
      double size = 9.5,
      FontWeight weight = FontWeight.w500}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TFText.mono(size: size, color: color, weight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final compact = dayWidth < 14;
    final weekend = Paint()..color = const Color(0x06FFFFFF);
    final grid = Paint()
      ..color = TF.borderSubtle
      ..strokeWidth = 1;
    final gridStrong = Paint()
      ..color = TF.borderDefault
      ..strokeWidth = 1;

    // Day columns: weekend shading, week/month lines, header labels.
    for (var i = 0; i < dayCount; i++) {
      final d = DateTime(start.year, start.month, start.day + i);
      final x = i * dayWidth;
      if (d.weekday >= DateTime.saturday) {
        canvas.drawRect(
            Rect.fromLTWH(
                x, headerHeight, dayWidth, size.height - headerHeight),
            weekend);
      }
      final monthStart = d.day == 1;
      if (d.weekday == DateTime.monday || monthStart) {
        canvas.drawLine(Offset(x, monthStart ? 0 : headerHeight * 0.5),
            Offset(x, size.height), monthStart ? gridStrong : grid);
      }
      if (monthStart || i == 0) {
        final yearSuffix = d.year == DateTime.now().year ? '' : ' ${d.year}';
        _text(canvas, '${_months[d.month - 1]}$yearSuffix', Offset(x + 4, 6),
            color: TF.textSecondary, weight: FontWeight.w600);
      }
      if (!compact) {
        _text(
            canvas,
            '${d.day}',
            Offset(
                x + (dayWidth - (d.day > 9 ? 11 : 6)) / 2, headerHeight - 17),
            color: d.weekday >= DateTime.saturday
                ? TF.textDisabled
                : TF.textMuted);
      } else if (d.weekday == DateTime.monday) {
        _text(canvas, '${d.day}', Offset(x + 3, headerHeight - 17));
      }
    }

    // Header + row separators.
    canvas.drawLine(
        Offset(0, headerHeight), Offset(size.width, headerHeight), gridStrong);
    for (var r = 1; r <= items.length; r++) {
      final y = headerHeight + r * rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Bars.
    for (var r = 0; r < items.length; r++) {
      final item = items[r];
      final color =
          TF.hex(item.statusColor, fallback: TF.priorityColor(item.priority));
      final x0 = _days(start, item.start) * dayWidth;
      final fullW = (_days(item.start, item.end) + 1) * dayWidth;
      // Staggered sweep-in.
      final local = ((progress * 1.4) - r * 0.04).clamp(0.0, 1.0);
      final w = math.max(fullW * Curves.easeOutCubic.transform(local), 2.0);
      final top = headerHeight + r * rowHeight + 12;
      final rect =
          Rect.fromLTWH(x0 + 1, top, w - 2 < 2 ? 2.0 : w - 2, rowHeight - 24);
      final rr =
          RRect.fromRectAndRadius(rect, const Radius.circular(TF.radiusSm));

      final overdue = !item.isTerminal && item.end.isBefore(today);
      canvas.drawRRect(rr, Paint()..color = color.withValues(alpha: 0.18));
      final pct =
          (item.isTerminal ? 100 : item.progressPercent).clamp(0, 100) / 100;
      if (pct > 0) {
        canvas.save();
        canvas.clipRRect(rr);
        canvas.drawRect(
            Rect.fromLTWH(rect.left, rect.top, rect.width * pct, rect.height),
            Paint()..color = color.withValues(alpha: 0.75));
        canvas.restore();
      }
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = overdue
              ? TF.danger.withValues(alpha: 0.8)
              : color.withValues(alpha: 0.6),
      );
      // Label inside the bar when it fits.
      if (local >= 1 && rect.width > 44) {
        _text(
          canvas,
          item.isTerminal ? 'DONE' : '${item.progressPercent}%',
          Offset(rect.left + 6, rect.top + (rect.height - 12) / 2),
          color: TF.textPrimary,
          size: 9,
          weight: FontWeight.w600,
        );
      }
    }

    // Today marker.
    final tx = _days(start, today) * dayWidth + dayWidth / 2;
    if (tx >= 0 && tx <= size.width) {
      final p = Paint()
        ..color = TF.brand
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(tx, headerHeight), Offset(tx, size.height), p);
      canvas.drawCircle(
          Offset(tx, headerHeight), 3.5, Paint()..color = TF.brand);
      final tp = TextPainter(
        text: TextSpan(
            text: 'TODAY',
            style: TFText.mono(
                size: 8.5, color: TF.onBrand, weight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      final label = Rect.fromLTWH(tx - tp.width / 2 - 4, headerHeight - 30,
          tp.width + 8, tp.height + 2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(label, const Radius.circular(TF.radiusSm)),
          Paint()..color = TF.brand);
      tp.paint(canvas, Offset(label.left + 4, label.top + 1));
    }
  }

  @override
  bool shouldRepaint(covariant _GanttPainter old) =>
      old.progress != progress ||
      old.dayWidth != dayWidth ||
      old.items != items ||
      old.start != start;
}
