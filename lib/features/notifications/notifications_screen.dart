import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart' show AppNotification;
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/widgets.dart';

enum _InboxFilter { all, unread }

/// Inbox (web `NotificationBell` dropdown, expanded to a full screen):
/// unread/all filter, "Mark all read", Today/Earlier grouping, cursor-based
/// infinite scroll, swipe-to-read and pull-to-refresh.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final List<AppNotification> _items = [];

  /// Items marked read during this visit. In the "Unread" filter they stay
  /// visible (dimmed) until the filter changes or the list refreshes, so the
  /// read transition can animate instead of the row vanishing.
  final Set<String> _readThisSession = {};

  String? _next;
  bool _loading = true;
  bool _loadingMore = false;
  bool _markingAll = false;
  Object? _error;
  Object? _moreError;
  _InboxFilter _filter = _InboxFilter.all;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _load() async {
    setState(() {
      if (_items.isEmpty) _loading = true;
      _error = null;
      _moreError = null;
    });
    await _fetch();
  }

  /// Fetches the first page. Does not call setState before the first await,
  /// so it is safe to run from initState.
  Future<void> _fetch() async {
    try {
      final page = await ref.read(repositoryProvider).notifications();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _next = page.next;
        _readThisSession.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(unreadCountProvider);
    await _load();
  }

  Future<void> _loadMore() async {
    final cursor = _next;
    if (cursor == null || _loadingMore || _moreError != null) return;
    setState(() => _loadingMore = true);
    try {
      final page =
          await ref.read(repositoryProvider).notifications(cursorUrl: cursor);
      if (!mounted) return;
      setState(() {
        final known = _items.map((n) => n.id).toSet();
        _items.addAll(page.items.where((n) => !known.contains(n.id)));
        _next = page.next;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _moreError = e;
        _loadingMore = false;
      });
    }
  }

  void _replace(String id, AppNotification Function(AppNotification) f) {
    final i = _items.indexWhere((n) => n.id == id);
    if (i != -1) _items[i] = f(_items[i]);
  }

  Future<void> _markRead(AppNotification n) async {
    if (n.isRead) return;
    HapticFeedback.lightImpact();
    setState(() {
      _replace(n.id, (x) => x.markRead());
      _readThisSession.add(n.id);
    });
    try {
      await ref.read(repositoryProvider).markNotificationRead(n.id);
      ref.invalidate(unreadCountProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _replace(n.id, (_) => n);
        _readThisSession.remove(n.id);
      });
      showErrorToast(context, e);
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    final snapshot = List<AppNotification>.of(_items);
    HapticFeedback.mediumImpact();
    setState(() {
      _markingAll = true;
      for (var i = 0; i < _items.length; i++) {
        if (!_items[i].isRead) {
          _readThisSession.add(_items[i].id);
          _items[i] = _items[i].markRead();
        }
      }
    });
    try {
      await ref.read(repositoryProvider).markAllNotificationsRead();
      ref.invalidate(unreadCountProvider);
      if (mounted) showToast(context, 'All notifications marked as read');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(snapshot);
      });
      showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _setFilter(_InboxFilter f) {
    if (f == _filter) return;
    HapticFeedback.selectionClick();
    setState(() {
      _filter = f;
      _readThisSession.clear();
      _moreError = null;
    });
  }

  List<AppNotification> get _visible => _filter == _InboxFilter.all
      ? _items
      : _items
          .where((n) => !n.isRead || _readThisSession.contains(n.id))
          .toList();

  bool get _hasUnread => _items.any((n) => !n.isRead);

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadCountProvider).valueOrNull;

    return Scaffold(
      backgroundColor: TF.bgBase,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              unread: unread,
              canMarkAll: _hasUnread || (unread ?? 0) > 0,
              markingAll: _markingAll,
              onMarkAll: _markAllRead,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: _Segmented(
                value: _filter,
                onChanged: _setFilter,
                unread: unread,
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final Widget child;
    if (_loading && _items.isEmpty) {
      child = const KeyedSubtree(
        key: ValueKey('loading'),
        child: SkeletonList(count: 7, itemHeight: 68),
      );
    } else if (_error != null && _items.isEmpty) {
      child = KeyedSubtree(
        key: const ValueKey('error'),
        child: _scrollableFill(ErrorState(error: _error!, onRetry: _load)),
      );
    } else {
      child = KeyedSubtree(
          key: ValueKey('list-${_filter.name}'), child: _buildList());
    }
    return AnimatedSwitcher(
        duration: TF.durSlow, switchInCurve: TF.ease, child: child);
  }

  /// Wraps a non-scrolling widget so pull-to-refresh still works.
  Widget _scrollableFill(Widget child) {
    return RefreshIndicator(
      color: TF.brand,
      backgroundColor: TF.bgElevated,
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, c) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: math.max(c.maxHeight, 320.0), child: child)
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final visible = _visible;

    if (visible.isEmpty && _next == null) {
      return _scrollableFill(EmptyState(
        icon: Icons.notifications_none_rounded,
        title: "You're all caught up",
        message: _filter == _InboxFilter.unread
            ? 'No unread notifications. Nice work.'
            : 'Assignments, mentions and updates will show up here.',
        action: _filter == _InboxFilter.unread && _items.isNotEmpty
            ? TFButton(
                label: 'Show all',
                variant: TFButtonVariant.secondary,
                size: TFButtonSize.sm,
                onPressed: () => _setFilter(_InboxFilter.all),
              )
            : null,
      ));
    }

    // Flatten into header + item rows.
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final today = <AppNotification>[];
    final earlier = <AppNotification>[];
    for (final n in visible) {
      final t = n.createdAt;
      if (t != null && !t.isBefore(startOfToday)) {
        today.add(n);
      } else {
        earlier.add(n);
      }
    }
    final rows = <Object>[
      if (today.isNotEmpty) ...['Today', ...today],
      if (earlier.isNotEmpty) ...['Earlier', ...earlier],
    ];

    final showFooter = _next != null || _moreError != null;

    return RefreshIndicator(
      color: TF.brand,
      backgroundColor: TF.bgElevated,
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 120),
        itemCount: rows.length + (showFooter ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= rows.length) return _buildFooter();
          final row = rows[i];
          final stagger = math.min(i, 10) * 35;
          if (row is String) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Eyebrow(row),
            )
                .animate(key: ValueKey('h-$row'))
                .fadeIn(duration: 300.ms, delay: stagger.ms);
          }
          final n = row as AppNotification;
          return _NotificationTile(
            key: ValueKey(n.id),
            notification: n,
            onTap: () => _markRead(n),
            onSwipe: () => _markRead(n),
          )
              .animate(key: ValueKey('a-${n.id}'))
              .fadeIn(duration: 320.ms, delay: stagger.ms, curve: TF.ease)
              .slideX(
                  begin: 0.04,
                  end: 0,
                  duration: 320.ms,
                  delay: stagger.ms,
                  curve: TF.ease);
        },
      ),
    );
  }

  Widget _buildFooter() {
    if (_moreError != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: TFButton(
            label: 'Load more',
            icon: Icons.refresh_rounded,
            variant: TFButtonVariant.secondary,
            size: TFButtonSize.sm,
            onPressed: () {
              setState(() => _moreError = null);
              _loadMore();
            },
          ),
        ),
      );
    }
    // Sentinel: when the footer is built (scrolled near), fetch the next page.
    if (!_loadingMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadMore();
      });
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.unread,
    required this.canMarkAll,
    required this.markingAll,
    required this.onMarkAll,
  });

  final int? unread;
  final bool canMarkAll;
  final bool markingAll;
  final VoidCallback onMarkAll;

  @override
  Widget build(BuildContext context) {
    final count = unread ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Notifications'),
                const SizedBox(height: 4),
                Row(children: [
                  Text('Inbox', style: TFText.h1()),
                  const SizedBox(width: 10),
                  AnimatedSwitcher(
                    duration: TF.dur,
                    transitionBuilder: (c, a) =>
                        ScaleTransition(scale: a, child: c),
                    child: count > 0
                        ? TFBadge(
                            key: ValueKey(count),
                            '${count > 99 ? '99+' : count} new',
                            color: TF.brand,
                            dot: true,
                          )
                        : const SizedBox.shrink(key: ValueKey('none')),
                  ),
                ]),
              ],
            ),
          ),
          TFButton(
            label: 'Mark all read',
            icon: Icons.done_all_rounded,
            size: TFButtonSize.sm,
            variant: TFButtonVariant.ghost,
            loading: markingAll,
            onPressed: canMarkAll ? onMarkAll : null,
          ),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented(
      {required this.value, required this.onChanged, required this.unread});

  final _InboxFilter value;
  final ValueChanged<_InboxFilter> onChanged;
  final int? unread;

  @override
  Widget build(BuildContext context) {
    final count = unread ?? 0;
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: TF.bgSurface,
        borderRadius: BorderRadius.circular(TF.radiusMd),
        border: Border.all(color: TF.borderDefault),
      ),
      child: Stack(children: [
        AnimatedAlign(
          duration: TF.dur,
          curve: TF.ease,
          alignment: value == _InboxFilter.all
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            heightFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                color: TF.bgElevated,
                borderRadius: BorderRadius.circular(TF.radiusSm),
                border: Border.all(color: TF.borderBrand),
              ),
            ),
          ),
        ),
        Row(children: [
          _segment('All', _InboxFilter.all, null),
          _segment('Unread', _InboxFilter.unread, count > 0 ? count : null),
        ]),
      ]),
    );
  }

  Widget _segment(String label, _InboxFilter f, int? badge) {
    final selected = value == f;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(f),
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedDefaultTextStyle(
              duration: TF.dur,
              style: TFText.mono(
                size: 12,
                weight: FontWeight.w600,
                letterSpacing: 1.2,
                color: selected ? TF.textPrimary : TF.textMuted,
              ),
              child: Text(label.toUpperCase()),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? TF.brand : TF.brandLight,
                  borderRadius: BorderRadius.circular(TF.radiusSm),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: TFText.mono(
                    size: 10,
                    weight: FontWeight.w700,
                    color: selected ? TF.onBrand : TF.brand,
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
    required this.onSwipe,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onSwipe;

  static IconData iconFor(AppNotification n) {
    final verb = n.verb.toLowerCase();
    final target = (n.targetType ?? '').toLowerCase();
    if (verb == 'welcome') return Icons.celebration_outlined;
    if (verb.contains('assign')) return Icons.assignment_ind_outlined;
    if (verb.contains('mention')) return Icons.alternate_email_rounded;
    if (verb.contains('comment') || target == 'comment') {
      return Icons.chat_bubble_outline_rounded;
    }
    if (verb.contains('due') ||
        verb.contains('overdue') ||
        verb.contains('remind')) {
      return Icons.schedule_rounded;
    }
    if (verb.contains('status') || verb.contains('moved')) {
      return Icons.swap_horiz_rounded;
    }
    if (verb.contains('invite') ||
        verb.contains('member') ||
        verb.contains('join')) {
      return Icons.group_add_outlined;
    }
    if (verb.contains('export') || verb.contains('report')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (verb.contains('attach') || target == 'attachment') {
      return Icons.attach_file_rounded;
    }
    if (verb.contains('billing') ||
        verb.contains('plan') ||
        verb.contains('subscription')) {
      return Icons.credit_card_rounded;
    }
    return switch (target) {
      'task' => Icons.task_alt_rounded,
      'project' => Icons.folder_outlined,
      'organization' || 'membership' => Icons.apartment_rounded,
      _ => Icons.notifications_none_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = !n.isRead;
    final verbLabel = Fmt.title(n.verb);
    final description =
        n.description.trim().isEmpty ? verbLabel : n.description;

    final tile = Pressable(
      onTap: unread ? onTap : null,
      scale: 0.985,
      child: AnimatedContainer(
        duration: TF.durSlow,
        curve: TF.ease,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: unread ? TF.bgSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(TF.radiusLg),
          border:
              Border.all(color: unread ? TF.borderDefault : TF.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Amber left accent for unread.
              AnimatedContainer(
                duration: TF.durSlow,
                curve: TF.ease,
                width: unread ? 3 : 0,
                decoration: const BoxDecoration(gradient: TF.brandGradient),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: TF.durSlow,
                        curve: TF.ease,
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: unread ? TF.brandLight : TF.bgElevated,
                          borderRadius: BorderRadius.circular(TF.radiusMd),
                          border: Border.all(
                              color: unread ? TF.borderBrand : TF.borderSubtle),
                        ),
                        child: Icon(iconFor(n),
                            size: 17, color: unread ? TF.brand : TF.textMuted),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedDefaultTextStyle(
                              duration: TF.durSlow,
                              curve: TF.ease,
                              style: TFText.sans(
                                size: 14,
                                height: 1.4,
                                weight:
                                    unread ? FontWeight.w500 : FontWeight.w400,
                                color: unread ? TF.textPrimary : TF.textMuted,
                              ),
                              child: Text(description,
                                  maxLines: 3, overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(height: 6),
                            Row(children: [
                              if (n.actorName != null) ...[
                                Flexible(
                                  child: Text(
                                    n.actorName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TFText.sans(
                                      size: 12,
                                      weight: FontWeight.w500,
                                      color: TF.textSecondary,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text('·', style: TFText.small()),
                                ),
                              ],
                              Text(Fmt.relative(n.createdAt),
                                  style: TFText.mono(size: 11)),
                              const Spacer(),
                              if (n.verb.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    verbLabel.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TFText.mono(
                                        size: 9.5,
                                        letterSpacing: 1,
                                        color: TF.textDisabled),
                                  ),
                                ),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Unread dot.
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: AnimatedScale(
                          duration: TF.durSlow,
                          curve: unread ? TF.easeBounce : TF.ease,
                          scale: unread ? 1 : 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: TF.brand,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: Color(0x66F5A623), blurRadius: 6)
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('dismiss-${n.id}'),
      direction: unread ? DismissDirection.horizontal : DismissDirection.none,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.3,
        DismissDirection.endToStart: 0.3,
      },
      confirmDismiss: (_) async {
        onSwipe();
        return false; // keep the row; it animates into the read state instead
      },
      background: const _SwipeBackground(alignment: Alignment.centerLeft),
      secondaryBackground:
          const _SwipeBackground(alignment: Alignment.centerRight),
      child: tile,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({required this.alignment});
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final left = alignment == Alignment.centerLeft;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignment,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: left ? Alignment.centerLeft : Alignment.centerRight,
          end: left ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            TF.brand.withValues(alpha: 0.28),
            TF.brand.withValues(alpha: 0.04)
          ],
        ),
        borderRadius: BorderRadius.circular(TF.radiusLg),
        border: Border.all(color: TF.borderBrand),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.done_rounded, size: 18, color: TF.brand),
          const SizedBox(width: 8),
          Text('MARK READ',
              style: TFText.mono(
                  size: 11,
                  weight: FontWeight.w700,
                  color: TF.brand,
                  letterSpacing: 1.4)),
        ],
      ),
    );
  }
}
